# Estado de las apps nativas de MyPump

> Lo lee primero cualquier sesión que retome el trabajo. Plan aprobado el 13-oct-2026:
> `~/.claude/plans/planifica-la-ejecucion-de-atomic-crescent.md`. El pedido original está en
> `docs/PROMPT_SESION_APPS_NATIVAS.md`.

## Candado

**Trabaja:** sesión `7a9c6371` (MacBook), desde el 13-oct-2026 23:59.

Si el candado es de otra sesión y tiene menos de 6 h, no se toca este clon. Cuando una sesión termina, deja el
candado libre.

## Dónde

**Clon:** `~/Developer/mypump-nativa`, rama `nativa`. Está fuera de iCloud: el Escritorio sincroniza y ya generó
copias en conflicto.

**Hooks locales:**
- `pre-commit` rechaza commits que toquen `public/`, `ios/` o `android/`.
- `commit-msg` exige `[CF-Pages-Skip]` en el mensaje.

**Evidencias y volcados:** `~/Developer/nativa-evidencia/`. La subcarpeta `privado/` guarda datos reales y nunca se
commitea.

**Reglas fijas:**
- **El merge de `nativa` a `main` va squash.** El commit 2e64484 se llevó por error 182 MB de compilados de SwiftPM (sin secretos) y ya están en la historia de `nativa`, que no se reescribe.
- `swift test` siempre con `--scratch-path ~/Developer/nativa-evidencia/dd/kit`: sin eso deja `.build/` dentro del repo (ahora está en el `.gitignore`).
- Nunca push a `main`.
- Nunca tags `v*` ni `a*`. **Mientras la 1.0.12 esté en revisión (desde el 14-oct 16:24), con más razón:** el
  flujo `v*` de Codemagic tiene `cancel_previous_submissions` y cancelaría el envío.
- Las migraciones van como `supabase/migrations/nativa_NNN_*.sql`, solo con OK (G2).

## Fase actual: 0, lo que pide el §9

| Paso | Estado |
|---|---|
| Clon, hooks y estado | ✅ |
| Toolchain Android + runtimes de iOS 17 y 18 | ✅ JDK 21, SDK 36 con emulador e imagen arm64; iOS 17.5 y 18.6 (simuladores "Nativa iOS 17/18" en `simuladores-viejos.txt`) |
| Cuentas de prueba (`scripts/nativa/sembrar.mjs`) | ✅ `test-nativa-ios`. Falta la visible para el chat |
| `docs/NATIVA_CONTRATO.md` + `apps/shared/contrato.json` | ✅ verificado contra `pg_proc` |
| `docs/NATIVA_PARIDAD.md` | ✅ 145 ítems con ID y 9 decisiones para G1 |
| Prueba del almacenamiento viejo en iOS: v1.0.11, v1.0.12-b18 y main × iOS 17, 18 y 26 | ✅ 17.5, 18.6 y 26.5 por las dos rutas y en las dos direcciones (`scripts/nativa/spike-legado.sh`) |
| Prueba del almacenamiento viejo en Android | ✅ emulador Android 16 / WebView 133: la espía lee 23/23 claves y la marca sobrevive a un cierre forzado (`spike-legado-android.sh`) |
| Bocetos en el simulador → G1 | ⏳ |

## Fase 1-2 (en paralelo, desde el 14-oct)

| Pieza | Estado |
|---|---|
| Motor: modelos, cliente RPC, cola, ModeloApp, copia offline | ✅ con integración real (`test-nativa-real`) |
| Reglas con vectores de la web | ✅ progresión, clave, porción casera, anclaje e hidratación de swaps, sustitución de alimentos (2.510 casos) y de ejercicios (323 + 3.232 privados), alimento propio, comida libre |
| **Dieta (iPhone)** | ✅ datos reales, sin Comí/Salté (D10), mano, reemplazo, alimento propio con escaneo, comidas libres. XCUITest en 17.5 y 26.5. Falta: dieta de ejemplo (DIE-17), recarga al cambiar el día (DIE-18) |
| Modelos de Chat, Revisión/Mi Día, fotos de progreso y Progreso | ✅ con tests y backend real (falta conectar las pantallas: lo hace el agente de diseño) |
| Bienvenida, demo, sin conexión, aviso de guardado, volver a primer plano | ✅ (XCUITest de acceso) |
| Notificaciones (local del domingo, push, destinos) | ✅ push real al iPhone de Mati aceptado por APNs (14-oct 18:34; falta que confirme que lo vio y que abrió Revisión). El del domingo, visto en lo que iOS deja agendado en el simulador. En su iPhone se ve el domingo 18-oct a las 11:00 |
| Respaldo científico (14 fuentes), entitlements, PrivacyInfo, workflow `ios-nativa` | ✅ (el workflow no se dispara hasta que Mati acepte el contrato de Apple) |
| Migración del almacenamiento viejo (Fase L/R + write-back) | ✅ simulador 26.5 23/23 y 17.5 22/22 (`scripts/nativa/sim-migracion.sh`). **TF-0 con la 100 falló en el iPhone** (no encontraba los archivos, ver bitácora 14-oct 14:15); arreglado en la 101 y probado contra la copia real |
| Motor de Entreno (`ModeloEntreno` + reglas) | ✅ mergeado: 4.546 vectores públicos y 80.461 privados, integración real |
| Revisión adversarial del código iOS (19 hallazgos) | ✅ 18 arreglados con regresiones (`RegresionesRevisionTests`); el 19 (entitlement de HealthKit sin código, badges fijos) lo cierran Salud y diseño |
| `normalizarDieta` | ✅ igual a la web en 11 casos públicos y las 90 dietas reales |
| Diseño "pro" + conectar Entreno, Chat, Revisión, Progreso y Mis datos a los modelos | ✅ mergeado (1ad2484); Dieta, Acceso y Salud con el mismo sistema (86f28e4); 8 XCUITest. Revisión adversarial de las escrituras en curso |
| Salud (HealthKit, recuperación, relojes) | ✅ mergeada: 35 casos de la web + banco en simulador 1.091/1.091 registros; el historial ya no pisa la noche de hoy (desvío a propósito, ver `NATIVA_PROPUESTAS_WEB.md`) |
| Hoja de permisos de la primera vez (GEN-06), aviso de fin de descanso (D8), aviso de plan incompleto (GEN-05) | ✅ (XCUITest del onboarding) |
| Android: base, reglas y capa de datos (`:core`) | ✅ mergeado en `nativa` el 14-oct (81338b8): reglas con los vectores de la web, Entreno, Salud, cola, chat, Revisión, migración (parte pura), palanca, recibo y conteos (`nativa_001`, probada contra el backend con `test-nativa-android`) |
| Android: lector del almacenamiento viejo con WebView y arranque de la migración en `:app`, prueba en el emulador, D7 | ✅ mergeado el 14-oct (4e48457): leveldb encontrado sin rutas fijas, **24/24 de punta a punta en el emulador** (`scripts/nativa/emu-migracion.sh`), D7 en el modelo y la cola; 400 tests JVM + 9 instrumentados. Backup decidido (D14). Falta: un teléfono real con la 1.0.12 de Play |
| Android: pantallas en Compose | 🟡 acceso, demo, sin conexión, permiso de la IA, Dieta en lectura y Mis datos (375f970); fuentes y legales en una Custom Tab (0c745f7); 43 pruebas instrumentadas. Entreno en curso (subagente, en un worktree). Faltan Chat, Revisión, Dieta con escritura y Progreso |
| Android: Health Connect, FCM | ☐ |


**Control de la beta (G5):** `python3 scripts/nativa/beta_diario.py [--dias 7] [--con-pruebas]` da, por cliente con la
nativa, su teléfono (versión, push, última vez visto), el último recibo de la migración y las sustituciones en el
servidor. Avisa con ⚠️ si alguna tabla del servidor bajó (cero pérdida) o si quedó algo en la cola, en fallidos o en
fotos. Solo lee y muestra ids, sin nombres. En las cuentas test-* las alertas son las que siembra
`sim_migracion.py`: una op desconocida y una foto fuera de ventana.

**Antes de G7:** regenerar las capturas de la tienda (`scripts/nativa/capturas-tienda-ios.sh`). Las del 14-oct 14:58 son
anteriores a los cambios de esa tarde: Mis datos sin IA ni recordatorios, y la pista de la última vez como botón.

**Herramientas nuevas:** `scripts/nativa/lanzar-sim.sh` (abre la app con una cuenta de prueba sin que el token pase por
la terminal), `probar-ui.sh` (XCUITest con `TEST_RUNNER_MYPUMP_TOKEN`), `spike-legado.sh`.

## Compuertas

| Compuerta | Estado |
|---|---|
| G1 · bocetos, estimación y decisiones de paridad | pendiente (no frena el motor) |
| G2 · migraciones de esquema | ✅ **`nativa_001` y `nativa_002` aplicadas** (14-oct, OK de Mati; las corrió él). Verificado por la API pública. Auditoría de seguridad sin agujeros: `mypump_get_app_config` es pública a propósito. Esquema regenerado. **`nativa_003` (sustituciones de ejercicio, SER-14) aplicada por Mati el 14-oct a las 18:16**: API pública, esquema (solo agregados) y auditoría sin agujeros, y una sustitución pasa entre dos teléfonos contra producción. Pendiente para otra tanda: `mypump_borrar_serie` |
| G4 · descargas | Android: `androidx.browser`, `ui-test-junit4`/`ui-test-manifest` (14-oct) y **Firebase Messaging 25.0.1 + plugin google-services 4.4.4 + Health Connect `connect-client` 1.1.0** («dale», 14-oct 21:10). Son las versiones que ya compila la Capacitor y están en la caché de Gradle. El `google-services.json` es el de `android/app` (ya público, proyecto mypump-663be) |
| G5 · TestFlight externo | pendiente. Los internos ya están autorizados |
| G6 · mensajes a clientes | pendiente |
| G7 · revisión de tiendas | pendiente |

## Decisiones tomadas en autónomo (13/14-oct, Mati: "seguí sin mi intervención")

| # | Decisión | Por qué |
|---|---|---|
| D1 | Comodín: como hoy (un día más) | Paridad por defecto |
| D2 | `mensajes_semana` y el título de la progresión: como hoy (no se muestran) | Paridad por defecto |
| D3 | Entrada fija a **Mis datos** (recordatorios, Salud, diagnóstico, privacidad, "Eliminar mis datos") | La exige Apple 5.1.1(i) para el link de privacidad; sin score no se llegaba |
| D4 | Textos corregidos (recordatorio de entreno inexistente; "11:00", no "mediodía") | Que la app no mienta |
| D5 | Tema: sigue al sistema salvo que el cliente haya guardado `'dark'` | `theme.js` escribe `'light'` siempre, así que no es una elección |
| D6 | Lima en la interfaz; el ícono no cambia | Identidad actual |
| D7 | ~~IA de terceros (5.1.2(i)): permiso con un "no" real~~ **Sacado el 14-oct a las 18:45 (Mati): "la IA es algo que funcionaba bajo mi aprobación, no tiene que ser algo que la persona tenga que aceptar".** Sin interruptor ni hoja en las apps; los scripts de la Mini volvieron a la versión sin filtro (los restauró Mati a las 18:48). La tabla `mypump_consentimiento_ia` queda sin uso | En su lugar: el nombre se tapa con la IA local de la Mini antes de Codex, y el chat de la app escribe con la skill `responder-clientes` (en diseño, ver bitácora) |
| D8 | Aviso local de fin de descanso con la app en segundo plano | Mejora sin riesgo |
| D9 | Borrado: link a `eliminar-datos.html` desde Mis datos, sin RPC | No hace falta tocar la base |
| D10 | **Sin "Comí / Salté" en Dieta** (pedido de Mati, 14-oct). Se va también el consumo parcial; el anillo muestra el objetivo y cuánto suman las opciones elegidas | Le resultaba molesto al cliente. El coach deja de recibir esas marcas de los clientes con la nativa (la web las sigue teniendo) |
| D11 | **Sin dieta usable: "Todavía no hay plan de comidas"** (la web mostraba la dieta de ejemplo de 3.200 kcal como si fuera del cliente) | Engañaba al cliente; la demo sigue mostrando el ejemplo |
| D14 | **Android: el backup de Google sigue llevándose `app_webview/`** (la app vieja), como con la Capacitor, **menos sus cachés**. Decidido por la sesión con el "hacelo todo vos" de Mati (14-oct) | Restaurado en un teléfono nuevo, el cliente entra sin pegar el link. La copia va cifrada de punta a punta con el bloqueo de pantalla y el token de la nativa no viaja nunca. Las cachés se regeneran y podían pasar el tope de 25 MB, que deja sin copia a todo |
| D15 | **El aviso del domingo no se configura y llega como un mensaje de Mati** (14-oct, Mati: "tienen que parecer enviados por mí"): título "Mati", "Cómo venís esta semana? Subí tu revisión así te hago la devolución", domingos a las 11:00. Mis datos solo ofrece activar las notificaciones si falta el permiso | Quien lo había apagado en la app vieja lo vuelve a recibir; solo lo corta desde los Ajustes del teléfono |
| T1 | Cola, caché y swaps en **JSON con escritura atómica**, sin GRDB | Volumen chico; cero dependencias de terceros |
| T2 | Cliente RPC propio (URLSession), sin supabase-swift | Hace falta el código HTTP para clasificar errores (aprobado 13-oct) |

## Limitaciones conocidas (igual que la web)

- **Desconfirmar una serie no la borra del servidor** (revisión del 14-oct, hallazgo 9). Si el cliente la deja sin
  volver a confirmarla, Mati la sigue viendo. Arreglo propuesto para una tanda de G2: una RPC
  `mypump_borrar_serie(p_token, p_sesion_id, p_ejercicio_id, p_serie)` y un kind `carga_del` en la cola de las dos apps.

## Lo que solo puede hacer Mati

- ~~Aceptar el contrato nuevo del Developer Program~~ (aceptado el 14-oct).
- ~~Publicar la 1.0.12 de iOS antes que la 2.0.0~~. **Enviada a revisión el 14-oct a las 16:24**, con OK de Mati:
  build 18 (el de `v1.0.12-b18`, que es `main` salvo el texto de privacidad), publicación automática al aprobarse y
  progresiva en 7 días. Ojo: la versión que estaba en la App Store era la **1.0.6**; la 1.0.11 nunca salió.

## Bitácora

- **14-oct 21:00, fuera de las apps pero ligado a ellas (Mati: «hacelo todo vos», «seguí en autónomo»):**
  - **WhatsApp sin nombres** (elección de Mati: «tapar el texto»). Cada cliente es un alias fijo (`CL-7F3A`), unido a
    su ficha por el teléfono.
    - Código en `~/Desktop/Pump-Respuestas/wa-mcp/src` (no está en git; lo respalda iCloud): `alias.mjs`,
      `pedidos.mjs`, `mcp.mjs`, `mini.mjs`, `vigia.mjs` y `aprobacion.mjs`, con 28 pruebas.
    - Hook de AskUserQuestion en `~/.claude/settings.json`: los nombres van solo en las descripciones de las opciones,
      que no vuelven a la IA. Verificado en el registro de la sesión.
    - La sesión de Mensajes lo adopta cuando Mati le dé el OK. Detalle en la memoria `whatsapp-tapado-alias`.
  - **Fuga corregida:** con Qwen caído, `app_chat.py contexto` mostraba los otros clientes de CANDIDATOS. Ahora la
    pasada fija tapa los nombres de todas las fichas. 1f30b5f, desplegado; se borró el caché con la fuga.
  - **Gerardo Damyan Tejeda:** la fila 403 de `clientes_memoria` se llamaba como su teléfono y el brief no la
    encontraba. Se renombró (backup en la Mini, `~/pump-backups/clientes_memoria/`).
  - **El aviso «💡 guion de Reel»** salía en cada mensaje de todas las sesiones, porque UserPromptSubmit no usa
    matcher. Ahora `~/.claude/hooks/guion_reel.py` mira el texto y solo avisa con un guion de verdad.
  - **Beta y tienda:** `NATIVA_BETA.md` y `NATIVA_TIENDAS_2.0.0.md` al día, sin D7. `scripts/nativa/beta_diario.py`
    para el control diario.

- **14-oct 19:00, Mati probando la 101 en su iPhone:**
  - **"El toca para registrar lo de la última vez no funciona":** la pista era texto; en la web es un botón
    (`cliente.html:4044`, `data-sugconfirm`). Ahora confirma la serie igual que el ✓ (TablaSeries `pista`), con
    UltimaVezUITests (cuenta de prueba: la demo no tiene historial). Avisado el agente de Entreno de Android.
  - **D7 sacado** (ver la tabla de decisiones): sin interruptor ni hoja en iOS; la foto del plato y la de la etiqueta
    se analizan siempre. Android, en un agente aparte. En la Mini, Mati restauró los `.bak-pre-d7` a las 18:48
    (md5 iguales a `a42a276^`, verificado; el chat siguió corriendo). En el repo, los tres scripts vuelven a esa
    versión y se va `scripts/test_consentimiento_ia.py`. Al momento de sacarlo, la única respuesta guardada era la de
    la cuenta de Mati (un "no" de las 18:40): ningún cliente quedó sin IA.
  - **D15:** el aviso del domingo llega como un mensaje de Mati y no se configura.
  - **El chat de la app lo contesta la sesión "Mensajes clientes Pump Team"** (elección de Mati, 19:10), con la skill
    `responder-clientes` y su aprobación:
    - `~/.claude/skills/responder-clientes/scripts/app_chat.py` (copiado a `~/pump-respuestas/` de la Mini):
      `bandeja` / `contexto <id>` / `responder <id> [--aplicar]`;
    - la sesión NO ve el nombre: lo tapa `agent/medical/deid_qwen` (ficha + Qwen). El mapa queda en la Mini
      (`~/pump-respuestas/cache/app/`, 600) y el nombre vuelve al publicar;
    - en el chat, Qwen tapaba palabras del entreno ("el cardio lo hago antes o después de entrenar" salía
      "el [INSTITUCION_1]… de [TRABAJO_1]"). `app_chat.py` le suma al filtro el vocabulario del entreno y la dieta, y un
      trabajo o una institución solo se tapan con nombre propio o número. El módulo compartido no se tocó;
    - probado de punta a punta con `test-nativa-real`: el teléfono y el nombre tapados, 2 mensajes publicados como Mati
      (`origen='ia'`, `meta.respuesta_a`, `via='sesion-mensajes'`) y un push «Mati» por mensaje;
    - guía en `references/chat-app.md` y tres líneas en `SKILL.md`. Avisada la sesión de Mensajes.
  - **`CHAT_IA_AUTO=0`** en `~/pump-centinela/.env` (OK de Mati, 19:20; backup `.env.bak-auto-20261014`): el worker de
    Codex ya no manda nada solo. Sigue dejando borradores en el Cerebro y avisando.
  - **El worker de Codex tampoco recibe el nombre** (e00095f, desplegado con OK de Mati a las 19:33; backups
    `*.bak-sinnombre-20261014`): `deid_chat.py` compartido con la bandeja de la sesión. `scripts/test_chat_sin_nombre.py`
    da 16/16 en el Mini con Qwen real y con los archivos ya instalados. Si no se puede tapar, el mensaje no va a la IA y
    queda para Mati.
  - **Política de privacidad** (OK de Mati al texto, G3): commit e171038 en la rama `privacidad-sin-permiso-ia`, sobre
    `main` (c682643). La sube Mati con
    `git -C ~/Developer/mypump-nativa push origin privacidad-sin-permiso-ia:main`.

- **14-oct 18:45, "hacelo todo vos" (Mati):**
  - **`nativa_003` aplicada** por Mati a las 18:16 (captura de su terminal: COMMIT). Verificado:
    - leer, guardar y borrar responden por la API pública;
    - el esquema regenerado (b76f4d1) solo agrega;
    - `auditar_seguridad_db.py` no encuentra agujeros (lo que marca ya estaba y es a propósito);
    - **una sustitución pasa de un teléfono a otro y vuelve contra producción**, con la cuenta `test-nativa-real`
      (IntegracionTests.unaSustitucionPasaDeUnTelefonoAOtro, 38b641a);
    - la migración en el simulador sube la sustitución de la app vieja: **25/25** ("Remo sentado en polea",
      `migracion/20261014-181947`).
  - **Android:** `androidx.browser`, `ui-test-junit4` y `ui-test-manifest` (G4 con el OK). Las fuentes y los legales
    abren en una Custom Tab, como el Safari de iOS (0c745f7). **43/43 instrumentadas** en un emulador propio
    (`nativa36b`; el `nativa36` lo usa el subagente de Entreno). D14 decidido (58bac1d).
  - **En el iPhone de Mati** (su cuenta, su único teléfono registrado, la 2.0.0 de TestFlight):
    - **push real:** `mypump_encolar_push` a su cuenta con destino Revisión (cola 1503). `push.py` lo mandó a las 18:34
      y APNs lo aceptó ("1 enviados, 0 con error"). Falta que confirme que lo vio y que tocarlo abrió Revisión;
    - **`?diag=health`:** abierto con `devicectl … --payload-url`. Un link sin `t=` no cambia la cuenta
      (`FormatoToken.extraer` da nil). No se pudo ver la pantalla: la duplicación del iPhone dice "iPhone en uso";
    - **el AASA del CDN de Apple** solo abre la app para `/`, `/cliente` y `/cliente.html` **con `t`**. El link de
      soporte tiene que ser `?t=<token>&diag=health` (igual que con la Capacitor: el AASA es el mismo);
    - **el aviso del domingo:** visto en lo que iOS deja agendado en el simulador 26.5 con una prueba nueva
      (AvisosUITests: "Activar recordatorios" con el permiso aceptado). Queda un solo pedido: 1002, domingo 11:00,
      semanal, "Tu revisión de la semana", abre Revisión. Lo lee `scripts/nativa/avisos_programados.py <udid>`. En el
      iPhone de Mati se verá el **domingo 18-oct a las 11:00**.
  - **Falta en el iPhone, con el teléfono libre (bloqueado, para la duplicación):** el diagnóstico de Universal Links
    (Ajustes → Desarrollador) con un link de prueba, sin abrirlo, y ver la hoja de `?diag=health`.

- **14-oct 17:30, sustituciones de ejercicio en el servidor (SER-14, decisión de Mati de las 16:24):**
  - **Base:** `supabase/migrations/nativa_003_sustituciones_ejercicio.sql`. Una tabla (`mypump_exercise_swaps`) y cinco
    funciones; no cambia nada existente y la web no la usa. Ensayo en producción dentro de una transacción, deshecho al
    final: **61/61**, también llamando como `anon`.
  - **Cómo funciona (iOS 9cd1f65 + 9edff18, Android 1d151d9 + d0a579b, las dos + d10c974):**
    - cada entrada lleva la hora en que el cliente la eligió y **gana lo más nuevo**, en el servidor y al leerlo;
    - borrar deja una **lápida** con la hora de lo que se borró: otro teléfono no la revive con algo más viejo, y no saca
      algo más nuevo que el cliente no vio;
    - un reloj desfasado no gana: la lectura trae la hora del servidor y el teléfono estampa corregido; además el servidor
      recorta las horas a la suya + 5 minutos y una copia propia del futuro no le gana al servidor;
    - que algo falte en el servidor **no es un borrado**: el teléfono lo vuelve a subir (nada se pierde aunque la tabla
      se vaciara);
    - la **poda es solo del teléfono** y no se manda;
    - la cola **no muestra avisos** por estas operaciones, como antes, cuando no tocaban la red;
    - lo que no llegó a la cola porque la app se cerró se encola al volver a abrir;
    - si el cliente vuelve a la app vieja, solo se aplica lo que cambió ahí.
  - **Revisión independiente** (subagente, solo lectura), en rondas:
    - sobre la primera versión, 7 hallazgos reales; el más grave, que la poda de un teléfono viejo podía borrar en el
      servidor lo que el cliente fijó después en otro;
    - sobre la segunda, 3 más: "Guardando…" colgado en escrituras normales, la vuelta a la app vieja que podía borrar una
      fijada de otro teléfono, y los relojes adelantados.
    - sobre la tercera, 2 restos raros de relojes desfasados, también cubiertos (d10c974).
    - Todos quedaron cubiertos, cada uno con su prueba. Veredicto de la revisión: **se puede aplicar**; no hay pérdida de
      datos con relojes bien puestos.
  - **Igual que antes mientras la 003 no esté aplicada** (PGRST202): todo queda en el teléfono y sin avisos nuevos. La
    migración en el simulador dio **25/25** con la versión final (17:56; la fila nueva dice "sin tabla").
  - **Pruebas:** iOS 373 y Android 436, en verde. Mutantes: 18 en iOS y 17 en Android, uno por protección, y caen todos.
  - **Regla para siempre:** una vez aplicada, las firmas de estas funciones no se cambian (ver `NATIVA_CONTRATO.md` §11):
    la app toma "la función no existe" como "todavía no hay tabla" y perdería cambios en silencio.
  - Ningún build con una versión anterior de SER-14 salió de la Mac: los de TestFlight (101 y 102) no tienen SER-14.
  - **Para aplicarla (G2, la corre Mati; el archivo ya está en la Mini, md5 `1f8f52d9…`, igual al del repo):**
    `ssh mini 'cd ~/agentkit-coach && venv/bin/python ~/_aplicar.py /tmp/nativa_003_sustituciones_ejercicio.sql'`
    Después: regenerar el esquema, correr `auditar_seguridad_db.py` y ver una sustitución pasar entre dos simuladores.
- **14-oct 17:30, lo demás de la tarde:**
  - **Fotos contra el servidor real** (4a1acd8): una foto como las de la cámara (4032×3024, con GPS) queda guardada como
    JPEG de 675×900, derecha y **sin ubicación**; la de la cola de la web sube sola. Cierra MIG-03, REV-02 y REV-03.
  - **El aviso de arriba tapaba "volver"** (a3254ff): en iOS 26, el aviso de la demo y el de "Sin conexión" tapaban el
    botón de volver del detalle de un ejercicio. En la demo es lo que mira App Review, y sin señal le pasaba a un cliente.
    Lo encontró la prueba nueva de Entreno, mirando la grabación. De paso, VoiceOver ahora lee la card entera (antes no
    oía la sustitución, los mensajes, la pauta ni el récord). Suite de interfaz entera en verde, en 17.5 y en 26.5.
  - **Números como la web en iOS** (dd270a7): con el iPhone en otra región se veía "2,454 kcal" junto a "15,1 g". Ahora
    es siempre `es_AR`. Lo encontró la revisión de Android, igual que el "según tu iPhone" que aparecía en iPad.
  - **Interfaz de Android en Compose** (merge 375f970): acceso, demo, sin conexión, permiso de la IA, Dieta en lectura y
    Mis datos, con 42 pruebas instrumentadas. Encontró y arregló tres errores propios: se colgaba con la red lenta al
    pegar el link, la demo dejaba su pestaña a la cuenta y había texto negro sobre negro en oscuro. Queda en
    `apps/android/README.md` lo que sigue: Entreno, Chat, Revisión, Dieta con escritura, Progreso, notificaciones y
    Health Connect.
  - **Para decidir (Android):**
    - agregar `ui-test-junit4`/`ui-test-manifest` (pruebas de interfaz estándar) y `androidx.browser` (fuentes y legales
      dentro de la app, como iOS): son descargas nuevas (G4);
    - Android 16 anota el link entero (con el token) en sus registros de transición. Le pasa a cualquier app, también a
      la Capacitor de hoy: un `adb bugreport` del teléfono de un cliente lleva su link.

- **14-oct 16:24, decisiones de Mati y la 1.0.12:**
  - **Decisiones:**
    - ACC-08: D11 también vale para la rutina; queda "Todavía no hay rutina".
    - CHA-01 y ENT-17: aceptados como desvíos de diseño.
    - SER-14: preparar la tabla de sustituciones en el servidor (G2).
    - Pidió "que se mantenga todo funcionando igual o mejor que antes".
  - **1.0.12 enviada a revisión de Apple:**
    - la versión que estaba publicada era la **1.0.6**, porque la 1.0.11 nunca salió;
    - el build 18 lleva la web del 22-sep, que es `main` salvo el texto de privacidad: no hacía falta recompilar;
    - sin permisos nuevos respecto de la 1.0.6;
    - las Novedades en castellano y las notas para el revisor nuevas ("WHAT IS NEW IN 1.0.12"), con el resto de las
      notas de la 1.0.6 igual;
    - publicación automática al aprobarse y **progresiva en 7 días**, que se puede pausar.
- **14-oct 15:55, la tarde sin el iPhone (Mati afuera):**
  - **Auditoría de la paridad de iOS** (subagente, solo lectura): 103 ítems con evidencia; 69 ya estaban hechos.
    Resumen y lo que falta al pie de `NATIVA_PARIDAD.md`.
  - **Error real en iOS 17** (424f5af), lo agarró correr la suite de interfaz en 17.5: en Dieta, "A mano", "Con foto"
    y el permiso de la IA de comidas libres no hacían nada. La sección vivía al final de un `LazyVStack`, y en iOS 17
    sus `.sheet` no se presentan. Interfaz: **11/11 en 17.5 y en 26.5**, 10/10 en 18.6.
  - **Cerrado de la auditoría:**
    - DIA-01: "Último día válido" con la cuenta real;
    - DIA-06: hábitos pendientes, con test;
    - MIG-07: el recibo cierra con cola real, chequeo en el simulador;
    - MIG-03: la foto migrada llegó al servidor;
    - GEN-02 y D5: el modo oscuro guardado, y "Siempre en modo oscuro" en Mis datos;
    - GEN-03: el aviso de Revisión en Chat y Progreso;
    - ENT-01: ✓ y 💬 juntos, y sin selector con un día;
    - SAL-11: Salud sin secciones vacías;
    - SAL-13: `?diag=health`;
    - REV-02: fotos con ImageIO, con tests de tamaño, orientación, HEIC y GPS. La galería ya no decodifica entera una
      foto de 48 MP;
    - REV-03 y ENT-15: tests.
  - **Android mergeado** (4e48457): 24/24 en el emulador y D7. Encontró dos errores de iOS, arreglados en b9db8a0:
    - el permiso de la IA quedaba de la cuenta anterior al cambiar de link;
    - una Fase R sin red no se reintentaba hasta el arranque siguiente (`cargasConRed`).
  - **Simulador de punta a punta: 24/24**, con el chequeo nuevo del recibo. MyPumpKit: 328 tests.
  - **Capturas de la tienda** listas (`nativa-evidencia/tienda/20261014-145803`), sin el cartel de la demo y con
    Progreso con datos. La dieta de la demo ya no muestra "−23 %" (f7aa713).
  - **Build 102 OK** en Codemagic (`nios-2.0.0-102` sobre b9db8a0, 16:01). Va a TestFlight interno y le llega solo
    a Mati.
  - Después del 102:
    - prueba de interfaz de SER-04, que muerde;
    - tests de Android tras el merge en verde;
    - las pantallas principales en iOS 17.5 se ven bien, con la barra de pestañas clásica y la del descanso
      anterior a 26.1 (`nativa-evidencia/ios17/20261014-160125`).
  - **Decisiones pendientes de Mati:**
    1. ACC-08: ¿D11 también para la rutina? La nativa dice "Todavía no hay rutina" en vez de la de ejemplo.
    2. CHA-01 y ENT-17: ¿quedan como desvíos de diseño? (el chat sin "Vos"/"Mati", y "Siguiente →" en vez de abrir solo
       el próximo ejercicio).
    3. SER-14: ¿preparo la tabla de sustituciones de ejercicio en el servidor (G2)?
    4. ¿Mando la 1.0.12 a revisión? Tiene que publicarse antes que la 2.0.0.
    5. Android: ¿el backup de Google sigue llevándose `app_webview/`, donde está el token viejo? Era así con la
       Capacitor.
    6. TF-0 en su iPhone: tocar su link en WhatsApp, `?diag=health`, un push real y el aviso del domingo.
- **14-oct 14:50, sin el iPhone (Mati afuera una hora):**
  - **Rama de Android mergeada** en `nativa` (81338b8). Solo toca `apps/android`.
  - **Los hallazgos de iOS del gemelo de Android, arreglados** (04a62c0):
    - FechaJS como V8 (25 casos de node);
    - un motivo de Recuperación con valor null es "0h00";
    - `miles` como `toLocaleString`;
    - el porcentaje de calibración ya no pasa por `Int()`.
  - **Las cinco pruebas de la migración que solo tenía Android**, portadas: pasan (1bfc859).
  - **Simulador de punta a punta otra vez, 23/23** (`migracion/20261014-143532`). Destapó un error real (5eb8738): el
    descanso que trae la migración se cortaba al pasar al día visto, porque se restauraba antes del cambio de día y
    cambiar de día lo detiene. Ahora va como la web (primero el día, después `restoreRest`). En la captura:
    "Descanso / 10:00 — 9:49". El script siembra siempre el arranque de la sesión en curso: el de la cuenta de prueba
    podía tener más de 6 h.
  - En curso: el agente de Android (lector con WebView, arranque de la migración, emulador, D7) y una auditoría de la
    columna iOS de `NATIVA_PARIDAD.md` (103 ítems sin tilde, muchos ya hechos).
- **14-oct 14:25, TF-0 OK con la 101** (iPhone de Mati, iOS 27.0, su cuenta; actualizada desde TestFlight encima de la 100):
  - **Entró sola, sin link**, con el mismo estado que la app de la tienda (Día 2, semana 5 de 12, la sesión vieja
    "Sin cerrar"). Salud sigue conectada ("Este iPhone ya está mandando pasos y actividad") y el recordatorio del
    domingo a las 11:00, prendido.
  - `legado/registro.log` (copiado con `devicectl device copy from`): Fase L corrida 1 con el token adoptado y la
    cola vieja vacía; Fase R con **recibo confirmado**; escritura de vuelta "borrada 15, ok 1". En el arranque
    siguiente, la corrida 2 (repetición por la huella nueva) da **escritura confirmada 1** y todo lo demás en 0.
  - **Recibo** en `mypump_migracion_nativa` (id 1, `2.0.0 (101)`, 17:20:05 UTC): `servidorAntes` = `servidorDespues`
    en las 15 tablas (17 sesiones, 208 cargas, 46 hábitos, 346 días de salud…), como corresponde con la cola vacía.
    Sin tokens (el `otroToken` de `opsPorCola` es el nombre de una categoría).
  - **Push:** la nativa actualizó la fila de siempre en `mypump_push_devices` (ios, `app_version` 2.0.0, 64
    caracteres en hex MAYÚSCULAS, activo, sin error). Sigue habiendo un solo dispositivo: no hay avisos duplicados.
  - **Falta (lo hace Mati):** tocar su link `app.mypumpteam.com/?t=…` en WhatsApp (tiene que abrir la app), recibir
    un push real y que el domingo a las 11 llegue un solo aviso. El informe de Mis datos lo miro en el simulador: la
    duplicación del iPhone no hace scroll con eventos simulados.
- **14-oct 14:15, TF-0 con la 100: falló la migración, arreglado en la 101.**
  - En el iPhone de Mati (iPhone 17 Pro Max, **iOS 27.0**, su propia cuenta) acepté los términos de TestFlight (OK de
    Mati) y canjeé la invitación con el código de la página de Apple, sin tocar el link del mail. La 2.0.0 (100) se
    instaló encima de la de la tienda: **no entró sola, pidió el link.**
  - **Causa:** en el iPhone WebKit guarda en `Library/WebKit/WebsiteData/…`. El lector buscaba solo
    `Library/WebKit/<bundle>/WebsiteData/…`, que es la ruta del simulador (la única probada). La Fase L no encontró
    nada y arrancó como recién instalada. No escribió ni borró nada: el `localStorage` viejo quedó intacto (1,1 MB,
    última escritura 13:51, antes de instalar).
  - **Cómo se vio:** `xcrun devicectl device info files --domain-type appDataContainer` deja listar el contenedor de
    una app de TestFlight (no había `Application Support/legado`) y `device copy from` copia archivos. `log collect`
    de un iPhone pide root.
  - **Arreglo (bb5bcfc):** `LectorLegado.ubicar` recorre todo `Library/WebKit` y reconoce el origen por su archivo
    `origin`. Los tests usan por defecto la ruta del iPhone, más una prueba con la del simulador y otra con las dos.
    `LegadoRealTests` corre la Fase L contra la copia real (`MYPUMP_LEGADO_REAL=…/privado/tf0-iphone`): adopta el
    token; 31 claves, 0 ops pendientes, 1 sustitución, 1 swap de comida, 8 preferencias, 3 sesiones vencidas.
  - De paso, el hallazgo 2 de la revisión de Android: Entreno no leía lo que deja la migración (`sesiones`/`start`
    y el día visualizado por rutina). Prueba de punta a punta. 307 tests.
  - **Build 101** disparado (`nios-2.0.0-101` sobre bb5bcfc). Falta: instalarlo en el iPhone de Mati y verificar
    entrada sola, plan, recibo y conteos.
- **14-oct 13:35:**
  - **Contrato aceptado.** Acepté el Apple Developer Program License Agreement nuevo desde el Chrome de Mati, a pedido suyo ("aceptalo vos por mí"); el login lo hizo él. En App Store Connect el acuerdo de apps gratuitas quedó activo desde hoy. El de apps de pago (nuevo, para cobrar dentro de la app) no se tocó.
  - **Primer TestFlight interno disparado:** tag `nios-2.0.0-100` sobre f14f108. Workflow `ios-nativa` de Codemagic; el estado se ve en el check de GitHub del commit.
    - **Resultado: OK** (compilado, firmado, IPA revisado y subido). Apple lo procesó: 2.0.0 (100) "Lista para enviar"; vence a los 90 días.
  - **TestFlight interno armado** (OK de Mati): grupo **"Equipo Pump"** con distribución automática y Mati como tester (fuarkteam@gmail.com, titular). Tiene las 13 compilaciones; cada build nativo nuevo le llega solo. Falta TF-0 en su iPhone (`docs/NATIVA_TF0.md`).
- **14-oct 13:28:** D7 completa. Política de privacidad publicada (c682643, OK de Mati; el push a `main` lo hizo él porque el clasificador frena los despliegues). `main` mergeado en `nativa` (20c8c37).
- **14-oct (tarde, 2):**
  - **Revisión adversarial de las pantallas:** 14 hallazgos, arreglados 13 con tests. El 9 queda como limitación,
    igual que en la web.
  - **D7:** el permiso para la IA, en la app y en el servidor.
  - **G2:** OK de Mati. El ensayo de `nativa_001` y `nativa_002` dio OK, pero aplicarlas lo frenó el clasificador:
    las corre Mati.
  - **Desplegado por Mati (14-oct 13:13):** las dos migraciones y los tres scripts, con el md5 igual al del repo. Lo que se corrió:
    1. Las migraciones, que ya están en la Mini:
       `ssh mini 'cd ~/agentkit-coach && venv/bin/python ~/_aplicar.py /tmp/nativa_001_recibo_conteos_palanca.sql && venv/bin/python ~/_aplicar.py /tmp/nativa_002_consentimiento_ia.sql'`
    2. Los scripts, con backup:
       `ssh mini 'cd ~/pump-centinela && for f in chat_worker.py sugerir_pendientes.py centinela.py; do cp $f $f.bak-pre-d7; done' && scp pump-centinela/{chat_worker.py,sugerir_pendientes.py,centinela.py} mini:pump-centinela/`
    - Si los scripts llegan antes que la `nativa_002`, igual andan: "nadie dijo que no".
    - **Ojo:** esos tres scripts están cambiados solo en `nativa`. Si otra sesión despliega desde `main` antes del
      merge, se pierde el filtro.

- **14-oct (tarde):**
  - **iOS:**
    - El diseño "pro" quedó mergeado, con todas las pantallas conectadas a los modelos.
    - La demo de Release ya no lleva datos de la cuenta de prueba (`Muestras.bundle` fuera de Release).
    - Salud sin títulos repetidos y con coma decimal.
    - Dieta, Acceso y Salud con el sistema de diseño.
  - **G2, tanda 1:** preparada sin aplicar (recibo, conteos y palanca remota). La app ya funciona con y sin la migración.
  - **Android:** la prueba del almacenamiento viejo dio OK. El agente de datos sigue con Entreno, Salud y la migración
    pura.

- **14-oct (~11 h, corte por límite de uso):**
  - **Cierres arreglados** (522c871): un número absurdo de la base, la cola o el almacenamiento viejo ya no cierra la
    app. Además, `food_data` falso no se aplica.
  - **Regex** (fe2070d): `.` y `\s` iguales a los de JS, en un solo lugar, con vectores nuevos.
  - **D7 documentado** (1805ad2): opciones en `NATIVA_TIENDAS_2.0.0.md`.
  - Release compila sin advertencias (9,9 MB). 279 tests.
  - **Para retomar:**
    1. **Diseño:** el agente quedó frenado en `.claude/worktrees/agent-a7c9f396d6e2eff0b` con 5 archivos sin commitear
       (Entreno y Mis datos). Hay 150 capturas en `nativa-evidencia/diseno/r4`. Hay que commitear, revisar el diff
       (lo que escribe datos), mergear, correr los XCUITest y sacar `Muestras` del build si ya no se usa.
    2. **Android:** el agente quedó en `.claude/worktrees/agent-a3be09f4e786973f9`, recién arrancado con Entreno,
       Salud y la migración pura. Se retoma con SendMessage.
    3. **Tildar en PARIDAD:** DIE-18 y GEN-07, que ya están cubiertos.
  - **Nunca `git stash` pelado:** el stash se comparte con los worktrees de los agentes.

- **13-oct:** plan aprobado y clon creado.
- **14-oct (madrugada):** MyPumpKit con modelos, reglas portadas con vectores (progresión, clave, porción casera, anclaje e hidratación de swaps), cliente RPC + cola offline + ModeloApp con integración real contra `test-nativa-real`. Agentes en paralelo: motor de sustitutos de alimentos, motor de sustitutos de ejercicios y pulido visual.
- **14-oct (mañana):** Salud mergeada; `ModeloApp.entreno` con el catálogo del servidor; onboarding de permisos; borradores para las tiendas (`NATIVA_TIENDAS_2.0.0.md`) y cambios propuestos para la web (`NATIVA_PROPUESTAS_WEB.md`). 266 tests + 8 de interfaz.
- **14-oct (5-6 h):** merges de migración y motor de Entreno (214 → 228 tests). Revisión adversarial: 4 altos (carrera del link que borraba la sesión, cola trabada, plan que desaparecía con poca señal, cola congelada sin sesión), 9 medios y 6 bajos, todos arreglados con regresiones salvo los de Salud/diseño. Android: base mergeada, sigue con datos.
- **14-oct (4-5 h):** se reanudó tras el corte por límite: los 4 agentes retomaron con su contexto (el de diseño tenía 5 commits). Modelos nuevos con tests contra el backend: chat (con el arreglo n.º 4 que no duplica mensajes), Revisión/Mi Día, fotos de progreso (cola propia), Progreso, notificaciones; respaldo científico; entitlements y PrivacyInfo; workflow `ios-nativa`. Agente nuevo: Salud.
- **14-oct (~2 h):** bienvenida nativa (pegar link con PasteButton, link vencido, sin conexión con reintento automático, universal links) y modo demo sin red; XCUITest de acceso pasan. **Corte por límite de uso:** los agentes de diseño, migración, motor de Entreno y Android quedaron en sus worktrees (`.claude/worktrees/agent-*`, ramas `worktree-agent-*`) con lo que hayan commiteado; retomar revisando cada rama y mergeando a `nativa`.
- **14-oct (1-2 h):** Dieta nativa terminada salvo la dieta de ejemplo: el reemplazo da las mismas 55 opciones que la web para "Huevo entero" (lado a lado con la web local de `origin/main` y la misma cuenta). Spike del almacenamiento viejo OK en 17.5 y 18.6. Merge de los motores de sustitución (alimentos y ejercicios). Agentes nuevos: migración, motor de Entreno, Android.
- **14-oct:** riesgo n.º 1 resuelto en iOS 26.5 (`NATIVA_SPIKE_ALMACENAMIENTO.md`). Contrato verificado contra la base: 50 RPC, ninguna duplicada; `push_pendientes` manda a cada dispositivo a propósito. Cuenta `test-nativa-ios` sembrada.
