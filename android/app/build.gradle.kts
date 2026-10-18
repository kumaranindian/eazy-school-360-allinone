import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties (git-ignored; see
// DEVELOPMENT_GUIDE.md "Release signing"). Without it a release build is
// signed with the debug key, which a store rejects - so a release build now
// FAILS unless you opt in with -PallowDebugSignedRelease=true (local checks).
val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keyPropertiesFile.exists()
val allowDebugSignedRelease =
    (project.findProperty("allowDebugSignedRelease") as String?) == "true"
if (hasReleaseKey) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}

android {
    namespace = "com.avail404.eazyschool.eazyschool360"
    compileSdk = flutter.compileSdkVersion
    // Firebase plugins require a newer NDK than the Flutter default.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.avail404.eazyschool.eazyschool360"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // firebase_auth requires minSdk 23.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKey) {
                signingConfig = signingConfigs.getByName("release")
            } else if (allowDebugSignedRelease) {
                logger.warn(
                    "WARNING: android/key.properties not found - this release " +
                        "build is signed with the DEBUG key and must not be published."
                )
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

// CFG-1: never produce a store artifact without the release key.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any {
        it.project == project &&
            Regex("^(assemble|bundle|package)Release$").matches(it.name)
    }
    if (buildsRelease && !hasReleaseKey && !allowDebugSignedRelease) {
        throw GradleException(
            "android/key.properties is missing: refusing to build a release " +
                "signed with the debug key. Add the upload keystore " +
                "(DEVELOPMENT_GUIDE.md, Release signing) or pass " +
                "-PallowDebugSignedRelease=true for a local, non-publishable build."
        )
    }
}

flutter {
    source = "../.."
}
