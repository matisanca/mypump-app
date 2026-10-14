#!/bin/sh
# Copia a la app iOS lo que es canónico en apps/shared/:
#   - Muestras.bundle: respuestas reales de test-nativa-real (bocetos y previews);
#   - Demo.bundle: la demo de la web (SAMPLE_RUTINA/SAMPLE_DIET), la que ve App Review;
#   - Bases.bundle: la base de alimentos (MYPUMP_FOOD_DB calculada por la web) y el catálogo de ejercicios.
# Las carpetas .bundle se copian enteras al .app, sin aplanar nombres.
set -e
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
R="$RAIZ/apps/ios/MyPump/Recursos"
rm -rf "$R/Muestras.bundle" "$R/Demo.bundle" "$R/Bases.bundle"
mkdir -p "$R/Muestras.bundle" "$R/Demo.bundle" "$R/Bases.bundle"
cp "$RAIZ"/apps/shared/fixtures/test-nativa-real/*.json "$R/Muestras.bundle/"
cp "$RAIZ"/apps/shared/demo/*.json "$R/Demo.bundle/"
cp "$RAIZ"/apps/shared/food-db.json "$R/Bases.bundle/"
[ -f "$RAIZ"/apps/shared/catalogo-ejercicios.json ] && cp "$RAIZ"/apps/shared/catalogo-ejercicios.json "$R/Bases.bundle/"
echo "✓ $(ls "$R/Muestras.bundle" | wc -l | tr -d ' ') muestras y $(ls "$R/Demo.bundle" | wc -l | tr -d ' ') archivos de demo"
