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
import pathlib
import subprocess
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
           "--skip-git-repo-check", "-c", "mcp_servers={}"]
    try:
        p = subprocess.run(cmd, input="responde exactamente: ok",
                           capture_output=True, text=True, timeout=120, env=env, cwd="/tmp")
    except subprocess.TimeoutExpired:
        return False, "no contesto en 120s"
    except FileNotFoundError:
        return False, f"no existe el binario en {CODEX}"

    if p.returncode != 0:
        return False, f"salio con codigo {p.returncode}: {(p.stderr or '')[:200]}"

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

    texto = (
        "🚨 *El chat con IA esta caido*\n\n"
        f"Codex no responde: {detalle}\n\n"
        "Los mensajes de los clientes NO se pierden: quedan escalados en 💬 Chats "
        "del Cerebro y los contestas vos. Pero hasta que esto se arregle, la IA no "
        "contesta a nadie.\n\n"
        "Para arreglarlo, en la Mac mini:\n"
        "```\n"
        f"{CODEX} login\n"
        "```\n"
        "Y para confirmar que quedo:\n"
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
