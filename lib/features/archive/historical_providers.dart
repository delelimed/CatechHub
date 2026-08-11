// ══════════════════════════════════════════════════════════════════════════════
// historical_providers.dart — CatechHub (provider archivio storico)
//
// Espone gli stream dell'archivio storico applicando le regole di visibilità
// [HistoricalAccessPolicy]:
//   - Responsabile: stream completo di tutti i record.
//   - Catechista: stream filtrato ai SOLI ragazzi attualmente nelle proprie
//     classi. Se un ragazzo esce dalle classi del catechista, i suoi record
//     "scadono" e spariscono dal flusso alla successiva emissione.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/historical_record.dart';
import 'historical_access_policy.dart';
import 'historical_record_repository.dart';

final historicalRecordRepositoryProvider =
    Provider<HistoricalRecordRepository>((ref) {
  return HistoricalRecordRepository();
});

/// Stream dell'archivio storico VISIBILE all'utente corrente (ACL applicata).
final historicalRecordsStreamProvider = StreamProvider((ref) {
  final repo = ref.watch(historicalRecordRepositoryProvider);
  final policy = ref.watch(historicalAccessPolicyProvider);
  return repo.getAllRecords().map(policy.applyVisibility);
});

/// Stream dello storico di un singolo studente, già filtrato per ACL.
final studentHistoryStreamProvider = StreamProvider.autoDispose
    .family<List<HistoricalRecord>, String>((ref, studentId) {
  final repo = ref.watch(historicalRecordRepositoryProvider);
  final policy = ref.watch(historicalAccessPolicyProvider);
  return repo
      .getAllRecords()
      .map((records) => policy.applyVisibility(records))
      .map((visible) =>
          visible.where((r) => r.studentId == studentId).toList());
});

final historicalAccessPolicyProvider = Provider<HistoricalAccessPolicy>((ref) {
  return const HistoricalAccessPolicy();
});
