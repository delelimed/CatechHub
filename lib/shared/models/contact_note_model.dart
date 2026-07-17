// ══════════════════════════════════════════════════════════════════════════════
// contact_note_model.dart — CatechHub (modello nota di contatto genitori)
//
// Registra una comunicazione intercorsa tra il catechista e i genitori
// di uno studente. Funge da "registro di contatto" per tenere traccia
// delle interazioni con le famiglie.
//
// CONTESTO PROGETTO:
//   Il catechista ha la necessità di documentare le comunicazioni con
//   i genitori per ragioni organizzative e di trasparenza pastorale.
//   Questo modello traccia:
//   - Data/ora del contatto
//   - Mezzo utilizzato (de visu, WhatsApp, telefonata)
//   - Note descrittive sul contenuto della comunicazione
//
//   La vista ContactNotesPage (route: /contact-notes) permette di
//   visualizzare e filtrare le note per studente.
//
// RELAZIONI:
//   ContactNote (N) ──> (1) Student  [via studentId]
//
// MEZZI DI CONTATTO (medium):
//   - 'de_visu': incontro faccia a faccia (es. dopo la messa)
//   - 'whatsapp': messaggio WhatsApp
//   - 'cellulare': chiamata telefonica
//
//   mediumLabel() converte il codice in etichetta visuale italiana.
// ══════════════════════════════════════════════════════════════════════════════

class ContactNote {
  /// ID univoco della nota di contatto.
  final String id;

  /// FK verso Student (ragazzo di cui si è contattato il genitore).
  final String studentId;

  /// Data e ora del contatto (ISO 8601).
  final DateTime dateTime;

  /// Mezzo di contatto: 'de_visu', 'whatsapp' o 'cellulare'.
  final String medium;

  /// Note descrittive sulla comunicazione (testo libero).
  final String notes;

  /// Nome del catechista che ha modificato per ultimo questo record.
  final String lastModifiedBy;

  ContactNote({
    required this.id,
    required this.studentId,
    required this.dateTime,
    required this.medium,
    required this.notes,
    this.lastModifiedBy = '',
  });

  factory ContactNote.fromMap(String id, Map<String, dynamic> data) {
    return ContactNote(
      id: id,
      studentId: data['studentId'] ?? '',
      dateTime: DateTime.tryParse(data['dateTime']?.toString() ?? '') ??
          DateTime.now(),
      medium: data['medium'] ?? 'de_visu',
      notes: data['notes'] ?? '',
      lastModifiedBy: data['lastModifiedBy'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'dateTime': dateTime.toIso8601String(),
      'medium': medium,
      'notes': notes,
      'lastModifiedBy': lastModifiedBy,
    };
  }

  /// Converte il codice medium in etichetta visuale italiana.
  ///   'de_visu' → "De visu"
  ///   'whatsapp' → "WhatsApp"
  ///   'cellulare' → "Cellulare"
  static String mediumLabel(String medium) {
    switch (medium) {
      case 'de_visu':
        return 'De visu';
      case 'whatsapp':
        return 'WhatsApp';
      case 'cellulare':
        return 'Cellulare';
      default:
        return medium;
    }
  }
}
