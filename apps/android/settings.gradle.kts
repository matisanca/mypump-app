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

rootProject.name = "MyPump"

// Lo que no es pantalla va en módulos JVM puros: los tests corren en la JVM, en segundos y sin emulador, igual que
// `swift test` con MyPumpKit en iOS.
include(":app")
include(":core:modelos")
include(":core:reglas")
include(":core:datos")
