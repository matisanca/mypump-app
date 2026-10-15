import com.android.build.api.artifact.SingleArtifact
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

/** La raíz del repo: la demo, el catálogo y las respuestas grabadas viven en `apps/shared/`, la fuente en la app de iOS. */
val raizRepo: File = rootDir.resolve("../..").canonicalFile

/**
 * Copia a una carpeta generada lo que es canónico fuera de `apps/android`, sin duplicarlo en el repo: así la demo y el
 * catálogo no se desfasan de los que usan iOS y los tests, y la fuente de la marca es la misma de iOS. `mapa` es
 * destino (dentro de la carpeta generada) → archivo de origen.
 */
abstract class CopiarCompartido : DefaultTask() {
    @get:Input
    abstract val mapa: MapProperty<String, String>

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val origenes: ConfigurableFileCollection

    @get:OutputDirectory
    abstract val salida: DirectoryProperty

    @TaskAction
    fun copiar() {
        val dir = salida.get().asFile
        dir.deleteRecursively()
        for ((destino, origen) in mapa.get()) {
            val desde = File(origen)
            check(desde.isFile) { "falta $origen (lo copia ${this.name})" }
            desde.copyTo(File(dir, destino), overwrite = true)
        }
    }
}

/**
 * Salud (APL-07): mira el manifest MERGEADO de release, el que va adentro del binario y el único que mira Google (el fuente
 * no alcanza: una librería puede meter un permiso aunque nuestro manifest no lo tenga, y así se coló la saturación en la
 * Capacitor). Falla si hay un permiso de salud de ESCRITURA, uno de lectura que no está en [permitidos] (o falta uno de
 * ellos: pedirlo tiraría SecurityException), o si falta la política de privacidad que exige Health Connect.
 */
abstract class VerificarPermisosSalud : DefaultTask() {
    @get:InputFile
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val manifest: RegularFileProperty

    @get:Input
    abstract val permitidos: ListProperty<String>

    @get:OutputFile
    abstract val informe: RegularFileProperty

    @TaskAction
    fun verificar() {
        val texto = manifest.get().asFile.readText()
        val salud = Regex("""<uses-permission[^>]*android:name="android\.permission\.health\.([A-Z_]+)"""")
            .findAll(texto).map { it.groupValues[1] }.toSortedSet()
        val problemas = buildList {
            salud.filter { it.startsWith("WRITE_") }.forEach { add("pide ESCRITURA de salud: $it (MyPump solo lee)") }
            (salud - permitidos.get().toSet()).filter { !it.startsWith("WRITE_") }.forEach { add("pide un permiso de salud de más: $it") }
            (permitidos.get().toSet() - salud).forEach { add("falta el permiso $it (pedirlo tiraría SecurityException)") }
            if (!texto.contains("androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE")) add("falta la justificación de los permisos (ACTION_SHOW_PERMISSIONS_RATIONALE)")
            if (!texto.contains("android.intent.category.HEALTH_PERMISSIONS") || !texto.contains("android.permission.START_VIEW_PERMISSION_USAGE")) {
                add("falta el activity-alias de VIEW_PERMISSION_USAGE (Android 14+)")
            }
        }
        informe.get().asFile.writeText(salud.joinToString("\n", postfix = "\n"))
        check(problemas.isEmpty()) { "Permisos de salud del manifest mergeado (${manifest.get().asFile}):\n  " + problemas.joinToString("\n  ") }
    }
}

fun CopiarCompartido.desde(vararg pares: Pair<String, String>) {
    val m = pares.associate { (destino, relativo) -> destino to raizRepo.resolve(relativo).path }
    mapa.set(m)
    origenes.from(m.values)
}

/** Archivo, la letra de la marca (OFL): la misma de iOS, para los títulos y los números grandes. */
val fuentesCompartidas = tasks.register<CopiarCompartido>("fuentesCompartidas") {
    desde("font/archivo.ttf" to "apps/ios/MyPump/Recursos/Fuentes/Archivo.ttf")
    salida.set(layout.buildDirectory.dir("generated/compartido/res"))
}

/** La demo de la web ("Ver demo", sin red ni cuenta), el catálogo de ejercicios para arrancar sin red y la licencia de la fuente. */
val assetsCompartidos = tasks.register<CopiarCompartido>("assetsCompartidos") {
    desde(
        "demo/rutina.json" to "apps/shared/demo/rutina.json",
        "demo/dieta.json" to "apps/shared/demo/dieta.json",
        "bases/catalogo-ejercicios.json" to "apps/shared/catalogo-ejercicios.json",
        "licencias/Archivo-OFL.txt" to "apps/ios/MyPump/Recursos/Fuentes/Archivo-OFL.txt",
    )
    salida.set(layout.buildDirectory.dir("generated/compartido/assets"))
}

android {
    // Los mismos que la app Capacitor (android/app/build.gradle): es una actualización de la misma app en Play, no
    // una app nueva. Cambiar el applicationId sería publicar otra app y perder a todos los clientes.
    namespace = "com.pumpteam.mypump"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.pumpteam.mypump"
        // 26 como la Capacitor: Health Connect ni existe por debajo de Android 9, y con menos el merger de manifests
        // ya fallaba por las librerías de salud.
        minSdk = 26
        targetSdk = 36
        // La Capacitor publicada es 18 / 1.0.12. La nativa arranca en 100 / 2.0.0: un versionCode no se puede reusar
        // en Play, y el salto deja lugar a arreglos de la 1.0.x mientras la 2.0.0 está en prueba.
        versionCode = 100
        versionName = "2.0.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    sourceSets {
        // Las pruebas de interfaz contestan con las respuestas REALES grabadas de las cuentas de prueba (las mismas de los
        // tests de :core y de iOS). Van solo en el APK de pruebas.
        getByName("androidTest").assets.srcDir(raizRepo.resolve("apps/shared/fixtures"))
    }

    packaging {
        // Los .so van sin comprimir y alineados a 16 KB (Play lo exige para Android 15+ con páginas de 16 KB). Es el
        // default de AGP 8.5.1+ con minSdk ≥ 23; queda escrito para que nadie lo cambie sin saber.
        jniLibs.useLegacyPackaging = false
    }

    // Salud: las pruebas de la traducción de Health Connect corren en la JVM con JUnit 5, como las de :core.
    testOptions {
        unitTests.all {
            it.useJUnitPlatform()
            it.testLogging { events("passed", "skipped", "failed") }
        }
    }
}

androidComponents {
    onVariants { variante ->
        variante.sources.res?.addGeneratedSourceDirectory(fuentesCompartidas, CopiarCompartido::salida)
        variante.sources.assets?.addGeneratedSourceDirectory(assetsCompartidos, CopiarCompartido::salida)
    }
}

// Salud: los 13 permisos de lectura de Health Connect que deja la Capacitor, más el historial (ver el manifest). El de
// release se verifica en cada assembleRelease/bundleRelease y en `check`; el informe queda en
// build/reports/permisos-salud/release.txt.
val permisosSalud = listOf(
    "READ_STEPS", "READ_DISTANCE", "READ_ACTIVE_CALORIES_BURNED", "READ_BASAL_METABOLIC_RATE", "READ_FLOORS_CLIMBED",
    "READ_HEART_RATE", "READ_RESTING_HEART_RATE", "READ_HEART_RATE_VARIABILITY", "READ_SLEEP", "READ_RESPIRATORY_RATE",
    "READ_WEIGHT", "READ_BODY_FAT", "READ_EXERCISE", "READ_HEALTH_DATA_HISTORY",
)
androidComponents {
    onVariants(selector().withBuildType("release")) { variante ->
        val sufijo = variante.name.replaceFirstChar { it.uppercase() }
        tasks.register<VerificarPermisosSalud>("verificarPermisosSalud$sufijo") {
            manifest.set(variante.artifacts.get(SingleArtifact.MERGED_MANIFEST))
            permitidos.set(permisosSalud)
            informe.set(layout.buildDirectory.file("reports/permisos-salud/${variante.name}.txt"))
        }
    }
}
tasks.matching { it.name in listOf("assembleRelease", "bundleRelease", "check") }.configureEach {
    dependsOn("verificarPermisosSaludRelease")
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":core:datos"))

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.androidx.browser)
    debugImplementation(libs.compose.ui.tooling)

    // Salud: Health Connect (solo lectura; ver el manifest). La traducción de sus registros se prueba en la JVM
    // (`src/test`, JUnit 5 como los de :core) con dobles del cliente.
    implementation(libs.health.connect.client)
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)

    // El token con el Keystore de verdad y las pruebas de interfaz: corren en un emulador o un teléfono
    // (`connectedDebugAndroidTest`). Las de interfaz usan el arnés propio (androidTest/…/ui/Pantalla.kt); desde el 14-oct
    // está también `ui-test-junit4` (OK de Mati) para las nuevas con `createAndroidComposeRule`.
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.junit)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
    debugImplementation(libs.compose.ui.test.manifest)
}
