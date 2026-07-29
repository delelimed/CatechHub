import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:CatechHub/features/sync/p2p/p2p_security_service.dart';

void main() {
  group('P2PDeviceAssociation', () {
    test('toJson e fromJson sono reversibili', () {
      final now = DateTime(2026, 7, 15);
      final original = P2PDeviceAssociation(
        deviceId: 'CH_1743290112345678_a1b2c3',
        deviceName: 'Tablet Catechista',
        publicKeyBase64: base64Encode([1, 2, 3, 4, 5]),
        fingerprint: 'abcd1234:efgh5678',
        sharedSecretBase64: base64Encode(List.generate(32, (i) => i)),
        associatedAt: now,
        devicePrivateKeyBase64: base64Encode([10, 20, 30]),
        devicePublicKeyBase64: base64Encode([40, 50, 60]),
        localRole: 'catechist',
        remoteRole: 'catechist',
      );

      final json = original.toJson();
      final restored = P2PDeviceAssociation.fromJson(json);

      expect(restored.deviceId, original.deviceId);
      expect(restored.deviceName, original.deviceName);
      expect(restored.publicKeyBase64, original.publicKeyBase64);
      expect(restored.fingerprint, original.fingerprint);
      expect(restored.sharedSecretBase64, original.sharedSecretBase64);
      expect(restored.associatedAt, original.associatedAt);
      expect(restored.devicePrivateKeyBase64, original.devicePrivateKeyBase64);
      expect(restored.devicePublicKeyBase64, original.devicePublicKeyBase64);
      expect(restored.localRole, original.localRole);
      expect(restored.remoteRole, original.remoteRole);
    });

    test('fromJson gestisce campi opzionali mancanti', () {
      final json = {
        'deviceId': 'CH_test_id',
        'deviceName': 'Test',
        'publicKey': 'dGVzdF9rZXk=',
        'fingerprint': 'fp',
        'sharedSecret': 'c2VjcmV0',
        'associatedAt': '2026-07-15T10:00:00.000Z',
        'devicePrivateKey': 'cHJpdmF0ZQ==',
        'devicePublicKey': 'cHVibGlj',
      };

      final assoc = P2PDeviceAssociation.fromJson(json);

      expect(assoc.deviceId, 'CH_test_id');
      expect(assoc.deviceName, 'Test');
      expect(assoc.localRole, isNull);
      expect(assoc.remoteRole, isNull);
    });

    test('isValid restituisce true per associazione recente', () {
      final assoc = P2PDeviceAssociation(
        deviceId: 'd1',
        deviceName: 'Recent',
        publicKeyBase64: 'key',
        fingerprint: 'fp',
        sharedSecretBase64: 'secret',
        associatedAt: DateTime.now().subtract(const Duration(days: 1)),
        devicePrivateKeyBase64: 'pk',
        devicePublicKeyBase64: 'pub',
      );

      expect(assoc.isValid, isTrue);
    });

    test('isValid restituisce false per associazione scaduta (>30 giorni)', () {
      final assoc = P2PDeviceAssociation(
        deviceId: 'd1',
        deviceName: 'Expired',
        publicKeyBase64: 'key',
        fingerprint: 'fp',
        sharedSecretBase64: 'secret',
        associatedAt: DateTime.now().subtract(const Duration(days: 31)),
        devicePrivateKeyBase64: 'pk',
        devicePublicKeyBase64: 'pub',
      );

      expect(assoc.isValid, isFalse);
    });

    test('daysRemaining calcola correttamente i giorni residui', () {
      final assoc = P2PDeviceAssociation(
        deviceId: 'd1',
        deviceName: 'Test',
        publicKeyBase64: 'key',
        fingerprint: 'fp',
        sharedSecretBase64: 'secret',
        associatedAt: DateTime.now().subtract(const Duration(days: 5)),
        devicePrivateKeyBase64: 'pk',
        devicePublicKeyBase64: 'pub',
      );

      expect(assoc.daysRemaining, 25);
    });

    test('daysRemaining restituisce 0 per associazione scaduta', () {
      final assoc = P2PDeviceAssociation(
        deviceId: 'd1',
        deviceName: 'Expired',
        publicKeyBase64: 'key',
        fingerprint: 'fp',
        sharedSecretBase64: 'secret',
        associatedAt: DateTime.now().subtract(const Duration(days: 40)),
        devicePrivateKeyBase64: 'pk',
        devicePublicKeyBase64: 'pub',
      );

      expect(assoc.daysRemaining, 0);
    });
  });

  group('P2PIdentity', () {
    test('toJson e fromJson sono reversibili', () {
      final original = P2PIdentity(
        deviceId: 'CH_test_device',
        deviceName: 'Tablet Catechista',
        username: 'Mario Rossi',
        publicKeyBase64: base64Encode([1, 2, 3, 4, 5]),
        fingerprint: 'abcd1234:efgh5678',
        connectionEndpoint: 'CH_test_device',
      );

      final json = original.toJson();
      final restored = P2PIdentity.fromJson(json);

      expect(restored.deviceId, original.deviceId);
      expect(restored.deviceName, original.deviceName);
      expect(restored.username, original.username);
      expect(restored.publicKeyBase64, original.publicKeyBase64);
      expect(restored.fingerprint, original.fingerprint);
      expect(restored.connectionEndpoint, original.connectionEndpoint);
    });

    test('encode e decode sono reversibili', () {
      final original = P2PIdentity(
        deviceId: 'CH_test_device',
        deviceName: 'Tablet Catechista',
        username: 'Mario Rossi',
        publicKeyBase64: base64Encode([10, 20, 30, 40, 50]),
        fingerprint: 'fp:fp',
        connectionEndpoint: 'CH_test_device',
      );

      final encoded = original.encode();
      final decoded = P2PIdentity.decode(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.deviceId, original.deviceId);
      expect(decoded.deviceName, original.deviceName);
    });

    test('decode restituisce null per input non valido', () {
      final decoded = P2PIdentity.decode('non_valido');
      expect(decoded, isNull);
    });

    test('fromJson gestisce identita legacy v1', () {
      final json = {
        'deviceId': 'CH_legacy',
        'deviceName': 'Legacy',
        'username': 'Vecchio Catechista',
        'publicKey': base64Encode([1, 2, 3]),
        'fingerprint': 'fp',
        'endpoint': 'CH_legacy',
      };

      final identity = P2PIdentity.fromJson(json);

      expect(identity.deviceId, 'CH_legacy');
      expect(identity.deviceName, 'Legacy');
      expect(identity.username, 'Legacy');
    });

    test('fromJson gestisce versione 2 (username separato)', () {
      final json = {
        'deviceId': 'CH_v2',
        'deviceName': 'Device',
        'username': 'Catechista',
        'publicKey': base64Encode([1, 2, 3]),
        'fingerprint': 'fp',
        'endpoint': 'CH_v2',
        'v': 2,
      };

      final identity = P2PIdentity.fromJson(json);

      expect(identity.username, 'Catechista');
      expect(identity.deviceName, 'Device');
    });
  });

  group('P2PEncryptedPayload', () {
    test('toJson e fromJson sono reversibili', () {
      final original = P2PEncryptedPayload(
        ciphertext: Uint8List.fromList([1, 2, 3, 4, 5]),
        nonce: Uint8List.fromList([10, 11, 12, 13]),
        mac: Uint8List.fromList([20, 21, 22, 23, 24]),
        useChacha: true,
      );

      final json = original.toJson();
      final restored = P2PEncryptedPayload.fromJson(json);

      expect(restored.ciphertext, original.ciphertext);
      expect(restored.nonce, original.nonce);
      expect(restored.mac, original.mac);
      expect(restored.useChacha, original.useChacha);
    });

    test('decode e encode sono reversibili', () {
      final original = P2PEncryptedPayload(
        ciphertext: Uint8List.fromList([1, 2, 3, 4, 5]),
        nonce: Uint8List.fromList([10, 11, 12, 13]),
        mac: Uint8List.fromList([20, 21, 22, 23, 24]),
      );

      final encoded = original.encode();
      final decoded = P2PEncryptedPayload.decode(encoded);

      expect(decoded.ciphertext, original.ciphertext);
      expect(decoded.nonce, original.nonce);
      expect(decoded.mac, original.mac);
    });

    test('fromJson riconosce algoritmo aes-256-gcm', () {
      final json = {
        'nonce': base64Encode([1, 2, 3]),
        'ciphertext': base64Encode([4, 5, 6]),
        'mac': base64Encode([7, 8, 9]),
        'alg': 'aes-256-gcm',
      };

      final payload = P2PEncryptedPayload.fromJson(json);
      expect(payload.useChacha, isFalse);
    });

    test('fromJson riconosce algoritmo chacha20-poly1305', () {
      final json = {
        'nonce': base64Encode([1, 2, 3]),
        'ciphertext': base64Encode([4, 5, 6]),
        'mac': base64Encode([7, 8, 9]),
        'alg': 'chacha20-poly1305',
      };

      final payload = P2PEncryptedPayload.fromJson(json);
      expect(payload.useChacha, isTrue);
    });
  });
}
