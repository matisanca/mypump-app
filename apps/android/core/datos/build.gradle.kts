// La capa de datos (MyPumpDatos en iOS): cliente RPC con OkHttp, la cola de escrituras, los archivos por cuenta y los
// modelos de estado (StateFlow) que usa el ViewModel. Kotlin/JVM puro: lo que necesita Android (Keystore, Context,
// SharedPreferences) va en :app detrás de las interfaces de acá.
plugins {
    alias(libs.plugins.kotlin.jvm)
}

dependencies {
    api(project(":core:modelos"))
    api(project(":core:reglas"))
    api(libs.kotlinx.coroutines.core)
    implementation(libs.okhttp)

    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.withType<Test>().configureEach {
    // La subida de fotos de la integración corre solo a pedido (el servicio deja 12 por día por cliente).
    environment("MYPUMP_PROBAR_FOTOS", System.getenv("MYPUMP_PROBAR_FOTOS") ?: "")
    // La integración contra el backend real no se cachea: lo que valida está afuera.
    outputs.upToDateWhen { false }
}
