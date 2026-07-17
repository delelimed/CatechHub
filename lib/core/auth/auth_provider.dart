// ══════════════════════════════════════════════════════════════════════════════
// auth_provider.dart — CatechHub (Riverpod auth state machine - POST MIGRAZIONE)
// 
// NUOVO FLUSSO (solo biometria/PIN telefono):
//   - NESSUN PIN app proprio
//   - isPinConfigured → SEMPRE false (rimosso per compatibilità, deprecato)
//   - setupInitialProfile() → solo profilo (nome, cognome, gruppo), NO PIN
//   - unlock() → SOLO biometria nativa (con fallback automatico PIN telefono)
//   - Sessione in RAM (_sessionUnlocked), kill processo = rientro richiesto
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_service.dart';
import '../../shared/models/class_model.dart';
import '../storage/local_database.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = AsyncNotifierProvider<LocalAuthNotifier, Map<String, dynamic>?>(
  () => LocalAuthNotifier(),
);

class LocalAuthNotifier extends AsyncNotifier<Map<String, dynamic>?> {
  AuthService get _authService => ref.read(authServiceProvider);

  @override
  Future<Map<String, dynamic>?> build() async {
    final logged = _authService.isUnlocked;
    return logged ? _authService.currentUser : null;
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

  /// Sblocca la sessione SOLO con autenticazione biometrica nativa
  /// (con fallback automatico PIN/pattern/password del TELEFONO).
  /// NON accetta PIN proprio dell'app (non esiste più).
  Future<bool> unlockWithBiometrics() async {
    state = const AsyncValue.loading();
    try {
      final success = await _withTimeout(
        _authService.authenticate(),
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

  /// Configurazione profilo INIZIALE (prima volta).
  /// Salva: nome, cognome, gruppo. NON chiede PIN (usa biometria telefono).
  /// Crea automaticamente la SchoolClass iniziale.
  Future<bool> setupInitialProfile({
    required String firstName,
    required String lastName,
    required String groupName,
  }) async {
    state = const AsyncValue.loading();
    try {
      final success = await _withTimeout(
        _authService.setupInitialProfile(
          firstName: firstName,
          lastName: lastName,
          groupName: groupName,
        ),
        const Duration(seconds: 30),
        'Timeout durante la configurazione',
      );

      if (!success) {
        state = AsyncValue.data(null);
        return false;
      }

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
        await _authService.signOut();
        state = AsyncValue.error(e, stack);
        return false;
      }

      state = AsyncValue.data(_authService.currentUser);
      return true;
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      return false;
    }
  }

  /// Blocca la sessione (senza cancellare dati).
  Future<void> lock() async {
    state = const AsyncValue.loading();
    try {
      await _authService.signOut();
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// RESET COMPLETO: cancella profilo e chiavi. Per "disinstallazione logica".
  Future<void> resetAll() async {
    state = const AsyncValue.loading();
    try {
      await _authService.resetAll();
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
}