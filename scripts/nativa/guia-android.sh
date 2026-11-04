#!/bin/zsh
# «Tu guía» en un emulador de Android: instala el APK de debug y el de pruebas ya compilados, corre las clases pedidas con
# `am instrument` (sin Gradle, para no pisar otra corrida) y baja las capturas a ~/Developer/nativa-evidencia/guia/<carpeta>/
# con el prefijo and-<nombre>-.
#
# Uso: scripts/nativa/guia-android.sh <serial> <nombre> <carpeta: maqueta|e2e|lado-a-lado> <clase[#método],…>
#   ej. scripts/nativa/guia-android.sh emulator-5600 chico maqueta com.pumpteam.mypump.ui.GuiaUiTest
#
# Para GuiaRealUiTest (contra el servidor, con test-nativa-android) el token NO va por argumentos: se lee del registro
# privado adentro de este script y se escribe por la entrada estándar en la carpeta privada de la app de pruebas, que la
# prueba lee y borra. Compilar antes: ./gradlew :app:assembleDebug :app:assembleDebugAndroidTest
set -e
SERIAL=$1; NOMBRE=$2; CARPETA=$3; CLASES=$4
[ -z "$CLASES" ] && { echo "uso: $0 <serial> <nombre> <carpeta> <clases>"; exit 2; }
export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
adb() { "$ANDROID_HOME/platform-tools/adb" -s $SERIAL "$@" }
RAIZ=${0:A:h}/../..
APKS=$RAIZ/apps/android/app/build/outputs/apk
OUT=~/Developer/nativa-evidencia/guia/$CARPETA
mkdir -p $OUT

adb shell rm -rf /data/local/tmp/mypump-capturas
adb uninstall com.pumpteam.mypump >/dev/null 2>&1 || true
adb uninstall com.pumpteam.mypump.test >/dev/null 2>&1 || true
adb install -r -t $APKS/debug/app-debug.apk >/dev/null
adb install -r -t $APKS/androidTest/debug/app-debug-androidTest.apk >/dev/null

if [[ $CLASES == *GuiaRealUiTest* ]]; then
  python3 -I - "$SERIAL" <<'PY'
import json, os, subprocess, sys
reg = json.load(open(os.path.expanduser('~/Developer/nativa-evidencia/privado/cuentas-prueba.json')))
tok = reg['test-nativa-android']['token']
adb = os.path.expanduser('~/Library/Android/sdk/platform-tools/adb')
# A la carpeta de la app (la prueba corre en su proceso): por stdin, nunca en la línea de comandos.
subprocess.run([adb, '-s', sys.argv[1], 'shell', 'run-as com.pumpteam.mypump sh -c "mkdir -p files && cat > files/guia-e2e-token"'], input=tok.encode(), check=True)
PY
fi

LOG=$OUT/and-$NOMBRE-$(date +%H%M%S)-instrument.txt
FALLO=0
adb shell am instrument -w -r -e class "$CLASES" com.pumpteam.mypump.test/androidx.test.runner.AndroidJUnitRunner > $LOG 2>&1 || FALLO=1
grep -q "FAILURES!!!\|INSTRUMENTATION_FAILED\|Process crashed" $LOG && FALLO=1
adb shell run-as com.pumpteam.mypump rm -f files/guia-e2e-token >/dev/null 2>&1 || true

TMP=$(mktemp -d)
adb pull /data/local/tmp/mypump-capturas/. $TMP/ >/dev/null 2>&1 || true
for f in $TMP/*.png(N); do mv $f $OUT/and-$NOMBRE-${f:t}; done
rm -rf $TMP
adb shell am broadcast -a com.android.systemui.demo -e command exit >/dev/null 2>&1 || true
grep -E "^OK|^Tests run|FAILURES" $LOG | tail -2
echo "capturas en $OUT (and-$NOMBRE-*), registro en $LOG"
exit $FALLO
