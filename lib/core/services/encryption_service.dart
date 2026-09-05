import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

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
  // A1: iterazioni usate per i NUOVI pacchetti QR share. Allineate al backup
  // (350000): rendono impraticabile il brute-force offline del PIN (10^12
  // combinazioni). La decifratura accetta anche i pacchetti legacy a 60000
  // iterazioni (stesso AAD QR) per non rompere i dati già condivisi.
  static const int secureShareIterations = 350000;
  static const int saltLength = 16;
  static const int nonceLength = 12;
  static const int tagLengthBytes = 16;

  /// AAD (Additional Authenticated Data) context strings per operazione.
  /// Prevengono attacchi di ciphertext substitution legando il ciphertext
  /// al contesto d'uso specifico.
  static final Uint8List _aadPasswordData = Uint8List.fromList(
    utf8.encode('CatechHub_Context_PasswordData_v1'),
  );
  static final Uint8List _aadQrShare = Uint8List.fromList(
    utf8.encode('CatechHub_Context_QRShare_v1'),
  );

  static Uint8List secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  /// True se il pacchetto usa il contesto QR share (AAD dedicato).
  /// Accetta sia le iterazioni legacy (60000) sia quelle correnti (350000)
  /// per la decifratura retrocompatibile dei pacchetti già condivisi.
  static bool _isQrShareContext(int iterations) =>
      iterations == fastShareIterations ||
      iterations == secureShareIterations;

  // ──────────────────────────────────────────────
  //  PBKDF2 — DERIVAZIONE CHIAVE DA PASSWORD
  // ──────────────────────────────────────────────

  /// Deriva chiave AES-256 da password con PBKDF2-HMAC-SHA256.
  /// Algoritmo standard (RFC 2898): il risultato è byte-identico a quello
  /// prodotto dal vecchio punto di derivazione basato su pointycastle, quindi
  /// i dati già cifrati restano decifrabili.
  static Future<Uint8List> derivePasswordKeyBytes(
    String password,
    Uint8List salt, {
    int iterations = defaultIterations,
    int keyLength = 32,
  }) async {
    final pbkdf2 = Pbkdf2.hmacSha256(
      iterations: iterations,
      bits: keyLength * 8,
    );
    final key = await pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final bytes = await key.extractBytes();
    return Uint8List.fromList(bytes);
  }

  static String generateSalt() {
    return base64Encode(secureRandomBytes(saltLength));
  }

  // ──────────────────────────────────────────────
  //  AES-256-GCM — CIFRATURA/DECIFRATURA
  // ──────────────────────────────────────────────

  static Future<String> encryptData(
    Map<String, dynamic> data,
    String password, {
    int iterations = defaultIterations,
  }) async {
    final salt = secureRandomBytes(saltLength);
    final nonce = secureRandomBytes(nonceLength);
    final key = await derivePasswordKeyBytes(
      password,
      salt,
      iterations: iterations,
    );
    final jsonData = jsonEncode(data);

    final isFastShare = _isQrShareContext(iterations);
    final aad = isFastShare ? _aadQrShare : _aadPasswordData;

    // AES-256-GCM standard: ciphertext || tag (16 byte), identico al formato
    // prodotto in precedenza con pointycastle.
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonData),
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    final encrypted = box.concatenation(nonce: false);

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

  static Future<Map<String, dynamic>> decryptData(
    String encryptedData,
    String password,
  ) async {
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

      final key = await derivePasswordKeyBytes(
        password,
        Uint8List.fromList(salt),
        iterations: iterations,
      );

      final isFastShare = _isQrShareContext(iterations);
      final aad = isFastShare ? _aadQrShare : _aadPasswordData;

      // Ricostruisce nonce || ciphertext || tag e decifra con AES-256-GCM.
      final sealed = base64Decode(dataBase64);
      final concatenated = Uint8List(nonce.length + sealed.length)
        ..setAll(0, nonce)
        ..setAll(nonce.length, sealed);
      final box = SecretBox.fromConcatenation(
        concatenated,
        nonceLength: nonceLength,
        macLength: tagLengthBytes,
      );
      final decryptedBytes = Uint8List.fromList(
        await AesGcm.with256bits().decrypt(
          box,
          secretKey: SecretKey(key),
          aad: aad,
        ),
      );

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

  static Future<bool> verifyPassword(
    String encryptedData,
    String password,
  ) async {
    try {
      await decryptData(encryptedData, password);
      return true;
    } catch (e) {
      return false;
    }
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
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    if (end == -1) throw FormatException('Unbalanced braces');
    return jsonDecode(str.substring(start, end + 1)) as Map<String, dynamic>;
  }
}
