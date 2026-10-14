#!/bin/zsh
# Prueba de punta a punta de la migración del almacenamiento viejo en un simulador PROPIO, sin tocar la pantalla:
#   1. la Capacitor de main abre con red la cuenta de prueba test-nativa-ios (token sembrado con la app cerrada) y manda
#      ella misma una cola chica: así escribe sus claves reales y se prueba que el formato sembrado es el de la web;
#   2. con la app cerrada se siembra el resto (cola para la nativa con los 9 kinds, sin sesión, sin _id, anon, token
#      rotado, descanso, fotos, swaps, ajustes, 1 MB, unicode y nulo);
#   3. la nativa se instala ENCIMA (update real: conserva el contenedor) y arranca: Fase L, carga con red, Fase R,
#      escritura de vuelta. Se mira la base con las RPC de lectura y el localStorage con la Ruta B;
#   4. segundo arranque de la nativa: confirma la escritura y no repite nada;
#   5. la Capacitor otra vez encima (plan B): no resucita nada.
# El token nunca pasa por acá: lo lee sim_migracion.py. Capturas e informe en ~/Developer/nativa-evidencia/migracion/.
# Uso: scripts/nativa/sim-migracion.sh <udid>   (desinstala MyPump de ese simulador)
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=${1:?udid de un simulador propio}
EV=~/Developer/nativa-evidencia
CAP=$EV/dd/cap-main/Build/Products/Debug-iphonesimulator/App.app
NAT=$EV/dd/migracion/Build/Products/Debug-iphonesimulator/MyPump.app
PY=${0:A:h}/sim_migracion.py
OUT=$EV/migracion/$(date +%Y%m%d-%H%M%S)
BID=com.pumpteam.mypump
mkdir -p $OUT
[ -d $CAP ] || { echo "✗ falta la Capacitor compilada: $CAP"; exit 1; }
[ -d $NAT ] || { echo "✗ falta la nativa: compilala con -derivedDataPath $EV/dd/migracion"; exit 1; }

contenedor() { xcrun simctl get_app_container $UDID $BID data }   # el UUID cambia al reinstalar: se pide cada vez
base() { python3 -I $PY db "$(contenedor)" }
registro() { echo "$(contenedor)/Library/Application Support/legado/registro.log" }
esperar_registro() {   # $1 = texto, $2 = segundos
  local n=0
  until grep -q "$1" "$(registro)" 2>/dev/null; do
    (( n += 2 )); (( n > $2 )) && { echo "✗ no apareció «$1» en el registro de la nativa"; return 1 }
    sleep 2
  done
}
cerrar() { xcrun simctl terminate $UDID $BID 2>/dev/null || true; sleep 2 }

xcrun simctl boot $UDID 2>/dev/null || true
xcrun simctl bootstatus $UDID -b >/dev/null 2>&1
xcrun simctl uninstall $UDID $BID 2>/dev/null || true
xcrun simctl keychain $UDID reset 2>/dev/null || true   # el Keychain sobrevive a desinstalar: si no, la nativa ya tendría el token

echo "── 1. Capacitor de main, con red"
xcrun simctl install $UDID $CAP
xcrun simctl launch $UDID $BID >/dev/null
sleep 12   # theme.js escribe al cargar: así WebKit crea el archivo
cerrar
DB=$(base); [ -n "$DB" ] || { echo "✗ la Capacitor no dejó localstorage.sqlite3"; exit 1 }
echo "archivo: ${DB#$(contenedor)/}"
python3 -I $PY token "$DB"
python3 -I $PY cola-capacitor "$DB" $OUT
xcrun simctl launch $UDID $BID >/dev/null
sleep 25   # carga la cuenta, manda la cola (1,5 s después del arranque) y guarda la foto offline
xcrun simctl io $UDID screenshot $OUT/1-capacitor.png >/dev/null 2>&1 || true
cerrar
python3 -I $PY backend $OUT capacitor
python3 -I $PY almacen "$(base)" $OUT capacitor

echo "── 2. Se siembra el resto, con la app cerrada"
python3 -I $PY preparar "$(base)" $OUT
python3 -I $PY almacen "$(base)" $OUT sembrado

echo "── 3. La nativa ENCIMA"
xcrun simctl install $UDID $NAT
xcrun simctl launch $UDID $BID -pestana dieta >/dev/null
esperar_registro "escritura de vuelta" 150 || true
sleep 6   # que WebKit baje la escritura al disco
xcrun simctl io $UDID screenshot $OUT/2-nativa.png >/dev/null 2>&1 || true
cerrar
python3 -I $PY nativa "$(contenedor)" $OUT nativa
python3 -I $PY backend $OUT nativa
python3 -I $PY almacen "$(base)" $OUT nativa
for k in mypump-theme mypump_tipo_dia mypump_notif_prefs mypump_notif_pedido mypump_onboarding_v1 mypump_health_connected; do
  echo "$k = $(xcrun simctl spawn $UDID defaults read $BID $k 2>/dev/null || echo '(no está)')"
done > $OUT/ajustes-nativa.txt

echo "── 4. Segundo arranque de la nativa"
xcrun simctl launch $UDID $BID -pestana dieta >/dev/null
esperar_registro "Fase L corrida 2" 60 || true
sleep 10
xcrun simctl io $UDID screenshot $OUT/3-segundo.png >/dev/null 2>&1 || true
cerrar
python3 -I $PY nativa "$(contenedor)" $OUT segundo
python3 -I $PY backend $OUT segundo
python3 -I $PY almacen "$(base)" $OUT segundo

echo "── 5. La Capacitor otra vez encima (plan B)"
xcrun simctl install $UDID $CAP
xcrun simctl launch $UDID $BID >/dev/null
sleep 25
xcrun simctl io $UDID screenshot $OUT/4-capacitor-vuelta.png >/dev/null 2>&1 || true
cerrar
python3 -I $PY backend $OUT vuelta
python3 -I $PY almacen "$(base)" $OUT vuelta

echo "── Verificación"
set +e
python3 -I $PY verificar $OUT
R=$?
python3 -I $PY limpiar $OUT
echo "informe: $OUT/informe.md"
exit $R
