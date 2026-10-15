#!/usr/bin/env python3 -I
"""Push real de punta a punta en Android (NOT-01 a NOT-04): FCM de verdad, con `push.py` de la Mini y la cuenta de prueba
test-nativa-android. Nunca toca a un cliente: el mensaje va al chat de la cuenta de prueba.

1. Instala la app de debug en el emulador (con Google Play) y le da el permiso de avisos.
2. La abre con la cuenta de prueba (lanzar-emu.py: el token no pasa por la terminal).
3. Espera a que su token de FCM llegue a `mypump_push_devices`.
4. Manda la app al fondo y deja un mensaje de Mati en el chat de la cuenta de prueba: el trigger de la 076 lo encola en
   `mypump_push_cola` con destino `chat`, y `push.py` (launchd, cada 5 minutos) lo manda por FCM.
5. Espera la notificación en el emulador y mira su canal; la toca y mira que se abra el chat con el mensaje.

Uso: python3 -I scripts/nativa/push-android.py <serial>   (antes: ./gradlew :app:assembleDebug)
"""
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

SDK = os.environ.get("ANDROID_HOME", os.path.expanduser("~/Library/Android/sdk"))
ADB = os.path.join(SDK, "platform-tools", "adb")
RAIZ = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PAQUETE = "com.pumpteam.mypump"
CLIENTE = "test-nativa-android"   # la ÚNICA de Android
PY_MINI = "~/agentkit-coach/venv/bin/python"


def adb(serial, *args, check=True):
    return subprocess.run([ADB, "-s", serial, *args], capture_output=True, text=True, check=check).stdout


def consultar(sql):
    """Lectura en la Mini: `_q.py` no hace commit."""
    r = subprocess.run(["ssh", "-o", "ConnectTimeout=10", "mini", f"cd ~/pump-centinela && {PY_MINI} _q.py"],
                       input=sql, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"✗ consulta: {r.stderr[-300:]}")
    return [linea.split(" | ") for linea in r.stdout.strip().splitlines()[1:]]


def aplicar(sql):
    r = subprocess.run(["ssh", "-o", "ConnectTimeout=10", "mini",
                        f"cat > /tmp/push-android.sql && {PY_MINI} ~/_aplicar.py /tmp/push-android.sql"],
                       input=sql, capture_output=True, text=True)
    if r.returncode or "COMMIT" not in r.stdout:
        sys.exit(f"✗ no se aplicó: {r.stdout[-300:]} {r.stderr[-300:]}")


def esperar(que, condicion, limite, cada=5):
    t0 = time.time()
    while time.time() - t0 < limite:
        v = condicion()
        if v is not None and v is not False and (not hasattr(v, "__len__") or len(v) > 0 or hasattr(v, "iter")):
            return v
        time.sleep(cada)
    sys.exit(f"✗ {que} (esperé {limite} s)")


def pantalla(serial):
    adb(serial, "shell", "uiautomator", "dump", "/sdcard/ventana.xml")
    xml = adb(serial, "exec-out", "cat", "/sdcard/ventana.xml")
    return ET.fromstring(xml[xml.index("<?xml"):])


def nodo_con(raiz, texto):
    for n in raiz.iter("node"):
        if texto in (n.get("text") or "") or texto in (n.get("content-desc") or ""):
            return n
    return None


def tocar(serial, nodo):
    x1, y1, x2, y2 = map(int, re.findall(r"\d+", nodo.get("bounds")))
    adb(serial, "shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    serial = sys.argv[1]
    inicio = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S+00")

    # 1 y 2. El permiso antes de abrir: así el arranque registra el token sin pasar por el onboarding de avisos.
    apk = os.path.join(RAIZ, "apps/android/app/build/outputs/apk/debug/app-debug.apk")
    adb(serial, "install", "-r", apk)
    adb(serial, "shell", "pm", "grant", PAQUETE, "android.permission.POST_NOTIFICATIONS", check=False)
    subprocess.run([sys.executable, "-I", os.path.join(RAIZ, "scripts/nativa/lanzar-emu.py"), serial], check=True)

    # 3.
    fila = esperar("el token de FCM no llegó a mypump_push_devices", lambda: consultar(
        f"select left(token, 6), app_version from mypump_push_devices where cliente_id = '{CLIENTE}' "
        f"and plataforma = 'android' and activo and visto_en >= '{inicio}' order by visto_en desc limit 1"), 180)
    print(f"✓ token de FCM registrado: {fila[0][0]}… ({fila[0][1]})")

    # 4. Con la app en el fondo el aviso lo muestra el sistema, con el canal y el ícono del manifest (NOT-02).
    adb(serial, "shell", "input", "keyevent", "KEYCODE_HOME")
    time.sleep(2)
    marca = f"Prueba de push nativa {datetime.now().strftime('%H:%M:%S')}"
    aplicar(f"insert into mypump_comentarios (cliente_id, ambito, autor, contenido) "
            f"values ('{CLIENTE}', 'general', 'coach', '{marca}');")
    cola = consultar(f"select id, estado, destino from mypump_push_cola where cliente_id = '{CLIENTE}' and cuerpo = '{marca}'")
    print(f"✓ mensaje de Mati en el chat de prueba; en la cola: {cola}")
    if not cola or cola[0][1] != "pendiente" or cola[0][2] != "chat":
        sys.exit("✗ el aviso no quedó pendiente con destino chat")

    # 5.
    t0 = time.time()
    esperar("la notificación no llegó al emulador",
            lambda: marca in adb(serial, "shell", "dumpsys", "notification", "--noredact"), 420, 10)
    print(f"✓ llegó la notificación ({time.time() - t0:.0f} s después de encolarla)")
    volcado = adb(serial, "shell", "dumpsys", "notification", "--noredact")
    registro = next((b for b in volcado.split("NotificationRecord(") if marca in b), "")
    canal = re.search(r"channel=(\S+)", registro)
    print(f"  canal: {canal.group(1) if canal else '?'}")
    if not canal or canal.group(1) != "mypump_mensajes":
        sys.exit("✗ no llegó por el canal de los mensajes de Mati")
    estado = consultar(f"select estado, intentos, coalesce(error, '') from mypump_push_cola where id = {cola[0][0]}")
    print(f"  en la cola: {estado}")

    # La cortina se abre con animación: un volcado temprano no la ve (15-oct). Se vuelve a abrir en cada intento.
    def en_la_cortina():
        adb(serial, "shell", "cmd", "statusbar", "expand-notifications")
        time.sleep(3)
        return nodo_con(pantalla(serial), marca)
    aviso = esperar("no encontré el aviso en la cortina", en_la_cortina, 60, 1)
    tocar(serial, aviso)
    time.sleep(3)
    # Con la app recién instalada, arriba queda la bienvenida (los permisos): se cierra y abajo tiene que estar el chat.
    bienvenida = nodo_con(pantalla(serial), "Ahora no")
    if bienvenida is not None:
        tocar(serial, bienvenida)
    raiz = esperar("tocar el aviso no abrió el chat con el mensaje",
                   lambda: (lambda r: r if nodo_con(r, "Escribile a Mati") is not None and nodo_con(r, marca) is not None else None)(pantalla(serial)),
                   30, 2)
    print("✓ tocar el aviso abre el chat, con el mensaje a la vista")
    return 0


if __name__ == "__main__":
    sys.exit(main())
