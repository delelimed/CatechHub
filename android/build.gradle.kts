import com.android.build.api.dsl.ApplicationExtension
import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.file.Directory
import org.gradle.api.tasks.Delete

// ══════════════════════════════════════════════════════════════════════════════
// build.gradle.kts — CatechHub (radice Android)
//
// Configurazione Gradle radice del progetto Android di CatechHub.
// Questo file si applica a TUTTI i moduli del progetto (app, plugin Flutter,
// librerie di terze parti) e definisce:
//
// 1. Repository centralizzati per il download delle dipendenze
// 2. Percorso build globale (redirect verso ../../build nella root Flutter)
// 3. Configurazione forzata dei subprojects (compileSdk, minSdk, JDK)
// 4. Patch specifiche per plugin problematici (flutter_bluetooth_serial)
// 5. Task clean per la pulizia delle build
//
// NOTA: Questo file NON contiene dipendenze dirette. Le dipendenze
// specifiche di ogni modulo sono definite nei rispettivi build.gradle.kts
// (es. app/build.gradle.kts per le dipendenze Android).
//
// CONTESTO PROGETTO:
// CatechHub è un'app Flutter per Android che sincronizza dati tra dispositivi
// catechisti via Bluetooth RFCOMM. Il progetto include plugin Flutter nativi
// (flutter_bluetooth_serial, flutter_blue_classic) che richiedono
// configurazioni Android specifiche per funzionare correttamente.
// Questo file centralizza tali configurazioni per evitare duplicazioni
// e garantire consistenza tra i moduli.
// ══════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// REPOSITORY CENTRALIZZATI
// ─────────────────────────────────────────────────────────────────────────────
// Definisce i repository da cui Gradle scarica le dipendenze per
// TUTTI i moduli del progetto (app, plugin, librerie).
//
// - google(): repository ufficiale Google per Android SDK, AGP, plugin Android
// - mavenCentral(): repository Maven centrale per librerie Java/Kotlin
//   di terze parti (Hive, Bluetooth, crittografia, ecc.)
//
// L'ordine è significativo: Gradle cerca prima in google(), poi in
// mavenCentral(). Google() ha priorità perché contiene le versioni
// più aggiornate delle dipendenze Android ufficiali.
// ─────────────────────────────────────────────────────────────────────────────

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARTELLA BUILD GLOBALE
// ─────────────────────────────────────────────────────────────────────────────
// Flutter utilizza una struttura di directory specifica: la cartella build
// del progetto Android deve trovarsi nella root del progetto Flutter
// (../../build rispetto alla directory android/).
//
// Questo redirect è necessario perché:
// 1. Flutter genera gli asset e i file Dart nella cartella build della root
// 2. Il plugin Gradle di Flutter si aspetta che la build directory sia
//    in una posizione specifica rispetto a pubspec.yaml
// 3. Senza questo redirect, i percorsi di output sarebbero sbagliati e
//    la build fallirebbe con errori di file non trovati
//
// La configurazione viene applicata sia alla root che a ogni subproject
// per garantire coerenza in tutta la gerarchia di moduli.
// ─────────────────────────────────────────────────────────────────────────────

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()

rootProject.layout.buildDirectory.value(newBuildDir)

// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURAZIONE CENTRALIZZATA DEI SUBPROJECTS
// ─────────────────────────────────────────────────────────────────────────────
// Questo blocco si applica a TUTTI i sottomoduli del progetto Android:
// - Il modulo app principale
// - I plugin Flutter compilati come librerie Android (es. permission_handler)
// - Le librerie di terze parti incluse come dipendenze
//
// Scopo: garantire che tutti i moduli utilizzino le stesse versioni
// di SDK, JDK e configurazioni di compilazione, evitando conflitti
// di compatibilità tra moduli.
// ─────────────────────────────────────────────────────────────────────────────

subprojects {
    // Configura la cartella di build specifica per ogni sottomodulo.
    // Ogni modulo ha la propria sotto-cartella nella build directory globale.
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    layout.buildDirectory.value(newSubprojectBuildDir)

    // ─────────────────────────────────────────────────────────────────────────
    // 1. FORZATURA COMPILESDK PER L'APPLICAZIONE PRINCIPALE (:app)
    // ─────────────────────────────────────────────────────────────────────────
    plugins.withId("com.android.application") {
        configure<ApplicationExtension> {
            compileSdk = 37
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. FORZATURA CONFIGURAZIONI PER LIBRERIE E PLUGIN FLUTTER (pub.dev)
    // ─────────────────────────────────────────────────────────────────────────
    // Intercetta l'applicazione del plugin Android Library per tutti i plugin
    // di terze parti. Forza compileSdk = 36 in fase di caricamento per garantire
    // che plugin come permission_handler trovino i simboli SDK più recenti.
    // ─────────────────────────────────────────────────────────────────────────
    plugins.withId("com.android.library") {
        configure<LibraryExtension> {
            // Forza compileSdk 36 per tutte le librerie
            compileSdk = 37

            // ─────────────────────────────────────────────────────────────────
            // PATCH PER FLUTTER_BLUETOOTH_SERIAL
            // ─────────────────────────────────────────────────────────────────
            // flutter_bluetooth_serial è un plugin Flutter per la comunicazione
            // Bluetooth Classic (RFCOMM). È utilizzato nella fase di pairing
            // iniziale tra dispositivi catechisti.
            // ─────────────────────────────────────────────────────────────────
            if (project.name == "flutter_bluetooth_serial") {
                // Forza minSdk 30 (Android 11) per garantire compatibilità
                // con i permessi Bluetooth Android 12+ e le API RFCOMM
                defaultConfig {
                    minSdk = 30
                }

                // Forza Java 17 source e target compatibility per allinearsi
                // alla configurazione del modulo app principale
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }

                // Forza il jvmTarget Kotlin a 17 per evitare incompatibilità
                // di bytecode.
                extensions.findByType<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension>()?.apply {
                    compilerOptions {
                        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// TASK CLEAN
// ─────────────────────────────────────────────────────────────────────────────
// Task Gradle predefinito per la pulizia della cartella build.
// Rimuove tutti i file generati (APK, classi compilate, bundle Dart,
// asset, report di compilazione).
//
// Utilizzo: ./gradlew clean (dalla directory android/)
// ─────────────────────────────────────────────────────────────────────────────

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}