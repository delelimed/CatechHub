import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/services/field_encryption_service.dart';
import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/responsabile/import_ragazzi/import_ragazzi_models.dart';
import 'package:CatechHub/features/responsabile/import_ragazzi/import_ragazzi_service.dart';
import 'package:CatechHub/features/students/students_repository.dart';
import 'package:CatechHub/shared/models/student_model.dart';

Student _student(String id, String name, String surname, {DateTime? birth}) {
  return Student(
    id: id,
    name: name,
    surname: surname,
    birthDate: birth ?? DateTime(2012, 1, 1),
    motherName: '',
    motherSurname: '',
    fatherName: '',
    fatherSurname: '',
    motherPhone: '',
    fatherPhone: '',
    studentPhone: '',
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalDatabase.authBox);
    await Hive.openBox<Map>(LocalDatabase.studentsBox);
    await Hive.openBox<Map>(LocalDatabase.auditLogBox);
    FieldEncryptionService.debugSecretOverride = 'test-secret';
  });

  tearDown(() async {
    FieldEncryptionService.debugSecretOverride = null;
    for (final box in [
      LocalDatabase.authBox,
      LocalDatabase.studentsBox,
      LocalDatabase.auditLogBox,
    ]) {
      try {
        await Hive.deleteBoxFromDisk(box);
      } catch (_) {}
    }
    tempDir.deleteSync(recursive: true);
  });

  group('ImportRagazziService - mappatura', () {
    test('autoMapHeaders riconosce le intestazioni italiane', () {
      final service = ImportRagazziService();
      final mapping = service.autoMapHeaders(const [
        'Nome',
        'Cognome',
        'Data di nascita',
        'Nome madre',
        'Cognome madre',
        'Nome padre',
        'Cognome padre',
        'Telefono madre',
        'Telefono padre',
        'Email genitore',
        'Note mediche / allergie',
        'Note libere',
      ]);
      expect(mapping[0], ImportField.nome);
      expect(mapping[1], ImportField.cognome);
      expect(mapping[2], ImportField.dataNascita);
      expect(mapping[10], ImportField.noteMediche);
      expect(mapping, hasLength(12));
      expect(service.missingRequired(mapping), isEmpty);
    });

    test('autoMapHeaders riconosce alias in inglese', () {
      final service = ImportRagazziService();
      final mapping = service.autoMapHeaders(const [
        'First Name',
        'Last Name',
        'Birth Date',
      ]);
      expect(mapping[0], ImportField.nome);
      expect(mapping[1], ImportField.cognome);
      expect(mapping[2], ImportField.dataNascita);
    });

    test('missingRequired segnala i campi obbligatori assenti', () {
      final service = ImportRagazziService();
      final mapping = service.autoMapHeaders(const ['Nome', 'Cognome']);
      final missing = service.missingRequired(mapping);
      expect(missing, contains(ImportField.dataNascita));
    });
  });

  group('ImportRagazziService - validazione', () {
    test('normalizza nome, data e telefono', () {
      final service = ImportRagazziService();
      final mapping = {
        0: ImportField.nome,
        1: ImportField.cognome,
        2: ImportField.dataNascita,
        3: ImportField.telefonoMadre,
      };
      final rows = service.buildRows([
        ['luca', 'bianchi', '10/05/2012', '+39 333 1234567'],
      ], mapping);
      final row = rows.single;
      expect(row.status, ImportRowStatus.valid);
      expect(row.values['name'], 'Luca');
      expect(row.values['surname'], 'Bianchi');
      expect(row.values['birthDate'], '2012-05-10');
      expect(row.values['motherPhone'], '+393331234567');
    });

    test('segna errore per data non valida', () {
      final service = ImportRagazziService();
      final mapping = {
        0: ImportField.nome,
        1: ImportField.cognome,
        2: ImportField.dataNascita,
      };
      final rows = service.buildRows([
        ['Luca', 'Bianchi', '31/02/2012'],
      ], mapping);
      expect(rows.single.status, ImportRowStatus.error);
      expect(rows.single.errors, isNotEmpty);
    });

    test('segna errore per campo obbligatorio mancante', () {
      final service = ImportRagazziService();
      final mapping = {
        0: ImportField.nome,
        1: ImportField.cognome,
        2: ImportField.dataNascita,
      };
      final rows = service.buildRows([
        ['Luca', '', '10/05/2012'],
      ], mapping);
      expect(rows.single.status, ImportRowStatus.error);
      expect(rows.single.errors, isNotEmpty);
    });
  });

  group('ImportRagazziService - deduplica', () {
    test('identifica un duplicato per nome+cognome+data nascita', () async {
      final repo = StudentsRepository();
      await repo.addStudent(_student('s1', 'Luca', 'Bianchi'));
      final service = ImportRagazziService(students: repo);

      final mapping = {
        0: ImportField.nome,
        1: ImportField.cognome,
        2: ImportField.dataNascita,
      };
      final rows = service.buildRows([
        ['luca', 'bianchi', '01/01/2012'],
      ], mapping);
      final checked = await service.detectDuplicates(rows);

      expect(checked.single.status, ImportRowStatus.duplicate);
      expect(checked.single.existing, isNotNull);
    });

    test('lascia valida una riga con identità diversa', () async {
      final repo = StudentsRepository();
      await repo.addStudent(_student('s1', 'Luca', 'Bianchi'));
      final service = ImportRagazziService(students: repo);

      final mapping = {
        0: ImportField.nome,
        1: ImportField.cognome,
        2: ImportField.dataNascita,
      };
      final rows = service.buildRows([
        ['Maria', 'Rossi', '01/01/2012'],
      ], mapping);
      final checked = await service.detectDuplicates(rows);

      expect(checked.single.status, ImportRowStatus.valid);
    });

    test('importRows applica azione ignore sui duplicati', () async {
      final repo = StudentsRepository();
      await repo.addStudent(_student('s1', 'Luca', 'Bianchi'));
      final service = ImportRagazziService(students: repo);

      final mapping = {
        0: ImportField.nome,
        1: ImportField.cognome,
        2: ImportField.dataNascita,
      };
      final rows = service.buildRows([
        ['luca', 'bianchi', '01/01/2012'],
      ], mapping);
      final checked = await service.detectDuplicates(rows);

      final report = await service.importRows(checked);
      expect(report.imported, 0);
      expect(report.duplicatesIgnored, 1);
      expect(await repo.getAllStudentsSync(), hasLength(1));
    });

    test('importRows crea nuovo record con azione createNew', () async {
      final repo = StudentsRepository();
      await repo.addStudent(_student('s1', 'Luca', 'Bianchi'));
      final service = ImportRagazziService(students: repo);

      final mapping = {
        0: ImportField.nome,
        1: ImportField.cognome,
        2: ImportField.dataNascita,
      };
      final rows = service.buildRows([
        ['luca', 'bianchi', '01/01/2012'],
      ], mapping);
      final checked = (await service.detectDuplicates(
        rows,
      )).map((r) => r.copyWith(action: DuplicateAction.createNew)).toList();

      final report = await service.importRows(checked);
      expect(report.imported, 1);
      expect(await repo.getAllStudentsSync(), hasLength(2));
    });
  });
}
