// ============================================================================
// TEST: Logica del Conteggio Rapido
// Copre: filtro per data, filtro per classi, conteggio presenti, completezza
// ============================================================================
import 'package:flutter_test/flutter_test.dart';

import 'package:CatechHub/features/classes/quick_count_logic.dart';

/// Costruisce un record di appello nel formato della box `attendance` Hive.
Map<String, dynamic> record({
  required String date,
  required String classId,
  required Map<String, String> presence,
}) {
  return {'date': date, 'classId': classId, 'presence': presence};
}

void main() {
  // ══════════════════════════════════════════════════
  //  isSameDay
  // ══════════════════════════════════════════════════
  group('isSameDay', () {
    test('true per date dello stesso giorno a ore diverse', () {
      final a = DateTime(2026, 8, 4, 9);
      final b = DateTime(2026, 8, 4, 20);
      expect(QuickCountLogic.isSameDay(a, b), isTrue);
    });

    test('false per giorni diversi', () {
      final a = DateTime(2026, 8, 4);
      final b = DateTime(2026, 8, 5);
      expect(QuickCountLogic.isSameDay(a, b), isFalse);
    });

    test('false per mesi diversi', () {
      final a = DateTime(2026, 7, 4);
      final b = DateTime(2026, 8, 4);
      expect(QuickCountLogic.isSameDay(a, b), isFalse);
    });
  });

  // ══════════════════════════════════════════════════
  //  recordsOnDate
  // ══════════════════════════════════════════════════
  group('recordsOnDate', () {
    test('filtra solo i record del giorno richiesto', () {
      final records = [
        record(date: '2026-08-04T18:00:00.000', classId: 'c1', presence: {}),
        record(date: '2026-08-03T18:00:00.000', classId: 'c1', presence: {}),
        record(date: '2026-08-04T19:30:00.000', classId: 'c2', presence: {}),
      ];
      final result = QuickCountLogic.recordsOnDate(
        records,
        DateTime(2026, 8, 4),
      );
      expect(result.length, 2);
    });

    test('restituisce lista vuota senza record per quella data', () {
      final records = [
        record(date: '2026-08-03T18:00:00.000', classId: 'c1', presence: {}),
      ];
      final result = QuickCountLogic.recordsOnDate(
        records,
        DateTime(2026, 8, 4),
      );
      expect(result, isEmpty);
    });

    test('ignora record con data non valida', () {
      final records = [
        {'date': 'non-una-data', 'classId': 'c1', 'presence': <String, String>{}},
      ];
      final result = QuickCountLogic.recordsOnDate(
        records,
        DateTime(2026, 8, 4),
      );
      expect(result, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════
  //  recordsOfClasses
  // ══════════════════════════════════════════════════
  group('recordsOfClasses', () {
    test('filtra per una o più classi selezionate', () {
      final records = [
        record(date: '2026-08-04', classId: 'c1', presence: {}),
        record(date: '2026-08-04', classId: 'c2', presence: {}),
        record(date: '2026-08-04', classId: 'c3', presence: {}),
      ];
      final result = QuickCountLogic.recordsOfClasses(records, {'c1', 'c3'});
      expect(result.length, 2);
      expect(result.every((r) => r['classId'] != 'c2'), isTrue);
    });

    test('lista vuota se nessun record appartiene alle classi', () {
      final records = [
        record(date: '2026-08-04', classId: 'c1', presence: {}),
      ];
      final result = QuickCountLogic.recordsOfClasses(records, {'c9'});
      expect(result, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════
  //  presentCount e totalPresentCount
  // ══════════════════════════════════════════════════
  group('presentCount', () {
    test('conta solo i Presente', () {
      final r = record(date: '2026-08-04', classId: 'c1', presence: {
        's1': 'Presente',
        's2': 'Assente',
        's3': 'Assente',
        's4': 'Presente',
      });
      expect(QuickCountLogic.presentCount(r), 2);
    });

    test('restituisce 0 se non ci sono Presente', () {
      final r = record(date: '2026-08-04', classId: 'c1', presence: {
        's1': 'Assente',
        's2': 'Assente',
      });
      expect(QuickCountLogic.presentCount(r), 0);
    });

    test('tollera mappa di presenza mancante o vuota', () {
      expect(QuickCountLogic.presentCount({'date': 'x', 'classId': 'c1'}), 0);
      expect(
        QuickCountLogic.presentCount(
          record(date: '2026-08-04', classId: 'c1', presence: {}),
        ),
        0,
      );
    });
  });

  group('totalPresentCount', () {
    test('somma i presenti di più record (multi-classe)', () {
      final records = [
        record(date: '2026-08-04', classId: 'c1', presence: {
          's1': 'Presente',
          's2': 'Presente',
        }),
        record(date: '2026-08-04', classId: 'c2', presence: {
          's3': 'Presente',
          's4': 'Assente',
        }),
      ];
      expect(QuickCountLogic.totalPresentCount(records), 3);
    });

    test('restituisce 0 con lista vuota', () {
      expect(QuickCountLogic.totalPresentCount([]), 0);
    });
  });

  // ══════════════════════════════════════════════════
  //  presentStudentIds
  // ══════════════════════════════════════════════════
  group('presentStudentIds', () {
    test('estrae gli id dei soli presenti', () {
      final records = [
        record(date: '2026-08-04', classId: 'c1', presence: {
          's1': 'Presente',
          's2': 'Assente',
        }),
        record(date: '2026-08-04', classId: 'c2', presence: {
          's3': 'Presente',
        }),
      ];
      expect(
        QuickCountLogic.presentStudentIds(records),
        unorderedEquals({'s1', 's3'}),
      );
    });

    test('senza duplicati tra record diversi', () {
      final records = [
        record(date: '2026-08-04', classId: 'c1', presence: {'s1': 'Presente'}),
        record(date: '2026-08-04', classId: 'c2', presence: {'s1': 'Presente'}),
      ];
      expect(QuickCountLogic.presentStudentIds(records), {'s1'});
    });
  });

  // ══════════════════════════════════════════════════
  //  isComplete
  // ══════════════════════════════════════════════════
  group('isComplete', () {
    test('true se il conteggio coincide con i presenti', () {
      expect(QuickCountLogic.isComplete(12, 12), isTrue);
    });

    test('false se c\'è una discrepanza', () {
      expect(QuickCountLogic.isComplete(11, 12), isFalse);
      expect(QuickCountLogic.isComplete(13, 12), isFalse);
    });

    test('false con zero presente e conteggio positivo', () {
      expect(QuickCountLogic.isComplete(1, 0), isFalse);
    });
  });
}
