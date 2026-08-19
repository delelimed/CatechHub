import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/services/audit_log_service.dart';
import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/classes/classes_repository.dart';
import 'package:CatechHub/features/responsabile/passaggio_anno_service.dart';
import 'package:CatechHub/features/students/students_repository.dart';
import 'package:CatechHub/shared/models/class_model.dart';
import 'package:CatechHub/shared/models/parish_config.dart';
import 'package:CatechHub/shared/models/student_model.dart';

Student _student(
  String id,
  String name, {
  String? classId,
  String stato = 'ATTIVO',
  String anno = '2026-2027',
}) {
  return Student(
    id: id,
    name: name,
    surname: name,
    birthDate: DateTime(2012, 1, 1),
    motherName: '',
    motherSurname: '',
    fatherName: '',
    fatherSurname: '',
    motherPhone: '',
    fatherPhone: '',
    studentPhone: '',
    classId: classId,
    statoPercorso: stato,
    annoIscrizione: anno,
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    AuditLogService.debugSecretOverride = 'test-secret-passaggio';
    tempDir = Directory.systemTemp.createTempSync('hive_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalDatabase.authBox);
    await Hive.openBox<Map>(LocalDatabase.classesBox);
    await Hive.openBox<Map>(LocalDatabase.studentsBox);
    await Hive.openBox<Map>(LocalDatabase.auditLogBox);
    await Hive.openBox(LocalDatabase.parishConfigBox);
  });

  tearDown(() async {
    AuditLogService.debugSecretOverride = null;
    for (final box in [
      LocalDatabase.authBox,
      LocalDatabase.classesBox,
      LocalDatabase.studentsBox,
      LocalDatabase.auditLogBox,
      LocalDatabase.parishConfigBox,
    ]) {
      try {
        await Hive.deleteBoxFromDisk(box);
      } catch (_) {}
    }
    tempDir.deleteSync(recursive: true);
  });

  group('PassaggioAnnoService.annoSuccessivo', () {
    test('calcola l\'anno successivo', () {
      expect(PassaggioAnnoService.annoSuccessivo('2026-2027'), '2027-2028');
    });

    test('restituisce l\'input se il formato non è valido', () {
      expect(PassaggioAnnoService.annoSuccessivo('2026'), '2026');
      expect(PassaggioAnnoService.annoSuccessivo(''), '');
    });
  });

  group('PassaggioAnnoService.passaAnno', () {
    test(
      'promuove la classe e aggiorna l\'anno di iscrizione degli attivi',
      () async {
        final classesRepo = ClassesRepository();
        final studentsRepo = StudentsRepository();

        await classesRepo.addClass(
          SchoolClass(
            id: 'class_pa_1',
            name: 'Prima Comunione 2026',
            studentIds: ['s1', 's2', 's3'],
            catechistIds: [],
            percorso: 'Prima Comunione',
            livello: 1,
            annoCatechistico: '2026-2027',
          ),
        );

        for (final id in ['s1', 's2', 's3']) {
          await studentsRepo.addStudent(
            _student(id, 'Nome', classId: 'class_pa_1'),
          );
        }

        await LocalDatabase.parishConfig().put(
          ParishConfig.storageKey,
          ParishConfig.empty
              .copyWith(annoCatechisticoCorrente: '2026-2027')
              .toMap(),
        );

        final results = await PassaggioAnnoService().passaAnno(
          nuovoAnno: '2027-2028',
          testNow: DateTime.utc(2027, 6, 30),
        );

        expect(results, hasLength(1));
        expect(results.first.promossi, 3);
        expect(results.first.ritirati, 0);
        expect(results.first.promoted.livello, 2);
        expect(results.first.promoted.annoCatechistico, '2027-2028');

        final updated = classesRepo.getClassesSync().firstWhere(
          (c) => c.id == 'class_pa_1',
        );
        expect(updated.livello, 2);
        expect(updated.annoCatechistico, '2027-2028');

        final config = LocalDatabase.parishConfig().get(
          ParishConfig.storageKey,
        );
        expect(config, isNotNull);
      },
    );

    test(
      'gli studenti RITIRATO vengono archiviati via removeFromClass',
      () async {
        final studentsRepo = StudentsRepository();
        await studentsRepo.addStudent(
          _student('s_rit', 'Marco', classId: 'class_pa_2', stato: 'RITIRATO'),
        );
        await studentsRepo.addStudent(
          _student('s_att', 'Luca', classId: 'class_pa_2'),
        );

        await ClassesRepository().addClass(
          SchoolClass(
            id: 'class_pa_2',
            name: 'Cresima',
            studentIds: ['s_rit', 's_att'],
            catechistIds: [],
            percorso: 'Cresima',
            livello: 1,
            annoCatechistico: '2026-2027',
          ),
        );

        await LocalDatabase.parishConfig().put(
          ParishConfig.storageKey,
          ParishConfig.empty
              .copyWith(annoCatechisticoCorrente: '2026-2027')
              .toMap(),
        );

        final results = await PassaggioAnnoService().passaAnno(
          nuovoAnno: '2027-2028',
        );

        expect(results.single.promossi, 1);
        expect(results.single.ritirati, 1);

        final ritirato = (await studentsRepo.getAllStudentsSync()).firstWhere(
          (s) => s.id == 's_rit',
        );
        expect(ritirato.classId, isNull);
      },
    );
  });
}
