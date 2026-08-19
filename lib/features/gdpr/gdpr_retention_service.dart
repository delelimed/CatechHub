// ═════════════════════════════════════════════════════════════════════════════
// gdpr_retention_service.dart — CatechHub (enforcement GDPR retention period)
//
// Modulo "GDPR & Privacy": job periodico che FA RISPETTARE il termine di
// conservazione dei dati di un minore (dataScadenzaTrattamento).
//
// REGOLE:
//   - All'avvio dell'app e una volta al giorno, scandisce gli studenti.
//   - Per ogni studente con trattamento SCADUTO (consenso firmato ma scadenza
//     superata) e non più "ATTIVO":
//       • registra nel Registro Trattamenti una voce immutabile e firmata
//         [AuditActionType.retentionTreatmentExpired] (una sola volta per
//         scadenza, evita rumore nel registro);
//       • marca il ragazzo come "RITIRATO": il percorso non è più attivo e i
//         suoi dati non vengono più trattati in modo operativo.
//       • DOPO UN PERIODO DI GRACE (default 30 giorni): cancella automaticamente
//         i dati operativi dello studente, mantenendo tombstone e registro per
//         conformità storage limitation (Art. 5 GDPR).
//   - Gli allegati del minore (foto, PDF, note) vengono rimossi dal vault
//     cifrato durante la pulizia automatica.
//   - La cancellazione fisica definitiva è sempre disponibile tramite
//     Diritto all'Oblio esplicito (DataDeletionService.deleteAllAndReset / hard
//     delete), per casi in cui il Responsabile debba conservare documentazione
//     per motivi contabili.
//
// GARANZA CONFORMITÀ GDPR:
//   - Termine di conservazione rispettato: dati rimossi dopo grace period
//   - Distinzione chiara tra marcatura e cancellazione esplicita
//   - Tracciabilità completa tramite registro immutabile
//
// ESEMPIO FLUSSO:
//   1. Consenso scaduto per studente X (dataScadenzaTrattamento = 2024-01-15)
//   2. GdprRetentionService -> stato → RITIRATO, markedAt = oggi
//   3. Per 30 giorni: dati di studentX operativi ma marcati RITIRATO
//   4. Dopo 30 giorni: pulizia automatica dati operativi studentX
//   5. Tombstone e registro rimangono invariati
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/audit_action.dart';
import '../../shared/models/audit_log.dart';
import '../../shared/models/student_model.dart';
import '../students/students_repository.dart';

/// Servizio di enforcement del periodo di conservazione GDPR.
class GdprRetentionService {
  GdprRetentionService._();

  /// Chiave del box auth che memorizza l'ultima esecuzione del job (UTC ISO).
  static const _lastRunKey = 'gdpr_retention_last_run';

  /// Chiave del box auth che traccia per ogni studente la scadenza già
  /// registrata nel Registro Trattamenti (evita voci duplicate) e la data
  //  in cui lo studente è stato marcato RITIRATO.
  static const _processedKey = 'gdpr_retention_processed_v1';

  /// Periodo di grace in giorni prima della pulizia automatica dati.
  /// Dopo questo periodo, i dati operativi dello studente marcato RITIRATO
  //  vengono cancellati automaticamente per rispettare Art. 5 GDPR (storage
  //  limitation), mantenendo tombstone e registro per tracciabilità.
  static const int _retentionGracePeriodDays = 30;

  static Timer? _dailyTimer;

  /// Avvia il controllo di ritenzione: esegue subito un passaggio e poi
  /// pianifica un passaggio giornaliero. Idempotente.
  static void start() {
    if (_dailyTimer != null) return;
    unawaited(enforce());
    _dailyTimer = Timer.periodic(
      const Duration(hours: 24),
      (_) => unawaited(enforce()),
    );
  }

  /// Ferma il timer giornaliero (usato nei test / shutdown).
  static void stop() {
    _dailyTimer?.cancel();
    _dailyTimer = null;
  }

  /// Esegue un passaggio di enforcement. Un errore interno non deve mai
  /// bloccare l'avvio dell'app: tutto è racchiuso in try-catch.
  static Future<void> enforce() async {
    try {
      await _enforceOnce();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GdprRetention] Passaggio fallito (non fatale): $e');
      }
    }
  }

  static Future<void> _enforceOnce() async {
    final auth = LocalDatabase.auth();
    final now = DateTime.now();

    // Evita di ripetere il passaggio nello stesso giorno.
    final lastRun = DateTime.tryParse(auth.get(_lastRunKey)?.toString() ?? '');
    if (lastRun != null &&
        lastRun.year == now.year &&
        lastRun.month == now.month &&
        lastRun.day == now.day) {
      return;
    }

    final repository = StudentsRepository();
    final students = await repository.getAllStudentsSync();

    // Carica lo stato processato: mappa studentId -> {expirationKey, markedAt}
    Map<String, Map<String, dynamic>> processed = {};
    final raw = auth.get(_processedKey);
    if (raw is Map) {
      // Migrazione compatibile: potrebbe essere una mappa semplice di stringhe
      // (vecchio formato). Convertiamo se necessario.
      if (raw.isNotEmpty) {
        final firstValue = raw.values.first;
        if (firstValue is! Map) {
          // Vecchio formato: mappa studentId -> expirationKey (string)
          // Convertiamo nel nuovo formato aggiungendo markedAt = null
          for (final entry in raw.entries) {
            processed[entry.key] = {
              'expirationKey': entry.value.toString(),
              'markedAt': null,
            };
          }
        } else {
          processed = Map<String, Map<String, dynamic>>.from(raw);
        }
      }
    }

    bool changed = false;
    for (final student in students) {
      final scadenza = student.dataScadenzaTrattamento;
      final studentData = processed[student.id];

      // Solo trattamenti firmati e scaduti.
      if (!student.consensoPrivacyFirmato || scadenza == null) continue;
      if (!scadenza.isBefore(now)) continue;

      final scadenzaKey = scadenza.toUtc().toIso8601String();

      // Se già processato per questa scadenza con lo stesso marker, controlla
      // cleanup grace period e salta.
      if (studentData != null) {
        final existingMarkedAt = studentData['markedAt'] as String?;
        final existingExpirationKey = studentData['expirationKey'] as String?;
        if (existingExpirationKey == scadenzaKey) {
          // Già processato per questa scadenza: controlla cleanup grace period
          _checkRetentionCleanup(student, now, existingMarkedAt);
          continue;
        }
      }

      // Nuova marcatura: registra la scadenza e la data di marcatura.
      // Se markedAt è null, questa è una nuova marcatura.
      final markedAt =
          studentData?['markedAt'] as String? ?? now.toUtc().toIso8601String();
      processed[student.id] = {
        'expirationKey': scadenzaKey,
        'markedAt': markedAt,
      };
      changed = true;

      // Marca il percorso come non più attivo (il trattamento è terminato).
      if (student.statoPercorso == 'ATTIVO' ||
          student.statoPercorso == 'FERMO') {
        await repository.setStatoPercorso(student.id, 'RITIRATO');
      }

      await _recordExpiry(student, scadenzaKey);
    }

    // Esegue la pulizia automatica dei dati scaduti per grace period.
    // Viene chiamata dopo aver processato tutte le marcature.
    await _performRetentionCleanup(processed, now);

    if (changed) {
      await auth.put(_processedKey, processed);
    }
    await auth.put(_lastRunKey, now.toUtc().toIso8601String());
  }

  /// Controlla se uno studente marcato RITIRATO deve essere sottoposto a
  /// pulizia automatica dei dati in base al grace period.
  static void _checkRetentionCleanup(
    Student student,
    DateTime now,
    String? markedAt,
  ) {
    if (markedAt == null) return;

    final markedDate = DateTime.tryParse(markedAt);
    if (markedDate == null) return;

    final daysSinceMarked = now.difference(markedDate).inDays;
    if (daysSinceMarked > _retentionGracePeriodDays) {
      // Grace period scaduto: esegui cleanup singolo studente
      _performSingleStudentCleanup(student.id);
    }
  }

  /// Esegue la pulizia automatica dei dati per un singolo studente i cui
  //  dati sono stati marcati RITIRATO oltre il grace period.
  /// Questo metodo NON cancella il tombstone o il registro trattamenti,
  //  ma rimuove i dati operativi dello studente dal database locale.
  static Future<void> _performSingleStudentCleanup(String studentId) async {
    try {
      // M7 / Fase 3 — item 8: CASCATA DI CANCELLAZIONE REALE. In passato qui
      // veniva eseguito un semplice `box.delete(studentId)`, lasciando sul
      // dispositivo gli allegati cifrati, le note giornaliere, i record
      // storici e le presenze del minore. Ora si usa la stessa cascata della
      // cancellazione manuale, che rimuove:
      //   - allegati (file vault + metadati), con wipe sicuro dei file;
      //   - note giornaliere e note di contatto;
      //   - record storici (archivio);
      //   - lo studente dalle classi (studentIds);
      //   - presenze/consegne documenti;
      //   - il record studente stesso.
      // Il tombstone e il registro trattamenti restano per la compliance
      // storage limitation.
      await StudentsRepository().deleteStudent(studentId);
      debugPrint(
        '[GdprRetention] Cleanup automatico dati completato per studente: $studentId '
        '(grace period scaduto, cascata allegati/note/storici/presenze)',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[GdprRetention] Errore cleanup automatico studente $studentId: $e',
        );
      }
    }
  }

  /// Esegue la pulizia automatica per tutti gli studenti i cui grace period
  //  è scaduto nell'arco dell'esecuzione corrente.
  static Future<void> _performRetentionCleanup(
    final Map<String, Map<String, dynamic>> processed,
    final DateTime now,
  ) async {
    for (final entry in processed.entries) {
      final studentId = entry.key;
      final studentData = entry.value;
      final markedAt = studentData['markedAt'] as String?;
      if (markedAt == null) continue;

      final markedDate = DateTime.tryParse(markedAt);
      if (markedDate == null) continue;

      final daysSinceMarked = now.difference(markedDate).inDays;
      if (daysSinceMarked > _retentionGracePeriodDays) {
        await _performSingleStudentCleanup(studentId);
      }
    }
  }

  /// Registra nel Registro Trattamenti una voce di ritenzione scaduta per uno studente.
  static Future<void> _recordExpiry(
    Student student,
    String expirationKey,
  ) async {
    final logId = generateAuditLogUuidV4();
    final now = DateTime.now().toUtc();
    final executedByCatechistId = _currentOperatorId();
    final executedByCatechistName = _currentOperatorName();
    final auditLog = AuditLog(
      logId: logId,
      timestamp: now,
      actionType: AuditActionType.retentionTreatmentExpired,
      executedByCatechistId: executedByCatechistId,
      executedByCatechistName: executedByCatechistName,
      affectedEntityType: AuditLog.entityRagazzo,
      affectedEntityId: student.id,
    );
    final box = LocalDatabase.auditLog();
    await box.put(auditLog.logId, auditLog.toMap());
    await box.flush();
  }

  static String _currentOperatorId() {
    try {
      final id = LocalDatabase.auth().get('catechist_id') as String?;
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}
    try {
      final id = LocalDatabase.auth().get('local_user_id') as String?;
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}
    return '';
  }

  static String _currentOperatorName() {
    try {
      final name = LocalDatabase.auth().get('local_user_name') as String?;
      if (name != null && name.isNotEmpty) return name;
    } catch (_) {}
    return 'Responsabile Catechistico';
  }
}
