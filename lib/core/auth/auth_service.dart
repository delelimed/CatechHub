// ══════════════════════════════════════════════════════════════════════════════
// auth_service.dart — CatechHub (Autenticazione SOLO nativa Android: Biometria/PIN dispositivo)
// NON usa più PIN proprietario dell'app. Usa local_auth con fallback automatico al
// PIN/Segno/Pattern del telefono. 100% OFFLINE, nessun dato sensibile esce dal device.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/local_database.dart';
import '../../features/sync/p2p/p2p_security_service.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/user_role.dart';

/// Servizio di autenticazione basato ESCLUSIVAMENTE su biometrica nativa Android
/// (impronta, volto, iride) con fallback automatico a PIN/Pattern/Password del dispositivo.
///
/// NON gestisce più PIN proprietario dell'app. La sicurezza è delegata al
/// lockscreen del dispositivo (KeyguardManager / BiometricPrompt).
///
/// FLUSSO:
/// 1. isDeviceSupported() → verifica che il device abbia HW/SW per biometria
/// 2. hasEnrolledBiometrics() → verifica che l'utente abbia registrato almeno una biometria
/// 3. authenticate() → mostra prompt nativo (biometricOnly: false = fallback PIN dispositivo)
/// 4. Su successo → sessione sbloccata in RAM (_sessionUnlocked)
/// 5. Su fallimento/timeout → resta bloccato
///
/// PROFILO UTENTE: salvato in Hive box 'auth' (nome, cognome, gruppo).
/// Prima configurazione: solo profilo, NESSUN PIN app.
class AuthService {
  /// ID statico catechista locale (singolo utente per dispositivo).
  static const localUserId = 'local_catechist_id';

  /// Chiave Hive per il catechistId persistente.
  static const _catechistIdKey = 'catechist_id';

  /// Chiave Hive per il salt crittografico usato nella derivazione dell'ID.
  static const _catechistSaltKey = 'catechist_salt';

  /// Nome visualizzato di default.
  static const localUserName = 'Catechista Locale';

  /// Genera un UUID v4 con un generatore crittograficamente sicuro.
  static String _generateUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 10xx
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Restituisce (e genera se necessario) un identificatore stabile per il
  /// catechista locale. Questo ID è condiviso tra tutti i dispositivi dello
  /// stesso catechista (via sync) e permette di distinguere il creatore della
  /// classe dagli altri catechisti associati.
  ///
  /// DERIVAZIONE (anti-enumerazione):
  ///   L'ID non è mai derivato SOLO dal nome (sarebbe enumerabile). Combina
  ///   l'anagrafica normalizzata (nome+cognome, senza spazi, case-insensitive)
  ///   con un salt crittografico unico UUIDv4:
  ///     id = "cat_" + sha256("nome_normalizzato:salt").hex[0..16]
  ///   Il salt viene persistito accanto all'ID, quindi l'ID resta stabile per
  ///   tutta la vita del profilo. Due persone con lo stesso nome generano ID
  ///   diversi perché il salt è unico per dispositivo.
  static String getCatechistId() {
    final box = LocalDatabase.auth();
    final existing = box.get(_catechistIdKey) as String?;
    if (existing != null && existing.isNotEmpty) return existing;

    final normalized = getLocalAnagraficaKey();
    String salt = box.get(_catechistSaltKey) as String? ?? '';
    if (salt.isEmpty) {
      salt = _generateUuidV4();
      box.put(_catechistSaltKey, salt);
    }
    final hash = sha256.convert(utf8.encode('$normalized:$salt')).toString();
    final newId = 'cat_${hash.substring(0, 16)}';
    box.put(_catechistIdKey, newId);
    return newId;
  }

  /// Getter di istanza per il catechistId corrente.
  String get catechistId => getCatechistId();

  /// Numero di telefono facoltativo del catechista (campo `phone_number`).
  static String getPhoneNumber() {
    final box = LocalDatabase.auth();
    return box.get('phone_number', defaultValue: '') as String? ?? '';
  }

  /// Normalizza una stringa anagrafica per confronti identità:
  /// lowercase, senza spazi, senza accenti significativi. Due nomi che
  /// differiscono solo per maiuscole/spazi risultano IDENTICI.
  ///
  /// Esempio: "Mario  Rossi" → "mariorossi", "MARIO ROSSI" → "mariorossi".
  static String normalizeCatechistName(String value) {
    final lower = value.toLowerCase();
    // Rimuove gli accenti (à→a, è→e, ...) così "Marìo" == "Mario".
    const withAccents =
        'àáâãäåèéêëìíîïòóôõöùúûüñç';
    const withoutAccents =
        'aaaaaaeeeeiiiiooooouuuunc';
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      final idx = withAccents.indexOf(ch);
      if (idx >= 0) {
        buffer.write(withoutAccents[idx]);
      } else {
        buffer.write(ch);
      }
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Chiave anagrafica normalizzata del profilo locale ("nome"+"cognome"
  /// senza spazi e case-insensitive). Stringa vuota se il profilo non è
  /// ancora configurato.
  static String getLocalAnagraficaKey() {
    final box = LocalDatabase.auth();
    final first = box.get('first_name', defaultValue: '') as String? ?? '';
    final last = box.get('last_name', defaultValue: '') as String? ?? '';
    if (first.trim().isEmpty || last.trim().isEmpty) return '';
    return normalizeCatechistName('$first $last');
  }

  /// True se il profilo locale è configurato con un'anagrafica completa.
  static bool hasLocalAnagrafica() => getLocalAnagraficaKey().isNotEmpty;

  /// Chiave anagrafica normalizzata per una coppia nome/cognome arbitraria
  /// (usata per confrontare l'identità di un dispositivo remoto).
  static String anagraficaKey(String? firstName, String? lastName) {
    final first = firstName?.trim() ?? '';
    final last = lastName?.trim() ?? '';
    if (first.isEmpty && last.isEmpty) return '';
    return normalizeCatechistName('$first $last');
  }

  /// Adotta un `catechistId` esistente come identità stabile di questo
  /// dispositivo.
  ///
  /// Usato quando un dispositivo viene associato come "Mio Dispositivo":
  /// i dispositivi appartenenti alla STESSA persona devono condividere lo
  /// stesso `catechistId`, così da essere riconosciuti come "stessa persona"
  /// (pieni diritti, sincronizzazione di tutte le classi).
  ///
  /// L'adozione avviene SOLO se [id] non è vuoto; altrimenti non fa nulla
  /// e restituisce l'identità corrente.
  static String adoptCatechistId(String id) {
    if (id.trim().isEmpty) return getCatechistId();
    final box = LocalDatabase.auth();
    final current = box.get(_catechistIdKey) as String?;
    if (current == id.trim()) return getCatechistId();
    box.put(_catechistIdKey, id.trim());
    dev.log('CatechistId adottato: $id');
    return id.trim();
  }

  final _box = LocalDatabase.auth();
  final _localAuth = LocalAuthentication();

  Map<String, dynamic>? _cachedUser;
  bool _sessionUnlocked = false;

  /// True se il profilo utente è già stato configurato (nome/cognome/gruppo).
  bool get isProfileConfigured =>
      _box.containsKey('first_name') &&
      _box.containsKey('last_name') &&
      _box.containsKey('group_name');

  /// True se la sessione è attualmente sbloccata (solo in RAM).
  bool get isUnlocked => _sessionUnlocked;

  /// True se il profilo è completo.
  bool get hasProfileData => isProfileConfigured;

  /// Verifica se il dispositivo supporta l'autenticazione biometrica nativa.
  /// Controlla: HW presente, API disponibili, keystore accessibile.
  Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } on PlatformException catch (e) {
      dev.log('Errore isDeviceSupported: ${e.message}');
      return false;
    }
  }

  /// Verifica se l'utente ha registrato almeno una biometria (impronta/volto)
  /// OPPURE ha un blocco schermo attivo (PIN/Pattern/Password).
  /// Restituisce true se authenticate(biometricOnly: false) potrà riuscire.
  Future<bool> canAuthenticate() async {
    try {
      // canCheckBiometrics verifica se ci sono biometrie registrate
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      // isDeviceSupported verifica supporto HW/SW
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      // getAvailableBiometrics elenca i tipi registrati
      final availableBiometrics = await _localAuth.getAvailableBiometrics();

      // Se il device supporta biometria E (ha biometrie registrate O ha lockscreen)
      // canCheckBiometrics torna true anche se ci sono solo PIN/Pattern (Android 10+)
      return isDeviceSupported && (canCheckBiometrics || availableBiometrics.isNotEmpty);
    } on PlatformException catch (e) {
      dev.log('Errore canAuthenticate: ${e.message}');
      return false;
    }
  }

  /// Verifica se il dispositivo ha un blocco schermo attivo (PIN/Pattern/Password/biometria).
  /// Usa KeyguardManager (API 23+) per rilevare se l'utente ha impostato un qualunque lockscreen.
  /// CRITICO: se false → l'app NON può funzionare (hard lock screen).
  Future<bool> hasSecureLockScreen() async {
    try {
      // canCheckBiometrics su Android 10+ (API 29+) ritorna true anche per solo PIN/Pattern
      // ma per sicurezza controlliamo anche via platform channel nativo se possibile
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      if (!isSupported) return false;

      // Se canCheckBiometrics è true, c'è almeno un metodo di sblocco configurato
      // (biometria OPPURE PIN/Pattern/Password del dispositivo)
      return canCheck;
    } on PlatformException catch (e) {
      dev.log('Errore hasSecureLockScreen: ${e.message}');
      return false;
    }
  }

  /// Avvia l'autenticazione nativa Android (BiometricPrompt).
  ///
  /// Parametri localizzati in italiano:
  /// - localizedReason: motivo mostrato nel dialog di sistema
  ///
  /// Ritorna true se autenticazione riuscita, false altrimenti (annullato, fallito, timeout).
  Future<bool> authenticate({
    String localizedReason = 'Autenticati per accedere al Registro CatechHub',
  }) async {
    try {
      final isSupported = await isDeviceSupported();
      if (!isSupported) {
        dev.log('Dispositivo non supporta autenticazione biometrica');
        return false;
      }

      final canAuth = await canAuthenticate();
      if (!canAuth) {
        dev.log('Nessun metodo di autenticazione configurato sul dispositivo');
        return false;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
        sensitiveTransaction: false,
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'CatechHub - Accesso Sicuro',
            cancelButton: 'Annulla',
            signInHint: 'Usa impronta, volto o PIN del telefono',
          ),
          IOSAuthMessages(
            cancelButton: 'Annulla',
            localizedFallbackTitle: 'Impostazioni',
          ),
        ],
      );

      if (authenticated) {
        _sessionUnlocked = true;
        _cachedUser = null;
        dev.log('Autenticazione nativa riuscita');

        // ══════════════════════════════════════════════════════════════════════════
        // MIGRAZIONE: Pulizia legacy PIN app (vecchio sistema proprietario)
        // Il vecchio PIN era salvato nella Hive box 'auth' con chiavi:
        // - 'local_pin_hash'    → stringa "v2:iterazioni:salt_b64:hash_b64"
        // - 'local_pin_salt'    → salt grezzo (se presente separatamente)
        // - 'local_pin_version' → versione schema
        // - 'local_pin_iterations' → iterazioni PBKDF2
        //
        // Eseguiamo la pulizia UNA SOLA VOLTA al primo login biometrico riuscito
        // post-aggiornamento, usando un flag in SharedPreferences.
        // ══════════════════════════════════════════════════════════════════════════
        final prefs = await SharedPreferences.getInstance();
        const legacyCleanedKey = 'legacy_pin_cleaned_v2';
        final pinCleaned = prefs.getBool(legacyCleanedKey) ?? false;

        if (!pinCleaned) {
          try {
            // 1. Cancella dalla Hive box 'auth' (dove stava il vecchio PIN)
            await _box.delete('local_pin_hash');
            await _box.delete('local_pin_salt');
            await _box.delete('local_pin_version');
            await _box.delete('local_pin_iterations');

            // 2. Se avevi anche salvato in flutter_secure_storage, pulisci lì
            //    (decommenta se usavi SecureStorage per il PIN)
            // final secureStorage = FlutterSecureStorage();
            // await secureStorage.delete(key: 'app_pin_hash');
            // await secureStorage.delete(key: 'app_pin_salt');
            // await secureStorage.delete(key: 'app_pin_version');

            // 3. Marca come completato
            await prefs.setBool(legacyCleanedKey, true);
            dev.log('Migrazione completata: legacy PIN rimosso da Hive auth box');
          } catch (e) {
            dev.log('Errore durante pulizia legacy PIN (non bloccante): $e');
            // Non bloccare il login se la pulizia fallisce
          }
        }

        return true;
      }

      dev.log('Autenticazione fallita o annullata');
      return false;
    } on PlatformException catch (e) {
      dev.log('Errore PlatformException authenticate: ${e.code} - ${e.message}');
      // Codici comuni: NotEnrolled, NotAvailable, LockedOut, PermanentlyLockedOut
      return false;
    } on TimeoutException {
      dev.log('Timeout autenticazione (45s)');
      return false;
    } catch (e) {
      dev.log('Errore generico authenticate: $e');
      return false;
    }
  }

  /// Configurazione profilo iniziale (onboarding).
  /// Salva nome, cognome. Se [createClass] è true, salva anche [groupName]
  /// e crea la classe iniziale. Se false, salva solo nome/cognome e l'utente
  /// si unirà a una classe esistente via P2P sync.
  /// [role] determina il ruolo locale (Catechista / Responsabile): con ruolo
  /// Responsabile non viene creata alcuna classe iniziale e la fase multiclasse
  /// dell'onboarding viene considerata già completata.
  /// [phoneNumber] è facoltativo e viene salvato come `phone_number`.
  /// Sblocca automaticamente la sessione.
  Future<bool> setupInitialProfile({
    required String firstName,
    required String lastName,
    String? groupName,
    String? phoneNumber,
    bool createClass = true,
    UserRole role = UserRole.catechista,
  }) async {
    if (firstName.trim().isEmpty || lastName.trim().isEmpty) {
      dev.log('Campi profilo vuoti');
      return false;
    }
    if (createClass && (groupName == null || groupName.trim().isEmpty)) {
      dev.log('Nome gruppo richiesto per creazione classe');
      return false;
    }

    try {
      getCatechistId(); // Ensure catechistId exists before profile data

      final isResponsabile = role == UserRole.responsabile;

      await _box.put('first_name', firstName.trim());
      await _box.put('last_name', lastName.trim());
      await _box.put(
        'phone_number',
        (phoneNumber?.trim() ?? '').replaceAll(RegExp(r'\s+'), ' '),
      );
      // Il catechistId viene generato DOPO il salvataggio dell'anagrafica,
      // così la sua derivazione può basarsi su Nome e Cognome normalizzati.
      getCatechistId(); // Ensure catechistId exists before profile data

      // Modalità operativa (spec: app_mode = RESPONSABILE | NORMAL | REPLICATED_PEER)
      // e setup_mode (create | join | responsabile) coerenti con la scelta
      // effettuata durante l'onboarding.
      await _box.put(
        'app_mode',
        isResponsabile
            ? 'RESPONSABILE'
            : createClass
                ? 'NORMAL'
                : 'REPLICATED_PEER',
      );
      await _box.put(
        'setup_mode',
        isResponsabile ? 'responsabile' : createClass ? 'create' : 'join',
      );
      await UserRole.setCurrent(role);

      final fullName = '${firstName.trim()} ${lastName.trim()}';
      await _box.put('local_user_name', fullName);

      // La fase di onboarding dedicata alla gestione multiclasse è pendente:
      // il router reindirizzerà il catechista alla schermata "/onboarding-classes"
      // finché non verrà completata (flag impostato a true dalla schermata).
      // Per il Responsabile questa fase non si applica (gestione centralizzata
      // in /parrocchia): viene marcata come completata.
      await _box.put('onboarding_classes_completed', isResponsabile);

      if (createClass) {
        await _box.put('group_name', groupName!.trim());

        // Crea automaticamente la classe/gruppo iniziale
        final classBox = LocalDatabase.classes();
        final classId = LocalDatabase.newId('class');
        final newClass = SchoolClass(
          id: classId,
          name: groupName.trim(),
          studentIds: [],
          catechistIds: [localUserId],
          lastModifiedBy: fullName,
          uniqueCode: generateClassUniqueCode(),
          nameLocked: false,
          creatorId: localUserId,
          creatorName: fullName,
          creatorCatechistId: getCatechistId(),
          catechistDeviceCounts: {getCatechistId(): 1},
        );
        await classBox.put(classId, newClass.toMap());
        // Forza la scrittura su disco: la classe deve sopravvivere anche a un
        // kill del processo immediatamente dopo la creazione.
        await classBox.flush();
        // La classe creata durante l'onboarding è subito quella corrente,
        // così al riavvio il router trova una selezione valida e persistente.
        await _box.put('current_class_id', classId);
      } else {
        await _box.put('group_name', fullName);
      }

      await P2PSecurityService().refreshIdentityName();
      await P2PSecurityService().refreshIdentityAnagrafica();

      _sessionUnlocked = true;
      _cachedUser = null;
      dev.log('Profilo iniziale configurato e sessione sbloccata');
      return true;
    } catch (e) {
      dev.log('Errore setupInitialProfile: $e');
      return false;
    }
  }

  /// Chiude la sessione (senza cancellare dati).
  Future<void> signOut() async {
    _sessionUnlocked = false;
    _cachedUser = null;
  }

  /// Aggiorna i dati del profilo.
  Future<bool> updateProfile({
    String? firstName,
    String? lastName,
    String? groupName,
    String? phoneNumber,
  }) async {
    try {
      if (firstName != null) await _box.put('first_name', firstName.trim());
      if (lastName != null) await _box.put('last_name', lastName.trim());
      if (groupName != null) await _box.put('group_name', groupName.trim());
      if (phoneNumber != null) {
        await _box.put(
          'phone_number',
          phoneNumber.trim().replaceAll(RegExp(r'\s+'), ' '),
        );
      }

      if (firstName != null || lastName != null) {
        final fn = firstName ?? _box.get('first_name', defaultValue: '');
        final ln = lastName ?? _box.get('last_name', defaultValue: '');
        await _box.put('local_user_name', '$fn $ln'.trim());
      }
      await P2PSecurityService().refreshIdentityName();
      await P2PSecurityService().refreshIdentityAnagrafica();
      _cachedUser = null;
      return true;
    } catch (e) {
      dev.log('Errore updateProfile: $e');
      return false;
    }
  }

  /// Restituisce l'utente corrente se la sessione è sbloccata.
  Map<String, dynamic>? get currentUser {
    if (!isUnlocked) {
      _cachedUser = null;
      return null;
    }

    if (_cachedUser != null) return _cachedUser;

    _cachedUser = {
      'uid': localUserId,
      'name': _box.get('local_user_name', defaultValue: localUserName),
      'firstName': _box.get('first_name', defaultValue: ''),
      'lastName': _box.get('last_name', defaultValue: ''),
      'phoneNumber': _box.get('phone_number', defaultValue: ''),
      'groupName': _box.get('group_name', defaultValue: ''),
      'email': 'locale@dispositivo',
      'role': UserRole.current().storageKey,
      'canManageCatechists': UserRole.isResponsabile,
      'canManageParish': UserRole.isResponsabile,
    };

    return _cachedUser;
  }

  /// RESET COMPLETO: cancella profilo e chiavi.
  /// Da usare se l'utente vuole "disinstallare logicamente" l'app.
  Future<void> resetAll() async {
    try {
      await _box.clear();
      _sessionUnlocked = false;
      _cachedUser = null;
      dev.log('Reset completo dati auth eseguito');
    } catch (e) {
      dev.log('Errore resetAll: $e');
    }
  }
}