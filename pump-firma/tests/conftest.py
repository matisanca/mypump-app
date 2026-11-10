"""Pruebas de pump-firma. Nada toca la base real ni manda correo real: Postgres 17 embebido (PGlite), SMTP falso,
bot falso y carpeta temporal. Las plantillas son sintéticas (tests/plantillas): el texto real no vive en el repo.

Hace falta una carpeta con `npm i @electric-sql/pglite @electric-sql/pglite-socket` (variable PUMP_FIRMA_DEV) o una
base de pruebas ya levantada (FIRMA_PRUEBA_DB_URL)."""
import base64
import io
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer

import psycopg
import pytest

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
sys.path.insert(0, RAIZ)
sys.path.insert(0, os.path.join(RAIZ, "tools"))

from firma import sello  # noqa: E402
from firma.almacen import Almacen  # noqa: E402
from firma.base import Base  # noqa: E402
from firma.config import Config  # noqa: E402
from firma.correo import Correo  # noqa: E402
from firma.servicio import Servicio  # noqa: E402

SQL = os.path.join(os.path.dirname(RAIZ), "supabase", "propuestas", "nativa_contrato_firma.sql")
SECRETO = "s" * 40
SECRETO_INTERNO = "i" * 40


def _puerto_libre():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture(scope="session")
def db_url():
    if os.environ.get("FIRMA_PRUEBA_DB_URL"):
        yield os.environ["FIRMA_PRUEBA_DB_URL"]
        return
    dev = os.path.expanduser(os.environ.get("PUMP_FIRMA_DEV", "~/Developer/nativa-evidencia/contrato/dev"))
    if not os.path.isdir(os.path.join(dev, "node_modules", "@electric-sql")):
        pytest.skip("sin PGlite: definir PUMP_FIRMA_DEV o FIRMA_PRUEBA_DB_URL")
    shutil.copy(os.path.join(AQUI, "pg_prueba.mjs"), os.path.join(dev, "pg_prueba.mjs"))
    puerto = _puerto_libre()
    log = open(os.path.join(dev, f"pg-{puerto}.log"), "w+")
    p = subprocess.Popen(["node", "pg_prueba.mjs", str(puerto), SQL], cwd=dev, stdout=log, stderr=subprocess.STDOUT)
    try:
        for _ in range(240):
            log.seek(0)
            salida = log.read()
            if "LISTO" in salida:
                break
            if p.poll() is not None:
                raise RuntimeError("la base de pruebas no arrancó:\n" + salida[-2000:])
            time.sleep(0.5)
        else:
            raise RuntimeError("la base de pruebas tardó demasiado")
        yield f"postgresql://postgres@127.0.0.1:{puerto}/postgres"
    finally:
        p.terminate()
        log.close()
        try:
            pass  # el log queda para diagnosticar
        except OSError:
            pass


@pytest.fixture(scope="session")
def admin(db_url):
    """Consultas como dueño de la base (lo que en producción solo hace una migración)."""
    def correr(sql, args=None, uno=False):
        with Base(db_url, intentos=6)._conectar() as c, c.cursor() as cur:
            c.autocommit = True
            cur.execute(sql, args)
            if cur.description is None:
                return None
            filas = cur.fetchall()
            return (filas[0] if filas else None) if uno else filas
    return correr


@pytest.fixture(scope="session", autouse=True)
def plantillas(db_url):
    import cargar_plantillas
    with psycopg.connect(db_url, autocommit=False, prepare_threshold=None) as c:
        for tipo in ("servicio_ar", "servicio_ext", "consentimiento_ar"):
            md = open(os.path.join(AQUI, "plantillas", tipo + ".md"), encoding="utf-8").read()
            cargar_plantillas.cargar(c, tipo, "prueba1", md)
        c.commit()


class _Buzon:
    def __init__(self):
        self.mensajes = []
        self.rechazar = False

    async def handle_DATA(self, server, session, envelope):
        if self.rechazar:
            return "451 intentar luego"
        from email import message_from_bytes, policy
        self.mensajes.append({"de": envelope.mail_from, "para": list(envelope.rcpt_tos),
                              "m": message_from_bytes(envelope.content, policy=policy.default)})
        return "250 OK"

    def para(self, mail, asunto=None):
        return [x for x in self.mensajes if mail in x["para"] and (asunto is None or asunto in x["m"]["Subject"])]

    def codigo(self, mail):
        cuerpo = self.para(mail)[-1]["m"].get_body(("plain",)).get_content()
        return re.search(r"\b(\d{6})\b", cuerpo).group(1)


@pytest.fixture(scope="session")
def smtp():
    from aiosmtpd.controller import Controller
    buzon = _Buzon()
    ctl = Controller(buzon, hostname="127.0.0.1", port=_puerto_libre())
    ctl.start()
    buzon.puerto = ctl.port
    yield buzon
    ctl.stop()


@pytest.fixture(scope="session")
def bot():
    recibidos = []

    class H(BaseHTTPRequestHandler):
        def do_POST(self):
            cuerpo = self.rfile.read(int(self.headers.get("content-length", 0)))
            recibidos.append({"cabeceras": dict(self.headers), "cuerpo": json.loads(cuerpo)})
            estado = 500 if getattr(recibidos, "fallar", False) else 200
            self.send_response(estado)
            self.end_headers()
            self.wfile.write(b"{}")

        def log_message(self, *a):
            pass

    class Lista(list):
        fallar = False
    recibidos = Lista()
    srv = HTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    recibidos.url = f"http://127.0.0.1:{srv.server_port}/webhook"
    yield recibidos
    srv.shutdown()


@pytest.fixture()
def sellos_falsos(monkeypatch):
    hechos = []

    def sellar(sha, tsa, openssl, ca_file, timeout=10.0):
        if getattr(sellar, "fallar", False):
            raise sello.SelloError("sin red")
        hechos.append((sha, tsa))
        return b"TSR-DE-PRUEBA-" + sha.encode(), datetime.now(timezone.utc)
    monkeypatch.setattr(sello, "sellar", sellar)
    sellar.hechos = hechos
    return sellar


@pytest.fixture()
def cfg(db_url, smtp, bot, tmp_path):
    (tmp_path / "privado").mkdir()
    return Config({"FIRMA_DB_URL": db_url, "FIRMA_SECRETO": SECRETO, "FIRMA_SECRETO_INTERNO": SECRETO_INTERNO,
                   "FIRMA_URL_PUBLICA": "https://firma.prueba.test", "FIRMA_DATOS": str(tmp_path),
                   "FIRMA_SMTP_HOST": "127.0.0.1", "FIRMA_SMTP_PUERTO": str(smtp.puerto), "FIRMA_SMTP_SEGURO": "plano",
                   "FIRMA_REMITENTE": "Prueba <firma@prueba.test>", "FIRMA_CUSTODIA_EMAIL": "custodia@ajena.test",
                   "FIRMA_CCO_COPIA": "archivo@prueba.test", "FIRMA_BOT_URL": bot.url, "FIRMA_BOT_SECRETO": "secreto-del-bot",
                   "FIRMA_TSAS": "digicert,globalsign"})


@pytest.fixture()
def srv(cfg, sellos_falsos, smtp, bot):
    smtp.rechazar = False
    bot.fallar = False
    return Servicio(cfg, Base(cfg.db_url), Almacen(cfg.datos), Correo(cfg.smtp_host, cfg.smtp_puerto, "", "", cfg.remitente, cfg.smtp_seguro))


_n = [0]


@pytest.fixture()
def alta():
    """Fábrica de altas distintas (personas inventadas)."""
    def hacer(residente=True, **cambios):
        _n[0] += 1
        n = f"{int(time.time() * 1000) % 10_000_000}{_n[0]}"
        a = {"alta_ref": f"prueba-{n}", "nombre": "Ana María", "apellido": "Pérez Ñandú", "email": f"ana{n}@correo.test",
             "whatsapp": f"+54 9 11 {n[-8:-4]}-{n[-4:]}" if residente else f"+34 6{n[-8:]}", "dni": "30.111.222" if residente else "X1234567T",
             "domicilio": "Calle Falsa 123, Ciudad", "pais": "Argentina" if residente else "España",
             "residente_argentina": residente, "plan": "Plan de prueba 3 meses", "objetivo": "Objetivo de prueba",
             "precio": "USD 100 en un pago"}
        a.update(cambios)
        return a
    return hacer


def dibujo(vacio=False) -> str:
    from PIL import Image, ImageDraw
    img = Image.new("RGBA", (600, 200), (255, 255, 255, 0))
    if not vacio:
        d = ImageDraw.Draw(img)
        d.line([(30, 150), (120, 40), (200, 160), (300, 60), (420, 150), (560, 80)], fill=(20, 20, 60, 255), width=5)
    b = io.BytesIO()
    img.save(b, format="PNG")
    datos = b.getvalue()
    if vacio and len(datos) < 600:  # que pase el control de tamaño y caiga en el de lienzo vacío
        img = Image.effect_noise((600, 200), 4).convert("RGBA")
        b = io.BytesIO()
        img.save(b, format="PNG")
        datos = b.getvalue()
    return "data:image/png;base64," + base64.b64encode(datos).decode()


def token_de_url(url: str) -> str:
    return url.rsplit("/f/", 1)[1]


CASILLAS_OK = {"electronico": True, "lei_acepto": True, "datos_salud": True}


@pytest.fixture()
def firmar_todo(srv, smtp):
    """Crea el alta y firma el documento del tipo pedido. Devuelve (doc resumen, token, respuesta de firmar)."""
    def hacer(a, tipo, **cuerpo_extra):
        r = srv.crear(a, "10.0.0.1", "prueba/1.0")
        assert r["ok"], r
        d = next(x for x in r["documentos"] if x["tipo"] == tipo)
        t = token_de_url(d["url"])
        srv.ver(t, "10.0.0.2", "Navegador de prueba")
        srv.pedir_codigo(t, "firma", "10.0.0.2", "Navegador de prueba")
        cuerpo = {"casillas": dict(CASILLAS_OK), "nombre": f"{a['nombre']} {a['apellido']}", "documento": a["dni"],
                  "domicilio": "", "firma_png": dibujo(), "codigo": smtp.codigo(a["email"])}
        cuerpo.update(cuerpo_extra)
        return d, t, srv.firmar(t, cuerpo, "10.0.0.2", "Navegador de prueba")
    return hacer
