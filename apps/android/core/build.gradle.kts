plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin { jvmToolchain(17) }

dependencies {
    api(libs.kotlinx.coroutines.core)
    api(libs.kotlinx.serialization.json)
    api(libs.okhttp)
    // Chat rendering: CommonMark + GFM parsed off the main thread into our own block model.
    // SSH companion install: ConnectBot sshlib (Apache-2.0).
    implementation(libs.sshlib)
    implementation(libs.commonmark)
    implementation(libs.commonmark.gfm.tables)
    implementation(libs.commonmark.gfm.strikethrough)
    implementation(libs.commonmark.task.list)
    implementation(libs.commonmark.autolink)
    // Phone-side agent tools: HTML/XML to text (MIT) and a sandboxed JS interpreter (MPL-2.0).
    api("org.jsoup:jsoup:1.18.1")
    api("org.mozilla:rhino:1.7.15")
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver)
    testImplementation(libs.okhttp.tls)
    testImplementation(libs.json.schema.validator)
}

tasks.test {
    // Contract tests read the single-source schema and samples from docs/protocol.
    systemProperty("huanhermes.protocolDir", rootProject.file("../../docs/protocol").absolutePath)
    // Optional live test against server/mock-host (needs python3).
    systemProperty("huanhermes.serverDir", rootProject.file("../../server").absolutePath)
    testLogging { events("failed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
}
