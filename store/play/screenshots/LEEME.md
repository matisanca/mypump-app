# Borradores, NO subir todavía

Sacadas de la app real (`app.mypumpteam.com/cliente?demo=1&scene=…`) con Chrome
headless. Sirven para ver forma y calidad. **No son las definitivas.**

| | |
|---|---|
| Tamaño | 1080×1920 — 1,78:1, dentro del límite de Play (el lado mayor no puede ser más del doble que el menor) |
| Problema de fondo | sale el cartel **"Modo demo — Mati todavía no publicó tu plan"** |
| Problema de forma | headless recorta a la derecha; **no es un bug de la app** (medido con emulación real: documento de 375 px, sin desbordes, 5 tabs visibles) |

Para las definitivas: sembrar un cliente sintético con el banco de pruebas
(`docs/BANCO_PRUEBAS.md`), capturar eso, y limpiar con
`scripts/cleanup-test-data.sql`. Datos plausibles, ninguna persona real.

**Las de iOS no sirven**: 1290×2796 es 2,17:1 y Play corta en 2:1.
