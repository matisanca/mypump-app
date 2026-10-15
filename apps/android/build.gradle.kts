import org.gradle.api.tasks.testing.logging.TestExceptionFormat
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension

plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    // Avisos: Firebase (FCM) para el push de los mensajes de Mati; lo aplica solo :app.
    alias(libs.plugins.google.services) apply false
}

/** La raíz del repo: los tests leen de ahí los vectores y fixtures compartidos con iOS (`apps/shared/`). */
val raizRepo: File = rootDir.resolve("../..").canonicalFile

/** Los vectores sacados de los planes reales: viven fuera del repo (es público) y en otra Mac no existen. */
val carpetaPrivada: File = File(System.getProperty("user.home"), "Developer/nativa-evidencia/privado")

// Lo común de los módulos JVM puros (:core:*): bytecode 17 para que los consuma :app, JUnit 5, y los tests apuntando
// a los mismos archivos que lee `swift test`.
subprojects {
    plugins.withId("org.jetbrains.kotlin.jvm") {
        extensions.configure<JavaPluginExtension> {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
        extensions.configure<KotlinJvmProjectExtension> {
            compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
        }
        tasks.withType<Test>().configureEach {
            useJUnitPlatform()
            // Los vectores privados de progresión pesan 18 MB de JSON.
            maxHeapSize = "2g"
            systemProperty("mypump.raizRepo", raizRepo.path)
            systemProperty("mypump.carpetaPrivada", carpetaPrivada.path)
            // Si cambia un vector (o aparece uno privado), los tests vuelven a correr aunque el código no cambie.
            inputs.files(fileTree(raizRepo.resolve("apps/shared")))
            inputs.files(fileTree(carpetaPrivada.resolve("vectores")))
            inputs.files(fileTree(carpetaPrivada.resolve("estructuras")))
            testLogging {
                events("passed", "skipped", "failed")
                exceptionFormat = TestExceptionFormat.FULL
                showStandardStreams = false
            }
        }
    }
}
