plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin { jvmToolchain(17) }

dependencies {
    api(libs.kotlinx.coroutines.core)
    api(libs.kotlinx.serialization.json)
    api(libs.okhttp)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver)
    testImplementation(libs.json.schema.validator)
}

tasks.test {
    // Contract tests read the single-source schema and samples from docs/protocol.
    systemProperty("huanhermes.protocolDir", rootProject.file("../../docs/protocol").absolutePath)
    // Optional live test against server/mock-host (needs python3).
    systemProperty("huanhermes.serverDir", rootProject.file("../../server").absolutePath)
    testLogging { events("failed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
}
