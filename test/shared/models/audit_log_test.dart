// ============================================================================
// TEST: AuditLog + AuditActionType
// Copre: immutabilità, UUIDv4, serializzazione, enum mapping, signature.
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/shared/models/audit_action.dart';
import 'package:CatechHub/shared/models/audit_log.dart';

void main() {
  group('AuditActionType', () {
    test('espone i valori di storage richiesti dallo spec', () {
      expect(AuditActionType.createStudent.storageValue, 'CREATE_STUDENT');
      expect(AuditActionType.updateStudent.storageValue, 'UPDATE_STUDENT');
      expect(
        AuditActionType.deleteStudentHard.storageValue,
        'DELETE_STUDENT_HARD',
      );
      expect(AuditActionType.createClass.storageValue, 'CREATE_CLASS');
      expect(AuditActionType.deleteClass.storageValue, 'DELETE_CLASS');
      expect(
        AuditActionType.reassignCatechist.storageValue,
        'REASSIGN_CATECHIST',
      );
      expect(AuditActionType.grantConsent.storageValue, 'GRANT_CONSENT');
      expect(AuditActionType.revokeConsent.storageValue, 'REVOKE_CONSENT');
      expect(AuditActionType.exportData.storageValue, 'EXPORT_DATA');
      expect(
        AuditActionType.tombstoneReceived.storageValue,
        'TOMBSTONE_RECEIVED',
      );
      expect(AuditActionType.passaggioAnno.storageValue, 'PASSAGGIO_ANNO');
    });

    test('fromStorageValue risolve i valori e ha fallback', () {
      expect(
        AuditActionType.fromStorageValue('GRANT_CONSENT'),
        AuditActionType.grantConsent,
      );
      expect(
        AuditActionType.fromStorageValue('SCONOSCIUTO'),
        AuditActionType.createStudent,
      );
    });

    test('ogni azione ha una etichetta leggibile', () {
      for (final action in AuditActionType.values) {
        expect(action.label, isNotEmpty);
      }
    });
  });

  group('AuditLog entity', () {
    final base = AuditLog(
      logId: '11111111-2222-4333-8444-555555555555',
      timestamp: DateTime.utc(2026, 8, 7, 10, 30),
      actionType: AuditActionType.grantConsent,
      executedByCatechistId: 'cat_responsabile_1',
      executedByCatechistName: 'Mario Rossi',
      affectedEntityType: AuditLog.entityConsenso,
      affectedEntityId: 'student_123',
    );

    test('costruisce correttamente l\'istanza', () {
      expect(base.logId, '11111111-2222-4333-8444-555555555555');
      expect(
        base.timestamp.toIso8601String(),
        DateTime.utc(2026, 8, 7, 10, 30).toIso8601String(),
      );
      expect(base.actionType, AuditActionType.grantConsent);
      expect(base.executedByCatechistId, 'cat_responsabile_1');
      expect(base.affectedEntityType, AuditLog.entityConsenso);
    });

    test('copyWith modifica e preserva immutabilità dell\'originale', () {
      final signed = base.copyWith(signature: 'hmac_abc');
      expect(signed.signature, 'hmac_abc');
      expect(base.signature, '');
    });

    test('toMap/fromMap roundtrip preserva tutti i campi', () {
      final map = base.copyWith(signature: 'firma').toMap();
      map['logId'] = base.logId;
      final restored = AuditLog.fromMap(base.logId, map);
      expect(restored.logId, base.logId);
      expect(restored.actionType, base.actionType);
      expect(restored.executedByCatechistId, base.executedByCatechistId);
      expect(restored.affectedEntityType, base.affectedEntityType);
      expect(restored.affectedEntityId, base.affectedEntityId);
      expect(restored.signature, 'firma');
    });

    test('toMap serializza timestamp come UTC ISO 8601', () {
      final map = base.toMap();
      expect(
        map['timestamp'],
        DateTime.utc(2026, 8, 7, 10, 30).toIso8601String(),
      );
      expect(map['actionType'], 'GRANT_CONSENT');
    });

    test('fromMap gestisce mappa vuota con fallback', () {
      final log = AuditLog.fromMap('some-id', <String, dynamic>{});
      expect(log.logId, 'some-id');
      expect(log.executedByCatechistId, '');
      expect(log.timestamp, isNotNull);
    });
  });

  group('generateAuditLogUuidV4', () {
    test('genera UUID v4 validi e univoci', () {
      final ids = {for (var i = 0; i < 100; i++) generateAuditLogUuidV4()};
      expect(ids.length, 100);
      final sample = ids.first;
      // versione 4 e variante RFC 4122
      expect(sample[14], '4');
      expect('89ab'.contains(sample[19]), isTrue);
    });
  });
}
