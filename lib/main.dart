import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wiredash/wiredash.dart';

import 'app/router.dart';
import 'core/auth/auth_provider.dart';
import 'core/auth/session_lifecycle_observer.dart';
import 'core/navigation/back_button_handler.dart';
import 'core/security/developer_options_warning_screen.dart';
import 'core/security/privacy_settings.dart';
import 'core/security/security_block_screen.dart';
import 'core/security/security_service.dart';
import 'core/services/update_service.dart';
import 'core/storage/local_database.dart';
import 'core/config/env_config.dart';

// ══════════════════════════════════════════════════════════════════════════════
// main.dart — CatechHub (punto di ingresso Dart)
//
// File di ingresso dell'applicazione CatechHub, un registro elettronico
// di catechismo per dispositivi Android, costruito con Flutter.
//
// Questo file è responsabile del BOOTSTRAP CRITICO dell'applicazione:
// l'ordine di inizializzazione delle fasi è fondamentale e non può essere
// modificato senza causare crash immediati.
//
// ARCHITETTURA DEL BOOTSTRAP:
//
//   FASE 0 - Binding Flutter (obbligatoria, prima riga assoluta)
//   FASE 1 - Servizi base Dart (formattazione date, nessun hardware)
//   FASE 2 - Inizializzazione Hive con auto-recovery (LIVELLO 1)
//   FASE 3 - Apertura Box Hive con corruption recovery (LIVELLO 2)
//   FASE 4 - Analytics e impostazioni privacy
//   FASE 5 - Servizi aggiornamenti e notifiche (INTERNET, non Bluetooth)
//   FASE 6 - Avvio app Flutter con Riverpod ProviderScope
//
// HARDWARE BLUETOOTH:
//   NESSUNA istanza di ClassicConnectionManager o BluetoothClassicService
//   viene creata nel main(). Tutta la logica hardware viene delegata
//   al metodo initState() della pagina che ne ha bisogno, protetta da
//   try-catch, per evitare crash se il Bluetooth non è disponibile.
//
// ARCHITETTURA HIVE E CORRUPTION RECOVERY:
//   L'inizializzazione di Hive avviene in DUE livelli:
//   - LIVELLO 1 (main): Hive.initFlutter() con try-catch. Se fallisce,
//     elimina i file .lock residui e riprova. Se fallisce ancora, mostra
//     schermata fatale.
//   - LIVELLO 2 (LocalDatabase.init): Ogni Box viene aperto individualmente
//     in try-catch atomico. Se un Box è corrotto, viene eliminato da disco
//     con Hive.deleteBoxFromDisk() e ricreato vuoto SENZA coinvolgere gli
//     altri Box. Solo authBox (registroBox) è critico: se fallisce dopo
//     tutti i tentativi, l'app mostra schermata di errore fatale.
//
// GESTIONE ERRORI:
//   Due livelli di cattura errori:
//   - FlutterError.onError: cattura errori del framework Flutter
//   - runZonedGuarded: cattura eccezioni non gestite dal Dart runtime
//   - _FatalErrorApp: schermata di errore per fallimenti irreversibili
//
// CONTESTO PROGETTO:
//   CatechHub gestisce dati sensibili di minori (anagrafica, allergie,
//   contatti genitori) e sincronizza i dati tra dispositivi catechisti
//   via Bluetooth RFCOMM. Il bootstrap garantisce che:
//   - Il database locale Hive sia inizializzato e riparato se corrotto
//   - I permessi siano richiesti in modo sequenziale e non invasivo
//   - L'app mostri errori leggibili in caso di fallimenti critici
//   - Il Bluetooth NON venga inizializzato prematuremente
// ══════════════════════════════════════════════════════════════════════════════

/// Chiave globale del navigator, utilizzata dal servizio aggiornamenti
/// per navigare alle schermate di update senza un BuildContext diretto.
///
/// Assegnata a MaterialApp.navigatorKey e resa disponibile globalmente
/// per permettere a UpdateService di aprire pagine di download/installazione
/// APK anche quando non ha un BuildContext valido.
final navigatorKey = GlobalKey<NavigatorState>();

/// Imposta la chiave di navigazione sul servizio aggiornamenti.
/// Chiamata durante il bootstrap per collegare UpdateService al navigator
/// globale dell'app.
void _initUpdateServiceNavigatorKey() {
  UpdateService.setNavigatorKey(navigatorKey);
}

/// ═══════════════════════════════════════════════════════════════════════════════
/// PUNTO DI INGRESSO PRINCIPALE DELL'APPLICAZIONE CatechHub
/// ═══════════════════════════════════════════════════════════════════════════════
///
/// ORDINE CRITICO DEL BOOTSTRAP (violazione = crash immediato):
///   1. WidgetsFlutterBinding.ensureInitialized() → PRIMA RIGA ASSOLUTA.
///      Nessuna operazione asincrona, nessuna chiamata nativa, nessun
///      accesso a Bluetooth o hardware può precedere questa riga.
///   2. FlutterError.onError → cattura errori del framework Flutter.
///   3. runZonedGuarded → cattura eccezioni non gestite dal Dart runtime.
///   4. Hive.initFlutter() → inizializzazione motore storage con auto-recovery.
///   5. LocalDatabase.init() → apertura Box individuali con corruption recovery.
///   6. Servizi Flutter base (date, aggiornamenti).
///   7. runApp() con Riverpod ProviderScope come root.
///
/// ARCHITETTURA HIVE E CORRUPTION RECOVERY:
///   L'inizializzazione di Hive avviene in DUE livelli:
///   - LIVELLO 1 (main): Hive.initFlutter() con try-catch. Se fallisce,
///     elimina i file .lock residui e riprova. Se fallisce ancora, mostra
///     schermata fatale.
///   - LIVELLO 2 (LocalDatabase.init): Ogni Box viene aperto individualmente
///     in try-catch atomico. Se un Box è corrotto, viene eliminato da disco
///     con Hive.deleteBoxFromDisk() e ricreato vuoto SENZA coinvolgere gli
///     altri Box. Solo authBox (registroBox) è critico: se fallisce dopo
///     tutti i tentativi, l'app mostra schermata di errore fatale.
///
/// HARDWARE BLUETOOTH:
///   NESSUNA istanza di ClassicConnectionManager o BluetoothClassicService
///   viene creata nel main(). Tutta la logica hardware viene delegata
///   al metodo initState() della pagina che ne ha bisogno, protetta da
///   try-catch, per evitare crash se il Bluetooth non è disponibile.
/// ═══════════════════════════════════════════════════════════════════════════════
Future<void> main() async {
  // ───────────────────────────────────────────────────────────────────────────
  // GLOBAL ERROR HANDLER: runZonedGuarded
  //
  // Cattura ogni eccezione non gestita che sfugge ai try-catch interni.
  // Senza questo, un'eccezione non catturata in un async gap causa il
  // crash immediato dell'app (errore rosso su release, eccezione su debug).
  //
  // runZonedGuarded è il primo wrapper che avvolge TUTTO il flusso.
  // Il secondo livello di protezione è FlutterError.onError (sotto),
  // che cattura specificamente gli errori del framework Flutter.
  //
  // Struttura di cattura errori:
  //   runZonedGuarded (eccezioni Dart runtime)
  //     └─ FlutterError.onError (errori framework Flutter)
  //         └─ try-catch interni (errori specifici per fase)
  //             └─ _FatalErrorApp (fallimenti irreversibili)
  // ───────────────────────────────────────────────────────────────────────────
  runZonedGuarded(
    () async {
      // ═══════════════════════════════════════════════════════════════════════
      // FASE 0 - INIZIALIZZAZIONE BINDING FLUTTER (OBBLIGATORIA - PRIMA RIGA)
      //
      // Deve essere la PRIMA riga eseguita nel metodo main(), prima di
      // qualsiasi altra operazione. Registra il binding con il engine Flutter
      // e abilita l'accesso ai canali piattaforma (MethodChannel, EventChannel)
      // e al renderer.
      //
      // CRITICO: Qualsiasi chiamata asincrona, nativa, o accesso a hardware
      // PRIMA di questa riga provoca un crash fatale:
      //   "Binding has not yet been initialized"
      //
// NOTA: FlutterError.onError viene impostato DOPO ensureInitialized()
      // perché il binding deve essere attivo prima di poter registrare
      // handler custom per gli errori del framework.
      // ══════════════════════════════════════════════════════════════════════
      WidgetsFlutterBinding.ensureInitialized();

      // ══════════════════════════════════════════════════════════════════════
      // FASE 0.1 - CARICAMENTO CONFIGURAZIONE .ENV (flutter_dotenv)
      //
      // Carica il file .env incluso negli assets PRIMA di inizializzare
      // freeRASP e Wiredash, così da leggere FREERASP_* e WIREDASH_*
      // direttamente dal file invece che da --dart-define.
      // ══════════════════════════════════════════════════════════════════════
      await EnvConfig.load();

      // ══════════════════════════════════════════════════════════════════════
      // FASE 0.5 - INIZIALIZZAZIONE FREERASP (SICUREZZA RUNTIME)
      //
      // DEVE avvenire DOPO ensureInitialized() e PRIMA di qualsiasi altra
      // inizializzazione (Hive, runApp, ecc.). freeRASP verifica l'integrità
      // dell'app e rileva root, emulator, hooking (Frida), tampering,
      // debug USB attivo, debugger connesso, opzioni sviluppatore attive.
      //
      // La configurazione viene letta da .env (caricato sopra) tramite EnvConfig:
      //   - FREERASP_PACKAGE_NAME (es. com.delelimed.catechhub)
      //   - FREERASP_RELEASE_HASH (SHA-256 del certificato in Base64)
      //
      // Se l'inizializzazione fallisce (hash errato, config errata), l'app
      // termina immediatamente mostrando un errore fatale.
      // ══════════════════════════════════════════════════════════════════════
      try {
        await SecurityService.init();
      } catch (e, stack) {
        debugPrint('[MAIN] ERRORE FATALE inizializzazione freeRASP: $e');
        debugPrint('$stack');
        runApp(_FatalErrorApp(
          message: 'Errore di inizializzazione sicurezza (freeRASP).\n'
              'L\'app non può avviarsi senza le protezioni runtime.\n\n'
              'Dettaglio: $e\n\n'
              'Contattare l\'amministratore o reinstallare l\'app.',
        ));
        return;
      }

      // ─────────────────────────────────────────────────────────────────────
      // GLOBAL ERROR HANDLER: FlutterError.onError
      //
      // Cattura gli errori del framework Flutter (build errors, layout errors,
      // errori di rendering). Senza questo handler, un errore di build in
      // un widget figlio crasha l'intera app.
      //
      // Comportamento:
      // - Debug mode: mostra l'errore nella console per il debug
      // - Release mode: logga l'errore senza crashare l'app
      //
      // NOTA: Questo handler NON cattura eccezioni Dart runtime (async gaps,
      // eccezioni lanciate esplicitamente). Per quelle, è responsabile
      // runZonedGuarded (il wrapper esterno).
      // ─────────────────────────────────────────────────────────────────────
      FlutterError.onError = (FlutterErrorDetails details) {
        debugPrint('[FLUTTER_ERROR] ${details.exception}');
        debugPrint('[FLUTTER_ERROR] Stack: ${details.stack}');
        if (kDebugMode) {
          FlutterError.presentError(details);
        }
      };

      // ═══════════════════════════════════════════════════════════════════════
      // FASE 1 - SERVIZI FLUTTER BASE (nessun hardware coinvolto)
      //
      // Inizializzazione della formattazione date per la localizzazione
      // italiana (it_IT). Opera esclusivamente su dati Dart, senza alcuna
      // interazione con il sistema operativo o l'hardware.
      //
      // Necessaria per formattare correttamente le date in italiano
      // in tutta l'app (incontri, presenze, note di contatto, ecc.).
      // ═══════════════════════════════════════════════════════════════════════
      await initializeDateFormatting('it_IT', null);

      // ═══════════════════════════════════════════════════════════════════════
      // FASE 2 - INIZIALIZZAZIONE HIVE CON AUTO-RECOVERY
      //
      // Hive è il database locale used da CatechHub per memorizzare:
      // - Anagrafica studenti (nome, cognome, data nascita, contatti)
      // - Presenze agli incontri
      // - Impostazioni app e autenticazione
      // - Allegati metadata (foto, PDF associati a studenti)
      // - Note di contatto con i genitori
      //
      // Hive.initFlutter() configura il percorso di archiviazione di default
      // (Documents/hive) e registra i TypeAdapter built-in di Hive.
      //
      // LIVELLO 1 DI RECOVERY:
      // Se Hive.initFlutter() fallisce (es. file di lock residuo da un crash
      // precedente, disco pieno, o permessi di storage negati), il catch:
      //   1. Cerca e elimina tutti i file .lock nella directory hive/
      //   2. Riprova Hive.initFlutter()
      //   3. Se fallisce ancora, mostra schermata di errore fatale
      //
      // I file .lock vengono creati da Hive quando un Box non viene chiuso
      // correttamente (es. kill del processo da parte del sistema, crash
      // della JVM). Se non vengono eliminati, impediscono l'apertura del
      // Box al prossimo avvio.
      // ═══════════════════════════════════════════════════════════════════════
      try {
        await Hive.initFlutter();
      } catch (hiveInitError) {
        debugPrint('[MAIN] Hive.initFlutter() fallito: $hiveInitError');
        debugPrint('[MAIN] Tentativo di recovery: eliminazione file .lock residui...');

        // Tentativo di recovery: elimina i file .lock residui da crash precedenti.
        // I file .lock vengono creati da Hive quando un Box non viene chiuso
        // correttamente. Se il processo viene terminato brutalmente (es. kill
        // da parte del sistema, crash della JVM), il .lock rimane su disco
        // e impedisce l'apertura del Box al prossimo avvio.
        try {
          final appDir = await getApplicationDocumentsDirectory();
          final hiveDir = Directory('${appDir.path}/hive');
          if (await hiveDir.exists()) {
            int deletedCount = 0;
            await for (final entity in hiveDir.list()) {
              if (entity is File && entity.path.endsWith('.lock')) {
                debugPrint('[MAIN] Eliminazione lock file residuo: ${entity.path}');
                await entity.delete();
                deletedCount++;
              }
            }
            debugPrint('[MAIN] Eliminati $deletedCount file .lock residui');
          }

          // Riprova l'inizializzazione dopo la pulizia dei lock
          await Hive.initFlutter();
          debugPrint('[MAIN] Hive.initFlutter() recovery completato con successo');
        } catch (retryError) {
          // ─────────────────────────────────────────────────────────────────
          // ERRORE FATALE: Hive NON si inizializza neanche dopo la pulizia.
          //
          // Causa probabile: disco pieno, permessi negati, filesystem
          // corrotto, o errore strutturale imprevisto.
          //
          // L'app NON può funzionare senza il database locale: ogni
          // funzionalità (anagrafica, presenze, impostazioni) dipende da Hive.
          //
          // Mostra schermata di errore fatale con istruzioni per l'utente.
          // ─────────────────────────────────────────────────────────────────
          debugPrint('[MAIN] Hive.initFlutter() retry fallito: $retryError');
          runApp(_FatalErrorApp(
            message: 'Impossibile inizializzare il database locale.\n'
                'Errore di inizializzazione Hive: $retryError\n\n'
                'Possibili cause:\n'
                '- Spazio di archiviazione esaurito\n'
                '- Permessi di archiviazione negati\n'
                '- Filesystem corrotto\n\n'
                'Prova a disinstallare e reinstallare l\'applicazione.',
          ));
          return;
        }
      }

      // ═══════════════════════════════════════════════════════════════════════
      // FASE 3 - DATABASE LOCALE HIVE (apertura Box con corruption recovery)
      //
      // LocalDatabase.init() apre ogni Box in un try-catch atomico
      // INDIVIDUALE. Se un Box è corrotto, viene eliminato da disco con
      // Hive.deleteBoxFromDisk() e ricreato vuoto SENZA coinvolgere gli
      // altri Box.
      //
      // I Box gestiti da LocalDatabase:
      // - authBox: credenziali, sessione, consensi (CRITICO)
      // - studentsBox: anagrafica studenti
      // - classesBox: gruppi e classi di catechismo
      // - meetingsBox: incontri e programmazione
      // - attendanceBox: presenze
      // - catechesiBox: contenuti catechetici
      // - documentsBox: documenti ciclo vita
      // - contactNotesBox: note contatto genitori
      // - attachmentsBox: metadati allegati
      // - settingsBox: impostazioni privacy e generali
      //
      // Il try-catch qui è l'ULTIMA LINEA DI DIFESA: cattura solo errori
      // che sfuggono al recovery interno (es. SecureStorage corrotto,
      // problema keystore, o permessi di storage negati).
      // ═══════════════════════════════════════════════════════════════════════

      // Comunica a LocalDatabase che Hive.initFlutter() è già stata
      // completata con successo, per evitare la doppia inizializzazione
      // (LocalDatabase.init potrebbe essere chiamato anche da altri punti).
      LocalDatabase.markHiveInitialized();

      try {
        await LocalDatabase.init();
      } catch (e) {
        // ─────────────────────────────────────────────────────────────────────
        // ERRORE FATALE: NESSUN RECOVERY POSSIBILE.
        //
        // Causa probabile: SecureStorage corrotto, keystore Android non
        // accessibile, o errore strutturale imprevisto nell'inizializzazione
        // di Hive stessa (NON nei singoli Box, che sono gestiti internamente).
        //
        // Mostra schermata di errore fatale con istruzioni per l'utente.
        // L'app NON può funzionare senza il database.
        // ─────────────────────────────────────────────────────────────────────
        debugPrint('[MAIN] Errore fatale database: $e');
        runApp(_FatalErrorApp(
          message: 'Impossibile inizializzare il database locale.\n'
              'L\'app ha provato a riparare i dati corrotti ma non è riuscita.\n'
              'Prova a disinstallare e reinstallare l\'applicazione.\n\n'
              'Dettaglio: $e',
        ));
        return;
      }

      // ═══════════════════════════════════════════════════════════════════════
      // FASE 4 - IMPOSTAZIONI PRIVACY
      //
      // Caricamento delle impostazioni di privacy dall'Hive Box dedicato.
      // Le operazioni non fatali sono protette da try-catch individuale.
      // ═══════════════════════════════════════════════════════════════════════
      // Carica le impostazioni di privacy dal database e le applica
      // a livello nativo (es. FLAG_SECURE per impedire screenshot).
      final privacy = PrivacySettingsNotifier.loadFromStorage();
      try {
        await PrivacySettingsNotifier.applyNativeOptions(privacy);
      } catch (e) {
        debugPrint('[MAIN] Privacy options apply fallito (non fatale): $e');
      }

      // ═══════════════════════════════════════════════════════════════════════
      // FASE 5 - SERVIZI AGGIORNAMENTI E NOTIFICHE
      //
      // Configurazione della chiave navigazione per il servizio aggiornamenti,
      // inizializzazione notifiche push, pulizia APK vecchi, e verifica
      // aggiornamenti all'avvio se abilitata nelle impostazioni utente.
      //
      // Tutte queste operazioni usano INTERNET, non Bluetooth.
      // Non interagiscono con i dati sensibili degli studenti.
      // ═══════════════════════════════════════════════════════════════════════
      try {
        _initUpdateServiceNavigatorKey();
        await UpdateService.initNotifications();
        await UpdateService.cleanupOldApks();
        if (privacy.checkUpdatesOnStart) {
          await UpdateService.checkForUpdates();
        }
      } catch (e) {
        // Servizi di aggiornamento non fatale: l'app può funzionare.
        debugPrint('[MAIN] Servizi aggiornamento falliti (non fatale): $e');
      }

      // ═══════════════════════════════════════════════════════════════════════
      // FASE 6 - AVVIO DELL'APPLICAZIONE FLUTTER
      //
      // Struttura del widget tree:
      //   ProviderScope (Riverpod) → SessionLifecycleObserver → MyApp
      //
      // - ProviderScope: gestisce lo stato globale dell'app tramite Riverpod
      // - SessionLifecycleObserver: monitora il ciclo di vita dell'app
      //   (pausa, ripresa) per gestire il blocco automatico della sessione
      //   dopo 120 secondi di inattività
      // - MyApp: widget radice che configura il tema, il router, e la logica
      //   di autenticazione
      //
      // La logica Bluetooth (ClassicConnectionManager, BluetoothClassicService)
      // viene inizializzata SOLO quando l'utente naviga alla pagina di sync,
      // all'interno di initState() protetto da try-catch.
      // ═══════════════════════════════════════════════════════════════════════
      runApp(const ProviderScope(child: SessionLifecycleObserver(child: MyApp())));
    },
    // ─────────────────────────────────────────────────────────────────────────
    // CATCH GLOBALE DEL runZonedGuarded:
    //
    // Cattura OGNI eccezione non gestita che non è stata catturata dai
    // try-catch interni. In release mode, logga l'errore senza crashare.
    //
    // Questo è l'ULTIMO catch-all del sistema: se un'eccezione arriva qui,
    // significa che tutti i livelli di protezione interni sono stati bypassati.
    // ─────────────────────────────────────────────────────────────────────────
    (error, stackTrace) {
      debugPrint('[RUNTIME_ERROR] Eccezione non gestita: $error');
      debugPrint('[RUNTIME_ERROR] Stack trace: $stackTrace');
    },
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET PRINCIPALE DELL'APPLICAZIONE
//
// MyApp è il widget radice dell'app CatechHub. Utilizza ConsumerWidget
// (Riverpod) per accedere agli stati globali (autenticazione, router,
// impostazioni privacy).
//
// Responsabilità:
// 1. Configurare il tema Material 3 con il colore primario dell'app
// 2. Gestire lo stato di autenticazione (login, sessione, errore)
// 3. Inizializzare Wiredash per il feedback utente (se abilitato)
// 4. Richiedere i permessi in sequenza controllata (notifiche, fotocamera)
// 5. Mostrare il sondaggio promoter mensile (casuale, se abilitato)
//
// Il widget NON gestisce direttamente la logica Bluetooth: quella è
// delegata alle pagine specifiche (sync, pairing) che la inizializzano
// nei loro metodi initState().
// ═══════════════════════════════════════════════════════════════════════════════

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  /// Project ID Wiredash per il feedback utente (letto da .env via EnvConfig).
  static String get _wiredashProjectId => EnvConfig.wiredashProjectId;

  /// Secret key Wiredash per l'autenticazione API (letto da .env via EnvConfig).
  static String get _wiredashSecret => EnvConfig.wiredashApiSecret;

  /// Flag per garantire che l'inizializzazione sequenziale venga eseguita
  /// una sola volta anche in caso di rebuild multipli del widget.
  static bool _initializationScheduled = false;

  /// Verifica che Wiredash sia configurato correttamente (projectId e secret non vuoti).
  bool get _wiredashConfigured =>
      _wiredashProjectId.isNotEmpty && _wiredashSecret.isNotEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Observation degli stati Riverpod necessari al rendering
    final authState = ref.watch(authStateProvider);
    final router = ref.watch(appRouterProvider);
    final privacy = ref.watch(privacySettingsProvider);

    // Programma l'inizializzazione sequenziale una sola volta.
    // addPostFrameCallback garantisce che il widget sia montato nel tree
    // prima di avviare le operazioni asincrone (permessi, dialog).
    if (!_initializationScheduled) {
      _initializationScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final navContext = navigatorKey.currentContext;
        if (navContext != null && navContext.mounted) {
          _runSequentialInitialization(navContext, ref, privacy);
        }
      });
    }

    // Verifica se l'utente è attualmente sulla route di login
    // (utilizzato per mostrare il caricamento senza splash screen)
    final isLoginRoute = router.routeInformationProvider.value.uri.path.startsWith('/login');

    // ═══════════════════════════════════════════════════════════════════════════
    // GESTIONE SICUREZZA freeRASP: ValueListenableBuilder per schermate di blocco
    // ═══════════════════════════════════════════════════════════════════════════
    //
    // Priorità di visualizzazione:
    // 1. Security Block Screen (rossa, NON bypassabile) - root, emulator, tamper, hook, deviceBinding
    // 2. Developer Options Warning Screen (arancione, BYPASSABILE) - devMode, ADB enabled, debugger
    // 3. App normale (router, auth, ecc.)
    //
    // L'ordine è importante: il blocco sicurezza (rosso) ha priorità sull'avviso (arancione).
    // ═══════════════════════════════════════════════════════════════════════════

    return ValueListenableBuilder<String?>(
      valueListenable: SecurityService.blockMessage,
      builder: (context, blockMsg, _) {
        // 1. SCHERMATA ROSSA DI BLOCCO SICUREZZA (NON bypassabile)
        if (blockMsg != null) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: SecurityBlockScreen(message: blockMsg),
          );
        }

        // 2. SCHERMATA ARANCIONE AVVISO OPZIONI SVILUPPATORE (BYPASSABILE)
        return ValueListenableBuilder<String?>(
          valueListenable: SecurityService.developerOptionsWarningMessage,
          builder: (context, warningMsg, _) {
            if (warningMsg != null) {
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                home: DeveloperOptionsWarningScreen(
                  message: warningMsg,
                  onContinue: () {
                    // L'utente ha scelto di continuare: resetta il messaggio
                    // per permettere alla app di procedere normalmente
                    SecurityService.developerOptionsWarningMessage.value = null;
                  },
                ),
              );
            }

            // 3. APP NORMALE
            Widget app = MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF174A7E)),
                scaffoldBackgroundColor: const Color(0xFFF5F7FB),
              ),
              navigatorKey: navigatorKey,
              home: authState.when(
                data: (_) {
                  return BackButtonHandler(
                    router: router,
                    child: Router(
                      routerDelegate: router.routerDelegate,
                      routeInformationParser: router.routeInformationParser,
                      routeInformationProvider: router.routeInformationProvider,
                    ),
                  );
                },
                loading: () => isLoginRoute
                    ? BackButtonHandler(
                        router: router,
                        child: Router(
                          routerDelegate: router.routerDelegate,
                          routeInformationParser: router.routeInformationParser,
                          routeInformationProvider: router.routeInformationProvider,
                        ),
                      )
                    : const _LoadingScreen(),
                error: (err, _) => _ErrorScreen(message: 'Errore Auth: $err'),
              ),
            );

            // Wrappa l'app con Wiredash SE l'utente ha acconsentito al feedback
            // remoto E il progetto Wiredash è configurato correttamente.
            // Wiredash permette all'utente di inviare feedback e segnalare bug.
            if (privacy.allowRemoteFeedback && _wiredashConfigured) {
              app = Wiredash(
                projectId: _wiredashProjectId,
                secret: _wiredashSecret,
                psOptions: const PsOptions(
                  frequency: Duration(days: 30),
                  initialDelay: Duration(days: 7),
                  minimumAppStarts: 0,
                ),
                child: app,
              );
            }

            return app;
          },
        );
      },
    );
  }

  /// ═══════════════════════════════════════════════════════════════════════════
  /// INIZIALIZZAZIONE SEQUENZIALE CONTROLLATA
  /// ═══════════════════════════════════════════════════════════════════════════
  /// Gestisce le richieste di permesso e le attivazioni in sequenza
  /// controllata, evitando di intasare il thread nativo hardware all'avvio.
  ///
  /// Ogni operazione è protetta da try-catch individuale per garantire
  /// che un errore in una fase non blocchi le successive.
  ///
  /// Sequenza:
  ///   1. Permesso notifiche (per aggiornamenti)
  ///   2. Permesso fotocamera (per scansione QR)
  ///   3. Sondaggio promoter mensile (casuale, se abilitato)
  /// ═══════════════════════════════════════════════════════════════════════════
  Future<void> _runSequentialInitialization(
    BuildContext context,
    WidgetRef ref,
    PrivacySettings privacy,
  ) async {
    // Se l'onboarding non è stato completato, salta tutta la
    // inizializzazione sequenziale (i permessi vengono gestiti
    // dall'onboarding stesso).
    try {
      final box = LocalDatabase.auth();
      final onboardingDone =
          box.get('onboarding_completed', defaultValue: false) as bool;
      if (!onboardingDone) return;
    } catch (_) {
      return;
    }

    try {
      await _requestNotificationPermissionIfNeeded(context);
      if (!context.mounted) return;

      await _requestCameraPermissionIfNeeded(context);
      if (!context.mounted) return;

      _showMonthlyRandomPromoterSurvey(context, privacy);
    } catch (e) {
      debugPrint('Errore durante l\'inizializzazione sequenziale: $e');
    }
  }

  /// Richiede il permesso delle notifiche se non è ancora stato concesso.
  ///
  /// Gestisce i diversi stati del permesso:
  /// - granted/limited: già concesso, non fare nulla
  /// - permanentlyDenied/restricted: mostra dialog per aprire le impostazioni
  /// - denied: richiedi il permesso dopo conferma dell'utente
  ///
  /// Il permesso è necessario per le notifiche di aggiornamento dell'app.
  Future<void> _requestNotificationPermissionIfNeeded(BuildContext context) async {
    final authBox = LocalDatabase.auth();
    final notificationRequested =
        authBox.get('notification_permission_requested', defaultValue: false) as bool;

    final status = await UpdateService.notificationPermissionStatus();
    if (status == PermissionStatus.granted || status == PermissionStatus.limited) {
      return;
    }

    if (!context.mounted) return;

    if (status == PermissionStatus.permanentlyDenied || status == PermissionStatus.restricted) {
      await _showNotificationSettingsDialog(context);
      return;
    }

    final shouldRequest = !notificationRequested || status == PermissionStatus.denied;
    if (!shouldRequest) return;

    final confirmation = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Permesso notifiche'),
        content: const Text(
          'CatechHub usa le notifiche per avvisarti degli aggiornamenti e delle novità. '
          'Vuoi permettere all\'app di inviarti notifiche?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Rifiuta'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Consenti'),
          ),
        ],
      ),
    );

    await authBox.put('notification_permission_requested', true);
    if (confirmation != true || !context.mounted) return;

    final newStatus = await UpdateService.requestNotificationPermission();
    if (newStatus == PermissionStatus.granted || newStatus == PermissionStatus.limited) {
      return;
    }

    if ((newStatus == PermissionStatus.permanentlyDenied || newStatus == PermissionStatus.restricted) && context.mounted) {
      await _showNotificationSettingsDialog(context);
    }
  }

  /// Richiede il permesso della fotocamera se non è ancora stato concesso.
  ///
  /// La fotocamera è necessaria per:
  /// - Scansione codici QR durante il pairing Bluetooth tra dispositivi
  /// - Scatto foto per gli allegati cifrati degli studenti/incontri
  ///
  /// Gestisce i diversi stati del permesso con la stessa logica
  /// delle notifiche (consenso → richiesta → fallback impostazioni).
  Future<void> _requestCameraPermissionIfNeeded(BuildContext context) async {
    final authBox = LocalDatabase.auth();
    final cameraRequested =
        authBox.get('camera_permission_requested', defaultValue: false) as bool;

    final status = await Permission.camera.status;
    if (status.isGranted) {
      return;
    }

    if (!context.mounted) return;

    if (status.isPermanentlyDenied || status.isRestricted) {
      await _showCameraSettingsDialog(context);
      return;
    }

    final shouldRequest = !cameraRequested || status.isDenied;
    if (!shouldRequest) return;

    final confirmation = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Permesso fotocamera'),
        content: const Text(
          'CatechHub usa la fotocamera per scansionare i codici QR '
          'per il backup/ripristino dei dati. '
          'Vuoi permettere all\'app di accedere alla fotocamera?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Rifiuta'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(),
            child: const Text('Consenti'),
          ),
        ],
      ),
    );

    await authBox.put('camera_permission_requested', true);
    if (confirmation != true || !context.mounted) return;

    final newStatus = await Permission.camera.request();
    if (newStatus.isGranted) {
      return;
    }

    if ((newStatus.isPermanentlyDenied || newStatus.isRestricted) && context.mounted) {
      await _showCameraSettingsDialog(context);
    }
  }

  /// Mostra un dialog che invita l'utente ad aprire le impostazioni del sistema
  /// per attivare manualmente le notifiche, quando il permesso è stato
  /// negato permanentemente dall'utente.
  Future<void> _showNotificationSettingsDialog(BuildContext context) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Notifiche disattivate'),
        content: const Text(
          'Le notifiche non sono abilitate. Per ricevere gli avvisi di aggiornamento, '
          'devi attivare le notifiche nelle impostazioni del sistema.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              UpdateService.openNotificationSettings();
            },
            child: const Text('Apri impostazioni'),
          ),
        ],
      ),
    );
  }

  /// Mostra un dialog che invita l'utente ad aprire le impostazioni del sistema
  /// per concedere manualmente il permesso della fotocamera, quando è stato
  /// negato permanentemente dall'utente.
  Future<void> _showCameraSettingsDialog(BuildContext context) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Fotocamera non autorizzata'),
        content: const Text(
          'Per scansionare i codici QR e associare dispositivi, '
          'devi concedere l\'autorizzazione alla fotocamera nelle impostazioni del dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Apri impostazioni'),
          ),
        ],
      ),
    );
  }

  /// Mostra il sondaggio promoter di Wiredash in modo casuale mensile.
  ///
  /// Il sondaggio chiede all'utente di valutare l'app (promoter score).
  /// Viene mostrato:
  /// - La prima volta: dopo 7-30 giorni dall'installazione (casuale)
  /// - Successivamente: ogni 30-45 giorni (casuale)
  ///
  /// La prossima data di visualizzazione viene memorizzata nel Box auth
  /// di Hive con la chiave 'wiredash_promoter_next_date'.
  ///
  /// Il sondaggio NON viene mostrato se:
  /// - L'utente non ha acconsentito al feedback remoto
  /// - Wiredash non è configurato
  /// - Il contesto non è più montato
  void _showMonthlyRandomPromoterSurvey(BuildContext context, PrivacySettings privacy) {
    if (!privacy.allowRemoteFeedback || !_wiredashConfigured || !context.mounted) {
      return;
    }

    final box = LocalDatabase.auth();
    final now = DateTime.now().toUtc();
    final nextSurveyKey = 'wiredash_promoter_next_date';
    final nextSurveyValue = box.get(nextSurveyKey) as String?;
    DateTime? nextSurveyDate;

    if (nextSurveyValue != null) {
      nextSurveyDate = DateTime.tryParse(nextSurveyValue)?.toUtc();
    }

    // Prima visita: programma la prima visualizzazione tra 7 e 30 giorni
    if (nextSurveyDate == null) {
      final scheduledDate = now.add(Duration(days: 7 + Random().nextInt(24)));
      box.put(nextSurveyKey, scheduledDate.toIso8601String());
      return;
    }

    // Non è ancora ora di mostrare il sondaggio
    if (now.isBefore(nextSurveyDate)) {
      return;
    }

    try {
      Wiredash.of(context).showPromoterSurvey(inheritMaterialTheme: true);
      // Programma la prossima visualizzazione tra 30 e 45 giorni
      final nextScheduledDate = now.add(Duration(days: 30 + Random().nextInt(15)));
      box.put(nextSurveyKey, nextScheduledDate.toIso8601String());
    } catch (_) {}
  }

}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET DI SUPPORTO (schermate di caricamento, errore e errore fatale)
//
// Widget privati utilizzati durante il bootstrap dell'app per mostrare
// stati transitori (caricamento) o condizioni di errore.
// ═══════════════════════════════════════════════════════════════════════════════

/// Schermata di caricamento mostrata durante l'autenticazione.
/// Visualizza un indicatore di progresso circolare nel colore primario dell'app.
/// Viene mostrata quando lo stato di auth è in fase di loading e l'utente
/// non è ancora sulla route di login.
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Color(0xFF174A7E))),
    );
  }
}

/// Schermata di errore generica per errori di autenticazione.
/// Mostra un messaggio di errore leggibile all'utente.
/// Viene mostrata quando lo stato di auth è in errore.
class _ErrorScreen extends StatelessWidget {
  final String message;
  const _ErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// Schermata di errore fatale mostrata quando l'inizializzazione del database
/// o del sistema fallisce criticamente all'avvio, impedendo il funzionamento
/// dell'applicazione.
///
/// Mostra un messaggio leggibile all'utente con istruzioni per risolvere
/// il problema (es. reinstallazione dell'app). Questa schermata sostituisce
/// l'intero MaterialApp: non ha router, non ha stato, non ha interattività
/// oltre il messaggio di errore.
///
/// Viene utilizzata in due casi:
/// 1. Hive.initFlutter() fallisce anche dopo il recovery dei file .lock
/// 2. LocalDatabase.init() fallisce dopo tutti i tentativi di corruption recovery
class _FatalErrorApp extends StatelessWidget {
  final String message;
  const _FatalErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 64,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Errore di Inizializzazione',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
