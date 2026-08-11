// ══════════════════════════════════════════════════════════════════════════════
// substitute_delegation.dart — CatechHub (modello delega supplenza temporanea)
//
// Modulo "Supplenze Temporanee e Delega Sicura". Rappresenta una delega con cui
// il catechista Titolare di una classe abilita temporaneamente un altro
// catechista della parrocchia (il Supplente) a
//   - prendere le presenze
//   - aggiungere note di lezione
// per l'intervallo [valid_from, valid_until].
//
// Il Supplente NON diventa membro permanente della classe (non compare in
// `catechistIds`): la visibilità è garantita SOLO dalla delega attiva e viene
// revocata alla scadenza o con la revoca manuale da parte del Titolare.
//
// CICLO DI VITA (status):
//   active    → valida (valid_from <= now <= valid_until)
//   expired   → scaduta naturalmente (ora > valid_until, dati non ancora acquisiti)
//   revoked   → revocata dal Titolare con "Termina Supplenza"
//   completed → acquisita dal Titolare E chiusa (chiave distrutta sul Supplente)
//
// CHIAVE TEMPORANEA:
//   `temporaryClassKey` trasporta la Class_Encryption_Key temporanea (AES-256).
//   Sul dispositivo del Titolare è la chiave da lui generata (usata per cifrare
//   i dati di consegna restituiti dal Supplente). Durante il handshake viaggia
//   cifrata con la chiave pubblica del Supplente.
// ══════════════════════════════════════════════════════════════════════════════

class SubstituteDelegationStatus {
  static const String active = 'active';
  static const String expired = 'expired';
  static const String revoked = 'revoked';
  static const String completed = 'completed';
}

class SubstituteDelegation {
  /// ID univoco della delega (formato `supp_<microsecondsSinceEpoch>`).
  final String delegationId;

  /// ID della classe delegata (stesso id su entrambi i dispositivi).
  final String classId;

  /// Codice univoco (40 cifre) della classe delegata.
  final String classUniqueCode;

  /// Nome della classe delegata.
  final String className;

  /// catechistId del catechista Titolare (proprietario della classe).
  final String ownerCatechistId;

  /// Nome visualizzato del Titolare.
  final String ownerName;

  /// Chiave pubblica X25519 (base64) dell'identità P2P del dispositivo del
  /// Titolare. Serve al Supplente per derivare il segreto condiviso ECDH.
  final String ownerPublicKey;

  /// catechistId del catechista Supplente (destinatario della delega).
  final String substituteCatechistId;

  /// Nome visualizzato del Supplente.
  final String substituteName;

  /// deviceId P2P del dispositivo che ha accettato la delega (target).
  final String substituteDeviceId;

  /// Inizio validità della supplenza (UTC).
  final DateTime validFrom;

  /// Fine validità della supplenza (UTC).
  final DateTime validUntil;

  /// Class_Encryption_Key temporanea (AES-256, base64) generata dal Titolare.
  /// Sul dispositivo del Titolare è la chiave in chiaro da lui generata; nel
  /// QR di handshake viene trasportata cifrata con la chiave pubblica.
  final String temporaryClassKey;

  /// Stato del ciclo di vita (vedi [SubstituteDelegationStatus]).
  final String status;

  /// True se il Titolare ha già acquisito presenze e note dal Supplente.
  final bool dataCollected;

  /// Chunk QR della delega (persistiti sul dispositivo del Titolare per poter
  /// rispettare il QR senza rigenerare una nuova chiave temporanea).
  final List<Map<String, dynamic>> qrChunks;

  /// Timestamp creazione (UTC, ISO 8601).
  final DateTime createdAt;

  /// Timestamp ultima modifica (UTC, ISO 8601).
  final DateTime updatedAt;

  SubstituteDelegation({
    required this.delegationId,
    required this.classId,
    required this.classUniqueCode,
    required this.className,
    required this.ownerCatechistId,
    required this.ownerName,
    required this.ownerPublicKey,
    required this.substituteCatechistId,
    required this.substituteName,
    required this.substituteDeviceId,
    required this.validFrom,
    required this.validUntil,
    required this.temporaryClassKey,
    this.status = SubstituteDelegationStatus.active,
    this.dataCollected = false,
    this.qrChunks = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  /// True se la delega è ancora valida nell'istante corrente.
  bool isActiveAt(DateTime now, {String? asStatus}) {
    final s = asStatus ?? status;
    if (s != SubstituteDelegationStatus.active) return false;
    return !now.isBefore(validFrom) && !now.isAfter(validUntil);
  }

  /// True se l'intervallo di validità è scaduto rispetto a [now].
  bool isExpiredAt(DateTime now) => now.isAfter(validUntil);

  SubstituteDelegation copyWith({
    String? status,
    bool? dataCollected,
    List<Map<String, dynamic>>? qrChunks,
    DateTime? updatedAt,
    DateTime? validFrom,
    DateTime? validUntil,
  }) {
    return SubstituteDelegation(
      delegationId: delegationId,
      classId: classId,
      classUniqueCode: classUniqueCode,
      className: className,
      ownerCatechistId: ownerCatechistId,
      ownerName: ownerName,
      ownerPublicKey: ownerPublicKey,
      substituteCatechistId: substituteCatechistId,
      substituteName: substituteName,
      substituteDeviceId: substituteDeviceId,
      validFrom: validFrom ?? this.validFrom,
      validUntil: validUntil ?? this.validUntil,
      temporaryClassKey: temporaryClassKey,
      status: status ?? this.status,
      dataCollected: dataCollected ?? this.dataCollected,
      qrChunks: qrChunks ?? this.qrChunks,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'delegationId': delegationId,
      'classId': classId,
      'classUniqueCode': classUniqueCode,
      'className': className,
      'ownerCatechistId': ownerCatechistId,
      'ownerName': ownerName,
      'ownerPublicKey': ownerPublicKey,
      'substituteCatechistId': substituteCatechistId,
      'substituteName': substituteName,
      'substituteDeviceId': substituteDeviceId,
      'validFrom': validFrom.toUtc().toIso8601String(),
      'validUntil': validUntil.toUtc().toIso8601String(),
      'temporaryClassKey': temporaryClassKey,
      'status': status,
      'dataCollected': dataCollected,
      'qrChunks': qrChunks,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory SubstituteDelegation.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    return SubstituteDelegation(
      delegationId: data['delegationId']?.toString() ?? id,
      classId: data['classId']?.toString() ?? '',
      classUniqueCode: data['classUniqueCode']?.toString() ?? '',
      className: data['className']?.toString() ?? '',
      ownerCatechistId: data['ownerCatechistId']?.toString() ?? '',
      ownerName: data['ownerName']?.toString() ?? '',
      ownerPublicKey: data['ownerPublicKey']?.toString() ?? '',
      substituteCatechistId: data['substituteCatechistId']?.toString() ?? '',
      substituteName: data['substituteName']?.toString() ?? '',
      substituteDeviceId: data['substituteDeviceId']?.toString() ?? '',
      validFrom:
          DateTime.tryParse(data['validFrom']?.toString() ?? '') ?? DateTime.now(),
      validUntil:
          DateTime.tryParse(data['validUntil']?.toString() ?? '') ?? DateTime.now(),
      temporaryClassKey: data['temporaryClassKey']?.toString() ?? '',
      status: data['status']?.toString() ?? SubstituteDelegationStatus.active,
      dataCollected: data['dataCollected'] == true,
      qrChunks: (data['qrChunks'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      createdAt:
          DateTime.tryParse(data['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(data['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  /// Conversione temporale sicura di una data (da ISO 8601 UTC).
  static DateTime parseUtc(String? raw, DateTime fallback) {
    final parsed = DateTime.tryParse(raw ?? '');
    return parsed == null ? fallback : parsed.toUtc();
  }
}

/// Nota di lezione registrata dal Supplente durante una supplenza.
class SubstituteLessonNote {
  final String noteId;
  final String delegationId;
  final String classId;
  final String classUniqueCode;
  final DateTime date;
  final String note;
  final String authorName;
  final DateTime createdAt;

  SubstituteLessonNote({
    required this.noteId,
    required this.delegationId,
    required this.classId,
    required this.classUniqueCode,
    required this.date,
    required this.note,
    required this.authorName,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  Map<String, dynamic> toMap() => {
        'noteId': noteId,
        'delegationId': delegationId,
        'classId': classId,
        'classUniqueCode': classUniqueCode,
        'date': date.toUtc().toIso8601String(),
        'note': note,
        'authorName': authorName,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory SubstituteLessonNote.fromMap(String id, Map<String, dynamic> data) {
    return SubstituteLessonNote(
      noteId: data['noteId']?.toString() ?? id,
      delegationId: data['delegationId']?.toString() ?? '',
      classId: data['classId']?.toString() ?? '',
      classUniqueCode: data['classUniqueCode']?.toString() ?? '',
      date: SubstituteDelegation.parseUtc(data['date']?.toString(), DateTime.now()),
      note: data['note']?.toString() ?? '',
      authorName: data['authorName']?.toString() ?? '',
      createdAt: SubstituteDelegation.parseUtc(
        data['createdAt']?.toString(),
        DateTime.now(),
      ),
    );
  }
}