import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:CatechHub/features/sync/p2p/p2p_security_service.dart';

void main() {
  group('P2PSecurityService.computePairingCode', () {
    test('genera un codice di 6 cifre', () {
      final code = P2PSecurityService.computePairingCode(
        base64Encode([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]),
      );
      expect(code.length, 6);
      expect(int.tryParse(code), isA<int>());
    });

    test('codici diversi con sessionNonce diverso', () {
      const sharedSecret = 'dGhpcyBpcyBhIHRlc3Qgc2VjcmV0';

      final code1 = P2PSecurityService.computePairingCode(
        sharedSecret,
        sessionNonce: 'nonce_a',
      );
      final code2 = P2PSecurityService.computePairingCode(
        sharedSecret,
        sessionNonce: 'nonce_b',
      );

      expect(code1, isNot(code2));
    });

    test('lo stesso input produce lo stesso codice', () {
      const sharedSecret = 'dGhpcyBpcyBhIHRlc3Qgc2VjcmV0';

      final code1 = P2PSecurityService.computePairingCode(
        sharedSecret,
        sessionNonce: 'nonce_fisso',
      );
      final code2 = P2PSecurityService.computePairingCode(
        sharedSecret,
        sessionNonce: 'nonce_fisso',
      );

      expect(code1, code2);
    });

    test('codice con nonce singolo (fallback) funziona', () {
      const sharedSecret = 'c2VjcmV0';

      final code = P2PSecurityService.computePairingCode(sharedSecret);

      expect(code.length, 6);
      expect(int.tryParse(code), isA<int>());
    });

    test('nonce diverso dallo stesso shared secret produce codici diversi', () {
      const sharedSecret = 'dGhpcyBpcyBhIHRlc3Qgc2VjcmV0';

      final codes = <String>{};
      for (int i = 0; i < 10; i++) {
        final code = P2PSecurityService.computePairingCode(
          sharedSecret,
          sessionNonce: 'nonce_$i',
        );
        codes.add(code);
      }

      expect(codes.length, greaterThan(5));
    });
  });

  group('P2PSecurityService.publicKeyMatchesAssociation', () {
    test('restituisce true se la chiave corrisponde', () {
      final assoc = P2PDeviceAssociation(
        deviceId: 'device_1',
        deviceName: 'Test Device',
        publicKeyBase64: 'test_public_key',
        fingerprint: 'fingerprint',
        sharedSecretBase64: 'shared_secret',
        associatedAt: DateTime.now(),
        devicePrivateKeyBase64: 'private_key',
        devicePublicKeyBase64: 'public_key',
      );

      expect(
        P2PSecurityService.publicKeyMatchesAssociation(
          assoc,
          'test_public_key',
        ),
        isTrue,
      );
    });

    test('restituisce false se la chiave non corrisponde', () {
      final assoc = P2PDeviceAssociation(
        deviceId: 'device_1',
        deviceName: 'Test Device',
        publicKeyBase64: 'original_key',
        fingerprint: 'fingerprint',
        sharedSecretBase64: 'shared_secret',
        associatedAt: DateTime.now(),
        devicePrivateKeyBase64: 'private_key',
        devicePublicKeyBase64: 'public_key',
      );

      expect(
        P2PSecurityService.publicKeyMatchesAssociation(
          assoc,
          'different_key',
        ),
        isFalse,
      );
    });
  });

  group('P2PSecurityService.secureRandom', () {
    test('genera il numero richiesto di byte', () {
      final bytes = P2PSecurityService.secureRandom(32);
      expect(bytes.length, 32);
    });

    test('genera output diverso ogni volta', () {
      final bytes1 = P2PSecurityService.secureRandom(16);
      final bytes2 = P2PSecurityService.secureRandom(16);
      expect(bytes1, isNot(bytes2));
    });
  });
}
