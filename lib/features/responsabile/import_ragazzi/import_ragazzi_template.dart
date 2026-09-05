// ══════════════════════════════════════════════════════════════════════════════
// import_ragazzi_template.dart — CatechHub (template di esempio importazione)
//
// Genera un file CSV di esempio con le intestazioni attese e una riga
// dimostrativa. Usato dal wizard "Importa Dati Ragazzi" per scaricare o
// visualizzare il formato dei campi.
// ══════════════════════════════════════════════════════════════════════════════

import 'import_ragazzi_models.dart';

/// Genera il contenuto CSV del template di esempio.
String buildTemplateCsv() {
  const headers = kTemplateHeaders;
  const sample = [
    'Mario',
    'Rossi',
    '12/03/2014',
    'Anna',
    'Rossi',
    'Luca',
    'Rossi',
    '3331234567',
    '3289876543',
    'annarossi@example.com',
    'Allergia alle arachidi',
    'Iscritto al gruppo della Prima Comunione',
  ];

  String csvField(String value) {
    if (value.contains(',') || value.contains(';') || value.contains('"')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  return '${headers.map(csvField).join(';')}\n'
      '${sample.map(csvField).join(';')}\n';
}

/// Riga di esempio del template (per anteprima a schermo).
const Map<ImportField, String> kTemplateSample = {
  ImportField.nome: 'Mario',
  ImportField.cognome: 'Rossi',
  ImportField.dataNascita: '12/03/2014',
  ImportField.madreNome: 'Anna',
  ImportField.madreCognome: 'Rossi',
  ImportField.padreNome: 'Luca',
  ImportField.padreCognome: 'Rossi',
  ImportField.telefonoMadre: '3331234567',
  ImportField.telefonoPadre: '3289876543',
  ImportField.emailGenitore: 'annarossi@example.com',
  ImportField.noteMediche: 'Allergia alle arachidi',
  ImportField.noteLibere: 'Iscritto alla Prima Comunione',
};
