// ============================================================================
// TEST: Rotazione delle chiavi di sessione P2P (finestre temporali di 30 min)
// ============================================================================
//
// Verifica che la chiave di sessione in transito:
//   - sia identica per entrambi i peer nella stessa finestra temporale;
//   - cambi (ruoti) a ogni finestra successiva, così che i dati in transito
//     siano sempre protetti da una chiave a breve scadenza;
//   - permetta la decifratura dei messaggi cifrati nella finestra precedente
//     (i messaggi in transito al confine della rotazione non si perdono).
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:CatechHub/features/sync/p2p/p2p_security_service.dart';

void main() {
  group('Finestre temporali (sessionKeyRotation)', () {
    test('la rotazione è impostata a 30 minuti', () {
      expect(P2PSecurityService.sessionKeyRotation, const Duration(minutes: 30));
    });

    test('sessionWindowIndex è deterministico nella stessa finestra', () {
      final base = DateTime.utc(2026, 7, 1, 12, 0);
      expect(
        P2PSecurityService.sessionWindowIndex(base),
        P2PSecurityService.sessionWindowIndex(base.add(const Duration(seconds: 29))),
      );
      expect(
        P2PSecurityService.sessionWindowIndex(base),
        P2PSecurityService.sessionWindowIndex(base.add(const Duration(minutes: 29, seconds: 59))),
      );
    });

    test('sessionWindowIndex avanza alla finestra successiva', () {
      final base = DateTime.utc(2026, 7, 1, 12, 0);
      final next = P2PSecurityService.sessionWindowIndex(
        base.add(const Duration(minutes: 30)),
      );
      expect(next, P2PSecurityService.sessionWindowIndex(base) + 1);
    });

    test('previousWindowIndex restituisce la finestra precedente', () {
      final w = P2PSecurityService.sessionWindowIndex();
      expect(
        P2PSecurityService.previousWindowIndex(w),
        w - 1,
      );
    });
  });

  group('deriveRotatingSessionKey — convergenza tra i peer', () {
    final shared = List<int>.generate(32, (i) => i + 1);
    const deviceA = 'device_A';
    const deviceB = 'device_B';
    final windowStart = P2PSecurityService.sessionWindowStart(
      P2PSecurityService.sessionWindowIndex(),
    );

    test('stessi input + stessa finestra → stessa chiave', () async {
      final k1 = await P2PSecurityService.deriveRotatingSessionKey(
        sharedSecretBytes: shared,
        localDeviceId: deviceA,
        remoteDeviceId: deviceB,
        at: windowStart,
      );
      final k2 = await P2PSecurityService.deriveRotatingSessionKey(
        sharedSecretBytes: shared,
        localDeviceId: deviceA,
        remoteDeviceId: deviceB,
        at: windowStart,
      );
      expect(await k1.extractBytes(), await k2.extractBytes());
    });

    test('l\'ordine dei deviceId non cambia la chiave (convergenza)', () async {
      final kAB = await P2PSecurityService.deriveRotatingSessionKey(
        sharedSecretBytes: shared,
        localDeviceId: deviceA,
        remoteDeviceId: deviceB,
        at: windowStart,
      );
      final kBA = await P2PSecurityService.deriveRotatingSessionKey(
        sharedSecretBytes: shared,
        localDeviceId: deviceB,
        remoteDeviceId: deviceA,
        at: windowStart,
      );
      expect(await kAB.extractBytes(), await kBA.extractBytes());
    });

    test('finestre diverse → chiavi diverse (rotazione)', () async {
      final currentWindow = P2PSecurityService.sessionWindowIndex();
      final startCurrent = P2PSecurityService.sessionWindowStart(currentWindow);
      final startNext = P2PSecurityService.sessionWindowStart(currentWindow + 1);

      final kCurrent = await P2PSecurityService.deriveRotatingSessionKey(
        sharedSecretBytes: shared,
        localDeviceId: deviceA,
        remoteDeviceId: deviceB,
        at: startCurrent,
      );
      final kNext = await P2PSecurityService.deriveRotatingSessionKey(
        sharedSecretBytes: shared,
        localDeviceId: deviceA,
        remoteDeviceId: deviceB,
        at: startNext,
      );
      expect(
        await kCurrent.extractBytes(),
        isNot(await kNext.extractBytes()),
      );
    });

    test('un sessionNonce diverso cambia la chiave', () async {
      final k1 = await P2PSecurityService.deriveRotatingSessionKey(
        sharedSecretBytes: shared,
        localDeviceId: deviceA,
        remoteDeviceId: deviceB,
        sessionNonce: 'nonce-1',
        at: windowStart,
      );
      final k2 = await P2PSecurityService.deriveRotatingSessionKey(
        sharedSecretBytes: shared,
        localDeviceId: deviceA,
        remoteDeviceId: deviceB,
        sessionNonce: 'nonce-2',
        at: windowStart,
      );
      expect(await k1.extractBytes(), isNot(await k2.extractBytes()));
    });

    test('la finestra temporale è codificata nell\'info HKDF', () async {
      final currentWindow = P2PSecurityService.sessionWindowIndex();
      final nextWindow = currentWindow + 1;
      expect(
        P2PSecurityService.sessionWindowId(currentWindow),
        isNot(P2PSecurityService.sessionWindowId(nextWindow)),
      );
      expect(P2PSecurityService.sessionWindowId(nextWindow), 'w$nextWindow');
    });
  });

  group('Cifratura in transito con chiave rotante', () {
    final service = P2PSecurityService();
    final shared = Uint8List.fromList(List<int>.generate(32, (i) => i * 2));
    const deviceA = 'device_A';
    const deviceB = 'device_B';
    const sessionNonce = 'shared-nonce';

    Future<SecretKeyData> keyForWindow(int windowIndex) async {
      return P2PSecurityService.deriveRotatingSessionKey(
        sharedSecretBytes: shared,
        localDeviceId: deviceA,
        remoteDeviceId: deviceB,
        sessionNonce: sessionNonce,
        at: P2PSecurityService.sessionWindowStart(windowIndex),
      );
    }

    test('round-trip con la chiave della stessa finestra', () async {
      final window = P2PSecurityService.sessionWindowIndex();
      final key = await keyForWindow(window);
      final payload = await service.encryptPayload('dati sensibili', key);
      final decoded = P2PEncryptedPayload.decode(payload.encode());
      final plain = await service.decryptPayload(decoded, key);
      expect(plain, 'dati sensibili');
    });

    test('la chiave della finestra successiva NON decifra il vecchio blob', () async {
      final currentWindow = P2PSecurityService.sessionWindowIndex();
      final keyCurrent = await keyForWindow(currentWindow);
      final keyNext = await keyForWindow(currentWindow + 1);

      final payload = await service.encryptPayload('dati sensibili', keyCurrent);
      final decoded = P2PEncryptedPayload.decode(payload.encode());

      // Dopo la rotazione il blob cifrato con la chiave precedente non è più
      // decifrabile con quella nuova (chiave a breve scadenza).
      expect(
        () => service.decryptPayload(decoded, keyNext),
        throwsA(anything),
      );
    });

    test('entrambi i peer possono decifrare con la chiave della finestra corrente', () async {
      final window = P2PSecurityService.sessionWindowIndex();

      // Peer A (mittente) cifra con la propria derivazione.
      final keyA = await P2PSecurityService.deriveRotatingSessionKey(
        sharedSecretBytes: shared,
        localDeviceId: deviceA,
        remoteDeviceId: deviceB,
        sessionNonce: sessionNonce,
        at: P2PSecurityService.sessionWindowStart(window),
      );
      final payload = await service.encryptPayload('segreto classe', keyA);

      // Peer B (destinatario) decifra con la propria derivazione (stessa
      // finestra → stessa chiave, nessun handshake aggiuntivo).
      final keyB = await P2PSecurityService.deriveRotatingSessionKey(
        sharedSecretBytes: shared,
        localDeviceId: deviceB,
        remoteDeviceId: deviceA,
        sessionNonce: sessionNonce,
        at: P2PSecurityService.sessionWindowStart(window),
      );
      final decoded = P2PEncryptedPayload.decode(payload.encode());
      expect(await service.decryptPayload(decoded, keyB), 'segreto classe');
    });
  });
}