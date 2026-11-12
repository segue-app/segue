import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "fm.segue.segue"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "fm.segue.segue"
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
    }

    // One permanent release key, so every new version installs over the
    // old one (in-app updates). It comes from android/key.properties
    // locally or SEGUE_* environment variables in CI; without it, debug
    // keys (fine for `flutter run --release`).
    val keyProps = Properties().apply {
        val f = rootProject.file("key.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    fun key(name: String, env: String): String? =
        keyProps.getProperty(name) ?: System.getenv(env)?.takeIf { it.isNotEmpty() }
    val storePath = key("storeFile", "SEGUE_KEYSTORE")
    signingConfigs {
        if (storePath != null) {
            create("release") {
                storeFile = file(storePath)
                storePassword = key("storePassword", "SEGUE_KEYSTORE_PASSWORD")
                keyAlias = key("keyAlias", "SEGUE_KEY_ALIAS")
                keyPassword = key("keyPassword", "SEGUE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
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
    // FileProvider, to hand a downloaded update to the installer.
    implementation("androidx.core:core-ktx:1.13.1")
}
