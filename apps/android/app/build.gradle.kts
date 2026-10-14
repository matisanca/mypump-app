import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
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
