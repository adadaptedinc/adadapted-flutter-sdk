group = "com.adadapted.flutter_sdk"
version = "1.0"

buildscript {
    val kotlinVersion = "2.4.0"

    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Deliberately no `kotlin-android` plugin and no `kotlinOptions` block. Flutter
// 3.47 applies Kotlin to plugin modules itself, and a plugin that applies it
// again is warned about on every build and will break outright when the
// built-in path becomes the only one. The jvmTarget moves to the top level
// `kotlin` block below. See:
// https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
plugins {
    id("com.android.library")
}

android {
    namespace = "com.adadapted.flutter_sdk"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Supplies the Google Advertising ID and the user's limit-ad-tracking choice.
    // Every reported event is attributed to that identifier, so this is not optional.
    implementation("com.google.android.gms:play-services-ads-identifier:18.2.0")
}
