#!/bin/zsh
# Capturas de los bocetos sin tocar la pantalla: cada pestaña × claro/oscuro × dispositivo, más Dynamic Type grande.
# Uso: scripts/nativa/capturas-bocetos.sh <carpeta-salida>   (los simuladores salen de nativa-evidencia/simuladores.txt)
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
OUT=${1:?carpeta de salida}; mkdir -p $OUT
APP=~/Developer/nativa-evidencia/dd/mypump/Build/Products/Debug-iphonesimulator/MyPump.app
while IFS='=' read -r nombre udid; do
  corto=$(echo $nombre | sed 's/Bocetos //; s/ /-/g' | tr 'A-Z' 'a-z')
  xcrun simctl boot $udid 2>/dev/null || true
  xcrun simctl bootstatus $udid -b >/dev/null 2>&1
  xcrun simctl status_bar $udid override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null || true
  xcrun simctl install $udid $APP
  xcrun simctl ui $udid content_size large
  for modo in light dark; do
    xcrun simctl ui $udid appearance $modo
    for p in entreno dieta chat revision progreso; do
      xcrun simctl terminate $udid com.pumpteam.mypump 2>/dev/null || true
      xcrun simctl launch $udid com.pumpteam.mypump -pestana $p >/dev/null; sleep 3
      xcrun simctl io $udid screenshot $OUT/$corto-$modo-$p.png >/dev/null 2>&1
    done
    xcrun simctl terminate $udid com.pumpteam.mypump 2>/dev/null || true
    xcrun simctl launch $udid com.pumpteam.mypump -pestana entreno -abrir ejercicio >/dev/null; sleep 4
    xcrun simctl io $udid screenshot $OUT/$corto-$modo-ejercicio.png >/dev/null 2>&1
  done
  # Letra grande (accesibilidad): Entreno y Dieta en claro.
  xcrun simctl ui $udid appearance light
  xcrun simctl ui $udid content_size accessibility-large
  for p in entreno dieta; do
    xcrun simctl terminate $udid com.pumpteam.mypump 2>/dev/null || true
    xcrun simctl launch $udid com.pumpteam.mypump -pestana $p >/dev/null; sleep 3
    xcrun simctl io $udid screenshot $OUT/$corto-letra-grande-$p.png >/dev/null 2>&1
  done
  xcrun simctl ui $udid content_size large
  echo "✓ $nombre"
done < ~/Developer/nativa-evidencia/simuladores.txt
