import java.util.Properties
import java.io.FileInputStream

// Carica il file local.properties
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.delelimed.registro_catechismo"
    
    compileSdk = 36 
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        
        // AGGIUNTO: Abilita il desugaring nelle opzioni di compilazione
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.delelimed.registro_catechismo"
        
        minSdk = 30
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // AGGIUNTO: Previene errori sul limite dei metodi (consigliato con il desugaring)
        multiDexEnabled = true
    }

    signingConfigs {
        create("sharedConfig") {
            // Recupera i valori in sicurezza
            val keyFile = localProperties.getProperty("keystore.file")
            
            storeFile = if (keyFile != null) file(keyFile) else null
            storePassword = localProperties.getProperty("keystore.password")
            keyAlias = localProperties.getProperty("keystore.alias")
            keyPassword = localProperties.getProperty("keystore.alias.password")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("sharedConfig")
            isMinifyEnabled = false
            isShrinkResources = false

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
    // Removed Google Play dependencies - not needed for local-only app
    
    // AGGIUNTO: Dipendenza nativa per il desugaring (sintassi Kotlin DSL)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.3")
}