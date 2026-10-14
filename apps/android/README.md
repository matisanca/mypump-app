# MyPump nativa — Android

La app nativa de Android (Kotlin + Jetpack Compose) que reemplaza a la Capacitor de `android/` como actualización de la
misma app en Play: mismo `com.pumpteam.mypump`, misma `.MainActivity`, mismo link del coach. Arranca en
`versionCode 100` / `2.0.0`. El plan es la Fase 5 de `~/.claude/plans/planifica-la-ejecucion-de-atomic-crescent.md`; el
estado de todo, `docs/NATIVA_ESTADO.md`.

## Módulos

| Módulo | Qué es | Gemelo en iOS |
|---|---|---|
| `:core:modelos` | Kotlin/JVM. Las filas de las RPC y lo que publica el Cerebro, con decodificación tolerante (`ValorJson`, `NumeroJs`) | `MyPumpModelos` |
| `:core:reglas` | Kotlin/JVM. Las reglas portadas de la web: progresión, clave de ejercicio, porción casera, anclaje e hidratación de swaps, categoría y sustitución de alimentos, sustitución de ejercicios, alimento propio, comida libre, progreso, peso, check y fotos de Revisión. `JsRegex` y `ColacionEspanol` dan la semántica de JS | `MyPumpReglas` |
| `:core:datos` | Kotlin/JVM. Por ahora solo la clasificación de errores del contrato | `MyPumpDatos` |
| `:app` | Android, Compose + Material 3. Por ahora, la pantalla de marca | `MyPump` |

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
  compileSdk 37 y AGP 9.1. Kotlin avisa que Gradle 8.14.3 va a dejar de alcanzar en Kotlin 2.5 (pide 8.14.4).
- **16 KB.** El único `.so` del APK (`androidx.graphics.path`, de Compose) sale alineado a 16 KB:
  `zipalign -c -P 16 -v 4 app-debug.apk`.
