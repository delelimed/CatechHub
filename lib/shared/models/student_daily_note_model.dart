// ══════════════════════════════════════════════════════════════════════════════
// student_daily_note_model.dart — CatechHub (modello nota giornaliera studente)
//
// Annotazione individuale del catechista su uno studente in una specifica
// giornata di catechismo. Serve per appunti rapidi durante o dopo l'incontro
// (es. "Oggi Marco era distratto", "Lucia ha fatto una bella domanda").
//
// CONTESTO PROGETTO:
//   Questo modello differisce da ContactNote (comunicazione con genitori)
//   e da Student.notes (note permanenti sull'anagrafica). È una nota
//   contestuale legata a un incontro specifico, visibile nella sezione
//   Dettaglio Studente durante la registrazione presenze.
//
// RELAZIONI:
//   StudentDailyNote (N) ──> (1) Student         [via studentId]
//   StudentDailyNote (N) ──> (1) PlanningMeeting  [via meetingId]
//
// STORAGE:
//   Salvato in Hive box "student_daily_notes_box".
//   I timestamp createdAt/updatedAt permettono ordinamento cronologico
//   e supportano la risoluzione CRDT in caso di sync P2P futuro.
// ══════════════════════════════════════════════════════════════════════════════

class StudentDailyNote {
  /// ID univoco della nota.
  final String id;

  /// FK verso Student (ragazzo a cui si riferisce la nota).
  final String studentId;

  /// FK verso PlanningMeeting (incontro in cui è stata scritta).
  final String meetingId;

  /// Testo della nota (es. "Ha partecipato attivamente al gioco").
  final String text;

  /// Timestamp di creazione (UTC, ISO 8601).
  final DateTime createdAt;

  /// Timestamp dell'ultima modifica (UTC, ISO 8601).
  final DateTime updatedAt;

  /// Nome del catechista che ha modificato per ultimo questo record.
  final String lastModifiedBy;

  StudentDailyNote({
    required this.id,
    required this.studentId,
    required this.meetingId,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.lastModifiedBy = '',
  });

  factory StudentDailyNote.fromMap(String id, Map<String, dynamic> data) {
    return StudentDailyNote(
      id: id,
      studentId: data['studentId'] ?? '',
      meetingId: data['meetingId'] ?? '',
      text: data['text'] ?? '',
      createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(data['updatedAt'] ?? '') ?? DateTime.now(),
      lastModifiedBy: data['lastModifiedBy'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'meetingId': meetingId,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastModifiedBy': lastModifiedBy,
    };
  }

  StudentDailyNote copyWith({
    String? id,
    String? studentId,
    String? meetingId,
    String? text,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? lastModifiedBy,
  }) {
    return StudentDailyNote(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      meetingId: meetingId ?? this.meetingId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
    );
  }
}
