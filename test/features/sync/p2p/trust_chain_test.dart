import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:CatechHub/features/sync/data/association_models.dart';
import 'package:CatechHub/features/sync/p2p/p2p_security_service.dart';

void main() {
  group('AssociatedDevice canonicalPayload', () {
    test('il payload canonico è deterministico', () {
      final cert = AssociatedDevice(
        deviceId: 'CH_123',
        catechistId: 'cat_1',
        publicKey: 'pubkey',
        authorizedByResponsabile: true,
        timestampApproval: DateTime.utc(2026, 7, 15, 12),
        approvedByDeviceId: 'CH_resp_1',
        expiresAt: DateTime.utc(2026, 8, 15, 12),
      );

      final p1 = cert.canonicalPayload;
      final cert2 = AssociatedDevice(
        deviceId: 'CH_123',
        catechistId: 'cat_1',
        publicKey: 'pubkey',
        authorizedByResponsabile: true,
        timestampApproval: DateTime.utc(2026, 7, 15, 12),
        approvedByDeviceId: 'CH_resp_1',
        expiresAt: DateTime.utc(2026, 8, 15, 12),
      );
      expect(p1, cert2.canonicalPayload);
    });

    test('il payload canonico cambia se cambia la scadenza', () {
      final base = AssociatedDevice(
        deviceId: 'CH_123',
        catechistId: 'cat_1',
        publicKey: 'pubkey',
        authorizedByResponsabile: true,
        timestampApproval: DateTime.utc(2026, 7, 15, 12),
        approvedByDeviceId: 'CH_resp_1',
        expiresAt: DateTime.utc(2026, 8, 15, 12),
      );
      final other = base.copyWith(expiresAt: DateTime.utc(2026, 9, 15, 12));
      expect(base.canonicalPayload, isNot(other.canonicalPayload));
    });

    test('toJson/fromJson è reversibile', () {
      final cert = AssociatedDevice(
        deviceId: 'CH_123',
        catechistId: 'cat_1',
        publicKey: 'pubkey',
        authorizedByResponsabile: true,
        timestampApproval: DateTime.utc(2026, 7, 15, 12),
        deviceName: 'Tablet',
        approvedByDeviceId: 'CH_resp_1',
        approvedByName: 'Don Rossi',
        approvalSignature: 'sig123',
        signerPublicKey: 'signer_pub',
        expiresAt: DateTime.utc(2026, 8, 15, 12),
      );

      final restored = AssociatedDevice.fromJson(cert.toJson());
      expect(restored.deviceId, cert.deviceId);
      expect(restored.approvalSignature, 'sig123');
      expect(restored.approvedByName, 'Don Rossi');
      expect(restored.publicKey, 'pubkey');
      expect(restored.expiresAt, isNotNull);
      expect(restored.expiresAt!.isAtSameMomentAs(cert.expiresAt!), isTrue);
    });
  });

  group('P2PSecurityService trust chain (Ed25519)', () {
    late SimpleKeyPair keyPair;
    late List<int> privateKeyBytes;
    late String publicKeyBase64;

    setUp(() async {
      keyPair = await Ed25519().newKeyPair();
      privateKeyBytes = await keyPair.extractPrivateKeyBytes();
      final publicKey = await keyPair.extractPublicKey();
      publicKeyBase64 = base64Encode(publicKey.bytes);
    });

    final cert = AssociatedDevice(
      deviceId: 'CH_123',
      catechistId: 'cat_1',
      publicKey: 'pubkey',
      authorizedByResponsabile: true,
      timestampApproval: DateTime.utc(2026, 7, 15, 12),
      approvedByDeviceId: 'CH_resp_1',
      signerPublicKey: 'signer_pub',
      expiresAt: DateTime.utc(2026, 8, 15, 12),
    );

    test('la firma asimmetrica verifica con la chiave pubblica', () async {
      final sig = await P2PSecurityService.signApprovalPayload(
        cert.canonicalPayload,
        privateKeyBytes,
      );
      final ok = await P2PSecurityService.verifyApprovalSignature(
        canonicalPayload: cert.canonicalPayload,
        signature: sig,
        publicKeyBase64: publicKeyBase64,
      );
      expect(ok, isTrue);
    });

    test('non verifica con chiave pubblica diversa', () async {
      final sig = await P2PSecurityService.signApprovalPayload(
        cert.canonicalPayload,
        privateKeyBytes,
      );
      final otherKey = await Ed25519().newKeyPair();
      final otherPub = await otherKey.extractPublicKey();
      final ok = await P2PSecurityService.verifyApprovalSignature(
        canonicalPayload: cert.canonicalPayload,
        signature: sig,
        publicKeyBase64: base64Encode(otherPub.bytes),
      );
      expect(ok, isFalse);
    });

    test('non verifica se il payload è stato alterato', () async {
      final sig = await P2PSecurityService.signApprovalPayload(
        cert.canonicalPayload,
        privateKeyBytes,
      );
      final tampered = cert.copyWith(
        timestampApproval: DateTime.utc(2026, 7, 16, 12),
      );
      final ok = await P2PSecurityService.verifyApprovalSignature(
        canonicalPayload: tampered.canonicalPayload,
        signature: sig,
        publicKeyBase64: publicKeyBase64,
      );
      expect(ok, isFalse);
    });

    test(
      'la chiave pubblica non permette di falsificare (mitM defense)',
      () async {
        // Anche conoscendo la sola chiave pubblica non si può produrre una firma
        // valida per un payload arbitrario.
        final forged = await P2PSecurityService.signApprovalPayload(
          'payload_forgiato',
          privateKeyBytes,
        );
        final ok = await P2PSecurityService.verifyApprovalSignature(
          canonicalPayload: cert.canonicalPayload,
          signature: forged,
          publicKeyBase64: publicKeyBase64,
        );
        expect(ok, isFalse);
      },
    );

    test('firma base64 stabile attraverso JSON', () async {
      final sig = await P2PSecurityService.signApprovalPayload(
        cert.canonicalPayload,
        privateKeyBytes,
      );
      final decoded =
          jsonDecode(jsonEncode({'sig': sig})) as Map<String, dynamic>;
      expect(decoded['sig'], sig);
    });
  });
}
