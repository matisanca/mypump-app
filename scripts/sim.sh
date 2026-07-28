#!/usr/bin/env bash
# =============================================================
# sim.sh — compila MyPump y la instala en el Simulador de iOS.
#
# PARA QUÉ
# Poder probar la app de verdad (no el bundle web en un navegador) sin
# depender de un iPhone físico ni de una vuelta completa por TestFlight, que
# son 3 minutos de build en la nube + procesamiento de Apple.
#
# QUÉ SÍ Y QUÉ NO PRUEBA EL SIMULADOR
#   SÍ  · toda la UI, navegación y flujos reales dentro de WKWebView
#       · que la app arranque y no crashee con los plugins nativos cargados
#       · HealthKit: el framework existe; los datos se cargan a mano en la app
#         Salud del simulador (Health → Explorar → agregar)
#       · notificaciones: `xcrun simctl push` inyecta un payload y permite ver
#         si la app reacciona y si el tap lleva a la escena correcta
#   NO  · el device token REAL de APNs (el simulador no tiene uno)
#       · el envío real desde la mini (eso necesita un iPhone)
#       · datos de sensores reales (HRV, sueño de un reloj)
#
# USO
#   ./scripts/sim.sh              # compila e instala en el simulador por defecto
#   ./scripts/sim.sh --boot-only  # solo arranca el simulador
#   ./scripts/sim.sh --device "iPhone 17 Pro"
# =============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE="${DEVICE:-iPhone 17 Pro}"
SOLO_BOOT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --boot-only) SOLO_BOOT=1; shift ;;
    --device)    DEVICE="$2"; shift 2 ;;
    *) echo "opción desconocida: $1"; exit 1 ;;
  esac
done

# ── Xcode presente? ───────────────────────────────────────────
# DEVELOPER_DIR le gana a xcode-select y no necesita sudo. Sirve cuando Xcode
# está instalado pero el developer dir sigue apuntando a CommandLineTools:
# así se puede compilar y usar el simulador sin pedirle la contraseña a nadie.
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if ! xcrun simctl help >/dev/null 2>&1; then
  echo "✗ No hay Xcode (falta simctl)."
  echo "  Instalalo desde el App Store. Si ya está instalado, el developer dir"
  echo "  apunta al lugar equivocado; para dejarlo fijo (y habilitar el panel"
  echo "  visual del simulador) corré:"
  echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

# ── Simulador ─────────────────────────────────────────────────
UDID=$(xcrun simctl list devices available \
       | grep -m1 "$DEVICE (" | grep -oE '[0-9A-F-]{36}' || true)
if [ -z "$UDID" ]; then
  echo "✗ No encontré el simulador '$DEVICE'. Disponibles:"
  xcrun simctl list devices available | grep -E '^\s+iPhone' | head -10
  exit 1
fi

echo "▸ Simulador: $DEVICE ($UDID)"
xcrun simctl boot "$UDID" 2>/dev/null || true   # ya booteado no es error
open -a Simulator

[ "$SOLO_BOOT" = "1" ] && { echo "✓ Simulador arrancado."; exit 0; }

# ── Bundle web al día ─────────────────────────────────────────
echo "▸ Sincronizando el bundle web…"
npx cap sync ios >/dev/null

# ── Compilar para simulador ───────────────────────────────────
# Se deja que Xcode firme como lo hace desde el IDE. NO usar
# CODE_SIGNING_ALLOWED=NO: sin firma el binario queda sin entitlements y
# HealthKit falla con este error exacto, que costó encontrar porque la UI
# solo dice "no se pudo activar":
#
#     Missing com.apple.developer.healthkit entitlement.
#
# Sí: el simulador VALIDA ese entitlement, aunque no valide otras cosas.
#
# Tampoco sirve re-firmar después con `codesign --force --entitlements`: los
# entitlements quedan en el binario pero la app deja de arrancar (SpringBoard
# la rechaza con POSIX 163), incluso firmando antes los frameworks internos y
# con `codesign --verify --deep --strict` en verde.
echo "▸ Compilando (esto tarda la primera vez)…"
DERIVED=$(mktemp -d)
xcodebuild -project ios/App/App.xcodeproj \
           -scheme App \
           -configuration Debug \
           -sdk iphonesimulator \
           -derivedDataPath "$DERIVED" \
           -quiet build

APP=$(find "$DERIVED/Build/Products" -name "*.app" -maxdepth 3 | head -1)
[ -z "$APP" ] && { echo "✗ No se generó el .app"; exit 1; }

# NO re-firmar acá. Ver el comentario de arriba: meter los entitlements a mano
# con `codesign --force` deja la app sin poder arrancar.

echo "▸ Instalando $(basename "$APP")…"
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" com.pumpteam.mypump

echo "✓ Listo. La app está corriendo en el simulador."
echo
echo "  Notificación de prueba:"
echo "    xcrun simctl push $UDID com.pumpteam.mypump scripts/push-test.json"
