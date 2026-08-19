// ============================================================================
// TEST: HistoricalAccessPolicy (regole di visibilità dell'archivio storico)
// Copre:
//   - Responsabile: accesso PIENO a tutti i record, anche di altri anni.
//   - Catechista: vede SOLO i record dei ragazzi attualmente nelle proprie
//     classi (storico anni precedenti).
//   - Scadenza dati: se il ragazzo esce dalle classi del catechista, i suoi
//     record spariscono dalla vista alla lettura successiva.
// ============================================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/auth/auth_service.dart';
import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/archive/historical_access_policy.dart';
import 'package:CatechHub/shared/models/historical_record.dart';
import 'package:CatechHub/shared/models/user_role.dart';

HistoricalRecord _record(String studentId, String year) {
  return HistoricalRecord(
    recordId: 'hist_$studentId$year',
    studentId: studentId,
    academicYear: year,
    className: 'Comunione A',
  );
}

/// Crea una classe nel box `classes` con i catechisti e gli studenti dati.
Future<void> _classa(
  String classId, {
  required List<String> catechistIds,
  required List<String> studentIds,
}) async {
  await LocalDatabase.classes().put(classId, {
    'name': 'Comunione A',
    'studentIds': studentIds,
    'catechistIds': catechistIds,
    'catechistRoles': {for (final c in catechistIds) c: 'TITOLARE'},
    'archived': false,
    'percorso': 'Prima Comunione',
    'livello': 1,
  });
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_policy_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalDatabase.authBox);
    await Hive.openBox<Map>(LocalDatabase.classesBox);
    await Hive.openBox<Map>(LocalDatabase.historicalRecordsBox);
  });

  tearDown(() async {
    for (final box in [
      LocalDatabase.authBox,
      LocalDatabase.classesBox,
      LocalDatabase.historicalRecordsBox,
    ]) {
      try {
        await Hive.deleteBoxFromDisk(box);
      } catch (_) {}
    }
    tempDir.deleteSync(recursive: true);
  });

  final records = [
    _record('s1', '2026-2027'),
    _record('s1', '2025-2026'),
    _record('s2', '2026-2027'),
    _record('s3', '2024-2025'),
  ];

  group('HistoricalAccessPolicy — Responsabile (Full Access)', () {
    test('vede TUTTI i record della parrocchia di tutti gli anni', () async {
      await UserRole.setCurrent(UserRole.responsabile);

      final policy = HistoricalAccessPolicy();
      expect(policy.isFullAccess, isTrue);

      final visible = policy.applyVisibility(records);
      expect(visible, hasLength(4));
      expect(visible.map((r) => r.studentId).toSet(), {'s1', 's2', 's3'});
    });

    test('canViewRecord è true per ogni record', () async {
      await UserRole.setCurrent(UserRole.responsabile);
      final policy = HistoricalAccessPolicy();
      for (final r in records) {
        expect(policy.canViewRecord(r), isTrue);
      }
    });
  });

  group('HistoricalAccessPolicy — Catechista (Restricted Access)', () {
    setUp(() async {
      await UserRole.setCurrent(UserRole.catechista);
    });

    test(
      'vede lo storico dei ragazzi ATTUALMENTE nelle proprie classi',
      () async {
        // Il catechista locale (local_catechist_id) ha la classe C1 con s1.
        await _classa(
          'c1',
          catechistIds: [AuthService.localUserId],
          studentIds: ['s1'],
        );

        final policy = HistoricalAccessPolicy();
        final visible = policy.applyVisibility(records);

        // Solo i record di s1 (2 anni). s2 e s3 sono di altre classi.
        expect(visible.map((r) => r.studentId).toSet(), {'s1'});
        expect(visible, hasLength(2));
      },
    );

    test('un ragazzo di un\'altra classe del catechista è visibile', () async {
      await _classa(
        'c1',
        catechistIds: [AuthService.localUserId],
        studentIds: ['s1', 's3'],
      );
      await _classa(
        'c2',
        catechistIds: [AuthService.localUserId],
        studentIds: ['s2'],
      );

      final policy = HistoricalAccessPolicy();
      final visible = policy.applyVisibility(records);

      expect(visible.map((r) => r.studentId).toSet(), {'s1', 's2', 's3'});
    });

    test(
      'SE IL RAGAZZO ESCE DALLE CLASSI, I SUOI RECORD SPARISCONO (scadenza)',
      () async {
        await _classa(
          'c1',
          catechistIds: [AuthService.localUserId],
          studentIds: ['s1', 's2'],
        );

        final policy = HistoricalAccessPolicy();
        expect(
          policy.applyVisibility(records).map((r) => r.studentId).toSet(),
          {'s1', 's2'},
        );

        // s2 viene rimosso dalla classe: nessuna ri-associazione né job
        // temporizzato, alla PROSSIMA lettura i suoi record non ci sono più.
        await LocalDatabase.classes().put('c1', {
          'name': 'Comunione A',
          'studentIds': ['s1'],
          'catechistIds': [AuthService.localUserId],
          'catechistRoles': {AuthService.localUserId: 'TITOLARE'},
          'archived': false,
          'percorso': 'Prima Comunione',
          'livello': 1,
        });

        final after = policy.applyVisibility(records);
        expect(after.map((r) => r.studentId).toSet(), {'s1'});
        expect(after.any((r) => r.studentId == 's2'), isFalse);
      },
    );

    test('se il catechista non ha classi non vede alcun record', () async {
      final policy = HistoricalAccessPolicy();
      expect(policy.applyVisibility(records), isEmpty);
    });

    test('canViewRecord è false per i record degli studenti altrui', () async {
      await _classa(
        'c1',
        catechistIds: [AuthService.localUserId],
        studentIds: ['s1'],
      );

      final policy = HistoricalAccessPolicy();
      expect(policy.canViewRecord(_record('s1', '2024-2025')), isTrue);
      expect(policy.canViewRecord(_record('s2', '2024-2025')), isFalse);
    });
  });
}
