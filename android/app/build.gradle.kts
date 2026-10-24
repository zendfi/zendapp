import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load signing config from key.properties (local dev) or CI env vars
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun prop(key: String): String? =
    keystoreProperties.getProperty(key)?.takeIf { it.isNotBlank() }

android {
    namespace = "com.zendfi.zendapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    signingConfigs {
        create("release") {
            keyAlias     = prop("keyAlias")     ?: System.getenv("KEY_ALIAS")      ?: "zend"
            keyPassword  = prop("keyPassword")  ?: System.getenv("KEY_PASSWORD")   ?: ""
            storeFile    = file(prop("storeFile") ?: "zend.jks")
            storePassword = prop("storePassword") ?: System.getenv("STORE_PASSWORD") ?: ""
        }
    }

    defaultConfig {
        applicationId = "com.zendfi.zendapp"
        minSdk        = flutter.minSdkVersion
        targetSdk     = flutter.targetSdkVersion
        versionCode   = flutter.versionCode
        versionName   = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig   = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring — required by flutter_local_notifications
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Firebase BoM — manages compatible versions across all Firebase libraries
    implementation(platform("com.google.firebase:firebase-bom:34.0.0"))
    implementation("com.google.firebase:firebase-messaging")
    // firebase-analytics intentionally omitted: there is no firebase_analytics
    // Dart package and no analytics call anywhere in lib/, so it only added
    // weight and a data-collection disclosure obligation on the Play Data
    // Safety form. FCM push delivery does not require it — analytics is only
    // needed for Notifications-composer campaign metrics, which we do not use.
}
