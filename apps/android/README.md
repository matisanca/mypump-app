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
| `:app` | Android, Compose + Material 3. La pantalla de marca, el `ModeloAppViewModel`, el token con el Keystore (`TokenEnKeystore`), las preferencias y las reglas de backup | `MyPump` |

Los `:core` no dependen de Android: sus tests corren en la JVM, en segundos y sin emulador.

## Compilar y probar

Hace falta el JDK 21 y el SDK de Android 36 (platform y build-tools):

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export ANDROID_HOME=~/Library/Android/sdk     # o sdk.dir en local.properties
cd apps/android
./gradlew test                  # todos los tests de :core (JUnit 5, en la JVM)
./gradlew :app:assembleDebug    # app/build/outputs/apk/debug/app-debug.apk
```

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

- **Regex.** En Android `java.util.regex` es ICU y en la JVM de los tests es el de OpenJDK. `JsRegex` traduce el
  patrón de JS a construcciones que significan lo mismo en los dos (sin `\b`, `\w`, `\s`, `.` ni `$` del motor), y un
  test lo exige: si una regla nueva usa `Regex` de Kotlin directo, que sea con un patrón que no dependa del motor.
- **Orden alfabético.** `localeCompare(…, 'es')` es `ColacionEspanol`, no `java.text.Collator` (el de OpenJDK ignora el
  espacio y en Android depende de la versión de ICU del sistema).
- **Números.** Lo que la web imprime con `String(x)` va con `NumeroJs.texto` (80 y no 80.0; 1e-7 y no 1.0E-7).
- **Versiones.** AGP en la línea 8.13 como la Capacitor. El BOM de Compose queda en 2026.06.01: desde Compose 1.12 piden
  compileSdk 37 y AGP 9.1. Por lo mismo lifecycle queda en 2.10.0 y OkHttp en 5.4.0 (la 5.5.0 de Android pide
  compileSdk 37). Kotlin avisa que Gradle 8.14.3 va a dejar de alcanzar en Kotlin 2.5 (pide 8.14.4).
- **16 KB.** El único `.so` del APK (`androidx.graphics.path`, de Compose) sale alineado a 16 KB:
  `zipalign -c -P 16 -v 4 app-debug.apk`.
