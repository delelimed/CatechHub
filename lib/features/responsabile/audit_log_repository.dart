// ══════════════════════════════════════════════════════════════════════════════
// audit_log_repository.dart — CatechHub (registro trattamenti GDPR locale-first)
//
// Modulo "Responsabile Catechistico": repository dell'AuditLog (Registro
// Trattamenti). Le voci sono IMMUTABILI e firmate HMAC. Letture reattive
// tramite [LocalDatabase.watchList]; scrittura append-only. La cancellazione
// delle voci è riservata al Diritto all'Oblio/reset totale.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_service.dart';
import '../../core/services/audit_log_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/audit_action.dart';
import '../../shared/models/audit_log.dart';
import '../../shared/models/user_role.dart';

final auditLogRepositoryProvider = Provider<AuditLogRepository>((ref) {
  return AuditLogRepository();
});

/// Repository append-only del Registro Trattamenti.
class AuditLogRepository {
  final _box = LocalDatabase.auditLog();

  /// Stream reattivo delle voci, ordinate dalla più recente alla più vecchia.
  Stream<List<AuditLog>> getAllLogs() {
    return LocalDatabase.watchList(
      _box,
      (id, data) => AuditLog.fromMap(id, data),
    ).map(_sortNewestFirst);
  }

  /// Lettura sincrona (più recenti prima).
  List<AuditLog> getAllLogsSync() {
    return _sortNewestFirst(
      LocalDatabase.values(_box, (id, data) => AuditLog.fromMap(id, data)),
    );
  }

  /// Stream reattivo filtrato per entità impattata.
  Stream<List<AuditLog>> getLogsForEntity(
    String entityType, {
    String? entityId,
  }) {
    return getAllLogs().map((logs) => logs.where((l) {
          if (l.affectedEntityType != entityType) return false;
          if (entityId != null && l.affectedEntityId != entityId) return false;
          return true;
        }).toList());
  }

  /// Scrive una voce firmata [AuditLog] nel registro. Append-only.
  ///
  /// Il parametro [preserveSignature] consente (per test) di inserire una
  /// voce con firma già calcolata. In produzione la firma viene sempre rigenerata.
  /// Ritorna la voce effettivamente persistita (con firma valorizzata).
  Future<AuditLog> add(AuditLog log, {bool preserveSignature = false}) async {
    final signed =
        preserveSignature ? log : await AuditLogService.sign(log);
    await _box.put(signed.logId, signed.toMap());
    await _box.flush();
    return signed;
  }

  /// Costruisce e scrive una voce di registro in un solo passaggio.
  Future<AuditLog> record({
    required AuditActionType actionType,
    required String affectedEntityId,
    String affectedEntityType = AuditLog.entityRagazzo,
    String? executedByCatechistId,
    String? executedByCatechistName,
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now().toUtc();
    final base = AuditLog(
      logId: generateAuditLogUuidV4(),
      timestamp: now,
      actionType: actionType,
      executedByCatechistId:
          executedByCatechistId ?? _currentOperatorId(),
      executedByCatechistName:
          executedByCatechistName ?? _currentOperatorName(),
      affectedEntityType: affectedEntityType,
      affectedEntityId: affectedEntityId,
    );
    return add(base);
  }

  /// Verifica l'integrità di una singola voce.
  Future<bool> verifyLog(AuditLog log) => AuditLogService.verify(log);

  /// Verifica l'integrità dell'intero registro; ritorna le voci manomesse.
  Future<List<AuditLog>> findTampered() async {
    final tampered = <AuditLog>[];
    for (final log in getAllLogsSync()) {
      if (!await AuditLogService.verify(log)) tampered.add(log);
    }
    return tampered;
  }

  List<AuditLog> _sortNewestFirst(List<AuditLog> logs) {
    final sorted = [...logs];
    sorted.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted;
  }

  String _currentOperatorId() {
    final role = UserRole.current();
    if (role == UserRole.responsabile) {
      try {
        final id = LocalDatabase.auth().get('catechist_id') as String?;
        if (id != null && id.isNotEmpty) return id;
      } catch (_) {}
    }
    try {
      final id = LocalDatabase.auth().get('catechist_id') as String?;
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}
    return AuthService.localUserId;
  }

  String _currentOperatorName() {
    try {
      final name = LocalDatabase.auth().get('local_user_name') as String?;
      if (name != null && name.isNotEmpty) return name;
    } catch (_) {}
    return 'Responsabile Catechistico';
  }
}