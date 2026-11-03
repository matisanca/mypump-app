# Pre-entrega: cómo integrarla (para MYPUMP PRO)

Rama `entregas/preentrega`, sacada de `nativa-202`. No está mergeada, no tiene tags ni builds de tienda.
La armó la obra pump-entregas (`~/pump-entregas`, ver `PLAN.md` y `CONEXIONES.md` allá).

## Qué es

Un cliente que ya pagó y completó el formulario recibe su cuenta y su token ANTES de la videollamada de comienzo.
Hoy, sin rutina publicada, la app cae al modo demo y no deja hacer nada. Con esto, si la base dice que está en
pre-entrega, se monta una portada encima del modo demo: activar avisos, perfil del gimnasio (cuando exista), videos
asignados con progreso, check de la semana 0 con fotos, formulario previo personalizado y chat.

## Archivos

- `public/js/preentrega.js` (nuevo): toda la portada. Lee y escribe solo por RPC.
- `public/cliente.html`: un `<script src="/js/preentrega.js">` y un gancho de ~10 líneas en la rama del modo demo
  del arranque (busca `Pre-entrega (preentrega.js)`). Con tope de 4 s; cualquier error deja la app como hoy.
- `public/js/config.js`: `PREENTREGA_ENABLED: false`. En localhost se prueba con `?preentrega=1`.
- `docs/ESQUEMA_PRODUCCION.txt`: regenerado con las RPC nuevas (para `check-contratos`).

`DATA._isDemo` sigue en `true`: el entrenamiento y la dieta de ejemplo no escriben nada. Chat, check y fotos
se llaman directo desde la portada.

## Base (ya aplicado en producción)

Migraciones de la obra (`~/pump-entregas/migraciones/entregas_00{1,2,3}`), con su REVERTIR:
`mypump_get_preentrega(p_token)`, `mypump_preentrega_progreso(p_token, p_video, p_segundos, p_visto)`,
`mypump_get_formulario_previo(p_token)`, `entregas_form_responder(p_clave, p_respuestas)`.
Mientras `entregas_config.preentrega.activo` y `entrevista.formulario_web` estén en false, la base solo responde
a clientes `test%`.

## Probado

- Web local con Playwright y la base real (cliente `test-entregas-pre01`): portada, chat, check, formulario, explorar y volver, sin errores de consola.
- `npm test`: todo verde salvo `test_sugerencia_coach`, que falla igual en `origin/nativa-202`.
- Revisión opus del diff: arreglados fotos (pasan por `_fotoAJpeg`), tope de arranque, capas (z-index 55, debajo de modales y toasts), avisos y repintado.

## Falta antes de prender el interruptor

1. Simulador iOS y Android real: en iOS el video abre con `@capacitor/browser` (los dominios propios no dejan cargar YouTube en el WebView); en Android probar el iframe de YouTube (errores 152/153).
2. Decidir quién contesta el chat de un cliente sin plan (app_chat.py contesta el chat general).
3. El check de la semana 0 usa `mypump_checkin_semanal` de la semana en curso: si la entrega cae esa misma semana, el primer check real lo pisa. Aceptable, pero que se sepa.
4. Sumar `youtube.com` a WKAppBoundDomains en un build futuro si se quiere el reproductor embebido en iOS.
5. Perfil del gimnasio: la portada llama a `window.abrirPerfilGimnasio()` si existe (MyPump Pro 2.0).
6. Formulario previo con nombre y datos (entregas_004, aplicada el 3/11): `mypump_get_formulario_previo` ahora devuelve también `nombre` y `datos_conocidos` ([{id: "dato_*", etiqueta, valor}]). La página web (`preguntas.html` del Cerebro) ya los muestra arriba, precargados y editables; si un dato cambia, se manda en `entregas_form_responder` con su id. En la portada de la app falta mostrarlos igual (hoy `preentrega.js` muestra solo las preguntas).
