/// Repository CRUD per le classi (gruppi catechistici) in CateREG.
///
/// Opera sul box Hive `classes` tramite [LocalDatabase.classes] e fornisce:
/// - Stream e lettura sincrona dell'elenco classi.
/// - Operazioni di scrittura: add, update, delete con **cascata**:
///   alla cancellazione di una classe vengono rimossi anche i relativi
///   record nei box `planning` e `attendance`.
/// - Gestione delle assegnazioni: aggiunta/rimozione di studenti e
///   catechisti a una classe.
/// - All'update, se degli studenti vengono rimossi dalla classe, i relativi
///   record di presenza vengono automaticamente puliti dal box `attendance`.
///
/// Integrazione CateREG: usato da [classesRepoProvider] e da tutte le
/// pagine che necessitano di leggere o modificare i dati delle classi.
import 'package:flutter/foundation.dart';
import '../../core/auth/auth_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/class_model.dart';
import '../../shared/utils/auth_utils.dart';

class ClassesRepository {
  final _box = LocalDatabase.classes();

  Stream<List<SchoolClass>> getClasses() {
    return LocalDatabase.watchList(
      _box,
      (id, data) => SchoolClass.fromMap(id, data),
    );
  }

  List<SchoolClass> getClassesSync() {
    return LocalDatabase.values(
      _box,
      (id, data) => SchoolClass.fromMap(id, data),
    );
  }

  Future<void> addClass(SchoolClass c) async {
    final id = c.id.isEmpty ? LocalDatabase.newId('class') : c.id;
    final code = c.uniqueCode.isEmpty ? generateClassUniqueCode() : c.uniqueCode;
    final catechistName = getCurrentCatechistName();
    final now = DateTime.now();
    final creatorId = c.creatorId.isEmpty ? AuthService.localUserId : c.creatorId;
    final creatorName = c.creatorName.isEmpty ? catechistName : c.creatorName;
    await _box.put(id, c.copyWith(
      id: id,
      uniqueCode: code,
      lastModifiedBy: catechistName,
      creatorId: creatorId,
      creatorName: creatorName,
      createdAt: now,
      updatedAt: now,
    ).toMap());
    // Forza la scrittura su disco: evita la perdita di una classe appena
    // creata se il processo viene terminato dal sistema subito dopo.
    await _box.flush();
  }

  Future<void> updateClass(String id, SchoolClass c) async {
    final previous = _getClass(id);
    if (previous == null) return;

    final currentName = getCurrentCatechistName();
    final isCreator = previous.isCreator(AuthService.localUserId, currentName, catechistId: AuthService.getCatechistId());

    SchoolClass toSave;
    if (isCreator) {
      toSave = c;
    } else {
      toSave = c.copyWith(
        name: previous.name,
        catechistIds: previous.catechistIds,
      );
    }

    final catechistName = getCurrentCatechistName();
    await _box.put(id, toSave.copyWith(
      id: id,
      lastModifiedBy: catechistName,
      updatedAt: DateTime.now(),
    ).toMap());
    await _box.flush();

    final removedStudentIds = previous.studentIds
        .where((studentId) => !c.studentIds.contains(studentId))
        .toList();
    if (removedStudentIds.isEmpty) return;

    final attendanceBox = LocalDatabase.attendance();
    for (final attendanceKey in attendanceBox.keys) {
      final data = LocalDatabase.toStringDynamicMap(attendanceBox.get(attendanceKey));
      if (data['classId'] != id) continue;

      final presence = Map<String, dynamic>.from(data['presence'] as Map? ?? {});
      var changed = false;
      for (final studentId in removedStudentIds) {
        changed = presence.remove(studentId) != null || changed;
      }

      if (changed) {
        data['presence'] = presence;
        await attendanceBox.put(attendanceKey, data);
      }
    }
  }

  Future<void> deleteClass(String id) async {
    try {
      await _box.delete(id);
      await _box.flush();
    } catch (e) {
      debugPrint('[ClassesRepository] Errore eliminazione classe $id: $e');
    }

    try {
      final planningBox = LocalDatabase.planning();
      final attendanceBox = LocalDatabase.attendance();

      final keysToDelete = <dynamic>[];
      for (final key in planningBox.keys) {
        try {
          final raw = planningBox.get(key);
          if (raw == null) continue;
          final data = LocalDatabase.toStringDynamicMap(raw);
          if (data['classId'] == id) keysToDelete.add(key);
        } catch (_) {
          continue;
        }
      }

      for (final key in keysToDelete) {
        try {
          await planningBox.delete(key);
        } catch (_) {}
        try {
          await attendanceBox.delete(key);
        } catch (_) {}
      }

      final attendanceKeysToDelete = <dynamic>[];
      for (final key in attendanceBox.keys) {
        try {
          final raw = attendanceBox.get(key);
          if (raw == null) continue;
          final data = LocalDatabase.toStringDynamicMap(raw);
          if (data['classId'] == id) attendanceKeysToDelete.add(key);
        } catch (_) {
          continue;
        }
      }

      for (final key in attendanceKeysToDelete) {
        try {
          await attendanceBox.delete(key);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[ClassesRepository] Errore durante cascata cancellazione classe $id: $e');
    }
  }

  Future<void> addStudentToClass(String classId, String studentId) async {
    final current = _getClass(classId);
    if (current == null || current.studentIds.contains(studentId)) return;
    await updateClass(
      classId,
      current.copyWith(studentIds: [...current.studentIds, studentId]),
    );
  }

  Future<void> removeStudentFromClass(String classId, String studentId) async {
    final current = _getClass(classId);
    if (current == null) return;
    await updateClass(
      classId,
      current.copyWith(
        studentIds: current.studentIds.where((id) => id != studentId).toList(),
      ),
    );
  }

  Future<void> addCatechistToClass(String classId, String catechistId) async {
    final current = _getClass(classId);
    if (current == null || current.catechistIds.contains(catechistId)) return;
    await updateClass(
      classId,
      current.copyWith(catechistIds: [...current.catechistIds, catechistId]),
    );
  }

  Future<void> removeCatechistFromClass(String classId, String catechistId) async {
    final current = _getClass(classId);
    if (current == null) return;
    await updateClass(
      classId,
      current.copyWith(
        catechistIds:
            current.catechistIds.where((id) => id != catechistId).toList(),
      ),
    );
  }

  SchoolClass? _getClass(String id) {
    final data = _box.get(id);
    if (data == null) return null;
    return SchoolClass.fromMap(id, LocalDatabase.toStringDynamicMap(data));
  }

  /// Assicura che tutte le classi abbiano un [uniqueCode].
  /// Da chiamare all'avvio per backfillare classi create prima
  /// dell'introduzione del campo.
  Future<void> ensureUniqueCodes() async {
    // Pulisci eventuali entry con chiave vuota (da import backup con ID mancanti)
    for (final key in _box.keys.toList()) {
      if (key.toString().isEmpty) {
        await _box.delete(key);
        continue;
      }
      final raw = _box.get(key);
      if (raw == null) continue;
      final data = LocalDatabase.toStringDynamicMap(raw);
      if (data['uniqueCode'] == null || (data['uniqueCode'] as String).isEmpty) {
        data['uniqueCode'] = generateClassUniqueCode();
        data['updatedAt'] = DateTime.now().toUtc().toIso8601String();
        await _box.put(key, data);
      }
    }
  }
}
