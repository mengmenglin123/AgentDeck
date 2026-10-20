import java.security.MessageDigest
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Native versions start at 0.2.0 / versionCode 2000 so they install over the
// Flutter app (0.1.2xx, versionCode 2xx), which uses the same applicationId and key.
val nativeVersionName = "0.7.4"
val nativeVersionCode = 2022

android {
    namespace = "com.huanmeng.huanhermes"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.huanmeng.huanhermes"
        minSdk = 26
        targetSdk = 35
        versionCode = nativeVersionCode
        versionName = nativeVersionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Screenshots go through TestStorage and are pulled into build/outputs.
        testInstrumentationRunnerArguments["useTestStorageService"] = "true"
        // Host the emulator UI tests talk to (mock-host on the CI runner).
        testInstrumentationRunnerArguments["hostAddr"] = "10.0.2.2"
    }

    // key.properties (private production key, git-ignored) wins, else the
    // prerelease key CI decodes from secrets, else debug signing (forks).
    val keyProps = Properties().apply {
        val f = rootProject.file("key.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    signingConfigs {
        create("release") {
            if (keyProps.getProperty("storeFile") != null) {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
                keyProps.getProperty("storeType")?.let { storeType = it }
            } else if (rootProject.file("signing/huanhermes-prerelease.p12").exists()) {
                // CI writes this file from the HH_SIGNING_P12_B64 secret; never committed.
                storeFile = rootProject.file("signing/huanhermes-prerelease.p12")
                storeType = "pkcs12"
                storePassword = System.getenv("HH_SIGNING_PASSWORD") ?: ""
                keyAlias = "huanhermes"
                keyPassword = System.getenv("HH_SIGNING_PASSWORD") ?: ""
            } else {
                initWith(getByName("debug"))
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }

    splits {
        abi {
            isEnable = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

configurations.all { exclude(group = "com.google.crypto.tink", module = "tink") }

dependencies {
    implementation(project(":core"))
    implementation(libs.androidx.security.crypto)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.core.splashscreen)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material3.navigation.suite)
    implementation(libs.compose.material.icons)
    implementation(libs.navigation.compose)
    implementation(libs.androidx.work.runtime)
    implementation(libs.camera.camera2)
    implementation(libs.camera.lifecycle)
    implementation(libs.camera.view)
    implementation(libs.zxing.core)
    // UnifiedPush and sshlib ship JVM tink; security-crypto ships tink-android. Keep one (Android) copy.
    implementation(libs.unifiedpush.connector)
    implementation("com.google.crypto.tink:tink-android:1.23.0")
    implementation(libs.datastore.preferences)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    debugImplementation(libs.compose.ui.tooling)
    testImplementation(libs.junit)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:rules:1.6.1")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.services:storage:1.5.0")
    androidTestUtil("androidx.test.services:test-services:1.5.0")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}


// Host companion for "SSH 一键安装": packaged reproducibly from this commit's server/ (scripts/build_companion.sh).
val companionDir = layout.buildDirectory.dir("generated/companion")
val bundleCompanion by tasks.registering {
    val out = companionDir
    val script = rootProject.file("../../scripts/build_companion.sh")
    val serverDir = rootProject.file("../../server")
    inputs.dir(serverDir)
    inputs.file(script)
    outputs.dir(out)
    doLast {
        val dir = out.get().asFile.resolve("companion").apply { deleteRecursively(); mkdirs() }
        val proc = ProcessBuilder("bash", script.absolutePath, nativeVersionName, "2026-01-01")
            .apply { environment()["HH_COMPANION_OUT"] = dir.absolutePath }
            .redirectErrorStream(true).start()
        val log = proc.inputStream.bufferedReader().readText()
        if (proc.waitFor() != 0) throw GradleException("build_companion.sh failed:\n$log")
        // AAPT gunzips "*.gz" assets and drops the extension: ship it under a neutral name.
        val tar = dir.resolve("huanhermes-host-$nativeVersionName.tgz.bin")
        dir.resolve("huanhermes-host-$nativeVersionName.tar.gz").renameTo(tar)
        val sha = MessageDigest.getInstance("SHA-256").digest(tar.readBytes()).joinToString("") { "%02x".format(it) }
        dir.resolve("companion.json").writeText("""{"version":"$nativeVersionName","sha256":"$sha","file":"${tar.name}"}""")
    }
}
android.sourceSets["main"].assets.srcDir(companionDir)
tasks.named("preBuild") { dependsOn(bundleCompanion) }
