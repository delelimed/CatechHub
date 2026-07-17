// ══════════════════════════════════════════════════════════════════════════════
// catechesi_model.dart — CatechHub (modello contenuto catechetico)
//
// Rappresenta un contenuto didattico per la catechesi: una scheda
// informativa con titolo, descrizione, tag, riferimenti biblici, link
// web e foto allegate. Funge da libreria di supporto per i catechisti.
//
// CONTESTO PROGETTO:
//   Il modulo Catechesi è una raccolta di contenuti che i catechisti
//   possono creare, consultare e associare agli incontri programmati.
//   A differenza di Student, Attendance e PlanningMeeting, i record
//   di Catechesi NON vengono sincronizzati via Bluetooth P2P (sono
//   esclusi dal sync CRDT per evitare conflitti — ogni catechista
//   gestisce la propria libreria personale).
//
// STRUTTURA:
//   - title: nome del contenuto (es. "La parabola del buon samaritano")
//   - tags: etichette per categorizzazione (es. ["Vangelo", "Parabole"])
//   - biblicalReferences: passi biblici (es. ["Lc 10,25-37"])
//   - websiteReferences: link a risorse online (es. video, articoli)
//   - photoIds: lista di Attachment.id per le foto associate
//   - description: testo libero di spiegazione/approfondimento
//   - createdAt/updatedAt: timestamp per ordinamento e sync (anche se
//     i record non vengono sincronizzati, i timestamp servono per la
//     UI e per eventuale futuro export)
//
// RELAZIONI:
//   Catechesi (1) ──< (N) Attachment  [via parentId + parentType='catechesi']
//   Catechesi (N) ──< (N) PlanningMeeting  (associazione opzionale via UI)
// ══════════════════════════════════════════════════════════════════════════════

class Catechesi {
  /// ID univoco del contenuto catechetico.
  final String id;

  /// Titolo del contenuto (es. "La parabola del buon samaritano").
  final String title;

  /// Etichette di categorizzazione (es. ["Vangelo", "Parabole", "Misericordia"]).
  final List<String> tags;

  /// Riferimenti biblici (es. ["Lc 10,25-37", "Mt 5,1-12"]).
  final List<String> biblicalReferences;

  /// Link a risorse web (es. video YouTube, articoli, podcast).
  final List<String> websiteReferences;

  /// ID degli Attachment associati (foto illustrative).
  final List<String> photoIds;

  /// Descrizione/approfondimento del contenuto (testo libero).
  final String description;

  /// Timestamp di creazione (UTC, ISO 8601).
  final DateTime createdAt;

  /// Timestamp dell'ultima modifica (UTC, ISO 8601).
  final DateTime updatedAt;

  Catechesi({
    required this.id,
    required this.title,
    required this.tags,
    required this.biblicalReferences,
    required this.websiteReferences,
    required this.photoIds,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  Catechesi copyWith({
    String? id,
    String? title,
    List<String>? tags,
    List<String>? biblicalReferences,
    List<String>? websiteReferences,
    List<String>? photoIds,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Catechesi(
      id: id ?? this.id,
      title: title ?? this.title,
      tags: tags ?? this.tags,
      biblicalReferences: biblicalReferences ?? this.biblicalReferences,
      websiteReferences: websiteReferences ?? this.websiteReferences,
      photoIds: photoIds ?? this.photoIds,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'tags': tags,
      'biblicalReferences': biblicalReferences,
      'websiteReferences': websiteReferences,
      'photoIds': photoIds,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Catechesi.fromMap(String id, Map<String, dynamic> data) {
    return Catechesi(
      id: id,
      title: data['title'] ?? '',
      tags: (data['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      biblicalReferences: (data['biblicalReferences'] as List<dynamic>?)?.cast<String>() ?? [],
      websiteReferences: (data['websiteReferences'] as List<dynamic>?)?.cast<String>() ?? [],
      photoIds: (data['photoIds'] as List<dynamic>?)?.cast<String>() ?? [],
      description: data['description'] ?? '',
      createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(data['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
