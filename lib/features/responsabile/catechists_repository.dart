// ══════════════════════════════════════════════════════════════════════════════
// catechists_repository.dart — CatechHub (rubrica catechisti della parrocchia)
//
// Modulo "Responsabile Catechistico": repository della rubrica dei catechisti.
// Persiste i profili [CatechistProfile] nel box `catechists_box` con chiave =
// catechistId. La scrittura è riservata al ruolo Responsabile.
//
// Il catechistId qui creato è lo stesso usato per:
//   - l'assegnazione alle classi (SchoolClass.catechistIds / catechistRoles);
//   - il collegamento ai dispositivi associati via P2P
//     (P2PDeviceAssociation.catechistId).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/catechist_profile.dart';
import '../../shared/models/user_role.dart';

final catechistsRepositoryProvider = Provider<CatechistsRepository>((ref) {
  return CatechistsRepository();
});

/// Stream reattivo dei profili catechisti ordinati per cognome.
final catechistsStreamProvider = StreamProvider<List<CatechistProfile>>((ref) {
  return ref.watch(catechistsRepositoryProvider).watchAll();
});

/// Repository della rubrica catechisti.
class CatechistsRepository {
  final _box = LocalDatabase.catechists();

  /// True se l'utente corrente può gestire la rubrica (solo Responsabile).
  bool get canManage => UserRole.isResponsabile;

  /// Stream reattivo dei profili ordinati per cognome.
  Stream<List<CatechistProfile>> watchAll() {
    return LocalDatabase.watchList(
      _box,
      (id, data) => CatechistProfile.fromMap(id, data),
    ).map(_sortBySurname);
  }

  /// Lettura sincrona di tutti i profili ordinati per cognome.
  List<CatechistProfile> getAllSync() {
    return _sortBySurname(
      LocalDatabase.values(
        _box,
        (id, data) => CatechistProfile.fromMap(id, data),
      ),
    );
  }

  /// Legge un singolo profilo, o null se assente.
  CatechistProfile? getById(String id) {
    final raw = _box.get(id);
    if (raw == null) return null;
    return CatechistProfile.fromMap(id, LocalDatabase.toStringDynamicMap(raw));
  }

  /// Crea o aggiorna un profilo catechista. Solo il Responsabile può scrivere.
  Future<void> save(CatechistProfile profile) async {
    if (!canManage) {
      throw UnsupportedError(
        'Solo il Responsabile Catechistico può gestire la rubrica catechisti.',
      );
    }
    await _box.put(profile.id, profile.toMap());
    await _box.flush();
  }

  /// Elimina un profilo. Solo il Responsabile può cancellare.
  Future<void> delete(String id) async {
    if (!canManage) {
      throw UnsupportedError(
        'Solo il Responsabile Catechistico può gestire la rubrica catechisti.',
      );
    }
    await _box.delete(id);
    await _box.flush();
  }

  List<CatechistProfile> _sortBySurname(List<CatechistProfile> list) {
    final sorted = [...list];
    sorted.sort((a, b) {
      final cmp = a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
      if (cmp != 0) return cmp;
      return a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
    });
    return sorted;
  }
}
