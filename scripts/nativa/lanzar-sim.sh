#!/bin/zsh
# Instala la app recién compilada en un simulador y la abre con una cuenta de prueba, sin que el token pase por la
# terminal. Uso: scripts/nativa/lanzar-sim.sh <udid> <cuenta: real|ios> [args de la app…]   (ej. -pestana dieta)
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=${1:?udid}; CUENTA=${2:?cuenta}; shift 2
APP=${APP:-~/Developer/nativa-evidencia/dd/mypump/Build/Products/Debug-iphonesimulator/MyPump.app}
T=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/Developer/nativa-evidencia/privado/cuentas-prueba.json')))['test-nativa-$CUENTA']['token'])")
xcrun simctl boot $UDID 2>/dev/null || true
xcrun simctl bootstatus $UDID -b >/dev/null 2>&1
xcrun simctl status_bar $UDID override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null || true
xcrun simctl install $UDID $APP
xcrun simctl terminate $UDID com.pumpteam.mypump 2>/dev/null || true
xcrun simctl launch $UDID com.pumpteam.mypump -token "$T" "$@" >/dev/null
