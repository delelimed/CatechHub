import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/classes/classes_repository.dart';
import 'package:CatechHub/features/responsabile/aula_repository.dart';
import 'package:CatechHub/shared/models/aula.dart';
import 'package:CatechHub/shared/models/class_model.dart';
import 'package:CatechHub/shared/models/user_role.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalDatabase.authBox);
    await Hive.openBox<Map>(LocalDatabase.classesBox);
    await Hive.openBox<Map>(LocalDatabase.aulaBox);
    await UserRole.setCurrent(UserRole.responsabile);
  });

  tearDown(() async {
    for (final box in [
      LocalDatabase.authBox,
      LocalDatabase.classesBox,
      LocalDatabase.aulaBox,
    ]) {
      try {
        await Hive.deleteBoxFromDisk(box);
      } catch (_) {}
    }
    tempDir.deleteSync(recursive: true);
  });

  group('AulaRepository', () {
    test('saveAula persiste l\'aula e la ritrova in sync', () async {
      final repo = AulaRepository();
      await repo.saveAula(
        Aula(
          stanzaId: 'stanza_1',
          nomeStanza: 'Aula Magna',
          capienzaMassima: 24,
        ),
      );

      final saved = repo.getAula('stanza_1');
      expect(saved, isNotNull);
      expect(saved!.nomeStanza, 'Aula Magna');
      expect(saved.capienzaMassima, 24);
    });

    test(
      'deleteAula rimuove l\'aula e pulisce gli slot dalle classi',
      () async {
        final repo = AulaRepository();
        await repo.saveAula(Aula(stanzaId: 'stanza_a', nomeStanza: 'Aula A'));

        await ClassesRepository().addClass(
          SchoolClass(
            id: 'class_slot_1',
            name: 'Sala',
            studentIds: [],
            catechistIds: [],
            roomSlots: [
              RoomSlot(
                slotId: 'slot_a',
                stanzaId: 'stanza_a',
                nomeStanza: 'Aula A',
                giornoSettimana: 6,
                oraInizio: '15:00',
                oraFine: '16:30',
              ),
            ],
          ),
        );

        await repo.deleteAula('stanza_a');

        expect(repo.getAula('stanza_a'), isNull);

        final updated = ClassesRepository().getClassesSync().firstWhere(
          (c) => c.id == 'class_slot_1',
        );
        expect(updated.roomSlots, isEmpty);
      },
    );
  });
}
