import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

class EncryptionService {
  static const int currentVersion = 2;
  static const int defaultIterations = 210000;
  // Iterazioni per la condivisione QR "fast share". DISTINTO da
  // defaultIterations: la scelta dell'AAD (QR vs backup) è basata sul
  // confronto `iterations == fastShareIterations`, quindi i due valori devono
  // rimanere diversi per non rompere la decifratura dei backup esistenti.
  // Il valore è stato alzato da 12000 a 60000 per rendere molto più costoso
  // il brute-force offline del PIN QR (insieme alla lunghezza minima di 10
  // cifre del PIN, la ricerca esaustiva diventa impraticabile).
  static const int fastShareIterations = 60000;
  static const int saltLength = 16;
  static const int nonceLength = 12;
  static const int tagLengthBits = 128;

  /// AAD (Additional Authenticated Data) context strings per operazione.
  /// Prevengono attacchi di ciphertext substitution legando il ciphertext
  /// al contesto d'uso specifico.
  static final Uint8List _aadPasswordData =
      Uint8List.fromList(utf8.encode('CatechHub_Context_PasswordData_v1'));
  static final Uint8List _aadQrShare =
      Uint8List.fromList(utf8.encode('CatechHub_Context_QRShare_v1'));

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
    final secretBytes = _encodeBigIntAsUnsigned(sharedSecret);
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

    final isFastShare = iterations == fastShareIterations;
    final aad = isFastShare ? _aadQrShare : _aadPasswordData;

    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(true, pc.AEADParameters(pc.KeyParameter(key), tagLengthBits, nonce, aad));

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
        // Il formato legacy (v1: AES-CBC senza MAC + KDF a singola iterazione)
        // è stato RIMOSSO: accettarlo sarebbe una porta di downgrade che
        // indebolisce la derivazione della chiave e perde l'integrità
        // autenticata del ciphertext (padding oracle). I backup v1 non sono
        // più supportati per scelta di sicurezza.
        throw Exception(
          'Versione backup non supportata (v${package['v']}). '
          'Il formato v1 non è più accettato per motivi di sicurezza.',
        );
      }

      final iterations = package['iter'] as int;
      final salt = base64Decode(package['salt'] as String);
      final nonce = base64Decode(package['nonce'] as String);
      final dataBase64 = package['data'] as String;

      final key = derivePasswordKeyBytes(password, Uint8List.fromList(salt), iterations: iterations);

      final isFastShare = iterations == fastShareIterations;
      final aad = isFastShare ? _aadQrShare : _aadPasswordData;

      final cipher = pc.GCMBlockCipher(pc.AESEngine())
        ..init(false, pc.AEADParameters(pc.KeyParameter(key), tagLengthBits, Uint8List.fromList(nonce), aad));

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
}

class _DartSecureRandom implements pc.SecureRandom {
  final Random _random = Random.secure();
  final _entropyPool = <int>[];

  @override
  String get algorithmName => 'DartSecureRandom';

  @override
  void seed(pc.CipherParameters params) {
    if (params is pc.KeyParameter) {
      _entropyPool.addAll(params.key);
    } else if (params is pc.ParametersWithIV) {
      _entropyPool.addAll(params.iv);
    } else if (params is pc.ECKeyGeneratorParameters) {
      final domainSeed = params.domainParameters.toString();
      _entropyPool.addAll(utf8.encode(domainSeed));
    }
    if (_entropyPool.length > 256) {
      _entropyPool.removeRange(0, _entropyPool.length - 256);
    }
  }

  @override
  int nextUint8() {
    if (_entropyPool.isNotEmpty) {
      final mix = _entropyPool.removeAt(0) ^ _random.nextInt(256);
      return mix;
    }
    return _random.nextInt(256);
  }

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

Uint8List _encodeBigIntAsUnsigned(BigInt number) {
  if (number == BigInt.zero) {
    return Uint8List.fromList([0]);
  }
  var size = (number.bitLength + (number.isNegative ? 8 : 7)) >> 3;
  var result = Uint8List(size);
  var n = number;
  for (var i = 0; i < size; i++) {
    result[size - i - 1] = (n & BigInt.from(0xFF)).toInt();
    n = n >> 8;
  }
  return result;
}
