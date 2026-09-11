group = "com.adadapted.flutter_sdk"
version = "1.0"

buildscript {
    val kotlinVersion = "2.4.20"

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

// Deliberately no `kotlin-android` plugin and no `kotlinOptions` block: Flutter
// applies Kotlin to plugin modules itself, and a plugin that applies it again is
// warned about on every build and will break when the built-in path becomes the
// only one. The jvmTarget moves to the top level `kotlin` block below.
//
// The floor for this shape is Flutter 3.44, which is what pubspec.yaml requires
// and what the migration guide tells plugin authors to set — from 3.44 the
// minimum KGP is 2.0.0, so apps using this plugin build on AGP 9. Flutter 3.47
// is a different threshold: it is what an app needs to turn built-in Kotlin on
// explicitly with `android.builtInKotlin=true`, not what this module needs to
// compile. See:
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
