// ══════════════════════════════════════════════════════════════════════════════
// tombstone_model.dart — CatechHub (Tombstone: traccia di rimozione definitiva)
//
// Modulo "GDPR & Privacy" — Diritto all'Oblio:
// Un Tombstone è il segnale persistente che un'entità (es. un [Student]) è
// stata ELIMINATA DEFINITIVAMENTE tramite il Right to Oblity. Viene conservato
// nel box `tombstone_box` e propagato via P2P agli altri dispositivi della
// parrocchia affinché il dato non venga "resuscitato" da un sync successivo.
//
// FIRMA:
//   Il tombstone trasporta una firma HMAC-SHA256 calcolata sul contenuto
//   canonico usato il shared secret statico ECDH (static-static) del canale
//   P2P. Il ricevente ricalcola la firma con lo STESSO segreto (simmetrico)
//   e accetta il tombstone solo se la firma coincide.
// ══════════════════════════════════════════════════════════════════════════════

class Tombstone {
  /// ID univoco del tombstone (formato: "ts_<microunix>_<suffisso>").
  final String id;

  /// Tipo di entità eliminata (es. AuditLog.entityRagazzo).
  final String entityType;

  /// ID persistente dell'entità eliminata (es. lo studentId).
  final String entityId;

  /// Data/ora dell'eliminazione (UTC ISO 8601).
  final DateTime deletedAt;

  /// Nome dell'operatore (Responsabile) che ha eseguito l'eliminazione.
  final String executedBy;

  /// ID del catechista operatore (per l'AuditLog).
  final String executedByCatechistId;

  /// Firma HMAC-SHA256 sul payload canonico ([TombstoneService.canonical]).
  final String signature;

  /// DeviceId dell'autore, per debugg e deduplicazione.
  final String signerDeviceId;

  const Tombstone({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.deletedAt,
    required this.executedBy,
    required this.executedByCatechistId,
    required this.signature,
    required this.signerDeviceId,
  });

  factory Tombstone.fromMap(String id, Map<String, dynamic> data) {
    return Tombstone(
      id: id,
      entityType: data['entityType'] ?? '',
      entityId: data['entityId'] ?? '',
      deletedAt: DateTime.tryParse(data['deletedAt']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      executedBy: data['executedBy'] ?? '',
      executedByCatechistId: data['executedByCatechistId'] ?? '',
      signature: data['signature'] ?? '',
      signerDeviceId: data['signerDeviceId'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'entityType': entityType,
        'entityId': entityId,
        'deletedAt': deletedAt.toUtc().toIso8601String(),
        'executedBy': executedBy,
        'executedByCatechistId': executedByCatechistId,
        'signature': signature,
        'signerDeviceId': signerDeviceId,
      };
}