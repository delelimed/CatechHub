// ══════════════════════════════════════════════════════════════════════════════
// passaggio_anno_service.dart — CatechHub (workflow annuale promozione)
//
// Responsabilità: chiude l'anno catechistico e promuove in blocco le classi al
// livello successivo dello stesso percorso, gestendo ragazzi fermi o ritirati
// e registrando ogni promozione nel Registro Trattamenti (PASSAGGIO_ANNO).
// ══════════════════════════════════════════════════════════════════════════════

import '../../shared/models/audit_action.dart';
import '../../shared/models/audit_log.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/parish_config.dart';
import '../../core/storage/local_database.dart';
import '../classes/classes_repository.dart';
import '../students/students_repository.dart';
import './audit_log_repository.dart';

/// Esito del passaggio di anno per una singola classe.
class PassaggioClasseResult {
  final SchoolClass source;
  final SchoolClass promoted;
  final int promossi;
  final int ritirati;

  const PassaggioClasseResult({
    required this.source,
    required this.promoted,
    required this.promossi,
    required this.ritirati,
  });
}

/// Servizio del workflow annuale di promozione delle classi.
class PassaggioAnnoService {
  /// Calcola l'anno catechistico successivo ("2026-2027" → "2027-2028").
  static String annoSuccessivo(String anno) {
    final parts = anno.trim().split('-');
    if (parts.length != 2) return anno;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return anno;
    return '$a-${b + 1}';
  }

  /// Promuove in blocco le classi attive al livello successivo.
  ///
  /// Parametri:
  ///  - [soloPercorsi]: limiti la promozione a specifici percorsi (vuoto = tutti).
  ///  - [archiviaRitirati]: se true, gli studenti con stato RITIRATO o FERMO
  ///    vengono rimossi dalla classe attiva (lo studente resta in anagrafica).
  ///  - [nuovoAnno]: anno di destinazione; default = successivo dell'anno configurato.
  ///  - [testTime]: data iniettabile nei test.
  ///
  /// L'anno catechistico corrente nella ParishConfig viene aggiornato
  /// automaticamente a fine passaggio.
  Future<List<PassaggioClasseResult>> passaAnno({
    List<String>? soloPercorsi,
    bool archiviaRitirati = true,
    String? nuovoAnno,
    DateTime? testNow,
  }) async {
    final classesRepo = ClassesRepository();
    final studentiRepo = StudentsRepository();
    final auditRepo = AuditLogRepository();

    final allClasses = classesRepo.getClassesSync();
    final config = _currentConfig();
    final targetAnno = nuovoAnno ?? annoSuccessivo(config.annoCatechisticoCorrente);
    if (targetAnno.isEmpty || config.annoCatechisticoCorrente.trim().isEmpty) {
      throw StateError('Configura prima l\'anno catechistico corrente.');
    }

    final now = (testNow ?? DateTime.now()).toUtc();
    final results = <PassaggioClasseResult>[];

    final candidates = allClasses.where((c) {
      if (c.archived) return false;
      if (soloPercorsi != null && soloPercorsi.isNotEmpty) {
        return soloPercorsi.contains(c.percorso);
      }
      return true;
    });

    for (final cls in candidates) {
      final studenti = studentiRepo.getStudentsByClassSync(cls.id);
      var ritirati = 0;
      var promossi = 0;

      // Promuovi la classe al livello successivo e cambia anno.
      final promossa = cls.copyWith(
        livello: cls.livello + 1,
        annoCatechistico: targetAnno,
        updatedAt: now,
      );

      if (archiviaRitirati) {
        for (final s in studenti) {
          final isFuori =
              (s.statoPercorso == 'RITIRATO' || s.statoPercorso == 'FERMO');
          if (isFuori) {
            await studentiRepo.removeFromClass(s.id, cls.id);
            ritirati++;
          } else {
            promossi++;
            await studentiRepo.setAnnoIscrizione(s.id, targetAnno);
          }
        }
      } else {
        promossi = studenti.where((s) => s.statoPercorso == 'ATTIVO').length;
        ritirati = studenti.length - promossi;
        for (final s in studenti) {
          await studentiRepo.setAnnoIscrizione(s.id, targetAnno);
        }
      }

      await classesRepo.updateClass(cls.id, promossa);
      await auditRepo.record(
        actionType: AuditActionType.passaggioAnno,
        affectedEntityId: cls.id,
        affectedEntityType: AuditLog.entityClasse,
        timestamp: now,
      );

      results.add(PassaggioClasseResult(
        source: cls,
        promoted: promossa,
        promossi: promossi,
        ritirati: ritirati,
      ));
    }

    // Aggiorna l'anno catechistico corrente nella configurazione locale.
    await _salvaAnno(targetAnno);

    return results;
  }

  ParishConfig _currentConfig() {
    try {
      final raw = LocalDatabase.parishConfig().get(ParishConfig.storageKey);
      if (raw == null) return ParishConfig.empty;
      return ParishConfig.fromMap(LocalDatabase.toStringDynamicMap(raw));
    } catch (_) {
      return ParishConfig.empty;
    }
  }

  Future<void> _salvaAnno(String anno) async {
    final updated = _currentConfig().copyWith(annoCatechisticoCorrente: anno);
    await LocalDatabase.parishConfig().put(ParishConfig.storageKey, updated.toMap());
    await LocalDatabase.parishConfig().flush();
  }
}