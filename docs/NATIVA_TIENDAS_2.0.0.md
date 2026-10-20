# MyPump 2.0.0 (nativa): material para las tiendas (G7)

Borrador para cuando toque enviar. Nada de esto se manda sin el OK de Mati (compuerta G7).

## App Store: notas para el revisor (en inglés, como las de 1.0.x)

```
WHAT IS NEW IN 2.0.0

MyPump was rebuilt as a fully native iOS app (SwiftUI) and is now called
Pump Team, the name of the coaching business (the seller, PUMP TEAM LLC).
Same features, same account system and same data: existing users update and
keep everything, without logging in again.

HOW TO TEST WITHOUT AN ACCOUNT

Pump Team has no signup: clients enter through a personal link their coach sends
them. For review, the app has a built-in demo.

1. Launch the app. On the welcome screen tap "Ver demo" ("See demo"). The app
   loads with sample data. No token, login or account is needed.
2. The five tabs are Entreno (training), Dieta (nutrition), Chat, Revisión
   (weekly check-in, progress photos and weight) and Progreso.
3. In the demo, Chat and the photo-based features are disabled because they
   need a real client account.

HEALTH DATA (HealthKit)

Pump Team only READS Health data (steps, sleep, resting heart rate, heart rate
variability, workouts and related types) to show the client and their coach
how they are recovering. It never writes to Health. The permission is asked
after a screen that explains why, and "Not now" skips it. Health data is shown
only to the client and their coach, and is never sold or used for advertising
or tracking.

NOT A MEDICAL DEVICE

Pump Team is not a regulated medical device: it does not diagnose, measure or
treat. It displays a training and nutrition plan authored by the client's
coach, who is a licensed physician, plus data the client enters.

SCIENTIFIC SOURCES (Guideline 1.4.1)

Every number in Dieta (calorie and macro targets) has a "Ver fuentes" link
right next to it, and Entreno, Dieta and the health section of Revisión end
with "Respaldo científico del plan". Both open the full list of sources
(ISSN, NASEM, ACSM, WHO, NIH, Argentine dietary guidelines) with links, plus a
medical disclaimer.

THIRD-PARTY AI (Guideline 5.1.2(i))

Clients never talk to an AI: every message in Chat comes from the coach. The
coach uses AI tools from OpenAI and Anthropic, through their APIs, to draft
chat replies and his weekly review of each plan; anything beyond a simple
acknowledgment is approved by him before it is sent. What these tools receive
is de-identified: before any text leaves our server, a model that runs on our
own server removes the client's name, phone, email and ID numbers (the weekly
review uses a meaningless label such as "c1"), and the name is put back on our
server, never by the provider. Depending on the message, that text can include
the client's plan summary and logs. Progress photos are never sent. A meal or
nutrition-label photo is sent alone, with no other data, to estimate its
nutrition values, and it is deleted right after. All of this is described in
the privacy policy, available inside the app (Revisión → Mis datos).

PRIVACY

Privacy policy and data deletion are available inside the app (Revisión →
Mis datos), and at https://app.mypumpteam.com/privacidad.html.

Contact: Salomon Matias Sancari - info@mypumpteam.com
```

**Antes de enviar, revisar:**
- **D7 se sacó el 14-oct (Mati): la IA no es algo que el cliente acepte.** En su lugar, a una IA de terceros llega todo
  desidentificado, sin nombre ni datos de contacto. Las notas de arriba lo dicen así desde el 15-oct: antes decían «No
  personal data reaches a third-party AI», que no era exacto (va contenido del plan y de los registros) y contradecía el
  renglón del informe semanal seudonimizado.
  - el chat va sin nombre ni datos de contacto, los tapa la IA local de la Mini (`pump-centinela/deid_chat.py`), tanto
    a Codex (borradores, `CHAT_IA_AUTO=0`) como a la sesión de Mensajes (`app_chat.py`, aprobación de Mati);
  - la foto del plato o de la etiqueta va sola, sin datos de la persona;
  - el informe semanal a Anthropic va seudonimizado.
  La política de privacidad lo dice así desde e171038 (publicada el 14-oct). **Riesgo que queda:** Apple podría pedir
  igual un permiso en la app. Si lo pide, la tabla `mypump_consentimiento_ia` (nativa_002) sigue en la base y la
  pantalla está en la historia de git (antes de 678c5a8).
- **iOS mínimo 17.** Hay que publicar antes la 1.0.12: es la última que van a poder instalar quienes tengan iOS 15 o 16.
- **Lanzamiento:** `release_type: MANUAL` con phased release de 7 días. Nunca con `cancel_previous_submissions`.

## App Store: "Novedades de esta versión" (es-419)

```
MyPump ahora se llama Pump Team y es una app nativa de iPhone: más rápida, más fluida y con el modo oscuro de tu teléfono.

• Entreno: cargá tus series con un toque, con descanso integrado y avisos aunque salgas de la app.
• Dieta: reemplazá alimentos con equivalentes reales y mirá la porción con la mano.
• Revisión: check, fotos y peso en un solo lugar.
• Funciona sin señal: lo que cargás se guarda y se sube solo.

Tu cuenta y tu historial siguen intactos: actualizá y seguí entrenando.
```

## App Store: la ficha con el nombre nuevo (con la 2.0.0, D21)

Lo de `APP_STORE_SUBMISSION.md` §1 y §4 que cambia. La descripción vieja decía «MyPump», «tu coach», «Marcá lo que
comés» (se fue con D10) y «Mi Día» (se fue con D17): describía cosas que la 2.0.0 ya no tiene.
- **Nombre:** `Pump Team`. El subtítulo («Entrenamiento y nutrición») y el texto promocional quedan igual.
- **Palabras clave** (93 de 100): «entrenamiento» ya está en el subtítulo y Apple lo indexa; en su lugar va «mypump»,
  para que el nombre viejo siga encontrando la app.
  ```
  mypump,gimnasio,rutina,fuerza,dieta,macros,fitness,nutricion,progreso,pesas,coach,musculacion
  ```
- **Descripción** (el bloque «Respaldo y aviso» del final viene de la 1.0.x, que lo pidió Apple por la 1.4.1):
  ```
  Pump Team es la app con la que seguís tu plan de entrenamiento y nutrición, hecho a medida por Mati, tu coach.

  • Entrenamiento guiado: tu rutina de la semana con series, repeticiones y descanso. Registrá cada carga a medida que entrenás, con cronómetro de descanso y tu "última vez" en cada ejercicio.
  • Nutrición: tu plan de comidas con macros y calorías. Elegí entre las opciones de cada comida, cambiá alimentos por equivalentes y sumá comidas libres con una foto o a mano.
  • Revisión semanal: contá cómo venís en 4 toques, cargá tu peso y subí tus fotos de progreso, que solo ve Mati.
  • Salud: si querés, tus datos de Apple Salud (pasos, sueño, pulso en reposo y variabilidad) para que Mati vea cómo venís recuperando.
  • Progreso: la evolución de tu fuerza y tus cargas en el tiempo.

  Pump Team es para clientes activos: Mati te da el acceso. ¿Querés verla por dentro? Tocá "Ver demo" en la pantalla de inicio.

  RESPALDO Y AVISO
  Las recomendaciones de nutrición y entrenamiento de Pump Team se apoyan en fuentes públicas y revisadas por pares (Mifflin-St Jeor, NASEM/Institute of Medicine, International Society of Sports Nutrition, American College of Sports Medicine, OMS, MedlinePlus/NIH y las Guías Alimentarias para la Población Argentina). Las referencias completas, con sus enlaces, están dentro de la app: Dieta, "Respaldo científico del plan".

  Pump Team es una herramienta de seguimiento, pensada para personas sanas. No es un dispositivo médico y no reemplaza la consulta con un profesional de la salud: consultá a tu médico antes de empezar o de cambiar tu plan.
  ```

## Capturas

La interfaz cambió entera, así que van capturas nuevas de 6,9" y 13", nunca de un cliente. Las sube Mati.

- **Las vigentes son del 15-oct a las 21:55**, con la marca de Pump Team (D21, el código del TestFlight 116): el verde
  del logo y el dorado en los récords. Están en `nativa-evidencia/tienda/20261015-pump-team`. Las de las 11:45
  (`20261015-114457`) y las anteriores quedaron viejas: tienen los colores de antes.
- `scripts/nativa/capturas-tienda-ios.sh` saca 20 capturas en los simuladores "Tienda 6,9" (iPhone 17 Pro Max, 1320×2868)
  y "Tienda 13" (iPad Pro 13" M5, 2064×2752), en claro y oscuro, con la barra a las 9:41 (con
  `APP=…/dd/mypump/Build/Products/Debug-iphonesimulator/MyPump.app`, la del último XCUITest).
  - Pantallas: Entreno, un ejercicio con 2 series, Dieta, Revisión con el check y Progreso con historial.
  - Datos: los bocetos, o sea la demo más las respuestas grabadas de la cuenta de prueba `test-nativa-real`. Nunca de
    un cliente.
  - `-captura YES` (solo DEBUG) saca el cartel "Estás viendo la demo".
  - La dieta de la demo ya no muestra el "−23 %" (f7aa713): eso también lo veía el revisor.
- Si cambia el diseño después de G1, se vuelven a sacar con el mismo script.

## Etiqueta de privacidad

Igual que hoy (salud y fitness, fotos, contenido del usuario e identificador, ligados al cliente, sin tracking). Se
suma **"Other Diagnostic Data"**: el recibo de la migración ya existe (`nativa_001` está aplicada). Son cuántas filas
hay por tabla y un UUID, sin contenido, ligado al cliente y sin tracking. Lo toca Mati en App Store Connect con el
envío (G7).

## Google Play

La 2.0.0 nativa sube como update de `com.pumpteam.mypump`.
- **El AAB.** Lo arma el workflow `android-nativa` de Codemagic (tag `nand-2.0.0-<versionCode>`, desde 101; la
  Capacitor publicada es el 18). Va firmado con `mypump-upload`, la misma clave de subida, y Play lo vuelve a firmar con
  la de la app.
- **La subida es manual:** no hay cuenta de servicio de Google Cloud.

### "Novedades de esta versión" (es-419, hasta 500 caracteres)

Las de la 2.0.1, con el nombre nuevo. Las de la 2.0.0, ya enviadas, empezaban «MyPump ahora es una app nativa de
Android» y decían «check, fotos, peso y hábitos» (los hábitos se fueron con D17).

```
MyPump ahora se llama Pump Team y es una app nativa de Android: más rápida, más fluida y con el modo oscuro de tu teléfono.

• Entreno: cargá tus series con un toque, con descanso integrado y aviso al terminar.
• Dieta: reemplazá alimentos con equivalentes reales y mirá la porción con la mano.
• Revisión: check, fotos y peso en un solo lugar.
• Funciona sin señal: lo que cargás se guarda y se sube solo.

Tu cuenta y tu historial siguen intactos: actualizá y seguí entrenando.
```

### Lo que hay que tocar en la consola (Mati, o yo con su sesión y su OK)

**Hecho el 15-oct y enviado a revisión a las 15:31**, con OK de Mati. Lo que se encontró en la consola:
- Data safety ya tenía «Otros mensajes desde la app» y «Dispositivo u otros IDs»: solo se sumó Diagnóstico (recopilado,
  no efímero, obligatorio, para funciones de la app, no compartido).
- La declaración de Health Connect ya tenía un texto por permiso, y el de frecuencia respiratoria estaba bien. El que
  mencionaba la saturación de oxígeno era un renglón propio de `READ_OXYGEN_SATURATION`. El formulario lo conserva
  aunque la app ya no pide el permiso, y no se puede borrar: su texto ahora dice que la app no lo usa desde la 1.0.7.
- Capturas: 8 por tipo de pantalla, que es el máximo. Van las 5 en claro y después Entreno, Dieta y Progreso en oscuro.
  Las de tablet de 10" también van en las de 7", que estaban vacías.

1. **Data safety** (`docs/PLAYSTORE_METADATA.md` tiene lo de hoy). Hay que sumar lo que la tabla no lista:
   - **Información y rendimiento de la app → Diagnóstico.** Es el recibo de la migración: cuántas filas hay por tabla
     y un UUID, sin contenido.
   - **ID de dispositivo u otros.** Es el token de FCM de los avisos; la 1.0.12 ya lo mandaba.
   - **Mensajes → Otros mensajes en la app.** Es el chat con el coach.

   Los tres son de funcionalidad de la app y no se comparten: la IA del chat procesa por cuenta de MyPump, sin el nombre.
   Si alguno ya figuraba, se deja como está.
2. **Health apps declaration.** Pide los mismos 14 permisos que la 1.0.12 (13 de lectura y el historial), sin escritura
   ni segundo plano, así que no cambia. Pero su texto todavía menciona «saturación de oxígeno», que se sacó el 28-ago:
   hay que corregir ese renglón. Queda «Frecuencia respiratoria: se compara contra la línea de base del propio usuario
   para detectar desvíos».
3. **Capturas: listas** en `nativa-evidencia/tienda-android/20261015-053511`, 5 pantallas en claro y en oscuro:
   - teléfono en 1080×1920 y tablet de 10" en 1440×2560;
   - Play no acepta un lado mayor que el doble del otro, y la pantalla entera del teléfono (1080×2400) lo es;
   - salen con `scripts/nativa/capturas-tienda-android.sh` (`CapturasTiendaTest`, solo con `-e tienda 1`), con las
     respuestas grabadas de `test-nativa-real`, nunca de un cliente.
4. **Producción por porcentaje.** Primero 10 %, después 50 % y 100 %, mirando cada día los recibos de la migración y los
   fallidos (`scripts/nativa/beta_diario.py`). El porcentaje se puede frenar, pero no volver atrás.
5. **Permisos que la app NO pide**, por si Play pregunta: alarmas exactas, servicios en primer plano, leer salud en
   segundo plano y escritura de salud. Las notificaciones (Android 13+) se piden en la hoja de la primera vez.

## Orden del lanzamiento (quién hace qué)

**Antes de enviar, en el iPhone de Mati con el último TestFlight** (unos 15 minutos):
1. Tocar su link de MyPump desde WhatsApp: abre la app y entra solo (ACC-01/09).
2. Conectar Salud de Apple desde Revisión → Mis datos y ver que lleguen sus datos (SAL-13).
3. Que le llegue un mensaje real de chat y que tocar el aviso abra el Chat.

**App Store (iPhone): enviada a revisión el 15-oct a las 21:56** (build 116, ver la bitácora de `NATIVA_ESTADO.md`).
1. Esperar que Apple publique la 1.0.12: es la última para iOS 15 y 16. Se mira con
   `curl -s "https://itunes.apple.com/lookup?bundleId=com.pumpteam.mypump&country=ar"`.
2. Mati, en App Store Connect:
   - la versión 2.0.0 con el último build del TestFlight (116 o posterior: el 116 trae la marca, D21);
   - el nombre **Pump Team** (Información de la app → Nombre). El 15-oct no había otra app con ese nombre en la
     tienda; el nombre solo se cambia con una versión nueva, así que va con la 2.0.0;
   - las capturas nuevas;
   - las notas de arriba;
   - «Other Diagnostic Data» en la etiqueta de privacidad.
3. G7: con el OK concreto de Mati, se envía con lanzamiento escalonado de 7 días. Nunca con
   `cancel_previous_submissions`.

**Google Play (Android): enviado a revisión el 15-oct a las 15:31.**
1. ✅ El AAB `nand-2.0.0-103` (versionCode 103, 15-oct 13:34), del artefacto de Codemagic, subido a mano a la versión
   de producción.
   - El 102 queda viejo: el 103 trae el arreglo de una pérdida de fotos.
   - El 101 no existe: falló el chequeo de APIs en Codemagic por el entorno.
   - Play aceptó la firma de subida. ACC-01 de Android (`pm get-app-links` con la app instalada desde Play) queda para
     cuando salga: hace falta un Android con la app de Play, el de Mati o un emulador donde él inicie sesión.
2. ✅ En Play Console: Data safety, la declaración de Health Connect corregida y las capturas de
   `tienda-android/20261015-053511`.
3. ⏳ G7: producción por porcentaje, 10 % → 50 % → 100 %, mirando cada día los recibos de la migración. La publicación
   administrada está apagada: el 10 % arranca solo cuando Google aprueba.

**Los OK que estaban esperando, hechos el 15-oct:** mini-vision con `gpt-5.6-sol` (DIE-14/15 ✅ con la IA real), el
push real de Android de punta a punta y las fotos de la web con la Mini caída (0620012, en `main`).

**Android 2.0.1 (104), después de la 2.0.0.** Mati (15-oct): la 2.0.0 sale igual al 10 %, y Android pasa al diseño del
iPhone. La 2.0.1 trae:
- el diseño del iPhone (ver la bitácora del 15-oct 17:00): la barra de pestañas flotante, la letra de la marca con su
  peso, el segmentado, el interruptor y el volver de iOS, y los cuadros de las fotos;
- los controles de iOS 26 (bitácora del 15-oct 17:15-19:45): las alertas, las hojas, la rueda de la hora, la pastilla de
  guardado y los menús;
- lo que Mati pidió el 15-oct para el iPhone (D16-D20): la barra siempre entera, sin Mi día, el peso en el check, el
  ejercicio abierto en la lista y «Ver cómo está mi cuerpo»;
- el arreglo de la foto que se perdía si el sistema cerraba la app con la cámara abierta (ca212de);
- el arreglo de la dieta que resucitaba un reemplazo al volver al plan mientras se traía la dieta (2d7adb9);
- la marca (D21): el verde del logo, el dorado en los récords, el nombre **Pump Team** debajo del ícono y el logo en el
  chat. En Play Console hay que cambiar también el título de la ficha a «Pump Team» y el ícono de 512 px, con el envío;
- lo que pidieron los clientes el 20-oct: los ajustes de porciones (D22), el descanso a la vista, con la cuenta
  regresiva fija con el teléfono bloqueado (D23), y los otros ejercicios del mismo músculo al sustituir (D24).

Se manda con capturas nuevas y con estas novedades (borrador, 458 de los 500 caracteres; quien venga de la 1.0.12 va directo a la
2.0.1):

```
Pump Team ahora se ve y se usa como en el iPhone.

• Dieta: ajustá una comida de hoy (más o menos calorías, gramos a mano o «Hoy no la como») y compensalo en la siguiente.
• Entreno: el descanso se ve grande al confirmar la serie y sigue con el teléfono bloqueado.
• Si la máquina está ocupada, al sustituir te ofrece otros ejercicios del mismo músculo.
• Funciona sin señal: lo que cargás se guarda y se sube solo.

Tu cuenta y tu historial siguen intactos.
```
La versión corta nueva deja que la palanca remota pida la 2.0.1 a quien tenga la 2.0.0 (`versionMinimaAndroid`). Es otro
envío a revisión de Google: se le pide el OK a Mati en el momento.

**iPhone 2.0.1, para el miércoles 21-oct** (Mati, 17-oct: «hacelo el miércoles… seguro sea con más correcciones»).
El TestFlight 117 trae solo la hoja única de Salud. El que se manda lleva además los ajustes de porciones (D22), el
descanso con Live Activity (D23), la foto con cámara y galería en un toque y los otros ejercicios del mismo músculo al
sustituir (D24). Para compilarlo hace falta el perfil App
Store de `com.pumpteam.mypump.descanso` (ver `NATIVA_ESTADO.md`). Tag `nios-2.0.1-118`.

Novedades (borrador):

```
• Dieta: ajustá una comida de hoy. Sumale o restale calorías y las porciones se recalculan solas; si te pasaste, lo compensás en la comida siguiente. También podés cambiar los gramos de cada alimento o marcar «Hoy no la como».
• Entreno: el descanso entre series se ve grande al confirmar la serie y, con el teléfono bloqueado, la cuenta regresiva sigue en la pantalla y en la Dynamic Island.
• Entreno: si la máquina está ocupada, al sustituir un ejercicio también te ofrece otros del mismo músculo, como fondos en lugar de la extensión en polea.
• Revisión: sacá la foto o elegila de la galería con un toque.
• Salud: arreglamos la conexión con Apple Salud cuando no das todos los permisos.
```

## Plan B: volver a la Capacitor si la 2.0.0 sale mal

No se sube nada de antemano. Una Capacitor 2.0.1 en TestFlight le ganaría a la nativa en la actualización automática
de TestFlight y le cambiaría la app a Mati en plena prueba. Lo que sí está probado: la Capacitor arriba de la nativa
funciona y no resucita nada (`sim-migracion.sh`, paso 5, 27/27 el 15-oct). Lo que se cargó en la nativa está en la
base. Lo que la web no lee, como las sustituciones de ejercicio de la `nativa_003`, queda guardado pero no se ve.

**iOS** (necesita el OK de Mati, como cualquier envío):
1. Pausar el lanzamiento escalonado de la 2.0.0 en App Store Connect.
2. En una rama desde `main` (la Capacitor vive en `ios/` y `public/`, que la nativa no toca), subir la versión en
   `ios/App/App.xcodeproj/project.pbxproj`, en las dos configuraciones:
   - `MARKETING_VERSION = 2.0.1`, que tiene que ser mayor que la 2.0.0;
   - `CURRENT_PROJECT_VERSION = 19` (del 19 al 99 son de la Capacitor, de 100 en adelante de la nativa).
3. Merge a `main` y tag `v2.0.1`. El workflow `ios-testflight` compila, sube y manda a revisión. Su
   `cancel_previous_submissions` es justo lo que hace falta acá. Si es urgente, pedir revisión acelerada.

**Android:**
1. Frenar el rollout de la nativa en Play Console. No se puede volver atrás, solo frenar.
2. En `android/app/build.gradle`: `versionCode` mayor que el último AAB nativo que se subió (si el último fue el 101,
   el 102 o más) y `versionName "2.0.1"`.
3. Tag `a2.0.1`: el workflow `android-play` arma el AAB, y se sube a mano a producción con rollout.

En los dos casos la app vieja arranca con lo suyo y lo que trae el servidor. Si después se vuelve a la nativa, la
migración se repite sola y el libro mayor evita duplicados (MIG-06).
