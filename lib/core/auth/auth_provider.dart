import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'auth_service.dart';

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
      final success = await _authService.signInWithPin(pin);
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
      final success = await _authService.unlockWithBiometrics();
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
      final success = await _authService.setupInitialPin(
        pin,
        firstName: firstName,
        lastName: lastName,
        groupName: groupName,
      );
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
}
