plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.resonance.resonance"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // FIX 1: Core library desugaring (flutter_local_notifications needs this)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        // FIX 2: Must match compileOptions above — both must be 17
        // Mismatch between Java (1.8) and Kotlin (17) caused the build failure
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.resonance.resonance"
        // FIX 3: minSdk 21 required for desugaring + audio_service
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FIX 4: Desugar library — required for flutter_local_notifications + audio_service
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
