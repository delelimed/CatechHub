pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val localPropertiesFile = file("local.properties")
        if (localPropertiesFile.exists()) {
            localPropertiesFile.inputStream().use { properties.load(it) }
        }
        val flutterSdkPath = properties.getProperty("flutter.sdk") ?: System.getenv("FLUTTER_ROOT")
        require(flutterSdkPath != null) { 
            "flutter.sdk not set in local.properties and FLUTTER_ROOT environment variable is not available." 
        }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    // Loader dei plugin Flutter
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    
    // Android Gradle Plugin 8.11.1
    id("com.android.application") version "8.11.1" apply false
    
    // Kotlin 2.2.20
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")

// 🛠️ FIX COMPATIBILITÀ: Risolve l'errore "Extension with name 'flutter' does not exist"
// per i plugin legacy/federati (es. android_file_picker) con le nuove versioni di Gradle/AGP.
gradle.beforeProject {
    if (path != ":" && path != ":app") {
        plugins.afterApply {
            if (!pluginManager.hasPlugin("flutter")) {
                try {
                    plugins.apply("flutter")
                } catch (e: Exception) {
                    // Ignora se il modulo non supporta l'applicazione diretta del plugin flutter
                }
            }
        }
    }
}