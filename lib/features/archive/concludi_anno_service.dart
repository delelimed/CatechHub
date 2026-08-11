// ══════════════════════════════════════════════════════════════════════════════
// concludi_anno_service.dart — CatechHub (chiusura anno catechistico e archivio)
//
// Implementa la funzione "Concludi Anno Catechistico", RISERVATA al
// Responsabile Catechistico:
//
//   1. Trasforma ogni classe attiva in un insieme di [HistoricalRecord]
//      IMMUTABILI (uno per ragazzo), fotografando per l'anno corrente:
//      - classe e catechista di riferimento
//      - sacramenti ricevuti (dal profilo dello studente)
//      - percentuale di presenza (calcolata dai record di presenza)
//      - riepilogo delle valutazioni (dalle note dello studente)
//
//   2. Prepara il database per le nuove iscrizioni dell'anno successivo:
//      riusa [PassaggioAnnoService.passaAnno] per promuovere le classi al
//      livello successivo dello stesso percorso, aggiornare l'anno
//      catechistico corrente e archiviare i ragazzi FERMI/RITIRATI.
//
//   3. Registra l'operazione nel Registro Trattamenti GDPR.
//
// Oltre alla chiusura massiva, espone le operazioni SINGOLE di fine anno:
//   - [promuoviStudente]: promuove un ragazzo all'anno successivo.
//   - [archiviaStudente]: archivia un ragazzo ad anno concluso.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/audit_action.dart';
import '../../shared/models/audit_log.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/historical_record.dart';
import '../../shared/models/parish_config.dart';
import '../../shared/models/student_model.dart';
import '../../shared/models/user_role.dart';
import '../classes/classes_repository.dart';
import '../responsabile/audit_log_repository.dart';
import '../responsabile/passaggio_anno_service.dart';
import '../students/students_repository.dart';
import 'historical_record_repository.dart';

/// Esito della chiusura anno catechistico massiva.
class ConcludiAnnoResult {
  /// Snapshot immutabili creati per l'anno appena concluso.
  final List<HistoricalRecord> records;

  /// Risultati della promozione delle classi all'anno successivo.
  final List<PassaggioClasseResult> promozioni;

  /// Anno di destinazione (nuovo anno catechistico corrente).
  final String nuovoAnno;

  const ConcludiAnnoResult({
    required this.records,
    required this.promozioni,
    required this.nuovoAnno,
  });
}

/// Servizio della chiusura anno catechistico e dell'archivio storico.
class ConcludiAnnoService {
  /// Stato percorso di un ragazzo archiviato ad anno concluso.
  static const statoArchiviato = 'ARCHIVIATO';

  final HistoricalRecordRepository _historyRepo =
      HistoricalRecordRepository();
  final ClassesRepository _classesRepo = ClassesRepository();
  final StudentsRepository _studentsRepo = StudentsRepository();
  final AuditLogRepository _auditRepo = AuditLogRepository();

  /// Verifica che l'operazione sia eseguita dal Responsabile Catechistico.
  void _requireResponsabile() {
    if (!RolePermissions.currentCan(RolePermission.manageParishConfig)) {
      throw UnsupportedError('Solo il Responsabile Catechistico può '
          'concludere l\'anno catechistico.');
    }
  }

  /// Calcola la percentuale di presenza (0–100) di [studentId] nella classe
  /// [classId], incrociando i record di presenza del box `attendance`.
  double _attendancePercentage(String classId, String studentId) {
    var presenze = 0;
    var assenze = 0;
    final attendanceBox = LocalDatabase.attendance();
    for (final key in attendanceBox.keys) {
      final data = LocalDatabase.toStringDynamicMap(attendanceBox.get(key));
      if (data['classId']?.toString() != classId) continue;
      final presence = Map<String, dynamic>.from(data['presence'] as Map? ?? {});
      final stato = presence[studentId]?.toString();
      if (stato == 'Presente') {
        presenze++;
      } else if (stato == 'Assente') {
        assenze++;
      }
    }
    final total = presenze + assenze;
    if (total == 0) return 0;
    return (presenze / total * 100).clamp(0, 100).toDouble();
  }

  /// Identifica il catechista titolare della classe da inserire nello
  /// snapshot: priorità al ruolo TITOLARE, altrimenti primo catechista.
  String _leadCatechistId(SchoolClass cls) {
    if (cls.catechistRoles.isNotEmpty) {
      final titolare = cls.catechistRoles.entries
          .firstWhere(
            (e) => e.value == ClassesRepository.roleTitolare,
            orElse: () => cls.catechistRoles.entries.first,
          )
          .key;
      if (titolare.isNotEmpty) return titolare;
    }
    if (cls.catechistIds.isNotEmpty) return cls.catechistIds.first;
    return '';
  }

  /// Costruisce lo snapshot storico di [student] per l'anno [academicYear]
  /// nella classe [cls]. Non scrive nulla: solo costruzione del record.
  HistoricalRecord _buildSnapshot(
    Student student,
    SchoolClass cls,
    String academicYear,
  ) {
    return HistoricalRecord(
      recordId: '',
      studentId: student.id,
      academicYear: academicYear,
      classId: cls.id,
      className: cls.name,
      catechistId: _leadCatechistId(cls),
      sacramentsReceived: student.sacraments,
      attendancePercentage: _attendancePercentage(cls.id, student.id),
      evaluationsSummary: student.notes?.trim().isEmpty == true
          ? ''
          : (student.notes?.trim() ?? ''),
    );
  }

  /// True se esiste già uno snapshot per lo studente nell'anno/classi dati.
  bool _hasSnapshot(String studentId, String academicYear, String classId) {
    final existing = _historyRepo.getAllRecordsSync().where(
          (r) =>
              r.studentId == studentId &&
              r.academicYear == academicYear &&
              (classId.isEmpty || r.classId == classId),
        );
    return existing.isNotEmpty;
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// CHIUSURA ANNO MASSIVA ("Concludi Anno Catechistico")
  /// ═══════════════════════════════════════════════════════════════════════
  ///
  /// 1. Snapshotta tutte le classi attive in record storici immutabili.
  /// 2. Prepara il database per le nuove iscrizioni promuovendo le classi
  ///    all'anno successivo (PassaggioAnnoService).
  ///
  /// Parametri:
  ///  - [soloPercorsi]: limita la chiusura a specifici percorsi (vuoto = tutti).
  ///  - [archiviaRitirati]: come in passaAnno, rimuove FERMI/RITIRATI.
  ///  - [nuovoAnno]: anno di destinazione; default = successivo di quello
  ///    configurato in ParishConfig.
  ///  - [testNow]: data iniettabile nei test.
  Future<ConcludiAnnoResult> concludiAnno({
    List<String>? soloPercorsi,
    bool archiviaRitirati = true,
    String? nuovoAnno,
    DateTime? testNow,
  }) async {
    _requireResponsabile();

    final config = _currentConfig();
    final annoCorrente = config.annoCatechisticoCorrente.trim();
    if (annoCorrente.isEmpty) {
      throw StateError('Configura prima l\'anno catechistico corrente.');
    }
    final targetAnno =
        nuovoAnno ?? PassaggioAnnoService.annoSuccessivo(annoCorrente);

    final allClasses = _classesRepo.getClassesSync();
    final candidates = allClasses.where((c) {
      if (c.archived) return false;
      if (soloPercorsi != null && soloPercorsi.isNotEmpty) {
        return soloPercorsi.contains(c.percorso);
      }
      return true;
    });

    // STEP 1 — Snapshot immutabili dell'anno corrente.
    final records = <HistoricalRecord>[];
    for (final cls in candidates) {
      final studenti = _studentsRepo.getStudentsByClassSync(cls.id);
      for (final student in studenti) {
        // Idempotenza: evita duplicati se la chiusura viene rieseguita.
        if (_hasSnapshot(student.id, annoCorrente, cls.id)) continue;
        records.add(_buildSnapshot(student, cls, annoCorrente));
      }
    }
    if (records.isNotEmpty) {
      await _historyRepo.addMany(records);
    }

    // STEP 2 — Prepara il database per le nuove iscrizioni (promozione).
    final promozioni = await PassaggioAnnoService().passaAnno(
      soloPercorsi: soloPercorsi,
      archiviaRitirati: archiviaRitirati,
      nuovoAnno: targetAnno,
      testNow: testNow,
    );

    // STEP 3 — Registro Trattamenti GDPR.
    await _log(AuditActionType.concludiAnno, 'anno:$annoCorrente',
        AuditLog.entityClasse);

    return ConcludiAnnoResult(
      records: records,
      promozioni: promozioni,
      nuovoAnno: targetAnno,
    );
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// PROMOZIONE SINGOLA DI FINE ANNO
  /// ═══════════════════════════════════════════════════════════════════════
  ///
  /// Archivia il ragazzo per l'anno corrente (snapshot) e lo promuove
  /// all'anno successivo, aggiornando l'anno di iscrizione e, se indicata,
  /// spostandolo nella classe di destinazione.
  Future<HistoricalRecord> promuoviStudente(
    Student student,
    SchoolClass cls, {
    String? targetClassId,
    String? nuovoAnno,
    DateTime? testNow,
  }) async {
    _requireResponsabile();
    final config = _currentConfig();
    final annoCorrente = config.annoCatechisticoCorrente.trim();
    final targetAnno =
        nuovoAnno ?? PassaggioAnnoService.annoSuccessivo(annoCorrente);

    final record = _buildSnapshot(student, cls, annoCorrente);
    if (!_hasSnapshot(student.id, annoCorrente, cls.id)) {
      await _historyRepo.addRecord(record);
    }

    await _studentsRepo.setAnnoIscrizione(student.id, targetAnno);

    if (targetClassId != null && targetClassId.isNotEmpty) {
      final target = _classesRepo
          .getClassesSync()
          .where((c) => c.id == targetClassId)
          .firstOrNull;
      if (target != null && target.id != cls.id) {
        await _classesRepo.removeStudentFromClass(cls.id, student.id);
        await _studentsRepo.updateStudent(
          student.id,
          student.copyWith(
            classId: target.id,
            classUniqueCode: target.uniqueCode,
            annoIscrizione: targetAnno,
          ),
        );
        await _classesRepo.addStudentToClass(target.id, student.id);
      }
    }

    await _log(AuditActionType.promuoviStudente, student.id,
        AuditLog.entityRagazzo);
    return record;
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// ARCHIVIAZIONE SINGOLA DI FINE ANNO
  /// ═══════════════════════════════════════════════════════════════════════
  ///
  /// Archivia il ragazzo ad anno catechistico concluso: crea lo snapshot
  /// storico per l'anno corrente, imposta lo stato [statoArchiviato] e lo
  /// rimuove dalla classe attiva (il ragazzo resta in anagrafica).
  Future<HistoricalRecord> archiviaStudente(
    Student student,
    SchoolClass cls, {
    DateTime? testNow,
  }) async {
    _requireResponsabile();
    final config = _currentConfig();
    final annoCorrente = config.annoCatechisticoCorrente.trim();

    final record = _buildSnapshot(student, cls, annoCorrente);
    if (!_hasSnapshot(student.id, annoCorrente, cls.id)) {
      await _historyRepo.addRecord(record);
    }

    await _studentsRepo.setStatoPercorso(student.id, statoArchiviato);
    await _studentsRepo.removeFromClass(student.id, cls.id);

    await _log(AuditActionType.archiviaStudente, student.id,
        AuditLog.entityRagazzo);
    return record;
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

  Future<void> _log(
    AuditActionType action,
    String entityId,
    String entityType,
  ) async {
    try {
      await _auditRepo.record(
        actionType: action,
        affectedEntityId: entityId,
        affectedEntityType: entityType,
      );
    } catch (e) {
      debugPrint('[ConcludiAnnoService] AuditLog non registrato ($action): $e');
    }
  }
}
