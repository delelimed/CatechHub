// ══════════════════════════════════════════════════════════════════════════════
// parish_event.dart — CatechHub (riunione / evento parrocchiale)
//
// Modello del "Global Parish Channel" (Canale Parrocchiale): riunioni tra
// catechisti, appuntamenti e avvisi generali della parrocchia. Questi dati
// sono CONSIERATI pubblici per la rete parrocchiale e viaggiano IN CHIARO,
// a differenza dei dati di classe (Class Channel) che sono cifrati per-classe.
//
// CONTESTO PROGETTO:
//   Rete Catechistica Parrocchiale: tutti i dispositivi della rete scambiano
//   riunioni e avvisi parrocchiali indipendentemente dal titolo sulle singole
//   classi. Questo consente una sincronizzazione rapida delle riunioni senza
//   condividere i dati sensibili delle classi con chi non ne ha titolo.
//
// STORAGE:
//   Salvato nel box Hive "parish_events_box" (Map) con chiave = id.
// ══════════════════════════════════════════════════════════════════════════════

class ParishEvent {
  /// ID univoco dell'evento (formato `parish_event_<microseconds>`).
  final String id;

  /// Titolo della riunione (es. "Riunione catechisti di Natale").
  final String title;

  /// Data dell'evento (ISO 8601).
  final DateTime date;

  /// Orario opzionale ("HH:mm").
  final String? time;

  /// Luogo dell'evento (es. "Sala Don Bosco").
  final String? location;

  /// Note / ordine del giorno.
  final String notes;

  /// Nome o ID del creatore.
  final String createdBy;

  /// Timestamp di creazione (UTC, ISO 8601).
  final DateTime createdAt;

  /// Timestamp dell'ultima modifica (UTC, ISO 8601).
  final DateTime updatedAt;

  ParishEvent({
    required this.id,
    required this.title,
    required this.date,
    this.time,
    this.location,
    this.notes = '',
    this.createdBy = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  ParishEvent copyWith({
    String? title,
    DateTime? date,
    String? time,
    String? location,
    String? notes,
    String? createdBy,
    DateTime? updatedAt,
  }) {
    return ParishEvent(
      id: id,
      title: title ?? this.title,
      date: date ?? this.date,
      time: time ?? this.time,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'date': date.toIso8601String(),
        'time': time,
        'location': location,
        'notes': notes,
        'createdBy': createdBy,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory ParishEvent.fromMap(String id, Map<String, dynamic> data) =>
      ParishEvent(
        id: id,
        title: data['title']?.toString() ?? '',
        date: DateTime.tryParse(data['date']?.toString() ?? '') ??
            DateTime.now(),
        time: data['time']?.toString(),
        location: data['location']?.toString(),
        notes: data['notes']?.toString() ?? '',
        createdBy: data['createdBy']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(data['createdAt']?.toString() ?? '')?.toUtc() ??
                DateTime.now().toUtc(),
        updatedAt:
            DateTime.tryParse(data['updatedAt']?.toString() ?? '')?.toUtc() ??
                DateTime.now().toUtc(),
      );
}
