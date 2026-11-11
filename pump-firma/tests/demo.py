#!/usr/bin/env python3
"""Demo local para mirar la página de firma con datos inventados. No toca producción ni manda correo real.
Uso:  python tests/demo.py <url de la base de pruebas> [puerto]
Levanta un SMTP falso (los códigos se imprimen acá), carga las plantillas (las de tests/plantillas, o las reales si
se pasa PUMP_FIRMA_FUENTES=/carpeta/privada) y deja el servicio en http://127.0.0.1:<puerto>."""
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))

import psycopg  # noqa: E402
import uvicorn  # noqa: E402
from aiosmtpd.controller import Controller  # noqa: E402

import cargar_plantillas  # noqa: E402
from firma import sello  # noqa: E402
from firma.almacen import Almacen  # noqa: E402
from firma.app import crear_app  # noqa: E402
from firma.base import Base  # noqa: E402
from firma.config import Config  # noqa: E402
from firma.correo import Correo  # noqa: E402
from firma.servicio import Servicio  # noqa: E402

AQUI = os.path.dirname(os.path.abspath(__file__))


class Buzon:
    async def handle_DATA(self, server, session, envelope):
        from email import message_from_bytes, policy
        m = message_from_bytes(envelope.content, policy=policy.default)
        cuerpo = m.get_body(("plain",)).get_content()
        cod = re.search(r"\b(\d{6})\b", cuerpo)
        print(f"[correo] para {envelope.rcpt_tos} · {m['Subject']}" + (f" · CÓDIGO {cod.group(1)}" if cod and "ódigo" in m["Subject"] else ""), flush=True)
        open(os.path.join(DATOS, "ultimo_correo.txt"), "w").write(f"{m['Subject']}\n\n{cuerpo}")
        return "250 OK"


db, puerto = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 8799
DATOS = tempfile.mkdtemp(prefix="pump-firma-demo-")
os.makedirs(os.path.join(DATOS, "privado"))
fuentes = os.environ.get("PUMP_FIRMA_FUENTES")
archivos = ({"servicio_ar": "A_v13.md", "servicio_ext": "E_v8.md", "consentimiento_ar": "B_consentimiento_medico.md"} if fuentes
            else {t: t + ".md" for t in cargar_plantillas.TIPOS})
with psycopg.connect(db, prepare_threshold=None) as c:
    for tipo, nombre in archivos.items():
        cargar_plantillas.cargar(c, tipo, "demo", open(os.path.join(fuentes or os.path.join(AQUI, "plantillas"), nombre), encoding="utf-8").read())
    c.commit()
if fuentes and os.path.exists(os.path.join(fuentes, "firma_prestador.png")):
    import shutil
    shutil.copy(os.path.join(fuentes, "firma_prestador.png"), os.path.join(DATOS, "privado", "firma_prestador.png"))
ctl = Controller(Buzon(), hostname="127.0.0.1", port=puerto + 1)
ctl.start()
sello.sellar = lambda sha, tsa, o, ca, timeout=10.0: (b"TSR-DEMO", __import__("datetime").datetime.now(__import__("datetime").timezone.utc))
cfg = Config({"FIRMA_DB_URL": db, "FIRMA_SECRETO": "d" * 40, "FIRMA_SECRETO_INTERNO": "e" * 40, "FIRMA_URL_PUBLICA": f"http://127.0.0.1:{puerto}",
              "FIRMA_DATOS": DATOS, "FIRMA_SMTP_HOST": "127.0.0.1", "FIRMA_SMTP_PUERTO": str(puerto + 1), "FIRMA_SMTP_SEGURO": "plano",
              "FIRMA_REMITENTE": "Demo <demo@prueba.test>", "FIRMA_CUSTODIA_EMAIL": "custodia@ajena.test"})
srv = Servicio(cfg, Base(db), Almacen(DATOS), Correo("127.0.0.1", puerto + 1, "", "", cfg.remitente, "plano"))
n = os.getpid()
for residente, pais, wa in ((True, "Argentina", "+54 9 11 5555 0101"), (False, "España", "+34 600 000 101"), (False, "México", "+52 55 0000 0101")):
    r = srv.crear({"alta_ref": f"demo-{n}-{pais}", "nombre": "Persona", "apellido": "De Prueba", "email": f"demo{n}@correo.test", "whatsapp": wa,
                   "dni": "30111222" if residente else "X1234567T", "domicilio": "Calle Falsa 123, Ciudad" if residente else "",
                   "pais": pais, "residente_argentina": residente, "plan": "Plan de prueba 3 meses", "objetivo": "Objetivo de prueba",
                   "precio": "USD 100 en un pago"}, "127.0.0.1", "demo")
    for d in r["documentos"]:
        print(f"[demo] {pais} · {d['tipo']} · {d['url']}", flush=True)
uvicorn.run(crear_app(cfg, srv, despacho_en_linea=True), host="127.0.0.1", port=puerto, log_level="warning")
