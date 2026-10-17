import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Native versions start at 0.2.0 / versionCode 2000 so they install over the
// Flutter app (0.1.2xx, versionCode 2xx), which uses the same applicationId and key.
val nativeVersionName = "0.2.5"
val nativeVersionCode = 2007

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

    // Same signing as the Flutter app: key.properties (private production key,
    // git-ignored) wins, else the committed prerelease key.
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
            } else {
                storeFile = rootProject.file("../mobile/android/app/signing/huanhermes-prerelease.p12")
                storeType = "pkcs12"
                storePassword = "huanhermes-prerelease"
                keyAlias = "huanhermes"
                keyPassword = "huanhermes-prerelease"
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
