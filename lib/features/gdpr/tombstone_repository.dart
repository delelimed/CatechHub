// ══════════════════════════════════════════════════════════════════════════════
// tombstone_repository.dart — CatechHub (persistenza dei tombstone)
//
// Modulo "GDPR & Privacy" — Diritto all'Oblio:
// Persistenza dei tombstone nel box `tombstone_box`. Append-only; i tombstone
// non vengono mai cancellati automaticamente (devono restare per impedire la
// "resurrezione" dei dati da sync successivi).
// ══════════════════════════════════════════════════════════════════════════════

import '../../core/storage/local_database.dart';
import 'tombstone_model.dart';

/// Repository dei tombstone (record di eliminazione definitiva).
class TombstoneRepository {
  final _box = LocalDatabase.tombstones();

  /// Salva (o aggiorna) un tombstone.
  Future<void> put(Tombstone tombstone) async {
    await _box.put(tombstone.id, tombstone.toMap());
    await _box.flush();
  }

  /// True se esiste un tombstone per l'entità [entityId].
  bool hasTombstone(String entityId) =>
      _box.keys.any(
        (k) => LocalDatabase.toStringDynamicMap(_box.get(k))['entityId'] ==
            entityId,
      );

  /// Ritorna il tombstone di [entityId], o null se assente.
  Tombstone? byEntityId(String entityId) {
    for (final key in _box.keys) {
      final map = LocalDatabase.toStringDynamicMap(_box.get(key));
      if (map['entityId'] == entityId) {
        return Tombstone.fromMap(key.toString(), map);
      }
    }
    return null;
  }

  /// Elenco completo dei tombstone (più recenti prima).
  List<Tombstone> getAll() {
    final list = _box.keys.map((key) {
      final map = LocalDatabase.toStringDynamicMap(_box.get(key));
      return Tombstone.fromMap(key.toString(), map);
    }).toList()
      ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return list;
  }

  /// ID dei tombstone correnti (utile per esclusioni durante il sync).
  Set<String> entityIdsTombstoned() {
    return _box.keys
        .map((key) =>
            LocalDatabase.toStringDynamicMap(_box.get(key))['entityId'])
        .whereType<String>()
        .toSet();
  }

  Future<void> clear() async {
    await _box.clear();
  }
}