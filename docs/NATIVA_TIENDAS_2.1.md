# MyPump 2.1: lo que cambia para las tiendas

Material para las fichas de la 2.1 (tanda 2 de `NATIVA_TANDAS_2_A_4.md`). Cada parte suma su sección.

## Código de barras en Dieta (S3)

**Qué hace.** En «Agregar alimento» aparece «Escanear código de barras». El escáner lee el código del envase, la app lo
busca en [Open Food Facts](https://world.openfoodfacts.org) y abre la misma hoja de cantidad que la búsqueda. Si el
producto no está o le faltan datos, ofrece cargarlo a mano (con el código) o sacarle una foto a la etiqueta. Esa foto
usa la misma lectura con IA que ya existe. Lo que se busca queda guardado en el teléfono, por código y por cuenta: un
producto encontrado vale 30 días y uno que no está, un día. Un alimento propio creado desde un código no vence, así que
al volver a escanearlo aparece directo.

**Qué viaja.** A Open Food Facts le llega **solo el código de barras**, en un `GET` público sin clave y con el
User-Agent «PumpTeam/<versión> (iOS|Android)», como pide la API. No viaja el token, ni el nombre, ni nada de la cuenta.
La respuesta se valida como un alimento propio y lo que no cierra se descarta. Ejemplos: más de 950 kcal o más de 110 g de
macros cada 100 g, o kcal que no cierran con las macros.

### iOS

- **Escáner:** VisionKit (`DataScannerViewController`) con EAN-13, EAN-8 y UPC-E. UPC-A llega como EAN-13. Con un iPhone
  que no lo soporta (anterior al A12), o sin permiso de cámara, aparece un aviso que manda a buscar por nombre. Sin
  permiso, el aviso también ofrece «Abrir Ajustes».
- **Permiso de cámara:** `NSCameraUsageDescription` ya existía por las fotos. El texto ahora nombra el escaneo:
  «…fotos de tus platos o de etiquetas nutricionales, o escanear el código de barras de un alimento…».
- **Etiqueta de privacidad / PrivacyInfo.xcprivacy:** no cambian. El código de barras de un producto no es un dato del
  usuario, y no se manda nada que lo identifique. Open Food Facts no es un SDK: es un pedido HTTP sin rastreo.
- **Notas para el revisor (si pregunta):** *"The barcode scanner in Diet → Add food looks up the scanned EAN/UPC in the
  public Open Food Facts database. Only the barcode number is sent; no account data. Camera access is only used while
  the scanner is open."*

### Android

- **Escáner:** el **Google code scanner** (`com.google.android.gms:play-services-code-scanner` 16.1.0). Lo elegimos
  sobre ML Kit con CameraX porque **no pide el permiso de cámara**: abre su propia pantalla (de Play Services) y le
  devuelve a la app solo el número. El manifest sigue con `CAMERA` en `tools:node="remove"` y el manifest final de release
  no suma ningún permiso. El modelo no va empaquetado: lo baja Play Services al instalar la app (meta-data
  `com.google.mlkit.vision.DEPENDENCIES = barcode_ui`). Sin Play Services, o mientras se baja, aparece un aviso y queda
  la búsqueda por nombre.
- **Data safety:** no cambia. No se recopila ni se comparte un dato nuevo del usuario: el código de un producto no es un
  dato personal y no va asociado a la cuenta.
- **Permisos:** ninguno nuevo.

### Datos (para la ficha, el brief y una 2.0.3)

- El agregado escaneado se guarda en `agregados` con `"origen": "barras"` y `"codigo": "<EAN>"`. Uno propio creado desde
  un código va con `"origen": "propio"` y el mismo `"codigo"`.
- **Compatibilidad con la 2.0.3:** su decodificado lee un origen desconocido como `base` y no descarta el agregado (iOS:
  `try? decode(Origen) ?? .base`; Android: `?: Origen.BASE`). Las macros y la cantidad se ven igual. Si esa versión
  reescribe el día, se pierden el origen y el código, pero no el agregado. Por eso no hizo falta caer en `"propio"`.
- El `resumen` que lee la ficha no cambia.
- Las reglas (normalizar el código y su dígito de control, UPC-E a EAN-13, el mapeo de Open Food Facts con el nombre en
  español primero y la marca entre paréntesis, kJ → kcal y la validación) están en el kit: `CodigoBarras` en iOS y en
  Android. Los vectores compartidos están en `apps/shared/vectores/barras_off.json`: 12 respuestas reales de productos
  argentinos (yogures, leches, galletitas, bizcochos, barras de cereal, turrón y alfajor) y 20 casos sintéticos.

## Novedades de la 2.1.0 (release notes, es-419)

La 2.1.0 es la versión unificada: suma todo lo de la 2.0.3 (que en Android nunca salió y en iOS está en revisión como
121), la tanda 2 (Salud, volumen por músculo, código de barras) y la app del Apple Watch. El conteo de reps del reloj
(antes «modo calibración», oculto) **viene prendido para todos** desde el 4-nov (decisión de Mati) y se anuncia; se
apaga en Mis datos → Conteo de reps. «Tu guía» entra en las dos (texto de MYPUMP PRO).

Qué cubre cada línea: Salud reemplaza a Progreso y trae recuperación (con confianza y motivo cuando falta el dato),
fuerza y cuerpo, más el volumen por músculo; Entreno trae la preparación (E1), el descanso por ejercicio y el aviso de
récord; Dieta trae los ajustes de comidas (agregar alimentos, tocar la cantidad) y el código de barras; el aviso local de
revisión ya no sale con la semana completa.

### App Store (1279 de 4000 caracteres)

```
Pump Team 2.1 llega al Apple Watch y estrena la pestaña Salud.

• Tu guía: los videos que tu entrenador preparó para vos antes de empezar, sobre la app, tu entrenamiento, tu alimentación y tu suplementación. Ves tu avance, retomás donde quedaste y le dejás tus dudas para la videollamada.
• Suplementación: una pestaña con tu suplementación del día por momento, el porqué de cada uno y lo que dejás de tomar.
• Apple Watch: tu rutina del día en la muñeca. Elegí el día, cargá reps y kg con la corona, el descanso te avisa con una vibración y ves tu frecuencia cardíaca y calorías en vivo. Al terminar cada serie, el reloj cuenta tus repeticiones y te las propone: confirmalas o corregilas con la corona. Si dejás el iPhone en el bolso, lo que cargás se guarda y se pasa solo después. Con complicaciones para la esfera.
• Salud: recuperación (con qué tan confiable es el dato), fuerza, cuerpo y volumen por músculo, todo en un lugar.
• Entreno: preparación antes de la primera serie, descanso propio por ejercicio y aviso cuando hacés un récord.
• Dieta: sumá alimentos a una comida, tocá la cantidad para cambiarla y escaneá el código de barras del envase.
• El aviso de revisión no sale si ya cargaste el peso y las fotos de la semana.

Tu cuenta y tu historial siguen intactos.
```

### Google Play (494 de 500 caracteres; sin reloj)

```
Pump Team 2.1 estrena Tu guía y la pestaña Salud.

• Tu guía: los videos de tu entrenador para empezar, con tu avance y un lugar para dejar tus dudas.
• Suplementación: tu día por momento y el porqué de cada uno.
• Salud: recuperación, fuerza, cuerpo y volumen por músculo.
• Entreno: preparación antes de la primera serie, descanso por ejercicio y aviso de récord.
• Dieta: sumá alimentos a una comida, tocá la cantidad y escaneá el código de barras.

Tu cuenta y tu historial siguen intactos.
```

## Apple Watch en App Store Connect

La app del reloj va **embebida** en el IPA del iPhone (`MyPump.app/Watch/MyPumpWatch.app` con las complicaciones
adentro), con `WKCompanionAppBundleIdentifier = com.pumpteam.mypump` y `WKRunsIndependentlyOfCompanionApp = NO`: no es
una app aparte, se instala desde el iPhone. watchOS 10 o superior. Versión y build iguales a los del iPhone (Codemagic
los pisa a nivel proyecto con el tag). App IDs, App Group y perfiles ya los creó Mati (ver `NATIVA_TANDAS_2_A_4.md`).

### Capturas del reloj (obligatorias)

Si el build trae una app de watchOS, App Store Connect pide capturas de Apple Watch en la ficha de la versión (en
«Vista previa y capturas de pantalla», la pestaña «Apple Watch»). Sin ellas no deja mandar a revisión. Van de 1 a 10, de
la pantalla sola (sin el marco del reloj) y **todas del mismo tamaño**; con un solo tamaño alcanza, Apple lo usa para
los demás modelos.

Tamaños que acepta, según la documentación de Apple que conozco (a junio de 2026):

| Reloj | Píxeles |
|---|---|
| Ultra 3 (49 mm) | 422 × 514 (*no estoy seguro: confirmarlo en la página de especificaciones de capturas*) |
| Ultra y Ultra 2 (49 mm) | 410 × 502 |
| **Series 10 y 11 (46 mm)** | **416 × 496** ← las que generamos |
| Series 7, 8 y 9 (45 mm) | 396 × 484 |
| Series 10 y 11 (42 mm) | 374 × 446 |
| Series 4 a 6 y SE (44 mm) | 368 × 448 |
| Series 7, 8 y 9 (41 mm) | 352 × 430 |
| Series 4 a 6 y SE (40 mm) | 324 × 394 |
| Series 3 (42 mm) | 312 × 390 |

Si App Store Connect rechaza un tamaño, el mensaje dice cuáles acepta: mandar el de 416 × 496, que es el de la
Series 11 de 46 mm y figura en la lista.

Las capturas están fuera del repo, en `~/Developer/nativa-evidencia/tiendas-2.1/reloj/` (simulador Series 11 46 mm,
watchOS 26.5, `-demo`, semana de muestra sin datos reales), en este orden:

1. `01-dias.png`: «Elegí el día» (Empuje, Tirón, Piernas).
2. `02-lista.png`: la rutina del día con «Empezar».
3. `03-ejercicio.png`: Press banca, serie 1 de 3, reps y kg para la corona.
4. `04-descanso.png`: el descanso con el anillo, −15, +15 y saltar.
5. `05-resumen.png`: «Entreno terminado» con el récord. Dice «Tiempo 0 min» porque la demo termina al instante: usarla
   solo si no molesta, o mandar las 4 primeras.

La hora de arriba dice 2:00 y no 9:41: el simulador de watchOS no soporta `simctl status_bar override` («Operation not
supported»). Apple no lo exige. No hay capturas del modo calibración.

### Notas para el revisor (App Review Information → Notes, en inglés)

```
Apple Watch app (new in 2.1.0): the watch app shows the workout of the day from the iPhone app, lets the user pick a
day, log reps and weight with the Digital Crown, and runs the rest timer with haptics. It works without the iPhone
nearby and syncs over WatchConnectivity when it is back.

HealthKit on Apple Watch: the watch app reads heart rate and active energy only to show them live during the workout
(HKWorkoutSession + HKLiveWorkoutBuilder). It requests write access to workouts only because an HKWorkoutSession
requires it; when the user ends the session, the workout is discarded (discardWorkout) and is never saved to Health.
Live heart rate and calories stay on the watch: they are not sent to the iPhone app or to our servers.

Motion (NSMotionUsageDescription): the watch app counts reps. During each set it reads the accelerometer and gyroscope
(Core Motion) and, when the set ends, proposes the count, which the user confirms or corrects with the Digital Crown.
It is on by default and can be turned off in the iPhone app (Mis datos -> Conteo de reps). The motion recordings stay on
the watch and the iPhone and are only shared if the user exports them; nothing is sent to our servers. In the demo the
counter is also on, and its recordings are discarded.

Supplements tab (new in 2.1.0): a read-only list of the user's natural supplements (no prescription drugs) as set by
their coach, grouped by time of day. It only appears when the coach has loaded supplements for that user; the demo
includes a sample. When it is shown, Health ("Salud") moves from the tab bar to the heart button at the top of the
"Revisión" tab.

To test: no sign-in is needed. On the iPhone, tap "Ver demo" on the welcome screen; then open the Pump Team app on the
paired Apple Watch, choose a day and tap "Empezar". After each set the watch proposes the rep count. The on/off switch
(Mis datos -> Conteo de reps) only appears with a real coaching account and a paired watch, not in the demo.
```

El conteo de reps ya no es oculto (4-nov), así que la línea de Motion describe una función pública. El revisor no
inicia sesión: usa la demo integrada («Ver demo»), con la rutina de muestra; «Tu guía» le aparece solo si va en las
muestras de la demo (la suma MYPUMP PRO).

### Etiqueta de privacidad: no cambia

Verificado en el código (`MyPumpWatch/EntrenoSalud.swift`, `EstadoReloj.swift`, `MyPumpReloj/Protocolo.swift`):

- La FC y las calorías en vivo (`SaludEntreno`) solo se muestran en el reloj y en su resumen (`ResumenReloj`), que se
  queda en el reloj. El protocolo con el iPhone (`pedirRutina`, `pedirDia`, `rutina`, `eventos`, `acuse`, `sinRutina`,
  `incompatible`) no lleva FC ni calorías, y el reloj no hace pedidos de red propios.
- El entreno se descarta (`discardWorkout`). Las muestras de FC y calorías que el reloj mide quedan en Salud como con
  cualquier uso del reloj; si el alumno conectó Salud en el iPhone, la sincronización de siempre (`SincronizadorSalud`)
  ya leía esos tipos. Eso está declarado desde la 2.0: **Health & Fitness, vinculado al usuario, sin tracking, App
  Functionality** (`docs/APP_STORE_SUBMISSION.md`).
- La grabación de calibración (`.mpcal`) pasa del reloj al iPhone por `transferFile` y solo sale si el usuario la
  exporta con `ShareLink`.

Conclusión: no hay tipo de dato nuevo; la etiqueta queda como está. Google Play (Data safety) tampoco cambia.

### Permisos y textos (`apps/ios/MyPumpWatch-Info.plist`)

| Clave | Texto | Cuándo se pide |
|---|---|---|
| `NSHealthShareUsageDescription` | «Pump Team muestra tu frecuencia cardíaca y tus calorías activas mientras entrenás.» | Al empezar el primer entreno en el reloj |
| `NSHealthUpdateUsageDescription` | «Pump Team necesita este permiso para medir tu entreno en vivo. No guardamos el entreno en Salud; el reloj registra tu frecuencia cardíaca y tus calorías activas como siempre.» | Junto con el anterior (escritura de `workoutType`, solo para abrir la sesión) |
| `NSMotionUsageDescription` | «Con el modo calibración prendido, Pump Team usa el movimiento del reloj durante cada serie…» | Solo con el modo calibración prendido para esa cuenta |
| `WKBackgroundModes` = `workout-processing` | (sin texto) | La sesión sigue con la muñeca baja: FC, calorías y la háptica del descanso |

Entitlements del reloj (`MyPumpWatch.entitlements`): HealthKit y el App Group `group.com.pumpteam.mypump.reloj`; las
complicaciones, solo el App Group. Sin HealthKit clinical records ni background delivery.

## Lista de chequeo para el envío (4/11)

Antes de las dos tiendas: verdes las corridas de UI de la unificada, la revisión opus de la combinación y el OK de Mati
para los tags. Nada se manda sin ese OK.

### App Store (iOS 2.1.0, build ≥ 126)

| # | Paso | Quién |
|---|---|---|
| 1 | OK para el tag `nios-2.1.0-<build>` sobre la punta de `nativa-202` (nadie más tagea `v*`) | Mati |
| 2 | Crear y empujar el tag; Codemagic arma el IPA con el reloj y lo sube a TestFlight. Mirar que «Verificar la firma» pase con los tres perfiles | Yo (terminal) |
| 3 | Probar el build de TestFlight en el iPhone y en el reloj: elegir día, una serie con la corona, el descanso vibra, FC en vivo | Mati (tiene el reloj) |
| 4 | Decidir qué pasa con la 2.0.3 (121) en revisión: dejarla salir o retirarla («Remove from review») para mandar la 2.1.0 | Mati decide; el clic lo puedo hacer yo en Chrome |
| 5 | En App Store Connect, «+ Versión» 2.1.0 y elegir el build | Yo en Chrome |
| 6 | Pegar las novedades de arriba (es-419) | Yo en Chrome |
| 7 | Subir las capturas del reloj (pestaña Apple Watch, 416 × 496). Opcional: capturas nuevas del iPhone con la pestaña Salud | Yo en Chrome (los archivos los sube Chrome desde `nativa-evidencia`) |
| 8 | Pegar las notas para el revisor; revisar la cuenta de demo con rutina | Yo en Chrome; Mati decide lo de Motion |
| 9 | Etiqueta de privacidad: confirmar que sigue igual (no hace falta tocarla) | Yo en Chrome |
| 10 | Publicación: automática al aprobarse, como la 2.0.2 (o manual si Mati quiere avisar a los alumnos antes) | Mati decide |
| 11 | «Enviar a revisión» | Mati da el OK; el clic, con ese OK, yo |

### Google Play (Android 2.1.0, `nand-2.1.0-106`)

| # | Paso | Quién |
|---|---|---|
| 1 | OK para el tag `nand-2.1.0-106` | Mati |
| 2 | Crear y empujar el tag; Codemagic arma el AAB | Yo (terminal) |
| 3 | Probar el build de prueba interna en un Android (Salud, código de barras con Play Services, preparación, récord) | Mati |
| 4 | En Play Console, Producción → «Crear versión» y subir el AAB (si pesa, en trozos como la 2.0.2) | Yo en Chrome |
| 5 | Pegar las novedades de Play (es-419, 494/500) | Yo en Chrome |
| 6 | Data safety y permisos: sin cambios (el Google code scanner no pide cámara) | Yo verifico en Chrome |
| 7 | Porcentaje del lanzamiento (la 2.0.2 fue al 100 %) | Mati decide |
| 8 | «Enviar a revisión» | Mati da el OK; el clic, con ese OK, yo |

Al terminar: bitácora en `NATIVA_ESTADO.md` con tags, builds y el estado de cada tienda.
