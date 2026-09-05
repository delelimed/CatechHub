// ══════════════════════════════════════════════════════════════════════════════
// user_role.dart — CatechHub (ruoli utente e matrice dei permessi)
//
// Modulo "Responsabile Catechistico": definisce i ruoli dell'utente locale
// (CATECHISTA / RESPONSABILE) e la matrice dei permessi associata.
//
// REGOLE:
//   - Solo Role.RESPONSABILE può scrivere/modificare/cancellare le entità
//     "globali" della parrocchia (Classi, Luoghi/Aule, Assegnazioni,
//     Log GDPR / AuditLog) e gestire il Diritto all'Oblio.
//   - Role.CATECHISTA mantiene i permessi operativi per la propria classe
//     (anagrafica ragazzi, presenze, documenti) ma NON accede alle entità
//     globali.
//
// PERSISTENZA:
//   Il ruolo corrente è salvato nel box auth con chiave "user_role".
// ══════════════════════════════════════════════════════════════════════════════

import '../../core/storage/local_database.dart';

/// Ruolo dell'utente locale all'interno della parrocchia.
enum UserRole {
  /// Catechista: gestisce la propria classe (presenze, anagrafica, documenti).
  catechista,

  /// Responsabile Catechistico: permessi globali di scrittura/modifica/
  /// cancellazione su classi, aule, assegnazioni e log GDPR.
  responsabile;

  /// Nome persistente (chiave Hive) del ruolo.
  String get storageKey => name;

  /// Etichetta localizzata mostrata nelle UI.
  String get label => switch (this) {
    UserRole.catechista => 'Catechista',
    UserRole.responsabile => 'Responsabile Catechistico',
  };

  static UserRole fromStorageKey(String? value) {
    return UserRole.values.firstWhere(
      (r) => r.storageKey == value,
      orElse: () => UserRole.catechista,
    );
  }

  static const _roleKey = 'user_role';

  /// Legge il ruolo corrente dell'utente dal box auth.
  static UserRole current() {
    try {
      return fromStorageKey(LocalDatabase.auth().get(_roleKey) as String?);
    } catch (_) {
      return UserRole.catechista;
    }
  }

  /// Imposta il ruolo corrente (persistente).
  static Future<void> setCurrent(UserRole role) async {
    await LocalDatabase.auth().put(_roleKey, role.storageKey);
  }

  /// True se l'utente locale è il Responsabile Catechistico.
  static bool get isResponsabile => current() == UserRole.responsabile;
}

/// Permesso specifico protetto dalla matrice ruoli.
enum RolePermission {
  /// Creazione/rinomina/archiviazione/eliminazione delle classi.
  manageClasses,

  /// Assegnazione/rimozione dei catechisti alle classi (con ruoli interni).
  assignCatechists,

  /// Gestione delle aule/luoghi e degli slot orari settimanali.
  manageAulas,

  /// Lettura e gestione del Registro Trattamenti (AuditLog).
  manageAuditLog,

  /// Diritto all'Oblio: hard delete + generazione TOMBSTONE P2P.
  rightToOblivion,

  /// Esportazione del registro trattamenti e backup parrocchiale cifrato.
  gdprExport,

  /// Gestione della configurazione parrocchiale e del passaggio d'anno.
  manageParishConfig,
}

/// Matrice dei permessi basata sul ruolo.
///
/// L'accesso alle entità "globali" è riservato a [UserRole.responsabile].
/// Il catechista gode dei soli permessi operativi sulla propria classe.
class RolePermissions {
  const RolePermissions._();

  /// Ritorna true se [role] possiede il permesso [permission].
  static bool can(UserRole role, RolePermission permission) {
    return switch (permission) {
      // Permessi globali: SOLO il Responsabile.
      RolePermission.manageClasses ||
      RolePermission.assignCatechists ||
      RolePermission.manageAulas ||
      RolePermission.manageAuditLog ||
      RolePermission.rightToOblivion ||
      RolePermission.gdprExport ||
      RolePermission.manageParishConfig => role == UserRole.responsabile,
    };
  }

  /// True se il ruolo corrente (utente locale) possiede [permission].
  static bool currentCan(RolePermission permission) =>
      can(UserRole.current(), permission);

  /// Elenco dei permessi detenuti dal ruolo (per UI dinamica).
  static Set<RolePermission> permissionsOf(UserRole role) => {
    for (final p in RolePermission.values)
      if (can(role, p)) p,
  };
}
