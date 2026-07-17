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
// CARTLLA BUILD GLOBALE
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
// La configurazione viene applicata both alla root e a ogni subproject
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
// - I plugin Flutter compilati come librerie Android
// - Le librerie di terze parti incluse come dipendenze
//
// Scopo: garantire che tutti i moduli utilizzino le stesse versioni
// di SDK, JDK e configurazioni di compilazione, evitando conflitti
// di compatibilità tra moduli.
//
// Il blocco afterEvaluate viene eseguito DOPO che ogni sottomodulo
// si è configurato con il proprio build.gradle, permettendo di
// sovrascrivere le configurazioni non conformi.
// ─────────────────────────────────────────────────────────────────────────────

subprojects {
    // Configura la cartella di build specifica per ogni sottomodulo.
    // Ogni modulo ha la propria sotto-cartella nella build directory globale.
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    layout.buildDirectory.value(newSubprojectBuildDir)

    // Eseguito DOPO che il sottomodulo si è configurato, per sovrascrivere
    // i parametri vecchi o mancanti. Questo è il punto in cui forziamo
    // le configurazioni che i plugin Flutter non dichiarano correttamente.
    afterEvaluate {
        // ─────────────────────────────────────────────────────────────────────
        // 1. FORZATURA COMPILESDK PER L'APPLICAZIONE PRINCIPALE
        // ─────────────────────────────────────────────────────────────────────
        // Garantisce che il modulo app utilizzisi compileSdk 36,
        // indipendentemente da quanto dichiarato nel suo build.gradle.
        // Utile quando i plugin Flutter cercano di sovrascrivere
        // il compileSdk con versioni più vecchie.
        // ─────────────────────────────────────────────────────────────────────

        extensions.findByType<ApplicationExtension>()?.apply {
            compileSdk = 36
        }

        // ─────────────────────────────────────────────────────────────────────
        // 2. FORZATURA CONFIGURAZIONI PER LIBRERIE E PLUGIN
        // ─────────────────────────────────────────────────────────────────────
        // Questo blocco si applica a TUTTE le librerie incluse nel progetto,
        // inclusi i plugin Flutter compilati come librerie Android.
        //
        // Molti plugin Flutter (es. flutter_bluetooth_serial) non dichiarano
        // correttamente le loro dipendenze nei rispettivi build.gradle,
        // causando errori di compilazione o crash all'avvio quando vengono
        // utilizzate versioni moderne di Kotlin e AGP.
        // ─────────────────────────────────────────────────────────────────────

        extensions.findByType<LibraryExtension>()?.apply {
            // Forza compileSdk 36 per tutte le librerie
            compileSdk = 36

            // ─────────────────────────────────────────────────────────────────
            // PATCH PER FLUTTER_BLUETOOTH_SERIAL
            // ─────────────────────────────────────────────────────────────────
            // flutter_bluetooth_serial è un plugin Flutter per la comunicazione
            // Bluetooth Classic (RFCOMM). È utilizzato nella fase di pairing
            // iniziale tra dispositivi catechisti.
            //
            // PROBLEMA: Il plugin non dichiara esplicitamente nel suo
            // build.gradle:
            // - minSdk (usa il default di Android, che potrebbe essere troppo basso)
            // - Java 17 source/target compatibility
            // - Kotlin jvmTarget 17
            //
            // CONSEGUENZA: Su dispositivi con Kotlin 2.2.20 e AGP 8.11.1,
            // il sistema tenta di caricare le classi native del plugin con
            // un bytecode incompatibile, causando crash all'avvio con errori
            // come "UnsupportedClassVersionError" o "VerifyError".
            //
            // SOLUZIONE: Questo blocco forza le configurazioni mancanti
            // DOPO che il plugin si è configurato, garantendo compatibilità
            // con il resto del progetto.
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
                // di bytecode. Senza questa impostazione, il plugin genera
                // bytecode per una versione JVM diversa, causando errori
                // di caricamento delle classi native all'avvio dell'app.
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
//
// Utile quando:
// - Si cambiano configurazioni di build e si vuole una build pulita
// - Si verificano errori di compilazione dovuti a file obsoleti
// - Si prepara il progetto per il commit (pulizia temporanei)
// ─────────────────────────────────────────────────────────────────────────────

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
