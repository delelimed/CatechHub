// ══════════════════════════════════════════════════════════════════════════════
// xlsx_parser.dart — CatechHub (parser .xlsx per l'importazione massiva)
//
// Un file .xlsx è un archivio ZIP che contiene documenti XML:
//   - xl/workbook.xml              → nomi dei fogli + mapping rId → sheet
//   - xl/_rels/workbook.xml.rels   → risoluzione del path della worksheet
//   - xl/sharedStrings.xml         → tabella delle stringhe condivise
//   - xl/worksheets/sheet1.xml     → celle della griglia (riferimenti A1)
//
// Il parser legge il PRIMO foglio del workbook, gestisce celle di tipo
// shared string (t="s"), inline string (t="inlineStr"), booleani (t="b"),
// numerici e formule. Ritorna la tabella grezza + intestazioni.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Risultato del parsing XLSX: tabella grezza + intestazioni rilevate.
class XlsxParseResult {
  final List<String>? headers;
  final List<List<String>> rows;
  final String? error;

  const XlsxParseResult({
    required this.headers,
    required this.rows,
    this.error,
  });
}

class XlsxParser {
  const XlsxParser();

  /// Decodifica i byte di un file .xlsx e ritorna il primo foglio.
  XlsxParseResult parse(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final sharedStrings = _readSharedStrings(archive);
      final worksheetPath = _resolveFirstWorksheet(archive);
      final sheetXml = archive.findFile(worksheetPath);
      if (sheetXml == null) {
        return XlsxParseResult(
          headers: null,
          rows: [],
          error: 'Foglio di lavoro non trovato nel file .xlsx.',
        );
      }
      return _parseSheet(sheetXml, sharedStrings);
    } on ArchiveException catch (e) {
      return XlsxParseResult(
        headers: null,
        rows: [],
        error: 'File .xlsx non valido o corrotto: $e',
      );
    }
  }

  /// Legge la tabella delle stringhe condivise (xl/sharedStrings.xml).
  List<String> _readSharedStrings(Archive archive) {
    final file = archive.findFile('xl/sharedStrings.xml');
    if (file == null) return const [];
    final bytes = file.readBytes();
    if (bytes == null || bytes.isEmpty) return const [];
    final doc = XmlDocument.parse(String.fromCharCodes(bytes));
    return doc
        .findAllElements('t')
        .map((node) => node.innerText)
        .toList();
  }

  /// Risolve il path della prima worksheet tramite workbook.xml + rels.
  String _resolveFirstWorksheet(Archive archive) {
    final workbook = archive.findFile('xl/workbook.xml');
    String? rId;
    if (workbook != null) {
      final bytes = workbook.readBytes();
      if (bytes != null && bytes.isNotEmpty) {
        final doc = XmlDocument.parse(String.fromCharCodes(bytes));
        final firstSheet = doc.findAllElements('sheet').firstOrNull;
        rId = firstSheet?.getAttribute('r:id');
      }
    }

    // Se r:id non è disponibile, usa un default ragionevole.
    if (rId != null && rId.isNotEmpty) {
      final rels = archive.findFile('xl/_rels/workbook.xml.rels');
      if (rels != null) {
        final bytes = rels.readBytes();
        if (bytes != null && bytes.isNotEmpty) {
          final doc = XmlDocument.parse(String.fromCharCodes(bytes));
          final rel = doc.findAllElements('Relationship').firstWhereOrNull(
                (node) => node.getAttribute('Id') == rId,
              );
          final target = rel?.getAttribute('Target');
          if (target != null && target.isNotEmpty) {
            return target.startsWith('/')
                ? target.substring(1)
                : 'xl/$target';
          }
        }
      }
    }
    return 'xl/worksheets/sheet1.xml';
  }

  /// Parsea il foglio di lavoro in una tabella di stringhe.
  XlsxParseResult _parseSheet(
    ArchiveFile sheetXml,
    List<String> sharedStrings,
  ) {
    final bytes = sheetXml.readBytes();
    if (bytes == null || bytes.isEmpty) {
      return const XlsxParseResult(headers: null, rows: []);
    }
    final doc = XmlDocument.parse(String.fromCharCodes(bytes));

    // Mappa riga → mappa colonna (1-based) → valore stringa.
    final table = <int, Map<int, String>>{};
    for (final row in doc.findAllElements('row')) {
      final rowNumber = int.tryParse(row.getAttribute('r') ?? '') ?? 0;
      if (rowNumber == 0) continue;
      final cells = <int, String>{};
      for (final cell in row.findElements('c')) {
        final ref = cell.getAttribute('r') ?? '';
        final colIndex = _columnFromRef(ref);
        if (colIndex == 0) continue;
        cells[colIndex] = _cellValue(cell, sharedStrings);
      }
      table[rowNumber] = cells;
    }

    if (table.isEmpty) {
      return const XlsxParseResult(headers: null, rows: []);
    }

    // Calcola il numero massimo di colonne.
    var maxCol = 0;
    for (final cells in table.values) {
      for (final col in cells.keys) {
        if (col > maxCol) maxCol = col;
      }
    }

    final orderedRows = table.keys.toList()..sort();
    final grid = <List<String>>[];
    for (final rowNumber in orderedRows) {
      final cells = table[rowNumber]!;
      final line = <String>[];
      for (var c = 1; c <= maxCol; c++) {
        line.add(cells[c] ?? '');
      }
      grid.add(line);
    }

    if (grid.isEmpty) {
      return const XlsxParseResult(headers: null, rows: []);
    }

    return XlsxParseResult(
      headers: grid.first,
      rows: grid.skip(1).toList(),
    );
  }

  /// Estrae il valore testuale di una cella gestendo i tipi XLSX.
  String _cellValue(XmlElement cell, List<String> sharedStrings) {
    final type = cell.getAttribute('t') ?? '';

    switch (type) {
      case 's':
        final v = cell.getElement('v')?.innerText ?? '';
        final index = int.tryParse(v);
        if (index == null || index < 0 || index >= sharedStrings.length) {
          return '';
        }
        return sharedStrings[index];

      case 'inlineStr':
        return cell.findElements('is').expand((e) => e.findElements('t')).map(
              (e) => e.innerText,
            ).join();

      case 'b':
        final v = cell.getElement('v')?.innerText;
        return v == '1' ? 'TRUE' : 'FALSE';

      default:
        return cell.getElement('v')?.innerText ?? '';
    }
  }

  /// Converte un riferimento di cella (es. "AB12") nell'indice colonna 1-based.
  static int _columnFromRef(String ref) {
    var col = 0;
    for (var i = 0; i < ref.length; i++) {
      final code = ref.codeUnitAt(i);
      if (code >= 65 && code <= 90) {
        col = col * 26 + (code - 64);
      } else {
        break;
      }
    }
    return col;
  }
}

/// Estensioni helper locali (evitano dipendenza da collection nel parser).
extension _FirstWhereOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }

  T? firstWhereOrNull(bool Function(T element) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
