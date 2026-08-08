// ══════════════════════════════════════════════════════════════════════════════
// field_encryption_service.dart — CatechHub (cifratura di campo dati sensibili)
//
// Modulo "GDPR & Privacy": cifra singoli valori sensibili (es.
// [Student.noteAllergieSalute]) PRIMA della persistenza su Hive, così che il
// valore memorizzato a livello di campo sia ciphertext anche ad ispezione
// diretta del box. La chiave è un segreto per-dispositivo conservato nel box
// `registroBox` (già protetto da AES-256 a livello di file).
//
// FORMATO:  "cieI1:" + base64(nonce(12) | ciphertext)
//   Le stringhe che non iniziano col prefisso vengono considerate già in
//   chiaro (retrocompatibilità / import P2P) e restituite senza decifratura.
//   Una decifratura fallita restituisce il valore originale (graceful drain).
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import '../storage/local_database.dart';

class FieldEncryptionService {
  FieldEncryptionService._();

  static const _prefix = 'cieI1:';
  static const _authKey = 'field_encryption_key';
  static const _context = 'CatechHub.FieldEncryption.v1';

  /// OVERRIDE SOLO PER TEST: se impostato viene usata una chiave derivata da
  /// questa stringa, evitando lettura/scrittura del box auth.
  static String? debugSecretOverride;

  static Uint8List? _cachedKey;

  static Uint8List _secureBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Uint8List _sha256(List<int> input) {
    final digest = pc.Digest('SHA-256');
    return digest.process(Uint8List.fromList(input));
  }

  /// Chiave di campo del dispositivo. Prima scelta: un segreto casuale
  /// conservato nel box auth (già cifrato AES da Hive); fallback: derivazione
  /// deterministica (utile quando il box auth non è ancora pronto).
  static Uint8List deviceKey() {
    if (debugSecretOverride != null) {
      return _sha256(utf8.encode(debugSecretOverride!));
    }
    if (_cachedKey != null) return _cachedKey!;
    try {
      final box = LocalDatabase.auth();
      var raw = box.get(_authKey) as String?;
      if (raw == null || raw.isEmpty) {
        raw = base64Encode(_secureBytes(32));
        box.put(_authKey, raw);
        box.flush();
      }
      final seed = base64Decode(raw);
      _cachedKey = _sha256(seed);
      return _cachedKey!;
    } catch (_) {
      return _sha256(utf8.encode(_context));
    }
  }

  static String _cipherBytes(Uint8List key, String plain) {
    final nonce = _secureBytes(12);
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        true,
        pc.AEADParameters(
          pc.KeyParameter(key),
          128,
          nonce,
          Uint8List(0),
        ),
      );
    final input = Uint8List.fromList(utf8.encode(plain));
    final out = Uint8List(cipher.getOutputSize(input.length));
    var len = cipher.processBytes(input, 0, input.length, out, 0);
    len += cipher.doFinal(out, len);
    final payload = Uint8List(nonce.length + len)
      ..setAll(0, nonce)
      ..setAll(nonce.length, Uint8List.sublistView(out, 0, len));
    return base64Encode(payload);
  }

  /// Cifra [plain]. Ritorna null per input nulli/vuoti. Idempotente: un
  /// valore già cifrato (prefisso `cieI1:`) viene restituito invariato.
  static String? encrypt(String? plain) {
    if (plain == null || plain.trim().isEmpty) return null;
    if (plain.startsWith(_prefix)) return plain;
    return '$_prefix${_cipherBytes(deviceKey(), plain)}';
  }

  /// Decifra un valore cifrato. Ritorna il valore così com'è se il valore
  /// non è cifrato o se la decifratura fallisce.
  static String? decrypt(String? stored) {
    if (stored == null) return null;
    if (!stored.startsWith(_prefix)) return stored;
    try {
      final sealed = stored.substring(_prefix.length);
      final bytes = base64Decode(sealed);
      if (bytes.length < 12) return stored;
      final nonce = Uint8List.sublistView(bytes, 0, 12);
      final data = Uint8List.sublistView(bytes, 12);
      final cipher = pc.GCMBlockCipher(pc.AESEngine())
        ..init(
          false,
          pc.AEADParameters(
            pc.KeyParameter(deviceKey()),
            128,
            nonce,
            Uint8List(0),
          ),
        );
      final out = Uint8List(cipher.getOutputSize(data.length));
      var len = cipher.processBytes(data, 0, data.length, out, 0);
      len += cipher.doFinal(out, len);
      return utf8.decode(Uint8List.sublistView(out, 0, len));
    } catch (_) {
      return stored;
    }
  }
}