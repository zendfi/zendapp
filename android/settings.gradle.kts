pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

// ── CMake version fix for argon2_ffi ─────────────────────────────────────────
// argon2_ffi v1.0.0+2 pins cmake '3.10.2' which is not available in modern
// Android SDK installations. If ANDROID_SDK_ROOT is set (CI / local SDK) and
// cmake 3.22.1 is present there, write cmake.dir into local.properties so
// every subproject that evaluates the file will find the correct cmake.
// This runs before any subproject evaluation, so it avoids the
// "project already evaluated" error from build.gradle.kts afterEvaluate.
val localPropsFile = file("local.properties")
val androidSdkRoot = System.getenv("ANDROID_SDK_ROOT")
    ?: System.getenv("ANDROID_HOME")
    ?: "/usr/local/lib/android/sdk"
val cmake3221 = "$androidSdkRoot/cmake/3.22.1"
if (file(cmake3221).exists()) {
    val props = java.util.Properties()
    if (localPropsFile.exists()) {
        localPropsFile.inputStream().use { props.load(it) }
    }
    if (props.getProperty("cmake.dir") == null) {
        localPropsFile.appendText("\ncmake.dir=$cmake3221\n")
    }
}

include(":app")
