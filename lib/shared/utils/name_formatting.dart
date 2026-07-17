// ══════════════════════════════════════════════════════════════════════════════
// name_formatting.dart — CatechHub (utility di normalizzazione nomi)
//
// Fornisce metodi statici per la formattazione coerente di nomi e
// cognomi all'interno dell'applicazione.
//
// CONTESTO PROGETTO:
//   I dati anagrafici degli studenti (nome, cognome, madre, padre)
//   vengono inseriti manualmente dai catechisti e possono arrivare in
//   formati inconsistenti: "mario rossi", "MARIO ROSSI", "  Mario  Rossi  ".
//   Questa utility normalizza tutti i nomi in formato "Title Case"
//   (es. "Mario Rossi") PRIMA del salvataggio in Hive, garantendo:
//   - Coerenza visiva in tutta l'app (dashboard, anagrafica, documenti)
//   - Ordinamento alfabetico corretto (sortedBySurname)
//   - Dati puliti per la sincronizzazione P2P Bluetooth
//
// USO (in students_repository.dart):
//   Student _normalize(Student student) => student.copyWith(
//     name: NameFormatting.capitalizeWords(student.name),
//     surname: NameFormatting.capitalizeWords(student.surname),
//     motherName: NameFormatting.capitalizeWords(student.motherName),
//     ...
//   );
//
// REGOLE:
//   - Prima lettera di ogni parola → maiuscola: "mARiO" → "Mario"
//   - Lettere successive → minuscole: "rOsSi" → "Rossi"
//   - Spazi multipli → singolo spazio: "  mario   rossi  " → "Mario Rossi"
//   - Stringa vuota → restituita invariata
//   - Parola singola di 1 carattere → uppercase: "a" → "A"
//
// NOTE:
//   - Non gestisce prefissi nobiliari (es. "d'Ambrosio", "De Luca") —
//     eventuali eccezioni vanno inserite manualmente dal catechista
//   - Si applica anche a motherName, motherSurname, fatherName,
//     fatherSurname (tutti i campi anagrafici testuali)
//
// TEST: test/shared/utils/name_formatting_test.dart (6 test cases)
// ══════════════════════════════════════════════════════════════════════════════

/// Formattazione nomi e cognomi (es. "mario rossi" → "Mario Rossi").
class NameFormatting {
  /// Capitalizza la prima lettera di ogni parola e converte il resto
  /// in minuscolo. Normalizza spazi multipli e trimma la stringa.
  static String capitalizeWords(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;

    return trimmed
        .split(RegExp(r'\s+'))
        .map((word) {
          if (word.isEmpty) return word;
          if (word.length == 1) return word.toUpperCase();
          return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
        })
        .join(' ');
  }
}
