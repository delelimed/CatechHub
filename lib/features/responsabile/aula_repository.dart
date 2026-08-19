// ══════════════════════════════════════════════════════════════════════════════
// aula_repository.dart — CatechHub (logistica parrocchiale: aule e slot)
//
// Modulo "Responsabile Catechistico":
//  - CRUD delle aule/stanza parrocchiali (box `aula_box`).
//  - Assegnazione/dismissione di slot settimanali ([RoomSlot]) alle classi,
//    delegando il controllo dei conflitti allo [SlotConflictService].
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/aula.dart';
import '../../shared/models/user_role.dart';

final aulaRepositoryProvider = Provider<AulaRepository>((ref) {
  return AulaRepository();
});

/// Repository delle aule e slot settimanali.
class AulaRepository {
  final _box = LocalDatabase.aula();

  bool get canManage => RolePermissions.currentCan(RolePermission.manageAulas);

  Stream<List<Aula>> getAulas() {
    return LocalDatabase.watchList(
      _box,
      (id, data) => Aula.fromMap(id, data),
    ).map(
      (aulas) => (aulas..sort((a, b) => a.nomeStanza.compareTo(b.nomeStanza))),
    );
  }

  List<Aula> getAulasSync() {
    final aulas = LocalDatabase.values(
      _box,
      (id, data) => Aula.fromMap(id, data),
    );
    aulas.sort((a, b) => a.nomeStanza.compareTo(b.nomeStanza));
    return aulas;
  }

  Aula? getAula(String stanzaId) {
    final data = _box.get(stanzaId);
    if (data == null) return null;
    return Aula.fromMap(stanzaId, LocalDatabase.toStringDynamicMap(data));
  }

  Future<void> saveAula(Aula aula) async {
    if (!canManage) {
      throw UnsupportedError(
        'Solo il Responsabile Catechistico può gestire '
        'le aule parrocchiali.',
      );
    }
    final id = aula.stanzaId.isEmpty
        ? LocalDatabase.newId('stanza')
        : aula.stanzaId;
    await _box.put(
      id,
      aula.copyWith(stanzaId: id, updatedAt: DateTime.now()).toMap(),
    );
    await _box.flush();
  }

  Future<void> deleteAula(String stanzaId) async {
    await _box.delete(stanzaId);
    await _box.flush();
    await _removeStatsFromClasses(stanzaId);
  }

  /// Rimuove lo slot riferito all'aula da tutte le classi (se l'azienda
  /// viene eliminata, gli slot orari residui vengono tolti).
  Future<void> _removeStatsFromClasses(String stanzaId) async {
    final classesBox = LocalDatabase.classes();
    for (final key in classesBox.keys) {
      final raw = classesBox.get(key);
      if (raw == null) continue;
      final data = LocalDatabase.toStringDynamicMap(raw);
      final slotEvent = data['roomSlots'];
      if (slotEvent is! List) continue;
      final remaining = slotEvent
          .whereType<Map>()
          .map((e) => RoomSlot.fromMap(Map<String, dynamic>.from(e)))
          .where((s) => s.stanzaId != stanzaId)
          .map((s) => s.toMap())
          .toList();
      data['roomSlots'] = remaining;
      await classesBox.put(key, data);
    }
  }
}
