allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Google services plugin for Firebase
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.4")
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// ── CMake version fix ─────────────────────────────────────────────────────────
// argon2_ffi v1.0.0+2 pins cmake 3.10.2 in its build.gradle, which is no
// longer available in modern Android SDK installations (NDK 27+ ships 3.22.1).
// Override the cmake version for the argon2_ffi subproject after its build
// script is evaluated, so Gradle uses the installed 3.22.1 instead.
subprojects {
    afterEvaluate {
        if (project.name == "argon2_ffi") {
            // Use the AGP extension APIs to override the cmake version.
            // This is equivalent to manually editing the plugin's build.gradle.
            val android = project.extensions
                .findByName("android") as? com.android.build.gradle.LibraryExtension
            android?.defaultConfig?.externalNativeBuild?.cmake {
                version = "3.22.1"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
