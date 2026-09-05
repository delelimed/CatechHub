// ══════════════════════════════════════════════════════════════════════════════
// audit_log.dart — CatechHub (Registro Trattamenti GDPR / AuditLog)
//
// Modulo "Responsabile Catechistico": entità IMMUTABILE del Registro
// Trattamenti (GDPR Art. 30). Ogni voce registra un'azione effettuata da un
// operatore sull'app, ed è firmata con una signature HMAC generata con le
// credenziali del Responsabile Catechistico. La firma rende la voce
// resistente a manomissioni posteriori: qualunque modifica al contenuto
// invalida la signature.
//
// STORAGE:
//   Salvata nel box Hive `audit_log_box` con chiave = log_id (UUIDv4).
//   L'entità è immutabile: non esiste un metodo di update; la cancellazione
//   è riservata al Diritto all'Oblio / reset totale.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:math';

import 'audit_action.dart';

/// Genera un UUID v4 con generatore crittograficamente sicuro.
String generateAuditLogUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40; // versione 4
  bytes[8] = (bytes[8] & 0x3F) | 0x80; // variante 10xx
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Entità immutabile del Registro Trattamenti (GDPR).
class AuditLog {
  /// Identificativo del log (UUIDv4).
  final String logId;

  /// Timestamp dell'azione (ISO 8601 UTC).
  final DateTime timestamp;

  /// Tipologia di azione registrata.
  final AuditActionType actionType;

  /// ID univoco dell'operatore (catechistId / localUserId del Responsabile).
  final String executedByCatechistId;

  /// Nome leggibile dell'operatore (snapshot al momento dell'azione).
  final String executedByCatechistName;

  /// Tipologia dell'entità impattata (es. "RAGAZZO", "CLASSE", "CATECHISTA").
  final String affectedEntityType;

  /// ID dell'entità impattata.
  final String affectedEntityId;

  /// Firma HMAC del record, generata con le credenziali del Responsabile.
  /// Previene manomissioni posteriori della voce.
  final String signature;

  const AuditLog({
    required this.logId,
    required this.timestamp,
    required this.actionType,
    required this.executedByCatechistId,
    required this.executedByCatechistName,
    required this.affectedEntityType,
    required this.affectedEntityId,
    this.signature = '',
  });

  /// Costante per i tipi di entità comuni.
  static const entityRagazzo = 'RAGAZZO';
  static const entityClasse = 'CLASSE';
  static const entityCatechista = 'CATECHISTA';
  static const entityConsenso = 'CONSENSO';

  AuditLog copyWith({
    String? logId,
    DateTime? timestamp,
    AuditActionType? actionType,
    String? executedByCatechistId,
    String? executedByCatechistName,
    String? affectedEntityType,
    String? affectedEntityId,
    String? signature,
  }) {
    return AuditLog(
      logId: logId ?? this.logId,
      timestamp: timestamp ?? this.timestamp,
      actionType: actionType ?? this.actionType,
      executedByCatechistId:
          executedByCatechistId ?? this.executedByCatechistId,
      executedByCatechistName:
          executedByCatechistName ?? this.executedByCatechistName,
      affectedEntityType: affectedEntityType ?? this.affectedEntityType,
      affectedEntityId: affectedEntityId ?? this.affectedEntityId,
      signature: signature ?? this.signature,
    );
  }

  factory AuditLog.fromMap(String id, Map<String, dynamic> data) {
    return AuditLog(
      logId: id,
      timestamp:
          DateTime.tryParse(data['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      actionType: AuditActionType.fromStorageValue(
        data['actionType']?.toString(),
      ),
      executedByCatechistId: data['executedByCatechistId'] ?? '',
      executedByCatechistName: data['executedByCatechistName'] ?? '',
      affectedEntityType: data['affectedEntityType'] ?? '',
      affectedEntityId: data['affectedEntityId'] ?? '',
      signature: data['signature'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toUtc().toIso8601String(),
      'actionType': actionType.storageValue,
      'executedByCatechistId': executedByCatechistId,
      'executedByCatechistName': executedByCatechistName,
      'affectedEntityType': affectedEntityType,
      'affectedEntityId': affectedEntityId,
      'signature': signature,
    };
  }
}
