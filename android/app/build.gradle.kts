/**
 * Noctorium Song Find on a phone: the Android half of a Flutter application.
 *
 * The finding, the providers and the screens are Dart. What is here is what only Android can do or be told:
 * the application's identity, how a release is signed, and in Kotlin the listening itself -- the microphone,
 * and what the phone is playing through a media projection -- and handing an update to the installer.
 */
plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.noctorium.songfind"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    /**
     * Signing, when there is a key to sign with -- the same four variables Noctorium's own build reads, so
     * the release workflow hands both applications one keystore and the two APKs carry one certificate.
     *
     * A release APK that is not signed cannot be installed by anybody, so a checkout without the key (a
     * fork, or a run before the secrets are set up) falls back below to the debug key and still produces
     * something that can be sideloaded and tried. It is not a substitute: an APK signed with the debug key
     * cannot later be updated by one signed properly.
     */
    val keystorePath: String? = System.getenv("NOCTORIUM_KEYSTORE")?.takeIf { it.isNotBlank() }

    signingConfigs {
        if (keystorePath != null) {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = System.getenv("NOCTORIUM_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("NOCTORIUM_KEY_ALIAS")
                keyPassword = System.getenv("NOCTORIUM_KEY_PASSWORD")
            }
        }
    }

    defaultConfig {
        // Its own identity: this sits beside Noctorium on a phone, and installing one must never look to
        // Android like replacing the other.
        applicationId = "app.noctorium.songfind"
        // The floor Noctorium sets, and what a launcher icon that is only an adaptive icon needs. Listening to
        // what the phone itself plays needs Android 10; below that the app says so and offers the microphone.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        /*
         * From `flutter build apk --build-name X.Y.Z --build-number N`, which the release workflow passes
         * from the tag, with N packed as Noctorium's is: 1.2.3 is 10203. A build given neither takes the
         * version in pubspec.yaml.
         */
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // The name under the icon. Every build type is called this unless it says otherwise; Flutter adds
        // a profile build type of its own, which would otherwise have no name to put in the manifest.
        manifestPlaceholders["appLabel"] = "Noctorium Song Find"
    }

    buildTypes {
        debug {
            // Its own identity, so a build being worked on installs beside the released one instead of
            // replacing it (and taking its sign-in with it), and its own name on the launcher so the two
            // cannot be mistaken for each other.
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appLabel"] = "Noctorium Song Find (debug)"
        }
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // FileProvider, which shares a downloaded update with the system's installer.
    implementation("androidx.core:core-ktx:1.13.1")
}

flutter {
    source = "../.."
}
