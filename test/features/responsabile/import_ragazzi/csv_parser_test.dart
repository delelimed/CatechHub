import 'package:flutter_test/flutter_test.dart';

import 'package:CatechHub/features/responsabile/import_ragazzi/csv_parser.dart';

void main() {
  const parser = CsvParser();

  group('CsvParser', () {
    test('parses a simple comma-separated file', () {
      final result = parser.parse(
        'Nome,Cognome,Data di nascita\n'
        'Luca,Bianchi,10/05/2012\n',
      );
      expect(result.headers, ['Nome', 'Cognome', 'Data di nascita']);
      expect(result.rows, [
        ['Luca', 'Bianchi', '10/05/2012'],
      ]);
      expect(result.errors, isEmpty);
    });

    test('detects semicolon delimiter', () {
      final result = parser.parse(
        'Nome;Cognome\n'
        'Maria;Rossi\n',
      );
      expect(result.headers, ['Nome', 'Cognome']);
      expect(result.rows.single, ['Maria', 'Rossi']);
    });

    test('strips UTF-8 BOM', () {
      final result = parser.parse('\uFEFFNome,Cognome\nLuca,Bianchi\n');
      expect(result.headers, ['Nome', 'Cognome']);
    });

    test('handles quoted fields with commas and escaped quotes', () {
      final result = parser.parse(
        'Nome,Note\n'
        '"Rossi, Mario","Ha ""febbre"" spesso"\n',
      );
      expect(result.rows.single, ['Rossi, Mario', 'Ha "febbre" spesso']);
    });

    test('handles CRLF line endings', () {
      final result = parser.parse('Nome,Cognome\r\nLuca,Bianchi\r\n');
      expect(result.rows.single, ['Luca', 'Bianchi']);
    });

    test('handles a final row without trailing newline', () {
      final result = parser.parse('Nome,Cognome\nLuca,Bianchi');
      expect(result.rows.single, ['Luca', 'Bianchi']);
    });

    test('returns empty result for blank content', () {
      final result = parser.parse('   \n  ');
      expect(result.headers, isNull);
      expect(result.rows, isEmpty);
      expect(result.errors, isEmpty);
    });

    test('reports rows with inconsistent column count', () {
      final result = parser.parse(
        'Nome,Cognome\n'
        'Luca,Bianchi\n'
        'Solo,Nome,InPiu\n',
      );
      expect(result.errors, hasLength(1));
      expect(result.errors.single.message, contains('3'));
    });
  });
}
