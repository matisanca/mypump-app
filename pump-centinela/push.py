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

# ── Web Push (VAPID) ─────────────────────────────────────────────────────
# Es el transporte que cubre a los 62 clientes que abren MyPump como link del
# navegador — y a Android entero, sin Firebase y sin esperar a Google Play.
#
# La clave privada NUNCA se commitea: vive solo en el .env de esta maquina. La
# publica que le toca es la que esta en public/js/config.js, y las dos tienen
# que ser del MISMO par o el navegador rechaza el envio con un 403 que no
# explica nada.
# ── FCM, para el Android nativo ──────────────────────────────────────────
# Web Push cubre a quien usa la PWA desde Chrome, que hoy son todos. Pero el
# WebView de la app instalada NO implementa la Push API, asi que el que la baje
# de Play no recibiria nada por ese camino: para el nativo el unico transporte
# es FCM.
#
# FCM_SA_PATH es el JSON de la cuenta de servicio de Firebase. Sin el, la rama
# de android no manda y deja el aviso en la cola, igual que Web Push sin VAPID.
FCM_SA_PATH = os.path.expanduser(_g("FCM_SA_PATH", ""))
FCM_PROJECT = _g("FCM_PROJECT_ID", "")
_fcm_cred = None       # se cachea: pedir un token OAuth por cada push es absurdo

VAPID_PRIVATE = _g("VAPID_PRIVATE_KEY")
VAPID_SUBJECT = _g("VAPID_SUBJECT", "mailto:fuarkteam@gmail.com")

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


# ── Libreta de entregados ─────────────────────────────────────────────
# Un aviso sale de la cola cuando `mypump_push_resultado` lo marca. Si esa RPC
# falla — un timeout, un corte de red de 3 segundos — el aviso YA llegó al
# iPhone pero sigue pendiente en la base, y como este script corre cada 5
# minutos, el cliente recibe la misma notificación una y otra vez hasta que la
# base vuelva. Ahí no hay a quién culpar: para el usuario es spam nuestro.
#
# Entonces lo entregado se anota primero acá, en la mini, apenas Apple acepta.
# La base sigue siendo la fuente de verdad de la cola; esta libreta solo
# responde una pregunta: "¿esto ya salió?". Si dice que sí, no se vuelve a
# mandar — se reintenta nada más el reporte, para que el aviso termine de
# salir de la cola.
LEDGER = os.path.expanduser(_g("PUSH_LEDGER", "~/pump-centinela/.push_entregados"))
LEDGER_DIAS = 7   # más viejo que esto ya no puede seguir en la cola


def cargar_entregados():
    """ids ya entregados a APNs -> set. Poda lo viejo de paso."""
    corte = time.time() - LEDGER_DIAS * 86400
    vivos, ids = [], set()
    try:
        for linea in open(LEDGER):
            try:
                r = json.loads(linea)
            except ValueError:
                continue          # línea a medio escribir: se descarta sola
            if r.get("ts", 0) >= corte:
                vivos.append(r)
                ids.add(r["id"])
    except FileNotFoundError:
        return set()
    # Reescribir solo cuando algo se cayó por viejo: si no, esto es un write
    # inútil cada 5 minutos.
    if len(vivos) != sum(1 for _ in open(LEDGER)):
        _guardar_ledger(vivos)
    return ids


def _guardar_ledger(registros):
    tmp = LEDGER + ".tmp"
    with open(tmp, "w") as f:
        for r in registros:
            f.write(json.dumps(r) + "\n")
    os.replace(tmp, LEDGER)   # atómico: nunca se ve un archivo a medias


def anotar_entregado(push_id):
    """Se llama APENAS Apple acepta, antes de reportar a Supabase."""
    try:
        os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
        with open(LEDGER, "a") as f:
            f.write(json.dumps({"id": push_id, "ts": int(time.time())}) + "\n")
    except Exception as e:
        # Sin libreta el peor caso vuelve a ser el de antes (un aviso repetido),
        # así que no se corta el envío por esto — pero que quede en el log.
        _log(f"  ojo: no pude anotar {push_id} en la libreta: {e}")


def reportar(p, exito, error, baja, intentos=3):
    """Marca el aviso en la base. Reintenta: es lo único que lo saca de la cola."""
    for i in range(intentos):
        try:
            _sb_req("mypump_push_resultado", {
                "p_id": p["id"], "p_ok": exito, "p_error": error,
                "p_device_token": p["device_token"], "p_baja_device": baja,
            })
            return True
        except Exception as e:
            if i == intentos - 1:
                _log(f"  no pude reportar el resultado de {p['id']}: {e}")
                return False
            time.sleep(2 ** i)
    return False


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


def enviar_web(endpoint, p256dh, auth, titulo, cuerpo, destino):
    """Web Push. Devuelve (ok, error, baja_device) — mismo contrato que APNs.

    Se usa pywebpush en vez de escribir el cifrado a mano. El payload de Web
    Push va cifrado con aes128gcm (RFC 8291): ECDH sobre P-256, HKDF y AES-GCM.
    Son ~60 lineas que, mal hechas, no fallan con un error: el navegador
    responde 201 Created y la notificacion no aparece nunca. Un bug asi no se
    detecta hasta que un cliente avisa que no le llega nada.
    """
    if not VAPID_PRIVATE:
        return False, "sin VAPID_PRIVATE_KEY en el .env", False
    try:
        from pywebpush import webpush, WebPushException
    except ImportError:
        return False, "falta pywebpush en el venv", False

    datos = {"title": titulo, "body": cuerpo}
    if destino:
        datos["destino"] = destino

    try:
        webpush(
            subscription_info={"endpoint": endpoint, "keys": {"p256dh": p256dh, "auth": auth}},
            data=json.dumps(datos),
            vapid_private_key=VAPID_PRIVATE,
            vapid_claims={"sub": VAPID_SUBJECT},
            ttl=86400,          # un dia: si el telefono esta apagado, igual llega
        )
        return True, None, False
    except WebPushException as e:
        codigo = getattr(getattr(e, "response", None), "status_code", None)
        # 404/410 = la suscripcion murió (desinstaló la PWA, limpió el sitio).
        # Es exactamente el 410 Gone de APNs y se trata igual: se da de baja el
        # device. Sin esto, el mismo endpoint muerto se reintenta para siempre.
        if codigo in (404, 410):
            return False, f"suscripcion dada de baja ({codigo})", True
        return False, f"webpush {codigo}: {str(e)[:160]}", False
    except Exception as e:
        return False, f"{type(e).__name__}: {str(e)[:160]}", False


def enviar_fcm(device_token, titulo, cuerpo, destino):
    """FCM HTTP v1. Devuelve (ok, error, baja_device) — mismo contrato que APNs.

    El token OAuth se saca con google.auth, que ya esta en el venv. Escribirlo a
    mano seria firmar un JWT RS256 y canjearlo: 40 lineas para reimplementar algo
    que la libreria oficial hace bien, incluido el refresco cuando vence.

    VA `notification` ADEMAS DE `data`, Y ES LO QUE HACE QUE SE VEA.

    Hasta el 29-ago esto mandaba data-only, con este razonamiento escrito aca:
    "con `notification` el tap no puede llevar a la pantalla del chat". ERA
    FALSO, y se llevaba puesta la feature entera:

      · El plugin de Capacitor solo postea una notificacion adentro de
        `if (notification != null)` (PushNotificationsPlugin.java:246-282). Es
        la unica llamada a notificationManager.notify() de todo el plugin. Con
        data-only ese bloque es null y no entra nunca: lo unico que hace es
        emitir `pushNotificationReceived` (:296)...
      · ...y en la app NADIE escucha ese evento. El unico listener de push es
        `pushNotificationActionPerformed`, que se dispara al TOCAR una
        notificacion que no iba a existir.

    Peor todavia: FCM contesta 200 igual, porque acepto el mensaje para
    entrega. Asi que `enviar_fcm` devolvia exito, el ledger lo anotaba como
    entregado, y el Cerebro iba a mostrar avisos que en el telefono nunca
    aparecieron. La falla muda de siempre — el dato bien calculado y nadie que
    lo consuma.

    Y el miedo al deep link no tenia fundamento: `handleOnNewIntent` (:58-77)
    vuelca TODAS las claves del intent —incluido el `destino`, que viaja en
    `data`— adentro de `notification.data`, y recien ahi dispara
    `pushNotificationActionPerformed`. Que es exactamente lo que lee el
    listener de notificaciones.js. El tap sigue llevando al chat.

    No se declara `channel_id` a proposito: si se nombra un canal que la app no
    creo, Android 8+ descarta la notificacion EN SILENCIO. Sin el campo, FCM
    usa su canal de respaldo, que siempre existe.
    """
    global _fcm_cred
    if not FCM_SA_PATH or not FCM_PROJECT:
        return False, "sin FCM_SA_PATH / FCM_PROJECT_ID en el .env", False
    if not os.path.exists(FCM_SA_PATH):
        return False, f"no existe {FCM_SA_PATH}", False

    try:
        import requests
        from google.oauth2 import service_account
        from google.auth.transport.requests import Request as GARequest
    except ImportError as e:
        return False, f"falta {e.name} en el venv", False

    try:
        if _fcm_cred is None:
            _fcm_cred = service_account.Credentials.from_service_account_file(
                FCM_SA_PATH,
                scopes=["https://www.googleapis.com/auth/firebase.messaging"])
        if not _fcm_cred.valid:
            _fcm_cred.refresh(GARequest())
    except Exception as e:  # noqa: BLE001
        return False, f"no pude autenticar con FCM: {type(e).__name__}: {str(e)[:120]}", False

    cuerpo_msg = {
        "message": {
            "token": device_token,
            # Sin esto el push llega, FCM contesta 200 y en la pantalla del
            # cliente no aparece nada. Ver el docstring.
            "notification": {
                "title": titulo,
                "body": cuerpo,
            },
            # `destino` sigue viajando en data: es lo que sobrevive al tap y
            # lleva a la pantalla correcta.
            "data": {
                "destino": destino or "chat",
            },
            "android": {
                # `high` es lo que despierta al telefono en Doze. Con la
                # prioridad normal, un aviso de la ronda del domingo podria
                # entregarse recien a la mañana siguiente.
                "priority": "high",
                "ttl": "86400s",
                "collapse_key": f"mypump-{destino or 'chat'}",
                "notification": {
                    # Que suene y vibre como cualquier mensaje. Sin esto, en
                    # algunos Android entra en silencio y el cliente se entera
                    # cuando abre el telefono por otra cosa.
                    "default_sound": True,
                    "default_vibrate_timings": True,
                    "notification_priority": "PRIORITY_HIGH",
                },
            },
        }
    }

    url = f"https://fcm.googleapis.com/v1/projects/{FCM_PROJECT}/messages:send"
    try:
        r = requests.post(
            url, json=cuerpo_msg, timeout=20,
            headers={"Authorization": f"Bearer {_fcm_cred.token}",
                     "Content-Type": "application/json; UTF-8"})
    except Exception as e:  # noqa: BLE001
        return False, f"{type(e).__name__}: {str(e)[:160]}", False

    if r.status_code == 200:
        return True, None, False

    # UNREGISTERED / INVALID_ARGUMENT sobre el token = el device murio
    # (desinstalo, o el token rotó). Es el 410 de APNs y el 404 de Web Push, y
    # se trata igual: se da de baja. Sin esto el token muerto se reintenta para
    # siempre y ensucia el conteo de fallos.
    txt = r.text[:300]
    if r.status_code == 404 or "UNREGISTERED" in txt or "NOT_FOUND" in txt:
        return False, f"device dado de baja ({r.status_code})", True
    return False, f"fcm {r.status_code}: {txt[:160]}", False


def main():
    faltan = [n for n, v in [
        ("APNS_KEY_PATH", APNS_KEY_PATH),
        ("APNS_KEY_ID", APNS_KEY_ID),
        ("APNS_TEAM_ID", APNS_TEAM_ID),
    ] if not v]
    # APNs faltante ya NO corta la corrida: si hay VAPID configurado, los
    # avisos web tienen que salir igual. Antes un .env sin APNS_KEY_ID
    # significaba que NADIE recibia nada, ni siquiera los del navegador.
    hay_apns = not faltan and os.path.exists(APNS_KEY_PATH)
    hay_web  = bool(VAPID_PRIVATE)
    hay_fcm  = bool(FCM_SA_PATH and FCM_PROJECT and os.path.exists(FCM_SA_PATH))
    if not (hay_apns or hay_web or hay_fcm):
        detalle = f"faltan {', '.join(faltan)}" if faltan else f"no existe la key en {APNS_KEY_PATH}"
        _log(f"push sin configurar ({detalle}; tampoco hay VAPID ni FCM) — nada que hacer")
        return 0

    # Se dice SIEMPRE qué transporte está vivo y cuál no. Un transporte apagado
    # no es un error, pero tampoco puede ser invisible: la razón por la que
    # Android estuvo sin push fue justamente que nada lo decía en voz alta.
    _log("transportes: "
         f"APNs {'ok' if hay_apns else 'APAGADO'} · "
         f"web {'ok' if hay_web else 'APAGADO'} · "
         f"FCM {'ok' if hay_fcm else 'APAGADO'}")
    if not hay_web:
        _log("  sin VAPID_PRIVATE_KEY: los avisos web quedan en la cola (ver docs/PUSH_WEB.md)")
    if not hay_fcm:
        _log("  sin FCM_SA_PATH/FCM_PROJECT_ID: los avisos del Android nativo quedan en la cola")
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
            _log(f"  -> [{p.get('plataforma','ios')}] {p['cliente_id']}: {p['titulo']} | {p['cuerpo'][:60]}")
        _log("(dry-run: no se mando nada; usa --enviar)")
        return 0

    jwt = None
    if hay_apns:
        jwt = jwt_apns()
        if not jwt:
            _log("no pude firmar el JWT de APNs")
            return 1

    entregados = cargar_entregados()

    ok = err = repetidos = 0
    for p in pendientes:
        if p["id"] in entregados:
            # Ya salió en una corrida anterior; quedó en la cola solo porque el
            # reporte no llegó. Se reintenta el reporte y NO se vuelve a mandar.
            repetidos += 1
            reportar(p, True, None, False)
            continue

        plataforma = (p.get("plataforma") or "ios").lower()
        if plataforma == "web":
            if not hay_web:
                # Se deja en la cola, no se marca error: apenas se configure
                # VAPID sale solo en la corrida siguiente. Gastar los 4
                # intentos ahora seria perder el aviso por una config que falta.
                continue
            exito, error, baja = enviar_web(
                p["device_token"], p.get("p256dh"), p.get("auth"),
                p["titulo"], p["cuerpo"], p.get("destino")
            )
        elif plataforma == "android":
            if not hay_fcm:
                # Igual que Web Push sin VAPID: se deja en la cola en vez de
                # gastar los 4 intentos. Apenas se configure FCM sale solo en la
                # corrida siguiente, sin perder el aviso.
                continue
            exito, error, baja = enviar_fcm(
                p["device_token"], p["titulo"], p["cuerpo"], p.get("destino")
            )
        else:
            if not hay_apns:
                continue
            exito, error, baja = enviar_uno(
                p["device_token"], p["titulo"], p["cuerpo"], p.get("destino"), jwt
            )
        # Anotar ANTES de reportar: entre el ok de Apple y el ok de Supabase es
        # justo donde se colaban los avisos repetidos.
        if exito:
            anotar_entregado(p["id"])
        reportar(p, exito, error, baja)

        if exito:
            ok += 1
        else:
            err += 1
            _log(f"  fallo {p['cliente_id']}: {error}")

    extra = f", {repetidos} ya entregados (solo se reporto)" if repetidos else ""
    _log(f"listo: {ok} enviados, {err} con error{extra}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
