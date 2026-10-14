import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

/** La raíz del repo: la demo y el catálogo viven en `apps/shared/`, la fuente en la app de iOS. */
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

    packaging {
        // Los .so van sin comprimir y alineados a 16 KB (Play lo exige para Android 15+ con páginas de 16 KB). Es el
        // default de AGP 8.5.1+ con minSdk ≥ 23; queda escrito para que nadie lo cambie sin saber.
        jniLibs.useLegacyPackaging = false
    }
}

androidComponents {
    onVariants { variante ->
        variante.sources.res?.addGeneratedSourceDirectory(fuentesCompartidas, CopiarCompartido::salida)
        variante.sources.assets?.addGeneratedSourceDirectory(assetsCompartidos, CopiarCompartido::salida)
    }
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
    debugImplementation(libs.compose.ui.tooling)

    // El token con el Keystore de verdad: corre en un emulador o un teléfono (`connectedDebugAndroidTest`).
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.junit)
}
