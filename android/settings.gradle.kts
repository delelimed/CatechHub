pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
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
    // Loader dei plugin Flutter: gestisce automaticamente la registrazione
    // di tutti i plugin dichiarati in pubspec.yaml
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // Android Gradle Plugin 8.11.1: versione richiesta per compatibilità
    id("com.android.application") version "8.11.1" apply false

    // Kotlin 2.0.21: Versione di sblocco compatibile con l'embedded-kotlin di Gradle
    // Evita il crash sui metadati del workspace e sul caricamento dei plugin Flutter
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")