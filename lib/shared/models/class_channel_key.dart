// ══════════════════════════════════════════════════════════════════════════════
// class_channel_key.dart — CatechHub (chiave di canale per classe)
//
// Modello della "Rete Catechistica Parrocchiale": la chiave di cifratura
// per-classe che autorizza un dispositivo a LEGGERE i dati riservati di una
// classe (anagrafica ragazzi, presenze, note, numeri genitori).
//
// CONTESTO PROGETTO:
//   I dati di una classe (Class Channel) vengono scambiati nella rete P2P
//   parrocchiale SEMPRE cifrati con questa chiave AES-256 (Class_Encryption_Key).
//   Un dispositivo "Senza Titolo" per la classe riceve comunque i blob cifrati
//   (per aiutare la propagazione in rete locale), ma NON possiede la chiave e
//   quindi non può leggere il contenuto.
//
//   Il titolo di trattamento viene esteso esclusivamente dal Responsabile o dal
//   Catechista Titolare della classe tramite QR handshake (vedi
//   ClassChannelService.createKeyGrant/importKeyGrant) o tramite bootstrap
//   in-band durante il sync P2P per i membri riconosciuti della classe.
//
// STORAGE:
//   Salvata nel box Hive "class_channel_keys_box" (Map) con chiave = classId.
//   Un dispositivo conserva SOLO le chiavi delle classi per cui ha titolo.
// ══════════════════════════════════════════════════════════════════════════════

class ClassChannelKey {
  /// ID della classe (SchoolClass.id).
  final String classId;

  /// Codice univoco di 40 cifre della classe (SchoolClass.uniqueCode).
  final String classUniqueCode;

  /// Nome della classe al momento della concessione (solo informativo).
  final String className;

  /// Chiave AES-256 (32 byte) in Base64. È il segreto della classe.
  final String keyBase64;

  /// Fingerprint SHA-256 della chiave (identifica la versione della chiave).
  final String keyId;

  /// CatechistId del Responsabile/Titolare che ha concesso il titolo.
  final String grantorCatechistId;

  /// Timestamp di concessione (UTC, ISO 8601).
  final DateTime grantedAt;

  /// true = chiave valida. false = titolo revocato (la chiave resta per
  /// eventuale rotazione ma non autorizza più la decifratura dei nuovi dati).
  final bool isActive;

  const ClassChannelKey({
    required this.classId,
    required this.classUniqueCode,
    required this.className,
    required this.keyBase64,
    required this.keyId,
    required this.grantorCatechistId,
    required this.grantedAt,
    this.isActive = true,
  });

  ClassChannelKey copyWith({
    String? classId,
    String? classUniqueCode,
    String? className,
    String? keyBase64,
    String? keyId,
    String? grantorCatechistId,
    DateTime? grantedAt,
    bool? isActive,
  }) {
    return ClassChannelKey(
      classId: classId ?? this.classId,
      classUniqueCode: classUniqueCode ?? this.classUniqueCode,
      className: className ?? this.className,
      keyBase64: keyBase64 ?? this.keyBase64,
      keyId: keyId ?? this.keyId,
      grantorCatechistId: grantorCatechistId ?? this.grantorCatechistId,
      grantedAt: grantedAt ?? this.grantedAt,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toMap() => {
    'classId': classId,
    'classUniqueCode': classUniqueCode,
    'className': className,
    'keyBase64': keyBase64,
    'keyId': keyId,
    'grantorCatechistId': grantorCatechistId,
    'grantedAt': grantedAt.toUtc().toIso8601String(),
    'isActive': isActive,
  };

  factory ClassChannelKey.fromMap(String id, Map<String, dynamic> data) =>
      ClassChannelKey(
        classId: data['classId']?.toString() ?? id,
        classUniqueCode: data['classUniqueCode']?.toString() ?? '',
        className: data['className']?.toString() ?? '',
        keyBase64: data['keyBase64']?.toString() ?? '',
        keyId: data['keyId']?.toString() ?? '',
        grantorCatechistId: data['grantorCatechistId']?.toString() ?? '',
        grantedAt:
            DateTime.tryParse(data['grantedAt']?.toString() ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
        isActive: data['isActive'] != false,
      );
}
