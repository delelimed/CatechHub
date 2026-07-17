import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/student_daily_note_model.dart';
import '../../shared/utils/auth_utils.dart';

final studentDailyNotesRepoProvider =
    Provider((ref) => StudentDailyNotesRepository());

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

  Future<void> addNote(StudentDailyNote note) async {
    final id = note.id.isEmpty
        ? LocalDatabase.newId('student_daily_note')
        : note.id;
    final data = note.toMap();
    data['lastModifiedBy'] = getCurrentCatechistName();
    await _box.put(id, data);
  }

  Future<void> updateNote(String id, StudentDailyNote note) async {
    final data = note.toMap();
    data['lastModifiedBy'] = getCurrentCatechistName();
    await _box.put(id, data);
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
