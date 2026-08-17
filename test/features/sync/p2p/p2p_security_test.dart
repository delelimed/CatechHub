import 'dart:convert';

import 'package:cryptography/cryptography.dart';
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

    // Fase 2 — item 6: le chiavi efimere vincolano il SAS alla sessione.
    test('chiavi efimere ordinate in modo canonico producono lo stesso codice',
        () {
      const sharedSecret = 'dGhpcyBpcyBhIHRlc3Qgc2VjcmV0';
      const sessionNonce = 'nonce_fisso';

      // I due peer scambiano le chiavi efimere; l'ordine locale/remoto è
      // invertito ma l'input canonico deve essere identico.
      final codeA = P2PSecurityService.computePairingCode(
        sharedSecret,
        sessionNonce: sessionNonce,
        localEphemeralPub: 'eph_local',
        remoteEphemeralPub: 'eph_remote',
      );
      final codeB = P2PSecurityService.computePairingCode(
        sharedSecret,
        sessionNonce: sessionNonce,
        localEphemeralPub: 'eph_remote',
        remoteEphemeralPub: 'eph_local',
      );

      expect(codeA, codeB);
    });

    test('una chiave efimera sostituita da un MitM cambia il codice', () {
      const sharedSecret = 'dGhpcyBpcyBhIHRlc3Qgc2VjcmV0';
      const sessionNonce = 'nonce_fisso';

      final codeLegit = P2PSecurityService.computePairingCode(
        sharedSecret,
        sessionNonce: sessionNonce,
        localEphemeralPub: 'eph_legit',
        remoteEphemeralPub: 'eph_legit',
      );
      final codeMitM = P2PSecurityService.computePairingCode(
        sharedSecret,
        sessionNonce: sessionNonce,
        localEphemeralPub: 'eph_legit',
        remoteEphemeralPub: 'eph_attacker',
      );

      expect(codeLegit, isNot(codeMitM));
    });

    test('senza sessionNonce le chiavi efimere bastano a vincolare il codice',
        () {
      const sharedSecret = 'dGhpcyBpcyBhIHRlc3Qgc2VjcmV0';

      final code1 = P2PSecurityService.computePairingCode(
        sharedSecret,
        localEphemeralPub: 'eph_1',
        remoteEphemeralPub: 'eph_2',
      );
      final code2 = P2PSecurityService.computePairingCode(
        sharedSecret,
        localEphemeralPub: 'eph_1',
        remoteEphemeralPub: 'eph_2',
      );
      final codeMitM = P2PSecurityService.computePairingCode(
        sharedSecret,
        localEphemeralPub: 'eph_1',
        remoteEphemeralPub: 'eph_rogue',
      );

      expect(code1, code2);
      expect(code1, isNot(codeMitM));
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

  group('P2PSecurityService.computeForwardSecretKey (forward secrecy)', () {
    test('entrambi i peer convergono sullo stesso segreto TripleDH', () async {
      final x25519 = X25519();

      // Coppie statiche di identità (uno per peer).
      final staticA = await x25519.newKeyPair();
      final staticB = await x25519.newKeyPair();
      final staticAPub = await staticA.extractPublicKey();
      final staticBPub = await staticB.extractPublicKey();

      // Coppie efimere generate per QUESTA sessione (non persistite).
      Future<SimpleKeyPairData> ephemeral() async {
        final kp = await x25519.newKeyPair();
        final pub = await kp.extractPublicKey();
        final priv = await kp.extractPrivateKeyBytes();
        return SimpleKeyPairData(
          priv,
          publicKey: SimplePublicKey(pub.bytes, type: KeyPairType.x25519),
          type: KeyPairType.x25519,
        );
      }

      final ephemA = await ephemeral();
      final ephemB = await ephemeral();
      final ephemAPub = await ephemA.extractPublicKey();
      final ephemBPub = await ephemB.extractPublicKey();

      // Peer A: static=A, ephem=A, remoto=B.
      final secretA = await P2PSecurityService.computeForwardSecretKey(
        x25519: x25519,
        localStatic: staticA,
        localEphemeral: ephemA,
        remoteStaticPublicKeyBase64: base64Encode(staticBPub.bytes),
        remoteEphemeralPublicKeyBase64: base64Encode(ephemBPub.bytes),
      );

      // Peer B: static=B, ephem=B, remoto=A.
      final secretB = await P2PSecurityService.computeForwardSecretKey(
        x25519: x25519,
        localStatic: staticB,
        localEphemeral: ephemB,
        remoteStaticPublicKeyBase64: base64Encode(staticAPub.bytes),
        remoteEphemeralPublicKeyBase64: base64Encode(ephemAPub.bytes),
      );

      expect(base64Encode(secretA), base64Encode(secretB));
    });

    test('il segreto cambia se l\'efimera remota cambia (chiave per-sessione)',
        () async {
      final x25519 = X25519();

      final staticA = await x25519.newKeyPair();
      final staticB = await x25519.newKeyPair();
      final staticBPub = await staticB.extractPublicKey();

      Future<SimpleKeyPairData> ephemeral() async {
        final kp = await x25519.newKeyPair();
        final pub = await kp.extractPublicKey();
        final priv = await kp.extractPrivateKeyBytes();
        return SimpleKeyPairData(
          priv,
          publicKey: SimplePublicKey(pub.bytes, type: KeyPairType.x25519),
          type: KeyPairType.x25519,
        );
      }

      // Stesse chiavi statiche ma efimera remota diversa → segreto diverso.
      final ephemB1 = await ephemeral();
      final ephemB2 = await ephemeral();
      final ephemB1Pub = await ephemB1.extractPublicKey();
      final ephemB2Pub = await ephemB2.extractPublicKey();

      final secret1 = await P2PSecurityService.computeForwardSecretKey(
        x25519: x25519,
        localStatic: staticA,
        localEphemeral: await ephemeral(),
        remoteStaticPublicKeyBase64: base64Encode(staticBPub.bytes),
        remoteEphemeralPublicKeyBase64: base64Encode(ephemB1Pub.bytes),
      );
      final secret2 = await P2PSecurityService.computeForwardSecretKey(
        x25519: x25519,
        localStatic: staticA,
        localEphemeral: await ephemeral(),
        remoteStaticPublicKeyBase64: base64Encode(staticBPub.bytes),
        remoteEphemeralPublicKeyBase64: base64Encode(ephemB2Pub.bytes),
      );

      expect(base64Encode(secret1), isNot(base64Encode(secret2)));
    });
  });
}
