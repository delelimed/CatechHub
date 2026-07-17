import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'students_repository.dart';

/// Riverpod [Provider] per [StudentsRepository]: fornisce l'istanza
/// del repository che opera sul Box `students` di Hive.
/// Usato dalle pagine del feature students per accesso CRUD centralizzato.
/// Dipende solo dal costruttore (nessuna dipendenza esterna).
final studentsRepoProvider =
    Provider<StudentsRepository>((ref) {
  return StudentsRepository();
});