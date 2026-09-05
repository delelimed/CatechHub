// ══════════════════════════════════════════════════════════════════════════════
// audit_log_service.dart — CatechHub (firma e verifica HMAC del Registro Trattamenti)
//
// Modulo "Responsabile Catechistico": genera la signature crittografica HMAC
// di ogni voce dell'AuditLog e ne verifica l'integrità. La chiave è derivata
// dalle credenziali dell'operatore (Responsabile) per legare la firma
// all'identità di chi compie l'azione e per impedire manomissioni posteriori.
//
// SCHEMA FIRMA:
//   signature = HMAC-SHA256( secretKey, canonicalPayload ) in base64
//   dove key  = HMAC-SHA256( secret, operatorKey )
//   e   operatorKey = catechistId corrente dell'operatore
//   e   payload     = "logId|actionType|timestamp|executorId|entityType|entityId"
//
// REGOLE:
//   - [sign] conserva l'immutabilità del record: non modifica l'istanza ma
//     restituisce una copia con la [AuditLog.signature] valorizzata.
//   - [verify] ritorna true se la signature è valida rispetto ai campi
//     dell'istanza (anti-manomissione).
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../shared/models/audit_log.dart';
import '../storage/local_database.dart';
import 'crypto_utils.dart';

/// Servizio di firma e verifica HMAC per il Registro Trattamenti.
class AuditLogService {
  /// Chiave FlutterSecureStorage usata come segreto personale del
  /// Responsabile Catechistico. Generata una sola volta per dispositivo.
  static const _hmacSecretKey = 'audit_log_hmac_secret';

  /// Costante di contesto per disambiguare la derivazione della chiave.
  static const String _context = 'CatechHub-GdprAuditLog-v1';

  /// Istanza di storage sicuro.
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// OVERRIDE SOLO PER TEST: if [debugSecretOverride] != null, il segreto
  /// base viene usato come tale evitando il plugin nativo InsecureStorage.
  /// Ignorato nelle build release (solo kDebugMode).
  /// @visibleForTesting
  static String? debugSecretOverride;

  /// Ottiene (generando se necessario) il segreto HMAC del Responsabile.
  ///
  /// Il segreto di base è unico per dispositivo, protetto da
  /// FlutterSecureStorage (Android Keystore).
  static Future<String> _getBaseSecret() async {
    if (kDebugMode) {
      final override = debugSecretOverride;
      if (override != null) return override;
    }

    final existing = await _secureStorage.read(key: _hmacSecretKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final entropy = List.generate(32, (_) => random.nextInt(256));
    final baseSecret = base64Encode(entropy);
    await _secureStorage.write(key: _hmacSecretKey, value: baseSecret);
    return baseSecret;
  }

  /// Chiave testuale dell'operatore corrente (catechistId locale o fallback).
  static String _operatorKey() {
    try {
      final box = LocalDatabase.auth();
      final catechistId = box.get('catechist_id') as String?;
      if (catechistId != null && catechistId.isNotEmpty) return catechistId;
    } catch (_) {
      // box auth non ancora disponibile: usa fallback.
    }
    return 'local_catechist_id';
  }

  /// Deriva la chiave HMAC-specifica dell'operatore corrente dal segreto.
  static Future<List<int>> _deriveKey() async {
    final base = await _getBaseSecret();
    return hmacSha256Bytes(
      utf8.encode('$_context:$base'),
      utf8.encode(_operatorKey()),
    );
  }

  /// Costruisce il payload canonico da firmare per [log].
  static String buildPayload(AuditLog log) {
    return '${log.logId}|${log.actionType.storageValue}|'
        '${log.timestamp.toUtc().toIso8601String()}|'
        '${log.executedByCatechistId}|${log.affectedEntityType}|'
        '${log.affectedEntityId}';
  }

  /// Firmerà [log] e restituisce una copia immutabile con la signature valorizzata.
  static Future<AuditLog> sign(AuditLog log) async {
    final key = await _deriveKey();
    final mac = await hmacSha256Bytes(key, utf8.encode(buildPayload(log)));
    return log.copyWith(signature: base64Encode(mac));
  }

  /// Verifica l'integrità di [log] confrontando la signature con i campi.
  /// Ritorna false se la firma è assente o non corrisponde.
  static Future<bool> verify(AuditLog log) async {
    if (log.signature.isEmpty) return false;
    final key = await _deriveKey();
    final mac = await hmacSha256Bytes(key, utf8.encode(buildPayload(log)));
    final expected = base64Encode(mac);
    return _constantTimeEquals(expected, log.signature);
  }

  /// Confronta due stringhe in tempo costante per evitare timing-attack.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
