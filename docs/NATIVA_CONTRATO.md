# Contrato de las apps nativas con el backend

> Lo único que las apps nativas pueden usar. Se verificó contra el código de `public/` (`main` `684b3e2`) y contra la
> base (`pg_proc`, 14-oct-2026). La versión que lee una máquina es `apps/shared/contrato.json`, con firmas, tipos y
> qué usa el cliente.
>
> Si una RPC cambia de firma en la base, el check de contrato tiene que fallar antes de que llegue a un teléfono.
>
> Abreviaturas: `C` = `public/cliente.html` · `SC` = `public/js/supabase-client.js` · `NT` = `notificaciones.js` ·
> `HK` = `healthkit-bridge.js` · `MV` = `mini-vision/server.mjs`.

## 0. Diferencias con el prompt de la sesión

1. **La cola de escrituras es `mypump_outbox_<TOKEN|anon>`** (`C:2688`), no `mypump_offline_<TOKEN>`.
   - `mypump_offline_<TOKEN>` es una copia `{info, rutina, dieta, ts}` para arrancar sin red (`C:8924-8931`).
   - La cola de fotos es `mypump_fotoq_<TOKEN>` (`C:7487`).
2. **El cliente llama 50 RPC, no 53.**
   - `get_entrenos_health` y `get_gasto_real` tienen wrapper (`SC:422-430`) pero ninguna pantalla los usa.
   - `encolar_push` solo la puede ejecutar `service_role` y la disparan los triggers (058, 076).
3. **Ninguna RPC del cliente registra las fotos de progreso.** Las sube y registra mini-vision con la service key; el
   cliente solo relee con `get_fotos_progreso`.

## 1. Transporte

- **Llamada:** `POST https://gydinputrtptqakdzyvc.supabase.co/rest/v1/rpc/<fn>`, con body JSON de claves `p_*`.
  - Headers: `apikey: <anon>`, `Authorization: Bearer <anon>` y `Content-Type: application/json`.
  - La anon key es pública y sale de `public/js/config.js`.
  - Las nativas aceptan también claves `sb_publishable_…`.
- **Cliente propio y fino**, sin supabase-swift ni supabase-kt (decisión del 13-oct):
  - devuelve `(status HTTP, cuerpo)`;
  - `null` es una respuesta válida;
  - clasifica como `clasificarError` (`SC:41-48`).

  | Caso | Clase | ¿Gasta intento? |
  |---|---|---|
  | Sin respuesta (`URLError`: sin red, timeout, host) | red | no |
  | 5xx, 429, 408 | transitorio | no |
  | Cualquier otro (400 PGRST/P0001, 404 PGRST202, 401/403) | permanente | sí |
- **Un token revocado NO da error.**
  - Casi todas las RPC devuelven **200** con `NULL`, `[]`, `0` o `false`.
  - Solo `registrar_push` y `registrar_push_web` hacen `RAISE 'token invalido'`.
  - Un token es válido si `access_token` coincide y `access_token_active = TRUE` (`001:304-317`).
- **`get_cliente_info` actualiza `last_accessed_at`** (lo confirmé en la definición vigente). Nunca se llama en segundo
  plano: el coach vería aperturas que no existieron.
- **Firmas.** Ninguna función `mypump_*` tiene dos firmas, así que no hay riesgo de PGRST203 (consulta del 14-oct).
  Todas las del cliente son `SECURITY DEFINER` y las ejecuta `anon`.
- **Valores comunes:**
  - `p_token`: el token guardado.
  - `p_fecha`: la fecha **local** del teléfono en `YYYY-MM-DD`, calculada en el momento de la acción (gregoriano,
    `en_US_POSIX`). El servidor acepta de −7 a +1 días respecto de hoy en Argentina.
  - `p_semana`: `semana_actual` de `get_rutina_activa`. `semana_offset` solo cambia rótulos.
  - Los ids (`p_dia_id`, `p_ejercicio_id`, `p_comida_id`) son los de la estructura publicada. `p_ejercicio_id` es el id
    del **lugar** en la rutina (`slug-d<n>-<i>`), aunque haya una sustitución.

## 2. RPC de lectura (27 que se usan)

| RPC | Parámetros | Cuándo | Qué usa de la respuesta |
|---|---|---|---|
| `get_cliente_info` | token | arranque | `{cliente_id, nombre, perfil}`. Si viene `[]` sin error = token inválido |
| `get_rutina_activa` | token | arranque | `{id, version, estructura, semana_actual, fecha_inicio, fecha_fin, tiene_siguiente}` |
| `get_dieta_activa` | token | arranque | `{id, version, estructura}` |
| `get_cliente_prefs` | token | al hidratar la dieta | `{excluir text[], idioma}`, con default `[]` y `'es'` |
| `get_custom_foods` | token | al hidratar | `[{name, kcal, prot, carb, fat, unit, unit_grams, category}]` (por 100 g) |
| `get_food_swaps` | token, dieta_id | al hidratar | `[{comida_id, opt_idx, food_idx, food_data}]`. Si viene `null` fue la red: no se migra |
| `get_comentarios` | token, ambito, referencia_id (ambos null) | arranque y después de comentar | `[{id, ambito, referencia_id, referencia_nombre, autor, contenido, leido_por_cliente, leido_por_coach, created_at}]` |
| `get_chat` | token, antes (created_at o null), limite=30 | arranque, abrir el chat, "anteriores" | `[{id, autor, contenido, leido_por_cliente, created_at}]`. Si vienen menos de 30, no hay más |
| `chat_nuevos` | token, desde (cursor) | poll cada 15 s en el chat, cada 45 s afuera, nunca en segundo plano | `[{id, autor, contenido, created_at}]`, del más viejo al más nuevo. Sin campo de leído |
| `get_ejercicios_estado` | token, sesion_id | al restaurar la sesión del día | `[{ejercicio_id, status, series_completadas, marcado_manualmente}]` |
| `get_registros_sesion` | token, sesion_id | ídem | `[{ejercicio_id, serie_numero, peso_kg, reps_realizadas, rir_real, ejercicio_nombre, notas}]` |
| `get_sesion_dia` | token, dia_id, semana | restaurar y `resolveSesion` | `{id, dia_id, semana, iniciada_en, finalizada_en}` |
| `get_sesiones_semana` | token, semana | arranque | `[{dia_id, iniciada_en, finalizada_en}]` → ✓ en el selector |
| `get_historico_por_clave` | token, claves[], limit_por_ej=48 | abrir la card, precargar el día, Progreso | `[{clave, registrado_en, peso_kg, reps_realizadas, rir_real, serie_numero, notas, ejercicio_nombre}]` |
| `get_historico_ejercicio` | token, ejercicio_id, limit | solo si la anterior da PGRST202 | camino viejo (por lugar en la rutina) |
| `get_historico_ejercicios` | token, ejercicio_ids[], limit_por_ej | ídem, en Progreso | camino viejo |
| `get_habitos_dia` | token, fecha | arranque; al volver si cambió el día | `{entrenamiento, comio_segun_plan, durmio_bien, cardio, vasos_agua}` |
| `get_streak` | token | Mi Día; después de cada hábito | `{streak, ultimo_dia_valido}` |
| `get_adherencia_30d` | token | al abrir "mis últimos 30 días" | 30 filas `{fecha, entrenamiento, comio_segun_plan, durmio_bien, vasos_agua, es_valido}` |
| `get_comidas_marcadas` | token, fecha | arranque; al volver si cambió el día | `[{comida_id, opcion_elegida, estado, marcada_en, foods_excluidos}]` |
| `get_comidas_libres` | token, fecha | ídem | `[{id, fecha, hora, descripcion, kcal, prot, carb, fat, detalle}]` |
| `get_salud` | token, desde=hoy−59, hasta=hoy | arranque, después de sincronizar salud, al conectar un reloj | `[{fecha, tipo, valor, fuente, detalle}]` |
| `get_recuperacion` | token, dias=14 | ídem | `[{fecha, score, estado, banda, dias_datos, banda_provisoria, estado_autonomico, hrv_metrica, discordancia, cobertura, motivos[]}]` (la última fila es la más nueva) |
| `get_mostrar_recuperacion` | token | ídem | boolean (`null` cuenta como `true`) |
| `get_conexiones` | token | arranque; poll cada 3 s (40 veces) después de "Conectar" | `[{proveedor, estado, ultimo_pull_en}]` |
| `get_checkin_semana` | token, fecha | Revisión | `{energia, descanso, hambre, adherencia, nota}` |
| `get_fotos_progreso` | token, desde=null | Revisión; después de subir | `[{semana_lunes, pose, tomada_el, created_at}]` |

**Historial:**
- `get_historico_por_clave` devuelve `false` si la RPC no existe (PGRST202): es la **única** caída legítima al camino
  viejo.
- Si devuelve `null` fue la red: el ejercicio queda sin cargar para reintentar. **Nunca** se cae al camino viejo por
  un corte de señal.
- La clave es `claveEjercicio(nombre efectivo)`, que tiene un gemelo en SQL: `mypump_clave_ejercicio`.

**Lectura directa de tabla** (sin token, catálogo público):
- `GET /rest/v1/mypump_ejercicios_catalogo?select=slug_en,name_en,name_normalized,aliases_es,primary_muscle,equipment,patron_movimiento,image_eccentric,image_concentric`.
- Se cachea (en la web, `mypump_ejercicio_catalogo_v1`).

## 3. RPC de escritura (23 que se usan)

| RPC | Parámetros | Vía | Cuándo cuenta como éxito |
|---|---|---|---|
| `iniciar_sesion` | token, dia_id, semana | directa (o desde `resolveSesion`) | UUID. Es idempotente desde la 075 |
| `registrar_carga` | token, sesion_id, dia_id, ejercicio_id (del **lugar**), ejercicio_nombre (**el efectivo**: el del sustituto si hay), serie (1..n), peso (`parseFloat`, con coma → punto), reps, rir (**0 vale**; `''` → null), notas (variante o null) | outbox `carga` | UUID; NULL = token inválido |
| `marcar_ejercicio_estado` | token, sesion_id, dia_id, ejercicio_id, series_objetivo, status (`pendiente`, `completo`, `completo_sin_datos`, `saltado`), marcado_manualmente | outbox `estado` | UUID |
| `finalizar_sesion` | token, sesion_id, notas, duracion_segundos (null si pasa de 6 h) | directa, **después de vaciar el outbox** | boolean; con `false` se avisa |
| `avanzar_semana` | token, semana_destino = actual+1 | directa | entero o null. Nunca retrocede (077). Después se borran los cachés de sesión |
| `activar_siguiente` | token | directa | boolean (última semana con `tiene_siguiente`) |
| `set_habito` | token, fecha, campo (`entrenamiento`, `comio_segun_plan`, `durmio_bien`, `cardio`, `vasos_agua`), valor **siempre string** | outbox `habito` (el agua con 600 ms de debounce) | fila de hábitos; después se relee el streak |
| `crear_comida_libre` | token, fecha, hora 'HH:MM' o null, descripcion, kcal, prot, carb, fat, detalle `{alimentos[], confianza, escala}` o null | directa | `data[0]` |
| `borrar_comida_libre` | token, id | directa, optimista con rollback | boolean |
| `marcar_comida` | token, fecha, comida_id, opcion (nombre de la opción), estado (`comido` o `saltado`), foods_excluidos (jsonb, índices de la opción o null) | outbox `comida` | fila. Con PGRST202 se reintenta sin `p_foods_excluidos` |
| `desmarcar_comida` | token, fecha, comida_id | outbox `comida` (estado null) | boolean; `false` también cuenta |
| `save_food_swap` | token, dieta_id, comida_id, opt_idx, food_idx, food_data `{name, qty, unit, kcal, prot, carb, fat, category, …, _orig{name, qty, unit}}` (**macros totales para esa qty**) | outbox `swap` | fila |
| `delete_food_swap` | token, dieta_id, comida_id, opt_idx, food_idx | outbox `swap_del` | boolean; `false` también cuenta |
| `create_custom_food` | token, name, kcal, prot, carb, fat (**por 100 g**), unit, unit_grams, category | directa | `data[0]` |
| `guardar_checkin` | token, fecha (el servidor la ancla al lunes ISO), energia, descanso, hambre, adherencia (1-5), nota | outbox `checkin` | fila |
| `ingest_salud` | token, registros `[{fecha, tipo, valor, fuente, detalle?}]` | outbox `peso` (manual) o directa desde salud (lotes de 300) | entero; **0 = no guardado**. Upsert por (cliente, fecha, tipo, fuente) |
| `ingest_entrenos` | token, entrenos `[{inicio, fin, tipo, duracion_min, kcal, distancia_km, fc_media, fc_max, fuente}]` | directa (lotes de 200; más de 500 da error) | entero. Upsert por (cliente, inicio, tipo) |
| `agregar_comentario` | token, ambito (`ejercicio` o `general`), referencia_id, referencia_nombre, contenido | ejercicio: directa con aviso. Chat: outbox `chat` | UUID. El servidor descarta el mismo texto dentro de 2 min (075) |
| `marcar_leidos_cliente` | token, ambito, referencia_id | directa (al abrir la card o el chat) | entero |
| `desconectar_wearable` | token, proveedor | directa | boolean |
| `set_mostrar_recuperacion` | token, mostrar | directa, optimista | boolean |
| `registrar_push` | token, device, plataforma, app_version | directa | boolean. `false` si device < 32 caracteres. Upsert por `token` UNIQUE (texto exacto) |
| `registrar_push_web` | token, endpoint (https), p256dh, auth | solo web | — |

## 4. La cola de escrituras (outbox)

**Formato.**
- Clave: `mypump_outbox_${TOKEN || 'anon'}`. El valor es un array JSON.
- Entrada (`C:2829`): `{_id: "<ms>_<seq>", kind, payload, dedupeKey, tries, ts}`.
  - En versiones viejas puede faltar `_id` (v1.0.2).
  - El backoff vive en memoria, no en la entrada.
- Al encolar, se borra cualquier entrada con el mismo `dedupeKey` y la nueva va al final.

| kind | payload | dedupeKey | Ejecuta |
|---|---|---|---|
| `carga` | `{sesionId?, diaId, semana, datos{diaId, ejercicioId, ejercicioNombre, serie, peso, reps, rir, notas}}` | `carga_<dia>_<exId>_<setIdx>` | `resolveSesion` → `registrar_carga` |
| `estado` | `{sesionId?, semana, diaId, exId, seriesObjetivo, status, manual}` | `estado_<dia>_<exId>` | `resolveSesion` → `marcar_ejercicio_estado` |
| `swap` | `{dietaId, comidaId, optIdx, foodIdx, food}` | `swap_<dieta>_<comida>_<opt>_<food>` | `save_food_swap` |
| `swap_del` | `{dietaId, comidaId, optIdx, foodIdx}` | la misma que `swap` | `delete_food_swap` |
| `habito` | `{fecha, campo, valor}` | `habito\|<fecha>\|<campo>` | `set_habito` + `get_streak` |
| `comida` | `{fecha, comidaId, opcion, estado, excl[]}` | `comida\|<fecha>\|<comidaId>` | `desmarcar_comida` si `estado` es null; si no, `marcar_comida` |
| `peso` | `{fecha, valor}` | `peso_<fecha>` | `ingest_salud` `[{fecha, tipo:'peso_kg', valor, fuente:'manual'}]` |
| `checkin` | `{fecha, datos{energia, descanso, hambre, adherencia, nota}}` | `checkin_<fecha>` | `guardar_checkin` |
| `chat` | `{contenido}` | `chat_<ms>_<40 chars>` | `agregar_comentario('general', null, null, contenido)`, y 250 ms después el poll |

**`resolveSesion`** (`C:2698-2720`):
1. Usa `payload.sesionId` si existe.
2. Si es el día y la semana abiertos en pantalla, usa la sesión abierta o la crea.
3. Si no, la busca en un caché `dia|semana`, después con `get_sesion_dia` y, si no existe, la crea con
   `iniciar_sesion`.
4. Si la consulta falló por red, devuelve null y se reintenta más tarde.

**`seGuardo`** (`C:2851-2858`): falla si no hay `success`, o si `data` es `null`, `undefined`, `0` o `[]`.

**Reintentos:**
- Una falla de red o transitoria corta la pasada sin gastar intento.
- Cualquier otro fallo suma un intento y la pasada sigue. Con 8 se abandona.
- Backoff: `min(30 s, 2 s × max(1, tries de la primera, racha sin red))`.
- Se drena:
  - al encolar;
  - 1,5 s después del arranque;
  - al volver a primer plano;
  - con el evento `online`;
  - antes de `finalizar_sesion`;
  - en la migración de swaps.

**Al abandonar una op en la web:**
- Se borra de la cola.
- Si era del chat, la burbuja queda en "no salió" con Reintentar.
- Aparece el toast "⚠ Algo no se pudo guardar…", que dura 9 s.

**Lo pendiente gana sobre lo que trae el servidor:**
- `pendingByKey` lo usan al hidratar los swaps, las comidas marcadas y Mi Día.
- La nativa lo respeta igual: lo que está en la cola se pinta por encima de la respuesta.

**Lo que la nativa hace distinto, a propósito:**
1. El `dedupeKey` de `carga` y `estado` incluye la semana. Hoy dos semanas pendientes del mismo día se pisan.
2. Un `kind` desconocido o una op abandonada van a una tabla de **fallidos**, no se borran.
3. Ante el primer "no guardado" de una pasada se pregunta `get_cliente_info`. Si el token cayó, las ops se estacionan
   sin gastar intentos.
4. El chat se marca "en vuelo" y, después de un corte, se mira `get_chat` antes de reenviar.

**Kinds que solo genera la nativa** (ver §11). La web no los conoce, y una versión vieja de la nativa los manda a
fallidos (no los borra):

| kind | payload | dedupeKey | Ejecuta |
|---|---|---|---|
| `consentimiento_ia` | `{acepta, plataforma, app}` | `consentimiento_ia` | `guardar_consentimiento_ia`. **Ya no se encola** (D7 se sacó el 14-oct): queda para vaciar lo que haya quedado en una cola de la 101/102 |
| `swap_ej` | `{rutinaId, exId, swap}` (`swap` es la entrada de la web tal cual, con `_ts`: la hora del cambio en ms) | `swap_ej_<rutina>_<exId>` | `save_exercise_swap` |
| `swap_ej_del` | `{rutinaId, exId, ts}` (`ts` = la hora de lo que se borró: lo que el cliente veía) | la misma que `swap_ej` | `delete_exercise_swap` (deja la lápida con `ts`) |

- Con PGRST202 (la migración 003 todavía no está en la base), `swap_ej` y `swap_ej_del` se dan por hechas: la
  sustitución queda solo en el teléfono, como antes, y sube con la primera lectura que encuentre la tabla.
- Son **silenciosas**: no muestran "guardando", "sin conexión" ni "no se guardó" (`Outbox.silenciosas`). La
  sustitución ya quedó en el teléfono; antes no tocaba la red.

## 5. Fotos de progreso y visión (`vision.mypumpteam.com`, mini-vision)

**Cómo autentica:**
- El campo `token` va en el body JSON; no hay header de auth.
- El servidor lo valida con `get_cliente_info`. Inválido → 403; Supabase caído → 503.
- El CORS solo le importa al navegador: las nativas no mandan `Origin`.

| Ruta | Request | Respuesta y errores |
|---|---|---|
| `POST /progreso/upload` | `{token, pose: frente\|perfil\|espalda, fecha?: YYYY-MM-DD (de −7 a +1), imagen_base64}`. Tiene que ser JPEG real, de hasta 3 MB | `{ok, semana_lunes, pose}`. Upsert en `mypump_fotos_progreso` por (cliente, lunes, pose); bucket privado `progreso`. Errores 400/403/429 (12 por día)/502/503 |
| `POST /progreso/urls` | `{token, desde?}` | `{ok, fotos:[{semana_lunes, pose, url}], expira_en:3600}` |
| `POST /vision` | `{token, tipo: etiqueta\|plato, imagen_base64}`, hasta 4 MB | `{ok, data}`. Etiqueta: `{nombre, porcion_g, kcal, prot, carb, fat, confianza}`. Plato: `{descripcion, escala, alimentos[{nombre, gramos, kcal, prot, carb, fat}], kcal…, confianza}`. 20 por día. Hasta 150 s |

**Cliente de hoy:**
- Fotos: JPEG de 900 px a calidad 0,7, sin EXIF.
- Visión: calidad 0,85, 1600 px para etiqueta y 1280 px para plato.

**Cola de fotos** `mypump_fotoq_<TOKEN>`:
- Mapa `"<lunesISO>|<pose>" → {pose, fecha, dataUrl, intentos}`.
- Máximo 3; rechaza más de 2,4 M caracteres.
- 8 intentos, y solo cuentan los errores del servidor.
- Un 4xx que no sea 429 es definitivo.

## 6. Wearables (Cloudflare Pages Functions)

- `GET https://app.mypumpteam.com/api/wearables/disponibles`: sin auth. Devuelve `{proveedores:[{id, nombre}]}`.
- `GET …/api/wearables/iniciar?t=<TOKEN>&proveedor=oura|whoop`: redirige 302 al OAuth del proveedor.
  - Se abre en **SFSafariViewController**, porque el token viaja en la query.
  - La app consulta `get_conexiones` cada 3 s durante 2 min y después cierra.
- `/api/wearables/callback` lo llama el proveedor. `/api/salud` es un webhook de un agregador: **no lo usa ninguna
  app**.

## 7. Push

**Registro:**
- iOS: `registrar_push(token, device = token APNs en hex MAYÚSCULAS, 'ios', 'x.y.z (build)')`.
  - Es el formato de Capacitor; con otro formato el mismo iPhone queda en dos filas.
  - Los builds de debug **no registran**: su token es de sandbox y `push.py` (`APNS_ENV=prod`) lo daría de baja.
- Android: el token FCM, con `'android'`.
- Se re-registra al arrancar si cambió el token.

**Envío** (`pump-centinela/push.py`, cada 5 min):
- `push_pendientes` devuelve **una fila por dispositivo activo**: el envío a todos los dispositivos es a propósito
  (verificado el 14-oct; no hay `DISTINCT ON`). Por eso el riesgo es que el mismo teléfono quede registrado dos veces.
- APNs: `{aps:{alert:{title, body}, sound:'default'}, destino}`, `apns-push-type: alert`, prioridad 10, sin badge.
- FCM: `notification{title, body}` + `data{destino}`, `priority: high`, sin `channel_id`.
- Un token muerto (410, `BadDeviceToken`, `UNREGISTERED`) se da de baja.

**Destinos:**

| destino | Quién lo genera | Pantalla |
|---|---|---|
| `chat` | comentario general del coach (076) | Chat |
| `train` | comentario sobre un ejercicio (076) | Entreno |
| `revision` | la notificación local del domingo | Revisión |
| `diet`, `progress`, `myday`, `salud` | válidos (057) | Dieta, Progreso, Mi Día, Mis datos |
| `comentarios` | histórico (048, `scripts/push-test.json`) | **no existe**: la nativa cae a Chat |

**Notificación local** (`NT:46-58`):
- Una sola: id **`1002`**, domingos a las 11:00, semanal: "Tu revisión de la semana" → Revisión.
- Las viejas 1001, 1003 y 1004 se cancelan.
- Preferencias en `mypump_notif_prefs` `{check:{on, hora, min}}`.

## 8. Acceso y links

**AASA** (`public/.well-known/apple-app-site-association`, ya publicado):
- `7H22AXLUS4.com.pumpteam.mypump` con `/?t=*`, `/cliente?t=*` y `/cliente.html?t=*`.
- Entitlement `applinks:app.mypumpteam.com`.
- Android: App Links sin filtro de path y `assetlinks.json` con la huella de Play.

**Token:**
- Regex `^[a-zA-Z0-9_-]{16,64}$`.
- Orden: `?t=`, después el path, después el guardado. Si `?t=` es igual a `mypump_token_invalido` y hay otro guardado
  válido, gana el guardado.
- Si llega `[]` sin error: "Este link ya no sirve", se borra el token y se guarda como inválido.

**Parámetros extra:** `?scene=<destino>` y `?diag=health`.

**Demo** (`?demo=1`):
- Datos de ejemplo empaquetados, sin token y **sin red** (App Review entra por acá).
- En la nativa no escribe nunca: la web, con un token guardado, podía escribir hábitos reales.

## 9. Lo que vive solo en el teléfono (inventario completo, `main` y tags v1.0.2 → v1.0.12-b18)

| Clave | Qué hace la nativa en la migración |
|---|---|
| `mypump_token` | → Keychain. Se respeta `mypump_token_invalido` |
| `mypump_outbox_<T>` (también `anon` y los de tokens viejos) | Se importa **sin ejecutar** (Fase L) y se ejecuta con red (Fase R). `anon` nunca se ejecuta. Un token viejo se reasigna solo si el vigente resuelve al mismo `cliente_id` |
| `mypump_fotoq_<T>` | → archivos → se suben. Las que estén fuera de ventana quedan guardadas y van al recibo |
| `mypump_exercise_swaps_<RUTINA>` | → tabla nueva del servidor (G2) más copia local, respetando la poda. Las `*_demo` no se suben |
| `mypump_food_swaps_<DIETA>` y `mypump_swaps_migrados_<DIETA>` | Si no se migraron, mismo anclaje y subida que la web |
| `mypump_offline_<T>` | Siembra la caché del primer arranque sin red |
| `mypump_tipo_dia` (global), `mypump_dia_visualizado_<RUTINA>`, `mypump-theme` (solo `'dark'` cuenta como elección), `mypump_notif_prefs`, `mypump_notif_pedido`, `mypump_onboarding_v1` | → ajustes nativos |
| `mypump_rest_<T>`, `mypump_sesion_<T>_<dia>{,_semana,_start,_finalizada}` | Descanso y `_start` si siguen vigentes. Lo demás manda el servidor |
| `mypump_health_*` (connected, last_sync, denegado, racha_vacia, backfill_v1/off/intento, historial_ok, diag) | → estado del sincronizador. La ingesta es idempotente, así que los cursores se pueden recalcular |
| `mypump_push_token`, `mypump_push_web_endpoint` | Se registran; la nativa vuelve a registrar igual |
| `mypump_ejercicio_catalogo_v1`, `mypump_a2hs_v1`, `mypump_dl_pospuesto`, `mypump_reload_online` (sessionStorage) | Se ignoran |

No hay IndexedDB. La Cache API la usa solo el service worker.

Las 21 claves y sus valores se leyeron byte a byte desde la nativa: ver `docs/NATIVA_SPIKE_ALMACENAMIENTO.md`.

## 10. Lógica del cliente: va al servidor (S) o se porta con vectores (P)

| Regla | Dónde vive hoy | Destino |
|---|---|---|
| Recuperación 0-100, racha, adherencia, historial por clave, métricas del coach | SQL (043, 008, 072…) | ya en el servidor |
| `claveEjercicio` | `C:2092` (gemela de `mypump_clave_ejercicio`) | P, con los 1.246 nombres reales |
| `normalizarRutina` / `normalizarDieta` (descanso ≤0 → 90, series ≤0 → 1, `semanas_total` → 12, macros de la opción A) | `C:1797-1878` | P |
| Progresión de la semana y su nota ("calibración" solo en semana 1 sin offset) | `C:1679-1747` | P |
| Sugerido de reps y kg, kg heredado, topes y preguntas (300 reps, >600 kg, 2,5× el récord, >max(30, 3×ref)) | `C:1577-1627`, `4066-4230` | P |
| Variantes de agarre por regex | `C:3983-4003` | P |
| Sustitutos de ejercicio (`findSubstitutes`: patrón + músculo, otro equipo primero, máx. 30) y `_toEs` | `public/js/app.js:692-737` | P, con el catálogo entero |
| Sustitutos de comida (categoría, macro dominante, porción, desvío ≤35 %, exclusiones, top 30 + universales + propios) | `app.js:19-394` | P, con FOOD_DB |
| Anclaje de swaps de comida (`_swapAplicable`, `_anclarOSacarSwap`) | `C:1981-2024`, `5878-6034` | P. Ojo: puede **borrar** en el servidor (`test-swaps-anclados.mjs`) |
| Poda de sustituciones de ejercicio | `C:2137-2161` | P |
| Bridge de salud (agregación, sueño, HRV, entrenos) | `HK` + el Swift del plugin (`Health.swift:1505-1556`) | P, con un golden test contra la Capacitor |
| Cola de escrituras | `C:2641-2968` | P, con los cuatro arreglos de §4 |

Hoy ninguna regla pide una RPC nueva de lógica. Los cambios de base de la nativa son de **datos**:
- sustituciones de ejercicio;
- recibo de migración;
- conteos;
- palanca remota.

Están en el plan y pasan por G2.

## 11. Lo que agregan las migraciones de la nativa (`supabase/migrations/nativa_*`)

Solo agregan: ninguna cambia una tabla o una función existente, y la web no usa nada de esto. Cada una se ensaya en
producción dentro de una transacción con `scripts/nativa/ensayar-migracion.py` y se aplica solo con el OK de Mati.
Mientras una función no exista (PGRST202), la app sigue como antes.

| Migración | Función | Devuelve | Quién la usa |
|---|---|---|---|
| 001 | `registrar_migracion_nativa(token, migracion uuid, corrida, recibo jsonb)` | TRUE; FALSE si el uuid es de otro cliente; NULL = token caído | el recibo de la migración del almacenamiento viejo |
| 001 | `conteos_cliente(token)` | filas por tabla del cliente (15); NULL = token caído | el recibo (antes y después) |
| 001 | `get_app_config()` | la palanca remota (5 valores) | al abrir |
| 002 | `get_consentimiento_ia(token)` | `{acepta}` (null = nunca se le preguntó); NULL = token caído | **nadie desde el 14-oct** (D7 se sacó; la tabla queda, la base solo crece) |
| 002 | `guardar_consentimiento_ia(token, acepta, plataforma, app)` | TRUE; NULL = token caído | solo una op vieja de la cola |
| 002 | `clientes_sin_ia(clientes text[])` | los que dijeron que no | **solo `service_role`**; nadie desde el 14-oct (los scripts de la Mini volvieron a la versión sin filtro) |
| 003 | `get_exercise_swaps(token, rutina_id)` | `{"vivas": {exId: entrada}, "borradas": {exId: ms}, "ahora": ms del servidor}`; NULL = token caído o rutina ajena | al cargar Entreno |
| 003 | `save_exercise_swap(token, rutina_id, ex_id, swap jsonb)` | TRUE (también si allá había algo más nuevo); FALSE = rutina ajena (cuenta como hecho); NULL = token caído | outbox `swap_ej` |
| 003 | `delete_exercise_swap(token, rutina_id, ex_id, ts)` | TRUE (deja la lápida, salvo que allá haya algo más nuevo); FALSE = rutina ajena; NULL = token caído | outbox `swap_ej_del` |

**Sustituciones de ejercicio (003, SER-14).**
- Cada fila es una entrada del mapa de la web (`exId → {original, current, fijado, semana, diaId}`) más `_ts`, la hora
  en que el cliente la eligió (ms del teléfono). Lo de la app vieja no la tiene: cuenta como 0, lo más viejo.
- **Gana lo más nuevo**, en el servidor y al leerlo en el teléfono. Borrar deja una **lápida** con la hora de lo que se
  borró (lo que el cliente veía): algo más viejo no la revive y ella no saca algo más nuevo que el cliente no vio.
- Un cambio se estampa con la hora del teléfono **corregida con la del servidor** (el `ahora` de la última lectura,
  guardado entre arranques), nunca menos que la de lo que reemplaza + 1 ni que la más alta que tuvo esa clave en la
  sesión (lo deshecho, las lápidas leídas). El servidor recorta cualquier hora a la suya + 5 minutos (también dentro de
  la entrada), y una copia del teléfono con hora más allá de eso no le gana a lo que diga el servidor. La misma elección
  con otra hora se adopta del servidor sin volver a subirla.
- ⚠️ **Una vez aplicada, estas firmas no se cambian nunca.** La app trata PGRST202 ("la función no existe") como
  "todavía no hay tabla" y da la op por hecha: con una firma cambiada, cada sustitución se perdería en silencio. Si hace
  falta otra firma, se crea una función con otro nombre y la vieja queda.
- Que algo falte en el servidor **no es un borrado**: el teléfono lo vuelve a subir. Así nada se pierde aunque la tabla
  se vaciara, y la primera vez de cada teléfono es una lectura más (no hay función de importar).
- La poda (las no fijadas valen por su día y su semana) es **solo del teléfono y no se manda**: un teléfono viejo no puede
  borrar lo que el cliente fijó después en otro. Lo vencido que quede en el servidor, cada teléfono lo poda al leerlo.
- Al leer, queda lo del teléfono en lo que se tocó mientras se esperaba, lo que estaba en la cola al empezar y lo que
  quedó en fallidos.
- Si el cliente vuelve a la app vieja, la migración solo aplica lo que cambió ahí desde la corrida anterior
  (`ejercicios-swaps-legado_<rutina>.json` es la base).
- Topes de la base: clave de 1 a 120 caracteres (puntos de código), entrada de hasta 16 KB, 300 claves por rutina
  (lápidas incluidas). Lo que no entra queda solo en el teléfono.
- Sin clave foránea a `mypump_rutinas`: si el Cerebro borra y vuelve a crear una rutina, un `ON DELETE CASCADE` se
  llevaría las sustituciones.
