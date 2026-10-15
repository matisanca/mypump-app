#!/usr/bin/env python3 -I
"""Android cierra MyPump mientras el cliente saca una foto de progreso con la cámara del teléfono (pasa seguido en los
teléfonos con poca memoria: la cámara es otra app). La foto no se tiene que perder.

Lo que hace, en el emulador (con la cámara emulada: `emulator -avd nativa34 -camera-back emulated`):
1. Abre la app de debug con test-nativa-android en Revisión (lanzar-emu.py: el token no pasa por la terminal).
2. Toca una pose, «Sacar foto»: se abre la cámara del sistema (com.android.camera2).
3. Con la cámara adelante, `am kill` mata el proceso de MyPump, que es lo que hace Android con poca memoria.
4. Saca la foto y la confirma: Android vuelve a crear MyPump en un proceso nuevo, con su estado guardado.
5. Comprueba que MyPump volvió en Revisión, que la foto se guardó o quedó en la cola, y que la cámara no dejó la foto
   huérfana en la caché.

El 15-oct encontró que la app volvía en Entreno y la foto quedaba huérfana: la clave del estado guardado dependía de la
identidad de un enum (`Escena`, RaizMyPump.kt). Ojo: sube una foto de verdad a la cuenta de prueba y gasta una de las 12
del día de ese link.

Uso: python3 -I scripts/nativa/camara-muerte-android.py <serial> [carpeta de capturas]   (antes: ./gradlew :app:assembleDebug)
"""
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

SDK = os.environ.get("ANDROID_HOME", os.path.expanduser("~/Library/Android/sdk"))
ADB = os.path.join(SDK, "platform-tools", "adb")
RAIZ = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PAQUETE = "com.pumpteam.mypump"
CAMARA = "com.android.camera2"
POSES = ("Foto de frente", "Foto de perfil", "Foto de espalda")


def adb(serial, *args):
    return subprocess.run([ADB, "-s", serial, *args], capture_output=True, text=True).stdout


def pantalla(serial):
    for _ in range(5):
        adb(serial, "shell", "uiautomator", "dump", "/sdcard/ventana.xml")
        xml = adb(serial, "exec-out", "cat", "/sdcard/ventana.xml")
        if "<?xml" in xml:
            return ET.fromstring(xml[xml.index("<?xml"):])
        time.sleep(1)
    sys.exit("✗ no pude leer la pantalla")


def etiquetas(raiz, paquete=None):
    return [n.get("text") or n.get("content-desc") or "" for n in raiz.iter("node")
            if (paquete is None or n.get("package") == paquete) and (n.get("text") or n.get("content-desc"))]


def buscar(raiz, texto=None, rid=None, paquete=None):
    """El nodo, o None. Ojo: un Element sin hijos es falso en un if; se compara siempre con None."""
    for n in raiz.iter("node"):
        if paquete and n.get("package") != paquete:
            continue
        if rid and (n.get("resource-id") or "").endswith(rid):
            return n
        if texto and texto in (n.get("text"), n.get("content-desc")):
            return n
    return None


def tocar(serial, nodo):
    x1, y1, x2, y2 = map(int, re.findall(r"\d+", nodo.get("bounds")))
    adb(serial, "shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))


def esperar(que, condicion, limite, cada=1.0):
    t0 = time.time()
    while time.time() - t0 < limite:
        v = condicion()
        if v is not None and v is not False:
            return v
        time.sleep(cada)
    sys.exit(f"✗ {que} (esperé {limite:.0f} s)")


def captura(serial, carpeta, nombre):
    if carpeta:
        png = subprocess.run([ADB, "-s", serial, "exec-out", "screencap", "-p"], capture_output=True).stdout
        with open(os.path.join(carpeta, nombre), "wb") as f:
            f.write(png)


def pid(serial):
    return adb(serial, "shell", "pidof", PAQUETE).strip()


def adelante(serial):
    s = adb(serial, "shell", "dumpsys", "activity", "activities")
    m = re.search(r"topResumedActivity=.*? ([\w.]+)/", s) or re.search(r"mResumedActivity: .*? ([\w.]+)/", s)
    return m.group(1) if m else "?"


def en_la_cola(serial):
    """Las claves de la cola de fotos en disco (build de debug: run-as)."""
    rutas = adb(serial, "shell", f"run-as {PAQUETE} find . -name fotos-pendientes.json").split()
    if not rutas:
        return []
    return re.findall(r'"(\d{4}-\d{2}-\d{2}\|[a-z]+)"', adb(serial, "shell", f"run-as {PAQUETE} cat {rutas[0]}"))


def huerfanas(serial):
    return [l for l in adb(serial, "shell", f"run-as {PAQUETE} ls cache/camara").split() if l.endswith(".jpg")]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    serial = sys.argv[1]
    carpeta = sys.argv[2] if len(sys.argv) > 2 else None
    if carpeta:
        os.makedirs(carpeta, exist_ok=True)
    if "true" not in adb(serial, "shell", "pm", "has-feature", "android.hardware.camera.any"):
        sys.exit("✗ el emulador no tiene cámara: arrancalo con -camera-back emulated")
    adb(serial, "shell", "pm", "grant", PAQUETE, "android.permission.POST_NOTIFICATIONS")
    adb(serial, "shell", "pm", "grant", CAMARA, "android.permission.CAMERA")
    subprocess.run([sys.executable, "-I", os.path.join(RAIZ, "scripts/nativa/lanzar-emu.py"), serial, "revision"], check=True)

    # 1. Revisión, con la hoja de la primera vez cerrada si aparece. Se elige una pose sin foto, o la de frente.
    def poses():
        r = pantalla(serial)
        ahora_no = buscar(r, texto="Ahora no")
        if ahora_no is not None:
            tocar(serial, ahora_no)
            return None
        return r if any(e.startswith(POSES) for e in etiquetas(r, PAQUETE)) else None
    r = esperar("no aparecieron las poses en Revisión", poses, 60, 2)
    vacias = [p for p in POSES if buscar(r, texto=p) is not None]
    pose = vacias[0] if vacias else next(e for e in etiquetas(r, PAQUETE) if e.startswith(POSES[0]))
    print(f"pose: «{pose}»" + ("" if vacias else " (ya tenía foto: se reemplaza)"))
    captura(serial, carpeta, "1-revision.png")

    # 2. «Sacar foto»: la cámara del sistema.
    tocar(serial, buscar(r, texto=pose))
    tocar(serial, esperar("no apareció «Sacar foto»", lambda: buscar(pantalla(serial), texto="Sacar foto"), 10))
    esperar("no se abrió la cámara", lambda: adelante(serial) == CAMARA or None, 20)
    time.sleep(3)
    antes = pid(serial)

    # 3. Android cierra MyPump con la cámara adelante.
    adb(serial, "shell", "am", "kill", PAQUETE)
    esperar("am kill no cerró MyPump", lambda: not pid(serial) or None, 10)
    print(f"✓ MyPump cerrada con la cámara abierta (pid {antes})")

    # 4. La foto, y confirmarla.
    tocar(serial, esperar("no encontré el disparador de la cámara",
                          lambda: buscar(pantalla(serial), rid="shutter_button", paquete=CAMARA), 15))
    captura(serial, carpeta, "2-camara.png")
    tocar(serial, esperar("la cámara no ofreció confirmar la foto",
                          lambda: buscar(pantalla(serial), rid="done_button", paquete=CAMARA), 20))

    # 5. MyPump vuelve en un proceso nuevo, en Revisión, con la foto guardada o en la cola.
    esperar("MyPump no volvió adelante", lambda: adelante(serial) == PAQUETE or None, 30)
    nuevo = pid(serial)
    print(f"✓ MyPump volvió en un proceso nuevo (pid {nuevo})")
    r = esperar("la foto no se guardó ni quedó en la cola", lambda: (lambda r: r if (
        any(e.startswith("Listo, guardada") or e.startswith("Hoy ya subiste muchas fotos") for e in etiquetas(r, PAQUETE))
        or en_la_cola(serial)) else None)(pantalla(serial)), 45, 2)
    captura(serial, carpeta, "3-vuelta.png")
    textos = etiquetas(r, PAQUETE)
    if "Semana del" not in " ".join(textos):
        sys.exit("✗ MyPump no volvió en Revisión: " + " | ".join(textos[:8]))
    print("✓ volvió en Revisión: " + next((e for e in textos if e.startswith(("Listo", "Hoy ya", "Sin conexión"))), "(en la cola)"))
    cola = en_la_cola(serial)
    if cola:
        print(f"  en la cola: {cola}")
    # Reducida la foto, el archivo de la cámara se borra (esté subida o en la cola): si queda, nadie la recibió.
    resto = huerfanas(serial)
    if resto:
        sys.exit(f"✗ la cámara dejó fotos huérfanas en la caché: {resto}")
    print("✓ la foto no se perdió")
    return 0


if __name__ == "__main__":
    sys.exit(main())
