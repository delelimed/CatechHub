import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart'; // Opzionale, per configurazioni avanzate Android

import '../services/encryption_service.dart';
import '../storage/local_database.dart';

Map<String, String> _computePinHash(Map<String, dynamic> args) {
  final pin = args['pin'] as String;
  final salt = base64Decode(args['salt'] as String);
  final iterations = args['iterations'] as int;
  final hashBytes = EncryptionService.derivePasswordKeyBytes(
    pin,
    Uint8List.fromList(salt),
    iterations: iterations,
  );
  return {'hash': base64Encode(hashBytes)};
}

class AuthService {
  static const localUserId = 'local_catechist_id';
  static const localUserName = 'Catechista Locale';

  final _box = LocalDatabase.auth();
  final _localAuth = LocalAuthentication();
  Map<String, dynamic>? _cachedUser;

  /// Sessione attiva solo in memoria: alla chiusura/kill del processo serve di nuovo il PIN.
  bool _sessionUnlocked = false;

  bool get isPinConfigured => _box.containsKey('local_pin_hash');

  bool get isUnlocked => _sessionUnlocked;

  bool get hasProfileData {
    return _box.containsKey('first_name') &&
        _box.containsKey('last_name') &&
        _box.containsKey('group_name');
  }

  static const _pinHashVersion = 'v2';
  static const _pinHashIterations = 210000;

  String _hashPin(
    String pin,
    Uint8List salt, {
    int iterations = _pinHashIterations,
  }) {
    final hash = EncryptionService.derivePasswordKeyBytes(
      pin,
      salt,
      iterations: iterations,
    );
    return base64Encode(hash);
  }

  bool _constantTimeEquals(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    var diff = aBytes.length ^ bBytes.length;
    for (var i = 0; i < aBytes.length && i < bBytes.length; i++) {
      diff |= aBytes[i] ^ bBytes[i];
    }
    return diff == 0;
  }

  Future<void> _storePinHash(String pin) async {
    final salt = EncryptionService.secureRandomBytes(16);

    final result = await compute(_computePinHash, {
      'pin': pin,
      'salt': base64Encode(salt),
      'iterations': _pinHashIterations,
    });

    await _box.put(
      'local_pin_hash',
      '$_pinHashVersion:$_pinHashIterations:${base64Encode(salt)}:${result['hash']}',
    );
  }

  Future<bool> _verifyStoredPin(String pin, Object? storedHashValue) async {
    if (storedHashValue is! String) return false;

    final parts = storedHashValue.split(':');
    if (parts.length == 4 && parts[0] == _pinHashVersion) {
      final iterations = int.tryParse(parts[1]);
      if (iterations == null) return false;

      final result = await compute(_computePinHash, {
        'pin': pin,
        'salt': parts[2],
        'iterations': iterations,
      });

      return _constantTimeEquals(result['hash']!, parts[3]);
    }

    if (parts.length == 2) {
      final legacySalt = parts[0];
      final legacyHash = parts[1];
      final legacyComputedHash = legacySha256(pin + legacySalt);
      final ok = _constantTimeEquals(legacyComputedHash, legacyHash);
      if (ok) {
        await _storePinHash(pin);
      }
      return ok;
    }

    return false;
  }

  String legacySha256(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  Future<bool> setupInitialPin(
    String pin, {
    required String firstName,
    required String lastName,
    required String groupName,
  }) async {
    if (pin.length < 4) {
      debugPrint('Il PIN deve essere di almeno 4 cifre');
      return false;
    }

    if (firstName.trim().isEmpty ||
        lastName.trim().isEmpty ||
        groupName.trim().isEmpty) {
      debugPrint('Nome, cognome e gruppo sono obbligatori');
      return false;
    }

    try {
      await _storePinHash(pin);
      await _box.put('first_name', firstName.trim());
      await _box.put('last_name', lastName.trim());
      await _box.put('group_name', groupName.trim());
      await _box.put('local_user_name', '$firstName $lastName'.trim());
      _sessionUnlocked = true;
      _cachedUser = null;
      return true;
    } catch (e, stack) {
      debugPrint('Errore durante la configurazione del PIN: $e');
      return false;
    }
  }

  Future<bool> signInWithPin(String inputPin) async {
    try {
      final valid = await _verifyStoredPin(
        inputPin,
        _box.get('local_pin_hash'),
      );
      if (valid) {
        _sessionUnlocked = true;
        _cachedUser = null;
        return true;
      }
      return false;
    } catch (e, stack) {
      debugPrint('Errore durante il controllo del PIN: $e');
      return false;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    try {
      // Verifica supporto biometrico senza richiedere permessi aggiuntivi
      // permission_handler non ha una permission specifica per biometria

      final isDeviceSupported = await _localAuth.isDeviceSupported();
      debugPrint('Dispositivo supportato: $isDeviceSupported');

      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      debugPrint('Can check biometrics: $canCheckBiometrics');

      if (!isDeviceSupported || !canCheckBiometrics) {
        debugPrint('Dispositivo non supporta biometria');
        return false;
      }

      final storedHashValue = _box.get('local_pin_hash');
      if (storedHashValue is! String) {
        debugPrint('PIN non configurato - impossibile usare biometria');
        return false;
      }

      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      debugPrint('Biometrie disponibili: $availableBiometrics');

      if (availableBiometrics.isEmpty) {
        debugPrint('Nessuna biometria configurata sul dispositivo');
        return false;
      }

      final authenticated = await _localAuth
          .authenticate(
            localizedReason: 'Autenticati per sbloccare il Registro',
            biometricOnly: false,
            persistAcrossBackgrounding: true,
          )
          .timeout(const Duration(seconds: 30), onTimeout: () => false);

      if (!authenticated) {
        debugPrint('Autenticazione biometrica fallita o annullata');
        return false;
      }

      _sessionUnlocked = true;
      _cachedUser = null;

      debugPrint('Autenticazione biometrica riuscita');
      return true;
    } catch (e) {
      debugPrint('Errore biometric auth: $e');
      return false;
    }
  }

  Future<bool> changePin(String oldPin, String newPin) async {
    try {
      // Verify old PIN first
      if (!await _verifyStoredPin(oldPin, _box.get('local_pin_hash'))) {
        debugPrint('PIN vecchio non corretto');
        return false;
      }

      // Validate new PIN
      if (newPin.length < 4) {
        debugPrint('Il nuovo PIN deve essere di almeno 4 cifre');
        return false;
      }

      await _storePinHash(newPin);
      return true;
    } catch (e) {
      debugPrint('Errore durante il cambio del PIN: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    _sessionUnlocked = false;
    _cachedUser = null;
  }

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
}
