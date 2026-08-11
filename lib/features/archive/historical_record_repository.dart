// ══════════════════════════════════════════════════════════════════════════════
// historical_record_repository.dart — CatechHub (archivio storico ragazzi)
//
// Repository CRUD sull'archivio storico. Opera sul box Hive
// `historical_records_box` tramite [LocalDatabase.historicalRecords].
//
// IMMUTABILITÀ:
//   I record sono SNAPSHOT: non esiste alcun metodo di update. Ogni chiusura
//   d'anno produce nuovi record con un nuovo [recordId]. L'unica operazione
//   di scrittura successiva all'inserimento è la cancellazione per
//   Diritto all'Oblio (cascade delete dello studente) o reset totale.
//
// VISIBILITÀ:
//   La lettura "grezza" espone TUTTI i record del dispositivo. Il filtro di
//   visibilità per ruolo (Responsabile pieno / Catechista limitato alle
//   proprie classi) è applicato da [HistoricalAccessPolicy], non qui.
// ══════════════════════════════════════════════════════════════════════════════

import '../../core/storage/local_database.dart';
import '../../shared/models/historical_record.dart';

class HistoricalRecordRepository {
  final _box = LocalDatabase.historicalRecords();

  /// Stream reattivo di tutti i record storici (più recenti prima).
  Stream<List<HistoricalRecord>> getAllRecords() {
    return LocalDatabase.watchList(
      _box,
      (id, data) => HistoricalRecord.fromMap(id, data),
    ).map(_sortNewestFirst);
  }

  /// Lettura sincrona di tutti i record storici.
  List<HistoricalRecord> getAllRecordsSync() {
    return _sortNewestFirst(LocalDatabase.values(
      _box,
      (id, data) => HistoricalRecord.fromMap(id, data),
    ));
  }

  /// Stream dei record storici di uno specifico studente.
  Stream<List<HistoricalRecord>> getRecordsForStudent(String studentId) {
    return getAllRecords().map(
      (records) => records.where((r) => r.studentId == studentId).toList(),
    );
  }

  /// Record storici di un gruppo di studenti (per la vista catechista).
  List<HistoricalRecord> getRecordsForStudentsSync(Set<String> studentIds) {
    if (studentIds.isEmpty) return const [];
    return getAllRecordsSync()
        .where((r) => studentIds.contains(r.studentId))
        .toList();
  }

  /// Inserisce uno snapshot immutabile. Se [recordId] è vuoto ne genera uno.
  Future<HistoricalRecord> addRecord(HistoricalRecord record) async {
    final id = record.recordId.isEmpty
        ? LocalDatabase.newId('hist')
        : record.recordId;
    await _box.put(id, record.copyWith(recordId: id).toMap());
    await _box.flush();
    return record.copyWith(recordId: id);
  }

  /// Inserisce più snapshot (chiusura anno massiva) in un'unica scrittura.
  Future<List<HistoricalRecord>> addMany(List<HistoricalRecord> records) async {
    final out = <HistoricalRecord>[];
    for (final record in records) {
      final id = record.recordId.isEmpty
          ? LocalDatabase.newId('hist')
          : record.recordId;
      out.add(record.copyWith(recordId: id));
    }
    await _box.putAll({for (final r in out) r.recordId: r.toMap()});
    await _box.flush();
    return out;
  }

  /// Elimina i record di un singolo studente (Diritto all'Oblio / cascade).
  Future<void> deleteRecordsForStudent(String studentId) async {
    final keys = _box.keys
        .where((key) {
          final data = _box.get(key);
          if (data == null) return false;
          return LocalDatabase.toStringDynamicMap(data)['studentId'] ==
              studentId;
        })
        .toList();
    for (final key in keys) {
      await _box.delete(key);
    }
  }

  /// Elimina i record di un gruppo di studenti (cancellazione anagrafica).
  Future<void> deleteRecordsForStudents(Iterable<String> studentIds) async {
    final set = studentIds.toSet();
    if (set.isEmpty) return;
    final keys = _box.keys
        .where((key) {
          final data = _box.get(key);
          if (data == null) return false;
          return set.contains(LocalDatabase.toStringDynamicMap(data)['studentId']);
        })
        .toList();
    for (final key in keys) {
      await _box.delete(key);
    }
  }

  /// Svuota l'intero archivio (reset totale).
  Future<void> deleteAll() async {
    await _box.clear();
    await _box.flush();
  }

  /// Conteggio dei record storici (per UI di conferma / info).
  int get count => _box.length;

  static List<HistoricalRecord> _sortNewestFirst(
    List<HistoricalRecord> records,
  ) {
    final list = records.toList()
      ..sort((a, b) => b.academicYear.compareTo(a.academicYear));
    return list;
  }
}
