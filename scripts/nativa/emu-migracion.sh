#!/bin/zsh
# Prueba de punta a punta de la migración del almacenamiento viejo en el emulador de Android (gemelo de
# sim-migracion.sh), sin tocar la pantalla:
#   1. la Capacitor de debug (compilar-capacitor-android.sh: android/ del repo, sin tocarlo) abre sin cuenta; por DevTools
#      se siembra el token de test-nativa-android y una cola chica, y se espera a que esté EN el leveldb;
#   2. con red, la Capacitor manda ella misma esa cola (así se prueba que el formato sembrado es el de la web) y deja su
#      copia offline;
#   3. sin red y con la app vieja fuera de la página (un archivo estático del mismo origen), se siembra lo que va a levantar
#      la nativa: una cola con ops con y sin sesión, una sesión en curso, el descanso, una cola anon y una de un token
#      rotado, ajustes, 1 MB, unicode, un nulo y un surrogate suelto. Se espera a que esté en el leveldb y se cierra;
#   4. la nativa de debug (firmada con la MISMA clave de debug: update real) se instala ENCIMA y arranca con red: Fase L,
#      carga, Fase R, recibo y escritura de vuelta. Se mira registro.log, los archivos (run-as) y la base;
#   5. segundo arranque: confirma la escritura y no trae nada; tercer arranque: ni siquiera lee;
#   6. la Capacitor otra vez encima (plan B): lo que quedó en su localStorage, y con red no resucita nada.
# El token nunca pasa por acá: lo lee emu_migracion.py. Informe en ~/Developer/nativa-evidencia/migracion-android/.
# Uso: scripts/nativa/emu-migracion.sh <serial>   (desinstala MyPump de ese emulador; usa el modo avión)
set -e
SERIAL=${1:?serial, ej. emulator-5554}
export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}
adb() { "$ANDROID_HOME/platform-tools/adb" -s $SERIAL "$@" }
EV=~/Developer/nativa-evidencia
RAIZ=${0:A:h}/../..
CAP=$EV/dd/cap-android/cap-main-debug.apk
NAT=$RAIZ/apps/android/app/build/outputs/apk/debug/app-debug.apk
PY=${0:A:h}/emu_migracion.py
CDP=${0:A:h}/cdp-localstorage.mjs
OUT=$EV/migracion-android/$(date +%Y%m%d-%H%M%S)
PKG=com.pumpteam.mypump
PUERTO=9334
mkdir -p $OUT
[ -f $CAP ] || ${0:A:h}/compilar-capacitor-android.sh
( cd $RAIZ/apps/android && ./gradlew -q :app:assembleDebug )

devtools() {   # espera la página https://localhost del WebView de la app viva y le reenvía el socket de DevTools
  local pid=""
  for i in {1..40}; do
    pid=$(adb shell pidof $PKG | tr -d '\r')
    if [ -n "$pid" ]; then
      adb forward tcp:$PUERTO localabstract:webview_devtools_remote_$pid >/dev/null 2>&1 || true
      curl -s --max-time 2 http://127.0.0.1:$PUERTO/json 2>/dev/null | grep -q '"url": *"https://localhost' && return 0
    fi
    sleep 1
  done
  echo "✗ sin DevTools de la Capacitor"; return 1
}
registro() { adb shell run-as $PKG cat files/legado/registro.log 2>/dev/null | tr -d '\r' }
esperar_registro() {   # $1 = texto, $2 = segundos
  local n=0
  until registro | grep -q "$1"; do
    (( n += 2 )); (( n > $2 )) && { echo "✗ no apareció «$1» en el registro de la nativa"; return 1 }
    sleep 2
  done
}
avion() { adb shell cmd connectivity airplane-mode $1 >/dev/null; sleep 4 }
cerrar() { adb shell am force-stop $PKG; sleep 2 }
abrir() { adb shell am start -n $PKG/.MainActivity >/dev/null }

avion disable
adb uninstall $PKG >/dev/null 2>&1 || true

echo "── 1. Capacitor de debug sin cuenta: el token y una cola chica, por DevTools"
adb install $CAP >/dev/null
abrir
devtools
sleep 3
python3 -I $PY semilla-capacitor $PUERTO $OUT
python3 -I $PY esperar-semilla $SERIAL token $OUT 300
cerrar

echo "── 2. La Capacitor con red manda ella su cola"
abrir
sleep 30   # carga la cuenta, manda la cola y guarda la copia offline
devtools
python3 -I $PY almacen $PUERTO $OUT capacitor
cerrar
python3 -I $PY backend $OUT capacitor

echo "── 3. Sin red, con la app vieja fuera de la página: lo que va a levantar la nativa"
avion enable
abrir
devtools
# Un archivo estático del mismo origen, sin scripts: la app vieja deja de correr y nada pisa lo que se siembra. (Una ruta
# que no existe no sirve: la Capacitor la contesta sin cuerpo y el WebView muestra chrome-error://, sin origen.)
node $CDP $PUERTO navegar https://localhost/manifest.json > $OUT/pagina-semilla.json
cat $OUT/pagina-semilla.json; echo
grep -q '"origin":"https://localhost"' $OUT/pagina-semilla.json || { echo "✗ la página para sembrar no quedó en https://localhost"; exit 1 }
python3 -I $PY semilla-nativa $PUERTO $OUT
python3 -I $PY esperar-semilla $SERIAL nota $OUT 420
cerrar
avion disable
python3 -I $PY backend $OUT sembrado

echo "── 4. La nativa ENCIMA (update real: misma clave de debug)"
adb install -r $NAT >/dev/null
T0=$(date +%s)
abrir
esperar_registro "escritura de vuelta, corrida" 240 || true
python3 -I $PY tiempo $OUT nativa_hasta_escritura_s $(( $(date +%s) - T0 ))
python3 -I $PY esperar-marca $SERIAL $OUT 180 || true
cerrar
python3 -I $PY nativa $SERIAL $OUT nativa
python3 -I $PY backend $OUT nativa

echo "── 5. Segundo arranque: confirma la escritura; tercero: no lee"
abrir
esperar_registro "Fase L corrida 2" 120 || true
sleep 15
cerrar
python3 -I $PY nativa $SERIAL $OUT segundo
python3 -I $PY backend $OUT segundo
abrir
sleep 25
cerrar
python3 -I $PY nativa $SERIAL $OUT tercero

echo "── 6. La Capacitor otra vez encima (plan B)"
avion enable
adb install -r -d $CAP >/dev/null
abrir
devtools
sleep 5   # index.html salta a cliente.html: que termine
python3 -I $PY almacen $PUERTO $OUT vuelta
cerrar
avion disable
abrir
sleep 30   # con red: si algo hubiera quedado en su cola, lo mandaría
cerrar
python3 -I $PY backend $OUT vuelta

echo "── Verificación"
set +e
python3 -I $PY verificar $OUT
R=$?
echo "informe: $OUT/informe.md"
exit $R
