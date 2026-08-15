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
library;
import 'package:flutter/foundation.dart';
import '../../core/auth/auth_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/audit_action.dart';
import '../../shared/models/audit_log.dart';
import '../../shared/models/aula.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/user_role.dart';
import '../../shared/utils/auth_utils.dart';
import '../responsabile/audit_log_repository.dart';
import '../responsabile/slot_conflict_service.dart';

class ClassesRepository {
  /// Ruolo interno "Titolare" per un catechista assegnato a una classe.
  static const roleTitolare = 'TITOLARE';

  /// Ruolo interno "Co-titolo/Aiuto" per un catechista assegnato a una classe.
  static const roleAiuto = 'AIUTO';

  final _box = LocalDatabase.classes();

  /// Difesa in profondità: le operazioni di assegnazione catechisti e di
  /// logistica (slot) sono operazioni "globali" della parrocchia riservate
  /// al Responsabile. La guard di pagina/route resta il confine primario.
  void _requireCanManageClasses() {
    if (!RolePermissions.currentCan(RolePermission.manageClasses)) {
      throw UnsupportedError(
          'Solo il Responsabile Catechistico può gestire le assegnazioni '
          'e la logistica delle classi.');
    }
  }

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
    await _log(AuditActionType.createClass, id, AuditLog.entityClasse);
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
      await _log(AuditActionType.deleteClass, id, AuditLog.entityClasse);
    } catch (e) {
      if (kDebugMode) {
      debugPrint('[ClassesRepository] Errore eliminazione classe $id: $e');
    }
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
      if (kDebugMode) {
      debugPrint('[ClassesRepository] Errore durante cascata cancellazione classe $id: $e');
    }
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

  Future<void> addCatechistToClass(String classId, String catechistId,
      {String role = roleTitolare}) async {
    _requireCanManageClasses();
    final current = _getClass(classId);
    if (current == null || current.catechistIds.contains(catechistId)) return;
    await updateClass(
      classId,
      current.copyWith(
        catechistIds: [...current.catechistIds, catechistId],
        catechistRoles: {...current.catechistRoles, catechistId: role},
      ),
    );
    await _log(AuditActionType.reassignCatechist, classId, AuditLog.entityClasse);
  }

  /// Imposta il ruolo interno di un catechista già assegnato a una classe
  /// (permessi: "TITOLARE" | "AIUTO").
  Future<void> setCatechistRole(
    String classId,
    String catechistId,
    String role,
  ) async {
    _requireCanManageClasses();
    final current = _getClass(classId);
    if (current == null) return;
    if (!current.catechistIds.contains(catechistId)) return;
    await _box.put(classId, current.copyWith(
      catechistRoles: {...current.catechistRoles, catechistId: role},
      lastModifiedBy: getCurrentCatechistName(),
      updatedAt: DateTime.now(),
    ).toMap());
    await _box.flush();
    await _log(AuditActionType.reassignCatechist, classId, AuditLog.entityClasse);
  }

  /// Restituisce il ruolo interno (TITOLARE/AIUTO) di un catechista in una classe.
  String roleOf(SchoolClass c, String catechistId) =>
      c.catechistRoles[catechistId] ?? roleTitolare;

  Future<void> removeCatechistFromClass(String classId, String catechistId) async {
    _requireCanManageClasses();
    final current = _getClass(classId);
    if (current == null) return;
    final roles = Map<String, String>.from(current.catechistRoles)
      ..remove(catechistId);
    await updateClass(
      classId,
      current.copyWith(
        catechistIds:
            current.catechistIds.where((id) => id != catechistId).toList(),
        catechistRoles: roles,
      ),
    );
    await _log(AuditActionType.reassignCatechist, classId, AuditLog.entityClasse);
  }

  /// Assegna uno slot orario settimanale a una classe, verificando i conflitti.
  /// Ritorna una classe aggiornata se l'assegnazione è stata applicata;
  /// solleva [SlotConflictException] se ci sono conflitti con altre classi.
  Future<SchoolClass> assignRoomSlot({
    required String classId,
    required RoomSlot slot,
    List<SchoolClass>? allClasses,
  }) async {
    _requireCanManageClasses();
    final current = _getClass(classId);
    if (current == null) {
      throw ArgumentError('Classe inesistente: $classId');
    }
    final classes = allClasses ?? getClassesSync();
    final conflicts = SlotConflictService.findConflicts(
      target: current,
      newSlot: slot,
      allClasses: classes,
      aulas: _aulasSync(),
    );
    if (conflicts.any((c) => c.classB != null)) {
      throw SlotConflictException(conflicts);
    }
    await updateClass(
      classId,
      current.copyWith(
        roomSlots: [...current.roomSlots, slot],
      ),
    );
    return _getClass(classId) ?? current;
  }

  /// Dismette uno slot da una classe.
  Future<SchoolClass?> removeSlotFromClass(String classId, String slotId) async {
    _requireCanManageClasses();
    final current = _getClass(classId);
    if (current == null) return null;
    await updateClass(
      classId,
      current.copyWith(
        roomSlots: current.roomSlots.where((s) => s.slotId != slotId).toList(),
      ),
    );
    return _getClass(classId);
  }

  List<Aula> _aulasSync() {
    return LocalDatabase.values(
      LocalDatabase.aula(),
      (id, data) => Aula.fromMap(id, data),
    );
  }

  /// Archivia una classe (chiusura percorso, storico conservato).
  Future<void> archiveClass(String id) async {
    final current = _getClass(id);
    if (current == null) return;
    await updateClass(id, current.copyWith(archived: true));
    await _log(AuditActionType.deleteClass, id, AuditLog.entityClasse);
  }

  /// Ripristina una classe archiviata.
  Future<void> unarchiveClass(String id) async {
    final current = _getClass(id);
    if (current == null) return;
    await updateClass(id, current.copyWith(archived: false));
  }

  /// Rinomina una classe conservando tutti gli altri dati.
  Future<void> renameClass(String id, String nuovoNome) async {
    final current = _getClass(id);
    if (current == null) return;
    final nome = nuovoNome.trim();
    if (nome.isEmpty || nome == current.name) return;
    await updateClass(id, current.copyWith(name: nome));
  }

  /// Registra l'azione nel Registro Trattamenti GDPR in modalità best-effort.
  Future<void> _log(
    AuditActionType action,
    String entityId,
    String entityType,
  ) async {
    try {
      await AuditLogRepository().record(
        actionType: action,
        affectedEntityId: entityId,
        affectedEntityType: entityType,
      );
    } catch (e) {
      if (kDebugMode) {
      debugPrint('[ClassesRepository] AuditLog non registrato ($action): $e');
    }
    }
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
