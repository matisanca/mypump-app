# Capturas definitivas de Play — listas para subir

Sacadas de la app **en producción** (`app.mypumpteam.com`) con el cliente
sintético `en-ritmo` del banco de pruebas. Datos plausibles, ninguna persona
real. Se limpian con `scripts/cleanup-test-data.sql`.

| | |
|---|---|
| Tamaño | 1080×1920 (1,78:1 — Play corta en 2:1) |
| Cómo | `node scripts/capturas-tienda.mjs '[…]' "<url>"` |
| Qué muestran | Entreno · Chat · Dieta · Revisión — el tabbar de 1.0.6 |

## `--screenshot` de Chrome headless NO sirve

Es lo que dejó cortadas a la derecha las capturas viejas, y la nota anterior lo
daba por "artefacto de headless" sin explicarlo. La causa medida: headless
**ignora `--window-size` para el viewport de layout** (queda en 756 px) pero sí
lo aplica al lienzo de la captura, así que renderiza ancho y recorta angosto.

`scripts/capturas-tienda.mjs` va por CDP con `Emulation.setDeviceMetricsOverride`
(`mobile: true`), que es lo único que da un viewport móvil de verdad. Verificado:
`innerWidth=360` y `scrollWidth=360` — cero desborde.

El script también borra el banner de "Instalá MyPump como app": solo existe en
la versión web y en una ficha de Play sería absurdo.

## Progreso quedó afuera a propósito

El escenario `en-ritmo` tiene la carga plana, así que la pantalla muestra
`0.0%` cinco veces y **parece rota**. Play pide 2 como mínimo; cuatro que se
entienden valen más que cinco con una que asusta.

## Esto encontró un bug

La primera tanda mostró el selector de días **encima de los mensajes del chat**.
Era real y estaba en producción (commit del fix + check en `check-escenas.mjs`).
Sacar capturas de la app de verdad es una prueba de integración barata.
