import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    // El mismo paquete que la Capacitor: se instala encima (update real, el contenedor se conserva). Firmado con la
    // clave de debug, igual que el APK de debug de la Capacitor.
    namespace = "com.pumpteam.mypump"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.pumpteam.mypump"
        minSdk = 26
        targetSdk = 36
        versionCode = 1000
        versionName = "espia"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { compilerOptions.jvmTarget.set(JvmTarget.JVM_17) }
