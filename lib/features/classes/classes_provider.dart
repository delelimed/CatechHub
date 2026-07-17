/// Provider Riverpod per CateREG — esposizione del repository classi e del
/// suo stream reattivo.
///
/// - [classesRepoProvider]: provider singleton di [ClassesRepository] per
///   operazioni CRUD sulle classi.
/// - [classesStreamProvider]: stream provider che espone un
///   `Stream<List<SchoolClass>>` a cui i widget possono agganciarsi con
///   `ref.watch()` per ricevere aggiornamenti in tempo reale.
///
/// Questi provider sono il punto di accesso principale per tutte le pagine
/// del feature `classes` (e pagine esterne) che necessitano di dati sulle
/// classi.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'classes_repository.dart';

final classesRepoProvider =
    Provider((ref) => ClassesRepository());

final classesStreamProvider = StreamProvider((ref) {
  final repo = ref.watch(classesRepoProvider);
  return repo.getClasses();
});