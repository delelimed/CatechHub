// ============================================================================
// TEST: AuditLogRepository (Registro Trattamenti GDPR)
// Copre: append-only, firma automatica, verifica integrità, filtri per entità.
// ============================================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/services/audit_log_service.dart';
import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/responsabile/audit_log_repository.dart';
import 'package:CatechHub/shared/models/audit_action.dart';
import 'package:CatechHub/shared/models/audit_log.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_audit_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalDatabase.authBox);
    await Hive.openBox<Map>(LocalDatabase.auditLogBox);
    AuditLogService.debugSecretOverride = 'test-secret-fisso';
  });

  tearDown(() async {
    AuditLogService.debugSecretOverride = null;
    await Hive.deleteBoxFromDisk(LocalDatabase.auditLogBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.authBox);
    tempDir.deleteSync(recursive: true);
  });

  group('AuditLogRepository', () {
    test('record scrive una voce firmata e leggibile', () async {
      final repo = AuditLogRepository();
      final log = await repo.record(
        actionType: AuditActionType.grantConsent,
        affectedEntityId: 'ragazzo_1',
        affectedEntityType: AuditLog.entityConsenso,
      );

      expect(log.signature, isNotEmpty);
      expect(await repo.verifyLog(log), isTrue);

      final all = repo.getAllLogsSync();
      expect(all.length, 1);
      expect(all.first.actionType, AuditActionType.grantConsent);
    });

    test('le voci sono ordinate dalla più recente alla più vecchia', () async {
      final repo = AuditLogRepository();
      await repo.record(
        actionType: AuditActionType.createStudent,
        affectedEntityId: 'ragazzo_1',
        affectedEntityType: AuditLog.entityRagazzo,
        timestamp: DateTime.utc(2026, 1, 1),
      );
      await repo.record(
        actionType: AuditActionType.createStudent,
        affectedEntityId: 'ragazzo_2',
        affectedEntityType: AuditLog.entityRagazzo,
        timestamp: DateTime.utc(2026, 2, 1),
      );

      final all = repo.getAllLogsSync();
      expect(all.length, 2);
      expect(all.first.affectedEntityId, 'ragazzo_2');
    });

    test('findTampered rileva una voce manomessa', () async {
      final repo = AuditLogRepository();
      final box = LocalDatabase.auditLog();
      await repo.record(
        actionType: AuditActionType.createStudent,
        affectedEntityId: 'ragazzo_1',
        affectedEntityType: AuditLog.entityRagazzo,
      );

      // Manometti manualmente il record nel box (simula attacco).
      final key = box.keys.first;
      final raw = Map<String, dynamic>.from(box.get(key) as Map);
      raw['affectedEntityId'] = 'ragazzo_MANOMESSO';
      await box.put(key, raw);

      final tampered = await repo.findTampered();
      expect(tampered.length, 1);
      expect(tampered.first.affectedEntityId, 'ragazzo_MANOMESSO');
    });

    test('getLogsForEntity filtra per tipo e id entità', () async {
      final repo = AuditLogRepository();
      await repo.record(
        actionType: AuditActionType.createClass,
        affectedEntityId: 'classe_1',
        affectedEntityType: AuditLog.entityClasse,
      );
      await repo.record(
        actionType: AuditActionType.createStudent,
        affectedEntityId: 'ragazzo_1',
        affectedEntityType: AuditLog.entityRagazzo,
      );

      final ragazzoLogs = repo
          .getAllLogsSync()
          .where((l) => l.affectedEntityType == AuditLog.entityRagazzo)
          .toList();
      expect(ragazzoLogs.length, 1);
      expect(ragazzoLogs.first.affectedEntityId, 'ragazzo_1');
    });
  });
}
