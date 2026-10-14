// Espía de la prueba del almacenamiento viejo en Android (riesgo n.º 1, ver docs/NATIVA_SPIKE_ALMACENAMIENTO.md).
// No es la app: es un APK mínimo con el mismo paquete que se instala ENCIMA de la Capacitor para ver si un WebView
// nativo lee el localStorage que ella dejó. Nunca va a Play.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "MyPumpEspia"
include(":app")
