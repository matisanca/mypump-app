#!/bin/zsh
# Prueba del almacenamiento viejo en Android (riesgo n.º 1, ver docs/NATIVA_SPIKE_ALMACENAMIENTO.md), sin tocar la
# pantalla: Capacitor de debug → se siembra la verdad por DevTools con la app viva → se cierra y se relee (lo que quedó
# en disco) → la espía se instala ENCIMA (update real, misma firma de debug) → lee por un WebView nativo en el mismo
# origen y escribe la marca → cierre forzado tras <espera> s → segundo arranque: ¿sobrevivió la marca?
# Uso: scripts/nativa/spike-legado-android.sh <serial adb> [segundos de espera antes del cierre forzado]
set -e
SERIAL=${1:?serial, ej. emulator-5554}; ESPERA=${2:-10}
export ANDROID_HOME=$HOME/Library/Android/sdk
ADB="$ANDROID_HOME/platform-tools/adb -s $SERIAL"
EV=~/Developer/nativa-evidencia
CAP=$EV/dd/cap-android/cap-main-debug.apk
ESPIA=${0:A:h}/../../apps/android-spike/app/build/outputs/apk/debug/app-debug.apk
CDP=${0:A:h}/cdp-localstorage.mjs
PKG=com.pumpteam.mypump
OUT=$EV/spike/android-$($ADB shell getprop ro.build.version.sdk | tr -d '\r')-espera$ESPERA; mkdir -p $OUT
PUERTO=9333

devtools() {   # adb forward al socket de DevTools del WebView de la app viva
  local pid=$($ADB shell pidof $PKG | tr -d '\r')
  $ADB forward tcp:$PUERTO localabstract:webview_devtools_remote_$pid >/dev/null
}
informe() {   # espera el informe de la espía y lo copia
  for i in {1..60}; do $ADB shell run-as $PKG test -f files/spike-listo && break; sleep 1; done
  $ADB shell run-as $PKG cat files/spike-informe.json > $1
  $ADB shell run-as $PKG rm -f files/spike-listo
}

$ADB uninstall $PKG >/dev/null 2>&1 || true
$ADB install $CAP >/dev/null
$ADB shell am start -n $PKG/.MainActivity >/dev/null
sleep 15   # que cargue la web (theme.js escribe mypump-theme)
devtools
node $CDP $PUERTO sembrar $EV/spike/semilla.json > $OUT/sembrado.json
sleep 15   # Chromium guarda el localStorage en tandas
$ADB shell am force-stop $PKG
$ADB shell am start -n $PKG/.MainActivity >/dev/null
sleep 15
devtools
node $CDP $PUERTO leer > $OUT/verdad.json   # lo que la Capacitor ve después de un cierre: lo que quedó en disco
$ADB shell am force-stop $PKG

$ADB install -r $ESPIA >/dev/null   # update: mismo paquete, misma firma de debug
for n in 1 2; do
  $ADB shell am start -n $PKG/.spike.Espia >/dev/null
  informe $OUT/informe-$n.json
  sleep $ESPERA
  $ADB shell am force-stop $PKG
done

python3 - $OUT <<'PY'
import json, os, sys
out = sys.argv[1]
verdad = json.load(open(os.path.join(out, 'verdad.json')))
for n in (1, 2):
    inf = json.load(open(os.path.join(out, f'informe-{n}.json')))
    v = inf.get('valores') or {}
    difiere = [k for k in verdad if v.get(k) != verdad[k]]
    extra = sorted(set(v) - set(verdad))
    print(f"arranque {n} (Android {inf.get('android')}, WebView {inf.get('webview')}, origen {inf.get('origen')}): "
          f"{len(verdad) - len(difiere)}/{len(verdad)} iguales · extra {extra} · marca previa {'sí' if inf.get('previa') else 'no'} · {inf.get('ms')} ms")
    if difiere: print('  difiere:', difiere[:5])
PY
