#!/bin/zsh
# probar.sh — las pruebas de las apps en UN paso, con un resumen corto: totales, las que fallan con su primer renglón
# y las capturas nuevas. Antes cada corrida eran 3 o 4 pasos (compilar, parsear los XML a mano, bajar o exportar las
# capturas) y un resultado viejo se podía leer como nuevo (21-oct: Mati pidió gastar menos pasos sin perder nada).
#
#   scripts/nativa/probar.sh kit [filtro]                  MyPumpKit (swift test). Si los tests mueren con una señal
#                                                          (objetos viejos que SwiftPM no recompiló), recompila y reintenta.
#   scripts/nativa/probar.sh jvm [tarea…]                  Android JVM; por defecto `test` (o :core:reglas:test, …).
#   scripts/nativa/probar.sh android-ui <Clase[#metodo]|todo>  Instrumentadas en el emulador (Clase sola = …mypump.ui.Clase);
#                                                          baja las capturas que cambiaron.
#   scripts/nativa/probar.sh ios-ui [-only-testing:…]      XCUITest con probar-ui.sh (UDID y CUENTA por variable de
#                                                          entorno; por defecto el simulador de siempre y `real`), y
#                                                          exporta los adjuntos.
#
# La salida completa queda en ~/Developer/nativa-evidencia/logs/<modo>-<fecha>.log. Sale con 0 si todo pasó.
set -u
RAIZ=${0:A:h}/../..
EVID=~/Developer/nativa-evidencia
LOGS=$EVID/logs
mkdir -p $LOGS
SELLO=$(date +%Y%m%d-%H%M%S)
MARCA=$LOGS/.inicio-$SELLO
touch $MARCA
trap 'rm -f $MARCA' EXIT
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export ANDROID_HOME=~/Library/Android/sdk
export JAVA_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null || echo /opt/homebrew/opt/openjdk@21)
ADB=$ANDROID_HOME/platform-tools/adb
CAPTURAS_EMU=/data/local/tmp/mypump-capturas

# Los JUnit XML que se escribieron DESPUÉS de arrancar (un XML viejo no cuenta), en totales y fallas. Con un tercer
# argumento `todos`, también los de antes.
junit() {
  python3 - "$1" "$2" "$MARCA" "${3:-}" <<'PY'
import glob, os, sys, xml.etree.ElementTree as ET
raiz, patron, marca, todos = sys.argv[1:5]
t0 = 0 if todos else os.path.getmtime(marca)
archivos = [f for f in glob.glob(os.path.join(raiz, patron), recursive=True) if os.path.getmtime(f) >= t0]
if not archivos:
    sys.exit(3)
tot = dict(tests=0, failures=0, errors=0, skipped=0)
fallas = []
for f in archivos:
    r = ET.parse(f).getroot()
    for s in ([r] if r.tag == "testsuite" else r.findall("testsuite")):
        for k in tot:
            tot[k] += int(s.get(k, 0))
        for tc in s.findall("testcase"):
            for tipo in ("failure", "error"):
                e = tc.find(tipo)
                if e is not None:
                    renglones = (e.get("message") or e.text or "").strip().splitlines()
                    clase = (tc.get("classname") or s.get("name", "")).split(".")[-1]
                    fallas.append(f"{clase}.{tc.get('name')}: {' / '.join(renglones[:2])[:300]}")
print(f"{tot['tests']} pruebas · {tot['failures'] + tot['errors']} fallas · {tot['skipped']} salteadas")
for x in fallas[:30]:
    print("  ✗", x)
sys.exit(1 if fallas else 0)
PY
}

kit() {
  local log=$LOGS/kit-$SELLO.log
  local -a filtro=()
  (( $# )) && filtro=(--filter "$1")
  cd $RAIZ/apps/ios/MyPumpKit || return 2
  swift test --scratch-path $EVID/dd/kit $filtro >$log 2>&1
  if grep -q "unexpected signal code" $log; then
    echo "los tests murieron con una señal: recompilo los objetos de prueba y reintento"
    find Tests -name '*.swift' -exec touch {} +
    swift test --scratch-path $EVID/dd/kit $filtro >$log 2>&1
  fi
  grep -E "Test run with|Executed [0-9]+ tests?, with [1-9]|✘|error:" $log | grep -v "Executed 0 tests" | head -40
  grep -q "Test run with .* passed" $log && ! grep -qE "✘|error:" $log
}

jvm() {
  local log=$LOGS/jvm-$SELLO.log
  cd $RAIZ/apps/android || return 2
  local -a tareas=(${@:-test})
  # Los resultados de lo pedido: `:core:reglas:test` → core/reglas; `test` a secas → todos los módulos.
  local patron="**/build/test-results/**/*.xml"
  (( ${#tareas} == 1 )) && [[ ${tareas[1]} == :*:test ]] && patron="${${${tareas[1]#:}%:test}//://}/build/test-results/**/*.xml"
  ./gradlew -q $tareas >$log 2>&1
  local salida=$?
  junit "$RAIZ/apps/android" "$patron"
  local r=$?
  if (( r == 3 && salida == 0 )); then
    # Gradle no las volvió a correr porque no cambió nada, y no deja "al día" una tarea que falló: vale lo último.
    echo "(Gradle no las volvió a correr: no cambió nada desde la última vez; esto es lo último)"
    junit "$RAIZ/apps/android" "$patron" todos
    r=$?
  fi
  (( r == 3 )) && echo "sin resultados nuevos: no llegó a correr"
  (( r == 3 || (salida != 0 && r == 0) )) && tail -15 $log
  (( salida == 0 && r == 0 ))
}

capturas_emu() {
  $ADB shell "ls $CAPTURAS_EMU/*.png >/dev/null 2>&1 && stat -c '%Y %n' $CAPTURAS_EMU/*.png" 2>/dev/null | sort
}

android_ui() {
  local clase=${1:?falta la clase (EntrenoUiTest, EntrenoUiTest#metodo o todo)}
  local -a filtro=(-Pandroid.testInstrumentationRunnerArguments.class=$clase)
  [[ $clase != *.* ]] && filtro=(-Pandroid.testInstrumentationRunnerArguments.class=com.pumpteam.mypump.ui.$clase)
  [[ $clase == todo ]] && filtro=()
  local log=$LOGS/android-ui-$SELLO.log antes despues
  antes=$(capturas_emu)
  cd $RAIZ/apps/android || return 2
  ./gradlew -q :app:connectedDebugAndroidTest $filtro >$log 2>&1
  local salida=$?
  junit "$RAIZ/apps/android" "app/build/outputs/androidTest-results/connected/debug/*.xml"
  local r=$?
  (( r == 3 )) && { echo "sin resultados nuevos: no llegó a correr"; tail -15 $log; }
  despues=$(capturas_emu)
  local -a nuevas=(${(f)"$(comm -13 <(print -r -- $antes) <(print -r -- $despues) | awk '{print $2}')"})
  if (( ${#nuevas} )) && [[ -n ${nuevas[1]} ]]; then
    local dest=$EVID/android-ui/$SELLO
    mkdir -p $dest
    for f in $nuevas; do $ADB pull $f $dest/ >/dev/null 2>&1 && echo "  captura: $dest/${f:t}"; done
  fi
  (( salida == 0 && r == 0 ))
}

ios_ui() {
  local log=$LOGS/ios-ui-$SELLO.log
  zsh $RAIZ/scripts/nativa/probar-ui.sh ${UDID:-5AEF73CA-182C-4391-A7CD-EB95A9D455D2} ${CUENTA:-real} "$@" >$log 2>&1
  local pasaron=$(grep -c "' passed (" $log)
  grep -E "' failed \(|error:|\*\* TEST" $log | head -30
  echo "$pasaron pruebas pasaron"
  local res=$(awk '/^resultado:/ {print $2}' $log)
  if [[ -n $res && -d $res ]]; then
    local dest=$EVID/ui/$SELLO-adjuntos
    mkdir -p $dest
    xcrun xcresulttool export attachments --path $res --output-path $dest >/dev/null 2>&1
    [[ -f $dest/manifest.json ]] && python3 - "$dest" <<'PY'
import json, sys
d = sys.argv[1]
for t in json.load(open(f"{d}/manifest.json")):
    for a in t.get("attachments", []):
        print(f"  adjunto: {a.get('suggestedHumanReadableName', '').split('_0_')[0]} → {d}/{a['exportedFileName']}")
PY
  fi
  grep -q "\*\* TEST SUCCEEDED \*\*" $log
}

modo=${1:-}
(( $# )) && shift
case $modo in
  kit) kit "$@" ;;
  jvm) jvm "$@" ;;
  android-ui) android_ui "$@" ;;
  ios-ui) ios_ui "$@" ;;
  *) sed -n '2,16p' ${0:A}; exit 2 ;;
esac
salida=$?
echo "log: $(ls -t $LOGS/*-$SELLO.log 2>/dev/null | head -1)"
exit $salida
