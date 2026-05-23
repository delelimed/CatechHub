import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:local_auth/local_auth.dart';

import '../storage/local_database.dart';

class AuthService {
  static const localUserId = 'local_catechist_id';
  static const localUserName = 'Catechista Locale';

  final _box = LocalDatabase.auth();
  final _localAuth = LocalAuthentication();
  Map<String, dynamic>? _cachedUser;

  bool get isPinConfigured => _box.containsKey('local_pin_hash');

  bool get isUnlocked => _box.get('isLoggedIn', defaultValue: false);

  bool get hasProfileData {
    return _box.containsKey('first_name') &&
        _box.containsKey('last_name') &&
        _box.containsKey('group_name');
  }

  String _hashPin(String pin, String salt) {
    return sha256.convert(utf8.encode(pin + salt)).toString();
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
      final salt = DateTime.now().microsecondsSinceEpoch.toString();
      final pinHash = _hashPin(pin, salt);
      await _box.put('local_pin_hash', '$salt:$pinHash');
      await _box.put('first_name', firstName.trim());
      await _box.put('last_name', lastName.trim());
      await _box.put('group_name', groupName.trim());
      await _box.put('local_user_name', '$firstName $lastName'.trim());
      await _box.put('isLoggedIn', true);
      _cachedUser = null;
      return true;
    } catch (e) {
      debugPrint('Errore durante la configurazione del PIN: $e');
      return false;
    }
  }

  Future<bool> signInWithPin(String inputPin) async {
    try {
      final storedHash = _box.get('local_pin_hash') as String?;
      if (storedHash == null) return false;

      final parts = storedHash.split(':');
      if (parts.length != 2) return false;

      final salt = parts[0];
      final savedHash = parts[1];
      final computedHash = _hashPin(inputPin, salt);

      if (computedHash == savedHash) {
        await _box.put('isLoggedIn', true);
        _cachedUser = null;
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Errore durante il controllo del PIN: $e');
      return false;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    try {
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;

      debugPrint('Biometric check - Supported: $isDeviceSupported, CanCheck: $canCheckBiometrics');

      if (!isDeviceSupported && !canCheckBiometrics) {
        debugPrint('Dispositivo non supporta biometrica');
        return false;
      }

      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      debugPrint('Biometriche disponibili: $availableBiometrics');

      if (availableBiometrics.isEmpty) {
        debugPrint('Nessuna biometrica configurata sul dispositivo');
        return false;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Autenticati per sbloccare il Registro',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: false,
          useErrorDialogs: true,
        ),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('Timeout autenticazione biometrica');
          return false;
        },
      );

      if (!authenticated) {
        debugPrint('Autenticazione biometrica fallita o annullata');
        return false;
      }

      final storedHash = _box.get('local_pin_hash');
      if (storedHash == null) {
        debugPrint('PIN non configurato');
        return false;
      }

      await _box.put('isLoggedIn', true);
      _cachedUser = null;
      debugPrint('Autenticazione biometrica riuscita');
      return true;
    } catch (e) {
      debugPrint('Errore biometric auth: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    await _box.put('isLoggedIn', false);
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
