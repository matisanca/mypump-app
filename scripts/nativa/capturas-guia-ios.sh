#!/bin/zsh
# Maqueta de «Tu guía» en iOS: la tarjeta de Entreno y la sección con la guía de muestra (sin token ni red), en los
# simuladores propios de la guía (guia-SE, guia-17Pro, guia-iPad), en claro y oscuro, y la letra más grande en el SE.
# Uso: scripts/nativa/capturas-guia-ios.sh [carpeta]   (por defecto ~/Developer/nativa-evidencia/guia/maqueta)
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
OUT=${1:-~/Developer/nativa-evidencia/guia/maqueta}; mkdir -p $OUT
APP=~/Developer/nativa-evidencia/dd/guia-ios/Build/Products/Debug-iphonesimulator/MyPump.app
B=(-bocetos YES -guiaMuestra YES -sinOnboarding YES)
foto() { # udid nombre args…
  local u=$1 n=$2; shift 2
  xcrun simctl terminate $u com.pumpteam.mypump 2>/dev/null || true
  xcrun simctl launch $u com.pumpteam.mypump $B "$@" >/dev/null; sleep ${ESPERA:-4}
  xcrun simctl io $u screenshot $OUT/ios-$n.png >/dev/null 2>&1
}
while IFS='=' read -r nombre udid; do
  corto=${nombre#guia-}
  xcrun simctl boot $udid 2>/dev/null || true
  xcrun simctl bootstatus $udid -b >/dev/null 2>&1
  xcrun simctl status_bar $udid override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null || true
  xcrun simctl install $udid $APP
  xcrun simctl ui $udid content_size large
  for modo in light dark; do
    xcrun simctl ui $udid appearance $modo
    foto $udid $corto-$modo-1-tarjeta -pestana entreno
    foto $udid $corto-$modo-2-guia -pestana entreno -abrir guia
    foto $udid $corto-$modo-3-bloques -pestana entreno -abrir guia -guiaAncla dudas-llamada -guiaMotivo MC-7a
    foto $udid $corto-$modo-4-suple -pestana entreno -abrir guia -guiaAncla suplementacion
    ESPERA=3 foto $udid $corto-$modo-5-placa -pestana entreno -abrir guia -guiaPlaca YES
  done
  if [[ $corto == SE ]]; then
    xcrun simctl ui $udid appearance light
    xcrun simctl ui $udid content_size accessibility-extra-extra-extra-large
    foto $udid $corto-letra-grande-1-tarjeta -pestana entreno
    foto $udid $corto-letra-grande-2-guia -pestana entreno -abrir guia
    foto $udid $corto-letra-grande-3-bloques -pestana entreno -abrir guia -guiaAncla FT-2a
    xcrun simctl ui $udid content_size large
  fi
  echo "listo $nombre"
done < ~/Developer/nativa-evidencia/guia/simuladores-ios.txt
