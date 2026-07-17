// ============================================================================
// TEST: ContactNote Model
// Copre: serializzazione, deserializzazione, etichette medium
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/shared/models/contact_note_model.dart';

void main() {
  // ── Serializzazione ──
  group('Serializzazione ContactNote', () {
    test('toMap e fromMap sono reversibili', () {
      // Arrange: prepara una nota di contatto
      final original = ContactNote(
        id: 'cn1',
        studentId: 's1',
        dateTime: DateTime(2024, 6, 15, 10, 30),
        medium: 'whatsapp',
        notes: 'Chiamata con la madre per discutere del comportamento',
      );
      // Act: serializza e deserializza
      final map = original.toMap();
      final restored = ContactNote.fromMap('cn1', map);
      // Assert: i campi corrispondono
      expect(restored.studentId, 's1');
      expect(restored.medium, 'whatsapp');
      expect(restored.notes, 'Chiamata con la madre per discutere del comportamento');
    });

    test('fromMap gestisce campi mancanti con default', () {
      // Arrange: mappa vuota
      final map = <String, dynamic>{};
      // Act: deserializza
      final note = ContactNote.fromMap('cn2', map);
      // Assert: i campi hanno default sensati
      expect(note.studentId, '');
      expect(note.medium, 'de_visu');
      expect(note.notes, '');
    });
  });

  // ── Etichette medium ──
  group('ContactNote.mediumLabel', () {
    test('restituisce etichetta corretta per de_visu', () {
      // Act: richiedi l'etichetta per 'de_visu'
      final label = ContactNote.mediumLabel('de_visu');
      // Assert: deve restituire "De visu"
      expect(label, 'De visu');
    });

    test('restituisce etichetta corretta per whatsapp', () {
      // Act: richiedi l'etichetta per 'whatsapp'
      final label = ContactNote.mediumLabel('whatsapp');
      // Assert: deve restituire "WhatsApp"
      expect(label, 'WhatsApp');
    });

    test('restituisce etichetta corretta per cellulare', () {
      // Act: richiedi l'etichetta per 'cellulare'
      final label = ContactNote.mediumLabel('cellulare');
      // Assert: deve restituire "Cellulare"
      expect(label, 'Cellulare');
    });

    test('restituisce il valore originale per medium sconosciuto', () {
      // Act: richiedi l'etichetta per un valore non previsto
      final label = ContactNote.mediumLabel('email');
      // Assert: deve restituire il valore originale
      expect(label, 'email');
    });
  });
}
