/// Repository del modulo "Supplenze Temporanee e Delega Sicura".
///
/// Opera su due Box Hive:
/// - `substitute_delegations_box` (Map, chiave = delegationId): le deleghe.
/// - `substitute_lesson_notes_box` (Map, chiave = noteId): le note di lezione
///   registrate dal Supplente durante la supplenza.
///
/// Gestisce inoltre il ciclo di vita locale della classe «ombra» sul
/// dispositivo del Supplente (snapshot di classi/studenti + chiave temporanea).
library;

import 'dart:convert';

import '../../core/storage/local_database.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/substitute_delegation.dart';
import '../../shared/utils/auth_utils.dart';
import '../sync/class_channel_service.dart';

class SubstituteDelegationRepository {
  final _box = LocalDatabase.substituteDelegations();
  final _notesBox = LocalDatabase.substituteLessonNotes();

  // ─────────────────────────────────────────────────────────────────────────
  // DELEGHE
  // ─────────────────────────────────────────────────────────────────────────

  Stream<List<SubstituteDelegation>> watchDelegations() {
    return LocalDatabase.watchList(
      _box,
      (id, data) => SubstituteDelegation.fromMap(id, data),
    );
  }

  List<SubstituteDelegation> getDelegationsSync() {
    return LocalDatabase.values(
      _box,
      (id, data) => SubstituteDelegation.fromMap(id, data),
    );
  }

  SubstituteDelegation? getById(String delegationId) {
    final raw = _box.get(delegationId);
    if (raw == null) return null;
    return SubstituteDelegation.fromMap(
      delegationId,
      LocalDatabase.toStringDynamicMap(raw),
    );
  }

  SubstituteDelegation? getForClass(String classId) {
    for (final delegation in getDelegationsSync()) {
      if (delegation.classId == classId) return delegation;
    }
    return null;
  }

  Future<void> save(SubstituteDelegation delegation) async {
    await _box.put(delegation.delegationId, delegation.toMap());
    await _box.flush();
  }

  Future<void> updateStatus(String delegationId, String status) async {
    final current = getById(delegationId);
    if (current == null) return;
    await save(
      current.copyWith(status: status, updatedAt: DateTime.now().toUtc()),
    );
  }

  Future<void> markCollected(String delegationId) async {
    final current = getById(delegationId);
    if (current == null) return;
    await save(
      current.copyWith(dataCollected: true, updatedAt: DateTime.now().toUtc()),
    );
  }

  /// Registry: rende persistente la scadenza naturale delle deleghe attive
  /// oltre [validUntil].
  Future<void> expirePastDelegations() async {
    final now = DateTime.now().toUtc();
    for (final delegation in getDelegationsSync()) {
      if (delegation.status == SubstituteDelegationStatus.active &&
          delegation.isExpiredAt(now)) {
        await updateStatus(
          delegation.delegationId,
          SubstituteDelegationStatus.expired,
        );
      }
    }
  }

  Future<void> delete(String delegationId) async {
    await _box.delete(delegationId);
    await _box.flush();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NOTE DI LEZIONE
  // ─────────────────────────────────────────────────────────────────────────

  Stream<List<SubstituteLessonNote>> watchNotesByClass(String classId) {
    return LocalDatabase.watchList(
      _notesBox,
      (id, data) => SubstituteLessonNote.fromMap(id, data),
    ).map((notes) => notes.where((n) => n.classId == classId).toList());
  }

  List<SubstituteLessonNote> getNotesForClassSync(String classId) {
    return LocalDatabase.values(
      _notesBox,
      (id, data) => SubstituteLessonNote.fromMap(id, data),
    ).where((n) => n.classId == classId).toList();
  }

  List<SubstituteLessonNote> getNotesForDelegationSync(String delegationId) {
    return LocalDatabase.values(
      _notesBox,
      (id, data) => SubstituteLessonNote.fromMap(id, data),
    ).where((n) => n.delegationId == delegationId).toList();
  }

  Future<SubstituteLessonNote> addLessonNote({
    required String delegationId,
    required String classId,
    required String classUniqueCode,
    required DateTime date,
    required String note,
  }) async {
    final noteId = LocalDatabase.newId('supp_nota');
    final entry = SubstituteLessonNote(
      noteId: noteId,
      delegationId: delegationId,
      classId: classId,
      classUniqueCode: classUniqueCode,
      date: date.toUtc(),
      note: note.trim(),
      authorName: getCurrentCatechistName(),
    );
    await _notesBox.put(noteId, entry.toMap());
    await _notesBox.flush();
    return entry;
  }

  Future<void> deleteLessonNote(String noteId) async {
    await _notesBox.delete(noteId);
    await _notesBox.flush();
  }

  Future<void> deleteNotesForDelegation(String delegationId) async {
    for (final note in getNotesForDelegationSync(delegationId)) {
      await _notesBox.delete(note.noteId);
    }
    await _notesBox.flush();
  }

  /// Importa una lista di note ricevute dal Supplente durante l'acquisizione
  /// dati (merge deduplicato per noteId).
  Future<int> importLessonNotes(List<Map<String, dynamic>> notes) async {
    var imported = 0;
    for (final raw in notes) {
      final id = raw['noteId']?.toString();
      if (id == null || id.isEmpty) continue;
      if (_notesBox.containsKey(id)) continue;
      final note = SubstituteLessonNote.fromMap(id, _stringifyValues(raw));
      await _notesBox.put(id, note.toMap());
      imported++;
    }
    if (imported > 0) await _notesBox.flush();
    return imported;
  }

  static Map<String, dynamic> _stringifyValues(Map<String, dynamic> raw) {
    final map = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (entry.value is String || entry.value is bool || entry.value is num) {
        map[entry.key] = entry.value;
      } else if (entry.value is Map || entry.value is List) {
        map[entry.key] = jsonDecode(jsonEncode(entry.value));
      }
    }
    return map;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SNAPSHOT CLASSE (dispositivo del Supplente)
  // ─────────────────────────────────────────────────────────────────────────

  /// Crea (o riusa) una classe «ombra» e gli studenti dello snapshot sul
  /// dispositivo del Supplente. La classe NON viene aggiunta a `catechistIds`:
  /// la visibilità resta legata alla delega.
  Future<void> importSubstituteSnapshot(
    SubstituteDelegation delegation,
    List<Map<String, String>> students,
  ) async {
    final classesBox = LocalDatabase.classes();
    if (!classesBox.containsKey(delegation.classId)) {
      final shadowClass = _buildShadowClass(delegation, students);
      await classesBox.put(delegation.classId, shadowClass.toMap());
      await classesBox.flush();
    }

    final studentsBox = LocalDatabase.students();
    final now = DateTime.now().toUtc().toIso8601String();
    for (final s in students) {
      final id = s['id'];
      if (id == null || studentsBox.containsKey(id)) continue;
      await studentsBox.put(
        id,
        _shadowStudentMap(
          delegation,
          id,
          name: s['name'] ?? '',
          surname: s['surname'] ?? '',
          now: now,
        ),
      );
    }
    await studentsBox.flush();

    _storeTempKeyIfAbsent(delegation);
  }

  /// [destroySubstituteData] rimuove classe ombra, studenti snapshot,
  /// chiave temporanea, presenze e note della supplenza sul Supplente.
  Future<void> destroySubstituteData(
    SubstituteDelegation delegation, {
    required List<Map<String, String>> snapshotStudents,
  }) async {
    final classesBox = LocalDatabase.classes();
    final snapshotIds = snapshotStudents
        .map((s) => s['id'])
        .whereType<String>()
        .toSet();

    final rawClass = classesBox.get(delegation.classId);
    if (rawClass != null) {
      final map = LocalDatabase.toStringDynamicMap(rawClass);
      final catechistIds = (map['catechistIds'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
      if (catechistIds.isEmpty) {
        // Classe ombra: eliminazione completa.
        await classesBox.delete(delegation.classId);
      } else {
        // Caso limite (classe già reale per il Supplente): non si tocca la
        // classe, ma si rimuovono gli id snapshot non più appartenenti.
        final studentIds = (map['studentIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        await classesBox.put(delegation.classId, {
          ...map,
          'studentIds': studentIds
              .where((id) => !snapshotIds.contains(id))
              .toList(),
        });
      }
    }

    final studentsBox = LocalDatabase.students();
    for (final id in snapshotIds) {
      final raw = studentsBox.get(id);
      if (raw == null) continue;
      final map = LocalDatabase.toStringDynamicMap(raw);
      if (map['classId']?.toString() == delegation.classId) {
        await studentsBox.delete(id);
      }
    }

    _removeTempKeyIfAbsent(delegation);

    final attendanceBox = LocalDatabase.attendance();
    final attendanceKeys = <dynamic>[];
    for (final key in attendanceBox.keys) {
      final data = LocalDatabase.toStringDynamicMap(attendanceBox.get(key));
      if (data['viaDelegationId']?.toString() == delegation.delegationId) {
        attendanceKeys.add(key);
      }
    }
    for (final key in attendanceKeys) {
      await attendanceBox.delete(key);
    }

    await deleteNotesForDelegation(delegation.delegationId);
    await delete(delegation.delegationId);

    await classesBox.flush();
    await studentsBox.flush();
    await attendanceBox.flush();
  }

  static SchoolClass _buildShadowClass(
    SubstituteDelegation delegation,
    List<Map<String, String>> students,
  ) {
    return SchoolClass(
      id: delegation.classId,
      name: delegation.className,
      studentIds: students.map((s) => s['id']!).toList(),
      catechistIds: const [],
      uniqueCode: delegation.classUniqueCode,
      nameLocked: true,
      creatorId: '',
      creatorName: delegation.ownerName,
      creatorCatechistId: delegation.ownerCatechistId,
      associatedCatechistIds: const [],
      lastModifiedBy: delegation.substituteName,
    );
  }

  static Map<String, dynamic> _shadowStudentMap(
    SubstituteDelegation delegation,
    String id, {
    required String name,
    required String surname,
    required String now,
  }) {
    return {
      'id': id,
      'name': name,
      'surname': surname,
      'classId': delegation.classId,
      'classUniqueCode': delegation.classUniqueCode,
      'birthDate': DateTime.fromMillisecondsSinceEpoch(
        0,
        isUtc: true,
      ).toIso8601String(),
      'motherName': '',
      'motherSurname': '',
      'fatherName': '',
      'fatherSurname': '',
      'motherPhone': '',
      'fatherPhone': '',
      'studentPhone': '',
      'consensoPrivacyFirmato': false,
      'consensoUsciteAutonome': false,
      'contributoVersato': false,
      'contributoEuros': 0,
      'annoContributo': '',
      'statoPercorso': 'ATTIVO',
      'annoIscrizione': '',
      'lastModifiedBy': delegation.substituteName,
      'createdAt': now,
      'updatedAt': now,
    };
  }

  Future<void> _storeTempKeyIfAbsent(SubstituteDelegation delegation) async {
    final keysBox = LocalDatabase.classChannelKeys();
    if (keysBox.containsKey(delegation.classId)) return;
    await keysBox.put(delegation.classId, {
      'classId': delegation.classId,
      'classUniqueCode': delegation.classUniqueCode,
      'className': delegation.className,
      'keyBase64': delegation.temporaryClassKey,
      'keyId': await ClassChannelService.computeKeyId(
        delegation.temporaryClassKey,
      ),
      'grantorCatechistId': delegation.ownerCatechistId,
      'grantedAt': DateTime.now().toUtc().toIso8601String(),
      'isActive': true,
    });
    await keysBox.flush();
  }

  Future<void> _removeTempKeyIfAbsent(SubstituteDelegation delegation) async {
    final keysBox = LocalDatabase.classChannelKeys();
    if (delegation.temporaryClassKey.isEmpty) return;
    final raw = keysBox.get(delegation.classId);
    if (raw == null) return;
    final map = LocalDatabase.toStringDynamicMap(raw);
    if (map['keyBase64']?.toString() == delegation.temporaryClassKey) {
      await keysBox.delete(delegation.classId);
      await keysBox.flush();
    }
  }
}
