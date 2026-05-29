import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as legacy_encrypt;
import 'package:pointycastle/export.dart' as pc;

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

  static Uint8List derivePasswordKeyBytes(
    String password,
    Uint8List salt, {
    int iterations = defaultIterations,
    int keyLength = 32,
  }) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(salt, iterations, keyLength));

    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  static String generateSalt() {
    return base64Encode(secureRandomBytes(saltLength));
  }

  static String encryptData(
    Map<String, dynamic> data,
    String password, {
    int iterations = defaultIterations,
  }) {
    final salt = secureRandomBytes(saltLength);
    final nonce = secureRandomBytes(nonceLength);
    final key = derivePasswordKeyBytes(password, salt, iterations: iterations);
    final jsonData = jsonEncode(data);

    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        true,
        pc.AEADParameters(
          pc.KeyParameter(key),
          tagLengthBits,
          nonce,
          Uint8List(0),
        ),
      );

    final encrypted = cipher.process(Uint8List.fromList(utf8.encode(jsonData)));
    final package = {
      'v': currentVersion,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iter': iterations,
      'alg': 'AES-256-GCM',
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'data': base64Encode(encrypted),
    };

    return base64Encode(utf8.encode(jsonEncode(package)));
  }

  static Map<String, dynamic> decryptData(
    String encryptedData,
    String password,
  ) {
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

      final key = derivePasswordKeyBytes(
        password,
        Uint8List.fromList(salt),
        iterations: iterations,
      );

      final cipher = pc.GCMBlockCipher(pc.AESEngine())
        ..init(
          false,
          pc.AEADParameters(
            pc.KeyParameter(key),
            tagLengthBits,
            Uint8List.fromList(nonce),
            Uint8List(0),
          ),
        );

      final decryptedBytes = cipher.process(base64Decode(dataBase64));
      final decrypted = utf8.decode(decryptedBytes);
      return jsonDecode(decrypted) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Password non valida o dati corrotti: $e');
    }
  }

  static bool verifyPassword(String encryptedData, String password) {
    try {
      decryptData(encryptedData, password);
      return true;
    } catch (e) {
      return false;
    }
  }

  static Map<String, dynamic> _decryptLegacyPackage(
    Map<String, dynamic> package,
    String password,
  ) {
    final salt = package['salt'] as String;
    final ivBase64 = package['iv'] as String;
    final dataBase64 = package['data'] as String;
    final passwordBytes = utf8.encode(password);
    final saltBytes = utf8.encode(salt);
    final hmac = pc.HMac(pc.SHA256Digest(), 64)
      ..init(pc.KeyParameter(Uint8List.fromList(passwordBytes)));
    final digest = hmac.process(Uint8List.fromList(saltBytes));
    final keyBytes = Uint8List(32);
    for (var i = 0; i < keyBytes.length; i++) {
      keyBytes[i] = digest[i % digest.length];
    }

    final key = legacy_encrypt.Key(keyBytes);
    final iv = legacy_encrypt.IV.fromBase64(ivBase64);
    final encrypter = legacy_encrypt.Encrypter(
      legacy_encrypt.AES(key, mode: legacy_encrypt.AESMode.cbc),
    );
    final decrypted = encrypter.decrypt64(dataBase64, iv: iv);
    return jsonDecode(decrypted) as Map<String, dynamic>;
  }
}
