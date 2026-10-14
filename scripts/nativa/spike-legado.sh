#!/bin/zsh
# Prueba del almacenamiento viejo en un simulador, sin tocar la pantalla (riesgo n.º 1, ver
# docs/NATIVA_SPIKE_ALMACENAMIENTO.md): Capacitor de main → escribe su localStorage → se siembra la verdad con la app
# cerrada → la espía se instala ENCIMA (update real) → lee por las dos rutas, escribe la marca → segundo arranque.
# Uso: scripts/nativa/spike-legado.sh <udid> <etiqueta> [appbound|sin]
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=${1:?udid}; ET=${2:?etiqueta}; VAR=${3:-sin}
EV=~/Developer/nativa-evidencia
CAP=$EV/dd/cap-main/Build/Products/Debug-iphonesimulator/App.app
SPY=$EV/dd/spike$([ $VAR = sin ] && echo -sin)/Build/Products/Debug-iphonesimulator/Spike.app
PY=${0:A:h}/legado_sqlite.py
OUT=$EV/spike/$ET-$VAR; mkdir -p $OUT
BID=com.pumpteam.mypump

xcrun simctl boot $UDID 2>/dev/null || true
xcrun simctl bootstatus $UDID -b >/dev/null 2>&1
xcrun simctl uninstall $UDID $BID 2>/dev/null || true
xcrun simctl install $UDID $CAP
xcrun simctl launch $UDID $BID >/dev/null
sleep 12   # theme.js escribe mypump-theme al cargar: así WebKit crea el archivo de verdad
xcrun simctl terminate $UDID $BID 2>/dev/null || true
sleep 2

DATA=$(xcrun simctl get_app_container $UDID $BID data)
DB=$(find "$DATA/Library/WebKit" -name localstorage.sqlite3 -path "*LocalStorage*" 2>/dev/null | head -1)
[ -n "$DB" ] || { echo "✗ la Capacitor no dejó localstorage.sqlite3"; find "$DATA/Library/WebKit" -maxdepth 6 | head -40; exit 1; }
echo "archivo: ${DB#$DATA/}"
python3 -I $PY dump "$DB" > $OUT/antes-de-sembrar.json
python3 -I $PY sembrar "$DB" $EV/spike/semilla.json
python3 -I $PY dump "$DB" > $OUT/verdad.json
echo "verdad: $(python3 -c "import json;print(len(json.load(open('$OUT/verdad.json'))))") claves"

# La espía encima: mismo bundle id, se conserva el contenedor.
xcrun simctl install $UDID $SPY
for n in 1 2; do
  xcrun simctl launch $UDID $BID >/dev/null
  sleep 15
  DATA=$(xcrun simctl get_app_container $UDID $BID data)
  cp "$DATA/Library/Application Support/spike-informe.json" $OUT/informe-$n.json
  xcrun simctl terminate $UDID $BID 2>/dev/null || true
  sleep 2
done
xcrun simctl io $UDID screenshot $OUT/pantalla.png >/dev/null 2>&1 || true

python3 - $OUT <<'EOF'
import json, sys, os
out = sys.argv[1]
verdad = json.load(open(os.path.join(out, 'verdad.json')))
for n in (1, 2):
    inf = json.load(open(os.path.join(out, f'informe-{n}.json')))
    a, b = inf.get('valores_rutaA') or {}, inf.get('valores_rutaB') or {}
    falta_a = [k for k in verdad if a.get(k) != verdad[k]]
    falta_b = [k for k in verdad if b.get(k) != verdad[k]]
    print(f"arranque {n} (iOS {inf.get('ios')}, {inf.get('variante')}): ruta A {len(verdad)-len(falta_a)}/{len(verdad)} · "
          f"ruta B {len(verdad)-len(falta_b)}/{len(verdad)} · iguales={inf.get('iguales')} · "
          f"marca previa={'sí' if inf.get('marca_previa_rutaB') else 'no'} · errores={[k for k in inf if k.endswith('_error')]}")
    if falta_a: print('  difiere A:', falta_a[:5])
    if falta_b: print('  difiere B:', falta_b[:5])
EOF
