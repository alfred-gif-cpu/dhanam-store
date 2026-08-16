import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) load(file.inputStream())
}

android {
    namespace = "com.dhanamstore.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = file(keystoreProperties["storeFile"] as String? ?: "release-keystore.jks")
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    defaultConfig {
        applicationId = "com.dhanamstore.app"
        // This said `minSdk = 23` for months and every APK still shipped 24.
        //
        // Flutter runs MinSdkVersionMigration on each build, which rewrites any
        // literal minSdk of 16-23 to flutter.minSdkVersion — 24 on 3.44. Not an
        // occasional regeneration: it is every single build, so the pin was
        // never in an artifact. Verified by reading the built APK with
        // `aapt2 dump badging`, which is the only place the answer is real.
        //
        // 23 was chosen because flutter_secure_storage asks for it, and it is
        // still the plugin's floor. But Flutter itself now declares 24 the
        // minimum it supports (gradle_utils.dart, minSdkVersionInt = 24), so 23
        // is below the framework's own floor, not just the plugin's.
        //
        // To actually hold 23 the value has to dodge the migration's regex,
        // which only matches a literal: `val androidMinSdk = 23` on its own
        // line, then `minSdk = androidMinSdk`. Worth doing only if Android 6.0
        // reach is worth running under a framework that no longer tests it.
        // Check a real APK afterwards either way.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
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

