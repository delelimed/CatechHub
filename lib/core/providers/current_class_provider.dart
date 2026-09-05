import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/classes/classes_provider.dart';
import '../../shared/models/class_model.dart';
import '../auth/auth_service.dart';
import '../storage/local_database.dart';

/// Notifier per gestire la classe attualmente selezionata dall'utente.
///
/// Questa classe è il punto centrale per lo scope per-classe di tutti i dati
/// dell'app: studenti, incontri, documenti, presenze, catechesi, ecc.
/// Quando l'utente cambia classe, tutti i provider che dipendono da questo
/// si aggiornano automaticamente.
class CurrentClassNotifier extends Notifier<String?> {
  @override
  String? build() {
    final box = LocalDatabase.auth();
    final saved = box.get('current_class_id') as String?;
    return (saved != null && saved.isNotEmpty) ? saved : null;
  }

  /// Imposta la classe corrente e la salva in Hive per persistenza.
  Future<void> setClass(String? classId) async {
    if (classId == state) return;
    state = classId;
    final box = LocalDatabase.auth();
    if (classId != null) {
      await box.put('current_class_id', classId);
    } else {
      await box.delete('current_class_id');
    }
  }

  /// Carica la classe salvata all'avvio dell'app (già gestita in [build]).
  Future<void> loadSavedClass() async {
    final box = LocalDatabase.auth();
    final saved = box.get('current_class_id') as String?;
    if (saved != null && saved.isNotEmpty && saved != state) {
      state = saved;
    }
  }

  /// Resetta la classe corrente (es. logout).
  Future<void> clear() async {
    state = null;
    final box = LocalDatabase.auth();
    await box.delete('current_class_id');
  }
}

final currentClassProvider = NotifierProvider<CurrentClassNotifier, String?>(
  CurrentClassNotifier.new,
);

/// Se la classe appena eliminata era quella attualmente aperta, deseleziona la
/// classe corrente (pulisce anche `current_class_id` nel box auth).
///
/// Da chiamare DOPO aver eliminato la classe, così modifica/cancellazione
/// restano sempre coerenti con la classe effettivamente aperta.
Future<void> clearCurrentClassIfDeleted(
  WidgetRef ref,
  String deletedClassId,
) async {
  if (ref.read(currentClassProvider) == deletedClassId) {
    await ref.read(currentClassProvider.notifier).clear();
  }
}

/// Provider che restituisce la SchoolClass corrente completa (non solo l'ID).
final currentClassDetailsProvider = Provider<SchoolClass?>((ref) {
  final classId = ref.watch(currentClassProvider);
  if (classId == null) return null;
  final classesAsync = ref.watch(classesStreamProvider);
  return classesAsync.when(
    data: (classes) => classes.firstWhere(
      (c) => c.id == classId,
      orElse: () =>
          SchoolClass(id: '', name: '', studentIds: [], catechistIds: []),
    ),
    loading: () => null,
    error: (_, _) => null,
  );
});

/// Provider che restituisce l'elenco delle classi a cui appartiene l'utente corrente.
final myClassesProvider = Provider<List<SchoolClass>>((ref) {
  const uid = AuthService.localUserId;
  final classesAsync = ref.watch(classesStreamProvider);
  return classesAsync.when(
    data: (classes) =>
        classes.where((c) => c.catechistIds.contains(uid)).toList(),
    loading: () => [],
    error: (_, _) => [],
  );
});
