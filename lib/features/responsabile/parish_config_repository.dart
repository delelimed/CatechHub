// ══════════════════════════════════════════════════════════════════════════════
// parish_config_repository.dart — CatechHub (configurazione parrocchiale)
//
// Modulo "Responsabile Catechistico": repository della configurazione
// locale della parrocchia. Persiste un SINGOLO record [ParishConfig] nel box
// `parish_config_box` con chiave fissa [ParishConfig.storageKey].
// La scrittura è riservata a [UserRole.responsabile].
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/parish_config.dart';
import '../../shared/models/user_role.dart';

final parishConfigRepositoryProvider = Provider<ParishConfigRepository>((ref) {
  return ParishConfigRepository();
});

/// Repository della configurazione parrocchiale (singlet record).
class ParishConfigRepository {
  final _box = LocalDatabase.parishConfig();

  /// Legge la configurazione corrente; ritorna [ParishConfig.empty] se assente.
  ParishConfig getConfig() {
    final raw = _box.get(ParishConfig.storageKey);
    if (raw == null) return ParishConfig.empty;
    return ParishConfig.fromMap(LocalDatabase.toStringDynamicMap(raw));
  }

  /// True se l'utente corrente può gestire la configurazione parrocchiale.
  bool get canManage => RolePermissions.currentCan(RolePermission.manageParishConfig);

  /// Salva la configurazione. Solo il Responsabile può scrivere.
  Future<ParishConfig> save(ParishConfig config) async {
    if (!canManage) {
      throw UnsupportedError('Solo il Responsabile Catechistico può gestire '
          'la configurazione parrocchiale.');
    }
    await _box.put(ParishConfig.storageKey, config.toMap());
    await _box.flush();
    return config;
  }

  /// Sblocca/blocca la modalità Responsabile Catechistico, conservando gli
  /// altri valori di configurazione.
  Future<ParishConfig> setResponsabileModeActive(bool active) async {
    final updated = getConfig().copyWith(isResponsabileModeActive: active);
    return save(updated);
  }

  /// Imposta forzatamente la modalità Responsabile durante l'ONBOARDING,
  /// prima ancora che il profilo (e quindi il ruolo) sia configurato.
  /// Non controlla la matrice dei permessi: l'utente non è ancora autenticato.
  Future<ParishConfig> forceResponsabileMode(bool active) async {
    final updated = getConfig().copyWith(isResponsabileModeActive: active);
    await _box.put(ParishConfig.storageKey, updated.toMap());
    await _box.flush();
    return updated;
  }

  /// Storale, riporta alla configurazione vuota (disattivando la modalità).
  Future<void> reset() async {
    await _box.delete(ParishConfig.storageKey);
    await _box.flush();
  }
}