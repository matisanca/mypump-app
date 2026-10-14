# Lista de paridad: app actual → nativas

> Cada fila es algo que la app actual hace y que las nativas tienen que hacer igual. Un ítem se tilda solo con
> evidencia: un test, una captura en `~/Developer/nativa-evidencia/` o una consulta.
>
> Lo que quede afuera lo decide Mati, por escrito, en la sección "Decisiones".
>
> - Fuentes: `C` = `public/cliente.html`, `SC` = `supabase-client.js`, `NT` = `notificaciones.js`,
>   `HK` = `healthkit-bridge.js`, `A` = `app.js`; las memorias están citadas por nombre.
> - Columnas: **iOS** / **And** = ☐ pendiente · ✅ verificado (con evidencia) · ➖ no aplica.

## Decisiones de Mati (G1)

Hasta que se decidan, rige lo de hoy.

| # | Tema | Hoy | Propuesta |
|---|---|---|---|
| D1 | Días comodín | se ven como un día más (no se lee `es_comodin`) | distintivo "comodín" |
| D2 | `mensajes_semana` y `progresion[].titulo` | no se muestran | mostrarlos en el encabezado de la semana |
| D3 | Mis datos | solo desde la card de Recuperación (inalcanzable sin score); el diagnóstico está tras 5 toques | entrada fija con recordatorios, Salud, diagnóstico, política de privacidad y "Eliminar mis datos" |
| D4 | Textos que mienten | el onboarding promete un recordatorio de entreno que no existe, y "Domingos al mediodía" es a las 11:00 | corregirlos |
| D5 | Tema | arranca en claro e ignora el sistema | seguir al sistema salvo que `'dark'` esté guardado |
| D6 | Verde | interfaz lima `#b8f060`, ícono esmeralda `#10b981` | lima en la interfaz e ícono sin cambios |
| D7 | IA de terceros (5.1.2(i)) | sin aviso; la IA habla como Mati | consentimiento único al abrir el chat o la foto del plato |
| D8 | Fin de descanso con la app en segundo plano | sin aviso | notificación local |
| D9 | Borrado de cuenta | solo `eliminar-datos.html` (mail) | link desde Mis datos, más una RPC opcional que solo registra el pedido |

## ACC · Acceso, errores y demo

| ID | Comportamiento | Fuente | iOS | And |
|---|---|---|---|---|
| ACC-01 | Token por universal link o app link `app.mypumpteam.com/?t=`, `/cliente?t=` o `/cliente.html?t=`, con regex `^[a-zA-Z0-9_-]{16,64}$` | `deeplink.js`, AASA | ☐ | ☐ |
| ACC-02 | Orden de resolución: `?t=`, path, guardado. Un `?t=` igual a `mypump_token_invalido` no pisa a uno guardado válido | `C:1257-1299` | ☐ | ☐ |
| ACC-03 | Sin token: "Bienvenido a MyPump", campo "pegá tu link" que acepta URL entera, a medias o el token solo, y "Ver demo" | `index.html:376-423`, `C:3415+` | ☐ | ☐ |
| ACC-04 | Token inválido (`[]` sin error): "Este link ya no sirve", borra el token, guarda `token_invalido` y deja pegar uno nuevo | `C:3415-3484` | ☐ | ☐ |
| ACC-05 | Servicio caído o sin red sin copia: "Sin conexión" o "Servicio fuera de línea", Reintentar, una sola recarga automática al volver la red | `C:3485-3504` | ☐ | ☐ |
| ACC-06 | Arranque sin red con copia offline: muestra plan y dieta guardados con el banner sin conexión | `C:8699-8711`, `8933` | ☐ | ☐ |
| ACC-07 | Demo: datos empaquetados, **sin red ni token**, sin chat, comentarios, comidas libres, relojes ni onboarding; Mi Día sembrado (racha 3) | `C:1240`, `1409-1550`, `8870` | ☐ | ☐ |
| ACC-08 | Sin rutina usable → rutina de ejemplo con banner "Modo demo — Mati todavía no publicó tu plan". Sin dieta → dieta de ejemplo con escrituras apagadas (`_dietaEjemplo`) | `C:8766-8800` | ☐ | ☐ |
| ACC-09 | Parámetros `?scene=<destino>` (validado contra las escenas) y `?diag=health` | `C:8587-8594`, `8673` | ☐ | ☐ |
| ACC-10 | Cambio de cuenta: llega un link con otro token válido → reemplaza (como la web) | `deeplink.js:15-43` | ☐ | ☐ |

## GEN · Estructura, avisos y ciclo de vida

| ID | Comportamiento | Fuente | iOS | And |
|---|---|---|---|---|
| GEN-01 | 5 tabs: Entreno · Dieta · Chat · Revisión · Progreso. Mis datos es una escena aparte que marca Revisión | `C:1109-1143`, `8498-8559` | ☐ | ☐ |
| GEN-02 | Header: "DÍA n • SEM x/y" (con `semana_offset`), título y tema | `C:1058-1075` | ☐ | ☐ |
| GEN-03 | Badges: Entreno = comentarios de ejercicio sin leer; Chat = mensajes sin leer; Revisión = cosas que faltan de la semana (check + fotos), con banner que lleva a Revisión desde las otras escenas | `C:2184-2202`, `2318-2325`, `7647-7684` | ☐ | ☐ |
| GEN-04 | Toast de guardado con 4 estados: "Guardando…" (si tarda más de 900 ms), "✓ Guardado" (después de un problema), "Sin conexión — se reintenta solo" y "⚠ Algo no se pudo guardar…" (9 s, se cierra tocándolo) | `C:2649-2685` | ☐ | ☐ |
| GEN-05 | Aviso único "a tu plan le falta información" arriba de Revisión | `C:1882-1896` | ☐ | ☐ |
| GEN-06 | Onboarding de permisos (primera apertura, 1,2 s después de pintar): Salud → Notificaciones. "Ahora no" nunca dispara la hoja del sistema; Salud corta a los 20 s; si deniega, muestra la ruta en Ajustes. Clave `mypump_onboarding_v1` | `C:4447-4593` | ☐ | ☐ |
| GEN-07 | Al volver a primer plano: recalcula el descanso, drena el outbox y la cola de fotos, actualiza el chat; si cambió el día, recarga comidas, comidas libres y Mi Día | `C:5031-5058` | ☐ | ☐ |
| GEN-08 | Movimiento reducido respetado | `C:1000-1003` | ☐ | ☐ |
| GEN-09 | Respaldo científico: fila al pie de Dieta, Entreno y Mi Día | `C:4712-4714` | ☐ | ☐ |

## ENT · Entreno (vista)

| ID | Comportamiento | Fuente | iOS | And |
|---|---|---|---|---|
| ENT-01 | Selector de días: "DÍA n" + primera palabra del nombre; ✓ si se cerró esta semana (`get_sesiones_semana`); 💬 si hay comentarios | `C:3528-3559` | ☐ | ☐ |
| ENT-02 | Día inicial = el último que se vio en ese teléfono (`mypump_dia_visualizado_<RUTINA>`) o el primero. No usa el calendario | `C:1898-1911` | ☐ | ☐ |
| ENT-03 | Los ids de día son claves opacas (`d<n>`, `b<v>d<n>`, `r<n>d<n>`, `lun`…); nunca se parsean | memoria `reference_publicar_ids_dia_trainplan_viejo` | ☐ | ☐ |
| ENT-04 | `normalizarRutina`: día sin id → `d<i>`; descanso ausente o ≤0 → 90 s; series ≤0 → 1; `semanas_total` → 12; bloques `null` se ignoran | `C:1797-1840`, memoria `reference_editar_rutina_viva` | ☐ | ☐ |
| ENT-05 | Bloques "B{i} · NOMBRE · hechos/total"; las biseries van por título y `notas_tecnica` (no hay biserie nativa) | `C:3598-3611` | ☐ | ☐ |
| ENT-06 | Progresión: `progresion[semana-1]` acotada al largo del array, o los campos viejos | `C:1679-1694` | ☐ | ☐ |
| ENT-07 | Nota de progresión contra la semana anterior (baja de reps, suba de series, baja de RIR). Banner "📈 N ejercicios cambian…" | `C:1701-1747`, `3669` | ☐ | ☐ |
| ENT-08 | "🎯 Semana de calibración" **solo** en la semana 1 sin offset | `C:3669-3678`, memoria `reference_activar_bloque_colision_sesiones` | ☐ | ☐ |
| ENT-09 | `semana_offset` solo cambia rótulos ("SEM 13/24", "Pasar a Semana N") | `C:3183`, `3673`, `3732`, `5286` | ☐ | ☐ |
| ENT-10 | Card cerrada: círculo de estado (n, ✓, ✓ sin datos, —), miniatura, badge de sustitución (🔒 fijada / ↔ solo hoy), chip "manual", 💬 n, chips CALENT., ×series·reps, descanso m:ss, "🏆 Récord" o "Primera vez" | `C:3816-3863` | ☐ | ☐ |
| ENT-11 | Card abierta: nota, selector de variante, tabla Reps/Kg/RIR, "📅 Última vez (ayer / hace n días)", "🏆 Récord a superar", imágenes Inicio/Pico, sustituir/volver, comentarios, nota técnica, video y acciones | `C:3866-3971` | ☐ | ☐ |
| ENT-12 | Fotos de ejercicios: `images._matched_slug` (no `catalogo_slug` de primer nivel) | memoria `reference_sustitutos_ejercicio_app` | ☐ | ☐ |
| ENT-13 | Sin columna de kg: calentamiento, o peso corporal por regex, salvo que el nombre mencione carga | `C:4004-4021` | ☐ | ☐ |
| ENT-14 | Avanzar de semana: visible si semana < total; la confirmación cambia si el día está incompleto; `avanzar_semana(actual+1)`, que nunca retrocede; borra los cachés de sesión y recarga; error "Sin conexión" o "No se pudo pasar de semana" | `C:3108-3139`, `3178-3194`, mig 077 | ☐ | ☐ |
| ENT-15 | Última semana con bloque en cola: "🎉 Empezar bloque nuevo" → `activar_siguiente` | `C:3141-3176`, `3740-3748` | ☐ | ☐ |
| ENT-16 | Vacío: "Este día no tiene ejercicios cargados…" | `C:3634` | ☐ | ☐ |
| ENT-17 | Al completar un ejercicio se abre el siguiente pendiente. Con todos hechos: "¡Día completado!" → siguiente día, o avanzar si es el último | `C:3196-3229` | ☐ | ☐ |

## SER · Series, historial, sustitutos y variantes

| ID | Comportamiento | Fuente | iOS | And |
|---|---|---|---|---|
| SER-01 | Un toque registra las reps de la última vez (misma serie y variante) o el tope del rango, y el kg de la última vez. Con AMRAP/∞/máx no hay registro de un toque | `C:4066-4072`, `4144-4230` | ☐ | ☐ |
| SER-02 | El RIR **nunca** se autocompleta; selector 0-5 que reenvía si la serie ya estaba confirmada. RIR 0 ≠ null | `C:4595-4623`, memoria `project_motor_recuperacion` | ☐ | ☐ |
| SER-03 | El kg se hereda de la serie anterior confirmada. Pista de calibración la primera vez | `C:1618-1627`, `4049` | ☐ | ☐ |
| SER-04 | Al tocar un campo se selecciona todo; en kg la coma pasa a punto; en reps solo dígitos | `C:4275-4304`, `4089-4099` | ☐ | ☐ |
| SER-05 | Topes: reps 1-300 y kg ≤2000 se rechazan. Pregunta si kg > 600, si kg > 2,5× el récord (con récord ≥10) o si reps > max(30, 3× la referencia) | `C:4085`, `4118-4142`, test `test-series-verosimiles` | ☐ | ☐ |
| SER-06 | El lápiz desconfirma la serie | `C:4323` | ☐ | ☐ |
| SER-07 | Variantes por regex (rueda → Nivel sin peso; tríceps en polea, jalón, remo en polea y curl en polea → Agarre). Viajan en `registros_carga.notas` y se restauran de ahí; las filas viejas sin nota cuentan solo para la opción por defecto | `C:3983-4003`, `1577-1599`, `3259-3266` | ☐ | ☐ |
| SER-08 | Historial por **clave** del nombre efectivo, 48 filas, un pedido por día; récord = la serie más pesada de lo traído | `C:3331-3406`, `1564`, mig 072 | ☐ | ☐ |
| SER-09 | PGRST202 = camino viejo; `null` = red, se reintenta. Nunca se cae al camino por lugar por un corte | memoria `project_historial_por_identidad` | ☐ | ☐ |
| SER-10 | Carrera: una respuesta vieja no pisa el historial de un lugar ya sustituido | idem (`_histPromises`) | ☐ | ☐ |
| SER-11 | Sustitutos: mismo `patron_movimiento` y `primary_muscle`, otro equipo primero, máximo 30; no aplica a calentamiento ni cardio; búsqueda; "🔒 Fijar para las próximas semanas" (sin tildar = solo hoy) | `A:692-737`, `C:9187-9324` | ☐ | ☐ |
| SER-12 | Poda: los no fijados se borran al cambiar de semana o al cerrar ese día; los fijados duran. Una entrada sin `fijado` cuenta como fijada | `C:2137-2161`, `8826-8836` | ☐ | ☐ |
| SER-13 | Con sustitución, la serie se guarda con el nombre del sustituto (el historial lo sigue) y el `ejercicio_id` del lugar. Aplicar o revertir invalida y vuelve a pedir el historial | `C:3008-3011`, `2040-2117` | ☐ | ☐ |
| SER-14 | Sustituciones **en el servidor** (tabla nueva, G2): también desde otro dispositivo de la nativa | plan | ☐ | ☐ |
| SER-15 | Estados: "Marcar completo" exige todas las series confirmadas; "Terminé este ejercicio" sin series pide confirmación y lo deja `completo_sin_datos` manual; reabrir | `C:4337-4392` | ☐ | ☐ |

## SES · Sesión, cronómetro, descanso y cierre

| ID | Comportamiento | Fuente | iOS | And |
|---|---|---|---|---|
| SES-01 | La sesión se crea con la primera serie o con "Empezar entrenamiento" (`iniciar_sesion` idempotente) | `C:2989`, mig 075 | ☐ | ☐ |
| SES-02 | Se restaura la sesión del día **confirmándola con el servidor**: si el servidor no la devuelve, se descarta la local (nada de sesiones fantasma), sin pisar series ya confirmadas en el teléfono | `C:2983-3002`, `3235-3327`, rama `fix/sesion-cache-valida-servidor` | ☐ | ☐ |
| SES-03 | Cronómetro por día; con más de 6 h muestra "SIN CERRAR · Empezar de nuevo" y la duración va null | `C:1337-1358`, `3683-3711` | ☐ | ☐ |
| SES-04 | Descanso al confirmar una serie (salvo calentamiento): 90 s si falta o es 0; −15 / +15 / Saltar; al terminar, sonido, vibración y barra verde que se cierra a los 2 s. Persiste (`endsAt`) | `C:4841-5027` | ☐ | ☐ |
| SES-05 | El sonido del descanso no corta la música del cliente (sesión de audio `.ambient`) | nativo | ☐ | ☐ |
| SES-06 | Cerrar el día: modal con series · reps · kg y notas (o versión anticipada con hasta 3 pendientes); **primero vacía el outbox**, después `finalizar_sesion`; con `false`, aviso | `C:4626-4709`, `3047-3085` | ☐ | ☐ |
| SES-07 | Cargar una serie en un día cerrado pregunta "Reabrir día" y usa la misma sesión | `C:4155`, `4164` | ☐ | ☐ |
| SES-08 | Comentarios por ejercicio: van directo (no por el outbox) con aviso si fallan; se marcan leídos al abrir la card | `C:2163-2246`, `3928-3946` | ☐ | ☐ |

## DIE · Dieta

| ID | Comportamiento | Fuente | iOS | And |
|---|---|---|---|---|
| DIE-01 | Formato A (`comidas`) y B (`tipos_dia[]`, con su `macros_target`); selector entreno/descanso guardado en `mypump_tipo_dia` (global) | `C:1931`, `5255`, `5774`, `docs/SCHEMA_DIETA.md` | ☐ | ☐ |
| DIE-02 | `normalizarDieta`: sin `macros_target` → suma de la opción A; comidas sin opciones se descartan; `tipos_dia:[]` cuenta como ausente | `C:1842-1878` | ☐ | ☐ |
| DIE-03 | Cabecera: anillo de kcal consumidas/objetivo, "DIETA · SEM", macros objetivo, "Consumido hoy n/m" y **renglón de respaldo dentro de la card de macros** (Mifflin-St Jeor, ISSN, NASEM) | `C:5272-5312`, memoria `project_app_store_connect_metadata` | ✅ D10: objetivo + "con las opciones elegidas" (capturas `dieta/v3`) | ☐ |
| DIE-04 | Opciones A/B/C/D **por comida** (se combinan entre comidas); la elegida vive en memoria y vuelve a A al recargar | `C:5693`, memoria `feedback_opciones_intercambiables_por_comida` | ✅ | ☐ |
| DIE-05 | "✓ Comí" / "✗ Salté"; tocar de nuevo desmarca; la marca guarda la opción vigente | `C:5114-5183` | ➖ D10 | ☐ |
| DIE-06 | Consumo parcial: "Comí" + destildar alimentos → `foods_excluidos` (índices de esa opción); solo se puede mirando esa opción | `C:5140-5183`, `5740` | ➖ D10 | ☐ |
| DIE-07 | Consumido = comidas marcadas − excluidos (con sustituciones) + comidas libres | `C:5185` | ➖ D10 | ☐ |
| DIE-08 | Porción casera ✋ por alimento | `C:5464-5656` | ✅ vectores `porcion_casera` + XCUITest `testLaMano…` | ☐ |
| DIE-09 | Sustituir ↔ salvo condimentos o `swappable:false` ("Este alimento no se puede sustituir") | `C:5658` | ✅ | ☐ |
| DIE-10 | Modal de sustitutos: búsqueda; 🌍 universales arriba con nombre en inglés; ★ propios; diferencia de kcal (bien hasta 5 %); exclusiones del cliente (cerdo, mariscos, lácteos); misma categoría y macro dominante; desvío ≤35 %; top 30 | `A:19-394`, `C:8978-9150` | ✅ 2.510 vectores + XCUITest `testReemplazar…` (iOS 17.5 y 26.5) | ☐ |
| DIE-11 | Swaps anclados (`food_data._orig`): valen si esa huella está en esa posición en **cualquier** tipo de día; sin ancla se anclan y se suben; si el ancla ya no existe en ningún tipo de día se **borran** del servidor | `C:1981-2024`, `5878-6034`, test `test-swaps-anclados` | ✅ vectores `anclaje_swaps` + integración | ☐ |
| DIE-12 | Al hidratar, lo pendiente en el outbox gana; una reversión pendiente no resucita el swap | `C:5963-6018` | ✅ `SwapsDeComidaTests` | ☐ |
| DIE-13 | `food_data` lleva macros **totales** para su `qty`; un contable va en unidades | memoria `reference_food_swaps_sobreviven_publicar` | ✅ vectores de sustitutos | ☐ |
| DIE-14 | Alimento propio: unidad g/ml/unidad/rebanada/taza/porción/cucharada, gramos por unidad, "📷 Escanear etiqueta", kcal 4/4/9 si faltan, se guarda **por 100 g**, "Crear y usar" lo aplica | `C:9327-9636` | ✅ `AlimentoPropioNuevoTests` + integración; escaneo sin probar con la IA | ☐ |
| DIE-15 | Comida libre por foto del plato (~30 s, gramos editables que re-escalan macros, "estimado") o a mano; borrar con ✕ (optimista con rollback) | `C:5221-5448` | ✅ a mano: XCUITest + integración; foto sin probar con la IA | ☐ |
| DIE-16 | Si la visión falla: aviso y carga a mano | `C:9474+` | ✅ | ☐ |
| DIE-17 | Sin dieta: dieta de ejemplo con aviso y escrituras apagadas | `C:8784-8800` | ☐ | ☐ |
| DIE-18 | Si cambió el día con la app abierta, al volver recarga marcas y comidas libres | `C:5049` | ☐ | ☐ |
| DIE-19 | Fecha local con la tolerancia del servidor (+1/−7): marcar no se "desmarca solo" en otra zona horaria | memoria `project_timezone_marcar_comida` | ✅ `FechaLocal` | ☐ |

## DIA · Mi Día (dentro de Revisión)

| ID | Comportamiento | Fuente | iOS | And |
|---|---|---|---|---|
| DIA-01 | Racha: 🔥 desde 7, ⚡ desde 3, ✨ desde 1, 💤 en 0 | `C:8245+` | ☐ | ☐ |
| DIA-02 | Entrené / Descansé / Falté | `C:8373-8398` | ☐ | ☐ |
| DIA-03 | Hábitos ✓/✗ (tocar de nuevo los borra): comí según el plan, dormí bien, **hice cardio** | `C:8314-8319`, mig 022 | ☐ | ☐ |
| DIA-04 | Agua 0-12 vasos, guardada 600 ms después del último toque | `C:8460` | ☐ | ☐ |
| DIA-05 | "Mis últimos 30 días": grilla cumplido/parcial/vacío con "X/30", que se carga al abrirla | `C:8412-8424` | ☐ | ☐ |
| DIA-06 | Lo pendiente en el outbox gana sobre lo del servidor | `C:6270-6276` | ☐ | ☐ |

## REV · Revisión

| ID | Comportamiento | Fuente | iOS | And |
|---|---|---|---|---|
| REV-01 | Orden: Fotos → Check → Peso → Mi reloj → Mi Día | `C:8052-8086` | ☐ | ☐ |
| REV-02 | Fotos frente/perfil/espalda desde cámara o galería (HEIC incluido); JPEG de 900 px a 0,7, sin ubicación; orientación correcta | `C:7476-7962`, memoria `project_mypump_ios_estado` | ☐ | ☐ |
| REV-03 | Cola de fotos: máximo 3, rechaza más de 2,4 MB, 8 intentos por errores del servidor (los de red no cuentan), 4xx distinto de 429 = definitivo; "Hay fotos esperando subir" | `C:7487-7602` | ☐ | ☐ |
| REV-04 | "🔥 N semanas seguidas"; galería por semana; comparador antes/después desde 4 semanas, con Δkg | `C:7600-7660` | ☐ | ☐ |
| REV-05 | URLs firmadas (`/progreso/urls`), cacheadas 50 min | `C:7617-7641` | ☐ | ☐ |
| REV-06 | Check semanal: 4 escalas 1-5 + nota; "Faltan: X"; va por el outbox y muestra "✓ enviado" | `C:7964-8034` | ☐ | ☐ |
| REV-07 | Peso 30-300 kg por el outbox (fuente manual); gráfico de 60 días con media de 7; "Esta semana ±g vs la pasada" | `C:7330-7464` | ☐ | ☐ |
| REV-08 | Mi reloj: Oura/WHOOP según `/api/wearables/disponibles` o si ya estaba conectado; autorización en el navegador del sistema (SFSafariViewController); poll de `get_conexiones` cada 3 s durante 2 min; "Quitar" con confirmación | `C:8088-8239` | ☐ | ☐ |

## PRO · Progreso

| ID | Comportamiento | Fuente | iOS | And |
|---|---|---|---|---|
| PRO-01 | Esqueleto de carga; totales Ejercicios / Sesiones | `C:6036-6249` | ☐ | ☐ |
| PRO-02 | Secciones por día, con un mismo ejercicio agrupado entre días (por clave) | idem, mig 072 | ☐ | ☐ |
| PRO-03 | Fila: 🏆 PR (la última sesión superó a todas), Top, gráfico del máximo por sesión (últimas 8) y Δ% (no invertido) | idem, memoria `project_mypump_plan_maestro` | ☐ | ☐ |
| PRO-04 | Detalle: gráfico + tabla de 8 filas (fecha, peso, reps, RIR) | idem | ☐ | ☐ |
| PRO-05 | Vacío "Aún no hay historial…"; sin red "No pudimos traer tu historial" + Reintentar | idem | ☐ | ☐ |

## CHA · Chat

| ID | Comportamiento | Fuente | iOS | And |
|---|---|---|---|---|
| CHA-01 | Burbujas "Vos" / "Mati", separadores Hoy / Ayer / fecha; vacío "Escribile a Mati…"; "Ver mensajes anteriores" de a 30 | `C:2248-2538` | ☐ | ☐ |
| CHA-02 | Hasta 1000 caracteres; lo que estás escribiendo sobrevive cuando llega un mensaje | idem | ☐ | ☐ |
| CHA-03 | Envío por el outbox con "enviando…" al instante; se reemplaza con la fila real; "no salió" + Reintentar si se abandona | `C:2443-2470` | ☐ | ☐ |
| CHA-04 | Poll de 15 s con el chat abierto, 45 s en otra pantalla, nada en segundo plano; al abrir marca leídos (`general`) | `C:2493`, `2483` | ☐ | ☐ |
| CHA-05 | La IA llega como `autor='coach'` y se ve como Mati (salvo D7) | migs 060, 062 | ☐ | ☐ |
| CHA-06 | Polling, no Realtime (la anon key es compartida) | memoria `project_chat_mypump` | ☐ | ☐ |

## SAL · Salud, recuperación y Mis datos

| ID | Comportamiento | Fuente | iOS | And |
|---|---|---|---|---|
| SAL-01 | Mismos tipos, agregaciones, unidades y `fuente` que el bridge (`apple_health` / `health_connect`). Sin `vo2Max` ni `totalCalories` | `HK:56-195` | ☐ | ☐ |
| SAL-02 | Pasos, kcal activas y FC en reposo agregados como el plugin: medianoche local, `.strictStartDate` y `defaultUnit` | `@capgo/.../Health.swift:1505-1556` | ☐ | ☐ |
| SAL-03 | Sueño: por noche gana la fuente con más sueño real; noches cortadas por huecos de más de 60 min; la noche va a la fecha del despertar; "en cama" ×0,9 estimado si no hay etapas; siestas suman; `sueno_medio_min`, eficiencia y etapas | `HK:513-668`, test `test-bridge` | ☐ | ☐ |
| SAL-04 | HRV: mediana por fecha, priorizando lo medido durante el sueño, después antes de las 10:00; `detalle{metrica sdnn/rmssd, ventana, n}` | `HK:676-707` | ☐ | ☐ |
| SAL-05 | Entrenos con FC media y máxima calculadas con las muestras del entrenamiento | `HK:829-891` | ☐ | ☐ |
| SAL-06 | Permisos en dos tandas (núcleo y resto) con reintentos; nunca escritura; "denegado" solo por datos (3 sincronizaciones vacías) | `HK:241-451` | ☐ | ☐ |
| SAL-07 | Sincronización de 7 días al abrir, al volver y con el botón; historial de 60 días (30 en Android sin permiso de historial) en ventanas de 5, con cursor y reintento cada 6 h | `HK:927-1065` | ☐ | ☐ |
| SAL-08 | Android: basales con mediana, sueño con `stages[]`, sin los 6 tipos solo de iOS; textos sin "Apple" | test `test-bridge-android` | ➖ | ☐ |
| SAL-09 | Card Recuperación: sin conectar (botón); conectado sin score (4 casos: trayendo historial, faltan datos de la noche, solo pasos, no llega nada); calibrando n/14; oculto por el cliente; con score: número, banda, frase, gráfico de 14 días, hasta 3 motivos y "Ver todos mis datos" | `C:6564-6788` | ☐ | ☐ |
| SAL-10 | Card Salud: pasos, minutos activos, sueño, HRV y promedio de pasos | `C:7233-7328` | ☐ | ☐ |
| SAL-11 | Mis datos: cómo se arma el score (componentes y pesos), sueño, corazón, actividad, otras señales y cuerpo, cada uno con 7 y 30 días y gráfico chico; toggle "Mostrarme el score" | `C:6886-7059` | ☐ | ☐ |
| SAL-12 | Prioridad de fuentes: whoop/oura/withings/polar > apple_health = health_connect > rook > manual | `C:6440-6457` | ☐ | ☐ |
| SAL-13 | Diagnóstico de salud (hoy 5 toques o `?diag=health`) | `C:8605-8665` | ☐ | ☐ |

## NOT · Notificaciones

| ID | Comportamiento | Fuente | iOS | And |
|---|---|---|---|---|
| NOT-01 | Registro de push desde el primer arranque con permiso: iOS = APNs hex MAYÚSCULAS `'ios'`; Android = FCM `'android'`; con `app_version` | `NT:278-323`, `push.py` | ☐ | ☐ |
| NOT-02 | Un solo transporte por teléfono | test `test-un-solo-transporte` | ☐ | ☐ |
| NOT-03 | Tocar el aviso abre el `destino` (train, diet, progress, myday, revision, salud, chat); uno desconocido cae a Chat | `NT:326-336`, `057:342` | ☐ | ☐ |
| NOT-04 | Con la app abierta se muestra banner y sonido (`willPresent` / canal propio en Android) | `capacitor.config.json` | ☐ | ☐ |
| NOT-05 | Local "Tu revisión de la semana": id 1002, domingos a las 11:00, semanal, abre Revisión; se cancelan 1001/1003/1004; apagado = nada agendado | `NT:46-147`, test `test-notificaciones` | ☐ | ☐ |
| NOT-06 | Recordatorios configurables en Mis datos (`mypump_notif_prefs`) | `C:7172-7231` | ☐ | ☐ |
| NOT-07 | Android: canal propio como `default_notification_channel_id`, ícono `ic_stat_mypump`, `POST_NOTIFICATIONS` | memoria `project_push_android_web` | ➖ | ☐ |
| NOT-08 | Al actualizar, las locales que dejó la Capacitor no se duplican (iOS: ids "1001"-"1004"; Android: PendingIntents de `TimedNotificationPublisher`) | plan | ☐ | ☐ |

## OFF · Sin conexión y cola

| ID | Comportamiento | Fuente | iOS | And |
|---|---|---|---|---|
| OFF-01 | Las 9 ops del outbox con su `dedupeKey` (que en la nativa incluye la semana) y FIFO | `C:2687-2968` | ☐ | ☐ |
| OFF-02 | Red y transitorio no gastan intentos; 8 rechazos = abandono, que va a fallidos y no se borra | `SC:41-48`, test `test-outbox` | ☐ | ☐ |
| OFF-03 | `seGuardo`: `null`, `0` y `[]` = no guardado | `C:2851-2858` | ☐ | ☐ |
| OFF-04 | Un bug propio no congela la cola (las de atrás siguen) | memoria `project_auditoria_mypump_19sep` | ☐ | ☐ |
| OFF-05 | Token revocado: las ops se estacionan sin gastar intentos | plan | ☐ | ☐ |
| OFF-06 | Banner sin conexión y toast "se reintenta solo" | `C:8933-8949` | ☐ | ☐ |

## MIG · Migración del almacenamiento viejo

| ID | Comportamiento | Fuente | iOS | And |
|---|---|---|---|---|
| MIG-01 | Se lee el `localStorage` viejo completo (Ruta A, verificado con la B) y se guarda una copia cruda | `NATIVA_SPIKE_ALMACENAMIENTO.md` | ✅ spike 17.5, 18.6 y 26.5 | ☐ |
| MIG-02 | Fase L sin red, antes de la UI: token, preferencias, importar ops sin ejecutar, caché offline | plan | ☐ | ☐ |
| MIG-03 | Fase R con red: ejecutar ops (validando rutina y día), subir fotos, sustituciones, swaps sin migrar, recibo con conteos | plan | ☐ | ☐ |
| MIG-04 | `anon` y `*_demo` nunca se ejecutan ni se suben | plan | ☐ | ☐ |
| MIG-05 | Escritura de vuelta: saca las ops ejecutadas y los cachés de sesión; se confirma en el arranque siguiente | spike | ✅ spike 17.5, 18.6 y 26.5 | ☐ |
| MIG-06 | Se repite si la Capacitor volvió a escribir (downgrade, TestFlight vencido, plan B) sin duplicar | plan | ☐ | ☐ |
| MIG-07 | Cero pérdida: conteos antes y después que cierran con el recibo | plan | ☐ | ☐ |

## APL · Tiendas

| ID | Comportamiento | Fuente | iOS | And |
|---|---|---|---|---|
| APL-01 | Respaldo científico pegado a cada número + modal con 14 fuentes ("Abrir fuente" en navegador interno), disclaimer último | `C:4711-4837` | ☐ | ☐ |
| APL-02 | Política de privacidad accesible dentro de la app | 5.1.1(i) | ☐ | ☐ |
| APL-03 | Demo accesible desde la primera pantalla ("Ver demo") | rechazo 2.1 del 24-jul | ☐ | ☐ |
| APL-04 | Textos de permisos idénticos a los aprobados (cámara, fotos, Salud) | `ios/App/App/Info.plist` | ✅ (cámara ampliada a plato y etiqueta) | ➖ |
| APL-05 | `PrivacyInfo.xcprivacy` coherente con la etiqueta publicada | plan | ☐ | ➖ |
| APL-06 | iPhone + iPad (`TARGETED_DEVICE_FAMILY 1,2`), iPad digno en ancho compacto | pbxproj | ☐ | ➖ |
| APL-07 | Health Connect: mismos 13 permisos de lectura + historial; chequeo del manifest mergeado; pantalla de justificación y URL de privacidad | `android/app/src/main/AndroidManifest.xml` | ➖ | ☐ |
| APL-08 | Launcher `.MainActivity` (o alias) y `allowBackup` sin el token | plan | ➖ | ☐ |
