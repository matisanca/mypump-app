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
check("manda data y NO notification", "data" in msg and "notification" not in msg,
      "con `notification` Android arma el aviso solo y el tap no puede abrir el chat")
check("el destino viaja", msg["data"]["destino"] == "chat")
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

print()
if fallas:
    print(f"✗ {fallas} fallo(s): Android puede quedarse sin push otra vez\n")
    sys.exit(1)
print("✓ Android tiene push por las dos vías\n")
