# «Tu guía» en la app nativa de iPhone y iPad

Rama `nativa-guia-ios`. Espec: `~/pump-entregas/docs/ESPEC-APP-PUMP-TEAM.md`. Contrato: `entregas_010_app` y
`entregas_011` (el resumen). No hace falta ninguna migración nuestra.

## Qué hay

- **Tarjeta en Entreno** (la pestaña de inicio), arriba del aviso de Revisión. Aparece solo si `entregas_app_resumen`
  da `ok: true` con al menos un video, y muestra el avance («4 de 13 videos, te quedan 12 min»). La barra de pestañas no
  cambia (D16). También aparece en «Todavía no hay rutina».
- **Cómo se entera sin abrir la guía:** con `entregas_app_resumen` (solo lee, no marca `abierto_en`), al terminar cada
  carga de la cuenta y al volver a primer plano. Queda en caché (`guia_resumen.json` en la carpeta de la cuenta): sin red
  se ve lo último. Con `ok: false` la tarjeta desaparece y se borra la copia de la guía.
- **La sección** (`MyPump/Guia/GuiaView.swift`), con la línea de `pack.html`: cabecera («Hola Marcelo», el texto de Mati
  y el avance), el reproductor con «Video N de M · bloque», el título, Anterior, Siguiente y Velocidad, el «para qué» y la
  duda del video; después «Tu app», el recuadro de dudas para la videollamada (tope 30), los demás capítulos plegables
  (abierto el del video que suena), la suplementación por momento del día con «Ver por qué», y el pie. iPad: dos
  columnas, el reproductor fijo a la izquierda y la lista a la derecha.
- **Videos de los suplementos (A5, web del 4/11)**: un clip del bloque «Tu suplementación» que nombra un suplemento
  (nombre no vacío, estado distinto de «sale» y `video_id` no vacío, sin recortar) no va en la lista, ni en «Viste X de
  N», ni en el reproductor de arriba: se ve con «Ver por qué (N s)», que lo abre chico debajo del suplemento, con su
  recuadro de duda, y lo cierra al tocarlo de nuevo. Con el clip visto, el botón lleva el tilde. Su avance va por la
  misma cola (`guia_avance`). Suena un solo video a la vez. La regla (`ReglasGuia.deLaLista`) es la de `entregas_012`,
  así la tarjeta del servidor y la lista dan lo mismo.
- **`entregas_app_get`** se llama solo al abrir la sección, una vez por apertura. Sin red, la copia guardada
  (`guia.json`) con el aviso «Sin conexión: ves lo último que guardaste».
- **Reproductor** (`ReproductorGuia.swift`): AVPlayerViewController con los controles del sistema (pantalla completa y
  girar). Tocar una fila arranca directo; Anterior, Siguiente y el final de un video pasan al otro con la placa de 2,6 s
  («Otro tema · Video N de M», el bloque y el título), que se cierra sola o al tocarla, y con el video quieto mientras
  tanto. Retoma desde `segundos` (entre 5 s y 5 s antes del final, si no está visto). Sin red: «Necesitás conexión para
  ver el video» con Reintentar.
- **Avance:** cada 10 s de diferencia, al pasar el 80 % (con visto), al terminar y al salir del video, como la web. Va por
  la cola con el kind `guia_avance` (silencioso, una op por video: gana la última con el mayor de los segundos y visto
  si alguna lo tenía). Lo visto queda en la copia: al volver sin red, sigue visto.
- **Dudas:** `guia_duda` y `guia_duda_llamada` por la cola, sin deduplicar. Lo que está en la cola se ve con un reloj
  («Se envía sola apenas tengas señal»). Si la base devuelve `false` (tope o token) o la cola la abandona, el texto
  vuelve al campo con «No se pudo guardar».
- **Accesibilidad:** claro y oscuro, Dynamic Type (con letra de accesibilidad la fila apila título y duración), VoiceOver
  (fila con «Visto/Sin ver», la duración hablada y el video actual; placa como botón), toques de 44 pt o más.

## Lógica pura y tests

- `MyPumpReglas/Guia.swift`: orden y bloques, textos de avance, partes del motivo, fecha de la llamada, siguiente y
  anterior, retomar, velocidad, `AvanceVideo` (cuándo guarda) y `VistaSuplementacion` (port de `bloqueSuple`).
- `MyPumpModelos/Guia.swift`: modelos tolerantes y `ResumenGuia`. `GuiaMuestra`: la guía inventada de «Marcelo».
- `MyPumpDatos/Guia.swift`: `ModeloGuia` (lecturas, caché, cola, lo pendiente encima de lo del servidor).
- Tests del kit: `GuiaTests` (reglas, modelos, avance, suplementación), `GuiaModeloTests` (servidor falso) y
  `GuiaIntegracionTests` contra el servidor con `MYPUMP_GUIA_TOKEN` (y `MYPUMP_GUIA_ESCRIBIR_DUDAS=1` para las dudas).
- XCUITest: `GuiaUITests` con `scripts/nativa/probar-guia-ios.sh <udid>` (test-nativa-ios).
- Maqueta: `scripts/nativa/capturas-guia-ios.sh` → `~/Developer/nativa-evidencia/guia/maqueta/ios-*.png`.

## Argumentos de DEBUG

`-guiaMuestra YES` (la guía de muestra, sin red), `-abrir guia`, `-guiaAncla <id>`, `-guiaMotivo <id>`,
`-guiaPlaca YES`, `-guiaOkFalse YES` (lecturas de la guía con `ok: false`) y `-sinRed YES`.

## Simuladores

`guia-SE`, `guia-17Pro` y `guia-iPad` (iOS 26.5), en `~/Developer/nativa-evidencia/guia/simuladores-ios.txt`.
derivedData: `~/Developer/nativa-evidencia/dd/guia-ios`.
