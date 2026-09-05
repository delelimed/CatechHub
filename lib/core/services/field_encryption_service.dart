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

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

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

  static Future<Uint8List> _sha256(List<int> input) async {
    final hash = await Sha256().hash(input);
    return Uint8List.fromList(hash.bytes);
  }

  /// Chiave di campo del dispositivo: un segreto casuale conservato nel box
  /// auth (già cifrato AES da Hive). Fallimento = fail-closed: non esiste
  /// alcuna chiave di fallback deterministica derivata da una costante
  /// pubblica, che renderebbe il ciphertext decifrabile da chiunque.
  static Future<Uint8List> deviceKey() async {
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
    _cachedKey = await _sha256(seed);
    return _cachedKey!;
  }

  static Future<String> _cipherBytes(Uint8List key, String plain) async {
    final nonce = _secureBytes(12);
    // AES-256-GCM standard: nonce || ciphertext || tag, byte-identico al
    // vecchio formato pointycastle (GCMBlockCipher con mac da 128 bit).
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(plain),
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    return base64Encode(box.concatenation());
  }

  /// Cifra [plain]. Ritorna null per input nulli/vuoti. Idempotente: un
  /// valore già cifrato (prefisso `cieI1:`) viene restituito invariato.
  static Future<String?> encrypt(String? plain) async {
    if (plain == null || plain.trim().isEmpty) return null;
    if (plain.startsWith(_prefix)) return plain;
    return '$_prefix${await _cipherBytes(await deviceKey(), plain)}';
  }

  /// Decifra un valore cifrato. Ritorna il valore così com'è se il valore
  /// non è cifrato o se la decifratura fallisce.
  static Future<String?> decrypt(String? stored) async {
    if (stored == null) return null;
    if (!stored.startsWith(_prefix)) return stored;
    try {
      final sealed = stored.substring(_prefix.length);
      final bytes = base64Decode(sealed);
      if (bytes.length < 12 + 16) return stored;
      final box = SecretBox.fromConcatenation(
        bytes,
        nonceLength: 12,
        macLength: 16,
      );
      final plain = await AesGcm.with256bits().decrypt(
        box,
        secretKey: SecretKey(await deviceKey()),
      );
      return utf8.decode(plain);
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
  static Future<Map<String, dynamic>> decryptStudentMapForTransport(
    Map<String, dynamic> map,
  ) async {
    if (map.isEmpty) return map;
    final copy = Map<String, dynamic>.from(map);
    for (final field in studentSensitiveFields) {
      final value = copy[field];
      if (value is String) {
        copy[field] = await decrypt(value);
      }
    }
    return copy;
  }

  /// Restituisce una copia di [map] con i campi sensibili CIFRATI con la
  /// chiave locale (da usare in ingresso: import/backup e ricezione P2P).
  /// I campi già cifrati (prefisso `cieI1:`) restano invariati (idempotente).
  static Future<Map<String, dynamic>> encryptStudentMapForStorage(
    Map<String, dynamic> map,
  ) async {
    if (map.isEmpty) return map;
    final copy = Map<String, dynamic>.from(map);
    for (final field in studentSensitiveFields) {
      final value = copy[field];
      if (value is String) {
        copy[field] = await encrypt(value);
      }
    }
    return copy;
  }
}
