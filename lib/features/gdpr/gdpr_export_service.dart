// ══════════════════════════════════════════════════════════════════════════════
// gdpr_export_service.dart — CatechHub (export conformità GDPR + audit CSV)
//
// Modulo "GDPR & Privacy": produce gli artefatti di compliance per il
// Responsabile Catechistico:
//   1. CSV del Registro Trattamenti (con firma HMAC per voce).
//   2. Pacchetto di conservazione parrocchiale (audit + anagrafica + consensi
//      + tombstone + configurazione) cifrato AES-256-GCM con PIN.
//
// Il pacchetto di conservazione VINCOLA il dato eliminato: oltre all'audit,
// vengono inclusi i tombstone del Diritto all'Oblio, così la documentazione
// è coerenza anche dopo una cancellazione definitiva.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import '../../core/services/backup_encryption_service.dart';
import '../responsabile/audit_log_repository.dart';
import '../responsabile/parish_config_repository.dart';
import '../students/students_repository.dart';
import 'tombstone_repository.dart';

/// Servizio di export per la conformità GDPR della parrocchia.
class GdprExportService {
  GdprExportService._();

  /// CSV del Registro Trattamenti (separatore ';' per compatibilità italiana,
  /// BOM UTF-8 per Excel). Include la firma HMAC di ogni voce.
  static String buildAuditLogCsv() {
    final logs = AuditLogRepository().getAllLogsSync();
    final buf = StringBuffer()
      ..write('\ufeff')
      ..writeln(
        'Timestamp;Azione;Operatore;OperatoreId;Entita;EntityId;Firma',
      );
    for (final log in logs) {
      buf.writeln([
        log.timestamp.toUtc().toIso8601String(),
        log.actionType.storageValue,
        log.executedByCatechistName,
        log.executedByCatechistId,
        log.affectedEntityType,
        log.affectedEntityId,
        log.signature,
      ].map(_csvEscape).join(';'));
    }
    return buf.toString();
  }

  /// Pacchetto complessivo di conservazione (JSON non cifrato).
  ///
  /// Include: config parrocchiale, studenti (con campi GDPR), registro,
  /// tombstone (diritto all'oblio) e metadata di esportazione.
  static Map<String, dynamic> buildParishConservationPackage() {
    final students = StudentsRepository().getAllStudentsSync().map((s) =>
        s.toMap()..['id'] = s.id);
    final logs = AuditLogRepository().getAllLogsSync().map((l) =>
        l.toMap()..['logId'] = l.logId);
    final tombstones = TombstoneRepository().getAll().map((t) =>
        t.toMap()..['id'] = t.id);

    return {
      'schema': 'CatechHub.Compliance.v1',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'configParrocchia': ParishConfigRepository().getConfig().toMap(),
      'registroTrattamenti': logs.toList(),
      'schedaSchedaConsensi': students.toList(),
      'tombstones': tombstones.toList(),
    };
  }

  /// Cifra il pacchetto di conservazione con [pin] (AES-256-GCM + PBKDF2).
  static String encryptParishConservationPackage(String pin) {
    return BackupEncryptionService.encryptBackup(
      jsonEncode(buildParishConservationPackage()),
      pin,
    );
  }

  /// Breve riepilogo testuale (art. 30) per stampa/archivio cartaceo.
  static String buildAuditSummaryText() {
    final logs = AuditLogRepository().getAllLogsSync();
    final studentCount = StudentsRepository().getAllStudentsSync().length;
    final tombCount = TombstoneRepository().getAll().length;
    final buf = StringBuffer()
      ..writeln('= Registro Trattamenti — Riepilogo =')
      ..writeln('Generato: ${DateTime.now().toIso8601String()}')
      ..writeln('Ragazzi in anagrafica: $studentCount')
      ..writeln('Voci di registro: ${logs.length}')
      ..writeln('Tombstone (diritto all\'oblio): $tombCount')
      ..writeln('--');
    for (final log in logs) {
      buf.writeln(
        '• ${log.timestamp.toUtc().toIso8601String()} '
        '| ${log.actionType.label} '
        '| ${log.executedByCatechistName} '
        '| ${log.affectedEntityId}',
      );
    }
    return buf.toString();
  }

  static String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    return escaped.contains(';') || escaped.contains('"') || escaped.contains('\n')
        ? '"$escaped"'
        : escaped;
  }
}