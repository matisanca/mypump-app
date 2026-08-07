# Banco de pruebas — fabricar cualquier caso de cliente desde la Mac

> Para lo específico de Apple Health (el mock del plugin nativo, el simulador,
> los escenarios de sueño y HRV) mirá **BANCO_PRUEBAS_SALUD.md**. Este
> documento es el cliente entero: plan, entreno, dieta, revisión.

## El problema

Para ver cómo se comporta la app con un cliente en la semana 13 de un
macrociclo, había que esperar a que existiera uno. Los bordes —el plan sin
`macros_target` que deja la app en blanco, el día sin ejercicios, la dieta de
2 opciones— no se veían nunca hasta que le pasaban a alguien.

## Arrancar

```bash
node scripts/seed-cliente.mjs --lista
```

Lista los escenarios con lo que cada uno reproduce y **qué hay que mirar** en
cada uno. Después:

```bash
node scripts/seed-cliente.mjs --escenario macrociclo-2            # genera el SQL
node scripts/seed-cliente.mjs --escenario macrociclo-2 --aplicar  # + siembra la historia
npm run dev
open "http://localhost:3000/cliente.html?t=BANCO_MACROCICLO_2_TOKEN"
```

## Por qué son dos pasos

Los permisos de Supabase están partidos al medio, y está bien que lo estén:

| | Quién escribe | Permiso | Cómo lo hace el banco |
|---|---|---|---|
| **El plan** (rutina + dieta) | el coach | `authenticated` | emite un `.sql` para pegar en el SQL Editor |
| **La historia** (sesiones, cargas, comidas, checks, peso, comentarios, salud) | el cliente | `anon` + token | lo aplica solo, por RPC |

La historia va por **las RPC reales**, no por `INSERT`. Un insert directo se
saltea los CHECK, los triggers y las reglas que viven adentro de las funciones:
el banco estaría probando una base que la app nunca produce. Yendo por la RPC,
si mañana alguien le agrega una validación a `mypump_registrar_carga`, el banco
se entera.

Si tenés `SUPABASE_SERVICE_KEY` exportada, el script también aplica el plan solo.
Sin ella, pegás el `.sql` una vez y el resto es automático.

## Los escenarios

**Los que existen de verdad hoy entre los 50 clientes**

| escenario | qué reproduce |
|---|---|
| `recien-vinculado` | le publicaron el plan y no abrió la app. Día 1 de todo |
| `primera-semana` | entrenó un par de veces, sin histórico previo |
| `en-ritmo` | el cliente promedio — la línea de base |
| `macrociclo-2` | semana 13 de 24, con `semana_offset = 12` |
| `ultima-semana-con-cola` | semana 12/12 con el bloque siguiente encolado |
| `ultima-semana-sin-cola` | terminó el plan y no hay siguiente |
| `abandonado` | entrenó 4 semanas y hace 3 que no aparece |
| `estancado` | cumple pero la carga no sube hace 5 semanas |
| `fundido` | adherencia alta, energía y descanso por el piso |
| `sin-reloj` | iPhone sin Apple Watch — el caso de Mati |
| `come-mal` | entrena bien, marca la mitad de las comidas |
| `con-comentarios` | comentarios del coach sin leer |

**Los bordes que rompen la app**

| escenario | qué pasa hoy |
|---|---|
| `sin-dieta` | ve `SAMPLE_DIET` (3200 kcal) como si fuera su plan, **sin ningún aviso** |
| `plan-sin-macros` | **rompe el arranque entero**: pantalla en blanco, no puede ni entrenar |
| `plan-sin-dias` | la app no arranca nunca, se queda cargando |
| `dia-vacio` | progreso `NaN` y "sesión completa" sin haber entrenado |
| `sin-descanso` | chip `NaN:NaN` y timer de descanso eterno |
| `dieta-2-opciones` / `dieta-1-opcion` | la grilla A/B/C/D asume 4 |
| `alimentos-por-unidad` | `unit: 'unidad'` sin `unitGrams` — **toda dieta publicada hoy** |

## El lado del coach

Por defecto los clientes del banco son **invisibles** para el centinela y el
Radar: el `cliente_id` arranca con `test-` y `centinela.py:1103` descarta ese
prefijo. Es una red de seguridad — sin ella los sintéticos aparecerían en el
radar real mezclados con gente.

Cuando lo que querés probar **es** el lado del coach:

```bash
node scripts/seed-cliente.mjs --escenario estancado --visible-al-coach --aplicar
```

Eso los nombra `banco-*`, que el filtro no descarta. **Acordate de limpiar
después**, o el domingo el centinela le va a mandar a Mati el análisis de un
cliente que no existe.

## Limpiar

```sql
-- Supabase → SQL Editor
\i scripts/cleanup-test-data.sql
```

Borra las 20 tablas para `test-001`, `test-banco-*` y `banco-*`. Termina con un
`SELECT` que tiene que dar 0 filas.

## Determinismo

Todo sale de un PRNG sembrado (`--seed`, default 42). El mismo escenario con la
misma semilla produce exactamente el mismo cliente — si no, un caso que falla
sería irreproducible.

## Qué NO cubre todavía

- **Fotos de progreso**: la subida va por `mini-vision` con su propia cola, no
  por RPC. Hay que subirlas a mano desde la app.
- **El blob del Cerebro** (`nutriplan_data`): el panel lee siempre `id='main'`,
  el de producción. Un cliente del banco no aparece en su sidebar.
- **Universal Links y arranque en frío nativo**: eso es simulador o iPhone.

## Si algo no coincide con producción

Los tests de `scripts/test-plan-sintetico.mjs` anclan la forma que genera el
banco contra la que produce el Cerebro: el formato de los ids de ejercicio, que
las opciones A/B/C/D de una comida valgan lo mismo entre sí, que el bloque en
cola vaya como `estructura_siguiente` de la fila activa. Si el Cerebro cambia
de forma, esos tests son los que avisan.

```bash
npm test    # los corre junto con el resto
```
