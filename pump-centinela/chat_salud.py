#!/usr/bin/env python3
"""chat_salud.py — avisa si Codex se murio, ANTES de que se note en el chat

POR QUE EXISTE
La sesion del CLI se vence sola. Ya paso: el CLI de Claude estuvo caido DOS
NOCHES ENTERAS en esta misma maquina y nadie se entero, porque un worker que
falla en silencio se ve identico a un worker sin trabajo.

Con el chat automatico prendido eso es peor que antes. El worker degrada a
escalar —cada mensaje termina en la bandeja de Mati con "la IA no pudo"— asi
que nadie recibe una respuesta mala. Pero Mati tampoco sabe POR QUE de golpe
tiene que contestar todo a mano, y lo va a descubrir el jueves, con 40 mensajes
encima.

QUE HACE
Cada hora le pide a Codex que conteste "ok". Si no contesta, manda UN WhatsApp
con el comando exacto para volver a loguearse. Uno solo: si avisara en cada
corrida, serian 24 mensajes por dia y a la segunda noche estarian silenciados.

USO
  python3 chat_salud.py              # chequea y avisa si hace falta
  python3 chat_salud.py --forzar     # avisa igual (para probar el aviso)
"""
import json
import os
import re
import pathlib
import subprocess
import time
import sys
import urllib.request
from datetime import datetime, timedelta

BASE = pathlib.Path(__file__).resolve().parent


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

CODEX = os.path.expanduser(_g("CODEX_BIN", "~/.local/bin/codex"))
MODELO = _g("CODEX_MODELO", "gpt-5.6-sol")
FORZAR = "--forzar" in sys.argv

# Libreta del ultimo aviso, para no repetirlo cada hora.
ESTADO = BASE / ".chat_salud"
SILENCIO_H = 8
# Cuánto se espera antes de la segunda opinión (ver main): suficiente para que
# pase un corte de red corto, poco para que el aviso llegue tarde si es real.
ESPERA_REINTENTO_S = 90


def _log(*a):
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}]", *a, flush=True)


def whatsapp(texto):
    tok, pnid, to = _g("META_ACCESS_TOKEN"), _g("META_PHONE_NUMBER_ID"), _g("COACH_PHONE_NUMBER")
    if not (tok and pnid and to):
        _log("faltan credenciales de Meta — no puedo avisar")
        return False
    payload = json.dumps({"messaging_product": "whatsapp", "recipient_type": "individual",
                          "to": to, "type": "text", "text": {"body": texto}}).encode()
    try:
        req = urllib.request.Request(
            f"https://graph.facebook.com/v21.0/{pnid}/messages", data=payload,
            headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status == 200
    except Exception as e:  # noqa: BLE001
        _log(f"no pude mandar el WhatsApp: {e}")
        return False


def aviso_reciente():
    try:
        d = json.loads(ESTADO.read_text())
        ult = datetime.fromisoformat(d["ultimo_aviso"])
        return datetime.now() - ult < timedelta(hours=SILENCIO_H)
    except Exception:
        return False


def anotar_aviso():
    try:
        ESTADO.write_text(json.dumps({"ultimo_aviso": datetime.now().isoformat()}))
    except Exception:
        pass


# Lineas de stderr que NO son el error: si se las deja, un aviso truncado a
# 200 caracteres termina mostrando ruido y no la causa (paso el 25-sep, y el
# aviso pedia un `codex login` que no tenia nada que ver).
_RUIDO = re.compile(r"rmcp::|Reading prompt from stdin|^\s*$|OpenTelemetry|tracing::")


def _err_util(stderr, limite=400):
    """Las ultimas lineas de stderr que dicen algo."""
    lineas = [l.strip() for l in (stderr or "").splitlines() if l.strip() and not _RUIDO.search(l)]
    if not lineas:
        return (stderr or "").strip()[-limite:] or "sin detalle en stderr"
    return " | ".join(lineas[-3:])[-limite:]


def codex_vivo():
    """(ok, detalle). Mismo comando exacto que usa el worker de verdad.

    Si el chequeo usara flags distintos, podria pasar en verde mientras el
    worker falla — que es la unica forma de que un health check sea PEOR que no
    tener ninguno.
    """
    env = dict(os.environ)
    for k in ("OPENAI_API_KEY", "OPENAI_BASE_URL", "OPENAI_ORG_ID"):
        env.pop(k, None)
    cmd = [CODEX, "exec", "-m", MODELO, "--json", "-s", "read-only",
           "--skip-git-repo-check",
           # --ignore-user-config y NO `-c mcp_servers={}`: ese override no
           # hace nada en codex-cli 0.145.0 y la corrida seguia levantando los
           # servidores MCP del config del escritorio. Con la Codex.app cerrada,
           # el MCP `daydream` (http://127.0.0.1:7433/mcp) no existe y cada
           # llamada escupia tres errores de transporte que se comian el
           # mensaje de error de verdad (25-sep). Ignorar el config tambien
           # saca de la ecuacion el `model = gpt-5.5` del archivo, que esta
           # dado de baja desde el 7-sep. La sesion (auth) NO depende de esto.
           "--ignore-user-config"]
    try:
        p = subprocess.run(cmd, input="responde exactamente: ok",
                           capture_output=True, text=True, timeout=120, env=env, cwd="/tmp")
    except subprocess.TimeoutExpired:
        return False, "no contesto en 120s"
    except FileNotFoundError:
        return False, f"no existe el binario en {CODEX}"

    if p.returncode != 0:
        return False, f"salio con codigo {p.returncode}: {_err_util(p.stderr)}"

    for linea in (p.stdout or "").splitlines():
        try:
            ev = json.loads(linea)
        except Exception:
            continue
        it = ev.get("item") or {}
        if ev.get("type") == "item.completed" and it.get("type") == "agent_message":
            if "ok" in (it.get("text") or "").lower():
                return True, "ok"
            return False, f"contesto algo raro: {(it.get('text') or '')[:80]}"
    return False, "no devolvio ningun mensaje (¿sesion vencida?)"


def main():
    ok, detalle = codex_vivo()

    # SEGUNDA OPINION antes de despertar a nadie. El 25-sep el chequeo fallo
    # una vez (a la hora siguiente ya andaba) y el aviso dijo que la IA no le
    # contestaba a nadie. Un corte de red de 10 segundos no es una caida: si
    # el primer intento falla, se espera y se vuelve a probar, y solo se avisa
    # si los dos fallan.
    if not ok and not FORZAR:
        _log(f"primer intento fallo: {detalle} — reintento en {ESPERA_REINTENTO_S}s")
        time.sleep(ESPERA_REINTENTO_S)
        ok2, detalle2 = codex_vivo()
        if ok2:
            _log("el reintento anduvo: era pasajero, no aviso")
            ok, detalle = True, "ok (fallo un intento y el siguiente anduvo)"
        else:
            detalle = f"{detalle} (y al reintentar: {detalle2})"

    if ok and not FORZAR:
        _log("codex ok")
        # Si venia caido y se recupero, avisar tambien: saber que volvio evita
        # que Mati siga contestando todo a mano por las dudas.
        if ESTADO.exists():
            whatsapp("✅ El chat con IA volvio a andar. Codex responde de nuevo.")
            try:
                ESTADO.unlink()
            except Exception:
                pass
        return 0

    _log(f"CODEX CAIDO: {detalle}")

    if aviso_reciente() and not FORZAR:
        _log(f"ya avise hace menos de {SILENCIO_H}h — no repito")
        return 1

    # El remedio depende del sintoma: mandar siempre "corre codex login" hacia
    # que Mati tocara la sesion por un problema de red.
    d = (detalle or "").lower()
    if "sesion" in d or "login" in d or "401" in d or "unauthorized" in d or "no devolvio ningun mensaje" in d:
        remedio = ("Parece la sesion de Codex. En la Mac mini:\n"
                   "```\n"
                   f"{CODEX} login\n"
                   "```")
    elif "no contesto en" in d or "timed out" in d or "timeout" in d:
        remedio = "Parece red o el modelo lento. Si en la proxima hora sigue igual, avisame y lo miro."
    elif "429" in d or "rate limit" in d or "usage limit" in d or "quota" in d:
        remedio = "Es el limite de uso de la cuenta de Codex: se destraba solo cuando se libera la cuota."
    else:
        remedio = "No es la sesion (eso se dice aparte). Mandame este mensaje y lo miro."
    texto = (
        "🚨 *El chat con IA esta caido*\n\n"
        f"Codex no responde: {detalle}\n\n"
        "Los mensajes de los clientes NO se pierden: quedan escalados en 💬 Chats "
        "del Cerebro y los contestas vos. Pero hasta que esto se arregle, la IA no "
        "contesta a nadie.\n\n"
        f"{remedio}\n\n"
        "Para ver como esta ahora:\n"
        "```\n"
        "cd ~/pump-centinela && ~/agentkit-coach/venv/bin/python chat_salud.py\n"
        "```"
    )
    if whatsapp(texto):
        anotar_aviso()
        _log("aviso mandado")
    return 1


if __name__ == "__main__":
    sys.exit(main())
