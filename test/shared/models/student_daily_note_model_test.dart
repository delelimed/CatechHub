// ============================================================================
// TEST: StudentDailyNote Model
// Copre: serializzazione, deserializzazione, copyWith
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/shared/models/student_daily_note_model.dart';

void main() {
  // ── Serializzazione ──
  group('Serializzazione StudentDailyNote', () {
    test('toMap e fromMap sono reversibili', () {
      // Arrange: prepara una nota giornaliera
      final now = DateTime(2024, 6, 15, 14, 30);
      final original = StudentDailyNote(
        id: 'sdn1',
        studentId: 's1',
        meetingId: 'm1',
        text: 'Oggi ha partecipato attivamente alla lezione',
        createdAt: now,
        updatedAt: now,
      );
      // Act: serializza e deserializza
      final map = original.toMap();
      final restored = StudentDailyNote.fromMap('sdn1', map);
      // Assert: i campi corrispondono
      expect(restored.studentId, 's1');
      expect(restored.meetingId, 'm1');
      expect(restored.text, 'Oggi ha partecipato attivamente alla lezione');
    });

    test('fromMap gestisce campi mancanti', () {
      // Arrange: mappa vuota
      final map = <String, dynamic>{};
      // Act: deserializza
      final note = StudentDailyNote.fromMap('sdn2', map);
      // Assert: valori di default
      expect(note.studentId, '');
      expect(note.meetingId, '');
      expect(note.text, '');
    });
  });

  // ── copyWith ──
  group('StudentDailyNote.copyWith', () {
    test('crea una copia con testo aggiornato', () {
      // Arrange: crea una nota
      final original = StudentDailyNote(
        id: 'sdn1',
        studentId: 's1',
        meetingId: 'm1',
        text: 'Testo originale',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );
      // Act: modifica il testo
      final copy = original.copyWith(text: 'Testo aggiornato');
      // Assert: solo il testo e cambiato
      expect(copy.text, 'Testo aggiornato');
      expect(copy.studentId, 's1');
      expect(copy.id, 'sdn1');
    });
  });
}
