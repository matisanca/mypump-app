#!/bin/zsh
# Pruebas de interfaz (XCUITest) en un simulador con una cuenta de prueba. El token sale del archivo privado y le
# llega al runner por TEST_RUNNER_MYPUMP_TOKEN: no pasa por la terminal ni queda en el repo.
# Uso: scripts/nativa/probar-ui.sh <udid> <cuenta: real|ios> [-only-testing:MyPumpUITests/DietaUITests/…]
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=${1:?udid}; CUENTA=${2:?cuenta}; shift 2
RAIZ=${0:A:h}/../..
OUT=~/Developer/nativa-evidencia/ui/$(date +%Y%m%d-%H%M%S)
mkdir -p ${OUT:h}
export TEST_RUNNER_MYPUMP_TOKEN=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/Developer/nativa-evidencia/privado/cuentas-prueba.json')))['test-nativa-$CUENTA']['token'])")
xcodebuild test -project $RAIZ/apps/ios/MyPump.xcodeproj -scheme MyPump -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath ~/Developer/nativa-evidencia/dd/mypump -resultBundlePath $OUT.xcresult "$@" 2>&1 \
  | grep -E "Test Case|error:|failed|passed|skipped|\*\* TEST" | grep -v "^\s*$"
echo "resultado: $OUT.xcresult"
