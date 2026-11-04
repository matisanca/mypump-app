# Salud dentro de Revisión (2.1.0, 4-nov)

Pedido de Mati: «la parte de salud, como lo principal es recuperación, la integraría con la revisión y que justamente
se envíe como parte de la revisión, que aparezca arriba de todo ahí […] después si quieren ver más datos toquen ahí en
recuperación y lo vean […] y cuando manden la revisión que se incluya todo eso también».

Mismo comportamiento en iOS y Android.

## 1. Navegación

- Salud deja de ser pestaña **siempre** (con o sin suplementación). Barra: Entreno · Dieta · [Suplementación] · Chat ·
  Revisión.
- Salud se abre como hoja (el mecanismo que ya existía «con suplementación»: iOS `saludAbierta`, con «Listo») desde la
  tarjeta Recuperación de Revisión. El botón del corazón de la barra de arriba de Revisión se quita: lo reemplaza la
  tarjeta. Mis datos sigue igual.
- Avisos, links y `-pestana salud|progreso` que pedían Salud o un segmento (recuperación, fuerza, cuerpo, reloj, peso):
  pestaña Revisión + la hoja de Salud en ese segmento.
- Progreso sigue siendo el segmento «Fuerza» de Salud, y se abre directo desde la tarjeta «Tu progreso» (abajo). El
  destino viejo «progreso» abre Salud en Fuerza.

## 2. Tarjeta «Recuperación», arriba de todo en Revisión

Primer elemento de Revisión (antes del aviso de plan incompleto, las fotos y el check). En iPad/tablet ancha, a lo ancho
sobre las dos columnas. Toda la tarjeta es tocable y abre Salud en Recuperación. Identificador de accesibilidad
`tarjeta-recuperacion-revision`, pista «Abre Salud».

Contenido según el estado que ya calcula `SaludVista.cardRecuperacion` (no se duplica la lógica):

| Estado | Lo que muestra |
|---|---|
| `conScore` | El score grande («72») con «de 100», `bandaTexto` en el color de la banda, la pastilla de confianza si hay, y una línea: `frase` o, si no hay, el texto del primer motivo. `notaVieja` chica si viene. |
| `oculto` | «Ocultaste el número de recuperación. Tocá para ver tus datos de salud.» |
| `calibrando` | «Aprendiendo tu normal: n de 14 días» + `yaSe` si no está vacío. |
| `conectadoSinScore` | La `frase` del caso (y nada más). |
| `sinConectar` | «Conectá tu reloj o Salud para ver tu recuperación de cada día.» (el botón de conectar está adentro de Salud). |
| Demo / sin cuenta | «Con tu cuenta, acá vas a ver tu recuperación de cada día.» |

Al pie, una fila: «Ver sueño, corazón y cuerpo» con chevron.

### «Tu progreso» (aprobada por Mati el 4-nov)

Debajo de Recuperación, pegada (en el teléfono, las dos con poco espacio entre sí; en tablet, lado a lado). Mismo estilo:
«📈 Tu progreso», una línea de `ProgresoSemana.linea` (récords → ejercicios que subieron → sesiones de la semana;
vectores en `apps/shared/vectores/progreso_semana.json`) o, sin línea, «Tu fuerza y tus récords, ejercicio por
ejercicio.» en gris; al pie «Ver fuerza y récords». Abre Salud en Fuerza. Identificador `tarjeta-progreso-revision`.
Si el progreso no se cargó todavía, la tarjeta lo trae.

## 3. «Tu salud, últimos 7 días» en el check de la semana

- Bloque adentro de la tarjeta del check, arriba del botón «Enviar mi check». Título «Tu salud, últimos 7 días»; debajo,
  chico: «Va con tu check: Mati lo ve junto a tus respuestas.» Una fila por dato: etiqueta, valor y detalle
  («promedio de 5 días»).
- Las filas salen de la regla pura `SaludSemana.resumen(salud:recuperacion:hoy:mostrarScore:)`
  (iOS `MyPumpReglas/SaludSemana.swift`; Android, la misma en `core/reglas`, contra
  `apps/shared/vectores/salud_semana.json`). Sin filas, el bloque no se muestra.
- Entradas: las filas de salud y la recuperación de `ModeloSalud` (ya trae 60 días de salud y 14 de recuperación),
  `mostrarRecuperacion` y la fecha de hoy. La demo no tiene datos de salud: el bloque no aparece.
- Al enviar el check con cuenta: además de lo de siempre, se dispara la sincronización de salud (sin esperar ni frenar
  el envío) para que el servidor tenga los últimos días.
- **Sin migración**: el puntaje se calcula en Postgres (`mypump_calc_recuperacion`, 043) con `mypump_salud_diaria`, que
  la app ya sincroniza; el panel del coach lo lee con `mypump_get_recuperacion_cliente_coach` (044). Lo que ve el
  cliente es lo mismo que está en el servidor para esa semana. Que el brief/panel de la revisión lo muestre junto al
  check es del lado del coach (MYPUMP PRO / BOT MINI).

## 4. Pruebas

- La regla, contra los vectores, en las dos plataformas.
- Interfaz: la barra sin Salud (con y sin suplementación), la tarjeta arriba de Revisión que abre Salud, un aviso de
  fuerza/recuperación que abre Revisión + Salud en ese segmento, y el bloque del check en la demo. Ajustar las pruebas
  existentes que tocaban la pestaña Salud o el botón `abrir-salud`.
