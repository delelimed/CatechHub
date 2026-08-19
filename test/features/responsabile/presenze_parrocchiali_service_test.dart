import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/classes/classes_repository.dart';
import 'package:CatechHub/features/responsabile/presenze_parrocchiali_service.dart';
import 'package:CatechHub/features/students/students_repository.dart';
import 'package:CatechHub/shared/models/class_model.dart';
import 'package:CatechHub/shared/models/student_model.dart';

Student _student(String id, String name, String surname) {
  return Student(
    id: id,
    name: name,
    surname: surname,
    birthDate: DateTime(2012, 1, 1),
    motherName: '',
    motherSurname: '',
    fatherName: '',
    fatherSurname: '',
    motherPhone: '',
    fatherPhone: '',
    studentPhone: '',
    classId: 'class_al_1',
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalDatabase.authBox);
    await Hive.openBox<Map>(LocalDatabase.classesBox);
    await Hive.openBox<Map>(LocalDatabase.studentsBox);
    await Hive.openBox<Map>(LocalDatabase.attendanceBox);
  });

  tearDown(() async {
    for (final box in [
      LocalDatabase.authBox,
      LocalDatabase.classesBox,
      LocalDatabase.studentsBox,
      LocalDatabase.attendanceBox,
    ]) {
      try {
        await Hive.deleteBoxFromDisk(box);
      } catch (_) {}
    }
    tempDir.deleteSync(recursive: true);
  });

  Future<void> setup() async {
    await ClassesRepository().addClass(
      SchoolClass(
        id: 'class_al_1',
        name: 'Prima Comunione',
        studentIds: ['al_1', 'al_2'],
        catechistIds: [],
      ),
    );
    final repo = StudentsRepository();
    await repo.addStudent(_student('al_1', 'Anna', 'Rossi'));
    await repo.addStudent(_student('al_2', 'Luca', 'Bianchi'));
  }

  group('PresenzeParrocchialiService.rilevaIstanza', () {
    test('nessun allarme sotto soglia', () async {
      await setup();
      await LocalDatabase.attendance().put('m1', {
        'classId': 'class_al_1',
        'date': '2026-10-01',
        'presence': {'al_1': 'Presente', 'al_2': 'Assente'},
      });

      final alerts = await PresenzeParrocchialiService().rilevaIstanza(
        threshold: 3,
      );
      expect(alerts, isEmpty);
    });

    test(
      'segnala il ragazzo con N assenze consecutive partendo dalla più recente',
      () async {
        await setup();
        final attendance = LocalDatabase.attendance();
        for (var i = 1; i <= 4; i++) {
          await attendance.put('m$i', {
            'classId': 'class_al_1',
            'date': '2026-10-0$i',
            'presence': {'al_2': (i <= 2) ? 'Presente' : 'Assente'},
          });
        }

        final alerts = await PresenzeParrocchialiService().rilevaIstanza(
          threshold: 2,
        );
        expect(alerts, isNotEmpty);
        final hit = alerts.firstWhere((a) => a.studentId == 'al_2');
        expect(hit.assenzeConsecutive, 2);
        expect(hit.totaleAssenze, 2);
        expect(hit.className, 'Prima Comunione');
      },
    );
  });
}
