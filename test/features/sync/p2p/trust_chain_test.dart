import 'dart:convert';

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
      );

      final p1 = cert.canonicalPayload;
      final cert2 = AssociatedDevice(
        deviceId: 'CH_123',
        catechistId: 'cat_1',
        publicKey: 'pubkey',
        authorizedByResponsabile: true,
        timestampApproval: DateTime.utc(2026, 7, 15, 12),
        approvedByDeviceId: 'CH_resp_1',
      );
      expect(p1, cert2.canonicalPayload);
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
      );

      final restored = AssociatedDevice.fromJson(cert.toJson());
      expect(restored.deviceId, cert.deviceId);
      expect(restored.approvalSignature, 'sig123');
      expect(restored.approvedByName, 'Don Rossi');
      expect(restored.publicKey, 'pubkey');
    });
  });

  group('P2PSecurityService trust chain (HMAC)', () {
    const secret = 'parish_secret_123';
    final cert = AssociatedDevice(
      deviceId: 'CH_123',
      catechistId: 'cat_1',
      publicKey: 'pubkey',
      authorizedByResponsabile: true,
      timestampApproval: DateTime.utc(2026, 7, 15, 12),
      approvedByDeviceId: 'CH_resp_1',
    );

    test('signatureMatches per lo stesso segreto', () {
      final sig = P2PSecurityService.signApprovalPayload(
        cert.canonicalPayload,
        secret,
      );
      final ok = P2PSecurityService.verifyApprovalSignature(
        canonicalPayload: cert.canonicalPayload,
        signature: sig,
        secret: secret,
      );
      expect(ok, isTrue);
    });

    test('non verifica con segreto diverso', () {
      final sig = P2PSecurityService.signApprovalPayload(
        cert.canonicalPayload,
        secret,
      );
      final ok = P2PSecurityService.verifyApprovalSignature(
        canonicalPayload: cert.canonicalPayload,
        signature: sig,
        secret: 'wrong_secret',
      );
      expect(ok, isFalse);
    });

    test('non verifica se il payload è stato alterato', () {
      final sig = P2PSecurityService.signApprovalPayload(
        cert.canonicalPayload,
        secret,
      );
      final tampered = cert.copyWith(
        timestampApproval: DateTime.utc(2026, 7, 16, 12),
      );
      final ok = P2PSecurityService.verifyApprovalSignature(
        canonicalPayload: tampered.canonicalPayload,
        signature: sig,
        secret: secret,
      );
      expect(ok, isFalse);
    });

    test('firma base64 stabile attraverso JSON', () {
      final sig = P2PSecurityService.signApprovalPayload(
        cert.canonicalPayload,
        secret,
      );
      final decoded = jsonDecode(jsonEncode({'sig': sig})) as Map<String, dynamic>;
      expect(decoded['sig'], sig);
    });
  });
}
