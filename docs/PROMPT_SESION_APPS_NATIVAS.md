# Sesión: las dos apps nativas de MyPump (iPhone en SwiftUI, Android en Kotlin)

Sos el desarrollador de **una sola cosa**: construir las apps nativas de MyPump para iPhone y
Android, que reemplazan en las tiendas a la app actual (un wrapper de Capacitor) **sin que nada
de lo que hoy funciona deje de funcionar y sin perder un solo dato de ningún cliente**. Si te
pido otra cosa (planes de clientes, órdenes, marketing), decime que va en otra sesión y volvé
a esto.

Hablame en castellano rioplatense, directo, sin vueltas. Cuando algo no se pueda hacer como lo
pido, decímelo de frente y con el motivo.

> Lo que dice este documento se verificó contra el código y la base el **13-oct-2026**. Las
> rutas y los números son reales a esa fecha. Si algo no coincide, **pará y avisame**: quiere
> decir que el código cambió y el resto puede estar viejo también.

---

## 1. Por qué existe esta sesión

Alan Fried, programador que lanzó una app parecida con muy buen diseño, probó MyPump el 13-oct
y dijo que es "un wrapper" y que hay que hacerla nativa: **SwiftUI en iPhone y Kotlin en
Android**. La idea, con sus palabras: **la parte web no se toca; se crean dos apps nuevas.**

El objetivo es que la app se sienta muchísimo más profesional:
- navegación y gestos nativos;
- animaciones fluidas, tipografía y componentes del sistema;
- modo oscuro y Dynamic Type;
- hápticos.

Lo que ya funciona tiene que seguir funcionando igual.

---

## 2. Las cinco reglas que no se negocian

1. **El Cerebro no se toca.** Es mi editor de planes (`/Users/matiassancari/Desktop/nutriplan`).
   Ahí creo rutinas, dietas y progresiones, y las publica a la base con
   `mypump_publicar_cliente`. Las apps nuevas leen exactamente lo mismo que lee hoy la app. El
   Cerebro no sabe ni le importa qué app usa cada cliente.
2. **La web no se toca.** `app.mypumpteam.com` (carpeta `public/`, Cloudflare Pages) sigue
   igual. La uso en las calls: abro el link del cliente en la Mac y le presento el plan
   compartiendo pantalla. Clientes sin la app también entran por ahí.
   - **Ojo:** un push a `main` del repo de la app publica `public/` al instante. No toques esa
     carpeta.
3. **No se pierde ningún dato.** Todo lo que el cliente cargó y viene haciendo tiene que
   aparecer igual en la app nueva: planes, sesiones, cargas, comidas, hábitos, check-ins,
   fotos, chat y salud. Eso incluye lo que hoy vive solo en el teléfono (ver §5).
4. **La base solo crece.** Se pueden agregar tablas, columnas y RPC nuevas. No se renombra,
   borra ni cambia la forma de nada que use el Cerebro, la web o la app actual.
   - Toda migración se prueba primero dentro de una transacción con rollback.
   - Después se aplica (ver §8) y se deja en `supabase/migrations/`.
5. **Son actualizaciones, no apps nuevas en la tienda.**
   - Mismo identificador en las dos tiendas: `com.pumpteam.mypump`.
   - Los clientes reciben la nativa como un update.
   - Siguen logueados y no reinstalan nada.
   - Se conservan la ficha aprobada del App Store, la DSA de la UE y los permisos de Salud y
     notificaciones.
   - Publicar como app aparte rompería todo eso.

La app actual (Capacitor) **sigue en producción** hasta que la nativa la iguale y pase la
prueba con clientes reales (§7). Nada se reemplaza antes.

---

## 3. Qué hay hoy (verificado 13-oct-2026)

| | Ruta / dato | Qué es |
|---|---|---|
| Repo de la app | `/Users/matiassancari/Desktop/💻 Software y Web (Pump)/mypump-app` | web + wrappers + backend |
| Cerebro | `/Users/matiassancari/Desktop/nutriplan` | editor de planes (NO TOCAR) |
| Cliente web | `public/cliente.html` (**9.892 líneas**) + `public/js/*.js` | toda la app que ve el cliente |
| JS | `healthkit-bridge.js` 1.378 · `app.js` 789 · `supabase-client.js` 721 · `food-db.js` 601 · `notificaciones.js` 462 · `deeplink.js` · `theme.js` | lógica |
| Landing | `public/index.html` (457) | sin token: botón "Ver demo" (lo usó App Review) |
| Wrapper | Capacitor 8 · `capacitor.config.json` · `ios/` (`AppDelegate.swift`) · `android/` (`MainActivity.java`) | shell nativo |
| Plugins | `@capacitor/app`, `browser`, `local-notifications`, `push-notifications`, `@capgo/capacitor-health` | |
| Identidad | `com.pumpteam.mypump` en las dos. iOS mínimo **15.0**, Android `minSdk` **26** | |
| Backend | Supabase `gydinputrtptqakdzyvc`, ~80 migraciones en `supabase/migrations/` | RPC `SECURITY DEFINER` por token |
| Servicios | Mac mini: `pump-centinela/` (Python: centinela, `push.py`, `chat_worker.py`, `recordatorios.py`, `wearables.py`) · `mini-vision/server.mjs` (Node) en `vision.mypumpteam.com` | push, IA del chat, análisis, escaneo de etiquetas y foto del plato |
| Builds | `codemagic.yaml`: workflows `ios-testflight` y `android-play`. Tags `v*` (iOS) y `a*` (Android). Un número de build no se reusa. | 1.0.12 = build 18 en las dos |

**Uso real (últimos 30 días, al 13-oct):**
- 62 clientes activos.
- **≥ 23 usan la app de iPhone** (sincronizan Apple Health).
- ≥ 9 usan la de Android (Health Connect).
- ~11 tienen push web.

Por eso **iPhone va primero**.

- **Push de iOS: hoy no hay ningún dispositivo iOS registrado.** El arreglo de
  `AppDelegate.swift` está en la 1.0.12, que en iOS espera que Mati acepte el nuevo contrato del
  Developer Program. La app nativa tiene que registrar el push de iOS desde el día 1.

**La lectura obligatoria antes de arrancar:**
- `docs/ARCHITECTURE.md` y `docs/SCHEMA_DIETA.md`.
- Los comentarios de `supabase/migrations/001_mypump_schema.sql`: el esquema de
  `mypump_rutinas.estructura`.
- El índice de memoria
  `/Users/matiassancari/.claude/projects/-Users-matiassancari-Desktop-nutriplan/memory/MEMORY.md`
  y las notas de la app que nombra. Ahí está cada bug que costó encontrar. Si no lo leés, lo
  vas a volver a meter.

**REGLA DURA:** nunca leas entero `public/cliente.html` ni `nutriplan/index.html`. Se navegan con
`grep -n` y después `Read` con offset/limit.

---

## 4. El contrato: lo único que las apps nuevas pueden usar

Las apps nativas hablan con el backend **igual que la web**: anon key pública + token del
cliente como parámetro de cada RPC. No hay login con contraseña. El acceso es el link
`https://app.mypumpteam.com/?t=<token>`.

**53 RPC que usa la app hoy.** Se sacaron cruzando los textos del cliente con `pg_proc`. Antes de
escribir código, confirmá cuáles se llaman de verdad y con qué parámetros, mirando la definición
VIGENTE con `pg_get_functiondef` en la base.
- No confíes en el último archivo de migraciones: al 13-oct la `079_publicar_conserva_ids_de_dia.sql`
  está en el repo **sin commitear y sin aplicar**.

- **Lectura (29):** `chat_nuevos`, `get_adherencia_30d`, `get_chat`, `get_checkin_semana`,
  `get_cliente_info`, `get_cliente_prefs`, `get_comentarios`, `get_comidas_libres`,
  `get_comidas_marcadas`, `get_conexiones`, `get_custom_foods`, `get_dieta_activa`,
  `get_ejercicios_estado`, `get_entrenos_health`, `get_food_swaps`, `get_fotos_progreso`,
  `get_gasto_real`, `get_habitos_dia`, `get_historico_ejercicio`, `get_historico_ejercicios`,
  `get_historico_por_clave`, `get_mostrar_recuperacion`, `get_recuperacion`,
  `get_registros_sesion`, `get_rutina_activa`, `get_salud`, `get_sesion_dia`,
  `get_sesiones_semana`, `get_streak`.
- **Escritura (24):** `activar_siguiente`, `agregar_comentario`, `avanzar_semana`,
  `borrar_comida_libre`, `crear_comida_libre`, `create_custom_food`, `delete_food_swap`,
  `desconectar_wearable`, `desmarcar_comida`, `encolar_push`, `finalizar_sesion`,
  `guardar_checkin`, `ingest_entrenos`, `ingest_salud`, `iniciar_sesion`, `marcar_comida`,
  `marcar_ejercicio_estado`, `marcar_leidos_cliente`, `registrar_carga`, `registrar_push`,
  `registrar_push_web`, `save_food_swap`, `set_habito`, `set_mostrar_recuperacion`.
- Todas con prefijo `mypump_`.

**Además:**
- Tabla `mypump_ejercicios_catalogo`: fotos y patrón de movimiento para los sustitutos.
- HTTP `/api/wearables/disponibles` y `/api/wearables/iniciar` (Cloudflare Pages Functions,
  `functions/api/`).
- `vision.mypumpteam.com` (etiquetas y foto del plato).
- La subida de fotos de progreso (`cliente.html:7549`, endpoint `/upload`: verificar adónde va).
- El push sale de `mypump_push_cola` (campo `destino`, a qué pantalla abre) por `push.py`.
  Los dispositivos van en `mypump_push_devices`: `plataforma`, `token`, `app_version`.

**Lo que publica el Cerebro y la app solo dibuja:**
- `mypump_rutinas.estructura`: días con `id` (OJO: `d<n>`, `b<v>d<n>`, `r<n>d<n>`; ver 079),
  bloques y ejercicios. Cada ejercicio trae `id`, `tipo`, `images`, `catalogo_slug` y
  `progresion` por semana: `series`, `reps`, `rir`, `titulo`.
- Más `mensajes_semana`, `semanas_total`, `semana_offset` y `fase`.
- `mypump_dietas.estructura`: `macros_target` + comidas con opciones A/B/C/D intercambiables
  **por comida**.
- La progresión **ya viene calculada**: la app no la inventa, la muestra.

Si la app nativa necesita algo que no está, se agrega del lado del servidor (regla 4), nunca
cambiando lo que publica el Cerebro.

---

## 5. Lo que hoy vive SOLO en el teléfono (el riesgo de perder datos)

La app actual guarda cosas en el `localStorage` del WebView. Una app nativa no las ve. Hay que
rescatarlas en el **primer arranque de la versión nativa, leyendo el almacenamiento que dejó la
app vieja en el mismo teléfono**. Sigue ahí porque es la misma app actualizada.

- En iOS se lee cargando un `WKWebView` en el mismo origen que usaba Capacitor, con un
  `WKURLSchemeHandler`.
- En Android, con un `WebView` en `https://localhost`.
- Una página mínima lee `localStorage` y se lo pasa al código nativo.
- **Verificá el origen exacto:** `capacitor.config.json` tiene `iosScheme: "https"`, y Capacitor
  no deja usar http/https como esquema propio.

| Clave | Qué es | Qué hacer |
|---|---|---|
| `mypump_token` | el acceso del cliente | pasarlo al Keychain / EncryptedSharedPreferences. Sin esto, todos tienen que volver a abrir su link |
| `mypump_offline_<TOKEN>` | **cola de escrituras sin sincronizar** (series, comidas, hábitos, swaps) | ejecutarla contra las mismas RPC antes de mostrar nada; si falla, no borrarla |
| cola de fotos (`FOTOQ_KEY`) | fotos de progreso sin subir | subirlas |
| `mypump_exercise_swaps_<RUTINA_ID>` | **sustituciones de ejercicio que eligió el cliente, incluidas las fijadas.** Hoy existen SOLO en el teléfono (`cliente.html:2030-2035`, `:2127`, `:8827`) | tabla + RPC nuevas (aditivas) y subirlas. La app nativa las guarda en el servidor desde ese momento |
| `mypump_tipo_dia`, preferencias de notificaciones (`notificaciones.js`), `mypump-theme` | preferencias | migrarlas |
| marcas de sesión `mypump_sesion_<TOKEN>_<dia>_start/_finalizada/_semana`, `mypump_rest_<TOKEN>` | sesión en curso | la sesión vive en el servidor; verificar que se retoma desde ahí |
| cursores de Salud (`healthkit-bridge.js`) | hasta dónde sincronizó | se recalculan; confirmar que el ingest es idempotente |

Los swaps de **comida** ya están en el servidor (`get_food_swaps`, `save_food_swap`,
`delete_food_swap`) y se **anclan** (ver la memoria de swaps). Todo lo demás (planes, sesiones,
cargas, comidas marcadas, hábitos, check-ins, fotos subidas, chat, salud) **ya está en
Supabase** y no corre riesgo.

**Prueba obligatoria de "no se perdió nada":** en cuentas de prueba y en los clientes beta, contá
filas por tabla antes y después del primer arranque nativo. Tienen que coincidir, más lo que se
rescató del teléfono.

---

## 6. Cómo se construye

**Dónde:** carpetas nuevas en el mismo repo, `apps/ios/` (proyecto Xcode, SwiftUI) y
`apps/android/` (Gradle, Kotlin + Jetpack Compose). `ios/` y `android/` de Capacitor **quedan
intactos**. Son el plan B y se pueden recompilar si la nativa tuviera un problema grave: en las
tiendas no hay vuelta atrás, se sube un build nuevo con versión más alta.

**iPhone (primero):**
- SwiftUI, Swift Concurrency.
- `supabase-swift` por SPM, para llamar a las RPC.
- Cola offline persistente (SQLite/SwiftData) con la misma semántica que el Outbox actual:
  error de red = reintentar, error del servidor = no reintentar a ciegas.
- Además:
  - HealthKit nativo.
  - APNs + `UNUserNotificationCenter`, con el registro por `mypump_registrar_push`.
  - PhotosUI y la cámara.
  - Universal Links para `app.mypumpteam.com/?t=`: hace falta el `apple-app-site-association`,
    que es un archivo nuevo en la web y lo **consultás conmigo** porque toca `public/`.
- Versión **2.0.0**, build ≥ 19.
- Firma: la receta vigente de Codemagic está en la memoria `reference_codemagic_firma_ios.md`.
- Workflow nuevo en `codemagic.yaml`, sin tocar los existentes hasta el cambio.

**Android (después):**
- Kotlin + Jetpack Compose.
- Health Connect y FCM: el mismo proyecto Firebase `mypump-663be`, que exige el mismo package.
- **En la MacBook no hay Java, ni Android SDK, ni Gradle.** Hay que instalarlos (pedímelo) o
  compilar en Codemagic.
- La prueba tiene que ser en un teléfono Android real.

**Orden de trabajo para iPhone.** Cada paso se prueba antes de seguir:
1. Acceso por token y migración del almacenamiento viejo (§5).
2. Entreno: semana, días (incluidos comodín), bloques, fotos, series y repeticiones.
3. Registrar series (offline), historial por ejercicio, sustitutos y variantes por serie.
4. Sesiones: iniciar, finalizar, cronómetro, descanso y comentarios.
5. Dieta: opciones, swaps anclados, comí/salté, consumo parcial, comidas libres, alimentos
   propios, foto del plato y etiqueta.
6. Mi Día, con hábitos y cardio.
7. Revisión: check-in y fotos por pose.
8. Progreso.
9. Chat con coach e IA.
10. Salud: HealthKit, wearables y motor de recuperación.
11. Notificaciones: push y locales.
12. Lo que exige Apple:
    - Respaldo científico pegado a cada número de la dieta. Por falta de eso rechazaron la app
      el 25-jul (guideline 1.4.1).
    - Borrado de cuenta.
    - Privacidad, `PrivacyInfo.xcprivacy` y los textos de permisos.
    - Un acceso de demostración para App Review.

**Diseño:** el pedido es "nivel muchísimo más profesional".
- Componentes nativos, SF Symbols, jerarquía clara, espacios generosos, transiciones del sistema
  y modo oscuro real.
- Mostrame **pantallas en el simulador** antes de cablear todo.
- Widgets, Live Activity del descanso y Apple Watch son extras para **después** del cambio, no
  bloquean.

**Lógica:** dos apps nativas más la web son tres implementaciones.
- Todo lo que sea regla de negocio y se pueda resolver en el servidor va al servidor, con RPC
  nuevas y aditivas.
- Lo que quede en el cliente se porta con sus casos de prueba. `npm test` corre 33 tests y checks;
  18 son de la lógica del cliente en JS (`scripts/test-*.mjs`, `scripts/check-*.mjs`) y cada uno
  encierra un bug real. Pasalos a XCTest y JUnit.
- Kotlin Multiplatform es opción si te convence, pero el default es lo que pidió Alan: dos apps
  separadas.

---

## 7. Cuándo se cambia la app vieja por la nueva

El cambio es en iPhone primero y en Android después. Se hace solo con todo esto cumplido:

1. **Lista de paridad al 100 %.** Cada pantalla, acción, estado vacío, error y comportamiento
   offline de la app actual tiene su equivalente probado. Si algo queda afuera, lo decido yo, por
   escrito.
2. **Lado a lado:** la misma cuenta de prueba muestra los mismos números en la web y en la
   nativa.
3. **Cero pérdida de datos**, con la prueba de §5 hecha.
4. **TestFlight** (y la prueba interna de Play) **al menos una semana** con Alan Fried
   (`mv7crheyk5ig`, tester, no es cliente), conmigo y con 3-5 clientes, sin regresiones.
5. **Lanzamiento escalonado** (phased release en App Store, rollout por porcentaje en Play).

**Siempre me preguntás antes de:**
- mandar a revisión de Apple o de Google;
- aceptar contratos;
- escribirle a un cliente;
- aplicar una migración en producción;
- tocar `public/`;
- instalar herramientas.

---

## 8. Cómo se trabaja

- **Base:** consultas y migraciones desde la mini (ver la memoria `reference_mini_aplicar_sql.md`).
  - `ssh mini '~/agentkit-coach/venv/bin/python3 ~/pump-centinela/_q.py'` no hace commit: sirve
    para leer y para ensayos.
  - `~/_aplicar.py <archivo>` hace COMMIT.
  - Una sentencia por llamada a `_q.py`.
- **Cuentas de prueba:**
  - `scripts/seed-cliente.mjs` fabrica clientes `test-*`, que el centinela, el Radar y la IA
    ignoran.
  - Para probar chat y coach hace falta una cuenta visible.
  - Nunca pruebes sobre clientes reales.
- **Simulador:** Xcode 26.6 e iOS 26.5 están instalados. Usá la herramienta del simulador y mostrame
  capturas.
- **Commits:** chicos, con mensaje claro, y **push después de cada cambio** (regla mía). Recordá que
  un push a `main` publica `public/` en la web.
- **Al final de cada sesión:** contame qué quedó hecho, qué falta de la lista de paridad y qué
  riesgos ves. Guardá en memoria lo que no se deduce del código.

---

## 9. Primera tarea

Antes de escribir una línea de Swift:

1. Armá `docs/NATIVA_CONTRATO.md`: las RPC que se usan de verdad, con parámetros, forma de la
   respuesta y cuándo se llaman. También los endpoints HTTP, la subida de fotos, los destinos de
   push y el formato exacto de cada tipo de la cola offline.
2. Armá `docs/NATIVA_PARIDAD.md`: la lista de paridad pantalla por pantalla, con los casos raros
   que encierran las memorias y los tests.
3. Probá en el simulador que el almacenamiento de la app vieja se puede leer desde una app nativa
   con el mismo bundle id. **Es el riesgo técnico número uno**: si no se puede, hay que sacar
   antes una actualización puente de la app actual, y eso sí toca código compartido con la web.
4. Mostrame el plan de pantallas (bocetos en el simulador) y una estimación por etapa.

Recién con mi OK arrancás la app.
