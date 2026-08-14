// ============================================================================
// TEST: Isolamento per-classe (GDPR / privacy by default)
// ============================================================================
//
// Verifica che, quando la sync avviene con uno scope di classe (modalità
// "Responsabile" o associazione a classi specifiche), il ricevente:
//   - costruisca l'indice SOLO con i record delle classi a cui è associato;
//   - applichi SOLO i record delle classi a cui è associato, ignorando i
//     record di classi altrui (nessuna fuga di dati tra classi).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/sync/p2p/hive_sync_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  const classAId = 'class_A';
  const classACode = 'CODE_A';
  const classBId = 'class_B';
  const classBCode = 'CODE_B';

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_sync_scope_');
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

  Map<String, dynamic> classEntry(String id, String code, String name) => {
        'id': id,
        'uniqueCode': code,
        'name': name,
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'isDeleted': false,
      };

  Map<String, dynamic> studentEntry(String id, String classId, String name) => {
        'id': id,
        'classId': classId,
        'name': name,
        'allergies': 'segreto medico $name',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'isDeleted': false,
      };

  Future<void> seedLocalData() async {
    await LocalDatabase.classes().put(
      classAId,
      classEntry(classAId, classACode, 'Classe A'),
    );
    await LocalDatabase.classes().put(
      classBId,
      classEntry(classBId, classBCode, 'Classe B'),
    );
    await LocalDatabase.students().put(
      'STU_A1',
      studentEntry('STU_A1', classAId, 'Mario A'),
    );
    await LocalDatabase.students().put(
      'STU_A2',
      studentEntry('STU_A2', classAId, 'Luigi A'),
    );
    await LocalDatabase.students().put(
      'STU_B1',
      studentEntry('STU_B1', classBId, 'Anna B'),
    );
  }

  group('buildLocalIndex — indice limitato allo scope classe', () {
    test('senza scope (Mio Dispositivo) l\'indice include tutte le classi',
        () async {
      await seedLocalData();
      final index = HiveSyncEngine().buildLocalIndex();
      final ids = index.map((e) => '${e.boxName}:${e.id}').toSet();
      expect(ids, contains('${LocalDatabase.studentsBox}:STU_A1'));
      expect(ids, contains('${LocalDatabase.studentsBox}:STU_B1'));
      expect(ids, contains('${LocalDatabase.classesBox}:$classAId'));
      expect(ids, contains('${LocalDatabase.classesBox}:$classBId'));
    });

    test('con scope della classe A l\'indice esclude la classe B', () async {
      await seedLocalData();
      final scope = const SyncClassScope(
        classId: classAId,
        classUniqueCode: classACode,
      );
      final index = HiveSyncEngine().buildLocalIndex([scope]);
      final ids = index.map((e) => '${e.boxName}:${e.id}').toSet();

      expect(ids, contains('${LocalDatabase.studentsBox}:STU_A1'));
      expect(ids, contains('${LocalDatabase.studentsBox}:STU_A2'));
      expect(ids, contains('${LocalDatabase.classesBox}:$classAId'));
      // Nessun dato della classe B (studenti, allergie, classe).
      expect(ids, isNot(contains('${LocalDatabase.studentsBox}:STU_B1')));
      expect(ids, isNot(contains('${LocalDatabase.classesBox}:$classBId')));
    });

    test('con scope vuoto nessun record è condiviso', () async {
      await seedLocalData();
      final index = HiveSyncEngine().buildLocalIndex(const []);
      expect(index, isEmpty);
    });

    test('i dati fuori scope non sono MAI esposti (nessuna leak)', () async {
      await seedLocalData();
      final scope = const SyncClassScope(
        classId: classAId,
        classUniqueCode: classACode,
      );
      final index = HiveSyncEngine().buildLocalIndex([scope]);
      final payload = index.map((e) => e.toJson()).toList().toString();
      expect(payload, isNot(contains('Anna B')));
      expect(payload, isNot(contains('segreto medico')));
      expect(payload, isNot(contains(classBCode)));
    });
  });

  group('applyRemoteRecords — ricezione limitata allo scope classe', () {
    test('i record fuori scope vengono ignorati', () async {
      final engine = HiveSyncEngine();
      final scope = const SyncClassScope(
        classId: classAId,
        classUniqueCode: classACode,
      );

      final records = [
        SyncRecord(
          id: 'STU_REMOTE_A',
          boxName: LocalDatabase.studentsBox,
          data: studentEntry('STU_REMOTE_A', classAId, 'Remoto A'),
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        // Studente di una classe NON associata al ricevente.
        SyncRecord(
          id: 'STU_REMOTE_B',
          boxName: LocalDatabase.studentsBox,
          data: studentEntry('STU_REMOTE_B', classBId, 'Remoto B'),
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        // Metadati (nome) della classe B: NON devono arrivare.
        SyncRecord(
          id: classBId,
          boxName: LocalDatabase.classesBox,
          data: classEntry(classBId, classBCode, 'Classe B segreta'),
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ];

      final result = await engine.applyRemoteRecords(records, scopes: [scope]);

      // Solo il record della classe A viene applicato.
      expect(result.receivedRecords, 1);
      expect(
        LocalDatabase.students().get('STU_REMOTE_A'),
        isNotNull,
      );
      expect(
        LocalDatabase.students().get('STU_REMOTE_B'),
        isNull,
      );
      expect(LocalDatabase.classes().get(classBId), isNull);
    });

    test('senza scope vengono applicati tutti i record', () async {
      final engine = HiveSyncEngine();
      final records = [
        SyncRecord(
          id: 'STU_ALL_A',
          boxName: LocalDatabase.studentsBox,
          data: studentEntry('STU_ALL_A', classAId, 'A'),
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        SyncRecord(
          id: 'STU_ALL_B',
          boxName: LocalDatabase.studentsBox,
          data: studentEntry('STU_ALL_B', classBId, 'B'),
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ];
      final result = await engine.applyRemoteRecords(records);
      expect(result.receivedRecords, 2);
      expect(LocalDatabase.students().get('STU_ALL_A'), isNotNull);
      expect(LocalDatabase.students().get('STU_ALL_B'), isNotNull);
    });
  });
}