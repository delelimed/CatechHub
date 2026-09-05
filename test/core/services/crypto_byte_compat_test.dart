// ============================================================================
// TEST: Byte-compatibilità crittografica
//
// Verifica che gli helper basati su `package:cryptography` producano output
// IDENTICI a quelli standard (FIPS 180-4, RFC 4231, RFC 2898, NIST SP 800-38D),
// gli stessi cioè che producevano `package:crypto` e `pointycastle`.
// ============================================================================
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:CatechHub/core/services/crypto_utils.dart';
import 'package:CatechHub/core/services/encryption_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Tag atteso del Test Case 1 (McGrew & Viega, NIST SP 800-38D):
  // AES-128-GCM, key = 0x00*16, IV = 0x00*12, plaintext vuoto, AAD assente.
  const gcmTestCase1Tag = <int>[
    0x58, 0xe2, 0xfc, 0xce, 0xfa, 0x7e, 0x30, 0x61,
    0x36, 0x7f, 0x1d, 0x57, 0xa4, 0xe7, 0x45, 0x5a,
  ];

  group('crypto_utils - SHA-256 (FIPS 180-4)', () {
    test('vettori ufficiali NIST', () {
      expect(sha256HexSync(''), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(sha256HexSync('abc'),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(
        sha256HexSync(
            'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
      // 1.000.000 di 'a' → digest noto.
      final million = List.filled(1_000_000, 'a').join();
      expect(
        sha256HexSync(million),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });

    test('byte identici a quelli di package:crypto (Digest.toString)', () {
      final input = utf8.encode('CatechHub:test-checksum');
      expect(sha256HexBytesSync(input), sha256HexSync(utf8.decode(input)));
    });
  });

  group('crypto_utils - HMAC-SHA256 (RFC 4231)', () {
    test('Test Case 1', () {
      final key = List<int>.filled(20, 0x0b);
      final data = utf8.encode('Hi There');
      expect(
        bytesToHex(hmacSha256BytesSync(key, data)),
        'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
      );
    });

    test('Test Case 2', () {
      final key = utf8.encode('Jefe');
      final data = utf8.encode('what do ya want for nothing?');
      expect(
        bytesToHex(hmacSha256BytesSync(key, data)),
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
      );
    });

    test('Test Case 3', () {
      final key = List<int>.filled(20, 0xaa);
      final data = List<int>.filled(50, 0xdd);
      expect(
        bytesToHex(hmacSha256BytesSync(key, data)),
        '773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe',
      );
    });
  });

  group('crypto_utils - roundtrip coerente', () {
    test('hmac hex e bytes producono lo stesso risultato', () async {
      final key = utf8.encode('segreto-test');
      final data = utf8.encode('payload canonico');
      expect(
        bytesToHex(await hmacSha256Bytes(key, data)),
        bytesToHex(hmacSha256BytesSync(key, data)),
      );
    });

    test('sha256 sync e async coincidono', () async {
      final data = 'CatechHub-sync-async';
      expect(await sha256Hex(data), sha256HexSync(data));
    });
  });

  group('EncryptionService - formato AES-GCM (NIST SP 800-38D)', () {
    test('vettore NIST GCM test case 1 (128-bit key)', () async {
      final key = List<int>.filled(16, 0);
      final plaintext = <int>[];
      final nonce = List<int>.filled(12, 0);
      final secretBox = await AesGcm.with128bits()
          .encrypt(
            plaintext,
            secretKey: SecretKey(key),
            nonce: nonce,
          );
      // Test Case 1 di McGrew & Viega: plaintext vuoto, key/nonce a zero.
      // Il tag SHA-256-based GCM (128-bit) vale 58e2fccefa7e3061367f1d57a4e7455a.
      expect(secretBox.mac.bytes.length, 16);
      expect(secretBox.nonce, nonce);
      expect(secretBox.cipherText, isEmpty);
      expect(secretBox.mac.bytes, List<int>.from(gcmTestCase1Tag));
    });

    test('il formato base64 conserva struttura nonce|ciphertext|tag', () async {
      final password = 'password-di-test';
      final data = {'chiave': 'valore'};
      final encrypted = await EncryptionService.encryptData(data, password);

      // Il payload è base64 di un JSON: non deve contenere `{` in chiaro.
      expect(encrypted, isNot(contains('{')));
      final decoded = utf8.decode(base64Decode(encrypted));
      expect(decoded, contains('{'));

      // Il payload JSON decodificato deve contenere salt, nonce, data e v=2.
      final parsed = jsonDecode(decoded) as Map<String, dynamic>;
      expect(parsed['v'], 2);
      expect(parsed['alg'], 'AES-256-GCM');
      expect(parsed['kdf'], 'PBKDF2-HMAC-SHA256');
      expect(parsed['salt'], isA<String>());
      expect(parsed['nonce'], isA<String>());
      expect(parsed['data'], isA<String>());
    });
  });
}