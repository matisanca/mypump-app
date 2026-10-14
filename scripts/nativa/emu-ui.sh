#!/bin/zsh
# Las pruebas instrumentadas de Android en el emulador (AVD nativa36) y las capturas de evidencia, en claro y en oscuro:
#   1. borra las capturas viejas del emulador (/data/local/tmp/mypump-capturas);
#   2. corre `connectedDebugAndroidTest`: todas (interfaz, Keystore y el WebView del legado) o solo las clases pedidas;
#   3. baja las capturas y el reporte a ~/Developer/nativa-evidencia/android-ui/<fecha>/.
# Sin tokens: las de interfaz contestan con el ServidorDePrueba (las respuestas grabadas de test-nativa-real), nunca la red.
# Uso: scripts/nativa/emu-ui.sh [serial] [clases, separadas por coma]
#   ej. scripts/nativa/emu-ui.sh emulator-5554 com.pumpteam.mypump.ui.CapturasUiTest
set -e
SERIAL=${1:-emulator-5554}
CLASES=${2:-}
export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}
export ANDROID_SERIAL=$SERIAL
adb() { "$ANDROID_HOME/platform-tools/adb" -s $SERIAL "$@" }
RAIZ=${0:A:h}/../..
OUT=~/Developer/nativa-evidencia/android-ui/$(date +%Y%m%d-%H%M%S)

adb shell rm -rf /data/local/tmp/mypump-capturas
ARGS=()
[ -n "$CLASES" ] && ARGS=(-Pandroid.testInstrumentationRunnerArguments.class=$CLASES)
FALLO=0
( cd $RAIZ/apps/android && ./gradlew :app:connectedDebugAndroidTest $ARGS ) || FALLO=1

mkdir -p $OUT
adb pull /data/local/tmp/mypump-capturas/. $OUT/ >/dev/null 2>&1 || true
cp -R $RAIZ/apps/android/app/build/reports/androidTests/connected/debug $OUT/reporte 2>/dev/null || true
# La barra de estado vuelve a la normal (las pruebas la dejan en 9:41 con la batería llena).
adb shell am broadcast -a com.android.systemui.demo -e command exit >/dev/null 2>&1 || true
echo "$(ls $OUT/*.png 2>/dev/null | wc -l | tr -d ' ') capturas y el reporte en $OUT"
exit $FALLO
