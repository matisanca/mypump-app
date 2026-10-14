#!/bin/zsh
# =============================================================
# salud-banco.sh — la nativa contra la app de hoy, en el simulador, sobre los MISMOS datos de HealthKit
#
# Arma apps/ios/SaludBanco (app de banco, solo simulador) con:
#   - el Health.swift REAL del plugin (@capgo/capacitor-health 8.9.3, de node_modules: no se commitea);
#   - healthkit-bridge.js de origin/main (corre en JavaScriptCore, sin WebView);
#   - FuenteHealthKit + SincronizadorSalud de la nativa.
# Siembra la Salud del simulador (62 días sintéticos con los bordes difíciles), corre la sincronización de 7 días y el
# historial de 60 en las dos con el mismo "ahora" y compara lote por lote lo que mandarían a ingest_salud e
# ingest_entrenos. El informe queda en ~/Developer/nativa-evidencia/salud-e2e-<fecha>.json.
#
# Lo que esto agrega a los vectores (scripts/nativa/vectores-salud.mjs): que HealthKit le conteste a FuenteHealthKit
# lo mismo que al plugin (predicados, ancla y reparto de los agregados, redondeo de las horas, orden y límites).
#
# Uso: scripts/nativa/salud-banco.sh [udid] [--vistas]
#   udid      por defecto el simulador "Salud 26"
#   --vistas  además abre las vistas de salud con la cuenta test-nativa-ios (base real; el token le llega al runner
#             por TEST_RUNNER_MYPUMP_TOKEN y no pasa por la terminal)
#
# Lo corre un XCUITest (SaludBancoUITests): acepta solo la hoja de permisos de Salud la primera vez y espera el
# veredicto. Las capturas quedan en el .xcresult.
# =============================================================
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
RAIZ=${0:A:h:h:h}
UDID=${1:-$(xcrun simctl list devices | grep "Salud 26 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')}
[ -n "$UDID" ] || { echo "no hay simulador \"Salud 26\" (xcrun simctl create \"Salud 26\" …)"; exit 1; }
BUNDLE=com.pumpteam.mypump.saludbanco
EXT=$RAIZ/apps/ios/SaludBanco/externo
DD=~/Developer/nativa-evidencia/dd/salud-banco
SELLO=$(date +%Y%m%d-%H%M%S)

# 1. El plugin y el bridge de hoy.
COMUN=$(git -C $RAIZ rev-parse --path-format=absolute --git-common-dir)
PLUGIN=${COMUN:h}/node_modules/@capgo/capacitor-health
[ -d $RAIZ/node_modules/@capgo/capacitor-health ] && PLUGIN=$RAIZ/node_modules/@capgo/capacitor-health
VER=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['version'])" $PLUGIN/package.json)
[ "$VER" = "8.9.3" ] || { echo "el plugin instalado es $VER y la app de hoy usa 8.9.3 (package-lock de origin/main)"; exit 1; }
mkdir -p $EXT
cp $PLUGIN/ios/Sources/HealthPlugin/Health.swift $EXT/Health.swift
git -C $RAIZ show origin/main:public/js/healthkit-bridge.js > $EXT/healthkit-bridge.js

# 2. Compilar, instalar y correr la comparación (XCUITest).
xcrun simctl boot $UDID 2>/dev/null || true
xcrun simctl bootstatus $UDID -b >/dev/null 2>&1
if [ "$2" = "--vistas" ]; then
  export TEST_RUNNER_MYPUMP_TOKEN=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/Developer/nativa-evidencia/privado/cuentas-prueba.json')))['test-nativa-ios']['token'])")
fi
mkdir -p ~/Developer/nativa-evidencia/salud
# Sin paralelo: si no, xcodebuild clona el simulador (y con varios simuladores prendidos no quedan procesos para bootear
# el clon).
xcodebuild test -project $RAIZ/apps/ios/SaludBanco/SaludBanco.xcodeproj -scheme SaludBanco -destination "platform=iOS Simulator,id=$UDID" \
  -parallel-testing-enabled NO -derivedDataPath $DD -resultBundlePath ~/Developer/nativa-evidencia/salud/banco-$SELLO.xcresult 2>&1 \
  | grep -E "Test Case|error:|\*\* TEST" || true
DOCS=$(xcrun simctl get_app_container $UDID $BUNDLE data)/Documents
[ -f $DOCS/salud-e2e.json ] || { echo "sin informe (mirá el .xcresult)"; exit 1; }
SALIDA=~/Developer/nativa-evidencia/salud/salud-e2e-$SELLO.json
cp $DOCS/salud-e2e.json $SALIDA
python3 - $SALIDA <<'EOF'
import json, sys
i = json.load(open(sys.argv[1]))
print(f"ahora {i['ahora']} · zona {i['zona']} · iOS {i['ios']} · {i['sembradas']} muestras sembradas · {i['consultasWeb']} consultas del bridge")
print(f"FuenteHealthKit encontrada por nombre: {'sí' if i['fuenteDescubierta'] else 'NO'}")
ok = i.get('error') is None and i['fuenteDescubierta']
for k in ('sync', 'historial'):
    f = i[k]
    ok = ok and f['iguales']
    print(f"{k}: {'IGUALES' if f['iguales'] else 'DISTINTOS'} · registros {f['registrosWeb']}/{f['registrosNativa']} · entrenos {f['entrenosWeb']}/{f['entrenosNativa']} · lotes {f['lotesWeb']}/{f['lotesNativa']} · {len(f['tipos'])} tipos")
    for d in f['diferencias'][:10]: print('   ', d)
if i.get('error'): print('error:', i['error'])
print('informe:', sys.argv[1])
sys.exit(0 if ok else 1)
EOF
