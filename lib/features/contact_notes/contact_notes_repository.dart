import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/contact_note_model.dart';
import '../../shared/utils/auth_utils.dart';

/// Provider Riverpod singleton del repository delle note di contatto.
final contactNotesRepoProvider = Provider((ref) => ContactNotesRepository());

/// Provider Riverpod singleton (alias) del repository delle note di contatto.
final contactNotesRepositoryProvider = contactNotesRepoProvider;

/// Repository CRUD per le [ContactNote] persistenti su Hive.
///
/// In CateREG ogni nota di contatto è legata a uno studente tramite
/// [ContactNote.studentId] e rappresenta un contatto avvenuto in un
/// preciso momento (de visu, WhatsApp, cellulare).
class ContactNotesRepository {
  final _box = LocalDatabase.contactNotes();

  /// Stream in tempo reale delle note di contatto per un dato studente,
  /// ordinate dalla più recente alla più vecchia.
  Stream<List<ContactNote>> getNotesForStudent(String studentId) {
    return LocalDatabase.watchList(
      _box,
      (id, data) => ContactNote.fromMap(id, data),
    ).map(
      (notes) =>
          notes.where((n) => n.studentId == studentId).toList()
            ..sort((a, b) => b.dateTime.compareTo(a.dateTime)),
    );
  }

  /// Lettura sincrona (una tantum) delle note di contatto per uno studente,
  /// utile per snapshot come l'anteprima nella lista principale.
  List<ContactNote> getNotesForStudentSync(String studentId) {
    return LocalDatabase.values(
        _box,
        (id, data) => ContactNote.fromMap(id, data),
      ).where((n) => n.studentId == studentId).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  /// Stream in tempo reale delle note di contatto appartenenti alla classe
  /// identificata dal [classUniqueCode], dalla più recente alla più vecchia.
  Stream<List<Map<String, dynamic>>> getNotesByClass(String classUniqueCode) {
    return LocalDatabase.watchList(_box, (id, data) => {'id': id, ...data}).map(
      (notes) =>
          notes.where((n) => n['classUniqueCode'] == classUniqueCode).toList()
            ..sort((a, b) {
              final aDate =
                  DateTime.tryParse(a['dateTime']?.toString() ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              final bDate =
                  DateTime.tryParse(b['dateTime']?.toString() ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            }),
    );
  }

  /// Lettura sincrona delle note di contatto di una classe.
  List<Map<String, dynamic>> getNotesByClassSync(String classUniqueCode) {
    return LocalDatabase.values(
        _box,
        (id, data) => {'id': id, ...data},
      ).where((n) => n['classUniqueCode'] == classUniqueCode).toList()
      ..sort((a, b) {
        final aDate =
            DateTime.tryParse(a['dateTime']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            DateTime.tryParse(b['dateTime']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
  }

  /// Aggiunge una nuova [ContactNote] al database Hive.
  /// Se l'ID è vuoto, ne genera uno automaticamente.
  Future<void> addNote(ContactNote note) async {
    final id = note.id.isEmpty ? LocalDatabase.newId('contact_note') : note.id;
    final catechistName = getCurrentCatechistName();
    final now = DateTime.now();
    final code =
        note.classUniqueCode ??
        _lookupClassUniqueCodeForStudent(note.studentId);
    final existing = _box.get(id);
    String? existingCreatedAt;
    if (existing != null) {
      final map = LocalDatabase.toStringDynamicMap(existing);
      existingCreatedAt = map['createdAt']?.toString();
    }
    final data = note.toMap();
    data['classUniqueCode'] = code;
    data['lastModifiedBy'] = catechistName;
    data['createdAt'] = existingCreatedAt ?? now.toIso8601String();
    data['updatedAt'] = now.toIso8601String();
    await _box.put(id, data);
  }

  /// Cerca il classUniqueCode a partire dallo studente.
  String? _lookupClassUniqueCodeForStudent(String studentId) {
    final studentData = LocalDatabase.students().get(studentId);
    if (studentData == null) return null;
    final studentMap = LocalDatabase.toStringDynamicMap(studentData);
    final classId = studentMap['classId'] as String?;
    if (classId == null || classId.isEmpty) return null;
    final classData = LocalDatabase.classes().get(classId);
    if (classData == null) return null;
    final classMap = LocalDatabase.toStringDynamicMap(classData);
    return classMap['uniqueCode'] as String?;
  }

  /// Elimina una singola nota di contatto dal database tramite ID.
  Future<void> deleteNote(String id) async {
    await _box.delete(id);
  }

  /// Elimina tutte le note di contatto associate a uno studente.
  /// Utile in caso di eliminazione dello studente dal sistema.
  Future<void> deleteAllForStudent(String studentId) async {
    final notes = getNotesForStudentSync(studentId);
    for (final note in notes) {
      await _box.delete(note.id);
    }
  }
}
