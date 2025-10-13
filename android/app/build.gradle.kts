plugins {
    id("com.android.application")
    id("com.google.gms.google-services") // Firebase
    id("org.jetbrains.kotlin.android")   // Kotlin Android plugin oficial
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.qorinti.app"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.qorinti.app"
        minSdk = 23
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        // Asegura compatibilidad Java
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        // Asegura compatibilidad Kotlin/Java
        jvmTarget = "1.8"
    }

    buildTypes {
        release {
            // Cambia por tu keystore real en producción
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Firebase BOM asegura versiones consistentes
    implementation(platform("com.google.firebase:firebase-bom:34.2.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")

    // (Opcional) Si usas más Firebase:
    // implementation("com.google.firebase:firebase-storage")
    // implementation("com.google.firebase:firebase-crashlytics")
}
