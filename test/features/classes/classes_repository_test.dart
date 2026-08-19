import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/classes/classes_repository.dart';
import 'package:CatechHub/shared/models/class_model.dart';
import 'package:CatechHub/shared/models/user_role.dart';

void main() {
  late Directory tempDir;

  group('ClassesRepository', () {
    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('hive_test_');
      Hive.init(tempDir.path);
      await Hive.openBox(LocalDatabase.authBox);
      await UserRole.setCurrent(UserRole.responsabile);
    });

    tearDown(() async {
      await Hive.deleteBoxFromDisk(LocalDatabase.classesBox);
      tempDir.deleteSync(recursive: true);
    });

    test(
      'removeCatechistFromClass rimuove il catechista dalla classe',
      () async {
        await Hive.openBox<Map>(LocalDatabase.classesBox);
        final repo = ClassesRepository();
        const classId = 'class_test_1';

        await repo.addClass(
          SchoolClass(
            id: classId,
            name: 'Classe Test',
            studentIds: [],
            catechistIds: ['cat_1', 'cat_2', 'cat_3'],
          ),
        );

        await repo.removeCatechistFromClass(classId, 'cat_2');

        final updated = repo.getClassesSync().firstWhere(
          (c) => c.id == classId,
        );
        expect(updated.catechistIds, ['cat_1', 'cat_3']);
        expect(updated.catechistIds, isNot(contains('cat_2')));
      },
    );

    test(
      'removeCatechistFromClass non modifica se il catechista non esiste',
      () async {
        await Hive.openBox<Map>(LocalDatabase.classesBox);
        final repo = ClassesRepository();
        const classId = 'class_test_2';

        await repo.addClass(
          SchoolClass(
            id: classId,
            name: 'Classe Test',
            studentIds: [],
            catechistIds: ['cat_1'],
          ),
        );

        await repo.removeCatechistFromClass(classId, 'cat_inesistente');

        final updated = repo.getClassesSync().firstWhere(
          (c) => c.id == classId,
        );
        expect(updated.catechistIds, ['cat_1']);
      },
    );

    test('removeCatechistFromClass non modifica altre classi', () async {
      await Hive.openBox<Map>(LocalDatabase.classesBox);
      final repo = ClassesRepository();

      await repo.addClass(
        SchoolClass(
          id: 'class_a',
          name: 'Classe A',
          studentIds: [],
          catechistIds: ['cat_1', 'cat_2'],
        ),
      );
      await repo.addClass(
        SchoolClass(
          id: 'class_b',
          name: 'Classe B',
          studentIds: [],
          catechistIds: ['cat_2', 'cat_3'],
        ),
      );

      await repo.removeCatechistFromClass('class_a', 'cat_2');

      final classA = repo.getClassesSync().firstWhere((c) => c.id == 'class_a');
      final classB = repo.getClassesSync().firstWhere((c) => c.id == 'class_b');

      expect(classA.catechistIds, ['cat_1']);
      expect(classB.catechistIds, ['cat_2', 'cat_3']);
    });

    test('addCatechistToClass aggiunge un catechista', () async {
      await Hive.openBox<Map>(LocalDatabase.classesBox);
      final repo = ClassesRepository();
      const classId = 'class_test_3';

      await repo.addClass(
        SchoolClass(
          id: classId,
          name: 'Classe Test',
          studentIds: [],
          catechistIds: ['cat_1'],
        ),
      );

      await repo.addCatechistToClass(classId, 'cat_2');

      final updated = repo.getClassesSync().firstWhere((c) => c.id == classId);
      expect(updated.catechistIds, ['cat_1', 'cat_2']);
    });

    test('addCatechistToClass non duplica catechista esistente', () async {
      await Hive.openBox<Map>(LocalDatabase.classesBox);
      final repo = ClassesRepository();
      const classId = 'class_test_4';

      await repo.addClass(
        SchoolClass(
          id: classId,
          name: 'Classe Test',
          studentIds: [],
          catechistIds: ['cat_1'],
        ),
      );

      await repo.addCatechistToClass(classId, 'cat_1');

      final updated = repo.getClassesSync().firstWhere((c) => c.id == classId);
      expect(updated.catechistIds, ['cat_1']);
    });

    test('renameClass cambia il nome conservando gli altri dati', () async {
      await Hive.openBox<Map>(LocalDatabase.classesBox);
      final repo = ClassesRepository();
      const classId = 'class_test_rename';

      await repo.addClass(
        SchoolClass(
          id: classId,
          name: 'Vecchio Nome',
          studentIds: ['s1', 's2'],
          catechistIds: ['cat_1', 'cat_2'],
          percorso: 'Prima Comunione',
          livello: 2,
          annoCatechistico: '2026-2027',
        ),
      );

      await repo.renameClass(classId, '  Nuovo Nome  ');

      final updated = repo.getClassesSync().firstWhere((c) => c.id == classId);
      expect(updated.name, 'Nuovo Nome');
      expect(updated.studentIds, ['s1', 's2']);
      expect(updated.catechistIds, ['cat_1', 'cat_2']);
      expect(updated.percorso, 'Prima Comunione');
      expect(updated.livello, 2);
    });

    test('renameClass ignora nomi vuoti o identici', () async {
      await Hive.openBox<Map>(LocalDatabase.classesBox);
      final repo = ClassesRepository();
      const classId = 'class_test_rename2';

      await repo.addClass(
        SchoolClass(
          id: classId,
          name: 'Nome Stabile',
          studentIds: [],
          catechistIds: [],
        ),
      );

      await repo.renameClass(classId, '   ');
      expect(
        repo.getClassesSync().firstWhere((c) => c.id == classId).name,
        'Nome Stabile',
      );

      await repo.renameClass(classId, 'Nome Stabile');
      expect(
        repo.getClassesSync().firstWhere((c) => c.id == classId).name,
        'Nome Stabile',
      );
    });
  });
}
