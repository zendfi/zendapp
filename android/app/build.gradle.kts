plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase / Google services
    id("com.google.gms.google-services")
}

// Load signing config from key.properties (local) or CI environment variables
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.zendfi.zendapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            // CI: secrets injected as env vars via key.properties written by workflow
            // Local: key.properties file in android/ directory
            keyAlias = keystoreProperties["keyAlias"] as String? ?: System.getenv("KEY_ALIAS") ?: "zend"
            keyPassword = keystoreProperties["keyPassword"] as String? ?: System.getenv("KEY_PASSWORD") ?: ""
            storeFile = file(keystoreProperties["storeFile"] as String? ?: "app/zend.jks")
            storePassword = keystoreProperties["storePassword"] as String? ?: System.getenv("STORE_PASSWORD") ?: ""
        }
    }

    defaultConfig {
        applicationId = "com.zendfi.zendapp"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
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
    // Firebase BoM — manages compatible versions across all Firebase libraries
    implementation(platform("com.google.firebase:firebase-bom:34.0.0"))
    // FCM for push notifications
    implementation("com.google.firebase:firebase-messaging")
    // Analytics (required by Firebase BoM)
    implementation("com.google.firebase:firebase-analytics")
}
