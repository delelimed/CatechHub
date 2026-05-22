import 'package:flutter/foundation.dart' show debugPrint;
import 'package:local_auth/local_auth.dart';

import '../storage/local_database.dart';

class AuthService {
  static const localUserId = 'local_catechist_id';
  static const localUserName = 'Catechista Locale';

  final _box = LocalDatabase.auth();
  final _localAuth = LocalAuthentication();

  bool get isPinConfigured => _box.containsKey('local_pin_hash');

  bool get isUnlocked => _box.get('isLoggedIn', defaultValue: false);

  bool get hasProfileData {
    return _box.containsKey('first_name') &&
        _box.containsKey('last_name') &&
        _box.containsKey('group_name');
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
      await _box.put('local_pin_hash', pin);
      await _box.put('first_name', firstName.trim());
      await _box.put('last_name', lastName.trim());
      await _box.put('group_name', groupName.trim());
      await _box.put('local_user_name', '$firstName $lastName'.trim());
      await _box.put('isLoggedIn', true);
      return true;
    } catch (e) {
      debugPrint('Errore durante la configurazione del PIN: $e');
      return false;
    }
  }

  Future<bool> signInWithPin(String inputPin) async {
    try {
      final savedPin = _box.get('local_pin_hash');
      if (savedPin == null) return false;

      if (savedPin == inputPin) {
        await _box.put('isLoggedIn', true);
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
      final canAuthenticate =
          await _localAuth.isDeviceSupported() ||
          await _localAuth.canCheckBiometrics;
      if (!canAuthenticate) return false;

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Autenticati per sbloccare il Registro',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: false,
        ),
      );

      if (!authenticated) return false;

      final savedPin = _box.get('local_pin_hash');
      if (savedPin == null) return false;

      await _box.put('isLoggedIn', true);
      return true;
    } catch (e) {
      debugPrint('Errore biometric auth: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    await _box.put('isLoggedIn', false);
  }

  Map<String, dynamic>? get currentUser {
    if (!isUnlocked) return null;
    return {
      'uid': localUserId,
      'name': _box.get('local_user_name', defaultValue: localUserName),
      'firstName': _box.get('first_name', defaultValue: ''),
      'lastName': _box.get('last_name', defaultValue: ''),
      'groupName': _box.get('group_name', defaultValue: ''),
      'email': 'locale@dispositivo',
      'role': 'catechist',
      'canManageCatechists': true,
    };
  }
}
