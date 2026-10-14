// Las filas que devuelve el backend y lo que publica el Cerebro, con la decodificación tolerante de MyPumpModelos
// (iOS). Kotlin/JVM puro: sin Android, para que los tests corran en la JVM.
plugins {
    alias(libs.plugins.kotlin.jvm)
}

dependencies {
    api(libs.kotlinx.serialization.json)

    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}
