// La capa de datos (cliente RPC, cola offline, caché): por ahora solo la clasificación de errores del contrato.
// Kotlin/JVM puro mientras se pueda; lo que necesite Android (Keystore, WorkManager) va en :app.
plugins {
    alias(libs.plugins.kotlin.jvm)
}

dependencies {
    api(project(":core:modelos"))
    api(project(":core:reglas"))

    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}
