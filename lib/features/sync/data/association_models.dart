import 'dart:convert';

class DeviceAssociation {
  final String deviceId;
  final String deviceName;
  final String sharedSecretHex;
  final DateTime associatedAt;

  const DeviceAssociation({
    required this.deviceId,
    required this.deviceName,
    required this.sharedSecretHex,
    required this.associatedAt,
  });

  bool get isValid =>
      DateTime.now().difference(associatedAt).inDays < 30;

  int get daysRemaining {
    final elapsed = DateTime.now().difference(associatedAt).inDays;
    final remaining = 30 - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'sharedSecretHex': sharedSecretHex,
        'associatedAt': associatedAt.toUtc().toIso8601String(),
      };

  factory DeviceAssociation.fromJson(Map<String, dynamic> json) =>
      DeviceAssociation(
        deviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String,
        sharedSecretHex: json['sharedSecretHex'] as String,
        associatedAt:
            DateTime.parse(json['associatedAt'] as String).toLocal(),
      );
}

/// Dispositivo associato e la sua posizione nella catena di fiducia impostata
/// dal Responsabile Catechistico.
///
/// Quando la modalità Responsabile è ATTIVA, un dispositivo può avviare la
/// sincronizzazione di una classe SOLO se è stato preventivamente firmato dal
/// dispositivo del Responsabile (via QR Code o scambio P2P diretto). Questo
/// record rappresenta quella firma/approvazione.
///
/// Campi (per specifica):
///   - [deviceId]: identificatore univoco del dispositivo.
///   - [catechistId]: identità stabile del catechista che usa il dispositivo.
///   - [publicKey]: chiave pubblica del dispositivo (base64).
///   - [authorizedByResponsabile]: true se il Responsabile ha approvato il
///     dispositivo per la sincronizzazione delle classi.
///   - [timestampApproval]: data/ora dell'approvazione da parte del Responsabile.
class AssociatedDevice {
  final String deviceId;
  final String catechistId;
  final String publicKey;
  final bool authorizedByResponsabile;
  final DateTime? timestampApproval;

  /// Nome visualizzato del dispositivo (per le UI).
  final String deviceName;

  /// ID del dispositivo del Responsabile che ha firmato l'approvazione.
  final String? approvedByDeviceId;

  /// Nome del Responsabile che ha firmato l'approvazione (per le UI).
  final String? approvedByName;

  /// Firma (Ed25519) della catena di fiducia (su [canonicalPayload]).
  final String? approvalSignature;

  /// Chiave pubblica di firma Ed25519 del dispositivo del Responsabile che ha
  /// emesso il certificato (base64). Coincide con la trust root della parrocchia
  /// distribuita via QR di fiducia. La verifica è asimmetrica: conoscere la
  /// chiave pubblica non consente di falsificare certificati.
  final String? signerPublicKey;

  /// Scadenza del certificato di approvazione. I certificati scaduti vengono
  /// rifiutati dai dispositivi verificatori (forza una ri-approvazione).
  final DateTime? expiresAt;

  const AssociatedDevice({
    required this.deviceId,
    required this.catechistId,
    required this.publicKey,
    this.authorizedByResponsabile = false,
    this.timestampApproval,
    this.deviceName = '',
    this.approvedByDeviceId,
    this.approvedByName,
    this.approvalSignature,
    this.signerPublicKey,
    this.expiresAt,
  });

  bool get isApproved => authorizedByResponsabile;

  /// Payload canonico firmabile del certificato di approvazione.
  String get canonicalPayload {
    final ts = timestampApproval?.toUtc().millisecondsSinceEpoch ?? 0;
    final exp = expiresAt?.toUtc().millisecondsSinceEpoch ?? 0;
    return [
      deviceId,
      catechistId,
      publicKey,
      approvedByDeviceId ?? '',
      ts.toString(),
      exp.toString(),
    ].join('|');
  }

  AssociatedDevice copyWith({
    bool? authorizedByResponsabile,
    DateTime? timestampApproval,
    String? deviceName,
    String? approvedByDeviceId,
    String? approvedByName,
    String? approvalSignature,
    String? signerPublicKey,
    DateTime? expiresAt,
    bool clearApproval = false,
  }) {
    return AssociatedDevice(
      deviceId: deviceId,
      catechistId: catechistId,
      publicKey: publicKey,
      authorizedByResponsabile:
          clearApproval ? false : (authorizedByResponsabile ?? this.authorizedByResponsabile),
      timestampApproval:
          clearApproval ? null : (timestampApproval ?? this.timestampApproval),
      deviceName: deviceName ?? this.deviceName,
      approvedByDeviceId:
          clearApproval ? null : (approvedByDeviceId ?? this.approvedByDeviceId),
      approvedByName:
          clearApproval ? null : (approvedByName ?? this.approvedByName),
      approvalSignature:
          clearApproval ? null : (approvalSignature ?? this.approvalSignature),
      signerPublicKey:
          clearApproval ? null : (signerPublicKey ?? this.signerPublicKey),
      expiresAt:
          clearApproval ? null : (expiresAt ?? this.expiresAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'catechistId': catechistId,
        'publicKey': publicKey,
        'authorizedByResponsabile': authorizedByResponsabile,
        'timestampApproval': timestampApproval?.toUtc().toIso8601String(),
        'deviceName': deviceName,
        'approvedByDeviceId': approvedByDeviceId,
        'approvedByName': approvedByName,
        'approvalSignature': approvalSignature,
        'signerPublicKey': signerPublicKey,
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
      };

  factory AssociatedDevice.fromJson(Map<String, dynamic> json) =>
      AssociatedDevice(
        deviceId: json['deviceId'] as String,
        catechistId: json['catechistId'] as String? ?? '',
        publicKey: json['publicKey'] as String? ?? '',
        authorizedByResponsabile: json['authorizedByResponsabile'] == true,
        timestampApproval: json['timestampApproval'] != null
            ? DateTime.parse(json['timestampApproval'] as String).toLocal()
            : null,
        deviceName: json['deviceName'] as String? ?? '',
        approvedByDeviceId: json['approvedByDeviceId'] as String?,
        approvedByName: json['approvedByName'] as String?,
        approvalSignature: json['approvalSignature'] as String?,
        signerPublicKey: json['signerPublicKey'] as String?,
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String).toLocal()
            : null,
      );
}

class QrHandshake {
  final String deviceId;
  final String deviceName;
  final String publicKeyHex;
  final int timestamp;

  const QrHandshake({
    required this.deviceId,
    required this.deviceName,
    required this.publicKeyHex,
    required this.timestamp,
  });

  bool get isFresh =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000 - timestamp).abs() <= 120;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'publicKeyHex': publicKeyHex,
        'timestamp': timestamp,
      };

  factory QrHandshake.fromJson(Map<String, dynamic> json) => QrHandshake(
        deviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String,
        publicKeyHex: json['publicKeyHex'] as String,
        timestamp: json['timestamp'] as int,
      );

  String encode() => jsonEncode(toJson());

  static QrHandshake? decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final handshake = QrHandshake.fromJson(map);
      if (handshake.deviceId.isEmpty || handshake.publicKeyHex.isEmpty) {
        return null;
      }
      return handshake;
    } catch (_) {
      return null;
    }
  }
}
