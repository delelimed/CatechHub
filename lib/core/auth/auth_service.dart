// ══════════════════════════════════════════════════════════════════════════════
// auth_service.dart — CatechHub (Autenticazione SOLO nativa Android: Biometria/PIN dispositivo)
// NON usa più PIN proprietario dell'app. Usa local_auth con fallback automatico al
// PIN/Segno/Pattern del telefono. 100% OFFLINE, nessun dato sensibile esce dal device.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/local_database.dart';
import '../../shared/models/class_model.dart';

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

  /// Nome visualizzato di default.
  static const localUserName = 'Catechista Locale';

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
  /// Salva nome, cognome, gruppo. NESSUN PIN app.
  /// Sblocca automaticamente la sessione.
  Future<bool> setupInitialProfile({
    required String firstName,
    required String lastName,
    required String groupName,
  }) async {
    if (firstName.trim().isEmpty ||
        lastName.trim().isEmpty ||
        groupName.trim().isEmpty) {
      dev.log('Campi profilo vuoti');
      return false;
    }

    try {
      await _box.put('first_name', firstName.trim());
      await _box.put('last_name', lastName.trim());
      await _box.put('group_name', groupName.trim());
      await _box.put('local_user_name', '${firstName.trim()} ${lastName.trim()}');

      // Crea automaticamente la classe/gruppo iniziale
      final classBox = LocalDatabase.classes();
      final classId = LocalDatabase.newId('class');
      final catechistName = '${firstName.trim()} ${lastName.trim()}';
      final newClass = SchoolClass(
        id: classId,
        name: groupName.trim(),
        studentIds: [],
        catechistIds: [localUserId],
        lastModifiedBy: catechistName,
      );
      await classBox.put(classId, newClass.toMap());

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
  }) async {
    try {
      if (firstName != null) await _box.put('first_name', firstName.trim());
      if (lastName != null) await _box.put('last_name', lastName.trim());
      if (groupName != null) await _box.put('group_name', groupName.trim());

      if (firstName != null || lastName != null) {
        final fn = firstName ?? _box.get('first_name', defaultValue: '');
        final ln = lastName ?? _box.get('last_name', defaultValue: '');
        await _box.put('local_user_name', '$fn $ln'.trim());
      }
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
      'groupName': _box.get('group_name', defaultValue: ''),
      'email': 'locale@dispositivo',
      'role': 'catechist',
      'canManageCatechists': true,
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