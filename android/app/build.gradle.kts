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
    }

    defaultConfig {
        applicationId = "com.delelimed.registro_catechismo"
        
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
}