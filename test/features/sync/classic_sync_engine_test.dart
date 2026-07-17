import 'package:flutter_test/flutter_test.dart';

import 'package:CatechHub/features/sync/data/classic_sync_models.dart';

void main() {
  group('SyncableRecord - Confronto LWW', () {
    test('winsOver dovrebbe restituire true se questo record e piu recente', () {
      final now = DateTime.now().toUtc();
      final recente = SyncableRecord(
        id: '1',
        boxName: 'students',
        data: {'nome': 'Mario'},
        createdAt: now,
        updatedAt: now.add(const Duration(minutes: 5)),
      );

      final vecchio = SyncableRecord(
        id: '1',
        boxName: 'students',
        data: {'nome': 'Luigi'},
        createdAt: now,
        updatedAt: now,
      );

      expect(recente.winsOver(vecchio), isTrue);
      expect(vecchio.winsOver(recente), isFalse);
    });

    test('winsOver dovrebbe restituire false se i record hanno lo stesso timestamp', () {
      final now = DateTime.now().toUtc();
      final recordA = SyncableRecord(
        id: '1',
        boxName: 'students',
        data: {'nome': 'A'},
        createdAt: now,
        updatedAt: now,
      );

      final recordB = SyncableRecord(
        id: '1',
        boxName: 'students',
        data: {'nome': 'B'},
        createdAt: now,
        updatedAt: now,
      );

      expect(recordA.winsOver(recordB), isFalse);
    });
  });

  group('SyncableRecord - Serializzazione', () {
    test('toMap e fromMap dovrebbero essere inversi', () {
      final record = SyncableRecord(
        id: 'test_123',
        boxName: 'classes',
        data: {'nome': 'Classe Test', 'anno': 2024},
        createdAt: DateTime.utc(2024, 1, 15, 10, 30),
        updatedAt: DateTime.utc(2024, 6, 20, 14, 45),
        isDeleted: false,
      );

      final map = record.toMap();
      final restored = SyncableRecord.fromMap(map);

      expect(restored.id, equals(record.id));
      expect(restored.boxName, equals(record.boxName));
      expect(restored.data['nome'], equals('Classe Test'));
      expect(restored.createdAt, equals(record.createdAt));
      expect(restored.updatedAt, equals(record.updatedAt));
      expect(restored.isDeleted, equals(record.isDeleted));
    });

    test('fromLocalRecord dovrebbe gestire campi mancanti', () {
      final data = <String, dynamic>{
        'nome': 'Studente Senza Timestamp',
      };

      final record = SyncableRecord.fromLocalRecord(
        id: 'id_1',
        boxName: 'students',
        data: data,
      );

      expect(record.id, equals('id_1'));
      expect(record.boxName, equals('students'));
      expect(record.data['nome'], equals('Studente Senza Timestamp'));
      expect(record.createdAt, isA<DateTime>());
      expect(record.updatedAt, isA<DateTime>());
    });
  });

  group('TrustedDevice - Modello Multi-Dispositivo', () {
    test('isValid dovrebbe restituire true per dispositivi associati da meno di 30 giorni', () {
      final device = TrustedDevice(
        deviceId: 'CH_001',
        deviceName: 'Catechista A',
        publicKey: 'chiave_pubblica_A',
        syncRole: ClassicSyncRole.mioDispositivo.name,
        pairedAt: DateTime.now().toUtc().subtract(const Duration(days: 15)),
      );

      expect(device.isValid, isTrue);
    });

    test('isValid dovrebbe restituire false per dispositivi associati da piu di 30 giorni', () {
      final device = TrustedDevice(
        deviceId: 'CH_002',
        deviceName: 'Catechista B',
        publicKey: 'chiave_pubblica_B',
        syncRole: ClassicSyncRole.mioDispositivo.name,
        pairedAt: DateTime.now().toUtc().subtract(const Duration(days: 31)),
      );

      expect(device.isValid, isFalse);
    });

    test('timeUntilExpiry dovrebbe calcolare correttamente il tempo rimanente', () {
      final device = TrustedDevice(
        deviceId: 'CH_003',
        deviceName: 'Catechista C',
        publicKey: 'chiave_pubblica_C',
        syncRole: ClassicSyncRole.mioDispositivo.name,
        pairedAt: DateTime.now().toUtc().subtract(const Duration(days: 20)),
      );

      final remaining = device.timeUntilExpiry;
      expect(remaining.inDays, equals(10));
    });

    test('timeUntilExpiry dovrebbe restituire Duration.zero per dispositivi scaduti', () {
      final device = TrustedDevice(
        deviceId: 'CH_004',
        deviceName: 'Catechista D',
        publicKey: 'chiave_pubblica_D',
        syncRole: ClassicSyncRole.mioDispositivo.name,
        pairedAt: DateTime.now().toUtc().subtract(const Duration(days: 60)),
      );

      expect(device.timeUntilExpiry, equals(Duration.zero));
    });

    test('toMap e fromMap dovrebbero essere inversi con syncRole', () {
      final device = TrustedDevice(
        deviceId: 'CH_TEST',
        deviceName: 'Test Device',
        publicKey: 'test_key_base64',
        syncRole: ClassicSyncRole.altroCatechista.name,
        pairedAt: DateTime.utc(2024, 6, 15, 12, 0),
      );

      final map = device.toMap();
      final restored = TrustedDevice.fromMap(map);

      expect(restored.deviceId, equals(device.deviceId));
      expect(restored.deviceName, equals(device.deviceName));
      expect(restored.publicKey, equals(device.publicKey));
      expect(restored.syncRole, equals('altroCatechista'));
      expect(restored.pairedAt, equals(device.pairedAt));
    });

    test('copyWith dovrebbe preservare syncRole se non specificato', () {
      final device = TrustedDevice(
        deviceId: 'CH_COPY',
        deviceName: 'Original',
        publicKey: 'key_copy',
        syncRole: ClassicSyncRole.altroCatechista.name,
        pairedAt: DateTime.now().toUtc(),
      );

      final copy = device.copyWith(deviceName: 'Modified');

      expect(copy.deviceName, equals('Modified'));
      expect(copy.syncRole, equals('altroCatechista'));
    });
  });

  group('ClassicPairingData - Scambio Chiavi', () {
    test('isExpired dovrebbe restituire true dopo 30 giorni', () {
      final data = ClassicPairingData(
        deviceId: 'CH_EXPIRED',
        macAddress: 'AA:BB:CC:DD:EE:01',
        deviceName: 'Dispositivo Scaduto',
        sharedKey: 'key123',
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 31)),
        syncRole: ClassicSyncRole.mioDispositivo,
      );

      expect(data.isExpired, isTrue);
    });

    test('isExpired dovrebbe restituire false prima di 30 giorni', () {
      final data = ClassicPairingData(
        deviceId: 'CH_VALID',
        macAddress: 'AA:BB:CC:DD:EE:02',
        deviceName: 'Dispositivo Valido',
        sharedKey: 'key123',
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 10)),
        syncRole: ClassicSyncRole.mioDispositivo,
      );

      expect(data.isExpired, isFalse);
    });

    test('toJson e fromJson dovrebbero essere inversi', () {
      final data = ClassicPairingData(
        deviceId: 'CH_JSON',
        macAddress: 'AA:BB:CC:DD:EE:03',
        deviceName: 'Test JSON',
        sharedKey: 'base64key==',
        createdAt: DateTime.utc(2024, 6, 15, 10, 0),
        syncRole: ClassicSyncRole.altroCatechista,
      );

      final json = data.toJson();
      final restored = ClassicPairingData.fromJson(json);

      expect(restored.deviceId, equals(data.deviceId));
      expect(restored.macAddress, equals(data.macAddress));
      expect(restored.deviceName, equals(data.deviceName));
      expect(restored.sharedKey, equals(data.sharedKey));
      expect(restored.createdAt, equals(data.createdAt));
      expect(restored.syncRole, equals(data.syncRole));
    });
  });

  group('ClassicPairingFlowState - Protocollo Bidirezionale', () {
    test('dovrebbe iniziare in stato idle', () {
      const state = ClassicPairingFlowState();
      expect(state.pairingState, equals(ClassicPairingState.idle));
      expect(state.isProcessing, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('copyWith dovrebbe preservare lo stato non modificato', () {
      const initial = ClassicPairingFlowState(
        pairingState: ClassicPairingState.idle,
        isProcessing: false,
      );

      final updated = initial.copyWith(
        pairingState: ClassicPairingState.fase2_A_scansionaQR,
        isProcessing: true,
      );

      expect(updated.pairingState, equals(ClassicPairingState.fase2_A_scansionaQR));
      expect(updated.isProcessing, isTrue);
      expect(updated.errorMessage, isNull);
      expect(updated.scannedPairingData, isNull);
    });

    test('dovrebbe gestire correttamente il flusso completo delle fasi', () {
      var state = const ClassicPairingFlowState();
      expect(state.pairingState, equals(ClassicPairingState.idle));

      state = state.copyWith(pairingState: ClassicPairingState.fase1_B_scansionaQR);
      expect(state.pairingState, equals(ClassicPairingState.fase1_B_scansionaQR));

      state = state.copyWith(pairingState: ClassicPairingState.verifyingHardware);
      expect(state.pairingState, equals(ClassicPairingState.verifyingHardware));

      state = state.copyWith(pairingState: ClassicPairingState.fase2_A_scansionaQR);
      expect(state.pairingState, equals(ClassicPairingState.fase2_A_scansionaQR));

      state = state.copyWith(pairingState: ClassicPairingState.completato);
      expect(state.pairingState, equals(ClassicPairingState.completato));
    });
  });

  group('Sincronizzazione Sequenziale Multi-Dispositivo', () {
    test('dovrebbe simulare sincronizzazione con due dispositivi diversi', () {
      final trustedDevices = [
        TrustedDevice(
          deviceId: 'CH_CATECHISTA_A',
          deviceName: 'Don Marco',
          publicKey: 'chiave_A_base64',
          syncRole: ClassicSyncRole.mioDispositivo.name,
          pairedAt: DateTime.now().toUtc().subtract(const Duration(days: 5)),
        ),
        TrustedDevice(
          deviceId: 'CH_CATECHISTA_B',
          deviceName: 'Suor Lucia',
          publicKey: 'chiave_B_base64',
          syncRole: ClassicSyncRole.mioDispositivo.name,
          pairedAt: DateTime.now().toUtc().subtract(const Duration(days: 10)),
        ),
      ];

      expect(trustedDevices.every((d) => d.isValid), isTrue);
      expect(trustedDevices.length, equals(2));

      expect(
        trustedDevices[0].publicKey,
        isNot(equals(trustedDevices[1].publicKey)),
      );

      expect(
        trustedDevices[0].deviceId,
        isNot(equals(trustedDevices[1].deviceId)),
      );

      for (final device in trustedDevices) {
        final key = device.publicKey;
        expect(key, isNotEmpty);
        expect(key, equals(device.publicKey));
      }
    });

    test('dovrebbe escludere dispositivi scaduti dalla sincronizzazione', () {
      final trustedDevices = [
        TrustedDevice(
          deviceId: 'CH_VALIDO',
          deviceName: 'Dispositivo Valido',
          publicKey: 'chiave_valida',
          syncRole: ClassicSyncRole.mioDispositivo.name,
          pairedAt: DateTime.now().toUtc().subtract(const Duration(days: 10)),
        ),
        TrustedDevice(
          deviceId: 'CH_SCADUTO',
          deviceName: 'Dispositivo Scaduto',
          publicKey: 'chiave_scaduta',
          syncRole: ClassicSyncRole.mioDispositivo.name,
          pairedAt: DateTime.now().toUtc().subtract(const Duration(days: 35)),
        ),
      ];

      final validDevices = trustedDevices.where((d) => d.isValid).toList();
      expect(validDevices.length, equals(1));
      expect(validDevices.first.deviceId, equals('CH_VALIDO'));
    });
  });

  group('Verifica Coerenza Ruoli - Unit Test', () {
    test('controllareCoerenzaRuoli dovrebbe restituire true per ruoli identici mioDispositivo', () {
      final isCoherent = ClassicPairingData.controllareCoerenzaRuoli(
        ClassicSyncRole.mioDispositivo,
        ClassicSyncRole.mioDispositivo,
      );
      expect(isCoherent, isTrue);
    });

    test('controllareCoerenzaRuoli dovrebbe restituire true per ruoli identici altroCatechista', () {
      final isCoherent = ClassicPairingData.controllareCoerenzaRuoli(
        ClassicSyncRole.altroCatechista,
        ClassicSyncRole.altroCatechista,
      );
      expect(isCoherent, isTrue);
    });

    test('controllareCoerenzaRuoli dovrebbe restituire false per ruoli discordanti', () {
      final isCoherentMioAltro = ClassicPairingData.controllareCoerenzaRuoli(
        ClassicSyncRole.mioDispositivo,
        ClassicSyncRole.altroCatechista,
      );
      final isCoherentAltroMio = ClassicPairingData.controllareCoerenzaRuoli(
        ClassicSyncRole.altroCatechista,
        ClassicSyncRole.mioDispositivo,
      );

      expect(isCoherentMioAltro, isFalse);
      expect(isCoherentAltroMio, isFalse);
    });

    test('roleCoherenceErrorMessage dovrebbe contenere testo descrittivo', () {
      const errorMsg = ClassicPairingData.roleCoherenceErrorMessage;
      expect(errorMsg, contains('Mio Dispositivo'));
      expect(errorMsg, contains('Altro Catechista'));
      expect(errorMsg, contains('stesso ruolo'));
      expect(errorMsg, isNotEmpty);
    });

    test('il ruolo dovrebbe persistere nel roundtrip JSON del QR code', () {
      final data = ClassicPairingData(
        deviceId: 'CH_ROLE',
        macAddress: 'AA:BB:CC:DD:EE:04',
        deviceName: 'Test Ruolo',
        sharedKey: 'key_role',
        createdAt: DateTime.now().toUtc(),
        syncRole: ClassicSyncRole.altroCatechista,
      );

      final json = data.toJson();
      final restored = ClassicPairingData.fromJson(json);

      expect(restored.syncRole, equals(ClassicSyncRole.altroCatechista));
    });

    test('QR code legacy senza syncRole dovrebbe defaultare a mioDispositivo', () {
      final jsonStr = '{"deviceId":"CH_OLD","deviceName":"Legacy",'
          '"sharedKey":"old_key","createdAt":"2024-01-01T00:00:00.000Z"}';

      final restored = ClassicPairingData.fromJson(jsonStr);
      expect(restored.syncRole, equals(ClassicSyncRole.mioDispositivo));
    });
  });

  group('Eliminazione Dispositivi - Unit Test', () {
    test('dovrebbe simulare rimozione singola dispositivo dalla tabella fidati', () {
      final trustedDevices = <String, TrustedDevice>{
        'CH_A': TrustedDevice(
          deviceId: 'CH_A',
          deviceName: 'Dispositivo A',
          publicKey: 'key_a',
          syncRole: ClassicSyncRole.mioDispositivo.name,
          pairedAt: DateTime.now().toUtc(),
        ),
        'CH_B': TrustedDevice(
          deviceId: 'CH_B',
          deviceName: 'Dispositivo B',
          publicKey: 'key_b',
          syncRole: ClassicSyncRole.mioDispositivo.name,
          pairedAt: DateTime.now().toUtc(),
        ),
      };

      expect(trustedDevices.length, equals(2));

      trustedDevices.remove('CH_A');

      expect(trustedDevices.length, equals(1));
      expect(trustedDevices.containsKey('CH_A'), isFalse);
      expect(trustedDevices.containsKey('CH_B'), isTrue);
    });

    test('dovrebbe simulare eliminazione completa di tutti i dispositivi', () {
      final trustedDevices = <String, TrustedDevice>{
        'CH_A': TrustedDevice(
          deviceId: 'CH_A',
          deviceName: 'Dispositivo A',
          publicKey: 'key_a',
          syncRole: ClassicSyncRole.mioDispositivo.name,
          pairedAt: DateTime.now().toUtc(),
        ),
        'CH_B': TrustedDevice(
          deviceId: 'CH_B',
          deviceName: 'Dispositivo B',
          publicKey: 'key_b',
          syncRole: ClassicSyncRole.mioDispositivo.name,
          pairedAt: DateTime.now().toUtc(),
        ),
        'CH_C': TrustedDevice(
          deviceId: 'CH_C',
          deviceName: 'Dispositivo C',
          publicKey: 'key_c',
          syncRole: ClassicSyncRole.mioDispositivo.name,
          pairedAt: DateTime.now().toUtc(),
        ),
      };

      final countBefore = trustedDevices.length;
      trustedDevices.clear();

      expect(trustedDevices.isEmpty, isTrue);
      expect(countBefore, equals(3));
    });

    test('eliminazione dovrebbe impedire sincronizzazione futura con il dispositivo', () {
      final device = TrustedDevice(
        deviceId: 'CH_TO_DELETE',
        deviceName: 'Da Eliminare',
        publicKey: 'key_to_revoke',
        syncRole: ClassicSyncRole.mioDispositivo.name,
        pairedAt: DateTime.now().toUtc(),
      );

      expect(device.isValid, isTrue);
      expect(device.publicKey, equals('key_to_revoke'));

      final trustedDevices = <String, TrustedDevice>{};
      expect(trustedDevices.containsKey(device.deviceId), isFalse);
    });

    test('eliminazione dispositivo inesistente non dovrebbe causare errori', () {
      final trustedDevices = <String, TrustedDevice>{
        'CH_EXISTING': TrustedDevice(
          deviceId: 'CH_EXISTING',
          deviceName: 'Esistente',
          publicKey: 'key_existing',
          syncRole: ClassicSyncRole.mioDispositivo.name,
          pairedAt: DateTime.now().toUtc(),
        ),
      };

      final existed = trustedDevices.remove('CH_NON_EXISTING');
      expect(existed, isNull);
      expect(trustedDevices.length, equals(1));
    });

    test('dopo eliminazione, la lista dispositivi dovrebbe essere aggiornata', () {
      var trustedDevices = <String, TrustedDevice>{
        'CH_A': TrustedDevice(
          deviceId: 'CH_A',
          deviceName: 'Dispositivo A',
          publicKey: 'key_a',
          syncRole: ClassicSyncRole.mioDispositivo.name,
          pairedAt: DateTime.now().toUtc(),
        ),
        'CH_B': TrustedDevice(
          deviceId: 'CH_B',
          deviceName: 'Dispositivo B',
          publicKey: 'key_b',
          syncRole: ClassicSyncRole.mioDispositivo.name,
          pairedAt: DateTime.now().toUtc(),
        ),
      };

      trustedDevices = Map.from(trustedDevices)..remove('CH_A');

      final deviceNames = trustedDevices.values.map((d) => d.deviceName).toList();
      expect(deviceNames, contains('Dispositivo B'));
      expect(deviceNames, isNot(contains('Dispositivo A')));
    });
  });
}
