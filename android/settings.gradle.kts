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

rootProject.name = "ngrams"

// :core is plain Kotlin, the game rules and the bank, tested on the JVM with no emulator.
// :app is the Android app around it.
include(":core", ":app")
