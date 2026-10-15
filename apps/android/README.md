# MyPump nativa — Android

La app nativa de Android (Kotlin + Jetpack Compose) que reemplaza a la Capacitor de `android/` como actualización de la
misma app en Play: mismo `com.pumpteam.mypump`, misma `.MainActivity`, mismo link del coach. Arranca en
`versionCode 100` / `2.0.0`. El plan es la Fase 5 de `~/.claude/plans/planifica-la-ejecucion-de-atomic-crescent.md`; el
estado de todo, `docs/NATIVA_ESTADO.md`.

## Módulos

| Módulo | Qué es | Gemelo en iOS |
|---|---|---|
| `:core:modelos` | Kotlin/JVM. Las filas de las RPC y lo que publica el Cerebro, con decodificación tolerante (`ValorJson`, `NumeroJs`) | `MyPumpModelos` |
| `:core:reglas` | Kotlin/JVM. Las reglas portadas de la web: progresión, clave de ejercicio, porción casera, anclaje e hidratación de swaps, categoría y sustitución de alimentos, sustitución de ejercicios, alimento propio, comida libre, normalización de la dieta, progreso, peso, check y fotos de Revisión. `JsRegex` y `ColacionEspanol` dan la semántica de JS | `MyPumpReglas` |
| `:core:datos` | Kotlin/JVM. El cliente de PostgREST y la visión (OkHttp), la cola de escrituras (`Outbox`, `Escrituras`), los archivos por cuenta (`Disco`) y los modelos de estado con `StateFlow` (`ModeloApp`, chat, Revisión y Mi Día, fotos, Progreso, avisos) | `MyPumpDatos` |
| `:app` | Android, Compose + Material 3. Las pantallas (ver "La interfaz"), el `ModeloAppViewModel`, el token con el Keystore (`TokenEnKeystore`), las preferencias, el tema guardado y las reglas de backup | `MyPump` |

Los `:core` no dependen de Android: sus tests corren en la JVM, en segundos y sin emulador.

## Compilar y probar

Hace falta el JDK 21 y el SDK de Android 36 (platform y build-tools):

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export ANDROID_HOME=~/Library/Android/sdk     # o sdk.dir en local.properties
cd apps/android
./gradlew test                  # todos los tests de :core (JUnit 5, en la JVM)
./gradlew :app:assembleDebug    # app/build/outputs/apk/debug/app-debug.apk
./gradlew connectedDebugAndroidTest   # las instrumentadas, en el emulador (AVD nativa36) o un teléfono
```

`scripts/nativa/emu-ui.sh [serial] [clases]` corre las instrumentadas y baja las capturas de `CapturasUiTest` (cada
pantalla en claro y en oscuro) y el reporte a `~/Developer/nativa-evidencia/android-ui/<fecha>/`.

`python3 -I scripts/nativa/lanzar-emu.py <serial> [escena]` instala el APK de debug y abre la app con el link de
`test-nativa-android` (gemelo de `lanzar-sim.sh`): el token se lee adentro del script y va por la entrada de `adb shell`,
nunca por argumentos. Ojo: Android 16 anota el link entero (`capturedLink=`) en los registros de transición del
`WindowManager`, así que después conviene `adb logcat -c`. Con un teléfono de un cliente pasa lo mismo con cualquier app:
un `adb bugreport` lleva su link.

## La interfaz

Gemela de `apps/ios/MyPump/`, adaptada a Material 3: barra de pestañas abajo, hojas (`ModalBottomSheet`), snackbar
para el aviso de guardado, título grande que se achica al desplazar. Los colores son los de `Tema.swift`, y los títulos
y números grandes van en Archivo.

| Paquete | Qué hay |
|---|---|
| `diseno` | `TemaMyPump` (claro/oscuro, `MyPump.colores`), `Iconos`, componentes (`Tarjeta`, `BotonMarca`, `Aviso`, `MarcoPantalla`, `Formato`) |
| `raiz` | `RaizMyPump` (marca, bienvenida, sin conexión, "Actualizá MyPump" o la app), `AppConPestanas` (5 pestañas, badges, barra de la demo, banner sin conexión, aviso de guardado), `Navegacion` |
| `acceso` | Bienvenida (`AccesoPantalla`) y `Apariencia` (D5) |
| `avisos` | Las notificaciones (ver "Los avisos"); la hoja de permisos de la primera vez está en `acceso/OnboardingPermisos` |
| `entreno` | Entreno (gemela de `apps/ios/MyPump/Entreno/`): la lista del día (`ListaEntreno`), el detalle de un ejercicio (`EjercicioPantalla`, `TablaSeries`), sustituir y cerrar el día (`Hojas`), el descanso (`Descanso`: la isla arriba de las pestañas, su reloj y el pitido), las preguntas del motor (`Preguntador`) y los textos de la app (`Bonito`, `CardAccesible`) |
| `dieta`, `revision`, `misdatos`, `respaldo` | Dieta en modo lectura, Revisión (por ahora la entrada a Mis datos), Mis datos y las 14 fuentes |
| `salud` | Health Connect (`FuenteHealthConnect`, la hoja de permisos, la política de privacidad) y sus pantallas: Salud en Mis datos, el detalle, las tarjetas de Revisión y el diagnóstico (ver "Salud (Health Connect)") |

- **El tema (D5).** Sigue al teléfono, salvo `mypump-theme = "dark"` en las preferencias (lo escribe "Siempre en modo
  oscuro" de Mis datos o la migración de la web). Los íconos de la barra de estado van con el tema de la app, no con el
  del teléfono.
- **Sin permiso para la IA.** D7 se sacó el 14-oct (Mati: la IA trabaja bajo su aprobación y no es algo que el cliente
  acepte): no hay hoja antes del primer mensaje, foto o check, ni interruptor en Mis datos, y la app no lee
  `mypump_get_consentimiento_ia`. La cola sigue sabiendo ejecutar `consentimiento_ia`, solo para vaciar lo que haya
  quedado de antes; un `consentimiento-ia.json` viejo queda en la carpeta de la cuenta y nadie lo lee.
- **El aviso del domingo** no se configura y llega como un mensaje de Mati: `AvisoDomingo` (título "Mati", id 1002 de la
  Capacitor, domingo a las 11:00, abre Revisión), gemelo del de iOS. Lo agenda `avisos/CentroAvisos` (ver "Los avisos");
  `PreferenciasAvisos` queda por la migración, no para agendar.
- **Links (fuentes y legales).** `abrirEnNavegador` abre una Custom Tab (`androidx.browser`, OK de Mati del 14-oct),
  como el SFSafariViewController de iOS, con el navegador FIJO (`navegadorConPestanas`; el `<queries>` de
  `CustomTabsService` deja verlos): el App Link de la MainActivity toma todo `app.mypumpteam.com`, y en un build de Play,
  con el dominio verificado, un VIEW implícito a `privacidad.html` volvía a MyPump. Sin un navegador con Custom Tabs, un
  VIEW con el selector de `CATEGORY_APP_BROWSER` (nunca MyPump). `NavegadorFueraDeLaAppTest` lo prueba eligiendo el dominio
  para la app en el emulador (y lo deja como estaba).
- **Entreno.** Todo sale del motor (`ModeloEntreno`, sin cambios en `:core`). Las pantallas lo leen con `vistaDe(motor)`:
  el motor publica una copia nueva del día en cada cambio, así que lo que recibe la vista se recompone solo cuando algo
  cambió. El descanso va aparte (cambia cuatro veces por segundo): su isla y su reloj (`RelojDescanso`) viven arriba de las
  pestañas, como en iOS, y terminan aunque se esté en otra. Abrir un ejercicio es estado de la pestaña (`rememberSaveable`),
  no una ruta: Atrás vuelve a la lista y "Siguiente: … →" (D13) cambia de ejercicio. Las preguntas del motor (reabrir el
  día, "¿Está bien cargado?", "¡Día completado!", avanzar de semana, el bloque nuevo) viven en el ViewModel (una pregunta
  abierta sobrevive a rotar) y lo que las espera corre en el alcance de la app.
- **El pitido del descanso (SES-05).** Un `AudioTrack` con los dos tonos de iOS, como sonido del sistema
  (`USAGE_ASSISTANCE_SONIFICATION`) y sin pedir el foco de audio: se mezcla con la música del cliente en vez de cortarla
  o bajarla, y con el teléfono en silencio o vibración no suena. El aviso táctil es el del sistema
  (`performHapticFeedback`), que no pide el permiso `VIBRATE`.
- **Fotos de los ejercicios.** `ImagenesRemotas` (en `diseno`): `HttpURLConnection`, decodificadas al tamaño en que se
  muestran y en memoria (sin librerías de imágenes). Las pruebas de interfaz las cambian por un "sin foto": no van a la
  red.
- **Recursos compartidos.** Gradle copia en la compilación (`app/build/generated/compartido/`) la fuente Archivo de la app
  de iOS, la demo y el catálogo de `apps/shared`: no hay copias en el repo que se puedan desfasar.
- **Pruebas de interfaz (`androidTest/…/ui`).** Desde el 14-oct están `ui-test-junit4` y `ui-test-manifest` (OK de Mati):
  las nuevas pueden usar `createAndroidComposeRule` (la primera, `CustomTabsTest`). Las anteriores siguen con el arnés
  propio, que no lo necesitaba: `Pantalla` lee el árbol de semántica de Compose con las mismas piezas públicas que usa esa
  librería (`ViewRootForTest.onViewCreatedCallback`, `SemanticsOwner`) y toca con las acciones de semántica: busca por
  `testTag` o por texto y espera a que aparezca. El backend es `ServidorDePrueba`, que contesta con las respuestas
  grabadas de `test-nativa-real` (`apps/shared/fixtures`, en los assets del APK de pruebas), sin tokens ni red. Las de Entreno
  (`EntrenoUiTest`) usan además `tocarDeVerdad` (un toque con el dedo, que en un campo ubica el cursor: así se prueba que
  tocar un campo lo selecciona entero, SER-04) y `teclear` (escribe donde está el cursor, como el teclado). Lo que se
  prueba suelto (`CustomTabsTest`) va en una `ComponentActivity` vacía que solo existe en debug (`src/debug/AndroidManifest.xml`).
  Si se agrega `ui-test-junit4` + `ui-test-manifest`, las pruebas pasan a `createAndroidComposeRule` casi sin cambios:
  las etiquetas son las mismas.

<!-- Revisión con Mi Día (REV-01…08, DIA-01…06, SAL-09/10): bloque propio de esa pantalla. -->
## Revisión con Mi Día

Gemela de `apps/ios/MyPump/Revision/` en el paquete `revision`; lo de las fotos que va a usar también Dieta (la
reducción, el botón de cámara o galería y el FileProvider) está en `fotos`. Todo sale de los modelos de `:core:datos`
(`ModeloRevision`, `ModeloFotos`, `ModeloSalud`): la pantalla no tiene reglas propias.

- **La pantalla** (`RevisionPantalla`): el aviso de plan incompleto arriba (GEN-05) y, en el orden de la web (REV-01),
  Fotos, Check, Peso, Mi reloj y Mi Día. Tirar para actualizar trae el check, el peso, Mi Día, las fotos y la salud.
  Un pedido de sección (`Navegacion.anclaRevision`, las claves de `AnclaRevision`) la desplaza hasta ella y se consume:
  el banner de las otras pestañas lleva al check si es lo único que falta y, si no, a las fotos (como iOS);
  `?scene=myday` y el aviso de Mi Día, a Mi Día. Si lo de arriba termina de cargar y la sección se movió, se corrige una
  vez (salvo que el cliente ya se haya desplazado solo).
- **Fotos** (REV-02…05, `FotosSemana`): la cámara del teléfono (`TakePicture`) o el selector de fotos del sistema
  (`PickVisualMedia`), sin pedir CAMERA ni permisos de la galería. La cámara escribe en `cache/camara/` por un
  FileProvider propio (`fotos/ProveedorFotos`, sin exportar, solo esa carpeta) y la foto se borra apenas se lee. El
  manifest saca CAMERA con `tools:node="remove"`: si una librería lo trajera, Android exigiría el permiso concedido hasta
  para abrir la cámara de otro. `fotos/ReduccionFoto` es la de iOS con lo del sistema: medidas sin decodificar,
  `BitmapFactory` de a potencias de 2, la orientación de `android.media.ExifInterface` aplicada a mano (`BitmapFactory`
  la ignora siempre, también en HEIC, así que no se gira dos veces) y `Bitmap.compress` a 900 px y 0,7, que no escribe
  metadatos. HEIC desde Android 9. Las miniaturas van con la URL firmada por `ImagenRemota` (en memoria, nunca en
  disco); con una foto guardada se firma de nuevo, porque reemplazar una de la semana no cambia cuántas hay y quedaba
  la miniatura vieja (cada firma es otra URL). La galería por semana y el comparador desde la 4.ª semana, con el cambio
  de peso; con 3 fotos esperando en la cola no entra otra ("Hay fotos esperando subir"). Contra la base real
  (`test-nativa-android`, 15-oct): una foto de la cámara del emulador quedó en el servidor como JPEG de 675×900, derecha
  y sin EXIF ni GPS.
- **Check** (REV-06): el borrador sobrevive a cambiar de pestaña y a rotar, lo guardado no lo pisa mientras el cliente
  toca, y se vacía al cambiar de semana. El botón dice qué falta ("Faltan: …").
- **Peso** (REV-07): el gráfico es un `Canvas` (sin librerías): la media de 7 días con la curva monótona de Salud
  (`curvaMonotona`), los pesos del día como puntos, 3 valores a la derecha y fechas por semana (cada dos, tres… si no
  entran sin pisarse, como Charts). Un peso fuera de 30-300 kg no sale y el campo se sacude (en la composición: en el
  alcance de la app la animación no tiene reloj de cuadros y se cae).
- **Mi reloj** (REV-08, `MiReloj`): "Conectar" abre `…/api/wearables/iniciar?t=` con `abrirEnNavegador`, que fija el
  navegador (el link es de `app.mypumpteam.com`, el App Link de MyPump); "Quitar" pide confirmación.
- **Mi Día** (DIA-01…06, `MiDia`): la racha con `RachaTexto.icono` y el último día válido desde 2 días, los hábitos ✓/✗
  (tocar de nuevo borra; TalkBack dice "Dormí bien: sí, marcado"), el agua, Recuperación y Salud (`salud/CardsSalud`,
  SAL-09/10; "Ver todos mis datos" abre el detalle encima), los 30 días (se traen al abrirlos) y el respaldo científico.
  En la demo todo se toca y nada sale: `ModeloRevision.demo()` no tiene token ni cola, las fotos dicen que no se guardan
  y sin cuenta no hay reloj ni salud.
- **Pruebas.** `fotos/ReduccionFotoTest` (instrumentada, gemela de `ReduccionFotoTests` más las 8 orientaciones de EXIF;
  la HEIC es `androidTest/assets/fotos/con-gps.heic`, porque Android no codifica HEIC sin librerías), `ui/RevisionUiTest`
  y `ui/RevisionCapturasTest` (cada sección en claro y en oscuro, la galería con 7 semanas de fotos y la demo). La cámara
  y el selector de fotos se reemplazan con un `Instrumentation.ActivityMonitor` que contesta una foto armada en la
  prueba (`FotoDePrueba`), sin abrir nada. `ServidorDePrueba` contesta `/progreso/upload`, `/progreso/urls` y
  `/api/wearables/disponibles` (antes, todo lo que no era RPC daba `[]`). Mi reloj no abre el navegador de verdad (el
  link lleva el token y va al sitio real): con el dominio elegido para MyPump (`pm set-app-links-user-selection`) se
  mira que el pedido va al navegador fijo y que el mismo link sin fijar lo abriría MyPump.

<!-- Dieta con escritura (DIE-08…18): bloque propio de esa pantalla. -->
## Dieta con escritura

Gemela de `apps/ios/MyPump/Dieta/` (DIE-08…18) en el paquete `dieta`, sin Comí ni Salté (D10). Lo que decide sale de
`:core` (`PorcionCasera`, `SustitucionAlimentos`, `BaseAlimentos`, `AlimentoPropioNuevo`, `ComidaLibreNueva`,
`SwapsDeComida`) y de `ModeloApp` (`sustituir`, `revertir`, `crearAlimentoPropio`, las comidas libres y `analizarFoto`):
la pantalla no tiene reglas propias, salvo el puente con el motor (`MotorSustitutos`, gemelo del de iOS).

- **La fila** (`FilaAlimento`): la mano (DIE-08) muestra la porción casera de lo que se está comiendo ("≈ 2 huevos"),
  una por alimento y por opción; el reemplazo (DIE-09) está salvo en los condimentos y en lo que Mati marcó
  `swappable: false`. Tocar la marca de un reemplazo ofrece volver al del plan ("¿Volver al alimento del plan?"). La
  tarjeta de cada comida recompone con los reemplazos: el parámetro que antes no se usaba no contaba para recomponer, y
  la fila seguía mostrando el alimento del plan.
- **Reemplazar** (`HojaReemplazar`, DIE-10/11/13): los candidatos del alimento DEL PLAN en esa posición, contra la base
  de la web (`food-db.json`, que Gradle copia de `apps/shared` a los assets y el ViewModel lee al arrancar) con los
  propios y las exclusiones del cliente. Los 🌍 van arriba con su nombre en inglés, los propios con "★ Tuyo", la
  diferencia de kcal en verde hasta 5 % (redondeada como `Math.round` de JS), los avisos del motor y la búsqueda. Lo
  elegido sale con `sustituir` (anclado, por la cola) y vuelve con `revertir`.
- **Alimento propio** (`CrearAlimento`, DIE-14), adentro de la misma hoja (Atrás vuelve a la lista): las unidades de la
  web, los gramos por unidad, el renglón de la base y "Crear y usar", que va directo al servidor y lo aplica si el motor
  lo ofrece. "Escanear etiqueta" (solo con cuenta) usa `BotonFoto` (1600 px, JPEG 0,85, sin EXIF ni GPS) y la visión
  `ETIQUETA`, y prellena todo editable.
- **Comidas libres** (`ComidasLibres`, DIE-15/16), al pie y solo con cuenta (en la demo no están): a mano o con la foto
  del plato (1280 px). La estimación trae "Lo que vio en el plato" con los gramos que re-escalan macros y totales, y la
  escala; si la visión falla, el aviso con el motivo y "Cargar a mano". Borrar es optimista y la comida vuelve si el
  servidor falla. Al volver a la app con otro día, `alVolverAPrimerPlano` las recarga (DIE-18).
- **Lo que espera a la IA** (~30 s, y gasta cupo) vive afuera de la composición (`EsperasDieta`, uno por modelo y
  cuenta): cambiar de pestaña o girar el teléfono no pierde la respuesta, y salir del formulario o cerrar la hoja olvida
  una etiqueta que llega tarde.
- **Pruebas.** En la JVM, `dieta/MotorSustitutosTest` con la base empaquetada y la dieta grabada (las 55 opciones de la
  web para el huevo, las exclusiones, los avisos, el redondeo de JS). Instrumentadas, `ui/DietaEscrituraUiTest`: las tres
  de `DietaUITests` de iOS, la foto del plato, la visión que falla, el alimento propio a mano y con la etiqueta, las
  restricciones del cliente, lo que no se reemplaza, borrar que falla, el cambio de día (con la zona horaria del
  proceso), la demo, y la respuesta de la IA que sobrevive a cambiar de pestaña y a girar, y que se olvida al salir. Y
  `ui/DietaCapturasTest`, once escenas en claro y en oscuro. `ServidorDePrueba` contesta `/vision` con lo que pide cada
  prueba y guarda comidas libres, alimentos propios y reemplazos mientras dura (así reabrir la app los vuelve a traer);
  `CamaraDePrueba` es el monitor de la cámara y la galería de Revisión. Lo de abajo de la lista se alcanza con
  `ScrollToIndex` de la semántica: la lista precompone lo que sigue sin ubicarlo, y medir posiciones engaña.

## Los avisos

Gemelos de `apps/ios/MyPump/Avisos/CentroAvisos.swift` y `Acceso/OnboardingPermisos.swift`, en el paquete `avisos` (la hoja
de la primera vez, en `acceso/OnboardingPermisos.kt`). Lo puro (el próximo domingo, cuándo se registra el push, a dónde
lleva tocar un aviso) está en `:core:datos` (`Avisos.kt`), con sus tests en la JVM (`AgendaAvisosTest`).

- **Push (FCM).** El mismo proyecto de Firebase que la Capacitor (`mypump-663be`, `app/google-services.json`, que es
  público), con `firebase-messaging` 25.0.1 y el plugin `google-services` 4.4.4 (G4). Sin token hasta que haga falta
  (`firebase_messaging_auto_init_enabled = false`): con una cuenta, fuera de la demo y con permiso, la app lo pide y lo
  manda a `mypump_registrar_push` con `'android'` y la versión ("2.0.0 (100)"), solo si cambió el token o la cuenta
  (`RegistroPush`). Un token nuevo (`onNewToken`) se registra aunque la app esté cerrada, con la cuenta guardada. La
  instalación de Firebase sobrevive a la actualización: el token es el que registraba la Capacitor y el upsert deja una
  sola fila (NOT-02). La nativa nunca registra Web Push.
- **Mostrar.** push.py manda `notification` + `data{destino}`. Con la app en segundo plano lo muestra FCM con el canal, el
  ícono y el color del manifest; con la app abierta FCM no lo muestra y lo publica `ServicioPush` (NOT-04). Dos canales:
  "Mensajes de Mati" (el push y el domingo; es el `default_notification_channel_id`) y "Fin del descanso", aparte, para
  que apagar uno no apague a Mati. El ícono chico `ic_stat_mypump` es el torso de `public/icons/logo.svg` (el dibujo del
  ícono de la app) en un vector blanco, con el esmeralda del ícono como tinte.
- **Tocar un aviso** abre `MainActivity` con el `destino` en los extras: los propios llevan `mypump_aviso` y los que mostró
  FCM traen `google.message_id`. La raíz cambia de pestaña con el mismo `destino` de los links con `?scene=`; en un
  arranque en frío, cuando aparecen las pestañas.
- **El aviso del domingo** (`AvisoDomingo`): una alarma inexacta (`setWindow`: entre las 11:00 y las 11:10; con el teléfono
  en reposo profundo, cuando despierta) que al sonar publica y agenda la de la semana siguiente. La hora sale del reloj
  de ese domingo (cambio de hora, viajes). Se reagenda al abrir con una cuenta y con permiso, y con `BOOT_COMPLETED`,
  `MY_PACKAGE_REPLACED`, `TIMEZONE_CHANGED` y `TIME_SET` (`ReceptorAvisos`). Sin cuenta o en la demo no queda nada; al
  quedarse sin cuenta se cancela.
- **Lo de la Capacitor** (NOT-08). Sus alarmas 1001-1004 siguen en el sistema después de actualizar: se encuentran con el
  mismo PendingIntent que armaba su plugin (`TimedNotificationPublisher` explícito, el id como código, `FLAG_MUTABLE`
  desde Android 12) y se cancelan. Lo que publicó se saca por id sin etiqueta (los nuestros llevan la etiqueta `mypump`,
  también el 1002) y se borra su canal "Default". Corre al actualizar y en cada arranque con una cuenta.
- **El permiso** (Android 13+): la hoja de la primera vez (GEN-06) o Mis datos ("Activar notificaciones" o, si se negó dos
  veces, "Activar en Ajustes"). Android no dice si su hoja va a volver a salir: sale de
  `shouldShowRequestPermissionRationale` y de `mypump_notif_pedido` (la clave de la web, que trae la migración). En 12 o
  menos no hay hoja: apagadas, a Ajustes.
- **El fin del descanso (D8).** Al pasar a segundo plano con un descanso corriendo, una alarma `setAndAllowWhileIdle`
  (inexacta) para el fin; al volver se cancela y se saca el aviso. Mientras el proceso corre, el aviso sale desde el reloj
  del descanso, en el segundo, y el pitido de la app no suena encima (desde Android 14 el sistema congela la app a los
  pocos segundos de quedar atrás, y ahí avisa la alarma). **El desfase:** en el emulador (pantalla prendida, también con
  el reposo forzado) la alarma llegó entre 10 y 50 ms después del fin. Pero el sistema le da a una alarma inexacta una
  ventana del 75 % de lo que faltaba (en `dumpsys alarm`, un descanso de 2:28 tiene +1:51), y con la pantalla apagada
  Android 12+ puede despertar el teléfono recién al final de esa ventana: si nada lo despierta antes (la música, otra
  alarma), un descanso de 90 s puede avisar hasta un minuto tarde. Sin alarmas exactas no se puede asegurar más; las
  alternativas (encadenar alarmas de menos de 10 s, que salen exactas pero despiertan el teléfono seguido, o un servicio
  en primer plano con el reloj en una notificación fija) son una decisión de producto.
- **Pruebas.** Instrumentadas: `OnboardingUiTest` y `AvisosUiTest`. El permiso no se puede sacar desde una prueba
  (`pm revoke` mata el proceso, también el de la prueba): las que necesitan "sin permiso" lo fijan en `PermisoDePrueba`, y
  las que miran lo publicado lo dan de verdad con `pm grant`. El token de FCM es inventado (`AvisosDePrueba`): las pruebas
  nunca hablan con Firebase. El envío real de un push necesita un teléfono con Google Play y una cuenta.
## Chat y Progreso

Gemelas de `apps/ios/MyPump/Chat/ChatView.swift` y de `Progreso/` (CHA-01…06 y PRO-01…05), en los paquetes `chat` y
`progreso`. Lo que arman con los modelos de `:core` (los grupos y separadores del hilo, el contador, las secciones, las
sesiones del gráfico y los números y las fechas en es-AR) es puro y se prueba en la JVM (`TextosChatTest`, y
`VistaProgresoTest` con el historial grabado).

- **Chat** (`ChatPantalla`). La lista va con `reverseLayout` (lo nuevo abajo, como Mensajes) y arriba de todo el banner de
  Revisión, el encabezado (otro con el hilo vacío) y "Ver mensajes anteriores". Las burbujas van a los costados (D12),
  con la colita y la hora en la última del grupo, "enviando…" y "no salió → Reintentar". Mientras se ve, el chat está
  abierto (un `DisposableEffect`: sondeo cada 15 s y lo de Mati queda leído) y al entrar `marcarLeido()` baja el badge. El
  borrador vive en la pantalla (`rememberSaveable`): no lo pisa un mensaje que llega. CHA-02 cuenta los caracteres como
  iOS (`String.count`: los que se ven, un emoji es uno): el contador aparece pasados los 900, en rojo desde los 1000, y por
  encima Enviar se apaga. En la demo, Enviar apagado y el aviso.
- **Progreso** (`ProgresoPantalla`). Carga al abrir la pestaña solo si no hay tarjetas o faltó la red, y siempre con
  `ModeloApp.cargarProgreso` (el sustituto, PRO-02); tirar hacia abajo recarga. El detalle (`ProgresoDetalle`) es estado
  de la pestaña, como un ejercicio en Entreno: Atrás vuelve a la lista. Los gráficos son `Canvas`, sin librerías: la curva
  monótona de Salud (`curvaMonotona`), las marcas redondas de los ejes y, en el detalle, el valor de la sesión bajo el
  dedo.
- **El esqueleto** (`progreso/Esqueleto.kt`, lo usan los dos) respeta "Quitar animaciones". Limpia la semántica de lo que
  le sigue en la cadena de modificadores: la `testTag` va antes.
- **Pruebas** (`ui/ChatUiTest`, `ui/ProgresoUiTest` y las capturas de `ui/CapturasChatProgresoUiTest`). El chat corre con
  `ChatDePrueba` (`ui/ChatYProgresoDePrueba.kt`), puesto encima del `ServidorDePrueba` sin cambiarlo: un hilo con memoria
  que pagina, sondea y devuelve como fila real lo que manda la cola, salvo que el servidor lo rechace. "No salió" se
  prueba con la cola de verdad, pasándola a mano (`drenar`) en vez de esperar sus pausas. Progreso corre con el teléfono
  en Buenos Aires: las sesiones son días locales.

## Salud (Health Connect)

Gemela de la Salud de iOS (HealthKit), con Health Connect `connect-client` 1.1.0, la misma versión que compila la
Capacitor (OK de Mati, G4). SAL-01 a SAL-13 y APL-07.

- **La fuente** (`salud/FuenteHealthConnect`, la `FuenteSalud` de `:core:datos`): consulta Health Connect EXACTAMENTE como
  el plugin de la app de hoy (@capgo/capacitor-health 8.9.3, `HealthManager.kt` + `HealthPlugin.kt`): los mismos 22
  tipos, páginas de `min(límite, 500)` hasta juntar el límite (en registros; el recorte por muestras va al final), los
  baldes de 24 h desde la medianoche que manda el bridge, el sueño como UNA sesión con sus etapas, las basales como la
  tasa del día, los entrenos (100, del más nuevo al más viejo) con la distancia y las calorías de su rango, y los mismos
  textos de error (van al diagnóstico). Lo puro está en `PluginHealthConnect` y se prueba en la JVM
  (`src/test/…/salud`, con un doble de `ClienteHealthConnect`). La fuente que se graba es `health_connect` y la HRV va
  como rMSSD (`PlataformaSalud.ANDROID`).
- **El historial.** Sin `READ_HEALTH_DATA_HISTORY` Health Connect no da nada de más de 30 días, y no avisa. Como el
  bridge: se pide junto con el núcleo, el veredicto se guarda (`mypump_health_historial_ok`), se re-pregunta sin la hoja
  al empezar cada historial, y sin él la corrida es de 30 días y no queda hecha (`SincronizadorSalud`, `:core`).
- **La hoja de permisos** como llamada `suspend` desde cualquier lado (la hoja de la primera vez, Mis datos, la tarjeta):
  el contrato de Health Connect se registra en la `MainActivity` (`PermisosHealthConnect.registrar`) y el pedido en vuelo
  sobrevive a rotar. Sin una pantalla a la vista no abre nada y tira. El corte de `conectar(limiteMs)` no la cancela.
- **La fuente del sistema** se instala en el `init` del `ModeloAppViewModel`, ANTES de crear el `ModeloApp`
  (`ModeloSalud` la lee al crearse con la cuenta). Una prueba que puso un doble en `ModeloSalud.fuenteDelSistema` lo
  conserva.
- **Sin Health Connect** (`EstadoHealthConnect`, con `getSdkStatus`): si hay que instalarlo o actualizarlo (Android 9 a
  13), se ofrece desde Play con `healthconnect://onboarding`; si el teléfono no lo soporta, no se ofrece nada. Se vuelve a
  mirar cada vez que la app vuelve a la vista.
- **Pantallas.** Mis datos: la recuperación en una fila (el anillo), que abre el detalle, y "Conectar Health Connect" si
  no está conectada. El detalle (`SaludDetallePantalla`, tirar hacia abajo recarga): cómo se arma el score, sueño,
  corazón, actividad, otras señales y cuerpo (sin datos, la sección no se muestra), "Mostrarme el score" y Health
  Connect (Sincronizar, Reintentar, "Abrir Health Connect" si no llega nada). Las tarjetas de Recuperación y Salud de
  Revisión (`CardsSalud`) están listas y probadas sueltas (`CardsSaludTest`): Revisión todavía no existe. El detalle y
  el diagnóstico se abren en una ventana propia (`PantallaSuperpuesta`): Mis datos es una sola columna.
- **El diagnóstico (SAL-13):** 5 toques en el título "Health Connect" del detalle, o `?diag=health` en el link
  (`DiagnosticoSaludPedido`, lo abre la raíz). Muestra los permisos dados (Health Connect sí los informa), el historial,
  el último intento, el último rechazo de la base, cada tipo de 14 días y el sueño por noche y por fuente.
- **Textos sin "Apple"** (SAL-08): todos de `TextosSalud.ANDROID`; las pruebas de interfaz lo verifican.

**Permisos (APL-07).** Los del manifest de la Capacitor: 13 de lectura más el historial; nada en segundo plano ni de
escritura. Lo que la Capacitor saca va con `tools:node="remove"`. La justificación de Health Connect
(`androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE`) y el `activity-alias` ViewPermissionUsageActivity (con
`START_VIEW_PERMISSION_USAGE`) abren `privacidad.html` en una Custom Tab (`PoliticaSaludActivity`). El manifest MERGEADO
de release se verifica solo (`./gradlew :app:verificarPermisosSaludRelease`, colgado de `assembleRelease`,
`bundleRelease` y `check`; el informe queda en `app/build/reports/permisos-salud/release.txt`). Quedan:

- **release:** `READ_STEPS`, `READ_DISTANCE`, `READ_ACTIVE_CALORIES_BURNED`, `READ_BASAL_METABOLIC_RATE`,
  `READ_FLOORS_CLIMBED`, `READ_HEART_RATE`, `READ_RESTING_HEART_RATE`, `READ_HEART_RATE_VARIABILITY`, `READ_SLEEP`,
  `READ_RESPIRATORY_RATE`, `READ_WEIGHT`, `READ_BODY_FAT`, `READ_EXERCISE` y `READ_HEALTH_DATA_HISTORY` (más
  `INTERNET`, `ACCESS_NETWORK_STATE`, `POST_NOTIFICATIONS` y el `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` de androidx).
  Ningún `WRITE_`.
- **debug:** lo mismo más los 13 `WRITE_` de esos tipos (`src/debug/AndroidManifest.xml`), solo para sembrar el emulador.

**Pruebas.**

- JVM (`./gradlew :app:testDebugUnitTest`): la traducción y las consultas contra un doble de Health Connect, y la
  sincronización de `:core` con esta fuente (`SincronizacionHealthConnectTest`).
- Instrumentadas (`androidTest/…/salud` y `ui/SaludUiTest`): la hoja de verdad, la justificación, 40 días sembrados en el
  Health Connect del emulador (`SembradoSalud`) leídos por la fuente, la semana sincronizada, el historial de 30 y de 60,
  y las pantallas con un Health Connect de mentira.
- **El banco** (`HealthConnectRealTest.e_…`, gemelo de `scripts/nativa/salud-banco.sh`): sobre los mismos datos y el
  mismo "ahora", el `healthkit-bridge.js` de origin/main en un WebView con el plugin de VERDAD (su `HealthManager.kt`,
  copiado de `node_modules` al compilar las pruebas por la tarea `bancoSalud`; nunca se commitea) contra la nativa:
  mismas consultas, mismos lotes a `ingest_salud` e `ingest_entrenos`, mismo estado guardado. Sin `node_modules` se
  saltea. El informe queda en `/data/local/tmp/mypump-banco-salud.json` del emulador.
- **Contra la base real**, a mano y solo con `test-nativa-android`: sembrar el emulador sin borrar
  (`adb install` de los dos APK y `adb shell am instrument -w -e sembrarSalud 1 -e class
  com.pumpteam.mypump.salud.SembrarParaLaBaseTest#sembrar com.pumpteam.mypump.test/androidx.test.runner.AndroidJUnitRunner`),
  abrir la app con `python3 -I scripts/nativa/lanzar-emu.py <serial> revision`, Mis datos → "Conectar Health Connect"
  (no abre la hoja: los permisos ya están). Después, `-e sembrarSalud borrar` con `#borrar`.

**Lo que hay que saber.**

- Sacar un permiso dado (`pm revoke`) MATA el proceso de la app, que es el de las pruebas: en una corrida solo se dan, y
  `HealthConnectRealTest` va en orden (primero lo que necesita los permisos sin dar).
- Health Connect deja AFUERA de los agregados (pasos, calorías, distancia) lo que escribió una app que no está en su
  lista de prioridad, y a la lista se entra recibiendo la escritura POR LA HOJA (con `pm grant`, no). Por eso la siembra
  da la escritura tocando la hoja (`HojaHealthConnect`, con el `UiAutomation` de la instrumentación). A los clientes no
  les pasa: lo que lee la app lo escribió su reloj, que está en la lista.
- La primera vez Health Connect muestra su presentación ("Get started") antes de la hoja.
- La justificación no tiene la categoría `DEFAULT` (como la del plugin y el ejemplo de Google): Health Connect la abre
  por componente.

## La capa de datos

- **Hilos.** `ModeloApp` se usa desde un solo hilo, el principal (el ViewModel le pasa su `viewModelScope`), como el
  `@MainActor` de iOS: dos llamadas se intercalan solo en las esperas de red, y cada carga mira al volver si su token
  sigue vigente. La red y el JSON corren fuera del principal (`ClienteRpc`). La `Outbox` es un actor: todo su estado se
  toca en un despachador de a un hilo.
- **Persistencia (T1).** Archivos JSON por cuenta en `filesDir/MyPump/cuenta-<sha256(token)[:16]>/` (la misma carpeta que
  arma iOS), con escritura atómica: temporal + fsync + rename. Sin Room. `MyPump/` queda fuera del backup y del pase a
  otro teléfono (`res/xml/reglas_backup.xml` y `reglas_extraccion.xml`).
- **Token.** Cifrado con AES-GCM y una clave del Keystore, en `noBackupFilesDir/acceso.bin`. Sin la clave (o con el
  archivo roto) no hay token: la app pide el link. Su test usa el Keystore real y necesita un emulador o un teléfono:
  `./gradlew connectedDebugAndroidTest`.
- **Tests.** Los de la cola, el chat, las fotos, la demo y las regresiones de la revisión del 14-oct corren con dobles de
  transporte que contestan las respuestas REALES grabadas (`apps/shared/fixtures/`). `IntegracionTest` va contra el
  backend de verdad con la cuenta `test-nativa-android` (solo esa: las otras son de otros agentes), cuyo token se lee
  del registro privado dentro del test y nunca se imprime; sin el registro se saltea. La subida de una foto corre solo
  con `MYPUMP_PROBAR_FOTOS=1 ./gradlew :core:datos:test` (el servicio deja 12 por día).
- **Configuración.** `ConfigBackendProduccion.kt` se genera desde `public/js/config.js` con
  `node scripts/nativa/config-android.mjs`, como la de iOS.

## La migración del almacenamiento viejo

La 2.0.0 sale como update de la Capacitor y levanta lo que ella dejó en el `localStorage` de su WebView (gemelo de
`apps/ios/MyPump/Legado/`; la parte pura está en `:core:datos`: `EjecutorLegado`, `FaseRemotaLegado`,
`MigracionLegado`, `ServidorMigracion`).

- **Dónde está.** `LevelDbLegado` recorre `app_webview*` del directorio de datos y reconoce el leveldb por su forma
  (`Local Storage/leveldb` con su `CURRENT`). No hay rutas fijas: con el WebView 133 es `app_webview/Default/Local
  Storage/leveldb`, con los viejos `app_webview/Local Storage/leveldb`, y en un teléfono puede ser otra (la lección del
  TF-0 de iOS). La huella es `stat` de los archivos de datos, sin `LOCK` ni `LOG`.
- **Cómo se lee.** `LectorWebView` (`:app/legado`): un WebView oculto con `loadDataWithBaseURL` en `https://localhost`
  (el origen de la Capacitor; así no pasa por el service worker de la web) y sin red. `LecturaJs` firma cada valor en
  JavaScript (FNV-1a sobre `charCodeAt`, la de `FirmaValor`) y devuelve JSON en ASCII por tramos de 1 M caracteres: un
  surrogate suelto o un emoji partido entre tramos cruzan enteros. Timeout, reintento si muere el renderer, y un error
  tira (no es "vacío").
- **El arranque.** `ArranqueMigracion`: la Fase L corre ANTES de crear `ModeloApp` (el ViewModel expone el modelo
  cuando termina; mientras tanto se ve la marca). Después, con la primera carga con red: la palanca, la Fase R, la
  escritura de vuelta (una vez, con la app a la vista) y los recibos pendientes. Todo queda en
  `files/legado/registro.log` (sin tokens ni contenido) y en Logcat con la etiqueta `MyPumpLegado`.
- **Chromium baja el `localStorage` al disco en tandas** y las espacia según cuántas ya hizo el proceso: una escritura
  puede tardar en llegar al leveldb. Por eso la escritura de vuelta se confirma en el arranque siguiente (si no llegó, se
  repite).
- **Pruebas.** `ScriptsLegadoTest` y `LevelDbLegadoTest` en la JVM (los scripts corren con node);
  `LegadoWebViewTest` con el WebView de verdad (`./gradlew connectedDebugAndroidTest`); y la de punta a punta en el
  emulador, con la Capacitor de debug compilada de `android/` sin tocarlo (`scripts/nativa/compilar-capacitor-android.sh`)
  y la cuenta `test-nativa-android`: `scripts/nativa/emu-migracion.sh emulator-5554`.

## Vectores: la web es la fuente de verdad

Los tests de `:core:reglas` leen los MISMOS archivos que los de iOS y exigen igualdad total con lo que dio la web:

- `apps/shared/vectores/*.json` (públicos, en el repo).
- `~/Developer/nativa-evidencia/privado/vectores/*.json` (sacados de los planes y dietas reales; nunca se commitean). Si no
  están, esos tests se saltean (aparecen como `SKIPPED`).
- `apps/shared/fixtures/` (respuestas reales grabadas de las cuentas de prueba), `apps/shared/demo/`, `food-db.json` y
  `catalogo-ejercicios.json`.

Se regeneran corriendo las funciones reales de `origin/main` (o de `VECTORES_REF`):

```sh
node scripts/nativa/generar-vectores.mjs            # progresión, clave, porción casera, anclaje (y la demo)
node scripts/nativa/vectores-alimentos.mjs          # food-db.json, categoría y sustitutos de alimentos
node scripts/nativa/vectores-ejercicios.mjs         # catálogo y sustitutos de ejercicios (--sin-red: el catálogo del repo)
node scripts/nativa/colacion-android.mjs            # las tablas de ColacionEspanol.kt (localeCompare 'es' de node)
```

Después, `./gradlew test` acá y `swift test` en `apps/ios/MyPumpKit`.

## Lo que hay que saber

- **Lo que se le pide al modelo corre en el alcance de la app**, `LocalAlcanceApp.current` (el `viewModelScope`), nunca
  en el `rememberCoroutineScope()` de la pantalla. La bienvenida sale de la composición apenas la cuenta empieza a
  cargar: con su propio alcance cancelaba `entrar()` a la mitad y, con la red lenta, la app quedaba en la marca para
  siempre (`AccesoUiTest.entrarConLaRedLentaNoSeCortaCuandoLaBienvenidaSaleDePantalla`). El `Task {}` de iOS no depende
  de la vista.
- **Texto sin color.** `TemaMyPump` pone el `LocalContentColor`: Material solo lo pone adentro de un `Surface` o un
  `Scaffold`, y afuera (la bienvenida, "Sin conexión") el texto salía negro también en oscuro.
- **Dependencias que no están** (y no se agregan sin acordarlo): `ui-test-junit4`/`ui-test-manifest`,
  `navigation-compose` (la navegación es estado propio: `Navegacion`, con `rememberSaveable`) y `material-icons` (los
  íconos son vectores en `Iconos`).
- **Regex.** En Android `java.util.regex` es ICU y en la JVM de los tests es el de OpenJDK. `JsRegex` traduce el
  patrón de JS a construcciones que significan lo mismo en los dos (sin `\b`, `\w`, `\s`, `.` ni `$` del motor), y un
  test lo exige: si una regla nueva usa `Regex` de Kotlin directo, que sea con un patrón que no dependa del motor.
- **Orden alfabético.** `localeCompare(…, 'es')` es `ColacionEspanol`, no `java.text.Collator` (el de OpenJDK ignora el
  espacio y en Android depende de la versión de ICU del sistema).
- **Números.** Lo que la web imprime con `String(x)` va con `NumeroJs.texto` (80 y no 80.0; 1e-7 y no 1.0E-7).
- **Versiones.** AGP en la línea 8.13 como la Capacitor. El BOM de Compose queda en 2026.06.01: desde Compose 1.12 piden
  compileSdk 37 y AGP 9.1. Por lo mismo lifecycle queda en 2.10.0 y OkHttp en 5.4.0 (la 5.5.0 de Android pide
  compileSdk 37). Kotlin avisa que Gradle 8.14.3 va a dejar de alcanzar en Kotlin 2.5 (pide 8.14.4).
- **16 KB.** Los `.so` del APK (`androidx.graphics.path`, de Compose, y `datastore_shared_counter`, que trae Firebase)
  salen alineados a 16 KB: `zipalign -c -P 16 -v 4 app-debug.apk`.
