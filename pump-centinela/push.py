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
import urllib.request
import urllib.error

# ── Config ────────────────────────────────────────────────────────────
SB_URL = os.environ.get("SUPABASE_URL", "https://gydinputrtptqakdzyvc.supabase.co")
SB_KEY = os.environ.get("SUPABASE_SERVICE_KEY", "")

APNS_KEY_PATH = os.environ.get("APNS_KEY_PATH", "")
APNS_KEY_ID   = os.environ.get("APNS_KEY_ID", "")
APNS_TEAM_ID  = os.environ.get("APNS_TEAM_ID", "")
APNS_TOPIC    = os.environ.get("APNS_TOPIC", "com.pumpteam.mypump")
APNS_ENV      = os.environ.get("APNS_ENV", "prod")

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

    req = urllib.request.Request(
        f"https://{APNS_HOST}/3/device/{device_token}",
        data=json.dumps(payload).encode(),
        headers={
            "authorization": f"bearer {jwt}",
            "apns-topic": APNS_TOPIC,
            "apns-push-type": "alert",
            "apns-priority": "10",
            "content-type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return (200 <= r.status < 300), None, False
    except urllib.error.HTTPError as e:
        detalle = ""
        try:
            detalle = (e.read() or b"").decode()[:200]
        except Exception:
            pass
        # 410 Gone = la app ya no está en ese dispositivo. 400 BadDeviceToken
        # también es terminal: seguir intentando contra ese token es tirar
        # requests para siempre.
        baja = e.code == 410 or "BadDeviceToken" in detalle
        return False, f"HTTP {e.code} {detalle}", baja
    except Exception as e:
        return False, str(e)[:200], False


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
