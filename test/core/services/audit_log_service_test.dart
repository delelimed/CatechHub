// ============================================================================
// TEST: AuditLogService (firma/verifica HMAC del Registro Trattamenti)
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/core/services/audit_log_service.dart';
import 'package:CatechHub/shared/models/audit_action.dart';
import 'package:CatechHub/shared/models/audit_log.dart';

AuditLog _makeLog({String signature = ''}) {
  return AuditLog(
    logId: '11111111-2222-4333-8444-555555555555',
    timestamp: DateTime.utc(2026, 8, 7, 10, 30),
    actionType: AuditActionType.grantConsent,
    executedByCatechistId: 'cat_responsabile_1',
    executedByCatechistName: 'Mario Rossi',
    affectedEntityType: AuditLog.entityConsenso,
    affectedEntityId: 'ragazzo_123',
    signature: signature,
  );
}

void main() {
  setUp(() {
    AuditLogService.debugSecretOverride = 'test-secret-fixo';
  });

  tearDown(() {
    AuditLogService.debugSecretOverride = null;
  });

  group('AuditLogService.sign/verify', () {
    test('sign valorizza la signature immutabilmente', () async {
      final original = _makeLog();
      final signed = await AuditLogService.sign(original);

      expect(signed.signature, isNotEmpty);
      expect(original.signature, '', reason: 'originale resta immutabile');
    });

    test('verify ritorna true per un log correttamente firmato', () async {
      final signed = await AuditLogService.sign(_makeLog());
      expect(await AuditLogService.verify(signed), isTrue);
    });

    test('verify ritorna false se la firma è assente', () async {
      expect(await AuditLogService.verify(_makeLog()), isFalse);
    });

    test('verify rileva la manomissione di un campo', () async {
      final signed = await AuditLogService.sign(_makeLog());
      final tampered = signed.copyWith(
        affectedEntityId: 'ragazzo_MANOMESSO',
      );
      expect(await AuditLogService.verify(tampered), isFalse);
    });

    test('verifica stabile: la stessa log firmata due volte verifica', () async {
      final signed1 = await AuditLogService.sign(_makeLog());
      final signed2 = await AuditLogService.sign(
        AuditLog(
          logId: signed1.logId,
          timestamp: signed1.timestamp,
          actionType: signed1.actionType,
          executedByCatechistId: signed1.executedByCatechistId,
          executedByCatechistName: signed1.executedByCatechistName,
          affectedEntityType: signed1.affectedEntityType,
          affectedEntityId: signed1.affectedEntityId,
        ),
      );
      expect(signed1.signature, signed2.signature);
    });

    test('buildPayload è canonico e deterministico', () {
      final payload = AuditLogService.buildPayload(_makeLog());
      expect(payload, contains('GRANT_CONSENT'));
      expect(payload, contains('cat_responsabile_1'));
      expect(payload, contains('ragazzo_123'));
    });
  });
}