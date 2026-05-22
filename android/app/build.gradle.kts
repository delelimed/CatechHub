plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.registro_catechismo"
    
    compileSdk = 36 
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.delelimed.registro_catechismo"
        
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Aggiungi qui la tua configurazione di firma (Keystore) per la produzione.
            signingConfig = signingConfigs.getByName("debug")
            
            // --- ATTIVAZIONE SICUREZZA E OTTIMIZZAZIONE (Kotlin DSL) ---
            
            // Attiva l'ottimizzazione e l'offuscamento del codice nativo/Java/Kotlin tramite R8
            isMinifyEnabled = true
            
            // Rimuove automaticamente le risorse (immagini, layout) non utilizzate dai pacchetti
            isShrinkResources = true
            
            // Specifica le regole di ProGuard da applicare
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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