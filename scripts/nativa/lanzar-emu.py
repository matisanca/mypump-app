#!/usr/bin/env python3 -I
"""Abre la app de Android en el emulador con la cuenta de prueba test-nativa-android, como si se tocara su link de
WhatsApp (gemelo de lanzar-sim.sh). El token se lee ACÁ ADENTRO de ~/Developer/nativa-evidencia/privado/cuentas-prueba.json
y nunca se imprime ni viaja por argumentos (los ve `ps`): va por la entrada estándar de `adb shell`.

Uso: python3 -I scripts/nativa/lanzar-emu.py <serial> [escena]   (escena: train, diet, chat, revision, progress)
Instala antes app/build/outputs/apk/debug/app-debug.apk si existe (./gradlew :app:assembleDebug).
"""
import json
import os
import subprocess
import sys

REGISTRO = os.path.expanduser("~/Developer/nativa-evidencia/privado/cuentas-prueba.json")
CUENTA = "test-nativa-android"   # la ÚNICA de Android: las otras son de otros agentes
ADB = os.path.join(os.environ.get("ANDROID_HOME", os.path.expanduser("~/Library/Android/sdk")), "platform-tools", "adb")
APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "apps", "android", "app", "build", "outputs", "apk", "debug", "app-debug.apk")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    serial = sys.argv[1]
    escena = sys.argv[2] if len(sys.argv) > 2 else None
    if escena and escena not in {"train", "diet", "chat", "revision", "progress"}:
        print(f"escena desconocida: {escena}")
        return 2
    token = json.load(open(REGISTRO))[CUENTA]["token"]
    if os.path.isfile(APK):
        subprocess.run([ADB, "-s", serial, "install", "-r", APK], check=True, stdout=subprocess.DEVNULL)
    link = f"https://app.mypumpteam.com/?t={token}" + (f"&scene={escena}" if escena else "")
    # Por la entrada estándar: en la Mac el token no queda en los argumentos de ningún proceso.
    comando = f"am start -W -a android.intent.action.VIEW -d '{link}' -n com.pumpteam.mypump/.MainActivity >/dev/null\n"
    r = subprocess.run([ADB, "-s", serial, "shell"], input=comando.encode(), stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    if r.returncode != 0:
        # El error de adb no incluye el link, pero por las dudas no se reenvía: solo el código.
        print(f"✗ no se pudo abrir la app (adb salió con {r.returncode})")
        return 1
    print(f"✓ MyPump abierta en {serial} con {CUENTA}" + (f", escena {escena}" if escena else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
