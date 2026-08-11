// ══════════════════════════════════════════════════════════════════════════════
// import_ragazzi_models.dart — CatechHub (modello dati importazione massiva)
//
// Modulo "Importazione Massiva Anagrafica Ragazzi" (solo Responsabile).
// Definisce i campi importabili, il modello di riga importata e i tipi di
// risultato usati dal wizard di importazione.
// ══════════════════════════════════════════════════════════════════════════════

import '../../../shared/models/student_model.dart';

/// Campo importabile del template anagrafica ragazzi.
enum ImportField {
  nome('Nome', required: true, dbKey: 'name'),
  cognome('Cognome', required: true, dbKey: 'surname'),
  dataNascita('Data di nascita', required: true, dbKey: 'birthDate'),
  madreNome('Nome madre', dbKey: 'motherName'),
  madreCognome('Cognome madre', dbKey: 'motherSurname'),
  padreNome('Nome padre', dbKey: 'fatherName'),
  padreCognome('Cognome padre', dbKey: 'fatherSurname'),
  telefonoMadre('Telefono madre', dbKey: 'motherPhone'),
  telefonoPadre('Telefono padre', dbKey: 'fatherPhone'),
  emailGenitore('Email genitore', dbKey: 'parentEmail'),
  noteMediche('Note mediche / allergie', dbKey: 'noteAllergieSalute'),
  noteLibere('Note libere', dbKey: 'notes');

  const ImportField(this.label, {this.required = false, required this.dbKey});

  /// Etichetta mostrata nelle UI (menu di mappatura).
  final String label;

  /// True se il campo è obbligatorio (blocca l'importazione se non mappato).
  final bool required;

  /// Chiave del campo all'interno della mappa normalizzata della riga.
  final String dbKey;

  /// Alias delle intestazioni riconosciuti in automatico (normalizzati).
  List<String> get aliases => switch (this) {
        ImportField.nome => const ['nome', 'name', 'firstname', 'nome ragazzo'],
        ImportField.cognome =>
          const ['cognome', 'surname', 'lastname', 'cognome ragazzo'],
        ImportField.dataNascita =>
          const ['data nascita', 'datanascita', 'birthdate', 'data di nascita'],
        ImportField.madreNome =>
          const ['nome madre', 'nomemadre', 'madre nome', 'mothername'],
        ImportField.madreCognome =>
          const ['cognome madre', 'cognomemadre', 'madre cognome', 'mothersurname'],
        ImportField.padreNome =>
          const ['nome padre', 'nomepadre', 'padre nome', 'fathername'],
        ImportField.padreCognome =>
          const ['cognome padre', 'cognomepadre', 'padre cognome', 'fathersurname'],
        ImportField.telefonoMadre =>
          const ['telefono madre', 'telefonomadre', 'madre telefono', 'motherphone'],
        ImportField.telefonoPadre =>
          const ['telefono padre', 'telefonopadre', 'padre telefono', 'fatherphone'],
        ImportField.emailGenitore =>
          const ['email genitore', 'emailgenitore', 'email', 'parentemail', 'e-mail'],
        ImportField.noteMediche => const [
            'note mediche',
            'notemediche',
            'note mediche / allergie',
            'note mediche allergie',
            'allergie',
            'note allergie',
            'noteallergiesalute',
          ],
        ImportField.noteLibere => const ['note', 'note libere', 'notelibere', 'notes'],
      };
}

/// Intestazioni del template di esempio.
const List<String> kTemplateHeaders = [
  'Nome',
  'Cognome',
  'Data di nascita',
  'Nome madre',
  'Cognome madre',
  'Nome padre',
  'Cognome padre',
  'Telefono madre',
  'Telefono padre',
  'Email genitore',
  'Note mediche / allergie',
  'Note libere',
];

/// Stato di validazione di una singola riga importata.
enum ImportRowStatus {
  /// La riga è valida e può essere importata.
  valid,

  /// La riga contiene errori di validazione (data/telefono/campi mancanti).
  error,

  /// La riga corrisponde a un ragazzo già presente nel DB (duplicato).
  duplicate,
}

/// Azione richiesta all'utente per un duplicato.
enum DuplicateAction {
  /// Non importare la riga.
  ignore,

  /// Aggiorna i dati dello studente già esistente.
  update,

  /// Crea comunque un nuovo record.
  createNew,
}

/// Riga importata (già normalizzata) con la mappa campo → valore.
class ImportRow {
  final int rowNumber;
  final Map<String, dynamic> values;

  /// Errori di validazione (lista di messaggi leggibili).
  final List<String> errors;

  /// Stato corrente della riga (validità).
  final ImportRowStatus status;

  /// Studente esistente trovato (solo se [status] == duplicate).
  final Student? existing;

  /// Azione scelta dall'utente per i duplicati.
  final DuplicateAction action;

  const ImportRow({
    required this.rowNumber,
    required this.values,
    this.errors = const [],
    this.status = ImportRowStatus.valid,
    this.existing,
    this.action = DuplicateAction.ignore,
  });

  ImportRow copyWith({
    ImportRowStatus? status,
    List<String>? errors,
    Student? existing,
    DuplicateAction? action,
  }) {
    return ImportRow(
      rowNumber: rowNumber,
      values: values,
      errors: errors ?? this.errors,
      status: status ?? this.status,
      existing: existing ?? this.existing,
      action: action ?? this.action,
    );
  }

  String get displayName {
    final name = (values['name'] ?? '').toString();
    final surname = (values['surname'] ?? '').toString();
    return '$name $surname'.trim();
  }
}

/// Report finale dell'importazione.
class ImportReport {
  final int totalRows;
  final int imported;
  final int updated;
  final int duplicatesIgnored;
  final int errors;
  final List<String> errorMessages;

  const ImportReport({
    required this.totalRows,
    required this.imported,
    required this.updated,
    required this.duplicatesIgnored,
    required this.errors,
    this.errorMessages = const [],
  });

  String get summary =>
      '$imported ragazzi importati con successo, $errors errori saltati, '
      '${duplicatesIgnored + updated} duplicati risolti';
}
