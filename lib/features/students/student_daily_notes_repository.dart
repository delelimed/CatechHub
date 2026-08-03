import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/student_daily_note_model.dart';
import '../../shared/utils/auth_utils.dart';

final studentDailyNotesRepoProvider =
    Provider((ref) => StudentDailyNotesRepository());

/// Provider Riverpod singleton (alias) del repository delle note giornaliere.
final studentDailyNotesRepositoryProvider = studentDailyNotesRepoProvider;

/// Repository per le annotazioni giornaliere per studente, archiviate
/// nel Box `studentDailyNotes` di Hive.
/// Modello: [StudentDailyNote]. Espone stream in tempo reale
/// ([getNotesForStudent]) e metodi sincroni per CRUD.
/// Il metodo [deleteAllForStudent] è usato dalla cascade delete
/// di [StudentsRepository] quando un ragazzo viene eliminato.
class StudentDailyNotesRepository {
  final _box = LocalDatabase.studentDailyNotes();

  Stream<List<StudentDailyNote>> getNotesForStudent(String studentId) {
    return LocalDatabase.watchList(
      _box,
      (id, data) => StudentDailyNote.fromMap(id, data),
    ).map((notes) => notes
        .where((n) => n.studentId == studentId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  List<StudentDailyNote> getNotesForStudentSync(String studentId) {
    return LocalDatabase.values(
      _box,
      (id, data) => StudentDailyNote.fromMap(id, data),
    )
        .where((n) => n.studentId == studentId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Stream in tempo reale delle note giornaliere della classe identificata
  /// dal [classUniqueCode], dalla più recente alla più vecchia.
  Stream<List<Map<String, dynamic>>> getNotesByClass(String classUniqueCode) {
    return LocalDatabase.watchList(
      _box,
      (id, data) => {'id': id, ...data},
    ).map((notes) => notes
        .where((n) => n['classUniqueCode'] == classUniqueCode)
        .toList()
      ..sort((a, b) {
        final aDate = DateTime.tryParse(a['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(b['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      }));
  }

  /// Lettura sincrona delle note giornaliere di una classe.
  List<Map<String, dynamic>> getNotesByClassSync(String classUniqueCode) {
    return LocalDatabase.values(
      _box,
      (id, data) => {'id': id, ...data},
    ).where((n) => n['classUniqueCode'] == classUniqueCode).toList()
      ..sort((a, b) {
        final aDate = DateTime.tryParse(a['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(b['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
  }

  Future<void> addNote(StudentDailyNote note) async {
    final id = note.id.isEmpty
        ? LocalDatabase.newId('student_daily_note')
        : note.id;
    final code = note.classUniqueCode ?? _lookupClassUniqueCode(note);
    final data = note.copyWith(classUniqueCode: code).toMap();
    data['lastModifiedBy'] = getCurrentCatechistName();
    await _box.put(id, data);
  }

  Future<void> updateNote(String id, StudentDailyNote note) async {
    final existing = _box.get(id);
    String? existingCode;
    if (existing != null) {
      final map = LocalDatabase.toStringDynamicMap(existing);
      existingCode = map['classUniqueCode'];
    }
    final code = note.classUniqueCode ?? existingCode ?? _lookupClassUniqueCode(note);
    final data = note.copyWith(classUniqueCode: code).toMap();
    data['lastModifiedBy'] = getCurrentCatechistName();
    await _box.put(id, data);
  }

  /// Cerca il classUniqueCode a partire dal meeting o dallo studente.
  String? _lookupClassUniqueCode(StudentDailyNote note) {
    // Prova dal meeting
    final meetingData = LocalDatabase.planning().get(note.meetingId);
    if (meetingData != null) {
      final meetingMap = LocalDatabase.toStringDynamicMap(meetingData);
      final meetingCode = meetingMap['classUniqueCode'] as String?;
      if (meetingCode != null && meetingCode.isNotEmpty) return meetingCode;
      final classId = meetingMap['classId'] as String?;
      if (classId != null && classId.isNotEmpty) {
        final classData = LocalDatabase.classes().get(classId);
        if (classData != null) {
          final classMap = LocalDatabase.toStringDynamicMap(classData);
          final code = classMap['uniqueCode'] as String?;
          if (code != null && code.isNotEmpty) return code;
        }
      }
    }
    // Fallback dallo studente
    final studentData = LocalDatabase.students().get(note.studentId);
    if (studentData == null) return null;
    final studentMap = LocalDatabase.toStringDynamicMap(studentData);
    final classId = studentMap['classId'] as String?;
    if (classId == null || classId.isEmpty) return null;
    final classData = LocalDatabase.classes().get(classId);
    if (classData == null) return null;
    final classMap = LocalDatabase.toStringDynamicMap(classData);
    return classMap['uniqueCode'] as String?;
  }

  Future<void> deleteNote(String id) async {
    await _box.delete(id);
  }

  Future<void> deleteAllForStudent(String studentId) async {
    final notes = getNotesForStudentSync(studentId);
    for (final note in notes) {
      await _box.delete(note.id);
    }
  }
}
