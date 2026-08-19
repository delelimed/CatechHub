// ============================================================================
// TEST: ConcludiAnnoService (chiusura anno catechistico e archivio storico)
// Copre:
//   - Guardia ruolo: solo il Responsabile può concludere l'anno.
//   - "Concludi Anno Catechistico": snapshot storici immutabili + promozione
//     delle classi + aggiornamento anno corrente.
//   - Promozione singola (promuoviStudente).
//   - Archiviazione singola ad anno concluso (archiviaStudente).
// ============================================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/services/audit_log_service.dart';
import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/archive/concludi_anno_service.dart';
import 'package:CatechHub/features/archive/historical_record_repository.dart';
import 'package:CatechHub/features/classes/classes_repository.dart';
import 'package:CatechHub/features/students/students_repository.dart';
import 'package:CatechHub/shared/models/class_model.dart';
import 'package:CatechHub/shared/models/historical_record.dart';
import 'package:CatechHub/shared/models/parish_config.dart';
import 'package:CatechHub/shared/models/student_model.dart';
import 'package:CatechHub/shared/models/user_role.dart';

Student _student(
  String id,
  String name, {
  String? classId,
  String stato = 'ATTIVO',
  String anno = '2026-2027',
  List<Sacrament> sacraments = const [],
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
    sacraments: sacraments,
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    AuditLogService.debugSecretOverride = 'test-secret-archivio';
    tempDir = Directory.systemTemp.createTempSync('hive_archivio_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalDatabase.authBox);
    await Hive.openBox<Map>(LocalDatabase.classesBox);
    await Hive.openBox<Map>(LocalDatabase.studentsBox);
    await Hive.openBox<Map>(LocalDatabase.attendanceBox);
    await Hive.openBox<Map>(LocalDatabase.auditLogBox);
    await Hive.openBox(LocalDatabase.parishConfigBox);
    await Hive.openBox<Map>(LocalDatabase.historicalRecordsBox);
  });

  tearDown(() async {
    AuditLogService.debugSecretOverride = null;
    for (final box in [
      LocalDatabase.authBox,
      LocalDatabase.classesBox,
      LocalDatabase.studentsBox,
      LocalDatabase.attendanceBox,
      LocalDatabase.auditLogBox,
      LocalDatabase.parishConfigBox,
      LocalDatabase.historicalRecordsBox,
    ]) {
      try {
        await Hive.deleteBoxFromDisk(box);
      } catch (_) {}
    }
    tempDir.deleteSync(recursive: true);
  });

  Future<void> setupConfig(String anno) async {
    await LocalDatabase.parishConfig().put(
      ParishConfig.storageKey,
      ParishConfig.empty.copyWith(annoCatechisticoCorrente: anno).toMap(),
    );
  }

  group('ConcludiAnnoService — guardia ruolo', () {
    test(
      'un Catechista non può concludere l\'anno (UnsupportedError)',
      () async {
        await UserRole.setCurrent(UserRole.catechista);
        await setupConfig('2026-2027');

        expect(
          () => ConcludiAnnoService().concludiAnno(),
          throwsUnsupportedError,
        );
      },
    );

    test('un Catechista non può promuovere singolarmente', () async {
      await UserRole.setCurrent(UserRole.catechista);
      final s = _student('s1', 'Luca', classId: 'c1');

      expect(
        () => ConcludiAnnoService().promuoviStudente(
          s,
          SchoolClass(
            id: 'c1',
            name: 'Comunione A',
            studentIds: ['s1'],
            catechistIds: [],
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('ConcludiAnnoService.concludiAnno', () {
    test('crea snapshot immutabili e promuove le classi', () async {
      await UserRole.setCurrent(UserRole.responsabile);
      await setupConfig('2026-2027');

      final studentsRepo = StudentsRepository();
      await studentsRepo.addStudent(
        _student(
          's1',
          'Luca',
          classId: 'c1',
          sacraments: const [Sacrament.battesimo, Sacrament.comunione],
        ),
      );
      await studentsRepo.addStudent(_student('s2', 'Marco', classId: 'c1'));

      await ClassesRepository().addClass(
        SchoolClass(
          id: 'c1',
          name: 'Comunione A',
          studentIds: ['s1', 's2'],
          catechistIds: ['cat_1'],
          catechistRoles: const {'cat_1': 'TITOLARE'},
          percorso: 'Prima Comunione',
          livello: 1,
          annoCatechistico: '2026-2027',
        ),
      );

      // Presenze: s1 presente 2/2, s2 assente all'ultimo incontro.
      await LocalDatabase.attendance().put('att_1', {
        'classId': 'c1',
        'date': '2026-10-01',
        'presence': {'s1': 'Presente', 's2': 'Presente'},
      });
      await LocalDatabase.attendance().put('att_2', {
        'classId': 'c1',
        'date': '2026-10-08',
        'presence': {'s1': 'Presente', 's2': 'Assente'},
      });

      final result = await ConcludiAnnoService().concludiAnno(
        nuovoAnno: '2027-2028',
        testNow: DateTime.utc(2027, 6, 30),
      );

      // Snapshot creati per entrambi i ragazzi.
      expect(result.records, hasLength(2));
      final repo = HistoricalRecordRepository();
      final stored = repo.getAllRecordsSync();
      expect(stored, hasLength(2));

      final s1 = stored.firstWhere((r) => r.studentId == 's1');
      expect(s1.academicYear, '2026-2027');
      expect(s1.className, 'Comunione A');
      expect(s1.catechistId, 'cat_1');
      expect(
        s1.sacramentsReceived,
        containsAll([Sacrament.battesimo, Sacrament.comunione]),
      );
      expect(s1.attendancePercentage, 100);

      final s2 = stored.firstWhere((r) => r.studentId == 's2');
      expect(s2.attendancePercentage, 50);

      // La classe è stata promossa al livello successivo.
      final promoted = ClassesRepository().getClassesSync().firstWhere(
        (c) => c.id == 'c1',
      );
      expect(promoted.livello, 2);
      expect(promoted.annoCatechistico, '2027-2028');

      // L'anno corrente è stato aggiornato.
      final config = LocalDatabase.parishConfig().get(ParishConfig.storageKey);
      final parsed = ParishConfig.fromMap(
        LocalDatabase.toStringDynamicMap(config),
      );
      expect(parsed.annoCatechisticoCorrente, '2027-2028');

      // Gli studenti promossi hanno l'anno di iscrizione aggiornato.
      final updatedS1 = (await studentsRepo.getAllStudentsSync()).firstWhere(
        (s) => s.id == 's1',
      );
      expect(updatedS1.annoIscrizione, '2027-2028');
    });

    test(
      'è idempotente: uno snapshot già esistente non viene duplicato',
      () async {
        await UserRole.setCurrent(UserRole.responsabile);
        await setupConfig('2026-2027');

        await StudentsRepository().addStudent(
          _student('s1', 'Luca', classId: 'c1'),
        );
        await ClassesRepository().addClass(
          SchoolClass(
            id: 'c1',
            name: 'Comunione A',
            studentIds: ['s1'],
            catechistIds: ['cat_1'],
            percorso: 'Prima Comunione',
            livello: 1,
            annoCatechistico: '2026-2027',
          ),
        );

        // Snapshot già presente per lo studente/anno/classe: la chiusura non
        // deve crearlo di nuovo (guardia anti-duplicato del servizio).
        final repo = HistoricalRecordRepository();
        await repo.addRecord(
          HistoricalRecord(
            recordId: '',
            studentId: 's1',
            academicYear: '2026-2027',
            classId: 'c1',
            className: 'Comunione A',
          ),
        );

        final result = await ConcludiAnnoService().concludiAnno(
          nuovoAnno: '2027-2028',
        );

        expect(result.records, hasLength(0));
        expect(repo.count, 1);
      },
    );

    test('lancia StateError se l\'anno corrente non è configurato', () async {
      await UserRole.setCurrent(UserRole.responsabile);
      // Nessun anno configurato → ParishConfig vuota.

      expect(
        () => ConcludiAnnoService().concludiAnno(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ConcludiAnnoService.promuoviStudente', () {
    test(
      'archivia l\'anno corrente e aggiorna l\'anno di iscrizione',
      () async {
        await UserRole.setCurrent(UserRole.responsabile);
        await setupConfig('2026-2027');

        await StudentsRepository().addStudent(
          _student('s1', 'Luca', classId: 'c1'),
        );
        final s = (await StudentsRepository().getAllStudentsSync()).firstWhere(
          (st) => st.id == 's1',
        );
        final cls = SchoolClass(
          id: 'c1',
          name: 'Comunione A',
          studentIds: ['s1'],
          catechistIds: ['cat_1'],
          percorso: 'Prima Comunione',
          livello: 1,
          annoCatechistico: '2026-2027',
        );

        final record = await ConcludiAnnoService().promuoviStudente(
          s,
          cls,
          nuovoAnno: '2027-2028',
        );

        expect(record.academicYear, '2026-2027');
        expect(HistoricalRecordRepository().count, 1);

        final updated = (await StudentsRepository().getAllStudentsSync())
            .firstWhere((st) => st.id == 's1');
        expect(updated.annoIscrizione, '2027-2028');
      },
    );
  });

  group('ConcludiAnnoService.archiviaStudente', () {
    test(
      'archivia ad anno concluso: snapshot + stato + rimozione dalla classe',
      () async {
        await UserRole.setCurrent(UserRole.responsabile);
        await setupConfig('2026-2027');

        final studentsRepo = StudentsRepository();
        await studentsRepo.addStudent(_student('s1', 'Luca', classId: 'c1'));
        await ClassesRepository().addClass(
          SchoolClass(
            id: 'c1',
            name: 'Comunione A',
            studentIds: ['s1'],
            catechistIds: [],
            percorso: 'Prima Comunione',
            livello: 1,
            annoCatechistico: '2026-2027',
          ),
        );

        final cls = ClassesRepository().getClassesSync().firstWhere(
          (c) => c.id == 'c1',
        );
        final s = (await studentsRepo.getAllStudentsSync()).firstWhere(
          (st) => st.id == 's1',
        );

        final record = await ConcludiAnnoService().archiviaStudente(s, cls);

        expect(record.academicYear, '2026-2027');
        expect(HistoricalRecordRepository().count, 1);

        final archived = (await studentsRepo.getAllStudentsSync()).firstWhere(
          (st) => st.id == 's1',
        );
        expect(archived.statoPercorso, ConcludiAnnoService.statoArchiviato);
        expect(archived.classId, isNull);

        // Il ragazzo è stato rimosso dalla classe attiva.
        final updatedCls = ClassesRepository().getClassesSync().firstWhere(
          (c) => c.id == 'c1',
        );
        expect(updatedCls.studentIds, isNot(contains('s1')));
      },
    );
  });
}
