import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class P2PIdentity {
  final String deviceId;
  final String deviceName;
  final String publicKeyBase64;
  final String fingerprint;

  const P2PIdentity({
    required this.deviceId,
    required this.deviceName,
    required this.publicKeyBase64,
    required this.fingerprint,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'publicKey': publicKeyBase64,
        'fingerprint': fingerprint,
        'v': 2,
      };

  factory P2PIdentity.fromJson(Map<String, dynamic> json) => P2PIdentity(
        deviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String? ?? '',
        publicKeyBase64: json['publicKey'] as String,
        fingerprint: json['fingerprint'] as String,
      );

  String encode() => base64Encode(utf8.encode(jsonEncode(toJson())));

  static P2PIdentity? decode(String raw) {
    try {
      final decoded = utf8.decode(base64Decode(raw));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      return P2PIdentity.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}

class P2PSession {
  final String remoteDeviceId;
  final String remoteDeviceName;
  final SecretKeyData sessionKey;
  final Uint8List handshakeNonce;
  final DateTime createdAt;
  final bool isInitiator;

  P2PSession({
    required this.remoteDeviceId,
    required this.remoteDeviceName,
    required this.sessionKey,
    required this.handshakeNonce,
    required this.createdAt,
    required this.isInitiator,
  });

  bool get isValid => DateTime.now().difference(createdAt).inMinutes < 30;
}

class P2PDeviceAssociation {
  final String deviceId;
  final String deviceName;
  final String publicKeyBase64;
  final String fingerprint;
  final String sharedSecretBase64;
  final DateTime associatedAt;

  const P2PDeviceAssociation({
    required this.deviceId,
    required this.deviceName,
    required this.publicKeyBase64,
    required this.fingerprint,
    required this.sharedSecretBase64,
    required this.associatedAt,
  });

  bool get isValid => DateTime.now().difference(associatedAt).inDays < 30;

  int get daysRemaining {
    final elapsed = DateTime.now().difference(associatedAt).inDays;
    final remaining = 30 - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'publicKey': publicKeyBase64,
        'fingerprint': fingerprint,
        'sharedSecret': sharedSecretBase64,
        'associatedAt': associatedAt.toUtc().toIso8601String(),
      };

  factory P2PDeviceAssociation.fromJson(Map<String, dynamic> json) =>
      P2PDeviceAssociation(
        deviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String? ?? '',
        publicKeyBase64: json['publicKey'] as String,
        fingerprint: json['fingerprint'] as String? ?? '',
        sharedSecretBase64: json['sharedSecret'] as String,
        associatedAt: DateTime.parse(json['associatedAt'] as String).toLocal(),
      );
}

class P2PEncryptedPayload {
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;
  final bool useChacha;

  P2PEncryptedPayload({
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    this.useChacha = false,
  });

  Map<String, dynamic> toJson() => {
        'nonce': base64Encode(nonce),
        'ciphertext': base64Encode(ciphertext),
        'mac': base64Encode(mac),
        'alg': useChacha ? 'chacha20-poly1305' : 'aes-256-gcm',
      };

  factory P2PEncryptedPayload.fromJson(Map<String, dynamic> json) =>
      P2PEncryptedPayload(
        nonce: Uint8List.fromList(base64Decode(json['nonce'] as String)),
        ciphertext:
            Uint8List.fromList(base64Decode(json['ciphertext'] as String)),
        mac: Uint8List.fromList(base64Decode(json['mac'] as String)),
        useChacha: json['alg'] == 'chacha20-poly1305',
      );

  String encode() => base64Encode(utf8.encode(jsonEncode(toJson())));

  static P2PEncryptedPayload decode(String raw) {
    final map =
        jsonDecode(utf8.decode(base64Decode(raw))) as Map<String, dynamic>;
    return P2PEncryptedPayload.fromJson(map);
  }
}

final _sha256Algo = Sha256();

String _bytesToHex(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class P2PSecurityService {
  static const _storagePrefix = 'p2p_assoc_';
  static const _localKeyPairName = 'p2p_local_keypair';
  static const _localIdentityKey = 'p2p_local_identity';

  final FlutterSecureStorage _secureStorage;
  final X25519 _x25519 = X25519();

  P2PSecurityService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static Uint8List secureRandom(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  Future<SimpleKeyPair> getOrCreateKeyPair() async {
    final stored = await _secureStorage.read(key: _localKeyPairName);
    if (stored != null && stored.isNotEmpty) {
      try {
        final data = jsonDecode(stored) as Map<String, dynamic>;
        final privBytes = base64Decode(data['private'] as String);
        final pubBytes = base64Decode(data['public'] as String);
        return SimpleKeyPairData(
          privBytes,
          publicKey: SimplePublicKey(pubBytes, type: KeyPairType.x25519),
          type: KeyPairType.x25519,
        );
      } catch (_) {}
    }
    return _generateAndStoreKeyPair();
  }

  Future<SimpleKeyPair> _generateAndStoreKeyPair() async {
    final keyPair = await _x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyData = await keyPair.extractPrivateKeyBytes();
    final stored = jsonEncode({
      'private': base64Encode(privateKeyData),
      'public': base64Encode(publicKey.bytes),
    });
    await _secureStorage.write(key: _localKeyPairName, value: stored);
    return keyPair;
  }

  Future<P2PIdentity> getLocalIdentity() async {
    final stored = await _secureStorage.read(key: _localIdentityKey);
    if (stored != null && stored.isNotEmpty) {
      try {
        return P2PIdentity.fromJson(jsonDecode(stored) as Map<String, dynamic>);
      } catch (_) {}
    }
    return _createAndStoreIdentity();
  }

  Future<P2PIdentity> _createAndStoreIdentity() async {
    final keyPair = await getOrCreateKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final deviceId =
        'CH_${DateTime.now().microsecondsSinceEpoch}_${_randomHex(6)}';
    final deviceName = await _getDeviceDisplayName();
    final fingerprint = await _computeFingerprint(publicKey);

    final identity = P2PIdentity(
      deviceId: deviceId,
      deviceName: deviceName,
      publicKeyBase64: base64Encode(publicKey.bytes),
      fingerprint: fingerprint,
    );
    await _secureStorage.write(
        key: _localIdentityKey, value: jsonEncode(identity.toJson()));
    return identity;
  }

  Future<String> _getDeviceDisplayName() async {
    try {
      const prefs = FlutterSecureStorage();
      final name = await prefs.read(key: 'device_display_name');
      if (name != null && name.trim().isNotEmpty) {
        return name.trim();
      }
    } catch (_) {}
    return 'CatechHub ${_randomHex(4)}';
  }

  String _randomHex(int length) {
    final random = Random.secure();
    return List.generate(length, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  Future<String> getPublicKeyBase64() async {
    final keyPair = await getOrCreateKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  Future<String> getFingerprint() async {
    final identity = await getLocalIdentity();
    return identity.fingerprint;
  }

  Future<String> generateQrPayload() async {
    final identity = await getLocalIdentity();
    return identity.encode();
  }

  static P2PIdentity? parseQrPayload(String raw) {
    return P2PIdentity.decode(raw);
  }

  Future<String> computeStaticSharedSecret(String remotePublicKeyBase64) async {
    final remoteKeyBytes = base64Decode(remotePublicKeyBase64);
    final keyPair = await getOrCreateKeyPair();

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(remoteKeyBytes, type: KeyPairType.x25519),
    );

    final secretBytes = await sharedSecret.extractBytes();
    return base64Encode(secretBytes);
  }

  Future<P2PSession> createEphemeralSession({
    required String remoteDeviceId,
    required String remoteDeviceName,
    required String remotePublicKeyBase64,
    bool isInitiator = false,
  }) async {
    final ephemeralKeyPair = await X25519().newKeyPair();
    final remoteKeyBytes = base64Decode(remotePublicKeyBase64);
    final myKeyPair = await getOrCreateKeyPair();

    final staticShared = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: SimplePublicKey(remoteKeyBytes, type: KeyPairType.x25519),
    );
    final staticBytes = await staticShared.extractBytes();

    final ecdhe = await _x25519.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: SimplePublicKey(remoteKeyBytes, type: KeyPairType.x25519),
    );
    final ecdheBytes = await ecdhe.extractBytes();

    final handshakeNonce = secureRandom(32);

    final hkdf = Hkdf(
      hmac: Hmac(_sha256Algo),
      outputLength: 32,
    );

    final info = utf8.encode(
        'CatechHub_P2P_Session_v2:$remoteDeviceId:${isInitiator ? 'init' : 'resp'}');

    final inputKeyMaterial = Uint8List(staticBytes.length + ecdheBytes.length + handshakeNonce.length);
    inputKeyMaterial.setAll(0, staticBytes);
    inputKeyMaterial.setAll(staticBytes.length, ecdheBytes);
    inputKeyMaterial.setAll(staticBytes.length + ecdheBytes.length, handshakeNonce);

    final sessionKeyData = await hkdf.deriveKey(
      secretKey: SecretKey(inputKeyMaterial),
      nonce: handshakeNonce,
      info: info,
    );

    return P2PSession(
      remoteDeviceId: remoteDeviceId,
      remoteDeviceName: remoteDeviceName,
      sessionKey: sessionKeyData,
      handshakeNonce: handshakeNonce,
      createdAt: DateTime.now(),
      isInitiator: isInitiator,
    );
  }

  Future<P2PEncryptedPayload> encryptPayload(
    String plainText,
    SecretKey sessionKey,
  ) async {
    final nonce = secureRandom(12);
    final secretBox = await AesGcm.with256bits().encrypt(
      utf8.encode(plainText),
      secretKey: sessionKey,
      nonce: nonce,
    );

    return P2PEncryptedPayload(
      nonce: Uint8List.fromList(secretBox.nonce),
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      mac: Uint8List.fromList(secretBox.mac.bytes),
      useChacha: false,
    );
  }

  Future<String> decryptPayload(
    P2PEncryptedPayload encrypted,
    SecretKey sessionKey,
  ) async {
    final secretBox = SecretBox(
      encrypted.ciphertext,
      nonce: encrypted.nonce,
      mac: Mac(encrypted.mac),
    );

    final plainBytes = await AesGcm.with256bits().decrypt(
      secretBox,
      secretKey: sessionKey,
    );

    return utf8.decode(plainBytes);
  }

  Future<String> encryptPayloadString(
    String plainText,
    String sharedSecretBase64,
  ) async {
    final key = base64Decode(sharedSecretBase64);
    final nonce = secureRandom(12);
    final secretKey = SecretKey(key);

    final secretBox = await AesGcm.with256bits().encrypt(
      utf8.encode(plainText),
      secretKey: secretKey,
      nonce: nonce,
    );

    final payload = P2PEncryptedPayload(
      nonce: Uint8List.fromList(secretBox.nonce),
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      mac: Uint8List.fromList(secretBox.mac.bytes),
    );
    return payload.encode();
  }

  Future<String> decryptPayloadString(
    String cipherText,
    String sharedSecretBase64,
  ) async {
    final key = base64Decode(sharedSecretBase64);
    final secretKey = SecretKey(key);
    final encrypted = P2PEncryptedPayload.decode(cipherText);

    final secretBox = SecretBox(
      encrypted.ciphertext,
      nonce: encrypted.nonce,
      mac: Mac(encrypted.mac),
    );

    final plainBytes = await AesGcm.with256bits().decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return utf8.decode(plainBytes);
  }

  Future<void> saveAssociation(P2PDeviceAssociation association) async {
    final key = '$_storagePrefix${association.deviceId}';
    await _secureStorage.write(
      key: key,
      value: jsonEncode(association.toJson()),
    );
  }

  Future<P2PDeviceAssociation?> getAssociation(String deviceId) async {
    final key = '$_storagePrefix$deviceId';
    final raw = await _secureStorage.read(key: key);
    if (raw == null) return null;
    try {
      final assoc =
          P2PDeviceAssociation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (!assoc.isValid) {
        await removeAssociation(deviceId);
        return null;
      }
      return assoc;
    } catch (_) {
      return null;
    }
  }

  Future<List<P2PDeviceAssociation>> getAllAssociations() async {
    final allKeys = await _secureStorage.readAll();
    final associations = <P2PDeviceAssociation>[];
    final expiredKeys = <String>[];

    for (final entry in allKeys.entries) {
      if (!entry.key.startsWith(_storagePrefix)) continue;
      try {
        final assoc = P2PDeviceAssociation.fromJson(
          jsonDecode(entry.value) as Map<String, dynamic>,
        );
        if (assoc.isValid) {
          associations.add(assoc);
        } else {
          expiredKeys.add(entry.key);
        }
      } catch (_) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      await _secureStorage.delete(key: key);
    }

    associations.sort((a, b) => b.associatedAt.compareTo(a.associatedAt));
    return associations;
  }

  Future<void> removeAssociation(String deviceId) async {
    await _secureStorage.delete(key: '$_storagePrefix$deviceId');
  }

  Future<void> removeAllAssociations() async {
    final allKeys = await _secureStorage.readAll();
    for (final key in allKeys.keys) {
      if (key.startsWith(_storagePrefix)) {
        await _secureStorage.delete(key: key);
      }
    }
  }

  Future<bool> hasValidAssociation() async {
    final associations = await getAllAssociations();
    return associations.isNotEmpty;
  }

  Future<String?> getSharedSecret(String deviceId) async {
    final assoc = await getAssociation(deviceId);
    return assoc?.sharedSecretBase64;
  }
}

Future<String> _computeFingerprint(SimplePublicKey publicKey) async {
  final hash = await _sha256Algo.hash(publicKey.bytes);
  final hex = _bytesToHex(hash.bytes);
  return '${hex.substring(0, 8)}:${hex.substring(8, 16)}:'
      '${hex.substring(16, 24)}:${hex.substring(24, 32)}';
}
