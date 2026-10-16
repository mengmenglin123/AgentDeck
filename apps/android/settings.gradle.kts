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
rootProject.name = "HuanHermesNative"
// :core is pure Kotlin/JVM (protocol, networking, chat logic) so its tests run
// anywhere with a JDK: `gradle -PcoreOnly :core:test` skips the Android app.
include(":core")
if (!providers.gradleProperty("coreOnly").isPresent) include(":app")
