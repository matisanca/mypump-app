# Tandas 2 a 4 y la web (plan aprobado por Mati el 3/11)

El detalle con nombres vive fuera del repo, en `nativa-evidencia/privado/PLAN_PEDIDOS_0211.md`. Cada tanda va en su rama, que sale de `nativa-202` (o de la rama de la tanda anterior, si depende de ella). Cada una lleva revisión opus y pruebas en las dos plataformas. Las compuertas de Mati no cambian: migraciones, la Mini, tags y tiendas, publicar la web y mensajes a clientes.

## Tanda 2 → 2.1
| # | Qué |
|---|---|
| S1 | **La pestaña «Progreso» pasa a llamarse «Salud»**, con tres segmentos. Siguen siendo 5 pestañas. **Recuperación:** el score, los motivos, la confianza, la tendencia de 14 días y el sueño, el corazón y la actividad. **Fuerza:** lo que hoy es Progreso, con récords y curvas. **Cuerpo:** el peso y su media, las fotos por semana y el check. La card de recuperación sale de Revisión, que queda solo para subir la semana. «Mi Día» se saca de todos lados |
| S2 | **Volumen por músculo:** las series efectivas por semana de cada músculo (el principal del catálogo, con la cadena de respaldo de E1), en Salud → Fuerza y en el cierre del día. Las series de preparación no cuentan |
| S3 | **Código de barras en Dieta:** el escáner del sistema (VisionKit en iPhone, ML Kit en Android) busca en Open Food Facts, que es gratis, sin clave y tiene muchos productos argentinos, y abre la misma hoja de cantidad de D1. Si el producto no está, se escanea la etiqueta con la IA que ya existe. Hay que actualizar los textos de permiso de la cámara si cambian |

## Tanda 3 → 2.2: Apple Watch
Un target watchOS nuevo, con la rutina del día y las series con la corona (reps y kg). El descanso avisa con háptica. Muestra la FC y las calorías en vivo con `HKWorkoutSession`, pero **no escribe en Salud todavía** (decisión de Mati). Se puede iniciar y terminar desde el reloj, y usarlo sin el teléfono, con una cola propia que se sincroniza al volver la conexión. La sincronización con el iPhone es inmediata (WatchConnectivity). Trae complicaciones (el próximo entreno y el descanso en curso) y un resumen al terminar. La preparación de E1 se muestra como en el teléfono. Lo que tiene que hacer Mati: crear el App ID y el perfil de firma, y la revisión de Apple. Android Wear queda para después.

## Tanda 4 → 2.3: conteo de reps
La 2.2 trae un **modo calibración**, oculto y por cuenta: graba el acelerómetro y el giroscopio (`CMBatchedSensorManager`) de cada serie, etiquetados con las reps cargadas a mano y con la familia de movimiento. No cuenta nada. Con esos datos se mide el error por familia. El conteo por picos y autocorrelación se prende solo en las familias que acierten ±1 rep en el 90 % de las series. Al terminar cada serie muestra «¿10 reps?» con la corona.

## Web igual a la app (en paralelo)
Se porta el diseño y las funciones de las apps, en este orden: Entreno y Dieta, después Salud, después Revisión y Chat. Entran Comí/Salté con porción, leer y escribir los ajustes de comida (incluido `agregados`), los sustitutos del mismo músculo, Siguiente →, el verde del logo, el modo oscuro y la preparación de E1. Sin «Mi Día». Cada parte se publica primero en una **vista previa** para que Mati la apruebe: un push a `main` publica al instante. También hay que corregir el progreso que se ve con un día de atraso para quien está en otra zona horaria (V1).
