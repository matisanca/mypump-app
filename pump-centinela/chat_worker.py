#!/usr/bin/env python3
"""chat_worker.py — la IA contesta el chat. En sombra: escribe, no publica.

COMO ESTA ARMADO, Y LA SIMPLIFICACION QUE LO ORDENA TODO
La app NUNCA le habla a esta maquina. El cliente escribe -> Supabase. Este
worker pollea Supabase cada minuto, corre Codex, y deja el resultado como
BORRADOR. Eso elimina de un plumazo: el corte de ~100s del edge de Cloudflare,
el patron 202+polling, un hostname nuevo en el tunel, CORS con
capacitor://localhost, rate limit por token, y el telefono esperando a un
proceso `codex`.

No hace falta nada de eso porque la respuesta TARDA MINUTOS A PROPOSITO.

MODO SOMBRA
Genera, valida y guarda un borrador. NO publica. Mati lo manda con un click
desde la bandeja del Cerebro, o lo edita, o lo descarta. Asi se calibra el tono
con un click en vez de escribir de cero, y de paso queda medida la tasa de
clasificacion antes de que la IA hable sola.

DEGRADA A ESCALAR, NUNCA A SILENCIO
Si Codex se cae, si la sesion vencio, si el JSON viene roto, si el validador
bloquea: se guarda un borrador de clase 'derivar' y la conversacion queda
ESCALADA. El peor resultado posible es que Mati tenga que contestar a mano —
que es exactamente lo que hace hoy. Lo que no puede pasar es que un mensaje
quede sin que nadie lo mire.

USO
  python3 chat_worker.py            # dry-run: muestra que haria
  python3 chat_worker.py --correr   # genera y guarda borradores
"""
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

import validador_chat as VAL

BASE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(BASE))


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


E = load_env(os.path.expanduser("~/agentkit-coach/.env"))
E.update(load_env(str(BASE / ".env")))
_g = lambda k, d="": os.environ.get(k) or E.get(k) or d

SB_URL = _g("SUPABASE_URL", "https://gydinputrtptqakdzyvc.supabase.co").rstrip("/")
SB_KEY = _g("SUPABASE_SERVICE_KEY") or _g("SUPABASE_KEY")

# Ruta ABSOLUTA. El codex de nvm no existe bajo launchd, que corre con un PATH
# minimo: el worker moriria con "command not found" y nadie lo veria.
CODEX = os.path.expanduser(_g("CODEX_BIN", "~/.local/bin/codex"))
MODELO = _g("CODEX_MODELO", "gpt-5.6-sol")

CORRER = "--correr" in sys.argv

# Semaforo. Con ~20 mensajes/hora de pico y 20-30s por llamada, 3 sobra 20x. El
# cuello no es la CPU de esta Mac: es el rate limit de la cuenta.
CONCURRENCIA = 3
TIMEOUT_S = 90

# Cupo diario en libreta local, mismo patron que .push_entregados. Pasado el
# cupo NO se contesta: se escala. Quedarse sin cuota a mitad de la tarde y
# empezar a fallar en silencio seria peor que escalar de mas.
CUPO_DIARIO = 120
LIBRETA = BASE / ".chat_worker_cupo"


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


def cupo_usado():
    hoy = datetime.now().strftime("%Y-%m-%d")
    try:
        d = json.loads(LIBRETA.read_text())
        return d.get(hoy, 0)
    except Exception:
        return 0


def anotar_cupo(n=1):
    hoy = datetime.now().strftime("%Y-%m-%d")
    try:
        d = json.loads(LIBRETA.read_text())
    except Exception:
        d = {}
    d = {k: v for k, v in d.items() if k >= hoy}   # se poda sola
    d[hoy] = d.get(hoy, 0) + n
    try:
        LIBRETA.write_text(json.dumps(d))
    except Exception:
        pass


# ── El prompt ────────────────────────────────────────────────────────────
#
# Se antepone el TONO verbatim y se pasa apodo, ultimos ~10 mensajes y si ya
# subio el check. CERO datos de salud: el modelo no necesita saber el HRV de
# nadie para contestar "dale, gracias".
TONO = """Escribis como Mati, entrenador argentino, por chat con un cliente suyo.
Tuteo rioplatense: "vos", "subi", "contame". Nunca "tu" ni "usted".
Sin signos de apertura: escribis "como venis", no "¿Cómo venís?".
Sin punto final. Como maximo UN emoji, y al final. Minusculas al arrancar.
Corto: una o dos oraciones. Si no entra en dos renglones de un telefono, sobra."""

REGLA_DURA = """REGLA QUE NO SE NEGOCIA:
NUNCA das indicaciones de entrenamiento, nutricion, suplementacion ni salud.
NI SIQUIERA genericas. Nada de "toma mas agua", "descansa mejor", "sumale
proteina", "baja el volumen". Nada de numeros, gramos, series, repeticiones,
calorias ni horas de sueno.
Cualquier pregunta, cambio, numero o sintoma -> clase "derivar".
Dolor de pecho, desmayo, lesion aguda o ideacion suicida -> clase "urgente".
Ante la duda, derivas. Escalar de mas cuesta un mensaje que Mati lee; escalar
de menos le manda una frase enlatada a alguien que necesitaba una persona."""

SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["clase", "respuesta", "motivo"],
    "properties": {
        "clase": {"type": "string", "enum": ["simple", "derivar", "urgente"]},
        "respuesta": {"type": "string"},
        "motivo": {"type": "string"},
    },
}


def armar_prompt(fila):
    apodo = (fila.get("nombre") or "").split()
    apodo = apodo[0].lower() if apodo else "che"
    hilo = fila.get("contexto") or []
    conversacion = "\n".join(
        f"{'CLIENTE' if m.get('autor') == 'cliente' else 'MATI'}: {m.get('texto','')}"
        for m in hilo[-10:])
    subio = "ya subio su revision de esta semana" if fila.get("ya_subio") else "todavia no subio su revision"

    return f"""{TONO}

{REGLA_DURA}

Le escribis a {apodo}, que {subio}.

Conversacion (lo ultimo es lo que hay que contestar):
{conversacion}

Devolves JSON con:
  clase: "simple" si alcanza con confirmar, agradecer o acusar recibo.
         "derivar" si pregunta algo, pide un cambio, da un numero o cuenta un
         sintoma. "urgente" si hay riesgo (dolor de pecho, desmayo, lesion
         aguda, ideacion suicida).
  respuesta: SOLO si clase es "simple". Una o dos oraciones, arrancando con
             "{apodo}". Si es "derivar", el texto tiene que decir que lo
             charlan por whatsapp, sin dar ninguna indicacion. Si es
             "urgente", dejala vacia: no se le contesta nada automatico.
  motivo: en una linea, por que elegiste esa clase."""


def llamar_codex(prompt):
    """Devuelve (dict, error). El prompt va por STDIN, nunca como argumento.

    Un mensaje de cliente puede tener comillas, saltos de linea y emojis; como
    argumento de shell eso es una fuente de bugs raros y de inyeccion.

    Se borra OPENAI_API_KEY del entorno del hijo A PROPOSITO: obliga a usar la
    sesion con suscripcion. Si quedara, cada respuesta se cobraria por API sin
    que nadie lo note hasta la factura.
    """
    env = dict(os.environ)
    for k in ("OPENAI_API_KEY", "OPENAI_BASE_URL", "OPENAI_ORG_ID"):
        env.pop(k, None)

    cmd = [CODEX, "exec", "-m", MODELO, "--json", "-s", "read-only",
           "--skip-git-repo-check",
           # Sin esto, cada llamada arrastra los servidores MCP de la mini y
           # escupe errores de transporte cuando alguno esta caido. Verificado:
           # ensucia la salida y suma latencia sin aportar nada acá.
           "-c", "mcp_servers={}"]
    try:
        p = subprocess.run(cmd, input=prompt, capture_output=True, text=True,
                           timeout=TIMEOUT_S, env=env, cwd="/tmp")
    except subprocess.TimeoutExpired:
        return None, f"codex no contesto en {TIMEOUT_S}s"
    except FileNotFoundError:
        return None, f"no existe {CODEX}"

    if p.returncode != 0:
        return None, f"codex salio con {p.returncode}: {(p.stderr or '')[:160]}"

    # La salida es JSONL. Interesa el ultimo agent_message.
    texto = None
    for linea in (p.stdout or "").splitlines():
        try:
            ev = json.loads(linea)
        except Exception:
            continue
        it = ev.get("item") or {}
        if ev.get("type") == "item.completed" and it.get("type") == "agent_message":
            texto = it.get("text")
    if not texto:
        return None, "codex no devolvio ningun mensaje"

    # El modelo a veces envuelve el JSON en ```json … ```.
    m = re.search(r"\{.*\}", texto, re.DOTALL)
    if not m:
        return None, f"la respuesta no traia JSON: {texto[:120]}"
    try:
        d = json.loads(m.group(0))
    except Exception as e:
        return None, f"JSON invalido: {e}"

    if d.get("clase") not in ("simple", "derivar", "urgente"):
        return None, f"clase desconocida: {d.get('clase')!r}"
    return d, None


def procesar(fila):
    """Devuelve el dict que se guarda como borrador. NUNCA lanza."""
    base = {"cliente_id": fila["cliente_id"], "respuesta_a": fila["mensaje_id"],
            "modelo": MODELO, "bloqueos": None}

    d, err = llamar_codex(armar_prompt(fila))
    if err:
        # Degradar a escalar, nunca a silencio.
        return {**base, "clase": "derivar", "respuesta": None,
                "motivo": f"la IA no pudo: {err}"}

    clase = d["clase"]
    if clase != "simple":
        return {**base, "clase": clase, "respuesta": None,
                "motivo": (d.get("motivo") or clase)[:300]}

    texto = (d.get("respuesta") or "").strip()
    bloqueos = VAL.revisar(texto)
    if bloqueos:
        # El validador gano. NO se reintenta ni se reescribe: intentar arreglar
        # la respuesta automaticamente es volver a confiar en el modelo para
        # justo lo que fallo.
        return {**base, "clase": "derivar", "respuesta": None,
                "bloqueos": bloqueos,
                "motivo": "el validador la freno: " + "; ".join(bloqueos[:3])}

    return {**base, "clase": "simple", "respuesta": texto,
            "motivo": (d.get("motivo") or "")[:300]}


def main():
    if not SB_KEY:
        _log("falta SUPABASE_SERVICE_KEY")
        return 1

    usado = cupo_usado()
    if usado >= CUPO_DIARIO:
        _log(f"cupo diario agotado ({usado}/{CUPO_DIARIO}) — hoy no se contesta mas, queda para Mati")
        return 0

    try:
        pendientes = _sb("mypump_chat_para_responder", {"p_limite": 10}) or []
    except urllib.error.HTTPError as e:
        _log(f"no pude leer la cola: {e.code} {e.read().decode()[:160]}")
        return 1

    if not pendientes:
        _log("nada para contestar")
        return 0

    _log(f"{len(pendientes)} mensajes sin responder" + ("" if CORRER else "   [DRY-RUN]"))

    if not CORRER:
        for f in pendientes:
            _log(f"  {(f.get('nombre') or f['cliente_id'])[:22]:<22} | {f['mensaje'][:70]}")
        _log("(dry-run: no se llamo a Codex ni se guardo nada; usa --correr)")
        return 0

    cupo = CUPO_DIARIO - usado
    if len(pendientes) > cupo:
        _log(f"solo quedan {cupo} del cupo: se procesan {cupo} y el resto espera")
        pendientes = pendientes[:cupo]

    with ThreadPoolExecutor(max_workers=CONCURRENCIA) as ex:
        resultados = list(ex.map(procesar, pendientes))

    guardados = 0
    conteo = {"simple": 0, "derivar": 0, "urgente": 0}
    for r in resultados:
        conteo[r["clase"]] = conteo.get(r["clase"], 0) + 1
        try:
            _sb("mypump_chat_borrador_guardar", {
                "p_cliente_id": r["cliente_id"],
                "p_respuesta_a": r["respuesta_a"],
                "p_clase": r["clase"],
                "p_respuesta": r["respuesta"],
                "p_motivo": r["motivo"],
                "p_bloqueos": r["bloqueos"],
                "p_modelo": r["modelo"],
            })
            guardados += 1
        except Exception as e:  # noqa: BLE001
            _log(f"  no pude guardar el borrador de {r['cliente_id']}: {e}")

    anotar_cupo(len(resultados))
    _log(f"{guardados} borradores guardados — {conteo['simple']} simples, "
         f"{conteo['derivar']} derivan, {conteo['urgente']} urgentes")
    _log("MODO SOMBRA: no se publico nada. Los borradores esperan en 💬 Chats del Cerebro.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
