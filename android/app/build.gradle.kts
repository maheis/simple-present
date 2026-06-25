import java.io.FileInputStream
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "de.maheis.simplepresent"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "de.maheis.simplepresent"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Android 13+ baseline (API 33) as requested.
        minSdk = 33
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Load signing info from key.properties if present (created by CI from secrets)
    val possibleKeys = listOf(rootProject.file("key.properties"), rootProject.file("android/key.properties"))
    val keystorePropertiesFile = possibleKeys.firstOrNull { it.exists() }
    if (keystorePropertiesFile != null) {
        val keystoreProperties = Properties()
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
        signingConfigs {
            create("release") {
                val storeFileProp = keystoreProperties.getProperty("storeFile")
                if (storeFileProp != null) {
                    storeFile = file(storeFileProp)
                }
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Use release signing config if available
            if (signingConfigs.findByName("release") != null) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        // Keep Kotlin bytecode target aligned with Java 17 toolchain used in CI.
        jvmTarget = JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
