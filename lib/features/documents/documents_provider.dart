import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_service.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/student_model.dart';
import '../classes/classes_provider.dart';
import '../students/students_provider.dart';
import 'documents_repository.dart';

/// Provider singleton del repository documenti.
/// Espone un'istanza condivisa di [DocumentsRepository] in tutto il progetto.
final documentsRepoProvider = Provider((ref) => DocumentsRepository());

/// Provider che espone in stream gli studenti appartenenti alla classe
/// del catechista corrente. Risolve la classe di cui il catechista fa parte
/// tramite [classesStreamProvider], poi filtra gli studenti da [studentsRepoProvider]
/// restituendo solo quelli associati a tale classe. Viene utilizzato per
/// calcolare i "mancanti" nelle statistiche dei documenti.
final myGroupStudentsProvider = StreamProvider.autoDispose<List<Student>>((ref) {
  final classesAsync = ref.watch(classesStreamProvider);
  final studentsRepo = ref.watch(studentsRepoProvider);

  return classesAsync.when(
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
    data: (classes) {
      final myClass = classes.firstWhere(
        (c) => c.catechistIds.contains(AuthService.localUserId),
        orElse: () => SchoolClass(
          id: '',
          name: '',
          studentIds: [],
          catechistIds: [],
        ),
      );

      if (myClass.id.isEmpty || myClass.studentIds.isEmpty) {
        return Stream.value([]);
      }

      return studentsRepo.getAllStudents().map((allStudents) {
        return allStudents
            .where((s) => myClass.studentIds.contains(s.id))
            .toList();
      });
    },
  );
});

/// Provider che espone in stream la lista completa dei documenti presenti
/// nel box Hive `documents`. I documenti vengono ordinati per data di
/// creazione decrescente (dal più recente al più vecchio).
final documentsStreamProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(documentsRepoProvider).getDocuments();
});

/// Provider parametrizzato per [docId] che espone in stream la mappa delle
/// consegne (deliveries) per un dato documento. La mappa ha come chiave lo
/// studentId e come valore un oggetto con givenOutAt e/o receivedAt.
/// Si aggiorna automaticamente allo scadere di ogni modifica su Hive.
final documentDeliveriesProvider =
    StreamProvider.family.autoDispose<Map<String, dynamic>, String>((ref, docId) {
  return ref.watch(documentsRepoProvider).getDeliveries(docId);
});
