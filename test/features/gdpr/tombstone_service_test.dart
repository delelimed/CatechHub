// ============================================================================
// TEST: TombstoneService — firma e verifica dei tombstone (Diritto all'Oblio)
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/features/gdpr/tombstone_service.dart';

void main() {
  group('TombstoneService.canonical', () {
    test('produce un payload stabile e deterministico', () {
      const ts = {
        'entityType': 'RAGAZZO',
        'entityId': 'local_123',
        'deletedAt': '2026-08-08T10:00:00.000Z',
        'executedBy': 'Anna Responsabile',
        'executedByCatechistId': 'cat_abc',
      };
      final c1 = TombstoneService.canonical(ts);
      final c2 = TombstoneService.canonical({...ts});
      expect(c1, c2);
      expect(c1, contains('RAGAZZO'));
      expect(c1, contains('local_123'));
    });
  });

  group('TombstoneService sign/verify', () {
    test('firma e verifica con lo stesso segreto condiviso', () {
      const secret = 'shared_secret_ecdH_base64value';
      final base = {
        'entityType': 'RAGAZZO',
        'entityId': 'local_456',
        'deletedAt': '2026-08-08T10:00:00.000Z',
        'executedBy': 'Anna',
        'executedByCatechistId': 'cat_y',
        'signerDeviceId': 'device-a',
      };
      final signed = TombstoneService.withSignature(base, secret);
      expect(signed['signature'], isA<String>());
      expect(TombstoneService.verify(signed, secret), isTrue);
    });

    test('verifica fallisce con secret diverso', () {
      const secret = 'segredo-A';
      const wrong = 'segredo-B';
      final base = {
        'entityType': 'RAGAZZO',
        'entityId': 'local_789',
        'deletedAt': '2026-08-08T10:00:00.000Z',
        'executedBy': 'Anna',
        'executedByCatechistId': 'cat_z',
      };
      final signed = TombstoneService.withSignature(base, secret);
      expect(TombstoneService.verify(signed, wrong), isFalse);
    });

    test('verifica fallisce se la firma e mancante o vuota', () {
      const secret = 'secret';
      final ts = {
        'entityType': 'RAGAZZO',
        'entityId': 'local_1',
        'deletedAt': '2026-08-08T10:00:00.000Z',
        'executedBy': '',
        'executedByCatechistId': '',
      };
      expect(TombstoneService.verify(ts, secret), isFalse);
    });

    test('verifica fallisce se il payload viene manomesso', () {
      const secret = 'secret';
      final base = {
        'entityType': 'RAGAZZO',
        'entityId': 'local_2',
        'deletedAt': '2026-08-08T10:00:00.000Z',
        'executedBy': 'Anna',
        'executedByCatechistId': 'cat_a',
      };
      final signed = TombstoneService.withSignature(base, secret);
      final tampered = {...signed, 'entityId': 'local_2_fake'};
      expect(TombstoneService.verify(tampered, secret), isFalse);
    });
  });
}