import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';

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
      return await Future.delayed(Duration.zero, () async {
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
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('Timeout setup PIN');
          return false;
        },
      );
    } catch (e) {
      debugPrint('Errore durante la configurazione del PIN: $e');
      return false;
    }
  }

  Future<bool> signInWithPin(String inputPin) async {
    try {
      return await Future.delayed(Duration.zero, () async {
        final storedHashValue = _box.get('local_pin_hash');
        if (storedHashValue is! String) return false;

        final parts = storedHashValue.split(':');
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
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('Timeout verifica PIN');
          return false;
        },
      );
    } catch (e) {
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

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Autenticati per sbloccare il Registro',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: false,
          useErrorDialogs: true,
        ),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );

      if (!authenticated) {
        debugPrint('Autenticazione biometrica fallita o annullata');
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