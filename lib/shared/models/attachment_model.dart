// ══════════════════════════════════════════════════════════════════════════════
// attachment_model.dart — CatechHub (modello allegato/file)
//
// Rappresenta un file allegato (immagine, PDF, documento) associato a
// una delle entità del sistema: studente, incontro o contenuto catechetico.
// I file fisici sono memorizzati in un catalogo cifrato su disco locale.
//
// CONTESTO PROGETTO:
//   Gli allegati sono un modulo trasversale: qualsiasi entità può avere
//   attachment associati tramite parentId + parentType:
//   - Student: foto profilo, documenti scansionati, certificati
//   - PlanningMeeting: materiale didattico, volantini
//   - Catechesi: foto di riferimento, schede attività
//
//   AttachmentParentType definisce le costanti per parentType:
//   'student', 'meeting', 'catechesi'.
//
// STORAGE:
//   - Metadati: Hive box "attachments_box"
//   - File fisici: directory cifrata ottenuta tramite path_provider,
//     con nome file = fileHash per deduplicazione
//
// SICUREZZA:
//   I file sono memorizzati cifrati a riposo (AES-256-GCM). La chiave
//   di cifratura è derivata dal PIN del catechista tramite PBKDF2.
//
// UTILITY:
//   - sizeLabel: formatta la dimensione in B/KB/MB (leggibile)
//   - isImage: true per mimeType "image/*"
//   - isPdf: true per mimeType "application/pdf"
// ══════════════════════════════════════════════════════════════════════════════

class Attachment {
  /// ID univoco dell'allegato.
  final String id;

  /// FK verso l'entità proprietaria (Student.id, PlanningMeeting.id, Catechesi.id).
  final String parentId;

  /// Tipo dell'entità proprietaria ('student', 'meeting', 'catechesi').
  /// Valori: AttachmentParentType.student / meeting / catechesi.
  final String parentType;

  /// Codice univoco di 40 cifre della classe associata (se parent è
  /// class-scoped). Copia ridondante per sync multi-classe.
  final String? classUniqueCode;

  /// Nome visualizzato del file (es. "certificato_battesimo.jpg").
  final String name;

  /// MIME type del file (es. "image/jpeg", "application/pdf").
  final String mimeType;

  /// Dimensione del file in byte.
  final int size;

  /// Timestamp di creazione/upload dell'allegato.
  final DateTime createdAt;

  /// Hash SHA-256 del contenuto del file. Usato come nome file su
  /// disco per deduplicazione: stesso hash = stesso file, evitando
  /// copie duplicate.
  final String fileHash;

  /// Descrizione opzionale dell'allegato (testo libero).
  final String? description;

  /// Timestamp dell'ultima modifica (UTC, ISO 8601).
  final DateTime updatedAt;

  /// Nome del catechista che ha modificato per ultimo questo record.
  final String lastModifiedBy;

  Attachment({
    required this.id,
    required this.parentId,
    required this.parentType,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.createdAt,
    required this.fileHash,
    this.classUniqueCode,
    this.description,
    DateTime? updatedAt,
    this.lastModifiedBy = '',
  }) : updatedAt = updatedAt ?? createdAt;

  factory Attachment.fromMap(String id, Map<String, dynamic> data) {
    return Attachment(
      id: id,
      parentId: data['parentId'] ?? '',
      parentType: data['parentType'] ?? '',
      name: data['name'] ?? '',
      mimeType: data['mimeType'] ?? 'application/octet-stream',
      size: data['size'] ?? 0,
      createdAt:
          DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      fileHash: data['fileHash'] ?? '',
      classUniqueCode: data['classUniqueCode'],
      description: data['description'],
      updatedAt:
          DateTime.tryParse(data['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      lastModifiedBy: data['lastModifiedBy'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'parentId': parentId,
      'parentType': parentType,
      'name': name,
      'mimeType': mimeType,
      'size': size,
      'createdAt': createdAt.toIso8601String(),
      'fileHash': fileHash,
      'classUniqueCode': classUniqueCode,
      'description': description,
      'updatedAt': updatedAt.toIso8601String(),
      'lastModifiedBy': lastModifiedBy,
    };
  }

  /// Dimensione in formato leggibile (es. "1.5 MB", "340 KB", "512 B").
  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// true se il file è un'immagine (mimeType inizia con "image/").
  bool get isImage => mimeType.startsWith('image/');

  /// true se il file è un PDF (mimeType == "application/pdf").
  bool get isPdf => mimeType == 'application/pdf';
}
