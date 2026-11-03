# 2.0.3 — tanda 1 del plan de pedidos del 2/11

Plan aprobado por Mati el 3/11 (el detalle con nombres vive fuera del repo, en `nativa-evidencia/privado/PLAN_PEDIDOS_0211.md`).
Rama `nativa-202`. Sale con los tags `nios-2.0.3-<build>` y `nand-2.0.3-<code>`, con el OK de Mati para cada envío.

## Qué entra

| # | Qué | Dónde | Servidor | Compuerta |
|---|---|---|---|---|
| R1 | **Recuperación con `confianza` y `motivo_falta`** en la card y el detalle: chip «Confianza media/baja», el texto de qué falta cuando no hay score o está calibrando, y el score de confianza baja con aclaración | Salud/Recuperación, iOS y Android | `nativa_007` ya aplicada | — |
| R2 | **Aviso local de revisión**: no sale si la semana ya está completa (peso + fotos de la semana) y se reprograma al completar. Lee `revision_dia` (1 = lun … 7 = dom, default 7) cuando el servidor lo mande; sin el campo, domingo como hoy | Avisos, Revisión | `nativa_008_revision_dia` (borrador renumerado de la 007) | OK de Mati para la migración |
| E1 | **Calentamiento y aproximación** como bloque aparte antes de las efectivas, al estilo de la captura de referencia, con «Ocultar». Lo arma la app con el criterio de Mati (3/11). En los **multiarticulares**: calentamiento de 16 a 20 reps muy liviano, solo en el primer ejercicio del músculo; 2 aproximaciones de 5 reps al 60 y 85 %, o 1 al 75 % en el último ejercicio del músculo; y potenciación opcional en los principales, de 1 a 3 reps con +5 kg. En los **monoarticulares**, 1 aproximación de 5 a 6 reps solo en el primero de ese músculo. Descanso de 30 s; se tildan pero no se registran como carga | Entreno, ejercicio | Campo `aproximaciones` opcional en el ejercicio: solo pisa la regla en un caso puntual | — |
| E2 | **Descanso editable por ejercicio**: el cronómetro del ejercicio se toca y se elige otro tiempo; queda guardado para ese ejercicio (por clave) en el teléfono y le gana al del plan | Entreno | — | — |
| E3 | **Aviso de récord** apenas se confirma una serie: «Récord: +2,5 kg» o «Récord: +1 rep» contra lo mejor anterior de ese ejercicio (misma clave), con háptica y el dorado de los récords | Entreno | — | — |
| E4 | **RIR sin 0 por defecto**: el 48 % de los RIR cargados son 0 y el 0 es la primera opción. El selector arranca en el RIR objetivo del plan | Entreno | — | Decisión tomada en autónomo; se revierte fácil |
| D1 | **Sumar un alimento a una comida del plan** (base de alimentos o propio) con gramos o porciones y macros en vivo, sin pasar por extras; cuenta en el total del día y en lo consumido | Dieta | Clave nueva `agregados` dentro del ajuste de la comida (`mypump_ajustes_dieta.ajustes`, jsonb sin validación de claves) y en `resumen` | — |
| D2 | **Cantidades a la vista**: cada alimento de la comida se toca y abre la hoja de cantidad (gramos o porciones, macros en vivo), en vez de esconderlo en «Ajustar esta comida» | Dieta | — | — |
| D3 | **Mantener las macros del día**: si una comida sube por un cambio o un agregado, ofrece bajar las siguientes (el mismo mecanismo de «Hoy no la como») | Dieta | — | — |
| V1 | **Progreso con un día de atraso** (pedido viejo): verificar la zona horaria con una cuenta de prueba en otra zona | Progreso | — | — |

El código de barras va en la 2.1 (tanda 2), con la sección Salud y el volumen por músculo.

## Cómo se hace

- Entreno (E1-E4) y Dieta (D1-D3) los hacen dos agentes opus en paralelo, cada uno en su worktree y en las dos plataformas, con reglas en el kit y vectores compartidos cuando hay cálculo (sugerencia de kg de la aproximación, detección de récord, macros con agregados).
- R1, R2 y V1 van después, cuando se mergea lo anterior.
- Cada parte pasa por una revisión opus independiente antes del merge; lo que escribe datos (agregados en ajustes, aviso de revisión) con revisión adversarial.
- Pruebas: kit, JVM, XCUITest y Android UI de las pantallas tocadas, y el check de contratos.
- Al salir: avisarle a la sesión de Mensajes para que le escriba a quien pidió lo de la dieta, y a quien pidió las aproximaciones.
