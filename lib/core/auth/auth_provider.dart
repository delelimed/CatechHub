import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_service.dart';
import '../../shared/models/class_model.dart';
import '../storage/local_database.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authStateProvider =
    StateNotifierProvider<LocalAuthNotifier, AsyncValue<Map<String, dynamic>?>>(
      (ref) {
        final authService = ref.watch(authServiceProvider);
        return LocalAuthNotifier(authService);
      },
    );

class LocalAuthNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>?>> {
  final AuthService _authService;

  LocalAuthNotifier(this._authService) : super(const AsyncValue.loading()) {
    Future.microtask(_checkInitialState);
  }

  Future<T> _withTimeout<T>(
    Future<T> future,
    Duration duration,
    String timeoutMessage,
  ) {
    return future.timeout(
      duration,
      onTimeout: () => throw TimeoutException(timeoutMessage),
    );
  }

  Future<void> _checkInitialState() async {
    try {
      final logged = _authService.isUnlocked;
      state = AsyncValue.data(logged ? _authService.currentUser : null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<bool> unlock(String pin) async {
    state = const AsyncValue.loading();
    try {
      final success = await _withTimeout(
        _authService.signInWithPin(pin),
        const Duration(seconds: 30),
        'Timeout durante il login',
      );
      state = AsyncValue.data(success ? _authService.currentUser : null);
      return success;
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      return false;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    state = const AsyncValue.loading();
    try {
      final success = await _withTimeout(
        _authService.unlockWithBiometrics(),
        const Duration(seconds: 45),
        'Timeout durante autenticazione biometrica',
      );
      state = AsyncValue.data(success ? _authService.currentUser : null);
      return success;
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      return false;
    }
  }

  Future<bool> setupAndUnlock(
    String pin, {
    required String firstName,
    required String lastName,
    required String groupName,
  }) async {
    state = const AsyncValue.loading();
    try {
      final success = await _withTimeout(
        _authService.setupInitialPin(
          pin,
          firstName: firstName,
          lastName: lastName,
          groupName: groupName,
        ),
        const Duration(seconds: 30),
        'Timeout durante la configurazione',
      );

      if (success) {
        try {
          final classBox = LocalDatabase.classes();
          final classId = LocalDatabase.newId('class');
          final newClass = SchoolClass(
            id: classId,
            name: groupName,
            studentIds: [],
            catechistIds: [AuthService.localUserId],
          );
          await classBox.put(classId, newClass.toMap());
        } catch (e, stack) {
          debugPrint('Errore durante la creazione del gruppo iniziale: $e');
        }
      }

      state = AsyncValue.data(success ? _authService.currentUser : null);
      return success;
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      return false;
    }
  }

  Future<void> lock() async {
    state = const AsyncValue.loading();
    try {
      await _authService.signOut();
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<bool> changePin(String oldPin, String newPin) async {
    try {
      return await _withTimeout(
        _authService.changePin(oldPin, newPin),
        const Duration(seconds: 30),
        'Timeout durante il cambio PIN',
      );
    } catch (e, stack) {
      debugPrint('Errore durante il cambio PIN: $e');
      return false;
    }
  }
}
