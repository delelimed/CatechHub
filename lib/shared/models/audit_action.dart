// ══════════════════════════════════════════════════════════════════════════════
// audit_action.dart — CatechHub (azioni registrate nell'AuditLog / Registro Trattamenti GDPR)
//
// Modulo "Responsabile Catechistico": enum delle azioni che producono una
// voce immutabile nel Registro Trattamenti (AuditLog). Ogni azione è legata
// a una [signature] HMAC generata con le credenziali del Responsabile per
// prevenire manomissioni posteriori.
// ══════════════════════════════════════════════════════════════════════════════

/// Tipologia di azione registrabile nel Registro Trattamenti GDPR.
enum AuditActionType {
  /// Creazione di un ragazzo (anagrafica).
  createStudent('CREATE_STUDENT'),

  /// Aggiornamento dell'anagrafica di un ragazzo.
  updateStudent('UPDATE_STUDENT'),

  /// Cancellazione definitiva (hard delete) di un ragazzo — Diritto all'Oblio.
  deleteStudentHard('DELETE_STUDENT_HARD'),

  /// Creazione di una classe/gruppo catechistico.
  createClass('CREATE_CLASS'),

  /// Cancellazione/archiviazione di una classe.
  deleteClass('DELETE_CLASS'),

  /// Riassegnazione di un catechista a una/dalle classi.
  reassignCatechist('REASSIGN_CATECHIST'),

  /// Concessione del consenso GDPR al trattamento dei dati di un minore.
  grantConsent('GRANT_CONSENT'),

  /// Revoca del consenso GDPR al trattamento dei dati di un minore.
  revokeConsent('REVOKE_CONSENT'),

  /// Esportazione del registro trattamenti / backup parrocchiale.
  exportData('EXPORT_DATA'),

  /// Ricezione di un TOMBSTONE P2P (dato rimosso da un altro dispositivo).
  tombstoneReceived('TOMBSTONE_RECEIVED'),

  /// Passaggio di anno catechistico (archiviazione/roll-over).
  passaggioAnno('PASSAGGIO_ANNO');

  const AuditActionType(this.storageValue);

  /// Valore persistente (stringa di archivio).
  final String storageValue;

  /// Etichetta localizzata per le UI.
  String get label => switch (this) {
        AuditActionType.createStudent => 'Creazione ragazzo',
        AuditActionType.updateStudent => 'Modifica ragazzo',
        AuditActionType.deleteStudentHard => 'Eliminazione definitiva ragazzo',
        AuditActionType.createClass => 'Creazione classe',
        AuditActionType.deleteClass => 'Eliminazione classe',
        AuditActionType.reassignCatechist => 'Riassegnazione catechista',
        AuditActionType.grantConsent => 'Concessione consenso',
        AuditActionType.revokeConsent => 'Revoca consenso',
        AuditActionType.exportData => 'Esportazione dati',
        AuditActionType.tombstoneReceived => 'Tombstone ricevuto',
        AuditActionType.passaggioAnno => 'Passaggio di anno',
      };

  static AuditActionType fromStorageValue(String? value) {
    return AuditActionType.values.firstWhere(
      (t) => t.storageValue == value,
      orElse: () => AuditActionType.createStudent,
    );
  }
}