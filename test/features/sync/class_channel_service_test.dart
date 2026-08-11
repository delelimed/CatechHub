// ============================================================================
// TEST: ClassChannelService — chiavi per-classe e cifratura del Canale Classe
// ============================================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/services/qr_data_service.dart';
import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/sync/class_channel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_class_channel_');
    Hive.init(tempDir.path);
    await Hive.openBox<Map>(LocalDatabase.classChannelKeysBox);
    await Hive.openBox<Map>(LocalDatabase.classChannelCiphertextBox);
    ClassChannelService.debugSeedOverride = 'test-class-channel-seed';
  });

  tearDown(() async {
    ClassChannelService.debugSeedOverride = null;
    await Hive.deleteBoxFromDisk(LocalDatabase.classChannelKeysBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.classChannelCiphertextBox);
    tempDir.deleteSync(recursive: true);
  });

  const classId = 'class_1';
  const classCode = '1234567890123456789012345678901234567890';
  const className = 'Comunione A';

  List<Map<String, dynamic>> sampleRecords() => [
        {
          'id': 'STU_1',
          'box': 'students',
          'data': {'name': 'Mario', 'classId': classId, 'classUniqueCode': classCode},
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
          'isDeleted': false,
        },
        {
          'id': 'ATT_1',
          'box': 'attendance',
          'data': {'present': true, 'classId': classId},
          'createdAt': '2026-01-02T00:00:00.000Z',
          'updatedAt': '2026-01-02T00:00:00.000Z',
          'isDeleted': false,
        },
      ];

  group('ClassChannelService — titolo e chiavi', () {
    test('getOrCreateKey crea una chiave e concede il titolo', () {
      expect(ClassChannelService.hasTitle(classCode), isFalse);

      final key = ClassChannelService.getOrCreateKey(
        classId: classId,
        classUniqueCode: classCode,
        className: className,
      );

      expect(key, isNotNull);
      expect(key.keyBase64, isNotEmpty);
      expect(key.keyId, hasLength(16));
      expect(ClassChannelService.hasTitle(classCode), isTrue);
      expect(ClassChannelService.getKeyByClassId(classId)?.classId, classId);
      expect(
        ClassChannelService.getKeyByUniqueCode(classCode)?.keyId,
        key.keyId,
      );
    });

    test('getOrCreateKey è idempotente (restituisce la stessa chiave)', () {
      final k1 = ClassChannelService.getOrCreateKey(
        classId: classId,
        classUniqueCode: classCode,
        className: className,
      );
      final k2 = ClassChannelService.getOrCreateKey(
        classId: classId,
        classUniqueCode: classCode,
        className: className,
      );
      expect(k1.keyId, k2.keyId);
      expect(k1.keyBase64, k2.keyBase64);
    });

    test('revokeTitle revoca il titolo locale', () {
      ClassChannelService.getOrCreateKey(
        classId: classId,
        classUniqueCode: classCode,
        className: className,
      );
      ClassChannelService.revokeTitle(classId);
      expect(ClassChannelService.hasTitle(classCode), isFalse);
      expect(ClassChannelService.getKeyByClassId(classId), isNull);
    });

    test('storeKey importa una chiave ricevuta', () {
      final imported = ClassChannelService.storeKey(
        classId: classId,
        classUniqueCode: classCode,
        className: className,
        keyBase64: ClassChannelService.generateKeyBase64(),
      );
      expect(imported, isNotNull);
      expect(ClassChannelService.hasTitle(classCode), isTrue);
    });
  });

  group('ClassChannelService — cifratura/decifratura', () {
    test('encryptRecords → decryptRecords è reversibile', () {
      ClassChannelService.getOrCreateKey(
        classId: classId,
        classUniqueCode: classCode,
        className: className,
      );
      final records = sampleRecords();

      final blob = ClassChannelService.encryptRecords(classCode, records);

      expect(blob, isNotNull);
      expect(blob!['v'], 1);
      expect(blob['keyId'], isNotEmpty);
      expect(blob['sealed'], isNotEmpty);

      final decrypted = ClassChannelService.decryptRecords(classCode, blob);
      expect(decrypted, isNotNull);
      expect(decrypted!.length, records.length);
      expect(decrypted[0]['id'], 'STU_1');
      expect(decrypted[1]['id'], 'ATT_1');
    });

    test('il blob NON contiene il testo in chiaro (nessuna leak)', () {
      ClassChannelService.getOrCreateKey(
        classId: classId,
        classUniqueCode: classCode,
        className: className,
      );
      final records = [
        {'nome': 'Giuseppe', 'note': 'allergia alle arachidi', 'id': 'x'},
      ];
      final blob = ClassChannelService.encryptRecords(classCode, records)!;

      final serialized = blob.toString();
      expect(serialized, isNot(contains('Giuseppe')));
      expect(serialized, isNot(contains('arachidi')));
    });

    test('decryptRecords senza titolo restituisce null (relay-only)', () {
      ClassChannelService.getOrCreateKey(
        classId: classId,
        classUniqueCode: classCode,
        className: className,
      );
      final blob = ClassChannelService.encryptRecords(
        classCode,
        sampleRecords(),
      )!;

      // Un dispositivo "senza titolo" non possiede la chiave.
      ClassChannelService.revokeTitle(classId);
      expect(ClassChannelService.decryptRecords(classCode, blob), isNull);
    });

    test('decryptRecords con chiave diversa restituisce null', () {
      ClassChannelService.getOrCreateKey(
        classId: classId,
        classUniqueCode: classCode,
        className: className,
      );
      final blob = ClassChannelService.encryptRecords(
        classCode,
        sampleRecords(),
      )!;

      // Rotazione della chiave: il vecchio blob non è più decifrabile.
      ClassChannelService.rotateKey(
        classId: classId,
        classUniqueCode: classCode,
        className: className,
      );
      expect(ClassChannelService.decryptRecords(classCode, blob), isNull);
    });

    test('encryptRecords con records vuoti restituisce null', () {
      ClassChannelService.getOrCreateKey(
        classId: classId,
        classUniqueCode: classCode,
        className: className,
      );
      expect(ClassChannelService.encryptRecords(classCode, []), isNull);
    });
  });

  group('ClassChannelService — relay dei blob cifrati', () {
    test('store/take round-trip conserva il blob senza titolo', () {
      ClassChannelService.getOrCreateKey(
        classId: classId,
        classUniqueCode: classCode,
        className: className,
      );
      final blob = ClassChannelService.encryptRecords(
        classCode,
        sampleRecords(),
      )!;

      ClassChannelService.storeRelayedCiphertext(classCode, blob);
      final taken = ClassChannelService.takeRelayedCiphertext(classCode);
      expect(taken, isNotNull);
      expect(taken!['sealed'], blob['sealed']);
    });

    test('il blob relayed è decifrabile dopo l\'acquisizione del titolo', () {
      final blob = ClassChannelService.encryptRecords(
        classCode,
        sampleRecords(),
      );
      // Il relay NON ha la chiave: il blob resta opaco.
      expect(blob, isNull);

      // Simulazione: altro dispositivo con titolo crea il blob.
      ClassChannelService.getOrCreateKey(
        classId: classId,
        classUniqueCode: classCode,
        className: className,
      );
      final realBlob = ClassChannelService.encryptRecords(
        classCode,
        sampleRecords(),
      )!;
      ClassChannelService.storeRelayedCiphertext(classCode, realBlob);
      expect(ClassChannelService.decryptRecords(classCode, realBlob), isNotNull);
    });
  });

  group('ClassChannelService — QR handshake del titolo', () {
    test('crea un grant QR e lo importa con il PIN corretto', () {
      final key = ClassChannelService.getOrCreateKey(
        classId: classId,
        classUniqueCode: classCode,
        className: className,
      );
      final pin = QRDataService.generatePin();
      final grantMap = ClassChannelService.buildGrantMap(
        key: key,
        grantorName: 'Don Mario',
      );
      expect(grantMap['type'], 'class_key_grant');
      expect(grantMap['keyId'], key.keyId);

      final chunks = ClassChannelService.createKeyGrantChunks(grantMap, pin);
      expect(chunks, isNotEmpty);

      // Ricostruzione lato ricevente (senza titolo).
      ClassChannelService.revokeTitle(classId);
      final assembled = QRDataService.assembleChunks(
        chunks.map(QRChunk.fromMap).toList(),
      );
      final imported = ClassChannelService.importKeyGrant(assembled, pin);

      expect(imported, isNotNull);
      expect(imported!.classUniqueCode, classCode);
      expect(imported.keyId, key.keyId);
      expect(ClassChannelService.hasTitle(classCode), isTrue);
    });

    test('PIN errato non importa il titolo', () {
      final key = ClassChannelService.getOrCreateKey(
        classId: classId,
        classUniqueCode: classCode,
        className: className,
      );
      final pin = QRDataService.generatePin();
      final grantMap = ClassChannelService.buildGrantMap(
        key: key,
        grantorName: 'Don Mario',
      );
      final chunks = ClassChannelService.createKeyGrantChunks(grantMap, pin);
      final assembled = QRDataService.assembleChunks(
        chunks.map(QRChunk.fromMap).toList(),
      );

      expect(
        () => ClassChannelService.importKeyGrant(assembled, '00000000'),
        throwsException,
      );
    });

    test('grant con type errato viene rifiutato', () {
      final payload = {
        'v': 1,
        'type': 'qualcos_altro',
        'keyBase64': ClassChannelService.generateKeyBase64(),
      };
      final pin = '12345678';
      final chunks = ClassChannelService.createKeyGrantChunks(payload, pin);
      final assembled = QRDataService.assembleChunks(
        chunks.map(QRChunk.fromMap).toList(),
      );
      expect(ClassChannelService.importKeyGrant(assembled, pin), isNull);
    });
  });
}
