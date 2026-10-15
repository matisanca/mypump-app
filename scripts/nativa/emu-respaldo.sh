#!/bin/zsh
# APL-08: el respaldo de Google de la nativa, de verdad, en el emulador (D14 en docs/NATIVA_ESTADO.md). Con `bmgr` y el
# transporte local de Android (no hace falta una cuenta de Google): respaldo, desinstalar, instalar de nuevo como en un
# teléfono nuevo (Android restaura antes de abrir) y mirar qué volvió ANTES de abrir la app, y después qué hace al abrir.
#   A. Con la app vieja: la Capacitor de debug con el token de test-nativa-android, la nativa encima (migra y adopta el
#      token), respaldo y teléfono nuevo. D14: vuelve app_webview/ (menos sus cachés) y la migración adopta el token que
#      quedó ahí: entra sin pegar el link. Lo de la nativa (no_backup/acceso.bin, files/MyPump/) no vuelve.
#   B. Solo la nativa (nunca tuvo la app vieja): instalada de cero y abierta con el link, respaldo y teléfono nuevo: no
#      vuelve el token por ningún lado y pide el link.
# El token nunca pasa por acá: lo leen emu_respaldo.py y lanzar-emu.py. Informe en ~/Developer/nativa-evidencia/respaldo-android/.
# Uso: scripts/nativa/emu-respaldo.sh <serial> [A|B]   (desinstala MyPump de ese emulador; al terminar deja el transporte
#      de respaldo y el estado de bmgr como estaban)
#   TRASPASO=1 prueba el pase a un teléfono nuevo (cable o wifi al configurarlo) en vez de la copia en la nube: el transporte
#   local se presenta como de dispositivo a dispositivo y valen las reglas de <device-transfer> en vez de <cloud-backup>.
set -e
SERIAL=${1:?serial, ej. emulator-5560}
SOLO=${2:-}
export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}
adb() { "$ANDROID_HOME/platform-tools/adb" -s $SERIAL "$@" }
EV=~/Developer/nativa-evidencia
RAIZ=${0:A:h}/../..
CAP=$EV/dd/cap-android/cap-main-debug.apk
NAT=$RAIZ/apps/android/app/build/outputs/apk/debug/app-debug.apk
PY=${0:A:h}/emu_respaldo.py
MIG=${0:A:h}/emu_migracion.py
LANZAR=${0:A:h}/lanzar-emu.py
OUT=$EV/respaldo-android/$(date +%Y%m%d-%H%M%S)
PKG=com.pumpteam.mypump
PUERTO=9335   # el de DevTools (emu-migracion.sh usa el 9334)
LOCAL=com.android.localtransport/.LocalTransport
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
cerrar() { adb shell am force-stop $PKG; sleep 2 }
# Antes de respaldar, la app queda en segundo plano y NO cerrada a la fuerza: Android no respalda una app "detenida"
# (force-stop la deja así hasta que se vuelve a abrir), como no la respalda en el teléfono de un cliente.
atras() { adb shell input keyevent KEYCODE_HOME; sleep 3 }
abrir() { adb shell am start -n $PKG/.MainActivity >/dev/null }
token_guardado() { adb shell run-as $PKG ls no_backup/acceso.bin >/dev/null 2>&1 }
esperar() {   # $1 = qué, $2 = segundos, $3… = el comando que tiene que dar bien
  local que=$1 seg=$2 n=0; shift 2
  until "$@"; do
    (( n += 2 )); (( n > seg )) && { echo "✗ no pasó en $seg s: $que"; return 1 }
    sleep 2
  done
}

# bmgr con el transporte local; al terminar (también si algo falla), como estaba. Y el logcat limpio: Android 16 anota ahí el
# link entero (con el token) al abrir la app con el link (ver lanzar-emu.py).
TRANSPORTE=$(adb shell bmgr list transports | tr -d '\r' | awk '$1 == "*" {print $2}')
HABILITADO=$(adb shell bmgr enabled | tr -d '\r')
AUTORESTORE=$(adb shell dumpsys backup | tr -d '\r' | grep -c "Auto-restore is enabled")
PARAMETROS=$(adb shell settings get secure backup_local_transport_parameters | tr -d '\r')
# Lo que el transporte local guardó de MyPump (con el token de la cuenta de prueba adentro, en app_webview/) se borra al
# empezar cada escenario y al terminar. Al empezar, además, porque si no el instalar de cero restaura el respaldo anterior.
# `bmgr init` vacía el transporte local entero y espera a terminar (`bmgr wipe` es asincrónico y no sirve con la app
# desinstalada); ese transporte es de pruebas: en un emulador no lo usa nadie más.
borrar_respaldo() {
  adb shell bmgr enable true >/dev/null 2>&1
  adb shell bmgr init $LOCAL >/dev/null 2>&1 || true
}
dejar_como_estaba() {
  borrar_respaldo
  if [ "$AUTORESTORE" = "0" ]; then adb shell bmgr autorestore false >/dev/null 2>&1; else adb shell bmgr autorestore true >/dev/null 2>&1; fi
  [ -n "$TRANSPORTE" ] && adb shell bmgr transport $TRANSPORTE >/dev/null 2>&1
  [[ "$HABILITADO" == *disabled* ]] && adb shell bmgr enable false >/dev/null 2>&1
  if [ "$PARAMETROS" = "null" ] || [ -z "$PARAMETROS" ]; then
    adb shell settings delete secure backup_local_transport_parameters >/dev/null 2>&1
  else
    adb shell settings put secure backup_local_transport_parameters "$PARAMETROS" >/dev/null 2>&1
  fi
  adb logcat -c >/dev/null 2>&1
  adb forward --remove tcp:$PUERTO >/dev/null 2>&1
  return 0
}
trap dejar_como_estaba EXIT INT TERM
echo "bmgr: $HABILITADO; transporte $TRANSPORTE → $LOCAL" | tee $OUT/bmgr-antes.txt
adb shell bmgr enable true >/dev/null
adb shell bmgr transport $LOCAL | tr -d '\r' | tee -a $OUT/bmgr-antes.txt
if [ "${TRASPASO:-}" = "1" ]; then
  adb shell settings put secure backup_local_transport_parameters is_device_transfer=true
  echo "pase a un teléfono nuevo (device-transfer)" > $OUT/modo.txt
else
  adb shell settings delete secure backup_local_transport_parameters >/dev/null 2>&1 || true
  echo "copia en la nube (cloud-backup)" > $OUT/modo.txt
fi
cat $OUT/modo.txt
adb shell cmd connectivity airplane-mode disable >/dev/null

# Respaldo, "teléfono nuevo" (desinstalar e instalar: Android restaura al instalar) y abrir. $1 = escenario.
respaldar_y_restaurar() {
  local e=$1
  python3 -I $PY inventario $SERIAL $OUT $e-antes
  python3 -I $PY token-en $SERIAL $OUT $e-antes
  echo "   bmgr backupnow…"
  adb shell bmgr backupnow $PKG | tr -d '\r' > $OUT/bmgr-$e.txt
  cat $OUT/bmgr-$e.txt
  grep -q "Package $PKG with result: Success" $OUT/bmgr-$e.txt || { echo "✗ el respaldo no salió"; return 1 }
  echo "   teléfono nuevo: desinstalar e instalar"
  adb uninstall $PKG >/dev/null
  adb install $NAT >/dev/null
  # La restauración del instalar corre aparte: hasta que aparezcan las preferencias y quede quieta.
  if esperar "la restauración al instalar" 40 adb shell run-as $PKG ls shared_prefs >/dev/null 2>&1; then
    echo "al instalar (restoreAtInstall)" > $OUT/restauracion-$e.txt
  else
    # Si el instalar no restauró, a mano con el conjunto del transporte local.
    local set=$(adb shell bmgr list sets | tr -d '\r' | awk 'NF {print $1; exit}')
    echo "   sin restauración al instalar; bmgr restore $set $PKG"
    adb shell bmgr restore $set $PKG | tr -d '\r' > $OUT/bmgr-restore-$e.txt
    echo "con bmgr restore $set (el instalar no restauró)" > $OUT/restauracion-$e.txt
  fi
  sleep 8
  python3 -I $PY inventario $SERIAL $OUT $e-restaurado
  python3 -I $PY token-en $SERIAL $OUT $e-restaurado
  registro > $OUT/registro-$e-restaurado.txt
  echo "   abrir en el teléfono nuevo"
  abrir
  sleep 25
  python3 -I $PY pantalla $SERIAL $OUT $e
  # Con una cuenta sale primero la hoja de permisos de la primera vez (nadie la contestó antes del respaldo): "Ahora no"
  # para ver las pestañas.
  python3 -I $PY saltar-hoja $SERIAL
  python3 -I $PY pantalla $SERIAL $OUT $e-pestanas
  registro > $OUT/registro-$e.txt
  python3 -I $PY inventario $SERIAL $OUT $e-abierta
  cerrar
}

if [ -z "$SOLO" ] || [ "$SOLO" = "A" ]; then
  echo "── A. Con la app vieja: Capacitor con el token, la nativa encima (D14)"
  borrar_respaldo
  adb uninstall $PKG >/dev/null 2>&1 || true
  adb install $CAP >/dev/null
  abrir
  devtools
  sleep 3
  python3 -I $PY token $PUERTO $OUT
  python3 -I $MIG esperar-semilla $SERIAL token $OUT 300
  cerrar
  adb install -r $NAT >/dev/null
  abrir
  esperar "la Fase L adopta el token" 120 token_guardado
  n=0
  until registro | grep -q "escritura de vuelta, corrida"; do
    (( n += 2 )); (( n > 120 )) && break
    sleep 2
  done
  sleep 10   # que la escritura de vuelta baje al leveldb y la cuenta cargue
  atras
  registro > $OUT/registro-A-antes.txt
  respaldar_y_restaurar A
fi

if [ -z "$SOLO" ] || [ "$SOLO" = "B" ]; then
  echo "── B. Solo la nativa: instalada de cero y abierta con el link"
  # Sin el respaldo de A y sin restaurar al instalar (las dos cosas, por las dudas): si no, vuelve lo de A y ya no es
  # "solo la nativa".
  borrar_respaldo
  adb uninstall $PKG >/dev/null 2>&1 || true
  adb shell bmgr autorestore false >/dev/null
  adb install $NAT >/dev/null
  adb shell bmgr autorestore true >/dev/null
  # Y si igual restauró (quedó algo de antes en el transporte), no sirve: se corta acá.
  sleep 8
  if adb shell run-as $PKG ls app_webview >/dev/null 2>&1 || adb shell run-as $PKG ls files/legado >/dev/null 2>&1; then
    echo "✗ el instalar de cero restauró un respaldo anterior: B no sería «solo la nativa»"; exit 1
  fi
  python3 -I $LANZAR $SERIAL
  esperar "la nativa guarda el token del link" 60 token_guardado
  sleep 15   # que cargue la cuenta (files/MyPump/)
  atras
  adb logcat -c
  respaldar_y_restaurar B
fi

echo "── Verificación"
set +e
python3 -I $PY verificar $OUT
R=$?
echo "informe: $OUT/informe.md"
exit $R
