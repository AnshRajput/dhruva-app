plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "tech.appuinside.dhruva"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "tech.appuinside.dhruva"
        // Device floor is minSdk 26 (DECISIONS.md "DEVICE FLOOR"); also the
        // floor the llama-cpp-dart AAR declares. flutter.minSdkVersion is 24 by
        // default, so pin 26 explicitly here.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // llama.cpp native libs (libllama.so + libggml* + libmtmd.so, arm64-v8a,
    // CPU+mtmd). Prebuilt AAR from netdur/llama_cpp_dart release v0.9.0-dev.9,
    // native-identical to our pinned commit c6e3778 (the 2 commits between are
    // pure-Dart). Provenance + re-fetch: scripts/fetch-android-aar.sh.
    // Closes R10 — without this the APK ships with no inference .so.
    implementation(files("libs/llama-cpp-dart.aar"))
}
