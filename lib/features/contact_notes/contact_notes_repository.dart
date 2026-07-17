import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/contact_note_model.dart';
import '../../shared/utils/auth_utils.dart';

/// Provider Riverpod singleton del repository delle note di contatto.
final contactNotesRepoProvider = Provider((ref) => ContactNotesRepository());

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
    ).map((notes) => notes
        .where((n) => n.studentId == studentId)
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime)));
  }

  /// Lettura sincrona (una tantum) delle note di contatto per uno studente,
  /// utile per snapshot come l'anteprima nella lista principale.
  List<ContactNote> getNotesForStudentSync(String studentId) {
    return LocalDatabase.values(
      _box,
      (id, data) => ContactNote.fromMap(id, data),
    )
        .where((n) => n.studentId == studentId)
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  /// Aggiunge una nuova [ContactNote] al database Hive.
  /// Se l'ID è vuoto, ne genera uno automaticamente.
  Future<void> addNote(ContactNote note) async {
    final id = note.id.isEmpty ? LocalDatabase.newId('contact_note') : note.id;
    final data = note.toMap();
    data['lastModifiedBy'] = getCurrentCatechistName();
    await _box.put(id, data);
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
