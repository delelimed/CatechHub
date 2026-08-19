import 'package:flutter_test/flutter_test.dart';

import 'package:CatechHub/features/responsabile/slot_conflict_service.dart';
import 'package:CatechHub/shared/models/aula.dart';
import 'package:CatechHub/shared/models/class_model.dart';

SchoolClass _cls(
  String id,
  String name, {
  List<RoomSlot> slots = const [],
  List<String> students = const [],
}) {
  return SchoolClass(
    id: id,
    name: name,
    studentIds: students,
    catechistIds: const [],
    roomSlots: slots,
  );
}

RoomSlot _slot(
  String slotId,
  String stanzaId, {
  int giorno = 6,
  String inizio = '15:00',
  String fine = '16:30',
}) {
  return RoomSlot(
    slotId: slotId,
    stanzaId: stanzaId,
    nomeStanza: 'Aula Test',
    giornoSettimana: giorno,
    oraInizio: inizio,
    oraFine: fine,
  );
}

Aula _aula(String stanzaId, {int capienza = 0}) {
  return Aula(
    nomeStanza: 'Aula Test',
    stanzaId: stanzaId,
    capienzaMassima: capienza,
  );
}

void main() {
  group('SlotConflictService.findConflicts', () {
    test('nessun conflitto se aule/giorni differenti', () {
      final classB = _cls(
        'b',
        'Cresima A',
        slots: [_slot('s1', 'stanza_1', giorno: 1)],
      );
      final conflicts = SlotConflictService.findConflicts(
        target: classB,
        newSlot: _slot('s2', 'stanza_2', giorno: 7),
        allClasses: [classB],
        aulas: const [],
      );
      expect(conflicts, isEmpty);
    });

    test(
      'conflitto interno: la classe ha già un impegno nello stesso orario',
      () {
        final classB = _cls(
          'b',
          'Cresima A',
          slots: [_slot('s1', 'Stanza_1', giorno: 1)],
        );
        final conflicts = SlotConflictService.findConflicts(
          target: classB,
          newSlot: _slot('s2', 'Stanza_1', giorno: 1),
          allClasses: [classB],
          aulas: [_aula('Stanza_1')],
        );
        expect(conflicts, isNotEmpty);
        final internal = conflicts.firstWhere((c) => c.classB == null);
        expect(internal.message, contains('Conflitto interno'));
      },
    );

    test(
      'conflitto tra classi: stessa aula, stesso giorno, orario sovrapposto',
      () {
        final classA = _cls('a', 'Cresima A');
        final classB = _cls(
          'b',
          'Comunione B',
          slots: [_slot('s1', 'Stanza_1', giorno: 1)],
        );
        final conflicts = SlotConflictService.findConflicts(
          target: classA,
          newSlot: _slot('s2', 'Stanza_1', giorno: 1),
          allClasses: [classA, classB],
          aulas: [_aula('Stanza_1')],
        );
        expect(conflicts, isNotEmpty);
        final cross = conflicts.firstWhere((c) => c.classB != null);
        expect(cross.message, contains('già occupata'));
        expect(cross.classA.name, 'Comunione B');
      },
    );

    test('warning capienza se la classe supera la capienza dell\'aula', () {
      final classA = _cls(
        'a',
        'Classe Numerosa',
        students: List.generate(12, (i) => 's$i'),
      );
      final conflicts = SlotConflictService.findConflicts(
        target: classA,
        newSlot: _slot('s2', 'Stanza_1', giorno: 1),
        allClasses: [classA],
        aulas: [_aula('Stanza_1', capienza: 10)],
      );
      expect(conflicts, isNotEmpty);
      expect(conflicts.first.message, contains('capienza massima'));
    });
  });

  test('RoomSlot.overlaps rileva sovrapposizioni di orario', () {
    expect(
      _slot(
        'a',
        's',
        inizio: '15:00',
        fine: '16:00',
      ).overlaps(_slot('b', 's', inizio: '15:30', fine: '16:30')),
      isTrue,
    );
    expect(
      _slot(
        'a',
        's',
        giorno: 1,
        inizio: '15:00',
        fine: '16:00',
      ).overlaps(_slot('b', 's', giorno: 2, inizio: '15:30', fine: '16:30')),
      isFalse,
    );
  });
}
