#!/bin/zsh
# Capturas para Google Play de la 2.0.0 nativa (gemelo de capturas-tienda-ios.sh): teléfono (AVD nativa36b) y tablet de 10"
# (nativa35), en claro y oscuro. Entreno, un ejercicio abierto con series, Dieta, Revisión y Progreso.
#
# - Los datos: la prueba instrumentada CapturasTiendaTest con el ServidorDePrueba (las respuestas grabadas de la cuenta de
#   prueba test-nativa-real, con un token inventado): nunca un cliente, y la API nunca va a la red. Solo bajan de internet las
#   fotos PÚBLICAS del catálogo de ejercicios (el bucket exercise-images), así las cards no quedan con el marcador gris.
# - El tamaño: Play no acepta capturas con un lado más del doble que el otro (1080×2400 lo es) y pide 9:16 o 16:9 para
#   tablets y para las recomendaciones. Por eso la pantalla se achica a 9:16 con `wm size` mientras se capturan (teléfono
#   1080×1920; tablet 1440×2560, parada como el iPad) y vuelve a la suya al terminar. TAMANO=nativo las saca con la
#   pantalla entera (no sirven para subir).
# - La barra de estado: el modo demo de SystemUI (9:41, batería llena, wifi lleno sin «!», sin celular ni notificaciones).
#   Al terminar queda apagado.
# Cada AVD arranca sin ventana, de a uno, y se apaga al terminar (si ya estaba prendido en su puerto, se usa y se deja).
# Uso: scripts/nativa/capturas-tienda-android.sh [carpeta-salida] [telefono|tablet10]
set -e
setopt null_glob   # un glob sin archivos es una lista vacía, no un error que corta el script sin restaurar
export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}
EV=~/Developer/nativa-evidencia
OUT=${1:-$EV/tienda-android/$(date +%Y%m%d-%H%M%S)}
SOLO=${2:-}
RAIZ=${0:A:h}/../..
APK=$RAIZ/apps/android/app/build/outputs/apk/debug/app-debug.apk
APK_PRUEBAS=$RAIZ/apps/android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
EMU=$ANDROID_HOME/emulator/emulator
CARPETA=/data/local/tmp/mypump-tienda
# avd puerto prefijo tamaño-9:16
DISPOSITIVOS=(
  "nativa36b 5560 telefono 1080x1920"
  "nativa35 5562 tablet10 1440x2560"
)
mkdir -p $OUT
( cd $RAIZ/apps/android && ./gradlew -q :app:assembleDebug :app:assembleDebugAndroidTest )

SERIAL=""
PRENDIDO_ACA=0
adb() { "$ANDROID_HOME/platform-tools/adb" -s $SERIAL "$@" }

# La pantalla y la barra como estaban, y el emulador apagado si lo prendió este script. También si algo falla en el medio.
restaurar() {
  [ -z "$SERIAL" ] && return 0
  adb shell am broadcast -a com.android.systemui.demo -e command exit >/dev/null 2>&1 || true
  adb shell settings put global sysui_demo_allowed 0 >/dev/null 2>&1 || true
  adb shell wm size reset >/dev/null 2>&1 || true
  adb shell cmd uimode night no >/dev/null 2>&1 || true
  if [ $PRENDIDO_ACA = 1 ]; then
    adb emu kill >/dev/null 2>&1 || true
    sleep 5
  fi
  SERIAL=""
}
trap restaurar EXIT INT TERM

for d in $DISPOSITIVOS; do
  set -- ${=d}
  avd=$1; puerto=$2; prefijo=$3; tam=$4
  [ -n "$SOLO" ] && [ "$SOLO" != "$prefijo" ] && continue
  SERIAL=emulator-$puerto
  PRENDIDO_ACA=0
  if ! "$ANDROID_HOME/platform-tools/adb" devices | grep -q "^${SERIAL}[[:space:]]*device"; then
    echo "── $avd: arrancando en $puerto (sin ventana)"
    mkdir -p $EV/logs
    nohup $EMU -avd $avd -port $puerto -no-window -no-audio -no-boot-anim -no-snapshot-save > $EV/logs/emu-$avd-tienda.log 2>&1 &
    PRENDIDO_ACA=1
  fi
  adb wait-for-device
  n=0
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    (( n += 3 )); (( n > 300 )) && { echo "✗ $avd no terminó de arrancar"; exit 1 }
    sleep 3
  done
  echo "── $avd ($SERIAL): Android $(adb shell getprop ro.build.version.release | tr -d '\r'), $(adb shell wm size | tail -1 | tr -d '\r')"
  adb shell svc power stayon true
  adb shell input keyevent KEYCODE_WAKEUP
  adb shell wm dismiss-keyguard
  [ "${TAMANO:-}" = "nativo" ] || adb shell wm size $tam
  sleep 2
  adb install -r $APK >/dev/null
  adb install -r $APK_PRUEBAS >/dev/null
  adb shell rm -rf $CARPETA
  # La barra la arma la prueba (después de la de PruebaUi); esto es para que no se vea otra cosa mientras arranca.
  adb shell settings put global sysui_demo_allowed 1
  adb shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null
  adb logcat -c
  echo "   CapturasTiendaTest (claro y oscuro)…"
  RES=$(adb shell am instrument -w -e tienda 1 -e class com.pumpteam.mypump.ui.CapturasTiendaTest \
    com.pumpteam.mypump.test/androidx.test.runner.AndroidJUnitRunner | tr -d '\r')
  echo "$RES" > $OUT/$prefijo-instrumentacion.txt
  # Cuántas fotos del catálogo bajaron (y cuántas otras URLs se bloquearon): lo anota la prueba en el logcat.
  adb logcat -d -s MyPumpTienda:I | grep "fotos del catálogo" | sed 's/^.*MyPumpTienda: //' > $OUT/$prefijo-fotos.txt || true
  if ! echo "$RES" | grep -q "^OK (2 tests)"; then
    echo "✗ la prueba no pasó en $avd (detalle en $OUT/$prefijo-instrumentacion.txt):"
    echo "$RES" | grep -E "^(FAILURES|Tests run|[0-9]+\)|java\.|.*Error)" | head -20
    exit 1
  fi
  TMP=$(mktemp -d)
  adb pull $CARPETA/. $TMP/ >/dev/null
  for f in $TMP/*.png; do mv $f $OUT/$prefijo-$(basename $f); done
  rm -rf $TMP
  adb shell rm -rf $CARPETA
  restaurar
  echo "✓ $avd"
done
trap - EXIT INT TERM

# Lo que pide Play: lado mayor ≤ 2 × lado menor; tablets y recomendaciones, 9:16 o 16:9 de 1080 a 7680 px.
for f in $OUT/*.png; do
  echo "$(basename $f): $(sips -g pixelWidth -g pixelHeight $f | awk '/pixel/ {printf "%s ", $2}')"
done
echo "capturas: $OUT"
