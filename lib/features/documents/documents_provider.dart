import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/class_scoped_providers.dart';
import '../../shared/models/student_model.dart';
import 'documents_repository.dart';

/// Provider singleton del repository documenti.
/// Espone un'istanza condivisa di [DocumentsRepository] in tutto il progetto.
final documentsRepoProvider = Provider((ref) => DocumentsRepository());

/// Provider che espone in stream gli studenti appartenenti alla classe
/// corrente. Filtra gli studenti tramite [currentClassStudentsProvider],
/// utilizzato per calcolare i "mancanti" nelle statistiche dei documenti.
final myGroupStudentsProvider = StreamProvider.autoDispose<List<Student>>((
  ref,
) {
  return ref.watch(currentClassStudentsProvider.future).asStream();
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
final documentDeliveriesProvider = StreamProvider.family
    .autoDispose<Map<String, dynamic>, String>((ref, docId) {
      return ref.watch(documentsRepoProvider).getDeliveries(docId);
    });
