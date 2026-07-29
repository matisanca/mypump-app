#!/usr/bin/env python3
"""
push.py — manda las notificaciones encoladas a los iPhones vía APNs.

POR QUÉ ACÁ Y NO EN CLOUDFLARE
El envío necesita firmar un JWT con una clave privada (ES256) y mantener una
conexión HTTP/2 con Apple. La mini ya tiene la service key, launchd y el patrón
de _sb_req del centinela; Pages Functions no tiene cron ni un lugar seguro para
la clave.

QUÉ HACE
  1. Pide la cola a Supabase (mypump_push_pendientes).
  2. Firma un JWT con la key de APNs (vale 1 hora; se cachea, Apple rechaza si
     se pide uno nuevo en menos de 20 min).
  3. POST a APNs por cada aviso.
  4. Reporta el resultado (mypump_push_resultado). Un 410 apaga el device.

CONFIG (.env de la mini)
  APNS_KEY_PATH   ruta al AuthKey_XXXXXXXXXX.p8   (la pone Mati a mano)
  APNS_KEY_ID     los 10 caracteres del nombre del archivo
  APNS_TEAM_ID    Team ID de la cuenta de Apple
  APNS_TOPIC      com.pumpteam.mypump
  APNS_ENV        prod | sandbox   (default: prod)

Sin esas variables sale limpio y no hace nada — igual que wearables.py.

USO
  python3 push.py            # dry-run: muestra qué mandaría
  python3 push.py --enviar   # manda de verdad
"""

import os
import sys
import json
import time
import datetime as dt
import subprocess
import tempfile
# urllib sigue para las llamadas a Supabase (HTTP/1.1 le sirve). APNs NO: exige
# HTTP/2 y va por curl — ver enviar_uno().
import urllib.request
import urllib.error

# ── Config ────────────────────────────────────────────────────────────
# Dos .env, como el resto de la mini: la service key vive en el del bot
# (compartida con centinela/wearables) y lo de APNs en el de pump-centinela.
# Se leen los dos y el segundo pisa al primero.
BOT_ENV  = os.path.expanduser("~/agentkit-coach/.env")
PUSH_ENV = os.path.expanduser("~/pump-centinela/.env")


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
# os.environ gana sobre los archivos: permite override puntual en una corrida.
_g = lambda k, d="": os.environ.get(k) or E.get(k) or d

SB_URL = _g("SUPABASE_URL", "https://gydinputrtptqakdzyvc.supabase.co").rstrip("/")
SB_KEY = _g("SUPABASE_SERVICE_KEY") or _g("SUPABASE_KEY")

APNS_KEY_PATH = os.path.expanduser(_g("APNS_KEY_PATH"))
APNS_KEY_ID   = _g("APNS_KEY_ID")
APNS_TEAM_ID  = _g("APNS_TEAM_ID")
APNS_TOPIC    = _g("APNS_TOPIC", "com.pumpteam.mypump")
APNS_ENV      = _g("APNS_ENV", "prod")

APNS_HOST = ("api.push.apple.com" if APNS_ENV == "prod"
             else "api.sandbox.push.apple.com")

ENVIAR = "--enviar" in sys.argv


def _log(*a):
    print(f"[{dt.datetime.now():%Y-%m-%d %H:%M:%S}]", *a, flush=True)


# ── Supabase ──────────────────────────────────────────────────────────
def _sb_req(fn, payload):
    """RPC contra Supabase con la service key."""
    req = urllib.request.Request(
        f"{SB_URL}/rest/v1/rpc/{fn}",
        data=json.dumps(payload).encode(),
        headers={
            "apikey": SB_KEY,
            "Authorization": f"Bearer {SB_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        cuerpo = r.read().decode()
        return json.loads(cuerpo) if cuerpo.strip() else None


# ── JWT de APNs ───────────────────────────────────────────────────────
# Apple pide un JWT ES256 firmado con la .p8. Se cachea porque rechaza tokens
# pedidos con menos de 20 minutos de diferencia (TooManyProviderTokenUpdates).
_jwt_cache = {"token": None, "emitido": 0}


def _b64(data: bytes) -> str:
    import base64
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def jwt_apns():
    ahora = int(time.time())
    if _jwt_cache["token"] and (ahora - _jwt_cache["emitido"]) < 3000:  # 50 min
        return _jwt_cache["token"]

    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec, utils as asym_utils
    except ImportError:
        _log("falta 'cryptography' en el venv")
        return None

    with open(APNS_KEY_PATH, "rb") as f:
        clave = serialization.load_pem_private_key(f.read(), password=None)

    header  = {"alg": "ES256", "kid": APNS_KEY_ID}
    payload = {"iss": APNS_TEAM_ID, "iat": ahora}
    firmar  = f"{_b64(json.dumps(header).encode())}.{_b64(json.dumps(payload).encode())}"

    der = clave.sign(firmar.encode(), ec.ECDSA(hashes.SHA256()))
    # APNs quiere la firma como r||s crudo (64 bytes), no el DER que devuelve
    # cryptography. Sin esta conversión Apple responde 403 InvalidProviderToken.
    r, s = asym_utils.decode_dss_signature(der)
    firma = r.to_bytes(32, "big") + s.to_bytes(32, "big")

    tok = f"{firmar}.{_b64(firma)}"
    _jwt_cache.update({"token": tok, "emitido": ahora})
    return tok


# ── Envío ─────────────────────────────────────────────────────────────
# APNs EXIGE HTTP/2. No es una preferencia: la conexión en HTTP/1.1 ni se
# establece. Verificado contra api.push.apple.com el 28-jul-2026:
#
#   curl --http1.1 ...  →  HTTP 000 (no conecta)
#   curl --http2   ...  →  HTTP 403 (llega y contesta: falta el token, correcto)
#   urllib          →  BadStatusLine: "Unexpected HTTP/1.x request: POST /3/device/..."
#
# Acá había urllib.request.urlopen, que habla SOLO HTTP/1.1. O sea que ninguna
# notificación pudo salir nunca: todos los envíos caían en el `except Exception`
# y se reportaban como fallidos. Como el error quedaba en la cola y no a la
# vista, no se notó — y del otro lado tampoco, porque encima ningún dispositivo
# llegaba a registrarse (mypump_registrar_push consultaba una tabla inexistente,
# arreglado en la mig 049).
#
# Se usa curl y no httpx porque httpx necesita el paquete `h2`, que no está
# instalado en el venv de la mini; curl ya viene con nghttp2 y no agrega nada
# que mantener. Ni el JWT ni el payload van por argv (serían visibles en `ps`):
# las cabeceras viajan en un archivo de config con permisos 600 y el cuerpo por
# stdin.
def enviar_uno(device_token, titulo, cuerpo, destino, jwt):
    """Devuelve (ok, error, baja_device)."""
    payload = {
        "aps": {
            "alert": {"title": titulo, "body": cuerpo},
            "sound": "default",
            "badge": 1,
        },
    }
    if destino:
        payload["destino"] = destino   # lo lee cablearTapsPush() en el cliente

    cfg = None
    try:
        fd, cfg = tempfile.mkstemp(prefix="apns_", suffix=".conf")
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(f'header = "authorization: bearer {jwt}"\n'
                    f'header = "apns-topic: {APNS_TOPIC}"\n'
                    'header = "apns-push-type: alert"\n'
                    'header = "apns-priority: 10"\n'
                    'header = "content-type: application/json"\n')

        p = subprocess.run(
            ["curl", "--http2", "--silent", "--show-error",
             "--config", cfg,
             "--request", "POST",
             "--data-binary", "@-",
             "--max-time", "20",
             # El cuerpo primero y el código al final, separados por \n: el
             # cuerpo de APNs es JSON de una línea, así que la última línea es
             # siempre el código.
             "--write-out", "\n%{http_code}",
             f"https://{APNS_HOST}/3/device/{device_token}"],
            input=json.dumps(payload), capture_output=True, text=True, timeout=30)
    except Exception as e:
        return False, f"curl: {type(e).__name__}: {str(e)[:160]}", False
    finally:
        if cfg:
            try: os.unlink(cfg)
            except OSError: pass

    if p.returncode != 0:
        return False, f"curl rc={p.returncode} {(p.stderr or '').strip()[:160]}", False

    partes = (p.stdout or "").rsplit("\n", 1)
    detalle = partes[0].strip()[:200] if len(partes) == 2 else ""
    try:
        codigo = int(partes[-1].strip())
    except ValueError:
        return False, f"respuesta ilegible: {(p.stdout or '')[:120]!r}", False

    if 200 <= codigo < 300:
        return True, None, False
    # 410 Gone = la app ya no está en ese dispositivo. 400 BadDeviceToken
    # también es terminal: seguir intentando contra ese token es tirar
    # requests para siempre.
    baja = codigo == 410 or "BadDeviceToken" in detalle
    return False, f"HTTP {codigo} {detalle}", baja


def main():
    faltan = [n for n, v in [
        ("APNS_KEY_PATH", APNS_KEY_PATH),
        ("APNS_KEY_ID", APNS_KEY_ID),
        ("APNS_TEAM_ID", APNS_TEAM_ID),
    ] if not v]
    if faltan:
        _log(f"push sin configurar (faltan {', '.join(faltan)} en el .env) — nada que hacer")
        return 0
    if not os.path.exists(APNS_KEY_PATH):
        _log(f"no existe la key en {APNS_KEY_PATH}")
        return 1
    if not SB_KEY:
        _log("falta SUPABASE_SERVICE_KEY")
        return 1

    try:
        pendientes = _sb_req("mypump_push_pendientes", {"p_limite": 100}) or []
    except Exception as e:
        _log(f"no pude leer la cola: {e}")
        return 1

    if not pendientes:
        _log("cola vacia")
        return 0

    _log(f"{len(pendientes)} avisos en cola" + ("" if ENVIAR else "  [DRY-RUN]"))

    if not ENVIAR:
        for p in pendientes[:20]:
            _log(f"  -> {p['cliente_id']}: {p['titulo']} | {p['cuerpo'][:60]}")
        _log("(dry-run: no se mando nada; usa --enviar)")
        return 0

    jwt = jwt_apns()
    if not jwt:
        _log("no pude firmar el JWT de APNs")
        return 1

    ok = err = 0
    for p in pendientes:
        exito, error, baja = enviar_uno(
            p["device_token"], p["titulo"], p["cuerpo"], p.get("destino"), jwt
        )
        try:
            _sb_req("mypump_push_resultado", {
                "p_id": p["id"], "p_ok": exito, "p_error": error,
                "p_device_token": p["device_token"], "p_baja_device": baja,
            })
        except Exception as e:
            _log(f"  no pude reportar el resultado de {p['id']}: {e}")
        if exito:
            ok += 1
        else:
            err += 1
            _log(f"  fallo {p['cliente_id']}: {error}")

    _log(f"listo: {ok} enviados, {err} con error")
    return 0


if __name__ == "__main__":
    sys.exit(main())
