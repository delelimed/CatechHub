// ══════════════════════════════════════════════════════════════════════════════
// planning_meeting.dart — CatechHub (modello programmazione incontri)
//
// Rappresenta un singolo incontro/evento programmato nel calendario
// del catechismo. Distingue tra veri incontri con studenti (con appello
// presenze) e riunioni interne tra catechisti (senza presenze).
//
// CONTESTO PROGETTO:
//   La programmazione è il cuore organizzativo dell'app. PlanningMeeting
//   viene usato da:
//   - PlanningPage: calendario delle giornate di catechismo
//   - AttendanceMeetingsPage: selezione dell'incontro per registrare
//     le presenze (filtra isReunion=false)
//   - Dashboard: mostra il "Prossimo impegno" (nextMeeting)
//   - Sync P2P: i record del box "planning_box" vengono sincronizzati
//
// VALIDAZIONE:
//   Se il titolo è vuoto al momento della deserializzazione da Hive
//   (es. record legacy), viene generato automaticamente come
//   "Giornata del <gg>/<mm>/<aaaa>".
//
// FLUSSO PRESENZE:
//   PlanningMeeting (1) ──< (N) Attendance  [via classId + date]
//   Solo gli incontri con isReunion=false hanno appello presenze.
//
// NOTE:
//   Il campo notes legge anche il legacy key 'publicNotes' per
//   retrocompatibilità con versioni precedenti dell'app.
// ══════════════════════════════════════════════════════════════════════════════

class PlanningMeeting {
  /// ID univoco dell'incontro.
  final String id;

  /// FK verso SchoolClass (gruppo a cui appartiene l'incontro).
  final String classId;

  /// ID del catechista che ha creato l'incontro.
  final String createdBy;

  /// Data dell'incontro (formato ISO 8601).
  final DateTime date;

  /// Titolo (es. "Incontro sulla Pasqua"). Se vuoto in fromMap,
  /// viene generato automaticamente "Giornata del <gg>/<mm>/<aaaa>".
  final String title;

  /// Descrizione delle attività previste per l'incontro.
  final String activity;

  /// Note aggiuntive (legacy: legge anche 'publicNotes' per retrocompatibilità).
  final String notes;

  /// true = riunione interna tra catechisti (programmata ma SENZA
  /// appello presenze). La UI nasconde il bottone presenze per
  /// questi incontri.
  final bool isReunion;

  /// Nome del catechista che ha modificato per ultimo questo record.
  final String lastModifiedBy;

  PlanningMeeting({
    required this.id,
    required this.classId,
    required this.createdBy,
    required this.date,
    required this.title,
    required this.activity,
    required this.notes,
    this.isReunion = false,
    this.lastModifiedBy = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'classId': classId,
      'createdBy': createdBy,
      'date': date.toIso8601String(),
      'title': title,
      'activity': activity,
      'notes': notes,
      'isReunion': isReunion,
      'lastModifiedBy': lastModifiedBy,
    };
  }

  factory PlanningMeeting.fromMap(String id, Map<String, dynamic> data) {
    final date = DateTime.tryParse(data['date']?.toString() ?? '') ?? DateTime.now();
    final legacyTitle = data['title']?.toString().trim();

    return PlanningMeeting(
      id: id,
      classId: data['classId'] ?? '',
      createdBy: data['createdBy'] ?? '',
      date: date,
      title: legacyTitle == null || legacyTitle.isEmpty
          ? 'Giornata del ${date.day}/${date.month}/${date.year}'
          : legacyTitle,
      activity: data['activity'] ?? '',
      notes: data['notes'] ?? data['publicNotes'] ?? '',
      isReunion: data['isReunion'] == true,
      lastModifiedBy: data['lastModifiedBy'] ?? '',
    );
  }
}
