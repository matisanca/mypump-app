#!/bin/zsh
# XCUITest de «Tu guía» con el cliente de prueba test-nativa-ios, en los simuladores propios de la guía y con su
# derivedData (no pisa a nadie). El token llega al runner por TEST_RUNNER_MYPUMP_TOKEN, sin pasar por la terminal.
# Uso: scripts/nativa/probar-guia-ios.sh <udid> [-only-testing:MyPumpUITests/GuiaUITests/…]
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=${1:?udid}; shift
RAIZ=${0:A:h}/../..
OUT=~/Developer/nativa-evidencia/guia/e2e/ios-$(date +%Y%m%d-%H%M%S)
export TEST_RUNNER_MYPUMP_TOKEN=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/Developer/nativa-evidencia/privado/cuentas-prueba.json')))['test-nativa-ios']['token'])")
[[ $# -eq 0 ]] && set -- -only-testing:MyPumpUITests/GuiaUITests
xcodebuild test -project $RAIZ/apps/ios/MyPump.xcodeproj -scheme MyPump -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath ~/Developer/nativa-evidencia/dd/guia-ios -resultBundlePath $OUT.xcresult "$@" 2>&1 \
  | grep -E "Test Case|error:|failed|passed|skipped|\*\* TEST" | grep -v "^\s*$"
echo "resultado: $OUT.xcresult"
