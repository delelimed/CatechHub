// ============================================================================
// TEST: Resilienza ai tombstone GDPR (H5)
// ============================================================================
//
// Verifica che un record cancellato localmente NON venga resuscitato da una
// copia "live" arrivata via sync da un dispositivo rimasto offline al momento
// della cancellazione. La cancellazione è appiccicosa: vince sul dato live e
// viene ripropagata (updatedAt aggiornato) così gli altri peer la applicano.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/sync/p2p/hive_sync_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_tombstone_resilience_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalDatabase.authBox);
    await Hive.openBox<Map>(LocalDatabase.studentsBox);
    await Hive.openBox<Map>(LocalDatabase.classesBox);
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(LocalDatabase.authBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.studentsBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.classesBox);
    tempDir.deleteSync(recursive: true);
  });

  Map<String, dynamic> studentEntry({
    required String id,
    required bool isDeleted,
    required DateTime updatedAt,
    String name = 'Gino Protetto',
  }) =>
      {
        'id': id,
        'classId': 'class_1',
        'name': name,
        'allergies': 'segreto medico',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'isDeleted': isDeleted,
      };

  SyncRecord liveRecord(String id) => SyncRecord(
        id: id,
        boxName: LocalDatabase.studentsBox,
        data: studentEntry(
          id: id,
          isDeleted: false,
          updatedAt: DateTime.utc(2026, 1, 15),
        ),
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 15),
      );

  group('applyRemoteRecords — Diritto all\'Oblio (H5)', () {
    test(
        'un record cancellato localmente NON viene resuscitato da una copia '
        'live remota (la PII del minore non riappare)', () async {
      // Dispositivo offline che conserva il record (cancellazione avvenuta
      // mentre era disconnesso): il box locale ha il record con isDeleted=true.
      await LocalDatabase.students().put(
        'STU_1',
        studentEntry(
          id: 'STU_1',
          isDeleted: true,
          updatedAt: DateTime.utc(2026, 1, 10),
        ),
      );

// Un altro peer (non aggiornato) gli invia la copia live: il record
      // cancellato NON viene resuscitato e la PII non viene sostituita da
      // una versione "viva" riproposta da un dispositivo rimasto offline.
      final result =
          await HiveSyncEngine().applyRemoteRecords([liveRecord('STU_1')]);

      expect(result.success, isTrue);
      final stored =
          LocalDatabase.toStringDynamicMap(LocalDatabase.students().get('STU_1'));
      expect(stored['isDeleted'], isTrue,
          reason: 'la cancellazione locale deve vincere sul dato live');
      expect(stored['name'], isNot('Minore Protetto'),
          reason: 'il dato live remoto non deve sovrascrivere il record '
              'cancellato');
    });

    test('la cancellazione resta appiccicosa e viene ripropagata', () async {
      final localUpdatedAt = DateTime.utc(2026, 1, 10);
      await LocalDatabase.students().put(
        'STU_2',
        studentEntry(
          id: 'STU_2',
          isDeleted: true,
          updatedAt: localUpdatedAt,
        ),
      );

      final result =
          await HiveSyncEngine().applyRemoteRecords([liveRecord('STU_2')]);

      expect(result.success, isTrue);
      final stored =
          LocalDatabase.toStringDynamicMap(LocalDatabase.students().get('STU_2'));
      expect(stored['isDeleted'], isTrue);
      // updatedAt deve essere stato aggiornato oltre la copia live così
      // l'indice la pubblica come cancellazione (ripropagazione ai peer).
      final newUpdatedAt = DateTime.parse(stored['updatedAt'] as String);
      expect(newUpdatedAt.isAfter(DateTime.utc(2026, 1, 15)), isTrue);
    });

    test(
        'una cancellazione remota sovrascrive comunque la copia live locale '
        '(comportamento LWW per il verso opposto)', () async {
      await LocalDatabase.students().put(
        'STU_3',
        studentEntry(
          id: 'STU_3',
          isDeleted: false,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      final remoteDeleted = SyncRecord(
        id: 'STU_3',
        boxName: LocalDatabase.studentsBox,
        data: studentEntry(
          id: 'STU_3',
          isDeleted: true,
          updatedAt: DateTime.utc(2026, 1, 20),
        ),
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 20),
        isDeleted: true,
      );
      final result = await HiveSyncEngine()
          .applyRemoteRecords([remoteDeleted]);

      expect(result.success, isTrue);
      final stored =
          LocalDatabase.toStringDynamicMap(LocalDatabase.students().get('STU_3'));
      expect(stored['isDeleted'], isTrue);
    });
  });
}