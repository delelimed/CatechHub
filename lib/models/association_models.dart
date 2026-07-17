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
