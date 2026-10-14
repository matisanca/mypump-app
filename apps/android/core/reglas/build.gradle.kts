// Las reglas portadas de la web (progresión, porciones, swaps, sustituciones…), verificadas con los mismos vectores
// que MyPumpReglas en iOS. Kotlin/JVM puro.
plugins {
    alias(libs.plugins.kotlin.jvm)
}

dependencies {
    api(project(":core:modelos"))

    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}
