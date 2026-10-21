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

## Camino a las tiendas (Mati, 14-oct 23:50)

Mati: «seguí en autónomo hasta dejar ambas andando perfecto y publicadas en ambas tiendas».
- **Sin beta con clientes:** «si crees que no está para lanzamiento, seguí testeando vos muchísimo hasta asegurarte que
  esté para lanzamiento real». La prueba exhaustiva propia reemplaza a G5 y G6.
- **Sin teléfono Android físico:** «prefiero que busques la forma de simularlo desde la mac». Se prueba con una matriz
  de emuladores con los servicios de Google.
- **El envío a revisión** de Apple y de Google se le confirma igual, con un resumen concreto, en el momento de mandarlo
  (G7). Los permisos de las acciones irreversibles van uno por uno.

**iPhone 2.0.0**
1. ✅ La 1.0.12 publicada por Apple (15-oct 14:48). La 2.0.0 (build 116) se envió a revisión el 15-oct a las 21:56.
   Antes: El 15-oct a las 15:33 la App Store seguía con la 1.0.6. Se mira con
   `curl -s "https://itunes.apple.com/lookup?bundleId=com.pumpteam.mypump&country=ar"`.
2. ⏳ Prueba exhaustiva propia. Estado al 15-oct 05:45:
   - ✅ XCUITest en 26.5 (iPhone 17 Pro), 17.5, 18.6 y el iPad Pro 13". Barrido en el iPhone SE en claro, oscuro y con
     la letra más grande de accesibilidad: encontró y arregló Dieta, Ejercicio y Revisión (b9e3cb3).
   - ✅ Migración de punta a punta en 26.5 y 17.5: 27/27. Encontró una pérdida de swaps de comida (6fd391b) y la cola de
     fotos que quedaba (549fdba).
   - ✅ Sin red con `-sinRed`: el chat ya no parece vacío (a064dc0). Token revocado: LinkVencidoTests, «este link ya no
     sirve».
   - ✅ Avisos de punta a punta: tocar el aviso abre el Chat, en caliente y en frío. **Encontró que tocar un aviso cerraba
     la app** (9c9e8b0).
   - ✅ Revisión adversarial del código (14 y 15-oct, hallazgos 1-14).
   - ✅ Lado a lado con la web en las cinco pestañas, con `test-nativa-real` (`nativa-evidencia/lado-a-lado`):
     - 05:39: Dieta, Progreso, Revisión y Chat.
     - 10:21, Entreno: el OCR de las capturas da lo mismo que la web. Coinciden el 9/9, las 31 series, los 7387 kg, los
       bloques 2/2, 3/3 y 4/4, cada récord, «7 ejercicios cambian carga» y «Pasar a Semana 6».
     - La única diferencia es «Sesión completa» con «Cerrar sesión de hoy» en lugar de «Día cerrado». Es del estado de
       la cuenta: `UltimaVezUITests` reabre el día, y reabrir solo borra la marca del teléfono, como en la web
       (`restoreSesionDelDia`).
   - ☐ El iPhone de Mati con el **último TestFlight** (113 desde el 15-oct 17:49): el universal link desde WhatsApp (ACC-01/09), Salud de verdad
     (SAL-13) y tocar un push real.
3. ✅ TestFlight 104 a 110 y **111** (15-oct 13:27): los arreglos de la segunda revisión adversarial, entre ellos una
   pérdida de fotos. El 110 trajo el rendimiento de Progreso y el chat sin pedido doble; el 109, la cola de fotos que ya
   no las pierde y la accesibilidad de la auditoría. Antes, la suite completa de interfaz en 26.5 dio 20 de 20, con las 15 salteadas a propósito (barrido y
   auditoría), y el kit 436/436. Del 104 al 106 tienen el cierre al tocar un aviso.
4. ✅ Capturas nuevas (15-oct 11:45, `nativa-evidencia/tienda/20261015-114457`, con la app del TestFlight 110) y los
   textos de `NATIVA_TIENDAS_2.0.0.md`.
5. ⏳ G7: **OK de Mati el 15-oct** («Sí, apenas salga la 1.0.12»): la 2.0.0 con el último build (el 111 cuando dio el OK; ahora el que lleve lo que pidió esa tarde), escalonado de 7 días y
   publicación manual. App Store Connect pide iniciar sesión en Chrome (15-oct 15:35) y eso lo hace Mati: la sesión
   no pone contraseñas ni códigos.
6. ✅ Plan B escrito en `NATIVA_TIENDAS_2.0.0.md`: la Capacitor 2.0.1 por los workflows de siempre, sin subirla de
   antemano. La vuelta de la nativa a la Capacitor está probada en el simulador.

**Android 2.0.0**
1. ✅ Todas las pantallas (f4bf5ce, 15-oct 03:00): no queda ninguna «en construcción».
2. ⏳ Paridad de Android: queda 1 en 🟡, ACC-01, que espera una instalación firmada por Play. DIE-14/15 se cerraron
   con la visión real (106a793). GEN-05, GEN-07 y GEN-08 ya tienen su prueba, que muerde (agente, 15-oct, mergeado en
   `nativa`).
3. ✅ Matriz de emuladores con Google Play (15-oct, 8733a3c): las 186 instrumentadas con 0 fallas en Android 9, 11, 13,
   14 y 16. La migración da 31/31 en 13 y 28/31 en 9: los 3 que fallan son de la Capacitor, que no arranca con WebView 66.
   Pendientes de la lista original:
   - ~~la migración desde la Capacitor 1.0.12~~ ✅ ya cubierta: `emu-migracion.sh` compila la Capacitor desde `main`, y
     entre `a1.0.12-b18` (la de Play, 22-sep) y `main` no cambió `android/` ni el almacenamiento. Solo cambiaron el
     texto de `privacidad.html` y, el 15-oct, el arreglo de las fotos de la web (0620012), posterior a esas corridas;
   - ~~un push real de punta a punta con `push.py` y la cuenta de prueba~~ ✅ 15-oct, con OK de Mati
     (`scripts/nativa/push-android.py`): llegó en 263 s por el canal `mypump_mensajes`, y tocarlo abre el Chat;
   - Health Connect, que viene integrado desde Android 14 y es una app aparte de 9 a 13;
   - tamaños de pantalla, modo oscuro y fuente grande.
4. ✅ Workflow `android-nativa`: **`nand-2.0.0-103`** (15-oct 13:34, 0bec33b, con los arreglos de la segunda revisión
   adversarial) y antes el 102 salieron enteros en Codemagic. Pasan las pruebas en
   la JVM, el AAB y el APK firmados con `mypump-upload`, las APIs de `:core` contra el minSdk, la versión, la firma, los
   permisos y los 16 KB. El 101 falló en el chequeo de APIs, que corría por primera vez allá: el script dependía del
   Java de Homebrew y de versiones enteras del SDK.
5. ✅ Play (15-oct, con la sesión de Mati en Chrome):
   - el AAB 103 en la versión de producción, con las novedades;
   - Data safety con «Información de la app y rendimiento → Diagnóstico» (el recibo de la migración). Mensajes y el ID
     del dispositivo ya estaban;
   - la declaración de Health Connect: el renglón viejo de saturación de oxígeno ahora dice que la app ya no usa el
     permiso. Google la había rechazado por él el 26-ago y se sacó en la 1.0.7;
   - las capturas: 8 de teléfono y 8 de tablet de 7" y de 10", 5 en claro y 3 en oscuro.
6. ⏳ G7: **enviado a revisión el 15-oct a las 15:31** con OK de Mati («Play: AAB 103 al 10%»), en 6 cambios. La
   publicación administrada está apagada, así que sale sola al aprobarse, al 10 %. Después, 50 % y 100 % mirando los
   recibos de la migración (`scripts/nativa/beta_diario.py`).

**2.0.1 de las dos (para el miércoles 21-oct, Mati: «hacelo el miércoles cuando tengamos más tokens y seguro sea con
más correcciones»)**
- Lleva: la hoja única de Salud (lo de Alan Fried), el descanso a la vista (Live Activity en iOS, cuenta regresiva
  fija en Android, ver D23), los ajustes de porciones (D22), el botón de foto con cámara y galería en un toque (Alan
  Ferraro) y los otros ejercicios del mismo músculo al sustituir (D24, Eric Walo).
- iOS: el **TestFlight 118** (20-oct 21:05, con el OK de Mati) ya lleva todo: D22, D23, D24, la foto y la hoja de
  Salud. Codemagic lo hizo en 4 min. La extensión usó su perfil («MyPump Descanso App Store» para `DescansoWidget`)
  y el IPA salió revisado con la extensión 2.0.1 (118). App Store Connect lo da «Lista para enviar» en el grupo
  interno Equipo Pump. Si hay correcciones el miércoles, va el 119. El push de un tag `nios-*` lo frena el
  clasificador: hace falta el OK de Mati en el momento.
- Android: AAB `nand-2.0.1-104`. Play está al 10 % con la 2.0.0; el 50 % y el 100 %, con el OK de Mati.
- El envío a las dos revisiones, con el OK de Mati (G7).

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
| Android: lector del almacenamiento viejo con WebView y arranque de la migración en `:app`, prueba en el emulador, D7 | ✅ mergeado el 14-oct (4e48457): leveldb encontrado sin rutas fijas, **24/24 de punta a punta en el emulador** (`scripts/nativa/emu-migracion.sh`), D7 en el modelo y la cola (D7 se sacó el 14-oct, f6977e9); 400 tests JVM + 9 instrumentados. Backup decidido (D14). Falta: un teléfono real con la 1.0.12 de Play |
| Android: pantallas en Compose | 🟡 acceso, demo, sin conexión, Dieta en lectura y Mis datos (375f970); fuentes y legales en una Custom Tab (0c745f7); Entreno (a17929a); sin permiso de IA y el aviso del domingo como mensaje de Mati, gemelo de iOS (f6977e9). JVM 434 (1 salteada) y 59 instrumentadas. Faltan Chat, Revisión, Dieta con escritura y Progreso |
| Android: notificaciones (FCM), hoja de la primera vez, D8 y Salud (Health Connect) | ✅ mergeados el 14-oct (b40b3fe y fd974ba): push de Mati por FCM con el proyecto de la Capacitor, el domingo con `setWindow`, la limpieza de las alarmas de la Capacitor (probada con una actualización real desde la 1.0.12), D8 inexacto; Health Connect con los permisos de solo lectura y el banco contra el bridge con 0 diferencias. JVM 466 + 24 de `:app`; 103 instrumentadas (2 a mano). Falta un teléfono real: push de punta a punta, marcas, Android 9-13 con Health Connect aparte, relojes |


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
| G2 · migraciones de esquema | ✅ **`nativa_001` y `nativa_002` aplicadas** (14-oct, OK de Mati; las corrió él). Verificado por la API pública. Auditoría de seguridad sin agujeros: `mypump_get_app_config` es pública a propósito. Esquema regenerado. **`nativa_003` (sustituciones de ejercicio, SER-14) aplicada por Mati el 14-oct a las 18:16**: API pública, esquema (solo agregados) y auditoría sin agujeros, y una sustitución pasa entre dos teléfonos contra producción. **`nativa_004` (los ajustes de porciones, D22) aplicada el 20-oct con el OK de Mati** («Sí, aplicala»), después del ensayo en rollback (37 chequeos). Verificado:
- por la API pública con `test-nativa-real`: leer, guardar, volver al plan (la fila queda con `{}`) y un token inventado da null;
- el esquema regenerado solo agrega (2 funciones, la tabla y su RLS);
- `auditar_seguridad_db.py`: ningún agujero. Pendiente para otra tanda: `mypump_borrar_serie` |
| G4 · descargas | Android: `androidx.browser`, `ui-test-junit4`/`ui-test-manifest` (14-oct) y **Firebase Messaging 25.0.1 + plugin google-services 4.4.4 + Health Connect `connect-client` 1.1.0** («dale», 14-oct 21:10). Son las versiones que ya compila la Capacitor y están en la caché de Gradle. El `google-services.json` es el de `android/app` (ya público, proyecto mypump-663be) |
| G5 · TestFlight externo | **no va** (Mati, 14-oct 23:50): sin beta con clientes, la reemplaza la prueba exhaustiva propia. Los internos están autorizados |
| G6 · mensajes a clientes | no hace falta para el lanzamiento (sin beta) |
| G7 · revisión de tiendas | **Play: enviado el 15-oct a las 15:31** (OK de Mati, AAB 103 al 10 %). **App Store: OK de Mati** para mandar la 2.0.0 apenas salga la 1.0.12; falta que él inicie sesión en App Store Connect |

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
| D16 | **La barra de pestañas no se achica ni se esconde nunca** (Mati, 15-oct: «empeora muchísimo el uso»). iOS sin `tabBarMinimizeBehavior`; Android, la cápsula fija | Se usa durante el entrenamiento, con el teléfono en la mano |
| D17 | **Sin Mi día en Revisión** (Mati, 15-oct: «nadie las usa»): fuera la racha, el entrenamiento del día, los hábitos, el agua y los últimos 30 días. Quedan la recuperación y la salud, con el ancla de Mi día | El modelo y la base no cambian: la web las sigue teniendo |
| D18 | **El peso va en el check** («Tu peso de hoy», opcional, sale con «Enviar mi check») y la tarjeta de peso sigue para cualquier otro día (Mati, 15-oct) | Misma cola (`peso`) que la tarjeta |
| D19 | **El ejercicio se abre en la lista de Entreno**, como la card de la web (Mati, 15-oct: «antes era más práctico»). La página del ejercicio queda para la técnica, el video y los comentarios | El motor ya tenía `expandido`; al completar, abre el siguiente |
| D20 | **«Ver cómo está mi cuerpo»**: la entrada al detalle de salud es un botón a la vista, no un renglón verde (Mati, 15-oct) | Nadie tocaba «Ver todos mis datos» |
| D21 | **La marca de Pump Team** (Mati, 15-oct: «estos son los colores de mi logo»): el verde del logo (#1D9330; #5BBE62 en oscuro) con blanco encima, el dorado claro (#FACB39) solo en los récords, el nombre **Pump Team** debajo del ícono y en los textos, el torso del ícono como logo en la bienvenida y en el chat (en lugar de la «M»), y «Mati» arriba del chat en vez de «tu coach». El ícono pasa del esmeralda al verde del logo | El paquete, el bundle id, las cuentas y los datos no cambian. En las tiendas el nombre cambia con el envío de cada versión (G7). La web sigue con MyPump y la lima hasta que Mati diga |
| D22 | **Ajustar una comida de hoy** (feedback del 20-oct que Mati pidió implementar: sumar o restar kcal y que se recalculen las porciones, compensar en la siguiente; Emilio García Álvarez: sacar el pre-entreno el día que no entrena y «jugar con los gramos»). De a 50 kcal sobre lo que se puede escalar, entre un cuarto y el triple, en porciones servibles; cantidades a mano por alimento, ancladas al alimento; «Hoy no la como»; compensar prendido de entrada; lo que una comida no absorbe sigue a la otra. Vale solo por hoy. Una fila por día en `mypump_ajustes_dieta` (nativa_004); volver al plan guarda `{}` y no borra | La regla es la misma en las dos apps (21 vectores compartidos). La web y el Cerebro no la usan: **para que Mati lo vea hace falta que el Cerebro o el brief lean la tabla**, que es de otra sesión; por eso la hoja no promete «Mati ve estos ajustes» |
| D23 | **El descanso entre series a la vista** (Ian Actis, 20-oct): grande en el ejercicio y traído a la vista al confirmar la serie; con la app atrás, una Live Activity en iOS (pantalla bloqueada y Dynamic Island) y una cuenta regresiva fija sin sonido en Android (canal de prioridad normal: con la baja no se ve bloqueado en los Pixel). La última serie del día y cerrar el día lo cortan | La extensión `com.pumpteam.mypump.descanso` necesita su propio perfil App Store; la versión y el build van a nivel proyecto para que siempre coincidan con los de la app |
| D24 | **Al sustituir, también otros ejercicios del mismo músculo** (Eric Walo, 20-oct: con la polea ocupada, a «Extensión en polea alta con barra» le salía una sola variante y quería fondos; Mati eligió «Siempre»). Debajo de las variantes del mismo movimiento (las de la web, sin cambios), la sección «Otros ejercicios de [músculo]»: mismo `primary_muscle`, otro patrón cuyo músculo dominante (el de la mayoría de sus filas) es ese, otro equipo primero, alfabético, 30, sin repetir lo de arriba ni nombres sin traducir. Nada en calentamiento, cardio ni sin patrón. El subtítulo dice «Otra variante u otro ejercicio de tríceps» cuando hay | Es de la app: la web sigue con el mismo movimiento. El sustituto se guarda como cualquier otro (la misma tabla y el historial por clave). El filtro del músculo dominante saca las filas mal cargadas (los encogimientos figuran como espalda media). La patada de tríceps se llama «Patada de tríceps»: la web la llama «Patada de glúteo» y es un desvío documentado en los vectores |
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
  progresiva en 7 días. Ojo: la versión que estaba en la App Store era la **1.0.6**; la 1.0.11 nunca salió. El 15-oct
  a las 04:00 seguía la 1.0.6.
- **Los OK del 15-oct, todos hechos** (Mati: «todo eso podés hacerlo vos», y uno por uno en la pregunta):
  1. ✅ **mini-vision:** `model = "gpt-5.6-sol"` en `~/.codex/config.toml` de la Mini (backup
     `config.toml.bak-20261015-nativa`). Volvió a andar.
  2. ✅ **Push real de Android:** ver «Android 2.0.0», punto 3.
  3. ✅ **El servicio de fotos** (`mini-vision/server.mjs`): el tope del día suma la foto recién cuando se guardó bien.
     En `main` (0620012) y en la Mini (backup `server.mjs.bak_20261015_topeFotos`).
  4. ✅ **La web ya no pierde fotos con la Mini caída** (`_flushFotosPasada`, `public/cliente.html`): un 5xx no gasta
     intentos y corta la pasada. En `main` (0620012), publicado por Cloudflare Pages.
  - Queda en la web, sin arreglar: la misma carrera de la foto de una pose que se vuelve a sacar mientras sube la vieja,
    que en la nativa arregla `FotosMismaPose`.
- **En su iPhone, con el último TestFlight (113 desde el 15-oct 17:49):** ACC-01/09 (el link de WhatsApp y el universal
  link) y SAL-13 (Salud real).
- **Para el envío a Apple (G7):** iniciar sesión en App Store Connect en Chrome. Con eso, la sesión arma la 2.0.0 (el último
  build, capturas, notas y «Other Diagnostic Data») y la manda con el escalonado de 7 días.
- **Para la 2.0.1 (20-oct):**
  1. ~~El OK para aplicar `nativa_004` (G2)~~: aplicada el 20-oct.
  2. ~~El perfil de la extensión del descanso~~: hecho el 20-oct en el Chrome de Mati, con su sesión («Vos en mi
     Chrome»):
     - el App ID «MyPump Descanso» (`com.pumpteam.mypump.descanso`), sin capacidades;
     - el perfil «MyPump Descanso App Store», con el único certificado de distribución (PUMP TEAM LLC), que vence el
       2027-08-05 como el de la app;
     - en Codemagic, `mypump-descanso-appstore-profile`.
     El `ios_signing` por `bundle_identifier` toma también `com.pumpteam.mypump.*` (docs de Codemagic), así que el
     YAML no cambia.
  3. ~~Cómo quiere ver los ajustes~~: en el brief de revisión y en la ficha del Cerebro (20-oct). Los parches los armó
     la sesión Pump Cerebro (mini) y los aplicó esta sesión con el OK de Mati («hacé ambos vos»):
     - la ficha, en el Cerebro (4f312b0, publicado);
     - el brief, en la Mini (`agent/brief_v3.py` y `prompt_revision_v3.md`). Quedan sin commitear como estaban, con
       backups `.bak-ajustes-20261020`. El brief nocturno ya lo toma; el a pedido, en el próximo reinicio del bot.
  4. El OK de los envíos del miércoles y del 50 % → 100 % de Play.

## Bitácora

- **19/20-oct, lo que pidieron los clientes, con auditoría** (Mati: «arrancá hoy y dejalo todo listo… testeado y
  funcionando»; después, en esfuerzo máximo: «revisá lo que se fue haciendo en forma de auditoría, mejoralo y seguí»).
  - **IA:** Codex sin créditos hasta el 24-oct. La visión y el chat de la Mini usan Claude CLI con el plan Max hasta
    el 25-oct a las 00:00 y después vuelven solos a Codex (940ddea). La auditoría encontró que la visión le dejaba a
    Claude leer archivos (`--allowedTools Read`): ahora va sin ninguna herramienta, con la foto adentro del mensaje
    (371fa11). Se revisó y nadie lo aprovechó. El mismo problema en el Pump Bot es código de otra sesión: quedó
    anotado como tarea aparte.
  - **Descanso (D23):** Live Activity, tarjeta grande y cuenta regresiva fija en Android (761be72, f3ecc6b, 31ea3de).
    La auditoría agregó el canal de prioridad normal en Android, el corte al terminar el día y la cola de la Live
    Activity. Tests: kit, JVM (los dos nuevos fallan sin el arreglo) y 18/18 instrumentadas de avisos.
  - **Fotos (Alan Ferraro):** cámara y galería con un toque en iOS (a23c833, eddda3e). Android ya lo hacía.
  - **Ajustes de porciones (D22):** iOS (7606a3e…6bf0bc6) y Android (d1a3614…68805c5). La auditoría cambió la regla
    antes de portarla:
    - lo que el tope no deja absorber se perdía: ahora sigue a la otra comida;
    - las cantidades a mano iban por posición y la dieta se republica con el mismo id (013): ahora van ancladas al
      alimento y a la unidad;
    - volver al plan borraba la fila y otro teléfono la resucitaba: ahora guarda `{}`;
    - si los reemplazos no llegaban, no se hidrataban los ajustes (da38ed9);
    - la hoja suma las macros (lo que pidió Emilio), el total del día y qué le pasa a cada comida siguiente;
    - el texto «Mati ve estos ajustes» todavía no era cierto y se cambió por «Vale solo por hoy»;
    - «pasan a el» → «pasan al».
  - **Pruebas:** kit 486/486, JVM de Android 607 (1 salteado), XCUITest de Dieta 6/6 y 23/23 instrumentadas de Dieta.
    Capturas en `nativa-evidencia/dieta/ajustes-2010` y `nativa-evidencia/android-ui/ajustes-2010`.
  - **Codemagic:** el workflow de iOS frena si falta el perfil de la extensión y revisa la extensión en el IPA.
  - **Revisión independiente** (un agente sobre todo el diff del día): 7 hallazgos, todos arreglados con su test en las
    dos apps (1600123…c2cef0b):
    - un ajuste hecho mientras se leían los del servidor se perdía y el siguiente lo borraba también del servidor (lo
      reprodujo en las dos);
    - en la demo, que es la que miran las revisiones de Apple y Google, la última serie y cerrar el día no cortaban el
      descanso;
    - las kcal sumadas no se acotaban a lo que la comida absorbe;
    - la hoja arrancaba con cantidades que ya no valían;
    - el redondeo achicaba un alimento al sumar;
    - las opciones vistas pasaban de una cuenta a la demo;
    - faltaban topes al leer.
    Queda como nota: si el descanso termina con la app atrás y no se vuelve a abrir, la Live Activity puede quedar
    hasta que la saca el sistema (8 h). Sacarla sola necesitaría pushes de ActivityKit.
  - **Al final:** kit 493/493; JVM de Android completa. En interfaz: la suite entera de iOS (con la app reinstalada,
    Onboarding 3/3), 35/35 instrumentadas de Dieta y Entreno, y las de ajustes también en oscuro y con la letra más
    grande.
  - **Otros del mismo músculo (D24, Eric Walo por Mati: «te doy feedback»).** La regla en las dos apps, con la misma
    salida. Los vectores (`otros_mismo_musculo.json`) tienen 8 listas a la vista y la huella de las 406 listas del
    catálogo, que Android compara una por una. Al cortar el tope en 29 solo falla la de las huellas.
    - La primera prueba en la demo mostró «Encogimientos» para el remo, porque el catálogo los carga como espalda media:
      ahora el patrón tiene que ser de ese músculo.
    - También mostró «Patada de glúteo con mancuernas» entre los de tríceps: la regla de la web confunde las dos
      patadas.
    - Pruebas: kit 498/498, JVM de Android 666 (1 salteado), EntrenoUITests 5/5 y EntrenoUiTest 12/12, con capturas en
      `nativa-evidencia/entreno/otros-musculo-2010b` y `android-ui/otros-2010`.
    - Si el kit se cae con la señal 11 en `ModeloEntreno.init`, son objetos de prueba viejos (SwiftPM no los recompiló
      cuando cambió `CatalogoEjercicios`): `touch` a los tests y otra vez.

- **17-oct, la 2.0.0 publicada en el App Store y la 2.0.1 (117) por lo de Alan.** Apple la aprobó y salió sola a las
  04:52, como **Pump Team**, escalonada en 7 días (la espera sin tokens la vio a las 16:58).
  - Alan Fried, con la 2.0.0 de la tienda: en «Conectá tu salud» tocó «No permitir» y el botón quedó cargando. Se
    reprodujo en el simulador (testSaludNoPermitirSigueEnseguida, nueva): los permisos iban en dos hojas seguidas
    (el núcleo y el resto, como la web) y, después de «No permitir», la segunda no aparecía. El onboarding esperaba
    el corte de 20 s (18 s medidos).
  - Arreglo (8a1bd6c): una sola hoja con todo; las dos tandas quedan para cuando la hoja entera falla. Los vectores
    de la web aceptan la hoja única como sus dos tandas (desvío a propósito). Y BotonMarca con `ocupado`: mientras
    trabaja queda verde, porque en gris la ruedita no se veía (también en Entrar, Cerrar el día y Conectar Salud).
  - Kit 448/448, XCUITest de Onboarding 3/3. TestFlight 117 (2.0.1). El envío a revisión, con el OK de Mati (G7).

- **15-oct 21:35-21:57, la 2.0.0 enviada a revisión de Apple** (Mati: «Sí, mandala» y, con la pantalla a la vista,
  «Sí, enviala»). Apple publicó la 1.0.12 a las 14:48 (la tienda de Argentina la mostró a las 21:34; sigue su
  escalonado). En App Store Connect, con la sesión que abrió Mati:
  - versión 2.0.0 con el **build 116**, nombre **Pump Team**, la descripción y las palabras clave de
    `NATIVA_TIENDAS_2.0.0.md` (con el bloque «Respaldo y aviso» de la 1.0.x, que no estaba en el borrador), las
    novedades y las notas para el revisor (con «not a medical device» y el contacto de la 1.0.12);
  - capturas nuevas, 8 por tamaño: iPhone 6,3" (el obligatorio de 2026, del iPhone 17 Pro, `6-3-*`), 6,9" y iPad
    13"; se sacaron de esta versión las 4 viejas de 6,5" y las 4 del iPad (las de la Capacitor, con Mi día);
  - privacidad publicada con «Otros datos de diagnóstico» (funcionalidad, vinculados, sin seguimiento);
  - sale sola al aprobarse, escalonada en 7 días, y mantiene las valoraciones.
  - **Mientras la 2.0.0 esté en revisión, nadie tagea `v*`:** el flujo de la Capacitor cancelaría el envío.

- **15-oct 20:50-21:45, la marca de Pump Team** (Mati: «ya no se respetan los colores de la marca», «donde dice tu
  coach tiene que ser Mati», el nombre Pump Team y el logo en el chat; con las capturas a la vista, «dejá todo así por
  ahora, con el del torso está bien»):
  - D21 en las dos apps (fdd3126): el verde del logo, el dorado en los récords, Pump Team debajo del ícono y en los
    textos, el torso en la bienvenida y en el chat, «Mati» arriba del chat y el ícono en el verde del logo. Ver
    `nativa-evidencia/pump-team-capturas-15oct.png`.
  - Pruebas: XCUITest 10/10 (Acceso, Chat, Onboarding y Avisos, 26.5) y 60/60 instrumentadas (Acceso, Chat,
    Onboarding, Avisos, Tema, Progreso y sus capturas).
  - Las tiendas (`NATIVA_TIENDAS_2.0.0.md`): las novedades y las notas del revisor con el nombre nuevo y sin «hábitos»
    (se fueron con D17); el nombre Pump Team va con la 2.0.0 en App Store Connect y con la 2.0.1 en Play, con el ícono
    de 512 px (`nativa-evidencia/tienda-android/icono-512-pump-team.png`). Las capturas del App Store, de nuevo con
    la marca (`nativa-evidencia/tienda/20261015-pump-team`); las de Play, con la 2.0.1.
  - TestFlight 116. La web sigue con MyPump y la lima: no se toca sin Mati.

- **15-oct 19:50-20:45, Android con la letra y los íconos del iPhone** (Mati: «la de android se sigue viendo horrible y
  la de iphone es mejorable», y el OK para bajar la letra y los íconos):
  - Lado a lado a la misma escala (3 px por pt/dp), los textos medían igual: lo que lo hacía ver de otra familia eran
    **la letra** (Roboto contra SF Pro) y **los íconos** (los de Material, rellenos y gruesos). Ahora van **Inter** (OFL)
    y **Material Symbols Rounded** (Apache 2.0, peso 500); Revisión y Progreso dibujados como los de iOS. Ver
    `nativa-evidencia/android-vs-iphone-15oct.png`.
  - La cabecera de Dieta, igual en todos los teléfonos: el anillo arriba y tres cajas (lado a lado salía en los anchos:
    el Pro Max y el Android de prueba, de 448 dp). La semana de Revisión, pegada al título grande; «Mis datos» en el
    círculo de vidrio; Progreso vacío centrado; la figura estirando en el calentamiento.
  - **En las dos apps:** al abrir un ejercicio en la lista (o el siguiente al completar uno), la lista lo trae a la
    vista, contando la barra de pestañas de Android (f1eb980, 6f17cf1). TestFlight 115.

- **15-oct 17:15-19:45, lo que pidió Mati para su video, y Android al nivel del iPhone.**
  - **iPhone, TF 112 y 113 (17:49):** la barra de pestañas fija (D16), sin Mi día (D17), el peso en el check (D18), el
    ejercicio abierto en la lista (D19) y «Ver cómo está mi cuerpo» (D20). Lo mismo en Android, para la 2.0.1 (104).
  - **Android con los controles de iOS 26**, copiados del simulador:
    - los diálogos (`Alerta`): tarjeta muy redondeada, título y mensaje a la izquierda, botones en cápsulas grises;
    - las hojas (`FormaHoja`, `AsaHoja`, `EncabezadoHoja`): «Cancelar» a la izquierda, el título al centro y la acción
      a la derecha;
    - la hora de la comida libre con la rueda de iOS (`RuedaHora`), no el reloj de agujas;
    - el aviso de guardado como la pastilla de iOS, y los menús con las puntas redondeadas.
  - **En las dos apps:** la flecha de la fila gira al abrir el ejercicio, «Series» va más chico en la lista, y
    «Sustituir» y «Técnica y notas» van en un renglón (los apilados ocupaban casi el doble).
  - **iPhone, un arreglo:** «¿Volver al alimento del plan?» salía como un globo arriba de todo, tapando el aviso de la
    demo y apuntando al gráfico de calorías. Pasaba porque estaba colgada de toda la pantalla; ahora cuelga de la fila.
    Lo mismo con «¿Quitar Oura?».
  - **Con la letra más grande de accesibilidad** (barrido nuevo, `testEjercicioEnLaLista`): «Sustituir» y «Técnica y
    notas» partían las palabras en un renglón y ahora van uno debajo del otro (las dos apps). En iPhone, el resumen de la
    sesión partía «HE-CHOS» y la tabla «REP-S».
  - **TestFlight 114** (caa40ba) con todo lo del iPhone de esta tarde.
  - **Android, suite entera:** 198 pruebas; las 3 que fallaron esperaban a Mi día y pasan arregladas (24/24 en la corrida
    final). Commit del diseño nuevo de Android para la 2.0.1.
  - **19:10, Mati:** «ya gastamos una fortuna de tokens y todavía no está listo?». La 2.0.0 de iPhone está lista (114);
    la frena la 1.0.12, todavía en revisión, y el login de App Store Connect, que es suyo. Eligió **esperar la 1.0.12**
    (no retirarla). **Se terminó el pulido:** no se agregan cambios salvo que él los pida. Se borraron los cron de cada
    hora y de cada 3 h (gastaban tokens en cada vuelta); queda un `until` de shell que mira la App Store cada 5 min sin
    gastar nada y avisa cuando sale la 1.0.12. Ahí: avisarle a Mati que entre a App Store Connect y mandar la 2.0.0 con
    el 114 (o el último).
  - **Android, una carrera en la dieta:** volver al alimento del plan mientras se traía la dieta lo resucitaba. Era el
    `DietaEscrituraUiTest` que fallaba 2 de cada 3; lo reproduce `volverAlPlanMientrasHidrataNoLoResucita` (2d7adb9).
  - **Pruebas:** las 16 de Android que dependían de Mi día o de la página del ejercicio, adaptadas (9b2a296).
  - **Datos falsos de reloj** en la cuenta de Mati (17:35), a pedido suyo, para ver la recuperación en su iPhone. Se
    borran cuando avise (memoria `salud-falsa-cuenta-mati`).

- **15-oct 17:00, Android con el diseño del iPhone** (Mati: «porque es tanto peor el diseño en android que en ios? no me
  gusta nada», y eligió «Igual que el iPhone»). Puesto lado a lado y a la misma escala (1 pt = 1 dp), lo que lo hacía
  ver peor era:
  1. **La letra de la marca sin peso.** Archivo es variable (100-900, 600 por defecto) y `Font(resId, peso)` la arma con
     los ajustes de variación vacíos: todos los títulos y números salían en 600. Ahora el eje va explícito
     (`ArchivoPesoTest`, que dibuja el texto en 500 y 900 y cuenta la tinta: con el código de antes daba igual).
  2. **La barra de pestañas de Google**, opaca, alta y de punta a punta. Ahora es la cápsula flotante de iOS 26
     (`BarraPestanas` + `Modifier.vidrio`), con la pestaña elegida en una píldora y el contenido pasando por debajo:
     `LocalRellenoInferior` lleva lo que tapa la barra al final del desplazamiento de cada pantalla (`MarcoPantalla`).
     El compositor del chat queda arriba de la barra, y con el teclado abierto, arriba del teclado.
  3. **Los controles de Material:** el segmentado (`Segmentado`, como el de iOS: riel gris y píldora blanca), el
     interruptor (`Interruptor`, el de iOS) y la flecha de volver (`BotonVolver`, el círculo de vidrio de iOS 26).
  4. **Los títulos grandes** en la letra del sistema en negrita, 34, como el título grande de iOS.
  5. **Los cuadros de las fotos**, macizos y grises: `campo.copy(alpha = 0.5f)` reemplazaba el 12 % del color por un
     50 %, cuando `opacity(0.5)` de iOS lo multiplica.

  La pantalla de Ejercicio ya tenía la estructura del iPhone: la captura de la tienda mostraba otro momento. La isla del
  descanso usa el mismo vidrio y los mismos márgenes que la barra.

- **15-oct 16:00, Android: una foto que se perdía si el sistema cerraba la app con la cámara abierta.** Las pruebas
  instrumentadas usan una cámara de mentira que contesta al instante, así que no lo veían. Con la cámara de verdad del
  emulador y `am kill` (lo que hace Android con poca memoria), MyPump volvía en un proceso nuevo pero en Entreno, y la
  foto quedaba huérfana en `cache/camara`.
  - **Causa:** la clave del `Crossfade` de la raíz es `Escena(destino, de)`, un data class con un enum. Compose arma con
    su `hashCode` la clave de todo el estado guardado (la pestaña, lo abierto, la clave del lanzador de la cámara), y el
    `hashCode` de un enum es el de identidad: cambia en cada proceso. Se perdía todo lo guardado, también el resultado de
    la galería y de la hoja de Health Connect.
  - **Arreglo:** `Escena.hashCode` con el nombre del destino (`EscenaTest`, que falla con el de antes).
    `scripts/nativa/camara-muerte-android.py` lo prueba de punta a punta: con el arreglo vuelve en Revisión con «Listo,
    guardada ✓». Las demás claves animadas ya eran estables.
  - No es una regresión: la Capacitor también pierde la foto (el selector de archivos del WebView no sobrevive al
    proceso). La 103 que está en revisión lo tiene; el arreglo va en la **2.0.1 (104)**, con la versión corta nueva para
    que la palanca remota pueda pedirla.

- **15-oct 15:31, Android enviado a revisión de Google.** Con los OK de Mati del 15-oct («Play: AAB 103 al 10%,
  Mini: vision y tope fotos, Base: push real Android, Web: fotos a main»):
  - **Play Console:** el AAB 103 (2.0.0) en producción al 10 % con sus novedades, Data safety con Diagnóstico, la
    declaración de Health Connect y 24 capturas nuevas (`tienda-android/20261015-053511`). Fueron 6 cambios, enviados
    juntos. La publicación administrada está apagada: al aprobarse sale sola al 10 %.
    - El AAB pesa más de los 10 MB que acepta la extensión de Chrome por archivo. Se subió en trozos, se rearmó en la
      página y se verificó con SHA-256 antes de dárselo a Play. Un servidor local no sirve: Chrome bloquea que una
      página pública le pida algo a la red local.
    - En la declaración de Health Connect quedaba un renglón de `READ_OXYGEN_SATURATION`, el permiso por el que Google
      rechazó la app el 26-ago. Ya no está en el paso 1 (la app pide 14), pero el formulario conserva el renglón y no se
      puede borrar. Su texto ahora dice que la app ya no lo usa.
    - Avisos de Play para más adelante: optimizar el código DEX antes de febrero de 2027 (prender R8), y faltan el
      archivo de desofuscación y los símbolos nativos.
  - **mini-vision** volvió con `gpt-5.6-sol`. Las respuestas reales a un plato y a una tabla nutricional quedaron en
    `VisionRealTests`/`VisionRealTest` (DIE-14/15 ✅).
  - **El tope de fotos del servidor** cuenta solo lo que se guardó, y **la web** ya no borra fotos por un 5xx (0620012,
    en `main` con OK de Mati; mergeado en `nativa` en e7617a9).
  - **El push real de Android** llegó en 263 s por `mypump_mensajes`, y tocarlo abre el Chat (NOT-01/03 ✅).
  - **App Store:** la 1.0.12 sigue en revisión (la tienda muestra la 1.0.6 a las 15:33). App Store Connect pide iniciar
    sesión: Mati.

- **15-oct 13:10, la segunda revisión adversarial** (lo que cambió desde el TestFlight 108). Encontró 4 problemas, cada
  uno con una prueba que falla sin el arreglo (verificado con mutaciones en las dos plataformas):
  1. **Fotos, pérdida de datos (ya pasaba antes):** si el cliente volvía a sacar la foto de una pose mientras la cola
     subía la vieja, la pasada se llevaba la nueva, o la vieja terminaba después y quedaba en el bucket. En Android es
     fácil, porque la cámara es otra app y al volver se drena. Ahora la cola solo saca la foto que mandó, y `subir`
     espera a la subida vieja de la misma pose (`FotosMismaPose`).
  2. **Android, `ImagenRemota` no recargaba al cambiar la URL** (ya pasaba antes): `produceState` conservaba la imagen
     anterior. Quedaban viejas la miniatura de una foto reemplazada, las de Entreno al cambiar de día y la de un
     ejercicio sustituido. `estadoImagenRemota` arranca desde la URL nueva (`EstadoImagenRemotaTest`, y la instrumentada
     de reemplazar la foto ahora baja una imagen de verdad: con `null` pasaba igual).
  3. **Progreso, dos cargas que se pisaban** (regresión de hoy): las tarjetas de una con el historial de la otra.
     Contador de cargas (`ProgresoDosCargas`).
  4. **El tope del día con el storage caído:** probar todas las fotos en cada pasada gastaba los 12 en 6 aperturas.
     El 5xx vuelve a cortar, y la que falló queda para el final (`FotosTope`). La causa de fondo está en el servidor:
     queda como OK pendiente 3.

  Lo que la revisión dio por bien:
  - los formateadores, iguales en 3.028 cadenas y con 16 hilos;
  - el chat sin pedido doble, que no deja el chat sin traer;
  - el agua, que queda siempre entre 0 y 12;
  - `FilaFluida` y los colores;
  - el `ContentObserver` de movimiento reducido.

  Además, la migración de punta a punta en iOS 26.5 con todo lo de hoy dio 27/27, y en Android 9 pasaron Revisión,
  Progreso y Chat (37/37).

  **Validación final de los builds 111 (iOS) y 103 (Android), 15-oct 14:30:**
  - iOS:
    - kit 445/445;
    - interfaz en iPhone 17 Pro 26.5: 20/20;
    - interfaz en iOS 17.5: 20/20;
    - interfaz en iPad Pro 13": 21/21 (las 15 salteadas son el barrido y la auditoría);
    - migración 27/27.
  - Android:
    - JVM 622/622;
    - la suite instrumentada completa en nativa36: 193, con 0 fallas y las 5 salteadas de siempre.

- **15-oct 11:40, rendimiento, el chat y lo último de paridad de Android:**
  - **Progreso tardaba 1,5 s en el hilo principal** con el historial más largo que deja el servidor (48 filas por
    ejercicio, 2.880 en total). La causa: dos `ISO8601DateFormatter` por fila, un `Calendar` por fecha y una expresión
    regular compilada por fila.
    - Arreglado en e56af0a: los formateadores se arman una vez (`Formateadores`) y los usan Progreso, el chat, la última
      vez de Entreno y Salud. Las cuentas de Progreso corren fuera del hilo principal. Queda en 0,25 s.
    - `FormateadoresTests` tiene un umbral que falla si vuelve un formateador por fila.
    - Android ya usaba formateadores inmutables (50 a 180 ms en la JVM), pero también calculaba en el hilo principal:
      ahora va en `Dispatchers.Default` (8fe0ba7).
  - **El chat se pedía dos veces** al abrirlo mientras cargaba la cuenta (por ejemplo, al tocar un aviso de Mati). Lo
    encontró el agente en Android y lo arregló ahí; iOS tenía lo mismo.
    - `ultimasTraidas` y `alAbrir()`: la carga de la cuenta no pide la última página si ya la trajo otro.
    - `ChatAlAbrirTests` falla con 2 pedidos en vez de 1 sin el arreglo.
  - **Android, la accesibilidad gemela de iOS** (c98584f):
    - el texto con información pasa de terciario a secundario;
    - el agua es un control con rango para TalkBack;
    - el emoji de salud es decorativo.
  - **El agente de Android** (mergeado):
    - GEN-05, GEN-07 y GEN-08 tienen prueba de interfaz. GEN-08 ahora sigue el ajuste aunque cambie con la app abierta.
    - `emu-ui.sh` desinstala antes de la suite.
    - `emu_migracion.py` ya no necesita el adb especial de Android 9.
    - La suite completa en nativa36 dio 193/193.
  - **Paridad pendiente:**
    - iOS: ACC-01/09 y SAL-13, que se cierran en el iPhone de Mati, y REV-04, al que le falta la captura del
      comparador con 4 semanas de fotos.
    - Android: ACC-01 (la firma de Play) y DIE-14/15 (mini-vision).

- **15-oct 10:50, la auditoría de accesibilidad de Xcode en iOS** (`performAccessibilityAudit` en cada pantalla, con
  `test-nativa-real`; `AuditoriaAccesibilidadUITests`, solo con `TEST_RUNNER_MYPUMP_AUDITORIA=1`). Arreglado en d2b6cf0:
  - **Contraste:** el texto con información que estaba en gris terciario (1,7:1) pasa a secundario. Son «Última: …» de
    Entreno, con el valor en negro, la hora y el «enviando…» del chat, quién comentó, la escala del check, los días del
    calendario y la pista del onboarding.
  - **El agua:** ahora es un solo control ajustable para VoiceOver, del alto de un dedo. Las zonas tocables chicas
    pasan de 5 a 0, con prueba (`testElAguaEsUnControlConSuValor`).
  - **`FilaFluida`:** lo que no entra se parte en renglones. Con la letra más grande en el SE, «Última: 60 kg × 9 ·
    ayer» terminaba en «…».

  Lo que la auditoría sigue marcando, revisado contra las capturas:
  - El contraste de textos negros o del verde de marca (7,1:1) cuando pasan por debajo de la barra de vidrio en un
    paso del desplazamiento.
  - Dynamic Type «parcialmente» en texto del sistema, que el barrido con la letra más grande muestra creciendo.
  - Texto cortado en etiquetas que se ven enteras (mayúsculas con espaciado y `minimumScaleFactor`).

- **15-oct 10:20, la matriz de Android y la cola de fotos:**
  - **La matriz de emuladores con Google Play** la armó un agente y está mergeada en 8733a3c. Las 186 instrumentadas
    pasan con 0 fallas en Android 9, 11, 13, 14 y 16. Cada salteada tiene su motivo: por ejemplo, Health Connect no
    viene en 9 a 13. El agente arregló tres errores de la app, cada uno con su prueba:
    1. **Dieta:** una respuesta tardía de la cuenta A se aplicaba en la cuenta B (comidas libres, alimento propio).
    2. **Links sin un navegador con Custom Tabs:** la política, las fuentes y Mi reloj abrían cualquier app con ícono,
       como la cámara o los contactos. Ahora el selector solo ofrece navegadores.
    3. **Mis fotos:** una foto que no se podía traer dejaba la ruedita girando para siempre, y en Android 9 colgaba la
       prueba. Ahora queda un ícono, y la descarga tiene un tope de 30 s.

    Además sumó las pruebas de ACC-05, GEN-04 y OFF-06. La JVM da 612/612 después del merge.
  - **La migración en Android 9 (WebView 66) da 28 de 31.** Los 3 que no dan son de la Capacitor 1.0.12: su web no
    arranca en un WebView anterior a Chrome 80, por `?.`, `??` y los campos de clase. Todo lo de la nativa pasa. Como
    es de `public/`, queda para Mati.
  - **El servicio de fotos no estaba caído.** Desde las 09:35, `/progreso/upload` contesta **429, «muchas fotos por
    hoy, probá mañana»**. Es el tope de 12 por día y por link, que `test-nativa-android` agotó con las corridas de
    MIG-03. `/health` y `/progreso/urls` dan 200, así que los clientes no estaban afectados. Ojo con Cloudflare: sin
    un User-Agent de app contesta 403 con el error 1010.
  - **Pero eso destapó una pérdida de fotos real.** La cola de fotos, igual que la de la web, borraba la foto al
    octavo error del servidor. Con la Mini caída Cloudflare contesta 502/530, y con el tope del día el servicio
    contesta 429: en los dos casos, abriendo la app unas cuantas veces la foto se perdía.
    - **El arreglo** (eee99a9 en iOS, e17654f en Android): un 5xx o un 429 ya no gastan la foto. Si nunca entra, la
      corta la ventana +1/−7 del servidor. Un 5xx sigue con la próxima foto, y el 429 corta la pasada y avisa «Hoy ya
      subiste muchas fotos».
    - **Evidencia:** REV-03 anota el desvío. Hay tres pruebas por plataforma, y cada una falla con la regla vieja. Kit
      436/436, JVM 614/614.
  - **La web tiene el mismo problema** (`flushFotos`, `cliente.html:7583-7602`). Su comentario dice que con el servidor
    caído la foto tiene que sobrevivir, pero cuenta el 502/530 de Cloudflare como error del servidor. Como es de
    `public/`, va para Mati.
  - **La paridad de Android:**
    - Pasan a ✅ ENT, SER y SES (39 ítems), con la matriz en lugar del teléfono (Mati: «simularlo desde la mac»).
      También pasan ACC-05, GEN-04 y OFF-06.
    - Quedan 6 en 🟡.

- **15-oct 06:40, la revisión adversarial de los cambios del día (8cf7369 en iOS y 01b6ae5 en Android):** un agente
  independiente revisó todo lo que cambió desde el TestFlight 104. Encontró tres problemas importantes, cada uno
  reproducido con una prueba que falla sin el arreglo:
  1. **Un reemplazo de comida nativo** llegaba al servidor antes de la decisión y se perdía el que estaba solo en el
     teléfono. Ahora se retienen todos los reemplazos, y solo si hay un mapa sin decidir.
  2. **Fotos de un token rotado:** se perdían porque el modelo de fotos vivo pisaba el archivo, y además se borraba la
     copia de la Capacitor. Ahora van por el modelo vivo y la copia se borra solo si quedaron.
  3. **Privacidad:** sin token, la migración podía entrar a la cuenta de la app vieja aunque la nativa anduviera con la
     de otra persona. Se arregló con `UltimaCuenta`.

  Además, los menores: la dieta en armado, el libro de fotos importadas, los reemplazos del link viejo y el chat sin traer.

  Resultados: kit 434/434, JVM 563/563, sim-migracion 27/27 en 26.5. Lo que dijo bien sin cambios: el delegado de
  avisos con Swift 6, `-avisoDePrueba` solo en Debug y la letra grande en el tamaño normal.

- **15-oct 05:40, la restauración de un respaldo y la letra grande en Android:**
  - **Restaurar un respaldo sin token** (b050d2d, en las dos plataformas): ya no depende de que cambie la huella. Ver
    D14 en la entrada de las 05:00; en iOS es el caso de un respaldo local de Finder sin cifrar, que no trae el Keychain.
  - **Android con la letra más grande del sistema** (`font_scale` 2.0, d77ce19). Tenía los mismos problemas que iOS:
    - Dieta ilegible: las kcal fuera del anillo, «Proteí», «T O T A L»;
    - la barra de pestañas cortaba los nombres.

    Ahora va apilado desde 1,5×, y los nombres de las pestañas crecen hasta 1,2×. Revisión, Progreso, Chat y Entreno ya
    se leían bien. Capturas en `nativa-evidencia/barrido/20261015-0513-android-fuente2` (antes) y `…-0518-…` (después).

- **15-oct 05:30, iOS: tocar un aviso cerraba la app (arreglado en el TestFlight 107) y el port a Android:**
  - **Tocar una notificación con la app en el fondo la cerraba** (9c9e8b0). Le iba a pasar a cada cliente que tocara un
    mensaje de Mati.
    - Causa: con la versión `async` del delegado, Swift llamaba al cierre de UIKit desde un hilo de fondo, y UIKit
      aborta con una aserción en `_updateSnapshotAndStateRestoration`.
    - Lo encontró una prueba nueva de punta a punta (NOT-03): con `-avisoDePrueba chat` (solo Debug) la app agenda un
      aviso local que entra por el mismo `didReceive`. La prueba la manda al fondo, lo toca y llega al Chat; en frío,
      arranca sin caerse.
    - **TestFlight 107** (`nios-2.0.0-107`, 05:20) lo lleva. **Del 104 al 106 tienen el cierre:** en el iPhone de Mati,
      actualizar al 107 antes de probar avisos.
  - **Sin señal, revisado con `-sinRed`:**
    - El chat parecía vacío, como en la web. Ahora dice «No pudimos traer los mensajes», con Reintentar (a064dc0, y en
      Android f0f6ab1).
    - Entreno, Dieta, Revisión y Progreso quedan como la web: muestran el plan guardado, con el aviso.
  - **Mis fotos:** una foto que no se podía traer dejaba la ruedita girando para siempre (226bd9e). Es el gemelo del
    arreglo de Android e16f231, que el agente de la matriz encontró en Android 9.
  - **Android, port de los arreglos de iOS:**
    - los swaps viejos esperan la decisión (4bf705a; la prueba reproduce la pérdida también en Android);
    - la cola de fotos de la Capacitor sale en la escritura de vuelta (473d5dd);
    - el chat sin red (f0f6ab1).

    JVM 553, sin fallas.

- **15-oct 05:00, iOS: la migración otra vez de punta a punta, la letra de accesibilidad y lo del agente de Play:**
  - **Migración** (`sim-migracion.sh`, con el código de hoy). Aparecieron dos errores reales y uno de la prueba:
    - **Pérdida de datos** (6fd391b). Los reemplazos de comida que estaban solo en el teléfono (una v1.0.11, sin la
      marca de migrados) se perdían. Era una regresión del hallazgo 2: la palanca suelta las ops viejas con un drenado
      inmediato, y el `swap` de la cola vieja llegaba al servidor antes de que se decidiera qué reemplazos del teléfono
      faltaban subir. El servidor «ya tenía algo», ganaba la mezcla y el resto se descartaba. Ahora la cola retiene los
      `swap`/`swap_del` viejos hasta esa decisión. Lo cubre `SwapsViejosPalancaTests`, que falla sin el arreglo.
    - **La cola de fotos de la Capacitor quedaba** (549fdba). Si el cliente volvía a la app vieja (el plan B o un
      TestFlight vencido), ella subía otra vez esas fotos y podía pisar una más nueva de la misma semana y pose. Lo
      encontró el agente de Android. Ahora la escritura de vuelta la saca, solo si no cambió.
    - **De la prueba** (45f4ed7). La limpieza de cada corrida deja una lápida de la sustitución de ejercicio, y en la
      corrida siguiente SER-14 fallaba sin que la app hiciera nada mal.
    - Resultado: 26/26 en 26.5 y en 17.5, y 27/27 con el chequeo nuevo de las fotos.
  - **Letra de accesibilidad (AX5) en el iPhone SE** (b9e3cb3). Un barrido que desplaza cada pantalla encontró:
    - Dieta ilegible: las kcal, los macros y el total de cada comida («T / OT / AL»).
    - «Enviado» dibujado encima de «Check de la semana».
    - El peso en «8… kg» y la última vez en «60 k…».
    - Las fechas del gráfico encimadas.

    Ahora va todo apilado, y en los tamaños de siempre no cambia nada (UI 17/17 en el iPhone 17 Pro).
    `BarridoLetraGrandeUITests` queda como herramienta: corre solo con `TEST_RUNNER_MYPUMP_BARRIDO=1`.
  - **`-sinRed YES`** (a88f527, solo en Debug) para ver la app sin señal en el simulador.
  - **Agente de Play, respaldo y MIG-03** (cda4efd):
    - **Capturas de Play:** 20 en `nativa-evidencia/tienda-android/20261015-034014`. El teléfono va en 1080×1920
      porque Play no acepta un lado mayor que el doble del otro; la tablet de 10" va en 1440×2560. Las claras mostraban
      «3G»: cambiar el modo noche rearmaba la barra. Rehechas sin eso en `tienda-android/20261015-053511`.
    - **Respaldo de Google (APL-08):** 19/19 con `bmgr`, en la nube y en el pase a otro teléfono.
      - El token de la nativa (Keystore y `acceso.bin`) nunca viaja.
      - Con la app vieja respaldada, al restaurar la nativa vuelve a adoptar el token del WebView (D14).
      - **D14 anda de casualidad.** Android restaura las fechas de los archivos en 1970, eso cambia la huella del
        leveldb y la migración corre de nuevo. Con las fechas iguales cortaría antes y pediría el link. Hay que
        endurecerlo en Android.
      - `files/legado/estado.json` lleva el token en los nombres de las claves a borrar y viaja en el respaldo. El
        mismo token ya viaja en `app_webview`, así que no hay exposición nueva y queda como la app vieja. En iOS es
        igual: el Keychain con `AfterFirstUnlock` viaja a propósito en el respaldo cifrado, y la copia cruda está
        excluida.
      - La identidad de Firebase viaja en el respaldo. Que el push siga llegando después de restaurar solo se puede ver
        con un teléfono real.
    - **MIG-03 en Android:** 31/31 con fotos y sustitución.
  - **Pendiente en Android,** cuando termine el agente de la matriz (toca los mismos archivos):
    - los dos arreglos de la migración (los swaps viejos y la cola de fotos);
    - D14 robusto;
    - `limpiar` al final de `emu-migracion.sh`.

- **15-oct 03:50, iOS en el iPad: el chat no tomaba el toque.** La suite de XCUITest en el iPad Pro 13" (iPadOS 26.5)
  encontró dos cosas:
  - **Pruebas:** en iPadOS 26 las pestañas son una barra flotante arriba y XCUITest no las ve como `tabBars`. Ahora se
    buscan como botones por su nombre (`MyPumpUITests/Pestanas.swift`).
  - **Un bug real del compositor del chat, no solo del iPad.** El campo de varias líneas (`axis: .vertical`) toma el
    toque solo cerca del texto.
    - En el iPad, tocar el medio del campo vacío no hacía nada.
    - En cualquier equipo, tampoco respondía el borde de la cápsula, que es la mitad de su alto.
    - Se aisló con variantes: el vidrio interactivo no era la causa; con el campo de una línea, andaba.
    - **El arreglo:** todo el vidrio lleva al campo, con un toque simultáneo que no le quita al campo sus propios toques
      (mover el cursor sigue andando).
    - Lo cubre `testTodoElVidrioLlevaAlCampo`: falla sin el arreglo en el iPhone 17 Pro y pasa con él en el iPad, en
      26.5 y en 17.5.
  - **Android no lo tiene:** el `decorationBox` del `BasicTextField` es parte del campo.

- **15-oct 03:00, Android: Dieta con escritura mergeada (f4bf5ce) y una falla de producción:**
  - **Dieta** (DIE-08 a 18): la mano, reemplazar, el alimento propio con la etiqueta, las comidas libres con la foto del
    plato y `food-db.json` en el APK. Ya no queda ninguna pantalla «en construcción» en Android. Instrumentadas: 170.
  - **Producción: las fotos de comida con IA fallan desde el 14-oct a las 13:03**, en la app de hoy y en la nativa.
    `~/mini-vision` corre `codex exec` sin `-m` y el modelo por defecto de la Mini (`gpt-5.5`) ya no lo acepta la cuenta
    de ChatGPT. El bot y el chat pasan `-m gpt-5.6-sol` y siguen andando.
    - **El arreglo**: una línea en `~/.codex/config.toml` de la Mini. Está probado a mano sin tocar nada.
    - **Espera el OK de Mati**; le llegó un aviso al teléfono a las 02:58.
    - Detalle en la memoria `codex-modelo-default-minivision`.

- **15-oct 02:30, iOS TestFlight 104 y la matriz de Android:**
  - **iOS:**
    - Los hallazgos menores de la revisión están arreglados (dd88596): 4, 5, 6, 7, 9 a 14, la firma de fotos, `Outbox` con
      números no finitos y el token de la Fase L.
    - Una foto de progreso con el token caído ya no se pierde (b3ee106).
    - Kit 416/416, XCUITest 17/17.
    - **TestFlight 104** (`nios-2.0.0-104`, 23 cambios de iOS desde el 103): salió de Codemagic a las 02:10.
  - **Android:**
    - Mergeados los arreglos importantes (be23b05): copia offline, palanca, Salud por cuenta y el domingo de una vez.
      Están también Revisión con Mi Día (0afe4ae) y Chat y Progreso.
    - Instrumentadas: 153 en Android 16.
  - **El emulador de Android 9 encontró que la app se cerraba al abrir el link del coach** (6319465):
    - `URLDecoder.decode(String, Charset)` es de la API 33 y `:core` se prueba con Java 21. Lo mismo pasaba con
      `URLEncoder.encode` en el catálogo de ejercicios y en Salud.
    - Ahora `scripts/nativa/api-android.py` revisa el bytecode de `:core` contra el minSdk (también en `android-nativa`).
    - En `:app`, NewApi es fatal en el release.
  - **La migración no leía nada con un WebView anterior a Chrome 71** (`globalThis`; e1b4533). La Capacitor anda desde
    el 60. Ahora usa `window`.
  - **La hoja de la primera vez** no pide las notificaciones si ya llegan, como pasa hasta Android 12 (1649ae6).
  - **El resto de lo que falló en Android 9 es de las pruebas, no de la app.** Las pruebas suponen:
    - una pantalla grande (Dieta fuera de la vista en 720×1280);
    - Android 12 o 13 (`pm set-app-links-user-selection`, `POST_NOTIFICATIONS`);
    - Health Connect integrado;
    - Chrome con Custom Tabs;
    - un heap grande (una foto de prueba de 48 MB).
    
    En el emulador quedó comprobado que la alarma del domingo se agenda bien. Las pruebas se van a ajustar en la pasada
    de la matriz.

- **15-oct 01:30, prueba exhaustiva de iOS (reemplaza la beta, pedido de Mati):**
  - **XCUITest completas en 26.5 (16/16) y 17.5 (16/16).**
    - La de «la última vez» se salteaba sola cuando la cuenta de prueba gastaba las series del primer ejercicio. Ahora
      recorre el día (c5919b3).
    - La del chat fallaba en 17.5 por la prueba, no por la app: elegía el tipo de campo antes de que cargara la
      pantalla. Ahora verifica también que alcance un toque (2f5edff).
  - **Revisión adversarial del código de iOS** (solo lectura): 14 hallazgos. Arreglados, cada uno con pruebas que
    fallan sin el arreglo:
    - **1, bloqueaba el lanzamiento** (800afb2). Después de pasar de semana o de bloque, la copia offline quedaba con la
      rutina vieja. Un arranque sin señal volvía a la semana anterior y las series pisaban las de esa semana.
    - **2** (800afb2). La palanca `migracion_ops_legadas` no frenaba lo que la Fase L deja directo en la cola. Ahora esas
      ops van marcadas y la cola las retiene.
    - **3** (cd5e47e). Salud era del teléfono: con el link de un cliente abierto en otro teléfono, se subía la salud del
      dueño. Ahora es por cuenta.
    - **8** (c636397). El aviso del domingo, repetido, le llegaba para siempre a quien dejó la app. **Ahora es de una
      vez y la app lo vuelve a armar cada vez que se usa:** a quien usa la app le llega igual y a quien la dejó, como
      mucho uno más.
    - **Los menores** (4, 5, 6, 7, 9 a 14 y las sospechas), en un agente.
    - **En Android están los mismos 1, 2, 3 y 8**, porque es un gemelo. Los está portando otro agente.
  - **Prueba que rompía el proceso** (SIGSEGV en 1 de 7 corridas): era `SinPermisoIATests`, que anotaba sin candado
    desde un transporte que corre en paralelo. No es de la app. Kit: 386/386.
  - **Notas para el revisor de Apple** (5075a03). Decían «No personal data reaches a third-party AI», que no era exacto.
    Ahora dicen lo mismo que la política: a la IA le llega todo desidentificado.
  - **Android, en paralelo:**
    - Chat y Progreso mergeados (5275563), con 121 instrumentadas.
    - Release firmado por Codemagic (`android-nativa`, dbbf266).
    - Matriz de emuladores con Google Play en Android 9, 11, 13, 14 y 15 (c3a9fe9).

- **14-oct 23:30, Android: notificaciones y Salud mergeados** (b40b3fe y fd974ba):
  - **Notificaciones** (NOT-01 a 08, GEN-06, D8). FCM `mypump-663be` con `firebase-messaging` 25.0.1 y
    `google-services` 4.4.4 (G4). Se registra solo con cuenta y permiso, si cambió el token o la cuenta. Dos canales:
    «Mensajes de Mati» y «Fin del descanso». El domingo, con `setWindow` de 10 min: `setInexactRepeating` semanal deja
    una ventana de ~5 días. La actualización real desde la Capacitor 1.0.12 en el emulador borró su alarma y su canal.
    **D8 en Android es inexacto:** con la pantalla apagada puede llegar hasta ~1 min tarde, y lo exacto pediría alarmas
    exactas o un servicio en primer plano. Queda así.
  - **El mismo hallazgo en iOS** (5b11bfd): con el link de otra cuenta en el mismo teléfono, el push no se volvía a
    registrar y los avisos seguían yendo a la cuenta anterior. Ahora recuerda la cuenta (`mypump_push_cuenta`, una huella).
  - **Salud** (SAL-01 a 13, APL-07). `FuenteHealthConnect`, gemela del plugin 8.9.3, con el banco contra el bridge de
    main: 183 consultas y 718 registros idénticos. Lo que se sumó:
    - el historial de 30 o 60 días según el permiso, que faltaba en `:core`;
    - la hoja de permisos como llamada suspend;
    - Mis datos con la recuperación y el detalle, y las tarjetas de Revisión listas;
    - el diagnóstico.
    
    La base real con `test-nativa-android` recibió 93 datos sintéticos de `health_connect`, que quedan en esa cuenta.
  - **`abrirEnNavegador` fija el navegador**, con la prueba del dominio verificado (falla con el código viejo).
  - **Al juntarlos**, la hoja de la primera vez arranca con Salud si hay Health Connect. Cuatro pruebas esperaban solo
    Notificaciones: se arreglaron (22f80fe) y se sumó una con la fuente de verdad.
  - **Para Play (G7):** la declaración de apps de salud, con los 13 permisos y el historial.
  - **Limitación:** si el cliente se va de la app en medio del historial, Health Connect niega leer en segundo plano y
    ese tramo queda con huecos. Igual que la Capacitor hoy.

- **14-oct 22:30, auditoría de la columna Android y lo que salió de ella:**
  - **Auditoría de solo lectura** de 83 filas (ACC, GEN, DIE, DIA, REV, PRO, CHA, OFF, MIG y APL): 28 ✅, 46 🟡,
    2 ☐ y 7 ➖. Quedó en `NATIVA_PARIDAD.md` (4ed3e9c y 530367a), junto con las celdas viejas de iOS ("falta la
    pantalla" cuando ya existía) y D10, D11, D14 y D15 en la tabla de decisiones.
  - **iOS, PRO-02** (6324c09): Progreso agrupaba por el nombre del plan; un ejercicio sustituido salía con el nombre y el
    historial del original. Ahora `ModeloApp.cargarProgreso()` pasa el ejercicio efectivo, como la web. Kit 374/374.
    Va en el próximo TestFlight.
  - **Android `:core`** (53ae738): GEN-05 como la web e iOS, `ultimoDiaValido` y `FechaJs.diaLargo`, Progreso por el
    ejercicio efectivo, la demo con Mi Día sembrado y el chat vacío, y las pruebas gemelas de iOS que faltaban. JVM
    434 → 449.
  - **Riesgo encontrado (Android, alto):** el App Link toma todo el dominio, igual que la Capacitor, pero
    `abrirEnNavegador` no fijaba el navegador. En un build de Play, con el dominio verificado, la política de
    privacidad, «Eliminar mis datos» y el link de Mi reloj volverían a MyPump. Lo arregla el agente de Salud, que abre la
    política desde Health Connect, con una prueba que verifica el dominio en el emulador.
  - **Siguiente tanda de Android** (encargos listos en `~/Developer/nativa-evidencia/encargos/`): Chat + Progreso,
    Revisión con Mi Día y Dieta con escritura. Salen cuando terminen los agentes de notificaciones y de Salud, para no
    pisarse en `Pestanas.kt` y por la memoria de la Mac.

- **14-oct 21:30, Android:**
  - **Sin permiso para la IA y el aviso del domingo como mensaje de Mati**, gemelos de iOS. Mergeado en f6977e9: sale
    `ConsentimientoIA`, `PermisoIA` y la sección de Mis datos; `AvisoDomingo` en `:core:datos`. Tests: JVM 434 (1
    salteada) y 59/59 instrumentadas en nativa36 con Entreno.
  - `main` (e171038, la política de privacidad sin el permiso de IA) mergeado en `nativa`.
  - La Mac tenía 10 simuladores prendidos y el swap lleno (42 de 43 GB): quedaron apagados los del proyecto.
  - Lanzados en paralelo dos agentes: notificaciones (FCM, la hoja de permisos de la primera vez, el aviso del domingo
    y D8) y Salud (Health Connect).

- **14-oct 21:00, fuera de las apps pero ligado a ellas (Mati: «hacelo todo vos», «seguí en autónomo»):**
  - **WhatsApp sin nombres** (elección de Mati: «tapar el texto»). Cada cliente es un alias fijo (`CL-7F3A`), unido a
    su ficha por el teléfono.
    - Código en `~/Desktop/Pump-Respuestas/wa-mcp/src` (no está en git; lo respalda iCloud): `alias.mjs`,
      `pedidos.mjs`, `mcp.mjs`, `mini.mjs`, `vigia.mjs` y `aprobacion.mjs`, con 28 pruebas.
    - Hook de AskUserQuestion en `~/.claude/settings.json`: los nombres van solo en las descripciones de las opciones,
      que no vuelven a la IA. Verificado en el registro de la sesión.
    - **Mati decidió no usarlo (21:15):** «acá en whatsapp considero que no hace falta alias». Se revirtieron el MCP
      (versión de las 19:07), el hook y la skill. Las herramientas quedan guardadas sin uso. Detalle en la memoria
      `whatsapp-tapado-alias`.
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
