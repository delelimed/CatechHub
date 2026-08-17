// ============================================================================
// TEST: M7 / Fase 3-8 (cascata cancellazione) e M8 / Fase 3-9 (dati demo esclusi)
// ============================================================================
//
// 1. La cancellazione di uno studente (usata dal cleanup automatico GDPR della
//    retention) deve essere una VERA cascata: allegati, note, storici, presenze
//    e riferimenti nelle classi devono sparire, non solo il record studente.
// 2. I record demo della guida (tag `_demo`) non devono MAI essere esportati
//    (export, pacchetto conservazione GDPR) né propagati via sync P2P.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/services/data_export_service.dart';
import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/gdpr/gdpr_export_service.dart';
import 'package:CatechHub/features/students/students_repository.dart';
import 'package:CatechHub/features/sync/p2p/hive_sync_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('retention_demo_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalDatabase.authBox);
    await Hive.openBox<Map>(LocalDatabase.studentsBox);
    await Hive.openBox<Map>(LocalDatabase.classesBox);
    await Hive.openBox<Map>(LocalDatabase.planningBox);
    await Hive.openBox<Map>(LocalDatabase.attendanceBox);
    await Hive.openBox<Map>(LocalDatabase.documentsBox);
    await Hive.openBox<Map>(LocalDatabase.documentDeliveriesBox);
    await Hive.openBox<Map>(LocalDatabase.attachmentsBox);
    await Hive.openBox<Map>(LocalDatabase.contactNotesBox);
    await Hive.openBox<Map>(LocalDatabase.studentDailyNotesBox);
    await Hive.openBox<Map>(LocalDatabase.historicalRecordsBox);
    await Hive.openBox(LocalDatabase.parishConfigBox);
    await Hive.openBox<Map>(LocalDatabase.auditLogBox);
    await Hive.openBox<Map>(LocalDatabase.tombstoneBox);
    await Hive.openBox<Map>(LocalDatabase.catechesiBox);
    await Hive.openBox(LocalDatabase.meetingCatechesiBox);
    await Hive.openBox<Map>(LocalDatabase.aulaBox);
    await Hive.openBox<Map>(LocalDatabase.catechistsBox);
    await Hive.openBox<Map>(LocalDatabase.avvisiBox);
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(LocalDatabase.authBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.studentsBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.classesBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.planningBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.attendanceBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.documentsBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.documentDeliveriesBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.attachmentsBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.contactNotesBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.studentDailyNotesBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.historicalRecordsBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.parishConfigBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.auditLogBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.tombstoneBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.catechesiBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.meetingCatechesiBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.aulaBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.catechistsBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.avvisiBox);
    tempDir.deleteSync(recursive: true);
  });

  Map<String, dynamic> studentEntry(String id, {bool demo = false}) => {
        'id': id,
        'classId': 'class_1',
        'classUniqueCode': 'CU_1',
        'name': demo ? 'Mario Demo' : 'Gino Reale',
        'surname': demo ? 'Esempio' : 'Protetto',
        'birthDate': '2014-01-01T00:00:00.000Z',
        'motherName': 'Anna',
        'motherSurname': 'Mamma',
        'fatherName': 'Luigi',
        'fatherSurname': 'Papa',
        'motherPhone': '3330000001',
        'fatherPhone': '3330000002',
        'studentPhone': '3330000003',
        'parentEmail': 'genitore@example.com',
        'allergies': 'nessuna',
        'autonomousExits': 'false',
        'notes': '',
        'consensoPrivacyFirmato': true,
        'dataFirmaConsenso': '2026-01-01T00:00:00.000Z',
        'dataScadenzaTrattamento': '2027-01-01T00:00:00.000Z',
        'statoPercorso': 'ATTIVO',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        if (demo) '_demo': true,
      };

  Map<String, dynamic> classEntry(List<String> studentIds) => {
        'name': 'Prima Comunione',
        'uniqueCode': 'CU_1',
        'catechistIds': ['local_catechist_id'],
        'studentIds': studentIds,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      };

  group('M7 / Fase 3-8: cascata di cancellazione reale', () {
    test('deleteStudent rimuove note, storici, presenze e riferimenti classe',
        () async {
      const id = 'STU_CASCADE';
      await LocalDatabase.students().put(id, studentEntry(id));
      await LocalDatabase.classes().put('class_1', classEntry([id]));
      await LocalDatabase.attendance().put(
            'meet_1',
            {'presence': {id: true}, 'updatedAt': '2026-01-01T00:00:00.000Z'},
          );
      await LocalDatabase.studentDailyNotes().put(
            'note_1',
            {'studentId': id, 'text': 'nota', 'updatedAt': '2026-01-01T00:00:00.000Z'},
          );
      await LocalDatabase.historicalRecords().put(
            'hist_1',
            {'studentId': id, 'note': 'storico', 'updatedAt': '2026-01-01T00:00:00.000Z'},
          );
      await LocalDatabase.documentDeliveries().put(
            'doc_1',
            {id: '2026-01-15', 'updatedAt': '2026-01-01T00:00:00.000Z'},
          );

      await StudentsRepository().deleteStudent(id);

      expect(LocalDatabase.students().containsKey(id), isFalse,
          reason: 'il record studente deve essere eliminato');
      final classMap =
          LocalDatabase.toStringDynamicMap(LocalDatabase.classes().get('class_1'));
      expect(classMap['studentIds'], isNot(contains(id)),
          reason: 'lo studente deve essere rimosso dalla classe');
      final presence = LocalDatabase.toStringDynamicMap(
          LocalDatabase.attendance().get('meet_1'))['presence'] as Map;
      expect(presence.containsKey(id), isFalse,
          reason: 'lo studente deve essere rimosso dalle presenze');
      expect(LocalDatabase.studentDailyNotes().containsKey('note_1'), isFalse,
          reason: 'le note giornaliere devono essere eliminate');
      expect(LocalDatabase.historicalRecords().containsKey('hist_1'), isFalse,
          reason: 'i record storici devono essere eliminati');
      final delivery =
          LocalDatabase.toStringDynamicMap(LocalDatabase.documentDeliveries().get('doc_1'));
      expect(delivery.containsKey(id), isFalse,
          reason: 'lo studente deve essere rimosso dalle consegne documenti');
    });

    test('deleteStudent non cancella un altro studente dello stesso box', () async {
      const id = 'STU_CASCADE';
      const other = 'STU_ALTRO';
      await LocalDatabase.students().put(id, studentEntry(id));
      await LocalDatabase.students().put(other, studentEntry(other));

      await StudentsRepository().deleteStudent(id);

      expect(LocalDatabase.students().containsKey(id), isFalse);
      expect(LocalDatabase.students().containsKey(other), isTrue,
          reason: 'la cascata non deve toccare gli altri studenti');
    });
  });

  group('M8 / Fase 3-9: dati demo esclusi da export e sync', () {
    test('exportAllData non include lo studente demo', () async {
      const demoId = 'STU_DEMO';
      const realId = 'STU_REAL';
      await LocalDatabase.students().put(demoId, studentEntry(demoId, demo: true));
      await LocalDatabase.students().put(realId, studentEntry(realId));
      await LocalDatabase.classes().put('class_1', classEntry([demoId, realId]));

      final data = await DataExportService.exportAllData();

      final exportedIds = (data['anagrafica']['students'] as List)
          .map((s) => (s as Map)['id'].toString())
          .toSet();
      expect(exportedIds, contains(realId),
          reason: 'lo studente reale deve essere esportato');
      expect(exportedIds, isNot(contains(demoId)),
          reason: 'lo studente demo non deve essere esportato');
    });

    test('pacchetto conservazione GDPR non include lo studente demo', () async {
      const demoId = 'STU_DEMO';
      const realId = 'STU_REAL';
      await LocalDatabase.students().put(demoId, studentEntry(demoId, demo: true));
      await LocalDatabase.students().put(realId, studentEntry(realId));

      final pkg = GdprExportService.buildParishConservationPackage();
      final exportedIds = (pkg['schedaSchedaConsensi'] as List)
          .map((s) => (s as Map)['id'].toString())
          .toSet();
      expect(exportedIds, contains(realId));
      expect(exportedIds, isNot(contains(demoId)),
          reason: 'il dato demo non deve comparire nell\'archivio di conservazione');
    });

    test('indice sync P2P e record modificati escludono lo studente demo',
        () async {
      const demoId = 'STU_DEMO';
      const realId = 'STU_REAL';
      await LocalDatabase.students().put(demoId, studentEntry(demoId, demo: true));
      await LocalDatabase.students().put(realId, studentEntry(realId));

      final index = HiveSyncEngine().buildLocalIndex();
      final indexedIds = index.where((e) => e.boxName == LocalDatabase.studentsBox)
          .map((e) => e.id)
          .toSet();
      expect(indexedIds, contains(realId));
      expect(indexedIds, isNot(contains(demoId)),
          reason: 'il dato demo non deve essere pubblicizzato via sync');

      final records = HiveSyncEngine()
          .extractModifiedRecords(DateTime.fromMillisecondsSinceEpoch(0).toUtc());
      final recordIds = records
          .where((r) => r.boxName == LocalDatabase.studentsBox)
          .map((r) => r.id)
          .toSet();
      expect(recordIds, contains(realId));
      expect(recordIds, isNot(contains(demoId)),
          reason: 'il dato demo non deve essere trasmesso via sync');
    });
  });
}
