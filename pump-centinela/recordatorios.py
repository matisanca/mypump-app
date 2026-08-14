#!/usr/bin/env python3
"""recordatorios.py — la ronda del domingo y los reintentos, sin Mati en el medio

QUE RESUELVE
Cada domingo Mati le escribe UNO POR UNO por WhatsApp a 62 clientes pidiendo la
revision. `centinela.py --pedido` redacta el texto pero se lo manda A EL, con la
cabecera literal `_Mandaselo a la lista de difusion:_`. Copiar y pegar 62 veces
le abre ~60 conversaciones que arrancan el domingo y terminan el jueves.

Ahora el mensaje va directo al chat de la app (mig 057) y el push suena solo
(mig 058). Mati no toca nada.

POR QUE ES UN ARCHIVO APARTE Y NO UN FLAG DE centinela.py
`centinela.py` tiene un guardarrail de UNA CORRIDA POR DIA guardado en su state.
Un `--recordatorios` el martes, despues de que el analisis ya corrio, seria un
no-op silencioso: no falla, no avisa, simplemente no hace nada. Ese es el peor
modo de fallar que hay, porque se descubre semanas despues.

LOS TRES MODOS
  --programar     Domingo 18:00. Reparte los 62 mensajes en 40-60 min.
  --recordar      Martes y jueves 20:00. Solo a quien todavia falta.
  --drenar        Cada 5 min. Publica lo que ya vencio.
  (sin flag)      Dry-run: muestra que haria y no escribe nada.

POR QUE ESCALONADO
Un humano no manda 62 mensajes en el mismo segundo. Si llegan todos a las
18:00:00, la ilusion se cae en la primera captura que dos clientes comparen. Y
de paso aplana el pico de respuestas.

LOS REINTENTOS CORTAN SOLOS
No hay flags de "ya se le aviso". Se consulta `mypump_chat_faltantes_semana()`,
que recalcula del lado servidor lo mismo que la app muestra: si subio, no
aparece, y no se le manda nada. Un flag habria que acordarse de apagarlo, y el
dia que se desincronice el cliente recibe un recordatorio de algo que ya hizo.
"""
import json
import os
import pathlib
import random
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import plantillas as PL

BASE = pathlib.Path(__file__).resolve().parent
BOT_ENV = os.path.expanduser("~/agentkit-coach/.env")
PUSH_ENV = str(BASE / ".env")


def load_env(p):
    e = {}
    try:
        for line in open(p):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                e[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return e


E = load_env(BOT_ENV)
E.update(load_env(PUSH_ENV))
_g = lambda k, d="": os.environ.get(k) or E.get(k) or d

SB_URL = _g("SUPABASE_URL", "https://gydinputrtptqakdzyvc.supabase.co").rstrip("/")
SB_KEY = _g("SUPABASE_SERVICE_KEY") or _g("SUPABASE_KEY")

MODO = ("programar" if "--programar" in sys.argv else
        "recordar" if "--recordar" in sys.argv else
        "drenar" if "--drenar" in sys.argv else "dry")

# Ventana del escalonado, en minutos. 40-60 es lo que tarda una persona en
# mandar 62 mensajes sin apuro.
VENTANA_MIN = 40
VENTANA_MAX = 60

# Tope duro de mensajes del coach por semana y por cliente. Sin esto, quien
# nunca sube nada recibiria domingo + martes + jueves TODAS las semanas, y eso
# no es seguimiento: es hostigamiento, y termina en app desinstalada.
TOPE_SEMANA = 3

# Todo lo que se AGENDA va en UTC (es lo que entiende la base), pero todo lo que
# se MUESTRA va en hora de Buenos Aires. Imprimir el UTC crudo hacia que el
# dry-run de las 23:59 dijera "02:59", y eso se lee como que algo esta roto.
TZ = ZoneInfo("America/Argentina/Buenos_Aires")


def _log(*a):
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}]", *a, flush=True)


def _sb(fn, payload):
    req = urllib.request.Request(
        f"{SB_URL}/rest/v1/rpc/{fn}",
        data=json.dumps(payload).encode(),
        headers={"apikey": SB_KEY, "Authorization": f"Bearer {SB_KEY}",
                 "Content-Type": "application/json"},
        method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        cuerpo = r.read().decode()
    return json.loads(cuerpo) if cuerpo.strip() else None


def apodo(nombre):
    """Primer nombre en minuscula. Es como escribe Mati: 'gerardo', no 'Gerardo'."""
    n = (nombre or "").strip()
    return n.split()[0].lower() if n else "che"


def faltantes():
    """Quien no completo su revision esta semana, ya filtrado por la base.

    Devuelve solo a quien SE LE PUEDE escribir: quedan afuera los escalados
    (esos los atiende Mati), los silenciados, y los que ya llegaron al tope.
    """
    filas = _sb("mypump_chat_faltantes_semana", {}) or []
    listos = []
    for f in filas:
        if f["escalado"] or f["silenciado"]:
            continue
        if f["avisos_semana"] >= TOPE_SEMANA:
            continue
        listos.append(f)
    return filas, listos


def _horario(base, i, total):
    """Reparte el mensaje i-esimo dentro de la ventana, con ruido.

    El ruido importa: sin el, los intervalos son exactos y 62 mensajes cada
    47 segundos clavados es tan poco humano como mandarlos todos juntos.
    """
    if total <= 1:
        return base
    ancho = random.uniform(VENTANA_MIN, VENTANA_MAX)
    paso = ancho / total
    jitter = random.uniform(-paso * 0.4, paso * 0.4)
    return base + timedelta(minutes=max(0.0, i * paso + jitter))


def programar_ronda(recordatorio=False):
    todos, listos = faltantes()
    if not listos:
        _log("no hay a quien escribirle" + (f" ({len(todos)} clientes revisados)" if todos else ""))
        return 0

    sem = datetime.now().isocalendar()[1]
    prefijo = "rec" if recordatorio else "dom"
    dia = datetime.now().strftime("%a").lower()
    base = datetime.now(timezone.utc)

    random.shuffle(listos)      # el orden tampoco puede ser siempre el mismo
    puestos = saltados = 0

    for i, f in enumerate(listos):
        # A quien ya mando el check pero le faltan las fotos NO se le pide la
        # revision entera: se le pide lo que falta. Pedirle algo que ya hizo es
        # la forma mas rapida de que deje de leer los mensajes.
        if not f["falta_check"] and f["fotos_puestas"] < 3:
            banco, tag = PL.SOLO_FOTOS, "fotos"
        elif recordatorio:
            banco, tag = PL.RECORDATORIO, "rec"
        else:
            banco, tag = PL.DOMINGO, "dom"

        texto = PL.elegir(banco, f["nombre"] or f["cliente_id"], apodo, sufijo=tag)
        cuando = _horario(base, i, len(listos))
        dedupe = f"{prefijo}-{f['cliente_id']}-{sem}-{dia}"

        if MODO == "dry":
            _log(f"  {cuando.astimezone(TZ):%H:%M}  {(f['nombre'] or f['cliente_id'])[:22]:<22} [{tag}] {texto[:66]}")
            puestos += 1
            continue

        r = _sb("mypump_chat_programar", {
            "p_cliente_id": f["cliente_id"],
            "p_contenido": texto,
            "p_cuando": cuando.isoformat(),
            "p_dedupe": dedupe,
        })
        if r:
            puestos += 1
        else:
            saltados += 1   # ya estaba programado: re-correr no duplica

    extra = f", {saltados} ya estaban" if saltados else ""
    afuera = len(todos) - len(listos)
    _log(f"{puestos} mensajes {'programados' if MODO != 'dry' else '(dry-run)'}{extra}"
         f"{f'; {afuera} quedaron afuera (escalados, silenciados o en el tope)' if afuera else ''}")
    return puestos


def drenar():
    """Publica lo que ya vencio. La ventana horaria la aplica la base."""
    if MODO == "dry":
        _log("dry-run: no se drena nada")
        return 0
    filas = _sb("mypump_chat_drenar", {"p_limite": 25}) or []
    pub = sum(1 for f in filas if f.get("publicado"))
    can = len(filas) - pub
    if filas:
        _log(f"drenados: {pub} publicados" + (f", {can} cancelados" if can else ""))
    return pub


def main():
    if not SB_KEY:
        _log("falta SUPABASE_SERVICE_KEY")
        return 1

    try:
        if MODO in ("programar", "dry"):
            _log("ronda del domingo" + ("  [DRY-RUN]" if MODO == "dry" else ""))
            programar_ronda(recordatorio=False)
            if MODO == "dry":
                _log("(dry-run: no se escribio nada; usa --programar)")
        elif MODO == "recordar":
            _log("recordatorio a quien todavia falta")
            programar_ronda(recordatorio=True)
        elif MODO == "drenar":
            drenar()
    except urllib.error.HTTPError as e:
        _log(f"error HTTP {e.code}: {e.read().decode()[:200]}")
        return 1
    except Exception as e:  # noqa: BLE001
        _log(f"{type(e).__name__}: {e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
