#!/usr/bin/env python3
"""test_push_android.py — que el Android tenga push, y que no vuelva a apagarse solo.

POR QUE EXISTE
Android quedó sin push de ningún tipo durante meses, y lo peor es CÓMO: no había
un error en ningún lado. `notificaciones.js` tenía `if (android) return null`
con un comentario que decía "para prenderlo, sacar estas tres líneas" — o sea,
dependía de que alguien se acordara. Y `push.py` devolvía "android/FCM todavia
no implementado" sin que nadie lo viera.

Dos huecos distintos y los dos silenciosos:
  · el binario: sin google-services.json, register() mata el proceso desde el
    lado NATIVO y ningún try/catch de JS lo atrapa;
  · el servidor: no existía la rama FCM.

Ahora el flag lo decide el build y el envío existe. Este test cubre las dos
puntas y falla si alguna se vuelve a apagar.
"""
import io
import json
import pathlib
import sys
import types

RAIZ = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "pump-centinela"))

fallas = 0


def check(nombre, ok, detalle=""):
    global fallas
    print(f"  {'✓' if ok else '✗'} {nombre}")
    if not ok:
        fallas += 1
        if detalle:
            print(f"      {detalle}")


print("\n1. La guarda de Android la decide el build, no una persona")
NOTIF = (RAIZ / "public" / "js" / "notificaciones.js").read_text()
check("ya no hay un return null fijo para android",
      "Cap.getPlatform() === 'android') return null" not in NOTIF,
      "volvió el apagado fijo: el push de Android no se prende aunque haya Firebase")
check("la guarda mira el flag del binario",
      "if (esAndroid && !window.MYPUMP_FCM) return null;" in NOTIF)

FLAG = (RAIZ / "public" / "js" / "fcm-flag.js").read_text()
check("el flag arranca en false", "window.MYPUMP_FCM = false;" in FLAG,
      "commitearlo en true prendería el push en binarios sin Firebase → crash nativo")

HTML = (RAIZ / "public" / "cliente.html").read_text()
check("cliente.html carga el flag", "/js/fcm-flag.js" in HTML)
check("lo carga ANTES que notificaciones.js",
      HTML.index("/js/fcm-flag.js") < HTML.index("/js/notificaciones.js"),
      "si carga después, window.MYPUMP_FCM es undefined cuando se evalúa la guarda")

YAML = (RAIZ / "codemagic.yaml").read_text()
check("el build escribe el flag según google-services.json",
      "if [ -f android/app/google-services.json ]" in YAML
      and "window.MYPUMP_FCM = true;" in YAML)
check("lo escribe ANTES de cap sync",
      YAML.index("Marcar si el binario lleva Firebase") < YAML.index("Capacitor sync Android"),
      "cap sync copia public/ entero: si el flag se escribe después, no entra al APK")

print("\n2. El servidor sabe mandar por FCM")
import push as P  # noqa: E402

check("existe enviar_fcm", callable(getattr(P, "enviar_fcm", None)))
FUENTE = (RAIZ / "pump-centinela" / "push.py").read_text()
check("ya no dice 'todavia no implementado'",
      "android/FCM todavia no implementado" not in FUENTE)
check("el router llama a enviar_fcm", "exito, error, baja = enviar_fcm(" in FUENTE)
check("sin FCM el aviso queda en la cola, no se quema",
      "if not hay_fcm:\n                # Igual que Web Push sin VAPID" in FUENTE,
      "si marcara error, gastaría los 4 intentos antes de que exista la config")

print("\n3. enviar_fcm se comporta")
P.FCM_SA_PATH, P.FCM_PROJECT = "", ""
ok, err, baja = P.enviar_fcm("tok", "t", "c", "chat")
check("sin config: no manda y no da de baja", (ok, baja) == (False, False) and "sin FCM" in err, err)

P.FCM_SA_PATH, P.FCM_PROJECT = "/no/existe.json", "proj"
ok, err, baja = P.enviar_fcm("tok", "t", "c", "chat")
check("con ruta inexistente: error claro, sin baja",
      (ok, baja) == (False, False) and "no existe" in err, err)

# Simular la API de FCM para ejercitar el camino real sin credenciales.
class _Cred:
    valid, token = True, "fake"
    def refresh(self, _): pass

enviado = {}


class _Resp:
    def __init__(self, code, text=""): self.status_code, self.text = code, text


def _fake_post(url, json=None, timeout=None, headers=None):
    enviado.update(url=url, body=json, headers=headers)
    return _Resp(*_fake_post.resp)


# Se INYECTAN los modulos falsos en sys.modules en vez de parchear los reales:
# google-auth vive en el venv de la mini y no en la maquina donde corre npm
# test. Un test de esta logica no puede depender de tener instalado el SDK de
# Google — lo que se prueba es NUESTRO codigo, no el de ellos.
_g_auth = types.ModuleType("google.auth")
_g_tr = types.ModuleType("google.auth.transport")
_g_trq = types.ModuleType("google.auth.transport.requests")
_g_trq.Request = lambda *a, **k: None
_g_oauth = types.ModuleType("google.oauth2")
_g_sa = types.ModuleType("google.oauth2.service_account")
_g_sa.Credentials = type("C", (), {
    "from_service_account_file": staticmethod(lambda *a, **k: _Cred())})
_g_root = types.ModuleType("google")
for _n, _m in [("google", _g_root), ("google.auth", _g_auth),
               ("google.auth.transport", _g_tr),
               ("google.auth.transport.requests", _g_trq),
               ("google.oauth2", _g_oauth),
               ("google.oauth2.service_account", _g_sa)]:
    sys.modules[_n] = _m

_g_req = types.ModuleType("requests")
_g_req.post = _fake_post
sys.modules["requests"] = _g_req

P.FCM_SA_PATH = str(RAIZ / "package.json")   # un archivo que existe
P.FCM_PROJECT = "mypump-prod"
P._fcm_cred = None

_fake_post.resp = (200, "")
ok, err, baja = P.enviar_fcm("device-123", "Mati", "te contesté", "chat")
check("200 → éxito", (ok, err, baja) == (True, None, False), f"{ok} {err}")
check("pega al proyecto correcto",
      enviado["url"].endswith("/v1/projects/mypump-prod/messages:send"), enviado.get("url"))
msg = enviado["body"]["message"]
# ── EL AVISO TIENE QUE VERSE ────────────────────────────────────────────────
# Esta asercion decia lo contrario hasta el 29-ago ("manda data y NO
# notification"), y estaba mal por una premisa falsa que yo mismo escribi: que
# con `notification` el tap no podia abrir el chat.
#
# Lo que pasaba de verdad con data-only: el plugin de Capacitor solo llama a
# notificationManager.notify() adentro de `if (notification != null)`
# (PushNotificationsPlugin.java:246-282). Con data-only ese bloque es null, no
# entra nunca, y lo unico que hace es emitir `pushNotificationReceived` — un
# evento que en toda la app NO ESCUCHA NADIE.
#
# Y FCM contesta 200 igual, asi que el ledger anotaba "entregado" y en el
# telefono no aparecia nada. Un test verde sobre una feature que no existia.
check("manda el bloque notification, que es lo que hace que se VEA",
      "notification" in msg,
      "sin notification, el plugin nunca postea nada y el aviso muere en silencio")
check("el titulo y el cuerpo van adentro de notification",
      msg.get("notification", {}).get("title") == "Mati"
      and msg["notification"]["body"] == "te contesté")
# El deep link no se pierde: handleOnNewIntent (:58-77) vuelca todas las claves
# del intent —`destino` incluido— en notification.data antes de disparar
# pushNotificationActionPerformed, que es el listener que si existe.
check("el destino sigue viajando en data, que es lo que sobrevive al tap",
      msg["data"]["destino"] == "chat")
# Nombrar un canal que la app no creo hace que Android 8+ descarte el aviso sin
# decir nada. Si alguien agrega channel_id, que sea a proposito.
check("no declara channel_id",
      "channel_id" not in msg["android"].get("notification", {}),
      "un canal inexistente = Android descarta la notificacion en silencio")
check("prioridad alta", msg["android"]["priority"] == "high",
      "sin high, Doze puede demorar el aviso hasta la mañana siguiente")

_fake_post.resp = (404, '{"error":{"status":"NOT_FOUND"}}')
ok, err, baja = P.enviar_fcm("muerto", "t", "c", None)
check("404 → da de baja el device", (ok, baja) == (False, True),
      "sin la baja, un token muerto se reintenta para siempre")

_fake_post.resp = (200, "")
P._fcm_cred = None
ok, _, _ = P.enviar_fcm("d", "t", "c", None)
check("destino por defecto = chat", enviado["body"]["message"]["data"]["destino"] == "chat")

_fake_post.resp = (500, "boom")
ok, err, baja = P.enviar_fcm("d", "t", "c", None)
check("500 → falla pero NO da de baja", (ok, baja) == (False, False),
      "un error temporal de Google no puede borrar el device del cliente")

# ── 4. El aviso tiene que VERSE, no solo llegar ─────────────────────────────
#
# El bloque `notification` de push.py es el primero de DOS candados que tiene la
# unica llamada a notificationManager.notify() del plugin
# (PushNotificationsPlugin.java:246-282):
#
#     if (notification != null) {                 ← candado 1, push.py
#         String[] presentation = getConfig().getArray("presentationOptions");
#         if (presentation != null) {             ← candado 2, capacitor.config
#             if (presentationList.contains("alert") || ...) {
#                 notificationManager.notify(...)
#
# Faltaban los dos. El segundo solo afecta el PRIMER PLANO —con la app en
# segundo plano el aviso lo postea el SDK de Firebase y este campo no
# interviene—, y por eso no aparece si uno prueba con la app cerrada.
print("\n4. El aviso se ve, no solo llega")

_cap = json.loads((RAIZ / "capacitor.config.json").read_text(encoding="utf-8"))
_po = _cap.get("plugins", {}).get("PushNotifications", {}).get("presentationOptions")
check("capacitor.config declara presentationOptions", _po is not None,
      "sin el campo, getArray() devuelve null y el plugin NUNCA postea en primer plano")
check("presentationOptions habilita el aviso visible",
      bool(_po) and any(o in _po for o in ("alert", "banner", "list")),
      "el plugin solo postea si contiene alert, banner o list")

# El ícono. Sin la meta-data, Firebase usa el del launcher, y desde Android 5 la
# barra de estado lo aplasta a una silueta por el canal alfa: un ícono opaco y a
# color sale como un CUADRADO BLANCO.
_manifest = (RAIZ / "android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
check("el manifest declara el ícono del aviso",
      "com.google.firebase.messaging.default_notification_icon" in _manifest,
      "sin esto el aviso sale como un cuadrado blanco en la barra de estado")
check("apunta a ic_stat_mypump",
      "@drawable/ic_stat_mypump" in _manifest)

_faltan = [d for d in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")
           if not (RAIZ / f"android/app/src/main/res/drawable-{d}/ic_stat_mypump.png").exists()]
check("el drawable existe en las 5 densidades", not _faltan,
      f"faltan: {', '.join(_faltan)} — el build falla al resolver @drawable")

# Y que sea una silueta de verdad: blanco puro con alfa variable. Si alguien lo
# reemplaza por el logo a color, esto se pone rojo antes de que lo vean los 62.
try:
    from PIL import Image
    _ic = Image.open(RAIZ / "android/app/src/main/res/drawable-xxhdpi/ic_stat_mypump.png").convert("RGBA")
    _r, _g, _b, _a = _ic.split()
    _opaco = _a.getextrema()[1]
    _colorido = any(c.getextrema() != (255, 255) for c in (_r, _g, _b))
    check("el ícono es una silueta blanca, no el logo a color",
          _opaco > 0 and not _colorido,
          "Android lo aplasta con el alfa; cualquier color se pierde y queda un bloque")
    # El relleno se mide DENTRO de la caja del dibujo, no sobre el icono entero.
    #
    # La primera version de este check miraba el icono completo con un umbral de
    # 90%, y dejo pasar un cuadrado blanco solido: como el logo se escala al 75%
    # del lienzo, un bloque macizo da ~56% y aprobaba. Lo vi recien al renderizar
    # el PNG y mirarlo. Dentro de su caja, en cambio, un bloque da ~100% y el
    # line-art del logo da ~35%: ahi los dos casos no se pisan.
    _caja = _a.point(lambda p: 255 if p > 8 else 0).getbbox()
    _rec = _a.crop(_caja)
    _relleno = sum(1 for p in _rec.get_flattened_data() if p > 8) / (_rec.width * _rec.height)
    check("el ícono es el logo, no un bloque macizo",
          _relleno < 0.65,
          f"relleno {_relleno:.0%} dentro de su caja: en la barra se ve un cuadrado blanco")
except ImportError:
    print("  · (sin Pillow: no se pudo inspeccionar el ícono)")

print()
if fallas:
    print(f"✗ {fallas} fallo(s): Android puede quedarse sin push otra vez\n")
    sys.exit(1)
print("✓ Android tiene push por las dos vías, y el aviso se ve\n")
