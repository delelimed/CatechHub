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

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart' as pc;

import '../storage/local_database.dart';

class FieldEncryptionService {
  FieldEncryptionService._();

  static const _prefix = 'cieI1:';
  static const _authKey = 'field_encryption_key';

  /// OVERRIDE SOLO PER TEST (ignorato nelle build release): se impostato viene
  /// usata una chiave derivata da questa stringa, evitando lettura/scrittura
  /// del box auth.
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

  /// Chiave di campo del dispositivo: un segreto casuale conservato nel box
  /// auth (già cifrato AES da Hive). Fallimento = fail-closed: non esiste
  /// alcuna chiave di fallback deterministica derivata da una costante
  /// pubblica, che renderebbe il ciphertext decifrabile da chiunque.
  static Uint8List deviceKey() {
    if (kDebugMode && debugSecretOverride != null) {
      return _sha256(utf8.encode(debugSecretOverride!));
    }
    if (_cachedKey != null) return _cachedKey!;
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

  // ─────────────────────────────────────────────────────────────────────────
  // CIFRATURA DI CAMPO PER LA MAPPA STUDENTE (TRASPORTO P2P / EXPORT / IMPORT)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // PROBLEMA CROSS-DEVICE:
  //   La chiave di campo è PER-DISPOSITIVO (segreto locale in authBox). Se
  //   un valore cifrato venisse trasferito così com'è a un altro dispositivo,
  //   quest'ultimo non potrebbe decifrarlo (chiave diversa) e mostrerebbe
  //   il ciphertext. Per questo:
  //     - SU EGRESSO (sync P2P in uscita, export backup): i campi sensibili
  //       vengono DECIFRATI prima di lasciare il dispositivo (il trasporto è
  //       già protetto: AES-GCM con shared secret per P2P, PIN backup per
  //       l'export).
  //     - SU INGRESSO (sync P2P in entrata, import): i campi in chiaro
  //       ricevuti vengono CIFRATI con la chiave locale prima della persistenza.
  //
  // Campi sensibili trattati (free-text, non usati per ricerca/filtri):
  //   - noteAllergieSalute, allergies, autonomousExits, notes.

  /// Campi free-text sensibili di [Student] soggetti a cifratura di campo.
  ///
  /// Questi campi vengono cifrati prima della persistenza su Hive tramite
  /// [FieldEncryptionService.encrypt()] e decifrati al lettura tramite
  /// [decryptStudentMapForTransport()]. I dati in ingresso (import, P2P)
  /// vengono automaticamente cifrati prima della persistenza.
  /// Campi aggiunti per conformità GDPR minorile (dati di contatto sensibili):
  static const studentSensitiveFields = <String>{
    'noteAllergieSalute',
    'allergies',
    'autonomousExits',
    'notes',
    'birthDate',
    'studentPhone',
    'motherPhone',
    'fatherPhone',
    'parentEmail',
  };

  /// Restituisce una copia di [map] con i campi sensibili DECIFRATI
  /// (da usare in uscita: export/backup e payload P2P).
  static Map<String, dynamic> decryptStudentMapForTransport(
    Map<String, dynamic> map,
  ) {
    if (map.isEmpty) return map;
    final copy = Map<String, dynamic>.from(map);
    for (final field in studentSensitiveFields) {
      final value = copy[field];
      if (value is String) {
        copy[field] = decrypt(value);
      }
    }
    return copy;
  }

  /// Restituisce una copia di [map] con i campi sensibili CIFRATI con la
  /// chiave locale (da usare in ingresso: import/backup e ricezione P2P).
  /// I campi già cifrati (prefisso `cieI1:`) restano invariati (idempotente).
  static Map<String, dynamic> encryptStudentMapForStorage(
    Map<String, dynamic> map,
  ) {
    if (map.isEmpty) return map;
    final copy = Map<String, dynamic>.from(map);
    for (final field in studentSensitiveFields) {
      final value = copy[field];
      if (value is String) {
        copy[field] = encrypt(value);
      }
    }
    return copy;
  }
}