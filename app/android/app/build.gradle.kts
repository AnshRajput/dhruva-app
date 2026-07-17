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

        // RISK / hard limitation (UX-hardening A3): the llama.cpp inference
        // engine ships arm64-v8a native libs ONLY (libs/llama-cpp-dart.aar).
        // libllama.so therefore only ever exists under lib/arm64-v8a/ — on a
        // device/emulator whose primary ABI resolves to armeabi-v7a or x86_64
        // `dlopen("libllama.so")` fails → EngineLoadFailure → no reply.
        //
        // Dhruva is intentionally an arm64-v8a-only app (every modern, post-2017
        // Android phone is arm64-v8a). This abiFilters declaration is the
        // arm64-only intent and is what the Play `appbundle`/App-Bundle delivery
        // path honors. NOTE: a fat `flutter build apk` does NOT honor it for the
        // engine/plugin `.so` (Flutter packages every --target-platform ABI
        // itself), so the RELEASE DISTRIBUTION build in scripts/distribute.sh
        // additionally passes `--target-platform android-arm64` to ship an
        // arm64-only Flutter engine. Proper long-term delivery is the App Bundle
        // so Play sends each device only its own ABI slice.
        ndk {
            abiFilters += "arm64-v8a"
        }
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
