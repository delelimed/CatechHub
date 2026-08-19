// ══════════════════════════════════════════════════════════════════════════════
// import_ragazzi_service.dart — CatechHub (parsing, validazione e importazione)
//
// Modulo "Importazione Massiva Anagrafica Ragazzi" (solo Responsabile).
// Pipeline:
//   1. Rilevamento tipo file (.csv / .xlsx) e parsing in tabella grezza.
//   2. Mappatura automatica delle colonne (alias delle intestazioni).
//   3. Normalizzazione (nomi Title Case, date, telefoni) e validazione.
//   4. Deduplica identità per nome+cognome+data di nascita.
//   5. Applicazione delle azioni dell'utente e scrittura nel DB.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import '../../../core/storage/local_database.dart';
import '../../../shared/models/student_model.dart';
import '../../../shared/utils/auth_utils.dart';
import '../../../shared/utils/name_formatting.dart';
import '../../students/students_repository.dart';
import 'csv_parser.dart';
import 'import_ragazzi_models.dart';
import 'xlsx_parser.dart';

/// Servizio di importazione massiva anagrafica ragazzi.
class ImportRagazziService {
  final StudentsRepository _students;

  ImportRagazziService({StudentsRepository? students})
    : _students = students ?? StudentsRepository();

  // ═════════════════════════════════════════════════════════════════════
  // 1. PARSING
  // ═════════════════════════════════════════════════════════════════════

  /// Parsea un file importato in una tabella grezza (intestazioni + righe).
  ///
  /// [fileName] è usato per rilevare l'estensione. Ritorna null se il tipo
  /// di file non è supportato.
  ({List<String> headers, List<List<String>> rows, List<String> warnings})?
  parseFile(String fileName, List<int> bytes) {
    final lower = fileName.toLowerCase();
    try {
      if (lower.endsWith('.csv')) {
        final content = utf8.decode(bytes, allowMalformed: true);
        final result = const CsvParser().parse(content);
        final warnings = result.errors.map((e) => e.message).toList();
        return (
          headers: result.headers ?? const [],
          rows: result.rows,
          warnings: warnings,
        );
      }
      if (lower.endsWith('.xlsx')) {
        final result = const XlsxParser().parse(bytes);
        if (result.error != null) {
          return (headers: const [], rows: const [], warnings: [result.error!]);
        }
        return (
          headers: result.headers ?? const [],
          rows: result.rows,
          warnings: const [],
        );
      }
      if (lower.endsWith('.xls')) {
        // .xls (BIFF legacy) non è supportato: suggerisci la conversione.
        return (
          headers: const [],
          rows: const [],
          warnings: [
            'Il formato .xls (legacy) non è supportato. Apri il file in '
                'Excel o LibreOffice e salvalo come .xlsx o .csv.',
          ],
        );
      }
      return (
        headers: const [],
        rows: const [],
        warnings: ['Formato file non supportato: usa .csv, .xlsx o .xls.'],
      );
    } catch (e) {
      return (
        headers: const [],
        rows: const [],
        warnings: ['Errore di lettura del file: $e'],
      );
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  // 2. MAPPATURA COLONNE
  // ═════════════════════════════════════════════════════════════════════

  /// Tenta la mappatura automatica delle intestazioni ai campi.
  ///
  /// Ritorna una mappa colonna (indice 0-based) → campo, includendo solo le
  /// colonne riconosciute. Le colonne non riconosciute restano non mappate.
  Map<int, ImportField> autoMapHeaders(List<String> headers) {
    final mapping = <int, ImportField>{};
    for (var i = 0; i < headers.length; i++) {
      final normalized = _normalizeHeader(headers[i]);
      if (normalized.isEmpty) continue;
      for (final field in ImportField.values) {
        if (field.aliases.any((a) => _normalizeHeader(a) == normalized)) {
          mapping[i] = field;
          break;
        }
      }
    }
    return mapping;
  }

  /// Normalizza un'intestazione: lowercase, senza spazi e senza punteggiatura.
  static String _normalizeHeader(String header) {
    return header.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
  }

  /// Verifica che tutti i campi obbligatori siano mappati.
  List<ImportField> missingRequired(Map<int, ImportField> mapping) {
    final mapped = mapping.values.toSet();
    return ImportField.values
        .where((f) => f.required && !mapped.contains(f))
        .toList();
  }

  // ═════════════════════════════════════════════════════════════════════
  // 3. NORMALIZZAZIONE E VALIDAZIONE
  // ═════════════════════════════════════════════════════════════════════

  /// Converte le righe grezze in righe normalizzate con la mappatura data.
  List<ImportRow> buildRows(
    List<List<String>> rawRows,
    Map<int, ImportField> mapping,
  ) {
    return [
      for (var r = 0; r < rawRows.length; r++)
        _normalizeAndValidate(rawRows[r], mapping, r + 2),
    ];
  }

  ImportRow _normalizeAndValidate(
    List<String> raw,
    Map<int, ImportField> mapping,
    int rowNumber,
  ) {
    final values = <String, dynamic>{};
    final errors = <String>[];

    for (final entry in mapping.entries) {
      final col = entry.key;
      final field = entry.value;
      final rawValue = col < raw.length ? raw[col].trim() : '';
      final normalized = _normalizeField(field, rawValue);

      if (field.required) {
        if (rawValue.isEmpty) {
          errors.add('Campo obbligatorio mancante: ${field.label}.');
          values[field.dbKey] = null;
          continue;
        }
        if (normalized == null) {
          errors.add(
            'Valore non valido per "${field.label}" alla riga $rowNumber.',
          );
        }
      } else if (rawValue.isNotEmpty && normalized == null) {
        errors.add(
          'Valore non valido per "${field.label}" alla riga $rowNumber.',
        );
      }

      values[field.dbKey] = normalized;
    }

    if (errors.isNotEmpty) {
      return ImportRow(
        rowNumber: rowNumber,
        values: values,
        errors: errors,
        status: ImportRowStatus.error,
      );
    }
    return ImportRow(rowNumber: rowNumber, values: values);
  }

  /// Normalizza un singolo valore in base al campo (nome, data, telefono…).
  /// Ritorna null se il valore non è valido per il campo.
  String? _normalizeField(ImportField field, String value) {
    switch (field) {
      case ImportField.nome:
      case ImportField.cognome:
      case ImportField.madreNome:
      case ImportField.madreCognome:
      case ImportField.padreNome:
      case ImportField.padreCognome:
        return NameFormatting.capitalizeWords(value);

      case ImportField.dataNascita:
        return _normalizeDate(value);

      case ImportField.telefonoMadre:
      case ImportField.telefonoPadre:
        return _normalizePhone(value);

      case ImportField.emailGenitore:
        return _normalizeEmail(value);

      case ImportField.noteMediche:
      case ImportField.noteLibere:
        return value.trim();
    }
  }

  /// Normalizza una data nei formati comuni (gg/mm/aaaa, gg-mm-aaaa,
  /// gg.mm.aaaa, aaaa-mm-gg, gg/mm/aa) → ISO 8601 (yyyy-MM-dd).
  /// Ritorna null se il formato non è riconosciuto.
  String? _normalizeDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    // Già ISO: aaaa-mm-gg o ISO completo con ora.
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})');
    final isoMatch = iso.firstMatch(value);
    if (isoMatch != null) {
      final d = _validDate(
        int.parse(isoMatch.group(1)!),
        int.parse(isoMatch.group(2)!),
        int.parse(isoMatch.group(3)!),
      );
      return d == null ? null : _iso(d);
    }

    // Italiano/Europeo: gg/mm/aaaa oppure gg-mm-aaaa oppure gg.mm.aaaa.
    final eu = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})$');
    final euMatch = eu.firstMatch(value);
    if (euMatch != null) {
      final day = int.parse(euMatch.group(1)!);
      final month = int.parse(euMatch.group(2)!);
      var year = int.parse(euMatch.group(3)!);
      if (year < 100) year += 2000;
      final d = _validDate(year, month, day);
      return d == null ? null : _iso(d);
    }

    return null;
  }

  DateTime? _validDate(int year, int month, int day) {
    if (year < 1900 || year > 2100) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    // Verifica che il giorno sia effettivamente valido (es. 31/02).
    if (date.day != day || date.month != month || date.year != year) {
      return null;
    }
    return date;
  }

  String _iso(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// Normalizza un numero di telefono: rimuove spazi, trattini e prefisso
  /// internazionale. Valida la lunghezza (8–15 cifre). Ritorna null se invalido.
  String? _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.length < 8 || digits.length > 15) return null;
    return digits;
  }

  /// Normalizza e valida una email (regex semplice ma affidabile).
  String? _normalizeEmail(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final ok = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(value);
    return ok ? value.toLowerCase() : null;
  }

  // ═════════════════════════════════════════════════════════════════════
  // 4. DEDUPLICA
  // ═════════════════════════════════════════════════════════════════════

  /// Calcola l'ID identità stabile di un ragazzo: nome+cognome normalizzati
  /// (case-insensitive) + data di nascita.
  static String identityKey(String name, String surname, String? birthIso) {
    final normalizedName = _identityPart(name);
    final normalizedSurname = _identityPart(surname);
    return '$normalizedName|$normalizedSurname|${birthIso ?? ''}';
  }

  static String _identityPart(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  /// Costruisce l'indice delle identità già presenti nel DB parrocchiale.
  Future<Map<String, List<Student>>> _existingByIdentity() async {
    final index = <String, List<Student>>{};
    for (final student in await _students.getAllStudentsSync()) {
      final key = identityKey(
        student.name,
        student.surname,
        _isoOnly(student.birthDate),
      );
      index.putIfAbsent(key, () => []).add(student);
    }
    return index;
  }

  String _isoOnly(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// Marca come duplicati le righe valide la cui identità esiste già.
  Future<List<ImportRow>> detectDuplicates(List<ImportRow> rows) async {
    final index = await _existingByIdentity();
    return rows.map((row) {
      if (row.status != ImportRowStatus.valid) return row;
      final key = identityKey(
        (row.values['name'] ?? '').toString(),
        (row.values['surname'] ?? '').toString(),
        (row.values['birthDate'] ?? '').toString(),
      );
      final matches = index[key];
      if (matches == null || matches.isEmpty) return row;
      return row.copyWith(
        status: ImportRowStatus.duplicate,
        existing: matches.first,
      );
    }).toList();
  }

  // ═════════════════════════════════════════════════════════════════════
  // 5. IMPORT
  // ═════════════════════════════════════════════════════════════════════

  /// Applica le azioni scelte dall'utente e scrive nel DB. Ritorna il report.
  Future<ImportReport> importRows(List<ImportRow> rows) async {
    var imported = 0;
    var updated = 0;
    var ignored = 0;
    var errorCount = 0;
    final errorMessages = <String>[];

    for (final row in rows) {
      if (row.status == ImportRowStatus.error) {
        errorCount++;
        errorMessages.add('Riga ${row.rowNumber}: ${row.errors.join(' ')}');
        continue;
      }

      if (row.status == ImportRowStatus.duplicate) {
        switch (row.action) {
          case DuplicateAction.ignore:
            ignored++;
            continue;
          case DuplicateAction.createNew:
            await _createFromRow(row);
            imported++;
            continue;
          case DuplicateAction.update:
            await _updateExisting(row);
            updated++;
            continue;
        }
      }

      // Riga valida, non duplicata.
      await _createFromRow(row);
      imported++;
    }

    return ImportReport(
      totalRows: rows.length,
      imported: imported,
      updated: updated,
      duplicatesIgnored: ignored,
      errors: errorCount,
      errorMessages: errorMessages,
    );
  }

  Future<void> _createFromRow(ImportRow row) async {
    final student = _studentFromRow(row, id: LocalDatabase.newId('student'));
    await _students.addStudent(student);
  }

  Future<void> _updateExisting(ImportRow row) async {
    final existing = row.existing;
    if (existing == null) return;
    final student = _studentFromRow(row, id: existing.id);
    // Mantiene classId/classUniqueCode dell'esistente.
    final merged = Student(
      id: existing.id,
      name: student.name,
      surname: student.surname,
      birthDate: student.birthDate,
      classId: existing.classId,
      classUniqueCode: existing.classUniqueCode,
      motherName: student.motherName,
      motherSurname: student.motherSurname,
      fatherName: student.fatherName,
      fatherSurname: student.fatherSurname,
      motherPhone: student.motherPhone,
      fatherPhone: student.fatherPhone,
      studentPhone: student.studentPhone,
      parentEmail: student.parentEmail,
      allergies: student.allergies,
      autonomousExits: existing.autonomousExits,
      notes: student.notes ?? existing.notes,
      consensoPrivacyFirmato: existing.consensoPrivacyFirmato,
      dataFirmaConsenso: existing.dataFirmaConsenso,
      dataScadenzaTrattamento: existing.dataScadenzaTrattamento,
      consensoUsciteAutonome: existing.consensoUsciteAutonome,
      contributoVersato: existing.contributoVersato,
      contributoEuros: existing.contributoEuros,
      annoContributo: existing.annoContributo,
      noteAllergieSalute: student.noteAllergieSalute,
      statoPercorso: existing.statoPercorso,
      annoIscrizione: existing.annoIscrizione,
      sacraments: existing.sacraments,
    );
    await _students.updateStudent(existing.id, merged);
  }

  /// Costruisce uno [Student] dalla riga normalizzata.
  Student _studentFromRow(ImportRow row, {required String id}) {
    final v = row.values;
    return Student(
      id: id,
      name: (v['name'] ?? '').toString(),
      surname: (v['surname'] ?? '').toString(),
      birthDate:
          DateTime.tryParse(v['birthDate']?.toString() ?? '') ?? DateTime.now(),
      classId: null,
      classUniqueCode: null,
      motherName: (v['motherName'] ?? '').toString(),
      motherSurname: (v['motherSurname'] ?? '').toString(),
      fatherName: (v['fatherName'] ?? '').toString(),
      fatherSurname: (v['fatherSurname'] ?? '').toString(),
      motherPhone: (v['motherPhone'] ?? '').toString(),
      fatherPhone: (v['fatherPhone'] ?? '').toString(),
      studentPhone: '',
      parentEmail: (v['parentEmail'] ?? '').toString(),
      allergies: _nullIfEmpty(v['noteAllergieSalute']),
      notes: _nullIfEmpty(v['notes']),
      noteAllergieSalute: _nullIfEmpty(v['noteAllergieSalute']),
      lastModifiedBy: getCurrentCatechistName(),
    );
  }

  String? _nullIfEmpty(dynamic value) {
    final s = value?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }
}
