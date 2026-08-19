// ============================================================================
// TEST: HistoricalRecordRepository (archivio storico ragazzi)
// Copre: CRUD snapshot immutabili, ordinamento, cascade delete per studente.
// ============================================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/archive/historical_record_repository.dart';
import 'package:CatechHub/shared/models/historical_record.dart';

HistoricalRecord _record(
  String studentId,
  String year, {
  String classId = 'c1',
  double attendance = 80,
}) {
  return HistoricalRecord(
    recordId: '',
    studentId: studentId,
    academicYear: year,
    classId: classId,
    className: 'Comunione A',
    catechistId: 'cat_1',
    sacramentsReceived: const [Sacrament.battesimo, Sacrament.comunione],
    attendancePercentage: attendance,
    evaluationsSummary: 'Ottimo percorso.',
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_hist_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalDatabase.authBox);
    await Hive.openBox<Map>(LocalDatabase.historicalRecordsBox);
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(LocalDatabase.authBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.historicalRecordsBox);
    tempDir.deleteSync(recursive: true);
  });

  group('HistoricalRecordRepository.addRecord', () {
    test('inserisce uno snapshot e genera il recordId', () async {
      final repo = HistoricalRecordRepository();
      final saved = await repo.addRecord(_record('s1', '2026-2027'));

      expect(saved.recordId, isNotEmpty);
      expect(repo.count, 1);
      expect(saved.studentId, 's1');
      expect(saved.sacramentsReceived, contains(Sacrament.comunione));
    });

    test('lo snapshot serializzato mantiene tutti i campi', () async {
      final repo = HistoricalRecordRepository();
      await repo.addRecord(_record('s2', '2025-2026', attendance: 92.5));

      final loaded = repo.getAllRecordsSync().single;
      expect(loaded.academicYear, '2025-2026');
      expect(loaded.attendancePercentage, 92.5);
      expect(loaded.className, 'Comunione A');
      expect(loaded.catechistId, 'cat_1');
      expect(loaded.evaluationsSummary, 'Ottimo percorso.');
    });
  });

  group('HistoricalRecordRepository.getAllRecordsSync', () {
    test('ordina i record dal più recente al più vecchio', () async {
      final repo = HistoricalRecordRepository();
      await repo.addRecord(_record('s1', '2024-2025'));
      await repo.addRecord(_record('s2', '2026-2027'));
      await repo.addRecord(_record('s3', '2025-2026'));

      final all = repo.getAllRecordsSync();
      expect(all.map((r) => r.academicYear).toList(), [
        '2026-2027',
        '2025-2026',
        '2024-2025',
      ]);
    });
  });

  group('HistoricalRecordRepository.deleteRecordsForStudent', () {
    test(
      'elimina i record di un singolo studente (Diritto all\'Oblio)',
      () async {
        final repo = HistoricalRecordRepository();
        await repo.addRecord(_record('s1', '2024-2025'));
        await repo.addRecord(_record('s1', '2025-2026'));
        await repo.addRecord(_record('s2', '2025-2026'));

        await repo.deleteRecordsForStudent('s1');

        expect(repo.count, 1);
        expect(repo.getAllRecordsSync().single.studentId, 's2');
      },
    );

    test('elimina i record di un gruppo di studenti', () async {
      final repo = HistoricalRecordRepository();
      await repo.addRecord(_record('s1', '2024-2025'));
      await repo.addRecord(_record('s2', '2024-2025'));
      await repo.addRecord(_record('s3', '2024-2025'));

      await repo.deleteRecordsForStudents(['s1', 's2']);

      expect(repo.getAllRecordsSync().single.studentId, 's3');
    });
  });

  group('HistoricalRecordRepository.deleteAll', () {
    test('svuota completamente l\'archivio (reset totale)', () async {
      final repo = HistoricalRecordRepository();
      await repo.addRecord(_record('s1', '2024-2025'));
      await repo.addRecord(_record('s2', '2025-2026'));

      await repo.deleteAll();

      expect(repo.count, 0);
    });
  });
}
