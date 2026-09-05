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
//   - HMAC-SHA256 sul contenuto canonico con il shared secret statico ECDH
//     del canale P2P (per-recipiente, verificato da chi lo riceve);
//   - A7: firma Ed25519 PER-DISPOSITIVO ([signatureEd25519]) calcolata con la
//     chiave privata Ed25519 derivata dall'identità del dispositivo. È
//     asimmetrica e attribuibile: il firmatario è identificabile tramite
//     [signerEd25519PublicKey] e non può essere spacciato per un altro device.
// ══════════════════════════════════════════════════════════════════════════════

class Tombstone {
  /// ID univoco del tombstone (formato: `ts_<microunix>_<suffisso>`).
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

  /// A7: firma Ed25519 per-dispositivo (base64) sul payload canonico.
  final String signatureEd25519;

  /// A7: chiave pubblica Ed25519 (base64) del firmatario.
  final String signerEd25519PublicKey;

  const Tombstone({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.deletedAt,
    required this.executedBy,
    required this.executedByCatechistId,
    required this.signature,
    required this.signerDeviceId,
    this.signatureEd25519 = '',
    this.signerEd25519PublicKey = '',
  });

  factory Tombstone.fromMap(String id, Map<String, dynamic> data) {
    return Tombstone(
      id: id,
      entityType: data['entityType'] ?? '',
      entityId: data['entityId'] ?? '',
      deletedAt:
          DateTime.tryParse(data['deletedAt']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      executedBy: data['executedBy'] ?? '',
      executedByCatechistId: data['executedByCatechistId'] ?? '',
      signature: data['signature'] ?? '',
      signerDeviceId: data['signerDeviceId'] ?? '',
      signatureEd25519: data['signatureEd25519'] ?? '',
      signerEd25519PublicKey: data['signerEd25519PublicKey'] ?? '',
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
    'signatureEd25519': signatureEd25519,
    'signerEd25519PublicKey': signerEd25519PublicKey,
  };
}
