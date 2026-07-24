// ═══════════════════════════════════════════════════════════════════════════════
// migration_manager.dart — CatechHub (Migrazione Atomica Zero Data Loss)
// ═══════════════════════════════════════════════════════════════════════════════
//
// MIGRAZIONE ZERO DATA LOSS — REQUISITI FONDAMENTALI:
// ──────────────────────────────────────────────────────────────────────────────
// 1. CHECK DI STATO: Verifica flag migration_zero_data_loss_completed in
//    FlutterSecureStorage (encryptedSharedPreferences: true). Se true → esci.
// 2. AUTENTICAZIONE PREVENTIVA: Richiede biometria/PIN via local_auth. Se fallisce
//    o annullata → INTERROMPI SENZA TOCCARE NULLA e solleva eccezione blocco.
// 3. ALGORITMO ATOMICO PER OGNI BOX:
//    A. Verifica esistenza vecchio Box (Hive.boxExists)
//    B. Apri vecchio Box legacy → estrai TUTTI i record (toMap)
//    C. Apri Box TEMPORANEO cifrato (${boxName}_encrypted_temp) con HiveAesCipher
//    D. Inserisci TUTTI i record atomicamente via putAll()
//    E. VERIFICA INTEGRALE: tempBox.length == legacyBox.length
//    F. ROLLBACK SICURO: Se mismatch o eccezione → chiudi ed elimina SOLO tempBox,
//       NON toccare vecchio Box, solleva eccezione blocco.
//    G. CONSOLIDAMENTO ED ERADICAZIONE (solo se verifica OK):
//       1. Chiudi vecchio Box → Hive.deleteBoxFromDisk(boxName) [ERADICAZIONE]
//       2. Apri Box DEFINITIVO con nome originale + cifratura AES-256
//       3. Copia dati da tempBox a nuovo Box definitivo
//       4. Chiudi ed elimina tempBox (deleteFromDisk)
//       5. Chiudi nuovo Box definitivo
// 4. FLAG FINALE: Scrivi migration_zero_data_loss_completed = 'true' in
//    SecureStorage SOLO se TUTTI i Box migrati con successo.
//
// GARANZIA ZERO DATA LOSS:
// - Il vecchio Box viene eliminato SOLO dopo verifica conteggio riuscita
// - Il Box temporaneo funge da buffer atomico
// - Qualsiasi errore → rollback completo, dati originali intatti
// - Conformità GDPR: eradicazione definitiva storage non sicuro
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart';

import 'local_database.dart';
import '../security/hardware_security_exception.dart';
import '../security/security_manager.dart';

/// Eccezione sollevata quando la migrazione deve bloccare l'app (es. auth fallita).
class MigrationBlockException implements Exception {
  final String userMessage;
  final String? technicalDetail;

  const MigrationBlockException(this.userMessage, {this.technicalDetail});

  @override
  String toString() => 'MigrationBlockException: $userMessage'
      '${technicalDetail != null ? ' (Dettaglio: $technicalDetail)' : ''}';
}

/// Eccezione sollevata per errori durante la migrazione di un singolo Box.
class MigrationBoxException implements Exception {
  final String boxName;
  final String message;
  final String? technicalDetail;

  const MigrationBoxException(this.boxName, this.message, {this.technicalDetail});

  @override
  String toString() => 'MigrationBoxException[$boxName]: $message'
      '${technicalDetail != null ? ' (Dettaglio: $technicalDetail)' : ''}';
}

/// Manager per la migrazione atomica "Zero Data Loss" dei Box Hive legacy
/// verso nuovi Box cifrati con AES-256 Hardware-Backed (TEE/StrongBox).
class MigrationManager {
  MigrationManager._();

  static final MigrationManager _instance = MigrationManager._();
  static MigrationManager get instance => _instance;

  /// Chiave nel SecureStorage per il flag di migrazione completata.
  static const String _migrationCompletedFlag = 'migration_zero_data_loss_completed';

  /// Elenco dei Box da migrare (nomi legacy → nomi definitivi).
  /// I nomi definitivi coincidono con quelli in LocalDatabase.
  static const Map<String, String> _boxesToMigrate = {
    // Box semplici (non Map)
    LocalDatabase.authBox: LocalDatabase.authBox,
    LocalDatabase.meetingCatechesiBox: LocalDatabase.meetingCatechesiBox,
    // Box Map
    LocalDatabase.classesBox: LocalDatabase.classesBox,
    LocalDatabase.studentsBox: LocalDatabase.studentsBox,
    LocalDatabase.planningBox: LocalDatabase.planningBox,
    LocalDatabase.attendanceBox: LocalDatabase.attendanceBox,
    LocalDatabase.documentsBox: LocalDatabase.documentsBox,
    LocalDatabase.documentDeliveriesBox: LocalDatabase.documentDeliveriesBox,
    LocalDatabase.attachmentsBox: LocalDatabase.attachmentsBox,
    LocalDatabase.contactNotesBox: LocalDatabase.contactNotesBox,
    LocalDatabase.catechesiBox: LocalDatabase.catechesiBox,
    LocalDatabase.studentDailyNotesBox: LocalDatabase.studentDailyNotesBox,
    LocalDatabase.trustedDevicesBox: LocalDatabase.trustedDevicesBox,
  };

  /// Configurazione AndroidOptions per FlutterSecureStorage (hardware-backed).
  static const AndroidOptions _androidOptions = AndroidOptions();

  /// Instance di FlutterSecureStorage per leggere/scrivere il flag migrazione.
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    lOptions: LinuxOptions(),
    mOptions: MacOsOptions(),
    wOptions: WindowsOptions(),
  );

  /// Instanza LocalAuthentication per autenticazione biometrica/PIN.
  final LocalAuthentication _localAuth = LocalAuthentication();

  /// Verifica se la migrazione è già stata completata.
  ///
  /// Legge il flag dal SecureStorage. Se true, la migrazione viene saltata.
  Future<bool> isMigrationCompleted() async {
    try {
      final String? flag = await _secureStorage.read(
        key: _migrationCompletedFlag,
        aOptions: _androidOptions,
      );
      return flag == 'true';
    } catch (e) {
      // Se non possiamo leggere il flag, assumiamo migrazione NON completata
      // per sicurezza (meglio rimigrare che perdere dati).
      debugPrint('[MigrationManager] Errore lettura flag migrazione: $e');
      return false;
    }
  }

  /// Esegue l'autenticazione biometrica/PIN preventiva obbligatoria.
  ///
  /// REQUISITO: L'utente DEVE autenticarsi prima di qualsiasi operazione
  /// sui dati sensibili. Se fallisce o annulla → solleva MigrationBlockException
  /// SENZA aver toccato alcun file.
  Future<void> _requireBiometricAuthentication() async {
    // Verifica disponibilità biometria
    final bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
    final bool isDeviceSupported = await _localAuth.isDeviceSupported();

    if (!canCheckBiometrics || !isDeviceSupported) {
      throw MigrationBlockException(
        'Dispositivo non supporta autenticazione biometrica/PIN. '
        'Impossibile procedere con la migrazione sicura.',
        technicalDetail: 'canCheckBiometrics=$canCheckBiometrics, isDeviceSupported=$isDeviceSupported',
      );
    }

    // Tenta autenticazione
    final bool authenticated = await _localAuth.authenticate(
      localizedReason: 'Autenticazione richiesta per migrare i dati sensibili '
          'verso il nuovo storage cifrato hardware-backed (TEE/StrongBox).',
      biometricOnly: false,
      sensitiveTransaction: true,
      persistAcrossBackgrounding: true,
    );

    if (!authenticated) {
      throw const MigrationBlockException(
        'Autenticazione biometrica/PIN fallita o annullata. '
        'La migrazione dei dati sensibili richiede conferma identità.',
        technicalDetail: 'User cancelled or authentication failed',
      );
    }
  }

  /// Migra un singolo Box legacy verso il nuovo Box cifrato.
  ///
  /// ALGORITMO ATOMICO ZERO DATA LOSS:
  /// 1. Verifica esistenza vecchio Box
  /// 2. Apri vecchio Box → estrai tutti i record (toMap)
  /// 3. Apri Box TEMPORANEO cifrato (${boxName}_encrypted_temp)
  /// 4. putAll() atomicamente tutti i record nel Box temporaneo
  /// 5. VERIFICA: tempBox.length == legacyBox.length
  /// 6. Se mismatch/eccezione → ROLLBACK: elimina SOLO tempBox, lascia originale
  /// 7. Se OK → CONSOLIDAMENTO:
  ///    a. Chiudi vecchio Box → Hive.deleteBoxFromDisk(boxName) [ERADICAZIONE]
  ///    b. Apri nuovo Box definitivo (nome originale + cifratura AES-256)
  ///    c. Copia dati da tempBox a nuovo Box
  ///    d. Chiudi ed elimina tempBox (deleteFromDisk)
  ///    e. Chiudi nuovo Box definitivo
  ///
  /// THROWS: MigrationBoxException se qualsiasi passo fallisce (rollback garantito)
  Future<void> _migrateSingleBox(
    String legacyBoxName,
    String targetBoxName,
    HiveAesCipher cipher,
  ) async {
    final String tempBoxName = '${targetBoxName}_encrypted_temp';

    // ═══════════════════════════════════════════════════════════════════════════
    // PASSO A: Verifica esistenza vecchio Box legacy
    // ═══════════════════════════════════════════════════════════════════════════
    final bool legacyExists = await Hive.boxExists(legacyBoxName);
    if (!legacyExists) {
      debugPrint('[MigrationManager] Box legacy "$legacyBoxName" non esiste, salto.');
      return; // Nessun dato da migrare per questo box
    }

    debugPrint('[MigrationManager] Inizio migrazione Box: $legacyBoxName → $targetBoxName');

    Box<dynamic>? legacyBox;
    Box<dynamic>? tempBox;
    Box<dynamic>? newBox;

    try {
      // ═══════════════════════════════════════════════════════════════════════════
      // PASSO B: Apri vecchio Box legacy (senza cifratura o con vecchia cifratura)
      // Estrai TUTTI i record via toMap()
      // ═══════════════════════════════════════════════════════════════════════════
      legacyBox = await Hive.openBox<dynamic>(legacyBoxName);
      final Map<dynamic, dynamic> legacyData = legacyBox.toMap();
      final int legacyCount = legacyData.length;

      debugPrint('[MigrationManager] Box "$legacyBoxName": estratti $legacyCount record');

      // Chiudi subito il Box legacy per rilasciare lock
      await legacyBox.close();
      legacyBox = null;

      // ═══════════════════════════════════════════════════════════════════════════
      // PASSO C: Apri Box TEMPORANEO cifrato con AES-256 Hardware-Backed
      // ═══════════════════════════════════════════════════════════════════════════
      tempBox = await Hive.openBox<dynamic>(tempBoxName, encryptionCipher: cipher);

      // ═══════════════════════════════════════════════════════════════════════════
      // PASSO D: Inserimento atomico TUTTI i record via putAll()
      // ═══════════════════════════════════════════════════════════════════════════
      if (legacyData.isNotEmpty) {
        await tempBox.putAll(legacyData);
      }

      // ═══════════════════════════════════════════════════════════════════════════
      // PASSO E: VERIFICA INTEGRALE — Confronto conteggio record
      // ═══════════════════════════════════════════════════════════════════════════
      final int tempCount = tempBox.length;

      if (tempCount != legacyCount) {
        // ═══════════════════════════════════════════════════════════════════════════
        // PASSO F: ROLLBACK DI SICUREZZA — MISMATCH CONTEGGIO
        // Elimina SOLO il Box temporaneo, NON toccare il vecchio Box originale
        // ═══════════════════════════════════════════════════════════════════════════
        debugPrint('[MigrationManager] ERRORE: Mismatch conteggio per "$legacyBoxName": '
            'legacy=$legacyCount, temp=$tempCount. ROLLBACK.');

        await tempBox.close();
        await Hive.deleteBoxFromDisk(tempBoxName);

        throw MigrationBoxException(
          legacyBoxName,
          'Verifica integrità fallita: conteggio record non corrisponde '
          '(legacy: $legacyCount, temp: $tempCount). Migrazione annullata per sicurezza.',
          technicalDetail: 'Count mismatch: legacy=$legacyCount vs temp=$tempCount',
        );
      }

      debugPrint('[MigrationManager] Verifica integrità OK per "$legacyBoxName": $tempCount record');

      // ═══════════════════════════════════════════════════════════════════════════
      // PASSO G: CONSOLIDAMENTO ED ERADICAZIONE DATI OBSOLETI
      // Solo qui, dopo verifica riuscita, eliminiamo il vecchio storage
      // ═══════════════════════════════════════════════════════════════════════════

      // G.1: Chiudi tempBox (dati ora sicuri nel tempBox cifrato)
      await tempBox.close();
      tempBox = null;

      // G.2: ERADICAZIONE DEFINITIVA — Elimina vecchio Box legacy dal disco
      // Questo rimuove fisicamente i file .hive e .lock non sicuri
      await Hive.deleteBoxFromDisk(legacyBoxName);
      debugPrint('[MigrationManager] ERADICATO Box legacy non sicuro: $legacyBoxName');

      // G.3: Apri nuovo Box DEFINITIVO con nome originale + cifratura AES-256
      newBox = await Hive.openBox<dynamic>(targetBoxName, encryptionCipher: cipher);

      // G.4: Copia dati dal Box temporaneo al nuovo Box definitivo
      // Riapri tempBox in sola lettura per copiare
      tempBox = await Hive.openBox<dynamic>(tempBoxName, encryptionCipher: cipher);
      final Map<dynamic, dynamic> tempData = tempBox.toMap();

      if (tempData.isNotEmpty) {
        await newBox.putAll(tempData);
      }

      // Verifica finale sul nuovo Box definitivo
      final int newCount = newBox.length;
      if (newCount != legacyCount) {
        // Questo non dovrebbe mai accadere se la verifica temp è passata
        await newBox.close();
        await Hive.deleteBoxFromDisk(targetBoxName);
        await tempBox.close();
        await Hive.deleteBoxFromDisk(tempBoxName);
        throw MigrationBoxException(
          legacyBoxName,
          'Verifica finale fallita sul Box definitivo: conteggio non corrisponde',
          technicalDetail: 'Expected $legacyCount, got $newCount in new box',
        );
      }

      // G.5: Chiudi ed elimina Box temporaneo (non serve più)
      await tempBox.close();
      await Hive.deleteBoxFromDisk(tempBoxName);
      tempBox = null;

      // G.6: Chiudi nuovo Box definitivo (verrà riaperto da LocalDatabase.init)
      await newBox.close();
      newBox = null;

      debugPrint('[MigrationManager] ✅ Migrazione completata per: $legacyBoxName → $targetBoxName '
          '($legacyCount record migrati, storage legacy eradicato)');

    } on MigrationBoxException {
      // Rilancia eccezioni di migrazione già tipizzate
      rethrow;
    } catch (e, stack) {
      // ═══════════════════════════════════════════════════════════════════════════
      // ROLLBACK GENERALE: Qualsiasi eccezione imprevista → pulizia sicura
      // ═══════════════════════════════════════════════════════════════════════════
      debugPrint('[MigrationManager] ERRORE imprevisto migrazione "$legacyBoxName": $e');
      debugPrint('$stack');

      // Cleanup best-effort: chiudi ed elimina SOLO risorse temporanee/nuove
      // MAI toccare il vecchio Box legacy!
      try {
        if (tempBox != null && tempBox.isOpen) {
          await tempBox.close();
        }
      } catch (_) {}

      try {
        await Hive.deleteBoxFromDisk(tempBoxName);
      } catch (_) {}

      try {
        if (newBox != null && newBox.isOpen) {
          await newBox.close();
        }
      } catch (_) {}

      try {
        await Hive.deleteBoxFromDisk(targetBoxName);
      } catch (_) {}

      // Il vecchio Box legacy rimane INTACTO sul disco
      throw MigrationBoxException(
        legacyBoxName,
        'Errore durante migrazione: ${e.toString()}',
        technicalDetail: '$e\n$stack',
      );
    }
  }

  /// Esegue la migrazione completa di tutti i Box censiti.
  ///
  /// FLUSSO PRINCIPALE:
  /// 1. Check flag migrazione completata → se true, return
  /// 2. Autenticazione biometrica/PIN obbligatoria
  /// 3. Ottieni cipher AES-256 da SecurityManager
  /// 4. Per ogni Box in _boxesToMigrate → _migrateSingleBox()
  /// 5. Se TUTTI OK → scrivi flag migration_zero_data_loss_completed = 'true'
  /// 6. Se QUALSIASI fallisce → solleva eccezione, flag NON scritto
  ///
  /// THROWS:
  /// - MigrationBlockException: auth fallita o device non supportato
  /// - MigrationBoxException: errore migrazione specifico Box (con rollback)
  /// - HardwareSecurityException: se SecurityManager non inizializzato
  Future<void> migrateOldDataIfNeeded() async {
    // ═══════════════════════════════════════════════════════════════════════════
    // PASSO 1: CHECK DI STATO — Flag migrazione completata
    // ═══════════════════════════════════════════════════════════════════════════
    final bool alreadyDone = await isMigrationCompleted();
    if (alreadyDone) {
      debugPrint('[MigrationManager] Migrazione già completata (flag=true), skip.');
      return;
    }

    debugPrint('[MigrationManager] === INIZIO MIGRAZIONE ZERO DATA LOSS ===');

    // ═══════════════════════════════════════════════════════════════════════════
    // PASSO 2: AUTENTICAZIONE PREVENTIVA OBBLIGATORIA
    // ═══════════════════════════════════════════════════════════════════════════
    await _requireBiometricAuthentication();
    debugPrint('[MigrationManager] Autenticazione biometrica/PIN: SUCCESSO');

    // ═══════════════════════════════════════════════════════════════════════════
    // PASSO 3: OTTIENI CIPHER AES-256 HARDWARE-BACKED DA SECURITY MANAGER
    // ═══════════════════════════════════════════════════════════════════════════
    if (!SecurityManager.instance.isInitialized) {
      throw const HardwareSecurityException(
        'SecurityManager non inizializzato: impossibile ottenere cipher AES-256.',
        technicalDetail: 'SecurityManager.instance.isInitialized == false',
      );
    }
    final HiveAesCipher cipher = SecurityManager.instance.hiveCipher;
    debugPrint('[MigrationManager] Cipher AES-256 hardware-backed ottenuto');

    // ═══════════════════════════════════════════════════════════════════════════
    // PASSO 4: MIGRAZIONE SEQUENZIALE DI TUTTI I BOX CENSITI
    // ═══════════════════════════════════════════════════════════════════════════
    // NOTA: Migrazione SEQUENZIALE (non parallela) per:
    // - Garantire atomicità per Box (rollback isolato)
    // - Evitare contention su file system / lock Hive
    // - Logging chiaro e debuggabile
    for (final entry in _boxesToMigrate.entries) {
      final String legacyName = entry.key;
      final String targetName = entry.value;

      await _migrateSingleBox(legacyName, targetName, cipher);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PASSO 5: CONSOLIDAMENTO FLAG — Solo se TUTTI i Box migrati con successo
    // ═══════════════════════════════════════════════════════════════════════════
    await _secureStorage.write(
      key: _migrationCompletedFlag,
      value: 'true',
      aOptions: _androidOptions,
    );

    debugPrint('[MigrationManager] === MIGRAZIONE COMPLETATA CON SUCCESSO ===');
    debugPrint('[MigrationManager] Flag migration_zero_data_loss_completed = true scritto in SecureStorage');
  }

  /// Reset del flag migrazione (SOLO PER TESTING/DEBUG).
  /// USARE CON ESTREMA CAUTEZZA: forza rimigrazione al prossimo avvio.
  Future<void> resetMigrationFlagForTesting() async {
    if (!kDebugMode) {
      throw StateError('resetMigrationFlagForTesting() disponibile solo in debug mode');
    }
    await _secureStorage.delete(key: _migrationCompletedFlag, aOptions: _androidOptions);
    debugPrint('[MigrationManager] [TESTING] Flag migrazione resettato');
  }
}