import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'auth_service.dart';

// 1. Fornisce l'istanza del servizio per eseguire i metodi di sblocco e blocco
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

// 2. 🟢 Gestisce lo stato dell'utente offline (restituisce una mappa di dati o null se bloccato)
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

  /// Verifica lo stato iniziale all'avvio dell'applicazione
  Future<void> _checkInitialState() async {
    try {
      final logged = _authService.isUnlocked;

      if (logged) {
        state = AsyncValue.data(_authService.currentUser);
      } else {
        state = const AsyncValue.data(null);
      }
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Esegue lo sblocco tramite PIN e aggiorna lo stato della UI
  Future<bool> unlock(String pin) async {
    state = const AsyncValue.loading();
    final success = await _authService.signInWithPin(pin);

    if (success) {
      state = AsyncValue.data(_authService.currentUser);
    } else {
      state = const AsyncValue.data(null);
    }
    return success;
  }

  /// Esegue lo sblocco tramite biometria, se disponibile
  Future<bool> unlockWithBiometrics() async {
    state = const AsyncValue.loading();
    final success = await _authService.unlockWithBiometrics();

    if (success) {
      state = AsyncValue.data(_authService.currentUser);
    } else {
      state = const AsyncValue.data(null);
    }
    return success;
  }

  /// Configura il PIN per la prima volta e sblocca l'app
  Future<bool> setupAndUnlock(
    String pin, {
    required String firstName,
    required String lastName,
    required String groupName,
  }) async {
    state = const AsyncValue.loading();
    final success = await _authService.setupInitialPin(
      pin,
      firstName: firstName,
      lastName: lastName,
      groupName: groupName,
    );

    if (success) {
      state = AsyncValue.data(_authService.currentUser);
    } else {
      state = const AsyncValue.data(null);
    }
    return success;
  }

  /// Blocca il registro e resetta lo stato a null
  Future<void> lock() async {
    state = const AsyncValue.loading();
    await _authService.signOut();
    state = const AsyncValue.data(null);
  }
}
