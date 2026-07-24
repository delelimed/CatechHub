import java.util.Properties
import java.io.FileInputStream

// ══════════════════════════════════════════════════════════════════════════════
// build.gradle.kts — CatechHub (modulo app Android)
//
// Configurazione Gradle del modulo principale dell'applicazione CatechHub,
// un registro elettronico di catechismo costruito con Flutter per Android.
// ══════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// CARICAMENTO LOCAL.PROPERTIES
// ─────────────────────────────────────────────────────────────────────────────
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.delelimed.catechhub"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.delelimed.catechhub"
        minSdk = 30
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true

        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    androidResources {
        localeFilters.add("it")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CONFIGURAZIONE FIRMA (SIGNING) - OTTIMIZZATA PER PC LOCALE & GITHUB ACTIONS
    // ─────────────────────────────────────────────────────────────────────────
signingConfigs {
    create("sharedConfig") {
        val isCodespace = System.getenv("CODESPACES") == "true"
        val envKeystorePath = System.getenv("SIGNING_KEYSTORE_PATH")
        
        if (isCodespace) {
            // 1. Configurazione specifica per GitHub Codespaces
            // Il file viene creato dal postStartCommand in questo percorso esatto
            storeFile = file("app_release_key.jks") 
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            
        } else if (envKeystorePath != null) {
            // 2. Configurazione per GitHub Actions
            storeFile = file(envKeystorePath)
            storePassword = System.getenv("SIGNING_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("SIGNING_KEY_ALIAS")
            keyPassword = System.getenv("SIGNING_KEY_PASSWORD")
            
        } else {
            // 3. Configurazione locale Windows (dal tuo file local.properties)
            val keyFile = localProperties.getProperty("keystore.file")
            storeFile = if (keyFile != null) file(keyFile) else null
            storePassword = localProperties.getProperty("keystore.password")
            keyAlias = localProperties.getProperty("keystore.alias")
            keyPassword = localProperties.getProperty("keystore.alias.password")
        }
    }
}

    buildTypes {
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }

        release {
            signingConfig = signingConfigs.getByName("sharedConfig")
            isMinifyEnabled = true
            isShrinkResources = true

            file("proguard-rules.pro").let { proguardFile ->
                if (proguardFile.exists()) {
                    proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), proguardFile)
                } else {
                    proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
                }
            }
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "**/*.dbg",
                "**/*.sym"
            )
        }
        jniLibs {
            keepDebugSymbols.clear() 
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
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("androidx.core:core:1.13.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}