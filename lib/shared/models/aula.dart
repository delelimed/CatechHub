// ══════════════════════════════════════════════════════════════════════════════
// aula.dart — CatechHub (entità Aula/Stanza e slot orari settimanali)
//
// Modulo "Responsabile Catechistico — Logistica Parrocchiale":
// rappresenta gli spazi fisici della parrocchia (aule, sale parrocchiali,
// cappelle) e la relativa capienza. Le attività delle classi vengono
// programmate in [RoomSlot] liberi da conflitti.
// ══════════════════════════════════════════════════════════════════════════════

/// Entità Aula/Stanza della parrocchia.
class Aula {
  /// ID univoco stanza (formato: "stanza_<microsecondsSinceEpoch>").
  final String stanzaId;

  /// Nome della stanza (es. "Aula San Biuseppe", "Sala parrocchiale").
  final String nomeStanza;

  /// Capienza massima consentita (numero max di persone/ragazzi).
  final int capienzaMassima;

  /// Note su accessibilità (barriere architettoniche, piano, ecc.).
  final String noteAccessibilita;

  /// Nome del responsabile che ha creato/modificato.
  final String lastModifiedBy;

  /// Timestamp di creazione (UTC, ISO 8601).
  final DateTime createdAt;

  /// Timestamp dell'ultima modifica (UTC, ISO 8601).
  final DateTime updatedAt;

  Aula({
    required this.stanzaId,
    required this.nomeStanza,
    this.capienzaMassima = 0,
    this.noteAccessibilita = '',
    this.lastModifiedBy = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Aula copyWith({
    String? stanzaId,
    String? nomeStanza,
    int? capienzaMassima,
    String? noteAccessibilita,
    String? lastModifiedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Aula(
      stanzaId: stanzaId ?? this.stanzaId,
      nomeStanza: nomeStanza ?? this.nomeStanza,
      capienzaMassima: capienzaMassima ?? this.capienzaMassima,
      noteAccessibilita: noteAccessibilita ?? this.noteAccessibilita,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Aula.fromMap(String id, Map<String, dynamic> data) {
    final rawCapienza = data['capienzaMassima'];
    return Aula(
      stanzaId: id,
      nomeStanza: data['nomeStanza'] ?? '',
      capienzaMassima: rawCapienza is int ? rawCapienza : int.tryParse('$rawCapienza') ?? 0,
      noteAccessibilita: data['noteAccessibilita'] ?? '',
      lastModifiedBy: data['lastModifiedBy'] ?? '',
      createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(data['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nomeStanza': nomeStanza,
      'capienzaMassima': capienzaMassima,
      'noteAccessibilita': noteAccessibilita,
      'lastModifiedBy': lastModifiedBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

/// Slot orario settimanale di una classe in un'aula.
///
/// [giornoSettimana] usa la convenzione Dart: 1=Lunedì … 7=Domenica
/// (DateTime.monday=1 .. sunday=7).
class RoomSlot {
  /// ID dello slot (formato "slot_<microsecondsSinceEpoch>").
  final String slotId;

  /// ID dell'aula assegnata.
  final String stanzaId;

  /// Nome snapshot dell'aula (per effetti sincronizzazione).
  final String nomeStanza;

  /// Giorno della settimana: 1..7 (1=Lunedì).
  final int giornoSettimana;

  /// Ora di inizio "HH:mm" (es. "15:00").
  final String oraInizio;

  /// Ora di fine "HH:mm" (es. "16:30").
  final String oraFine;

  /// Nota facoltativa (es. indicazioni per i catechisti).
  final String note;

  const RoomSlot({
    required this.slotId,
    required this.stanzaId,
    this.nomeStanza = '',
    required this.giornoSettimana,
    required this.oraInizio,
    required this.oraFine,
    this.note = '',
  });

  RoomSlot copyWith({
    String? slotId,
    String? stanzaId,
    String? nomeStanza,
    int? giornoSettimana,
    String? oraInizio,
    String? oraFine,
    String? note,
  }) {
    return RoomSlot(
      slotId: slotId ?? this.slotId,
      stanzaId: stanzaId ?? this.stanzaId,
      nomeStanza: nomeStanza ?? this.nomeStanza,
      giornoSettimana: giornoSettimana ?? this.giornoSettimana,
      oraInizio: oraInizio ?? this.oraInizio,
      oraFine: oraFine ?? this.oraFine,
      note: note ?? this.note,
    );
  }

  factory RoomSlot.fromMap(Map<String, dynamic> data) {
    return RoomSlot(
      slotId: data['slotId'] ?? '',
      stanzaId: data['stanzaId'] ?? '',
      nomeStanza: data['nomeStanza'] ?? '',
      giornoSettimana: (data['giornoSettimana'] as num?)?.toInt() ?? 0,
      oraInizio: data['oraInizio'] ?? '',
      oraFine: data['oraFine'] ?? '',
      note: data['note'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'slotId': slotId,
      'stanzaId': stanzaId,
      'nomeStanza': nomeStanza,
      'giornoSettimana': giornoSettimana,
      'oraInizio': oraInizio,
      'oraFine': oraFine,
      'note': note,
    };
  }

  /// Confronta l'intervallo orario [oraInizio, oraFine) con un altro slot.
  /// Ritorna true se i due slot si sovrappongono.
  bool overlaps(RoomSlot other) {
    if (other.giornoSettimana != giornoSettimana) return false;
    return _minutes(oraInizio) < _minutes(other.oraFine) &&
        _minutes(other.oraInizio) < _minutes(oraFine);
  }

  static int _minutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }
}