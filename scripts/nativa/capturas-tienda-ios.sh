#!/bin/zsh
# Capturas para el App Store de la 2.0.0 nativa: iPhone de 6,9" (1320×2868) y iPad de 13" (2064×2752), con la DEMO (los
# datos de ejemplo de la web: sin cuenta, sin token, sin datos de clientes), barra de estado fija (9:41, batería llena)
# y en claro y oscuro. Las sube Mati (G7).
# Pantallas: Entreno, un ejercicio abierto, Dieta, Revisión y Progreso (las de la 1.0.x, docs/APP_STORE_SUBMISSION.md §8).
# Uso: scripts/nativa/capturas-tienda-ios.sh [carpeta-salida]
#   Los simuladores salen de nativa-evidencia/simuladores-tienda.txt ("nombre=udid"). La app, de un build Debug para
#   simulador (`-entrar demo` es solo de DEBUG): dd/migracion o lo que diga APP=….
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
EV=~/Developer/nativa-evidencia
OUT=${1:-$EV/tienda/$(date +%Y%m%d-%H%M%S)}; mkdir -p $OUT
APP=${APP:-$EV/dd/migracion/Build/Products/Debug-iphonesimulator/MyPump.app}
BID=com.pumpteam.mypump
[ -d $APP ] || { echo "✗ falta la app: compilala en Debug para simulador (-derivedDataPath $EV/dd/migracion)"; exit 1; }

abrir() {   # $1 udid, $2 nombre del archivo, resto: argumentos de lanzamiento
  local udid=$1 archivo=$2; shift 2
  xcrun simctl terminate $udid $BID 2>/dev/null || true
  xcrun simctl launch $udid $BID -entrar demo -sinOnboarding YES "$@" >/dev/null
  sleep 5
  xcrun simctl io $udid screenshot $OUT/$archivo.png >/dev/null 2>&1
}

while IFS='=' read -r nombre udid; do
  corto=$(echo $nombre | sed 's/Tienda //; s/,/-/g')
  xcrun simctl boot $udid 2>/dev/null || true
  xcrun simctl bootstatus $udid -b >/dev/null 2>&1
  xcrun simctl status_bar $udid override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 2>/dev/null || true
  xcrun simctl uninstall $udid $BID 2>/dev/null || true
  xcrun simctl install $udid $APP
  xcrun simctl ui $udid content_size large
  for modo in light dark; do
    xcrun simctl ui $udid appearance $modo
    abrir $udid "$corto-$modo-1-entreno" -pestana entreno
    abrir $udid "$corto-$modo-2-ejercicio" -pestana entreno -abrir ejercicio
    abrir $udid "$corto-$modo-3-dieta" -pestana dieta
    abrir $udid "$corto-$modo-4-revision" -pestana revision
    abrir $udid "$corto-$modo-5-progreso" -pestana progreso
  done
  xcrun simctl terminate $udid $BID 2>/dev/null || true
  xcrun simctl ui $udid appearance light
  xcrun simctl status_bar $udid clear 2>/dev/null || true
  echo "✓ $nombre"
done < $EV/simuladores-tienda.txt

# Tamaños que acepta App Store Connect: 6,9" 1320×2868 (o 1290×2796) y 13" 2064×2752 (o 2048×2732).
for f in $OUT/*.png; do
  echo "$(basename $f): $(sips -g pixelWidth -g pixelHeight $f | awk '/pixel/ {printf "%s ", $2}')"
done
echo "capturas: $OUT"
