import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:CatechHub/core/services/qr_data_service.dart';
import 'package:CatechHub/features/substitutes/substitute_delegation_service.dart';
import 'package:CatechHub/features/sync/p2p/p2p_security_service.dart';
import 'package:CatechHub/shared/models/substitute_delegation.dart';

/// Versione in-memory di [P2PSecurityService] che usa una coppia X25519
/// fornita dal test al posto del secure storage (non disponibile nei test
/// Dart puro). `computeStaticSharedSecret` ricalcola lo stesso ECDH del
/// servizio reale: DH(localPriv, remotePub).
class _FakeP2PSecurityService extends P2PSecurityService {
  final SimpleKeyPair localKeyPair;

  _FakeP2PSecurityService(this.localKeyPair) : super();

  @override
  Future<String> getPublicKeyBase64() async {
    final pub = await localKeyPair.extractPublicKey();
    return base64Encode(pub.bytes);
  }

  @override
  Future<String> computeStaticSharedSecret(
    String remotePublicKeyBase64, {
    String? forDeviceId,
  }) async {
    final shared = await X25519().sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: SimplePublicKey(
        base64Decode(remotePublicKeyBase64),
        type: KeyPairType.x25519,
      ),
    );
    return base64Encode(await shared.extractBytes());
  }
}

SubstituteDelegation _delegation({
  required String ownerPublicKey,
  required String substitutePublicKey,
}) {
  final now = DateTime.now().toUtc();
  return SubstituteDelegation(
    delegationId: 'supp_test_revoke',
    classId: 'class_1',
    classUniqueCode: '1234567890',
    className: 'Classe Test',
    ownerCatechistId: 'cat_owner',
    ownerName: 'Titolare',
    ownerPublicKey: ownerPublicKey,
    substituteCatechistId: 'cat_sub',
    substituteName: 'Supplente',
    substituteDeviceId: 'CH_SUB',
    substitutePublicKey: substitutePublicKey,
    validFrom: now.subtract(const Duration(hours: 1)),
    validUntil: now.add(const Duration(days: 1)),
    temporaryClassKey: SubstituteDelegationService.generateTempKey(),
  );
}

Future<String> _assembleRevoke(
  SubstituteDelegationService service,
  SubstituteDelegation delegation,
) async {
  final chunks = await service.buildRevokeQrChunks(delegation);
  final qrChunks = chunks.map(QRChunk.fromMap).toList();
  return QRDataService.assembleChunks(qrChunks);
}

void main() {
  group('Revoca supplenza (regressione C2)', () {
    test('la revoca firmata dal Titolare viene verificata dal Supplente',
        () async {
      final x25519 = X25519();
      final ownerKp = await x25519.newKeyPair();
      final subKp = await x25519.newKeyPair();
      final ownerPub = await ownerKp.extractPublicKey();
      final subPub = await subKp.extractPublicKey();

      final delegation = _delegation(
        ownerPublicKey: base64Encode(ownerPub.bytes),
        substitutePublicKey: base64Encode(subPub.bytes),
      );

      // Lato Titolare: firma la revoca con DH(owner_priv, sub_pub).
      final ownerService =
          SubstituteDelegationService(p2p: _FakeP2PSecurityService(ownerKp));
      final assembled = await _assembleRevoke(ownerService, delegation);

      // Lato Supplente: verifica con DH(sub_priv, owner_pub) → stesso segreto.
      final subService =
          SubstituteDelegationService(p2p: _FakeP2PSecurityService(subKp));
      final delegationId = await subService.verifyRevoke(assembled);

      expect(delegationId, delegation.delegationId);
    });

    test('una delega con chiave Supplente mancante non genera la revoca',
        () async {
      final x25519 = X25519();
      final ownerKp = await x25519.newKeyPair();
      final ownerPub = await ownerKp.extractPublicKey();

      final delegation = _delegation(
        ownerPublicKey: base64Encode(ownerPub.bytes),
        substitutePublicKey: '',
      );

      final ownerService =
          SubstituteDelegationService(p2p: _FakeP2PSecurityService(ownerKp));

      expect(
        () => ownerService.buildRevokeQrChunks(delegation),
        throwsA(isA<Exception>()),
      );
    });

    test('una revoca da un dispositivo NON-Titolare viene rifiutata', () async {
      final x25519 = X25519();
      final ownerKp = await x25519.newKeyPair();
      final subKp = await x25519.newKeyPair();
      final attackerKp = await x25519.newKeyPair();
      final ownerPub = await ownerKp.extractPublicKey();
      final subPub = await subKp.extractPublicKey();

      final delegation = _delegation(
        ownerPublicKey: base64Encode(ownerPub.bytes),
        substitutePublicKey: base64Encode(subPub.bytes),
      );

      // L'attaccante firma con DH(attacker_priv, sub_pub): segreto diverso
      // da quello che il Supplente può ricalcolare → firma non valida.
      final attackerService =
          SubstituteDelegationService(p2p: _FakeP2PSecurityService(attackerKp));
      final assembled = await _assembleRevoke(attackerService, delegation);

      final subService =
          SubstituteDelegationService(p2p: _FakeP2PSecurityService(subKp));
      final delegationId = await subService.verifyRevoke(assembled);

      expect(delegationId, isNull);
    });

    test('un payload con delegationId alterato viene rifiutato', () async {
      final x25519 = X25519();
      final ownerKp = await x25519.newKeyPair();
      final subKp = await x25519.newKeyPair();
      final ownerPub = await ownerKp.extractPublicKey();
      final subPub = await subKp.extractPublicKey();

      final delegation = _delegation(
        ownerPublicKey: base64Encode(ownerPub.bytes),
        substitutePublicKey: base64Encode(subPub.bytes),
      );

      final ownerService =
          SubstituteDelegationService(p2p: _FakeP2PSecurityService(ownerKp));
      final chunks = await ownerService.buildRevokeQrChunks(delegation);
      final assembled = QRDataService.assembleChunks(
        chunks.map(QRChunk.fromMap).toList(),
      );

      // Alterazione del payload firmato: si modifica il delegationId nel body
      // JSON (la firma HMAC non lo copre più) mantenendo il trasporto valido.
      final wrapper = QRDataService.decompressData(assembled);
      final body = jsonDecode(
        utf8.decode(base64Decode(wrapper['body'] as String)),
      ) as Map<String, dynamic>;
      body['delegationId'] = 'supp_altro_id';
      wrapper['body'] = base64Encode(utf8.encode(jsonEncode(body)));
      final tampered = QRDataService.compressData(wrapper);

      final subService =
          SubstituteDelegationService(p2p: _FakeP2PSecurityService(subKp));
      final delegationId = await subService.verifyRevoke(tampered);

      expect(delegationId, isNull);
    });
  });
}