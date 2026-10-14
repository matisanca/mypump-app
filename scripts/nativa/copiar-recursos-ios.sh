#!/bin/sh
# Copia a la app iOS lo que es canónico en apps/shared/:
#   - Muestras.bundle: respuestas reales de test-nativa-real (bocetos y previews);
#   - Demo.bundle: la demo de la web (SAMPLE_RUTINA/SAMPLE_DIET), la que ve App Review.
# Las carpetas .bundle se copian enteras al .app, sin aplanar nombres.
set -e
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
R="$RAIZ/apps/ios/MyPump/Recursos"
rm -rf "$R/Muestras.bundle" "$R/Demo.bundle"
mkdir -p "$R/Muestras.bundle" "$R/Demo.bundle"
cp "$RAIZ"/apps/shared/fixtures/test-nativa-real/*.json "$R/Muestras.bundle/"
cp "$RAIZ"/apps/shared/demo/*.json "$R/Demo.bundle/"
echo "✓ $(ls "$R/Muestras.bundle" | wc -l | tr -d ' ') muestras y $(ls "$R/Demo.bundle" | wc -l | tr -d ' ') archivos de demo"
