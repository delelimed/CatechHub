// ============================================================================
// TEST: NameFormatting Utility
// Copre: capitalizzazione parole, gestione spazi, stringhe vuote
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/shared/utils/name_formatting.dart';

void main() {
  // ── Capitalizzazione ──
  group('NameFormatting.capitalizeWords', () {
    test('capitalizza la prima lettera di ogni parola', () {
      // Arrange: stringa tutto minuscolo
      final input = 'mario rossi';
      // Act: applica la formattazione
      final result = NameFormatting.capitalizeWords(input);
      // Assert: ogni parola inizia con maiuscola
      expect(result, 'Mario Rossi');
    });

    test('mette in minuscolo le lettere successive', () {
      // Arrange: stringa con maiuscole casuali
      final input = 'mARiO rOsSi';
      // Act: formatta
      final result = NameFormatting.capitalizeWords(input);
      // Assert: solo la prima lettera e maiuscola
      expect(result, 'Mario Rossi');
    });

    test('gestisce stringhe con spazi multipli', () {
      // Arrange: stringa con spazi multipli
      final input = '  mario   rossi  ';
      // Act: formatta (trim + gestione spazi)
      final result = NameFormatting.capitalizeWords(input);
      // Assert: spazi multipli ridotti a singolo spazio
      expect(result, 'Mario Rossi');
    });

    test('restituisce stringa vuota per input vuoto', () {
      // Arrange: stringa vuota
      final input = '';
      // Act: formatta
      final result = NameFormatting.capitalizeWords(input);
      // Assert: restituisce stringa vuota
      expect(result, '');
    });

    test('gestisce una singola lettera', () {
      // Arrange: una singola lettera
      final input = 'a';
      // Act: formatta
      final result = NameFormatting.capitalizeWords(input);
      // Assert: la lettera deve essere maiuscola
      expect(result, 'A');
    });

    test('gestisce nomi con tre o piu parole', () {
      // Arrange: nome con tre parole
      final input = 'mario luigi rossi';
      // Act: formatta
      final result = NameFormatting.capitalizeWords(input);
      // Assert: tutte le parole capitalizzate
      expect(result, 'Mario Luigi Rossi');
    });
  });
}
