import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/association_models.dart';

class AssociationSecurityService {
  static const _storagePrefix = 'assoc_';
  static const _localDeviceIdKey = 'assoc_local_device_id';
  static const _localKeyPairName = 'assoc_local_keypair';

  final FlutterSecureStorage _secureStorage;
  final X25519 _x25519 = X25519();

  AssociationSecurityService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static Uint8List secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  Future<String> getOrCreateDeviceId() async {
    final existing = await _secureStorage.read(key: _localDeviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final deviceId = 'CH_${DateTime.now().microsecondsSinceEpoch}';
    await _secureStorage.write(key: _localDeviceIdKey, value: deviceId);
    return deviceId;
  }

  Future<String> getLocalPublicKeyHex() async {
    final keyPair = await _getOrCreateKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  Future<SimpleKeyPair> _getOrCreateKeyPair() async {
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

  Future<String> computeSharedSecretHex(String remotePublicKeyHex) async {
    final remoteKeyBytes = base64Decode(remotePublicKeyHex);
    final keyPair = await _getOrCreateKeyPair();

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(
        remoteKeyBytes,
        type: KeyPairType.x25519,
      ),
    );

    final secretBytes = await sharedSecret.extractBytes();
    return base64Encode(secretBytes);
  }

  Future<String> encryptPayload(String plainText, String keyHex) async {
    final key = base64Decode(keyHex);
    final nonce = secureRandomBytes(12);
    final secretKey = SecretKey(key);

    final secretBox = await AesGcm.with256bits().encrypt(
      utf8.encode(plainText),
      secretKey: secretKey,
      nonce: nonce,
    );

    final package = {
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
    return base64Encode(utf8.encode(jsonEncode(package)));
  }

  Future<String> decryptPayload(String cipherText, String keyHex) async {
    try {
      final key = base64Decode(keyHex);
      final secretKey = SecretKey(key);
      final packageStr = utf8.decode(base64Decode(cipherText));
      final package = jsonDecode(packageStr) as Map<String, dynamic>;

      final nonce = base64Decode(package['nonce'] as String);
      final ciphertext = base64Decode(package['ciphertext'] as String);
      final macBytes = base64Decode(package['mac'] as String);

      final secretBox = SecretBox(
        ciphertext,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final plainBytes = await AesGcm.with256bits().decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return utf8.decode(plainBytes);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }

  Future<void> saveAssociation(DeviceAssociation association) async {
    final key = '$_storagePrefix${association.deviceId}';
    await _secureStorage.write(
      key: key,
      value: jsonEncode(association.toJson()),
    );
  }

  Future<DeviceAssociation?> getAssociation(String deviceId) async {
    final key = '$_storagePrefix$deviceId';
    final raw = await _secureStorage.read(key: key);
    if (raw == null) return null;

    try {
      final assoc =
          DeviceAssociation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (!assoc.isValid) {
        await removeAssociation(deviceId);
        return null;
      }
      return assoc;
    } catch (_) {
      return null;
    }
  }

  Future<List<DeviceAssociation>> getAllAssociations() async {
    final allKeys = await _secureStorage.readAll();
    final associations = <DeviceAssociation>[];
    final expiredKeys = <String>[];

    for (final entry in allKeys.entries) {
      if (!entry.key.startsWith(_storagePrefix)) continue;
      try {
        final assoc = DeviceAssociation.fromJson(
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
    return assoc?.sharedSecretHex;
  }

  Future<void> clearLocalKeys() async {
    await _secureStorage.delete(key: _localKeyPairName);
  }
}
