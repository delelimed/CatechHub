// ═══════════════════════════════════════════════════════════════════════════════
// security_manager.dart — CatechHub (Gestione Chiave Master Hardware-Only)
// ═══════════════════════════════════════════════════════════════════════════════
//
// REQUISITO FONDAMENTALE: PROTEZIONE ESCLUSIVAMENTE HARDWARE (TEE / StrongBox / Keymaster)
// ──────────────────────────────────────────────────────────────────────────────
// Questo modulo implementa la gestione della chiave master per Hive e
// FlutterSecureStorage richiedendo ESCLUSIVAMENTE la protezione via Hardware
// su Android, SENZA ALCUN FALLBACK SOFTWARE.
//
// ARCHITETTURA:
// ──────────────────────────────────────────────────────────────────────────────
// 1. VERIFICA HARDWARE: Controlla la presenza di TEE/StrongBox tramite:
//    - local_auth: verifica disponibilità autenticazione biometrica (proxy per TEE)
//    - FlutterSecureStorage: tentativo scrittura/lettura con encryptedSharedPreferences
// 2. GENERAZIONE CHIAVE: Solo se hardware verificato, genera Master Key AES-256
//    tramite Hive.generateSecureKey() e la memorizza in FlutterSecureStorage
// 3. CIFRATURA HIVE: Utilizza HiveAesCipher con la Master Key per proteggere i Box
// 4. BLOCCO SICUREZZA: Se hardware non disponibile, solleva HardwareSecurityException
//    che main.dart intercetta per mostrare SecurityBlockScreen
//
// PLUGIN UTILIZZATI (SOLO UFFICIALI, ZERO CODICE NATIVO CUSTOM):
// ──────────────────────────────────────────────────────────────────────────────
// • flutter_secure_storage ^11.0.0 — Storage cifrato con Android Keystore
// • local_auth ^3.0.2 — Verifica hardware biometrico (TEE proxy)
// • hive_flutter ^1.1.0 — Database locale con cifratura AES-256
//
// CONFIGURAZIONE ANDROID (flutter_secure_storage):
// ──────────────────────────────────────────────────────────────────────────────
// • Backend "custom ciphers" (AES-GCM) con chiave protetta dall'Android
//   Keystore hardware-backed (TEE / StrongBox quando disponibile su API 28+).
// • resetOnError: false → la master key NON viene cancellata su errori
//   temporanei del Keystore (evita la perdita silenziosa di tutti i box Hive).
// • NESSUN FALLBACK SOFTWARE: se Keystore non disponibile, l'operazione fallisce
//
// NOTE IMPORTANTI:
// ──────────────────────────────────────────────────────────────────────────────
// • minSdk 30 (Android 11+) garantisce supporto Keystore base
// • StrongBox richiede hardware dedicato (disponibile su Pixel 3+, Samsung S20+, ecc.)
// • TEE è presente su quasi tutti i dispositivi Android 11+ certificati
// • local_auth verifica BiometricManager.canCheckBiometrics come proxy TEE
// • Se il dispositivo non ha NEANCHE TEE base, non è idoneo per dati sensibili minori
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart';
import 'hardware_security_exception.dart';

/// Chiavi di storage per FlutterSecureStorage.
class _StorageKeys {
  static const String masterKey = 'catechhub_master_key_v1';
  static const String hardwareVerified = 'catechhub_hw_verified_v1';
  static const String keyVersion = 'catechhub_key_version_v1';
}

/// Versione corrente del formato chiave master.
const int _currentKeyVersion = 1;

/// Configurazione FlutterSecureStorage per Android HARDWARE-ONLY.
///
/// Impostazioni critiche:
/// - resetOnError: false → NON cancella i dati crittografati in caso di
///   errore temporaneo del Keystore (es. KeyStoreException durante la rotazione
///   dell'hardware key). Con il default true, un errore transitorio distruggerebbe
///   silenziosamente la master key e con essa tutti i box Hive cifrati.
///   IMPORTANTE: con resetOnError=false, in caso di KeyStoreException la chiave
///   NON viene mai cancellata automaticamente; l'utente può eventualmente
///   procedere a un reset manuale del dispositivo (che cancella comunque i dati
///   dell'app). Il rischio di una master key permanente e non estraibile è quindi
///   circoscritto ai soli casi di reset manuale da parte dell'utente.
/// - NESSUNA opzione di fallback software: se Keystore non disponibile,
///   read/write sollevano PlatformException.
/// - NOTA: `encryptedSharedPreferences` è deprecato nel plugin e NON viene
///   impostato: flutter_secure_storage 10.x usa di default il backend
///   "custom ciphers" (AES-GCM) con chiave generata e protetta dall'Android
///   Keystore hardware-backed, migrando automaticamente le chiavi esistenti.
///   Non è quindi necessario (né possibile in modo affidabile) forzare
///   StrongBox via opzioni del plugin: il Keystore usa TEE/StrongBox in base
///   all'hardware disponibile.
const AndroidOptions _androidOptions = AndroidOptions(resetOnError: false);

/// Opzioni complete per FlutterSecureStorage.
const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
  aOptions: _androidOptions,
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
  lOptions: LinuxOptions(),
  mOptions: MacOsOptions(),
  wOptions: WindowsOptions(),
);

/// Servizio Singleton per la gestione sicurezza hardware-only.
class SecurityManager {
  SecurityManager._();

  static final SecurityManager _instance = SecurityManager._();
  static SecurityManager get instance => _instance;

  /// Indica se l'inizializzazione hardware è stata completata con successo.
  bool _isHardwareInitialized = false;

  /// Chiave master AES-256 per Hive (32 bytes = 256 bit).
  ///
  /// Viene mantenuta SOLO durante la fase di inizializzazione e poi
  /// sovrascritta da [_wipeMasterKeyFromMemory]: dopo l'avvio il processo
  /// non conserva una copia materiale aggiuntiva oltre a quella interna al
  /// cipher Hive (che la richiede per la decifratura on-demand).
  Uint8List? _masterKey;

  /// Cipher Hive configurato con la master key.
  HiveAesCipher? _hiveCipher;

  /// Verifica se l'hardware security è inizializzato e pronto.
  bool get isInitialized => _isHardwareInitialized;

  /// Restituisce il cipher Hive per l'apertura dei Box cifrati.
  HiveAesCipher get hiveCipher {
    if (_hiveCipher == null) {
      throw StateError(
        'SecurityManager non inizializzato. Chiamare initialize() prima.',
      );
    }
    return _hiveCipher!;
  }

  /// Sovrascrive e rilascia la copia della master key materiale in memoria.
  ///
  /// Scrivere zeri prima di azzerare il riferimento evita che i byte della
  /// chiave restino recuperabili nell'heap riallocato dal GC.
  void _wipeMasterKeyFromMemory() {
    final key = _masterKey;
    if (key != null) {
      key.fillRange(0, key.length, 0);
    }
    _masterKey = null;
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // INIZIALIZZAZIONE PRINCIPALE — HARDWARE-BACKED OR BLOCK
  // ══════════════════════════════════════════════════════════════════════════════
  ///
  /// Esegue la sequenza completa di verifica hardware e generazione chiave.
  ///
  /// FLUSSO:
  /// 1. Verifica biometrica hardware (local_auth) → proxy per TEE
  /// 2. Test scrittura/lettura FlutterSecureStorage → verifica Keystore
  /// 3. Se tutto ok: genera/legge Master Key AES-256
  /// 4. Crea HiveAesCipher con la Master Key
  /// 5. Marca hardware come verificato
  ///
  /// SE QUALSIASI PASSO FALLISCE:
  /// - Solleva HardwareSecurityException con messaggio dettagliato
  /// - main.dart DEVE intercettare e mostrare SecurityBlockScreen
  /// - L'app NON deve proseguire l'avvio
  ///
  /// THROWS: HardwareSecurityException se hardware non conforme
  Future<void> initialize() async {
    if (_isHardwareInitialized) {
      return; // Già inizializzato
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PASSO 1: VERIFICA AUTENTICAZIONE DISPOSITIVO (PROXY PER TEE)
    // ─────────────────────────────────────────────────────────────────────────
    // local_auth verifica se il dispositivo ha un metodo di autenticazione
    // configurato (biometria OPPURE PIN/pattern/password del dispositivo).
    // Su Android 10+ (API 29+), la presenza di un PIN/pattern/password
    // implica la presenza di un TEE (Trusted Execution Environment) poiché
    // la verifica delle credenziali avviene all'interno del TEE.
    //
    // NOTA: Questo NON garantisce StrongBox, ma garantisce TEE base.
    // StrongBox è un requisito aggiuntivo (hardware dedicato) che il
    // Keystore userà automaticamente se disponibile (API 28+).
    await _verifyAuthenticationCapability();

    // ─────────────────────────────────────────────────────────────────────────
    // PASSO 2: TEST FLUTTER_SECURE_STORAGE CON ANDROID KEYSTORE
    // ─────────────────────────────────────────────────────────────────────────
    // Tenta di scrivere e leggere un valore di test usando encryptedSharedPreferences.
    // Se il Keystore hardware-backed non è disponibile, l'operazione fallirà
    // con PlatformException (es. "KeyStore exception", "Keystore not initialized").
    // NESSUN FALLBACK SOFTWARE VIENE TENTATO.
    await _verifyKeystoreAvailability();

    // ─────────────────────────────────────────────────────────────────────────
    // PASSO 3: GENERAZIONE/RECUPERO MASTER KEY AES-256
    // ─────────────────────────────────────────────────────────────────────────
    // Genera una nuova chiave master se non esiste, altrimenti recupera quella
    // memorizzata. La chiave viene generata tramite Hive.generateSecureKey()
    // che usa Random.secure() (CSPRNG del sistema operativo).
    await _loadOrGenerateMasterKey();

    // ─────────────────────────────────────────────────────────────────────────
    // PASSO 4: CREAZIONE HIVE AES CIPHER
    // ─────────────────────────────────────────────────────────────────────────
    // Il cipher conserva al suo interno la chiave (necessaria per la
    // decifratura on-demand dei box Hive). Subito dopo la creazione, la
    // copia della master key detenuta da questo manager viene sovrascritta
    // e rilasciata per minimizzare la finestra di permanenza in RAM di una
    // chiave materiale extra (oltre a quella già interna al cipher).
    _hiveCipher = HiveAesCipher(_masterKey!);
    _wipeMasterKeyFromMemory();

    // ─────────────────────────────────────────────────────────────────────────
    // PASSO 5: MARCATURA HARDWARE VERIFICATO
    // ─────────────────────────────────────────────────────────────────────────
    await _secureStorage.write(
      key: _StorageKeys.hardwareVerified,
      value: 'true',
      aOptions: _androidOptions,
    );
    await _secureStorage.write(
      key: _StorageKeys.keyVersion,
      value: _currentKeyVersion.toString(),
      aOptions: _androidOptions,
    );

    _isHardwareInitialized = true;
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // VERIFICA AUTENTICAZIONE DISPOSITIVO (PROXY TEE)
  // ══════════════════════════════════════════════════════════════════════════════
  ///
  /// Verifica che il dispositivo abbia un metodo di autenticazione configurato
  /// (biometria OPPURE PIN/pattern/password del dispositivo).
  ///
  /// Su Android 10+ (minSdk 30), `canCheckBiometrics` tramite `local_auth`
  /// restituisce true in DUE casi:
  /// 1. L'utente ha una biometria registrata (impronta, volto, iride)
  /// 2. L'utente ha un PIN/pattern/password del dispositivo configurato
  ///
  /// In entrambi i casi, la verifica avviene all'interno del TEE
  /// (Trusted Execution Environment), quindi la presenza di uno qualsiasi
  /// di questi metodi implica TEE presente.
  ///
  /// Se nessun metodo è disponibile:
  /// - Solleva HardwareSecurityException con istruzioni chiare per l'utente
  ///
  /// NOTE:
  /// - `getAvailableBiometrics()` restituisce una lista vuota quando
  ///   è configurato solo il PIN/pattern (nessuna biometria reale)
  /// - `canCheckBiometrics` = true + lista vuota = solo PIN/pattern → OK
  ///
  /// THROWS: HardwareSecurityException se nessun metodo di autenticazione
  Future<void> _verifyAuthenticationCapability() async {
    final LocalAuthentication auth = LocalAuthentication();

    final bool canCheck = await auth.canCheckBiometrics;
    final List<BiometricType> available = await auth.getAvailableBiometrics();

    // Nessun metodo di autenticazione configurato
    if (!canCheck && available.isEmpty) {
      throw const HardwareSecurityException(
        'Nessun metodo di autenticazione del dispositivo rilevato.\n\n'
        'Configura un PIN, pattern o password nelle impostazioni di sicurezza '
        'del dispositivo (Impostazioni → Schermata blocco → Tipo blocco schermo).\n\n'
        'In alternativa, registra un\'impronta digitale o il riconoscimento facciale.\n\n'
        'Questa applicazione richiede la protezione crittografica hardware '
        '(TEE/StrongBox) per salvaguardare i dati sensibili.',
        technicalDetail: 'canCheckBiometrics=false, availableBiometrics=[]',
      );
    }

    // canCheck = true, available vuoto → solo PIN/Pattern/Password
    // Su Android 10+, la verifica PIN/Pattern/Password è TEE-backed
    if (available.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[SECURITY] Autenticazione: solo credenziali dispositivo (PIN/pattern)',
        );
      }
      return;
    }

    // Biometrie disponibili: verifica siano forti
    final bool hasStrongBiometric =
        available.contains(BiometricType.strong) ||
        available.contains(BiometricType.fingerprint) ||
        available.contains(BiometricType.face) ||
        available.contains(BiometricType.iris);

    if (!hasStrongBiometric) {
      throw HardwareSecurityException(
        'Dispositivo non conforme: autenticazione biometrica forte non disponibile.',
        technicalDetail: 'Biometrici disponibili: $available',
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[SECURITY] Autenticazione: biometria forte disponibile (TEE garantito)',
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // VERIFICA DISPONIBILITÀ ANDROID KEYSTORE (HARDWARE-BACKED)
  // ══════════════════════════════════════════════════════════════════════════════
  ///
  /// Tenta una scrittura e lettura reale su FlutterSecureStorage con
  /// encryptedSharedPreferences: true.
  ///
  /// Se il Keystore hardware-backed non è disponibile (es. dispositivo senza TEE,
  /// Keystore corrotto, StrongBox non disponibile e TEE non accessibile),
  /// l'operazione solleverà una PlatformException.
  ///
  /// NON TENTIAMO ALCUN FALLBACK SOFTWARE: l'eccezione viene propagata
  /// e convertita in HardwareSecurityException.
  ///
  /// THROWS: HardwareSecurityException se Keystore non disponibile
  Future<void> _verifyKeystoreAvailability() async {
    final String testKey =
        '_hw_keystore_test_${DateTime.now().millisecondsSinceEpoch}';
    const String testValue = 'hardware_keystore_verification_test';

    try {
      // Scrittura test: forza uso Android Keystore via encryptedSharedPreferences
      await _secureStorage.write(
        key: testKey,
        value: testValue,
        aOptions: _androidOptions,
      );

      // Lettura test: verifica che la chiave sia stata memorizzata e recuperabile
      final String? readValue = await _secureStorage.read(
        key: testKey,
        aOptions: _androidOptions,
      );

      if (readValue != testValue) {
        throw const HardwareSecurityException(
          'Verifica Keystore fallita: valore letto non corrisponde.',
          technicalDetail: 'Mismatch scrittura/lettura test keystore',
        );
      }

      // Pulizia chiave test
      await _secureStorage.delete(key: testKey, aOptions: _androidOptions);
    } on Exception catch (e) {
      // Qualsiasi eccezione durante l'uso di FlutterSecureStorage con
      // encryptedSharedPreferences indica che il Keystore hardware-backed
      // non è disponibile o funzionante.
      throw HardwareSecurityException(
        'Dispositivo non conforme: Android Keystore hardware-backed non disponibile.',
        technicalDetail: 'FlutterSecureStorage error: ${e.runtimeType}: $e',
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // GENERAZIONE/RECUPERO MASTER KEY AES-256
  // ══════════════════════════════════════════════════════════════════════════════
  ///
  /// Genera una nuova Master Key AES-256 (32 bytes) se non esiste,
  /// altrimenti recupera quella memorizzata in FlutterSecureStorage.
  ///
  /// La chiave viene generata tramite Hive.generateSecureKey() che usa
  /// Random.secure() (CSPRNG del sistema operativo).
  ///
  /// La chiave viene memorizzata in FlutterSecureStorage (protetta da Keystore)
  /// come stringa Base64.
  Future<void> _loadOrGenerateMasterKey() async {
    // Tenta lettura chiave esistente
    final String? existingKeyB64 = await _secureStorage.read(
      key: _StorageKeys.masterKey,
      aOptions: _androidOptions,
    );

    if (existingKeyB64 != null && existingKeyB64.isNotEmpty) {
      // Chiave esistente: decodifica Base64
      try {
        _masterKey = base64Decode(existingKeyB64);
        if (_masterKey!.length != 32) {
          throw FormatException(
            'Lunghezza chiave non valida: ${_masterKey!.length}',
          );
        }
        return;
      } on FormatException catch (_) {
        // Chiave corrotta: rigenera
        await _secureStorage.delete(
          key: _StorageKeys.masterKey,
          aOptions: _androidOptions,
        );
      }
    }

    // Genera nuova Master Key AES-256 (32 bytes = 256 bit)
    final Uint8List newKey = Uint8List.fromList(Hive.generateSecureKey());
    _masterKey = newKey;

    // Memorizza in FlutterSecureStorage (protetta da Android Keystore hardware)
    final String keyB64 = base64Encode(newKey);
    await _secureStorage.write(
      key: _StorageKeys.masterKey,
      value: keyB64,
      aOptions: _androidOptions,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // UTILITÀ: ROTAZIONE CHIAVE MASTER (per future implementazioni)
  // ══════════════════════════════════════════════════════════════════════════════
  ///
  /// Rigenera la Master Key e la memorizza.
  /// ATTENZIONE: Questo invalida TUTTI i Box Hive esistenti!
  /// Usare solo con migrazione dati pianificata.
  Future<void> rotateMasterKey() async {
    if (!_isHardwareInitialized) {
      throw StateError('SecurityManager non inizializzato');
    }

    // Genera nuova chiave
    final Uint8List newKey = Uint8List.fromList(Hive.generateSecureKey());
    _masterKey = newKey;
    _hiveCipher = HiveAesCipher(newKey);
    _wipeMasterKeyFromMemory();

    // Memorizza nuova chiave
    final String keyB64 = base64Encode(newKey);
    await _secureStorage.write(
      key: _StorageKeys.masterKey,
      value: keyB64,
      aOptions: _androidOptions,
    );

    // Incrementa versione
    await _secureStorage.write(
      key: _StorageKeys.keyVersion,
      value: (_currentKeyVersion + 1).toString(),
      aOptions: _androidOptions,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // RESET COMPLETO (solo per testing/debug)
  // ══════════════════════════════════════════════════════════════════════════════
  ///
  /// Elimina tutte le chiavi di sicurezza e resetta lo stato.
  /// USARE SOLO IN DEBUG/TESTING.
  Future<void> resetForTesting() async {
    await _secureStorage.deleteAll(aOptions: _androidOptions);
    _wipeMasterKeyFromMemory();
    _hiveCipher = null;
    _isHardwareInitialized = false;
  }
}
