// ══════════════════════════════════════════════════════════════════════════════
// csv_parser.dart — CatechHub (parser CSV robusto per l'importazione massiva)
//
// Gestisce: BOM UTF-8, delimitatori comma/punto e virgola, campi tra virgolette
// ("" di escape), CRLF/LF, righe con lunghezza variabile. Ritorna una tabella
// grezza (List<List<String>>) e una lista di errori per le righe malformate.
// ══════════════════════════════════════════════════════════════════════════════

/// Risultato del parsing CSV: tabella grezza + intestazioni rilevate.
class CsvParseResult {
  /// Prima riga (intestazioni) oppure null se il file è vuoto.
  final List<String>? headers;

  /// Righe di dati (escluse le intestazioni).
  final List<List<String>> rows;

  /// Errori di parsing per riga (numero riga 1-based → messaggio).
  final List<CsvRowError> errors;

  const CsvParseResult({
    required this.headers,
    required this.rows,
    required this.errors,
  });
}

class CsvRowError {
  final int rowNumber;
  final String message;
  const CsvRowError(this.rowNumber, this.message);
}

class CsvParser {
  const CsvParser();

  /// Rimuove la BOM UTF-8 se presente.
  static String _stripBom(String content) {
    if (content.startsWith('\uFEFF')) return content.substring(1);
    return content;
  }

  /// Rileva il delimitatore più frequente tra comma e punto e virgola
  /// analizzando la prima riga fuori dalle virgolette.
  static String _detectDelimiter(String firstLine) {
    var inQuotes = false;
    var commas = 0;
    var semicolons = 0;
    for (var i = 0; i < firstLine.length; i++) {
      final ch = firstLine[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes) {
        if (ch == ',') commas++;
        if (ch == ';') semicolons++;
      }
    }
    return semicolons > commas ? ';' : ',';
  }

  /// Parsea il contenuto CSV in una tabella grezza.
  CsvParseResult parse(String rawContent) {
    final content = _stripBom(rawContent);
    if (content.trim().isEmpty) {
      return const CsvParseResult(headers: null, rows: [], errors: []);
    }

    final delimiter = _detectDelimiter(content.split('\n').first);

    final rows = <List<String>>[];
    final errors = <CsvRowError>[];

    var field = StringBuffer();
    final row = <String>[];
    var inQuotes = false;

    void endField() {
      row.add(field.toString());
      field = StringBuffer();
    }

    void endRow() {
      endField();
      rows.add(List.of(row));
      row.clear();
    }

    for (var i = 0; i < content.length; i++) {
      final ch = content[i];

      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < content.length && content[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
        continue;
      }

      if (ch == '"') {
        // Un doppio apice a inizio campo (o dopo virgola) avvia una zona
        // tra virgolette. Se compare nel mezzo, viene trattato letteralmente.
        if (field.isEmpty) {
          inQuotes = true;
        } else {
          field.write(ch);
        }
      } else if (ch == delimiter) {
        endField();
      } else if (ch == '\n') {
        endRow();
      } else if (ch == '\r') {
        // CRLF: ignora il \r, il \n successivo chiude la riga.
        if (i + 1 < content.length && content[i + 1] != '\n') {
          endRow();
        }
      } else {
        field.write(ch);
      }
    }

    // Ultimo campo/riga senza newline finale.
    if (field.isNotEmpty || row.isNotEmpty) endRow();

    if (rows.isEmpty) {
      return const CsvParseResult(headers: null, rows: [], errors: []);
    }

    // Verifica coerenza: righe con più campi delle intestazioni → errore.
    final headers = rows.first;
    final dataRows = <List<String>>[];
    for (var r = 1; r < rows.length; r++) {
      final current = rows[r];
      if (current.length != headers.length) {
        errors.add(
          CsvRowError(
            r + 1,
            'Riga ${r + 1}: numero di colonne (${current.length}) diverso dalle '
            'intestazioni (${headers.length}).',
          ),
        );
      } else {
        dataRows.add(current);
      }
    }

    return CsvParseResult(headers: headers, rows: dataRows, errors: errors);
  }
}
