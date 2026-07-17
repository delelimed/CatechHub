// ============================================================================
// TEST: Logica di Appello e Registro Presenze
// Copre: calcolo presenze, rilevamento assenze consecutive, flag avvisoRichiamo
// ============================================================================
import 'package:flutter_test/flutter_test.dart';

/// ── Modello semplificato per il test della logica di appello ──
/// Rappresenta una singola registrazione di presenza per un ragazzo
/// in una specifica data di riunione.
class PresenceRecord {
  final String studentId;
  final String meetingId;
  final DateTime date;
  final bool isPresent;

  const PresenceRecord({
    required this.studentId,
    required this.meetingId,
    required this.date,
    required this.isPresent,
  });
}

/// ── Classe che implementa la logica di business dell'appello ──
/// Calcola le assenze consecutive e determina se scattare l'avvisoRichiamo.
class AttendanceLogic {
  /// Calcola il numero di assenze consecutive alla fine di una lista
  /// di record di presenza ordinati per data.
  ///
  /// Se un ragazzo accumula 3 o piu assenze consecutive,
  /// il flag avvisoRichiamo deve attivarsi.
  static int calcolaAssenzeConsecutive(List<PresenceRecord> records) {
    if (records.isEmpty) return 0;

    // Ordina i record per data (piu recente prima)
    final sorted = List<PresenceRecord>.from(records)
      ..sort((a, b) => b.date.compareTo(a.date));

    var consecutiveAbsent = 0;
    for (final record in sorted) {
      if (!record.isPresent) {
        consecutiveAbsent++;
      } else {
        // Appena troviamo una presenza, interrompiamo il conteggio
        break;
      }
    }
    return consecutiveAbsent;
  }

  /// Determina se l'avvisoRichiamo deve attivarsi.
  /// Si attiva quando un ragazzo accumula 3 o piu assenze consecutive.
  static bool deveAttivareAvvisoRichiamo(List<PresenceRecord> records) {
    return calcolaAssenzeConsecutive(records) >= 3;
  }

  /// Calcola la percentuale di presenze su un insieme di record.
  static double calcolaPercentualePresenze(List<PresenceRecord> records) {
    if (records.isEmpty) return 0.0;
    final presenze = records.where((r) => r.isPresent).length;
    return presenze / records.length;
  }
}

void main() {
  // ══════════════════════════════════════════════════
  //  Calcolo Assenze Consecutive
  // ══════════════════════════════════════════════════
  group('Calcolo Assenze Consecutive', () {
    test('restituisce 0 se non ci sono record', () {
      // Arrange: lista vuota
      final records = <PresenceRecord>[];
      // Act: calcola le assenze consecutive
      final result = AttendanceLogic.calcolaAssenzeConsecutive(records);
      // Assert: deve restituire 0
      expect(result, 0);
    });

    test('restituisce 1 per una singola assenza', () {
      // Arrange: un solo record di assenza
      final records = [
        PresenceRecord(
          studentId: 's1',
          meetingId: 'm1',
          date: DateTime(2024, 6, 1),
          isPresent: false,
        ),
      ];
      // Act: calcola
      final result = AttendanceLogic.calcolaAssenzeConsecutive(records);
      // Assert: deve restituire 1
      expect(result, 1);
    });

    test('restituisce 3 per tre assenze consecutive', () {
      // Arrange: tre assenze consecutive (ordinati per data decrescente)
      final records = [
        PresenceRecord(
          studentId: 's1',
          meetingId: 'm3',
          date: DateTime(2024, 6, 15),
          isPresent: false,
        ),
        PresenceRecord(
          studentId: 's1',
          meetingId: 'm2',
          date: DateTime(2024, 6, 8),
          isPresent: false,
        ),
        PresenceRecord(
          studentId: 's1',
          meetingId: 'm1',
          date: DateTime(2024, 6, 1),
          isPresent: false,
        ),
      ];
      // Act: calcola
      final result = AttendanceLogic.calcolaAssenzeConsecutive(records);
      // Assert: deve restituire 3
      expect(result, 3);
    });

    test('si ferma alla prima presenza trovata (non consecutiva)', () {
      // Arrange: pattern Presenza-Assenza-Assenza-Assenza
      // Le assenze consecutive partono dalla data piu recente
      final records = [
        PresenceRecord(
          studentId: 's1',
          meetingId: 'm4',
          date: DateTime(2024, 6, 22),
          isPresent: true, // presente oggi
        ),
        PresenceRecord(
          studentId: 's1',
          meetingId: 'm3',
          date: DateTime(2024, 6, 15),
          isPresent: false,
        ),
        PresenceRecord(
          studentId: 's1',
          meetingId: 'm2',
          date: DateTime(2024, 6, 8),
          isPresent: false,
        ),
        PresenceRecord(
          studentId: 's1',
          meetingId: 'm1',
          date: DateTime(2024, 6, 1),
          isPresent: false,
        ),
      ];
      // Act: calcola (conta le assenze piu recenti prima)
      final result = AttendanceLogic.calcolaAssenzeConsecutive(records);
      // Assert: essendo il primo record una presenza, le assenze consecutive sono 0
      // (la lista e ordinata per data decrescente, il primo e il piu recente)
      expect(result, 0);
    });

    test('conta assenze dalla fine (dati piu recenti)', () {
      // Arrange: Assenza-Assenza-Presenza-Assenza
      // Le ultime 2 sono consecutive
      final records = [
        PresenceRecord(
          studentId: 's1',
          meetingId: 'm4',
          date: DateTime(2024, 6, 22),
          isPresent: false,
        ),
        PresenceRecord(
          studentId: 's1',
          meetingId: 'm3',
          date: DateTime(2024, 6, 15),
          isPresent: false,
        ),
        PresenceRecord(
          studentId: 's1',
          meetingId: 'm2',
          date: DateTime(2024, 6, 8),
          isPresent: true,
        ),
        PresenceRecord(
          studentId: 's1',
          meetingId: 'm1',
          date: DateTime(2024, 6, 1),
          isPresent: false,
        ),
      ];
      // Act: calcola (le 2 assenze piu recenti sono consecutive)
      final result = AttendanceLogic.calcolaAssenzeConsecutive(records);
      // Assert: deve restituire 2
      expect(result, 2);
    });
  });

  // ══════════════════════════════════════════════════
  //  AvvisoRichiamo (Flag Rettivo)
  // ══════════════════════════════════════════════════
  group('AvvisoRichiamo - Flag Rettivo', () {
    test('si attiva con 3 assenze consecutive', () {
      // Arrange: 3 assenze consecutive
      final records = [
        PresenceRecord(
          studentId: 's1', meetingId: 'm3',
          date: DateTime(2024, 6, 15), isPresent: false,
        ),
        PresenceRecord(
          studentId: 's1', meetingId: 'm2',
          date: DateTime(2024, 6, 8), isPresent: false,
        ),
        PresenceRecord(
          studentId: 's1', meetingId: 'm1',
          date: DateTime(2024, 6, 1), isPresent: false,
        ),
      ];
      // Act: verifica se l'avviso deve attivarsi
      final attivare = AttendanceLogic.deveAttivareAvvisoRichiamo(records);
      // Assert: deve essere true (>= 3 assenze)
      expect(attivare, isTrue);
    });

    test('NON si attiva con 2 assenze consecutive', () {
      // Arrange: 2 assenze consecutive seguite da una presenza
      final records = [
        PresenceRecord(
          studentId: 's1', meetingId: 'm3',
          date: DateTime(2024, 6, 15), isPresent: false,
        ),
        PresenceRecord(
          studentId: 's1', meetingId: 'm2',
          date: DateTime(2024, 6, 8), isPresent: false,
        ),
        PresenceRecord(
          studentId: 's1', meetingId: 'm1',
          date: DateTime(2024, 6, 1), isPresent: true,
        ),
      ];
      // Act: verifica
      final attivare = AttendanceLogic.deveAttivareAvvisoRichiamo(records);
      // Assert: deve essere false (< 3 assenze)
      expect(attivare, isFalse);
    });

    test('si attiva con 4 o piu assenze consecutive', () {
      // Arrange: 4 assenze consecutive
      final records = List.generate(
        4,
        (i) => PresenceRecord(
          studentId: 's1',
          meetingId: 'm${i + 1}',
          date: DateTime(2024, 6, 1).add(Duration(days: i * 7)),
          isPresent: false,
        ),
      );
      // Act: verifica
      final attivare = AttendanceLogic.deveAttivareAvvisoRichiamo(records);
      // Assert: deve essere true
      expect(attivare, isTrue);
    });

    test('si attiva anche con assenze non ordinate cronologicamente', () {
      // Arrange: 3 assenze con date in ordine sparso
      final records = [
        PresenceRecord(
          studentId: 's1', meetingId: 'm3',
          date: DateTime(2024, 6, 1), isPresent: false,
        ),
        PresenceRecord(
          studentId: 's1', meetingId: 'm1',
          date: DateTime(2024, 6, 15), isPresent: false,
        ),
        PresenceRecord(
          studentId: 's1', meetingId: 'm2',
          date: DateTime(2024, 6, 8), isPresent: false,
        ),
      ];
      // Act: verifica (l'algoritmo ordina internamente)
      final attivare = AttendanceLogic.deveAttivareAvvisoRichiamo(records);
      // Assert: deve essere true (3 assenze totali)
      expect(attivare, isTrue);
    });
  });

  // ══════════════════════════════════════════════════
  //  Percentuale Presenze
  // ══════════════════════════════════════════════════
  group('Percentuale Presenze', () {
    test('calcola 100% con tutte presenze', () {
      // Arrange: tutti presenti
      final records = List.generate(
        5,
        (i) => PresenceRecord(
          studentId: 's1',
          meetingId: 'm${i + 1}',
          date: DateTime(2024, 6, 1).add(Duration(days: i * 7)),
          isPresent: true,
        ),
      );
      // Act: calcola percentuale
      final percent = AttendanceLogic.calcolaPercentualePresenze(records);
      // Assert: deve essere 1.0 (100%)
      expect(percent, 1.0);
    });

    test('calcola 0% con tutte assenze', () {
      // Arrange: tutti assenti
      final records = List.generate(
        3,
        (i) => PresenceRecord(
          studentId: 's1',
          meetingId: 'm${i + 1}',
          date: DateTime(2024, 6, 1).add(Duration(days: i * 7)),
          isPresent: false,
        ),
      );
      // Act: calcola
      final percent = AttendanceLogic.calcolaPercentualePresenze(records);
      // Assert: deve essere 0.0
      expect(percent, 0.0);
    });

    test('calcola percentuale mista correttamente', () {
      // Arrange: 2 presenti su 4 totali
      final records = [
        PresenceRecord(studentId: 's1', meetingId: 'm1', date: DateTime(2024, 6, 1), isPresent: true),
        PresenceRecord(studentId: 's1', meetingId: 'm2', date: DateTime(2024, 6, 8), isPresent: false),
        PresenceRecord(studentId: 's1', meetingId: 'm3', date: DateTime(2024, 6, 15), isPresent: true),
        PresenceRecord(studentId: 's1', meetingId: 'm4', date: DateTime(2024, 6, 22), isPresent: false),
      ];
      // Act: calcola
      final percent = AttendanceLogic.calcolaPercentualePresenze(records);
      // Assert: deve essere 0.5 (50%)
      expect(percent, 0.5);
    });

    test('restituisce 0 con lista vuota', () {
      // Act/Assert: lista vuota -> 0%
      expect(AttendanceLogic.calcolaPercentualePresenze([]), 0.0);
    });
  });
}
