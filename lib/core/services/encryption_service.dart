import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;
import 'package:pointycastle/src/utils.dart';

class EncryptionService {
  static const int currentVersion = 2;
  static const int defaultIterations = 210000;
  static const int fastShareIterations = 12000;
  static const int saltLength = 16;
  static const int nonceLength = 12;
  static const int tagLengthBits = 128;

  static Uint8List secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  // ──────────────────────────────────────────────
  //  ECDH — SCAMBIO CHIAVI DIFFIE-HELLMAN (P-256)
  // ──────────────────────────────────────────────

  static final pc.ECDomainParameters _ecDomain = pc.ECCurve_secp256r1();

  static (Uint8List publicKeyBytes, pc.ECPrivateKey privateKey) generateEcdhKeyPair() {
    final keyParams = pc.ECKeyGeneratorParameters(_ecDomain);
    final secureRandom = _DartSecureRandom();
    final generator = pc.ECKeyGenerator()
      ..init(pc.ParametersWithRandom(keyParams, secureRandom));
    final keyPair = generator.generateKeyPair();
    final publicKeyBytes = keyPair.publicKey.Q!.getEncoded(true);
    final privateKey = keyPair.privateKey;
    return (publicKeyBytes, privateKey);
  }

  static Uint8List computeEcdhSharedSecret(
    Uint8List remotePublicKeyBytes,
    pc.ECPrivateKey localPrivateKey,
  ) {
    final point = _ecDomain.curve.decodePoint(remotePublicKeyBytes)!;
    final remotePublicKey = pc.ECPublicKey(point, _ecDomain);
    final agreement = pc.ECDHBasicAgreement()..init(localPrivateKey);
    final sharedSecret = agreement.calculateAgreement(remotePublicKey);
    final secretBytes = encodeBigIntAsUnsigned(sharedSecret);
    if (secretBytes.length >= 32) {
      return Uint8List.fromList(secretBytes.sublist(secretBytes.length - 32));
    }
    final padded = Uint8List(32);
    padded.setAll(32 - secretBytes.length, secretBytes);
    return padded;
  }

  static Uint8List deriveSessionKeyFromEcdh(
    Uint8List sharedSecret, Uint8List nonce, {
    String? deviceIdA, String? deviceIdB,
  }) {
    final hkdf = pc.HKDFKeyDerivator(pc.SHA256Digest());
    final infoParts = <String>['CatechHub_SessionKey_v2'];
    if (deviceIdA != null) infoParts.add(deviceIdA);
    if (deviceIdB != null) infoParts.add(deviceIdB);
    final info = Uint8List.fromList(utf8.encode(infoParts.join(':')));
    hkdf.init(pc.HkdfParameters(sharedSecret, 32, nonce, info));
    final sessionKey = Uint8List(32);
    hkdf.deriveKey(Uint8List(0), 0, sessionKey, 0);
    return sessionKey;
  }

  static String deriveSessionKey(
    Uint8List remotePublicKeyBytes, pc.ECPrivateKey localPrivateKey, Uint8List nonce, {
    String? deviceIdA, String? deviceIdB,
  }) {
    final sharedSecret = computeEcdhSharedSecret(remotePublicKeyBytes, localPrivateKey);
    final sessionKey = deriveSessionKeyFromEcdh(sharedSecret, nonce, deviceIdA: deviceIdA, deviceIdB: deviceIdB);
    return base64Encode(sessionKey);
  }

  // ──────────────────────────────────────────────
  //  PBKDF2 — DERIVAZIONE CHIAVE DA PASSWORD
  // ──────────────────────────────────────────────

  static Uint8List derivePasswordKeyBytes(
    String password, Uint8List salt, {
    int iterations = defaultIterations, int keyLength = 32,
  }) {
    final mac = pc.HMac(pc.SHA256Digest(), 64);
    final derivator = pc.PBKDF2KeyDerivator(mac)
      ..init(pc.Pbkdf2Parameters(salt, iterations, keyLength));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  static String generateSalt() {
    return base64Encode(secureRandomBytes(saltLength));
  }

  // ──────────────────────────────────────────────
  //  AES-256-GCM — CIFRATURA/DECIFRATURA
  // ──────────────────────────────────────────────

  static String encryptData(Map<String, dynamic> data, String password, {int iterations = defaultIterations}) {
    final salt = secureRandomBytes(saltLength);
    final nonce = secureRandomBytes(nonceLength);
    final key = derivePasswordKeyBytes(password, salt, iterations: iterations);
    final jsonData = jsonEncode(data);

    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(true, pc.AEADParameters(pc.KeyParameter(key), tagLengthBits, nonce, Uint8List(0)));

    final input = Uint8List.fromList(utf8.encode(jsonData));
    final out = Uint8List(cipher.getOutputSize(input.length));
    var len = cipher.processBytes(input, 0, input.length, out, 0);
    len += cipher.doFinal(out, len);
    final encrypted = Uint8List.view(out.buffer, 0, len);

    final package = {
      'v': currentVersion, 'kdf': 'PBKDF2-HMAC-SHA256', 'iter': iterations,
      'alg': 'AES-256-GCM', 'salt': base64Encode(salt), 'nonce': base64Encode(nonce),
      'data': base64Encode(encrypted),
    };
    return base64Encode(utf8.encode(jsonEncode(package)));
  }

  static Map<String, dynamic> decryptData(String encryptedData, String password) {
    try {
      final packageStr = utf8.decode(base64Decode(encryptedData));
      final package = jsonDecode(packageStr) as Map<String, dynamic>;

      if (package['v'] != currentVersion) {
        return _decryptLegacyPackage(package, password);
      }

      final iterations = package['iter'] as int;
      final salt = base64Decode(package['salt'] as String);
      final nonce = base64Decode(package['nonce'] as String);
      final dataBase64 = package['data'] as String;

      final key = derivePasswordKeyBytes(password, Uint8List.fromList(salt), iterations: iterations);

      final cipher = pc.GCMBlockCipher(pc.AESEngine())
        ..init(false, pc.AEADParameters(pc.KeyParameter(key), tagLengthBits, Uint8List.fromList(nonce), Uint8List(0)));

      final input = base64Decode(dataBase64);
      final out = Uint8List(cipher.getOutputSize(input.length));
      var len = cipher.processBytes(input, 0, input.length, out, 0);
      len += cipher.doFinal(out, len);
      final decryptedBytes = Uint8List.view(out.buffer, 0, len);

      try {
        final decrypted = utf8.decode(decryptedBytes);
        return jsonDecode(decrypted) as Map<String, dynamic>;
      } on FormatException {
        return _salvageJson(decryptedBytes);
      }
    } catch (e) {
      throw Exception('Password non valida o dati corrotti: $e');
    }
  }

  static bool verifyPassword(String encryptedData, String password) {
    try { decryptData(encryptedData, password); return true; } catch (e) { return false; }
  }

  static Map<String, dynamic> _salvageJson(Uint8List bytes) {
    final str = utf8.decode(bytes, allowMalformed: true);
    final start = str.indexOf('{');
    if (start == -1) throw FormatException('No JSON object found');
    var depth = 0;
    var end = -1;
    for (var i = start; i < str.length; i++) {
      if (str[i] == '{') depth++;
      if (str[i] == '}') {
        depth--;
        if (depth == 0) { end = i; break; }
      }
    }
    if (end == -1) throw FormatException('Unbalanced braces');
    return jsonDecode(str.substring(start, end + 1)) as Map<String, dynamic>;
  }

  static Map<String, dynamic> _decryptLegacyPackage(Map<String, dynamic> package, String password) {
    final salt = package['salt'] as String;
    final ivBase64 = package['iv'] as String;
    final dataBase64 = package['data'] as String;
    final passwordBytes = utf8.encode(password);
    final saltBytes = utf8.encode(salt);
    final hmac = pc.HMac(pc.SHA256Digest(), 64)..init(pc.KeyParameter(Uint8List.fromList(passwordBytes)));
    final digest = hmac.process(Uint8List.fromList(saltBytes));
    final keyBytes = Uint8List(32);
    for (var i = 0; i < keyBytes.length; i++) { keyBytes[i] = digest[i % digest.length]; }

    final iv = base64Decode(ivBase64);
    final cipher = pc.CBCBlockCipher(pc.AESEngine())..init(false, pc.ParametersWithIV(pc.KeyParameter(keyBytes), iv));
    final encryptedBytes = base64Decode(dataBase64);
    final decryptedBytes = cipher.process(encryptedBytes);
    final unpadded = _pkcs7Unpad(decryptedBytes);
    return jsonDecode(utf8.decode(unpadded)) as Map<String, dynamic>;
  }

  static Uint8List _pkcs7Unpad(Uint8List data) {
    final padLen = data.last;
    if (padLen < 1 || padLen > 16) return data;
    var valid = 0;
    for (var i = data.length - padLen; i < data.length; i++) {
      valid |= data[i] ^ padLen;
    }
    if (valid != 0) return data;
    return Uint8List.sublistView(data, 0, data.length - padLen);
  }
}

class _DartSecureRandom implements pc.SecureRandom {
  final Random _random = Random.secure();

  @override
  String get algorithmName => 'DartSecureRandom';

  @override
  void seed(pc.CipherParameters params) {}

  @override
  int nextUint8() => _random.nextInt(256);

  @override
  int nextUint16() {
    final b0 = nextUint8();
    final b1 = nextUint8();
    return (b1 << 8) | b0;
  }

  @override
  int nextUint32() {
    final b0 = nextUint8();
    final b1 = nextUint8();
    final b2 = nextUint8();
    final b3 = nextUint8();
    return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0;
  }

  @override
  BigInt nextBigInteger(int bitLength) {
    final byteLength = (bitLength + 7) >> 3;
    final bytes = Uint8List(byteLength);
    for (var i = 0; i < byteLength; i++) {
      bytes[i] = nextUint8();
    }
    final excessBits = 8 * byteLength - bitLength;
    if (excessBits > 0) {
      bytes[0] &= (1 << (8 - excessBits)) - 1;
    }
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  @override
  Uint8List nextBytes(int count) {
    return Uint8List.fromList(
      List<int>.generate(count, (_) => _random.nextInt(256)),
    );
  }
}
