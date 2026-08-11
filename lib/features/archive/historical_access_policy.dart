// ══════════════════════════════════════════════════════════════════════════════
// historical_access_policy.dart — CatechHub (regole di visibilità dell'archivio)
//
// Applica le regole di visibilità/ACL dell'archivio storico in base al ruolo:
//
//   RESPONSABILE CATECHISTICO (Full Access):
//     Vede lo storico COMPLETO di tutti i ragazzi della parrocchia e di tutti
//     gli anni trascorsi. Nessun filtro applicato.
//
//   CATECHISTA (Restricted Access):
//     Vede lo storico degli anni precedenti SOLO dei ragazzi ATTUALMENTE
//     assegnati alle proprie classi (catechistIds contiene localUserId).
//     Se il ragazzo NON è più in una classe del catechista, i dati locali
//     "scadono": i suoi record spariscono dalla vista. La scadenza non è un
//     job temporizzato ma una condizione valutata a ogni lettura: appena lo
//     studente lascia le classi del catechista, i record non sono più
//     restituiti (rimozione immediata dalla vista).
//
// Il catechista NON accede mai all'archivio degli studenti altrui: anche se
// i record giacciono nel box locale, la lettura è filtrata da questa policy.
// ══════════════════════════════════════════════════════════════════════════════

import '../../core/auth/auth_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/historical_record.dart';
import '../../shared/models/user_role.dart';

class HistoricalAccessPolicy {
  const HistoricalAccessPolicy();

  /// True se l'utente corrente è il Responsabile (accesso pieno).
  bool get isFullAccess => UserRole.isResponsabile;

  /// ID usato per identificare la presenza del catechista locale nelle classi
  /// (coerente con il resto dell'app: [AuthService.localUserId]).
  String get _localUserId => AuthService.localUserId;

  /// ID degli studenti attualmente assegnati alle classi del catechista
  /// locale. Vuoto per il Responsabile (accesso non filtrato).
  ///
  /// Questo è il cuore della "scadenza dati": l'insieme è ricalcolato a ogni
  /// lettura partendo dallo stato corrente delle classi, quindi appena uno
  /// studente esce dalle classi del catechista sparisce dall'insieme.
  Set<String> visibleStudentIdsForCatechist() {
    final ids = <String>{};
    final classesBox = LocalDatabase.classes();
    for (final key in classesBox.keys) {
      final data = LocalDatabase.toStringDynamicMap(classesBox.get(key));
      final catechistIds = (data['catechistIds'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
      if (!catechistIds.contains(_localUserId)) continue;
      ids.addAll(
        (data['studentIds'] as List? ?? []).map((e) => e.toString()),
      );
    }
    return ids;
  }

  /// True se il record è visibile all'utente corrente.
  ///
  /// - Responsabile: sempre visibile.
  /// - Catechista: visibile solo se lo studente è attualmente in una sua classe.
  bool canViewRecord(HistoricalRecord record) {
    if (isFullAccess) return true;
    return visibleStudentIdsForCatechist().contains(record.studentId);
  }

  /// Filtra una lista di record applicando le regole di visibilità del
  /// ruolo corrente.
  List<HistoricalRecord> applyVisibility(List<HistoricalRecord> records) {
    if (isFullAccess) return records;
    final allowed = visibleStudentIdsForCatechist();
    return records.where((r) => allowed.contains(r.studentId)).toList();
  }

  /// Legge le classi attive (non archiviate) per risolvere nomi/percorsi.
  List<SchoolClass> activeClassesSync() {
    return LocalDatabase.values(
      LocalDatabase.classes(),
      (id, data) => SchoolClass.fromMap(id, data),
    ).where((c) => !c.archived).toList();
  }
}
