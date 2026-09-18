plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Placeholder package name - change here (and move MainActivity.kt's
    // package/folder to match) when you have your real Play Store id.
    namespace = "com.createaistudio.app"
    // Overrides flutter.compileSdkVersion (35): androidx.core 1.18.0, pulled
    // in transitively by several plugins, requires compiling against 36.
    compileSdk = 36
    // Pinned to the highest version required by plugin dependencies
    // (app_links, connectivity_plus, file_picker, ...); NDKs are backward
    // compatible so this covers flutter.ndkVersion's needs too.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.createaistudio.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Overrides flutter.minSdkVersion (21): androidx.core-ktx 1.18.0
        // requires 23, and just_audio's audio_session dependency (Phase 3)
        // requires 24. Android 7.0+ still covers the vast majority of
        // active devices.
        minSdk = 24
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
