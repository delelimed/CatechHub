// ═══════════════════════════════════════════════════════════════════════════════
// security_service.dart — CatechHub (Servizio di Sicurezza freeRASP v8+)
// ═══════════════════════════════════════════════════════════════════════════════
//
// SERVIZIO DI SICUREZZA freeRASP v8+
//
// Questo servizio incapsula l'inizializzazione e la gestione dello stato
// di freeRASP (pacchetto `freerasp` v8+) per la protezione runtime
// dell'applicazione Android CatechHub.
//
// ARCHITETTURA:
// ──────────────────────────────────────────────────────────────────────────────
// • Singleton pattern con ValueNotifier per lo stato reattivo
// • Inizializzazione lazy in `init()` chiamata PRIMA di runApp() nel main()
// • Callback freeRASP aggiornano un ValueNotifier<String?> che espone il
//   messaggio di blocco (null = sicuro, stringa = messaggio di blocco)
// • Il widget radice (MyApp) ascolta questo notifier via ValueListenableBuilder
//   e mostra SecurityBlockScreen se c'è un messaggio, altrimenti la Home normale
//
// CONFIGURAZIONE TALSECCONFIG (freeRASP v8+):
// ──────────────────────────────────────────────────────────────────────────────
// • Package name e Release Hash (SHA-256 Base64) letti da --dart-define
//   (iniettati via --dart-define-from-file=.env in build release)
// • `killOnBypass: false` → freeRASP NON chiude l'app con SystemNavigator.pop
//   ma chiama solo i callback → noi mostriamo SecurityBlockScreen rossa
// • `watcherMail: 'catechhub.app@proton.me'` per report email
// • `isProd: !kDebugMode` → protezioni attive solo in Release
// • `supportedStores: []` → solo Play Store (lista vuota = solo Play Store)
//
// CALLBACK DI SICUREZZA (ThreatCallback):
// ──────────────────────────────────────────────────────────────────────────────
// • onPrivilegedAccess → "Root rilevato"
// • onSimulator → "Emulatore non consentito"
// • onAppIntegrity → "Firma dell'applicazione manomessa"
// • onHooks → "Tentativo di Hooking"
// • onDeviceBinding → "Binding dispositivo violato"
// • onUnofficialStore → SOLO print warning, NON blocca
//
// INTEGRAZIONE IN main.dart:
// ──────────────────────────────────────────────────────────────────────────────
// main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   await SecurityService.init();  // ← PRIMA di runApp()
//   runApp(const MyApp());
// }
//
// class MyApp extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return ValueListenableBuilder<String?>(
//       valueListenable: SecurityService.blockMessage,
//       builder: (_, blockMsg, __) {
//         if (blockMsg != null) return SecurityBlockScreen(message: blockMsg);
//         return MaterialApp(...); // App normale
//       },
//     );
//   }
// }
//
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:freerasp/freerasp.dart';
import 'package:CatechHub/core/config/env_config.dart';

/// Servizio Singleton per la gestione della sicurezza runtime con freeRASP v8+.
///
/// Espone un [ValueNotifier<String?>] ([blockMessage]) che notifica
/// se freeRASP ha rilevato un'anomalia di sicurezza.
///
/// - `null` → ambiente sicuro, app normale
/// - `String` → messaggio di blocco (es. "Root rilevato"), mostra SecurityBlockScreen
///
/// Deve essere inizializzato PRIMA di `runApp()` nel `main()`.
class SecurityService {
  SecurityService._();

  /// Istanza singleton.
  static final SecurityService _instance = SecurityService._();

  /// Accessor singleton.
  static SecurityService get instance => _instance;

  /// Notifier reattivo per lo stato di blocco sicurezza.
  ///
  /// - `null` = ambiente sicuro, mostra app normale
  /// - `String` = messaggio di blocco (es. "Root rilevato"), mostra SecurityBlockScreen
  static final ValueNotifier<String?> blockMessage = ValueNotifier<String?>(null);

  /// Flag per evitare doppia inizializzazione.
  static bool _initialized = false;

  /// Completer per attendere il completamento dell'inizializzazione.
  static final Completer<void> _initCompleter = Completer<void>();

  /// Future che completa quando l'inizializzazione è terminata.
  static Future<void> get initialized => _initCompleter.future;

  /// Inizializza freeRASP con configurazione TalsecConfig per Android.
  ///
  /// Deve essere chiamata **DOPO** `WidgetsFlutterBinding.ensureInitialized()`
  /// e **PRIMA** di `runApp()`.
  ///
  /// Legge la configurazione da `.env` (caricato via `flutter_dotenv`):
  /// - `FREERASP_PACKAGE_NAME` (es. `com.delelimed.catechhub`)
  /// - `FREERASP_RELEASE_HASH` (SHA-256 del certificato in Base64)
  ///
  /// In Release (`!kDebugMode`), se una delle due è vuota, lancia
  /// [StateError] per evitare build non protette in produzione.
  ///
  /// Configura `killOnBypass: false` per delegare la UI di blocco
  /// a [SecurityBlockScreen] invece di far killare l'app da freeRASP.
  static Future<void> init() async {
    if (_initialized) {
      debugPrint('[SecurityService] Già inizializzato, salto.');
      return;
    }

    debugPrint('[SecurityService] Inizializzazione freeRASP...');

    // ─── Lettura configurazione da .env (caricato via flutter_dotenv) ───
    await EnvConfig.load();
    final String packageName = EnvConfig.freeraspPackageName;
    final String releaseHash = EnvConfig.freeraspReleaseHash;

    // In Release, le variabili DEVONO essere presenti nel file .env
    if (!kDebugMode) {
      if (packageName.isEmpty) {
        throw StateError(
          '[SecurityService] FREERASP_PACKAGE_NAME non definito nel file .env. '
          'In build Release, deve essere presente nel file .env incluso negli asset.',
        );
      }
      if (releaseHash.isEmpty) {
        throw StateError(
          '[SecurityService] FREERASP_RELEASE_HASH non definito nel file .env. '
          'In build Release, deve essere presente nel file .env '
          '(SHA-256 del certificato di firma in Base64)',
        );
      }
    }

    debugPrint('[SecurityService] Package: $packageName');
    debugPrint('[SecurityService] Release Hash: ${releaseHash.isNotEmpty ? "presente (${releaseHash.length} char)" : "vuoto (debug mode)"}');
    debugPrint('[SecurityService] Debug Mode: $kDebugMode');

    // ─── Configurazione AndroidConfig (freeRASP v8+) ───
    final androidConfig = AndroidConfig(
      packageName: packageName,
      signingCertHashes: releaseHash.isNotEmpty ? [releaseHash] : [],
      supportedStores: const [], // Lista vuota = solo Google Play Store
    );

    // ─── Configurazione TalsecConfig (freeRASP v8+) ───
    final talsecConfig = TalsecConfig(
      androidConfig: androidConfig,
      watcherMail: 'catechhub.app@proton.me',
      isProd: !kDebugMode, // Protezioni attive solo in Release
      killOnBypass: false, // NON killare l'app: usiamo SecurityBlockScreen
    );

    // ─── Inizializzazione freeRASP con callback ───
    try {
      // Inizializza Talsec (singleton) - metodo 'start' in freeRASP v8+
      await Talsec.instance.start(talsecConfig);

      // Registra i callback di sicurezza
      Talsec.instance.attachListener(_buildThreatCallback());

      _initialized = true;
      _initCompleter.complete();
      debugPrint('[SecurityService] freeRASP inizializzato con successo');
    } catch (e, stack) {
      debugPrint('[SecurityService] ERRORE inizializzazione freeRASP: $e');
      debugPrint('$stack');
      _initCompleter.completeError(e, stack);
      rethrow;
    }
  }

  /// Costruisce il ThreatCallback con i gestori per ogni tipo di minaccia.
  static ThreatCallback _buildThreatCallback() {
    return ThreatCallback(
      onPrivilegedAccess: _onRootDetected,
      onSimulator: _onEmulatorDetected,
      onAppIntegrity: _onTamperDetected,
      onHooks: _onHookDetected,
      onDeviceBinding: _onDeviceBindingDetected,
      onUnofficialStore: _onUntrustedInstallationSourceDetected,
      onADBEnabled: _onADBEnabledDetected,
      onDebug: _onDebuggerAttachedDetected,
      onDevMode: _onDeveloperOptionsEnabledDetected,
    );
  }

  /// Reset dello stato di blocco (per testing o reset manuale).
  ///
  /// ⚠️ USARE SOLO IN DEBUG/TESTING. In produzione, un blocco
  /// sicurezza NON deve essere resettabile dall'utente.
  static void resetBlockState() {
    if (kDebugMode) {
      blockMessage.value = null;
      debugPrint('[SecurityService] Stato blocco resettato (DEBUG ONLY)');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // CALLBACK DI SICUREZZA FREE_RASP
  // ══════════════════════════════════════════════════════════════════════════════

  /// Callback: Root rilevato (device rooted / Magisk / KernelSU / etc.)
  static void _onRootDetected() {
    const msg = 'Root rilevato';
    _triggerBlock(msg);
  }

  /// Callback: Emulatore rilevato (non device fisico)
  static void _onEmulatorDetected() {
    const msg = 'Emulatore non consentito';
    _triggerBlock(msg);
  }

  /// Callback: Tampering rilevato (firma APK modificata, codice alterato)
  static void _onTamperDetected() {
    const msg = 'Firma dell\'applicazione manomessa';
    _triggerBlock(msg);
  }

  /// Callback: Hooking rilevato (Frida, Xposed, Substrate, ecc.)
  static void _onHookDetected() {
    const msg = 'Tentativo di Hooking';
    _triggerBlock(msg);
  }

  /// Callback: Device Binding violato (device non più autorizzato)
  static void _onDeviceBindingDetected() {
    const msg = 'Binding dispositivo violato';
    _triggerBlock(msg);
  }

  /// Callback: Sorgente di installazione non fidata (non Play Store).
  ///
  /// NOTA: Per requisito, NON blocca l'app, fa solo logging di warning.
  static void _onUntrustedInstallationSourceDetected() {
    const msg = 'Installazione da fonte non attendibile (non Play Store)';
    debugPrint('[SecurityService] WARNING: $msg');
    // NON chiamare _triggerBlock() → l'app continua a funzionare
  }

  /// Callback: ADB abilitato (debug USB attivo o ADB wireless).
  ///
  /// BLOCCA l'avvio dell'applicazione con schermata rossa.
  static void _onADBEnabledDetected() {
    const msg = 'Debug USB attivo rilevato';
    _triggerBlock(msg);
  }

  /// Callback: Debugger connesso (attached debugger).
  ///
  /// BLOCCA l'avvio dell'applicazione con schermata rossa.
  static void _onDebuggerAttachedDetected() {
    const msg = 'Debugger connesso rilevato';
    _triggerBlock(msg);
  }

  /// Callback: Opzioni sviluppatore attive.
  ///
  /// MOSTRA una schermata ARANCIONE di avviso (BYPASSABILE),
  /// NON blocca l'avvio dell'applicazione.
  static void _onDeveloperOptionsEnabledDetected() {
    const msg = 'Opzioni sviluppatore attive rilevate';
    debugPrint('[SecurityService] AVVISO: $msg');
    // Usa un notifier separato per la schermata arancione bypassabile
    WidgetsBinding.instance.addPostFrameCallback((_) {
      developerOptionsWarningMessage.value = msg;
    });
  }

  /// Notifier per la schermata di avviso opzioni sviluppatore (arancione, bypassabile).
  ///
  /// - `null` = nessun avviso, app normale
  /// - `String` = messaggio di avviso, mostra DeveloperOptionsWarningScreen
  static final ValueNotifier<String?> developerOptionsWarningMessage = ValueNotifier<String?>(null);

  /// Attiva lo stato di blocco e notifica l'UI (schermata rossa, NON bypassabile).
  static void _triggerBlock(String message) {
    debugPrint('[SecurityService] BLOCCO SICUREZZA: $message');
    // Usa WidgetsBinding per essere sicuri che il notifier sia sul main thread
    WidgetsBinding.instance.addPostFrameCallback((_) {
      blockMessage.value = message;
    });
  }
}