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
    // «Tu guía»: el token de la cuenta de prueba puede llegar por variable (si no, el registro privado), y las dudas, que
    // se acumulan en el servidor (3200 caracteres por video, 30 para la videollamada), se escriben solo a pedido.
    environment("MYPUMP_TOKEN_GUIA", System.getenv("MYPUMP_TOKEN_GUIA") ?: "")
    environment("MYPUMP_PROBAR_DUDAS", System.getenv("MYPUMP_PROBAR_DUDAS") ?: "")
    // Las dudas en audio (entregas_019): cada corrida sube UN audio real al cliente de prueba (tope de 10), solo a pedido.
    environment("MYPUMP_PROBAR_AUDIO", System.getenv("MYPUMP_PROBAR_AUDIO") ?: "")
    environment("MYPUMP_AUDIO_M4A", System.getenv("MYPUMP_AUDIO_M4A") ?: "")
    // La integración contra el backend real no se cachea: lo que valida está afuera.
    outputs.upToDateWhen { false }
}

// El doble del servidor del gimnasio: solo para las pruebas (también lo usa :app en androidTest).
kotlin.sourceSets.named("test") { kotlin.srcDir("src/dobleGimnasio/kotlin"); kotlin.srcDir("src/dobleTecnica/kotlin"); kotlin.srcDir("src/dobleFotosInicio/kotlin") }
