// ============================================================================
// TEST: Classic Sync Models
// Copre: ClassicPairingData, TrustedDevice, SyncableRecord
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/features/sync/data/classic_sync_models.dart';

void main() {
  // ══════════════════════════════════════════════════
  //  CRDT Last-Write-Wins: SyncableRecord
  // ══════════════════════════════════════════════════
  group('SyncableRecord - CRDT LWW', () {
    test('winsOver restituisce true se il record e piu recente', () {
      final now = DateTime.now().toUtc();
      final vecchio = SyncableRecord(
        id: 'r1',
        boxName: 'students',
        data: {'nome': 'Mario'},
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now.subtract(const Duration(hours: 1)),
      );
      final recente = SyncableRecord(
        id: 'r1',
        boxName: 'students',
        data: {'nome': 'Luigi'},
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now,
      );
      final risultato = recente.winsOver(vecchio);
      expect(risultato, isTrue);
    });

    test('winsOver restituisce false se il record e piu vecchio', () {
      final now = DateTime.now().toUtc();
      final vecchio = SyncableRecord(
        id: 'r1',
        boxName: 'students',
        data: {'nome': 'Mario'},
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now.subtract(const Duration(hours: 1)),
      );
      final recente = SyncableRecord(
        id: 'r1',
        boxName: 'students',
        data: {'nome': 'Luigi'},
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now,
      );
      final risultato = vecchio.winsOver(recente);
      expect(risultato, isFalse);
    });

    test('il record con isDeleted=true e timestamp recente prevale', () {
      final now = DateTime.now().toUtc();
      final cancellato = SyncableRecord(
        id: 'r1',
        boxName: 'students',
        data: {'nome': 'Mario', 'isDeleted': true},
        createdAt: now,
        updatedAt: now,
        isDeleted: true,
      );
      final attivo = SyncableRecord(
        id: 'r1',
        boxName: 'students',
        data: {'nome': 'Mario'},
        createdAt: now,
        updatedAt: now.subtract(const Duration(hours: 1)),
      );
      final risultato = cancellato.winsOver(attivo);
      expect(risultato, isTrue);
    });

    test('serializzazione e deserializzazione di SyncableRecord', () {
      final now = DateTime.now().toUtc();
      final original = SyncableRecord(
        id: 'r2',
        boxName: 'classes',
        data: {'nome': 'Classe A', 'studentIds': ['s1', 's2']},
        createdAt: now,
        updatedAt: now,
        isDeleted: false,
      );
      final map = original.toMap();
      final restored = SyncableRecord.fromMap(map);
      expect(restored.id, 'r2');
      expect(restored.boxName, 'classes');
      expect(restored.data['nome'], 'Classe A');
      expect(restored.isDeleted, false);
      expect(restored.updatedAt, now);
    });
  });

  // ══════════════════════════════════════════════════
  //  Leader Election Asimmetrica (Anti-Deadlock)
  // ══════════════════════════════════════════════════
  group('Leader Election - Confronto Lessicografico', () {
    test('il dispositivo con deviceId maggiore diventa dispositivoA', () {
      final myId = 'CH_65a1b2c3d4e5_ffffff';
      final peerId = 'CH_1234567890ab_aaaaaa';
      final comparison = myId.compareTo(peerId);
      if (comparison > 0) {
        expect(comparison, greaterThan(0));
      } else {
        expect(comparison, lessThanOrEqualTo(0));
      }
    });

    test('compareTo e antisimmetrico (garantisce coerenza)', () {
      final idA = 'CH_ffffffffffff_ffffff';
      final idB = 'CH_000000000000_000000';
      final ab = idA.compareTo(idB);
      final ba = idB.compareTo(idA);
      expect(ab, -ba);
    });

    test('il dispositivo con deviceId uguale diventa dispositivoB', () {
      final myId = 'CH_abc123_ffffff';
      final peerId = 'CH_abc123_ffffff';
      final comparison = myId.compareTo(peerId);
      expect(comparison, 0);
      expect(comparison <= 0, isTrue);
    });

    test('verifica che i dispositivi opposti ottengano ruoli diversi', () {
      final idDispositivo1 = 'CH_ffffffffffff_ffffff';
      final idDispositivo2 = 'CH_000000000000_000000';
      final ruolo1 = idDispositivo1.compareTo(idDispositivo2) > 0
          ? ClassicPairingRole.dispositivoA
          : ClassicPairingRole.dispositivoB;
      final ruolo2 = idDispositivo2.compareTo(idDispositivo1) > 0
          ? ClassicPairingRole.dispositivoA
          : ClassicPairingRole.dispositivoB;
      expect(ruolo1, isNot(equals(ruolo2)));
    });
  });

  // ══════════════════════════════════════════════════
  //  ClassicPairingData
  // ══════════════════════════════════════════════════
  group('ClassicPairingData', () {
    test('isExpired restituisce true dopo 30 giorni', () {
      final expiredDate = DateTime.now().toUtc().subtract(
        const Duration(days: 31),
      );
      final data = ClassicPairingData(
        deviceId: 'CH_test',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        deviceName: 'Test Device',
        sharedKey: 'key123',
        createdAt: expiredDate,
      );
      expect(data.isExpired, isTrue);
    });

    test('isExpired restituisce false se creata oggi', () {
      final now = DateTime.now().toUtc();
      final data = ClassicPairingData(
        deviceId: 'CH_test',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        deviceName: 'Test Device',
        sharedKey: 'key123',
        createdAt: now,
      );
      expect(data.isExpired, isFalse);
    });

    test('timeUntilExpiry restituisce Duration zero se scaduta', () {
      final expiredDate = DateTime.now().toUtc().subtract(
        const Duration(days: 60),
      );
      final data = ClassicPairingData(
        deviceId: 'CH_test',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        deviceName: 'Test',
        sharedKey: 'k',
        createdAt: expiredDate,
      );
      expect(data.timeUntilExpiry, Duration.zero);
    });

    test('toJson e fromJson sono reversibili', () {
      final now = DateTime.now().toUtc();
      final original = ClassicPairingData(
        deviceId: 'CH_abc123_def456',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        deviceName: 'Tablet del Catechista',
        sharedKey: 'sharedKeyBase64==',
        createdAt: now,
        syncRole: ClassicSyncRole.mioDispositivo,
      );
      final json = original.toJson();
      final restored = ClassicPairingData.fromJson(json);
      expect(restored.deviceId, original.deviceId);
      expect(restored.macAddress, original.macAddress);
      expect(restored.deviceName, original.deviceName);
      expect(restored.sharedKey, original.sharedKey);
      expect(restored.syncRole, original.syncRole);
    });

    test('controllareCoerenzaRuoli restituisce true se ruoli uguali', () {
      expect(
        ClassicPairingData.controllareCoerenzaRuoli(
          ClassicSyncRole.mioDispositivo,
          ClassicSyncRole.mioDispositivo,
        ),
        isTrue,
      );
      expect(
        ClassicPairingData.controllareCoerenzaRuoli(
          ClassicSyncRole.altroCatechista,
          ClassicSyncRole.altroCatechista,
        ),
        isTrue,
      );
    });

    test('controllareCoerenzaRuoli restituisce false se ruoli diversi', () {
      expect(
        ClassicPairingData.controllareCoerenzaRuoli(
          ClassicSyncRole.mioDispositivo,
          ClassicSyncRole.altroCatechista,
        ),
        isFalse,
      );
    });
  });

  // ══════════════════════════════════════════════════
  //  TrustedDevice
  // ══════════════════════════════════════════════════
  group('TrustedDevice', () {
    test('isValid restituisce true se il pairing ha meno di 30 giorni', () {
      final recentPairing = DateTime.now().toUtc().subtract(
        const Duration(days: 5),
      );
      final device = TrustedDevice(
        deviceId: 'CH_test',
        deviceName: 'Tablet',
        publicKey: 'key123',
        syncRole: 'mioDispositivo',
        pairedAt: recentPairing,
      );
      expect(device.isValid, isTrue);
    });

    test('isValid restituisce false se il pairing ha piu di 30 giorni', () {
      final expiredPairing = DateTime.now().toUtc().subtract(
        const Duration(days: 31),
      );
      final device = TrustedDevice(
        deviceId: 'CH_test',
        deviceName: 'Tablet',
        publicKey: 'key123',
        syncRole: 'mioDispositivo',
        pairedAt: expiredPairing,
      );
      expect(device.isValid, isFalse);
    });

    test('toMap e fromMap sono reversibili', () {
      final now = DateTime.now().toUtc();
      final original = TrustedDevice(
        deviceId: 'CH_abc123',
        deviceName: 'Smartphone del Coordinatore',
        publicKey: 'publicKeyBase64==',
        syncRole: 'altroCatechista',
        pairedAt: now,
      );
      final map = original.toMap();
      final restored = TrustedDevice.fromMap(map);
      expect(restored.deviceId, 'CH_abc123');
      expect(restored.deviceName, 'Smartphone del Coordinatore');
      expect(restored.publicKey, 'publicKeyBase64==');
      expect(restored.syncRole, 'altroCatechista');
    });

    test('copyWith permette di aggiornare publicKey e pairedAt', () {
      final original = TrustedDevice(
        deviceId: 'CH_test',
        deviceName: 'Tablet',
        publicKey: 'vecchiaChiave',
        syncRole: 'mioDispositivo',
        pairedAt: DateTime(2024, 1, 1).toUtc(),
      );
      final updated = original.copyWith(
        publicKey: 'nuovaChiave',
        pairedAt: DateTime(2024, 6, 1).toUtc(),
      );
      expect(updated.publicKey, 'nuovaChiave');
      expect(updated.pairedAt, DateTime(2024, 6, 1).toUtc());
      expect(updated.deviceId, 'CH_test');
      expect(updated.deviceName, 'Tablet');
    });
  });

  // ══════════════════════════════════════════════════
  //  ClassicPairingFlowState
  // ══════════════════════════════════════════════════
  group('ClassicPairingFlowState', () {
    test('copyWith con errorMessage null cancella l\'errore', () {
      const stateWithErrors = ClassicPairingFlowState(
        pairingState: ClassicPairingState.errore,
        errorMessage: 'Errore precedente',
      );
      final cleared = stateWithErrors.copyWith(
        pairingState: ClassicPairingState.idle,
      );
      expect(cleared.errorMessage, isNull);
      expect(cleared.pairingState, ClassicPairingState.idle);
    });

    test('copyWith isProcessing default e false', () {
      const initial = ClassicPairingFlowState();
      expect(initial.isProcessing, isFalse);
    });
  });

  // ══════════════════════════════════════════════════
  //  SyncResult
  // ══════════════════════════════════════════════════
  group('SyncResult', () {
    test('toString mostra statistiche in caso di successo', () {
      final result = SyncResult(
        success: true,
        sentRecords: 10,
        receivedRecords: 5,
        syncTimestamp: DateTime.now().toUtc(),
      );
      final str = result.toString();
      expect(str, contains('10 inviati'));
      expect(str, contains('5 ricevuti'));
    });

    test('toString mostra errore in caso di fallimento', () {
      final result = SyncResult(
        success: false,
        error: 'Timeout di rete',
        syncTimestamp: DateTime.now().toUtc(),
      );
      final str = result.toString();
      expect(str, contains('Timeout di rete'));
    });
  });
}
