import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// FlutterFire configuration. google-services.json is developer-specific and git-ignored
// (README.md, "Firebase setup"). The app passes FirebaseOptions explicitly
// (lib/firebase_options.dart), so demo and emulator builds work without it; when the
// file is present the Google Services plugin is applied exactly as before.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.lifecycle("google-services.json not found: building without the Google Services plugin.")
}

// The backend comes from --dart-define=CAMPUSSYNC_BACKEND (lib/firebase_options.dart).
// Flutter passes each define base64-encoded in -Pdart-defines. Resolve it the same way
// the Dart code does and record it in the APK's manifest (meta-data "campussync.backend"),
// so tools/build_apk.ps1 can confirm that a live release is not a demo build.
val dartDefines: Map<String, String> = (project.findProperty("dart-defines") as String?)
    .orEmpty()
    .split(",")
    .filter { it.isNotEmpty() }
    .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
    .associate { it.substringBefore("=") to it.substringAfter("=", "") }
val campussyncBackend: String = when (val requested = dartDefines["CAMPUSSYNC_BACKEND"].orEmpty()) {
    "live", "emulator" -> requested
    "demo", "" -> if (dartDefines["USE_FIREBASE_EMULATOR"] == "true") "emulator" else "demo"
    else -> throw GradleException("Unknown CAMPUSSYNC_BACKEND \"$requested\" (use demo, emulator or live).")
}
logger.lifecycle("CampusSync backend: $campussyncBackend")

android {
    namespace = "com.campussync.campussync"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (java.time on older Android).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.campussync.campussync"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["campussyncBackend"] = campussyncBackend
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // R8 shrinking is off: the shared_preferences plugin's Dart JNI bridge looks
            // up Kotlin stdlib/coroutine classes by name, and R8 renamed several of them
            // (release-only startup crash, see proguard-rules.pro). Re-enable only with
            // complete keep rules and a release-build smoke test.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
