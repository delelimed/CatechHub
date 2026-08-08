// ══════════════════════════════════════════════════════════════════════════════
// tombstone_service.dart — CatechHub (firma e verifica dei tombstone)
//
// Modulo "GDPR & Privacy" — Diritto all'Oblio:
// Firma HMAC-SHA256 dei tombstone per impedire l'accettazione di tombstone
// contraffatti. La chiave impiegata è il shared secret statico ECDH (static-
// static) del canale P2P: è SIMMETRICO tra i due dispositivi, quindi il
// mittente firma e il destinatario verifica con lo stesso valore.
//
// SCHEMA:
//   signature = base64( HMAC-SHA256( sharedSecret, canonical ) )
//   canonical = "entityType|entityId|deletedAt|executedBy|executedByCatechistId"
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:crypto/crypto.dart' show Hmac, sha256;

/// Servizio di firma/verifica dei tombstone P2P.
class TombstoneService {
  TombstoneService._();

  /// Payload canonico firmabile estratto da una mappa tombstone serializzata
  /// come quella prodotta da [Tombstone.toMap].
  static String canonical(Map<String, dynamic> ts) {
    return '${ts['entityType']}|${ts['entityId']}|${ts['deletedAt']}|'
        '${ts['executedBy']}|${ts['executedByCatechistId']}';
  }

  /// Firma HMAC-SHA256 base64 del payload canonico con [secretKey].
  static String sign(String canonicalPayload, String secretKey) {
    final mac = Hmac(sha256, utf8.encode(secretKey));
    return base64Encode(mac.convert(utf8.encode(canonicalPayload)).bytes);
  }

  /// Ritorna una copia di [ts] con 'signature' ricalcolata con [secretKey].
  static Map<String, dynamic> withSignature(
    Map<String, dynamic> ts,
    String secretKey,
  ) {
    return {...ts, 'signature': sign(canonical(ts), secretKey)};
  }

  /// Verifica la firma di [ts] contro [secretKey] (confronto tempo-costante).
  static bool verify(Map<String, dynamic> ts, String secretKey) {
    final expected = ts['signature'] as String?;
    if (expected == null || expected.isEmpty) return false;
    final actual = sign(canonical(ts), secretKey);
    return _constantTimeEquals(expected, actual);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}