// ══════════════════════════════════════════════════════════════════════════════
// app_mode.dart — CatechHub (modalità operativa dell'account)
//
// Distingue le tre modalità operative configurate in onboarding:
//   - normal:       Modalità Normale (senza responsabile) — catechista autonomo
//   - associato:    "Associa a Classe Esistente" — dispositivo collegato a una
//                   parrocchia gestita (REPLICATED_PEER / join)
//   - responsabile: Modalità Responsabile Catechistico
//
// Regole per le supplenze:
//   - Nella modalità normale le supplenze NON sono consentite.
//   - Nella modalità associato le supplenze sono consentite SOLO se nella
//     parrocchia è attiva la modalità Responsabile.
//   - Il Responsabile non usa le supplenze (gestisce direttamente la parrocchia).
// ══════════════════════════════════════════════════════════════════════════════

import '../../core/storage/local_database.dart';
import '../../features/responsabile/parish_config_repository.dart';
import '../models/user_role.dart';

/// Modalità operativa dell'account locale.
enum AppMode {
  normal,
  associato,
  responsabile;

  /// Etichetta leggibile per le UI.
  String get label => switch (this) {
    AppMode.normal => 'Modalità Normale',
    AppMode.associato => 'Modalità Associato',
    AppMode.responsabile => 'Modalità Responsabile',
  };
}

/// Helper sulla modalità operativa corrente (persistita nel box auth).
class AppModeUtils {
  AppModeUtils._();

  static const _appModeKey = 'app_mode';

  /// Legge la modalità operativa corrente dal box auth.
  static AppMode current() {
    try {
      final box = LocalDatabase.auth();
      final mode = box.get(_appModeKey, defaultValue: 'NORMAL') as String;
      return switch (mode) {
        'RESPONSABILE' => AppMode.responsabile,
        'REPLICATED_PEER' => AppMode.associato,
        _ => AppMode.normal,
      };
    } catch (_) {
      return AppMode.normal;
    }
  }

  /// True se l'account è in modalità normale (catechista autonomo).
  static bool get isNormal => current() == AppMode.normal;

  /// True se l'account è in modalità associato (collegato a una parrocchia).
  static bool get isAssociato => current() == AppMode.associato;

  /// True se l'account è in modalità responsabile.
  static bool get isResponsabileMode => current() == AppMode.responsabile;

  /// True se la funzione "Supplenze" è abilitata per l'account corrente.
  ///
  /// Disabilitata per il Responsabile e per la modalità normale; abilitata
  /// solo in modalità associato quando la parrocchia usa la modalità
  /// Responsabile.
  static bool supplenzeEnabled() {
    if (UserRole.isResponsabile) return false;
    if (isNormal) return false;
    try {
      final config = ParishConfigRepository().getConfig();
      if (!config.isResponsabileModeActive) return false;
    } catch (_) {
      return false;
    }
    return true;
  }

  /// True se l'account può consultare (in sola lettura) la logistica
  /// parrocchiale: aule, stanze e tabella orario settimanale.
  ///
  /// Vale per i dispositivi "Associato" (collegati a una parrocchia gestita)
  /// quando la parrocchia usa la modalità Responsabile. La modifica delle
  /// aule resta riservata al Responsabile.
  static bool canViewLogistica() {
    if (UserRole.isResponsabile) return true;
    if (isNormal) return false;
    try {
      final config = ParishConfigRepository().getConfig();
      if (!config.isResponsabileModeActive) return false;
    } catch (_) {
      return false;
    }
    return true;
  }

  /// True se l'account può consultare il calendario (pianificazione) di TUTTA
  /// la parrocchia. Vale per il Responsabile e per i dispositivi "Associato"
  /// quando la parrocchia usa la modalità Responsabile.
  static bool canViewCalendarioParrocchia() {
    if (UserRole.isResponsabile) return true;
    if (isNormal) return false;
    try {
      final config = ParishConfigRepository().getConfig();
      if (!config.isResponsabileModeActive) return false;
    } catch (_) {
      return false;
    }
    return true;
  }

  /// True se l'account può consultare le anagrafiche di OGNI ragazzo della
  /// parrocchia (non solo della propria classe). Vale per il Responsabile e per
  /// i dispositivi "Associato" quando la parrocchia usa la modalità Responsabile.
  static bool canViewAnagraficheParrocchia() {
    if (UserRole.isResponsabile) return true;
    if (isNormal) return false;
    try {
      final config = ParishConfigRepository().getConfig();
      if (!config.isResponsabileModeActive) return false;
    } catch (_) {
      return false;
    }
    return true;
  }

  /// True se l'account può consultare il registro assenze/presenze di OGNI
  /// ragazzo della parrocchia. Vale per il Responsabile e per i dispositivi
  /// "Associato" quando la parrocchia usa la modalità Responsabile.
  static bool canViewRegistroAssenze() {
    if (UserRole.isResponsabile) return true;
    if (isNormal) return false;
    try {
      final config = ParishConfigRepository().getConfig();
      if (!config.isResponsabileModeActive) return false;
    } catch (_) {
      return false;
    }
    return true;
  }

  /// Rende coerenti tra loro tutte le variabili della modalità Responsabile
  /// (app_mode, user_role e configurazione parrocchiale). Da chiamare
  /// all'avvio: se l'account è in modalità Responsabile assicura che il
  /// ruolo e la configurazione parrocchiale risultino attivi, così la
  /// dashboard non mostra mai "Accesso riservato" dopo un avvio.
  static Future<void> ensureConsistency() async {
    try {
      final isResponsabile = current() == AppMode.responsabile;
      final repo = ParishConfigRepository();
      final config = repo.getConfig();
      if (config.isResponsabileModeActive != isResponsabile) {
        await repo.forceResponsabileMode(isResponsabile);
      }
      if (isResponsabile && !UserRole.isResponsabile) {
        await UserRole.setCurrent(UserRole.responsabile);
      }
    } catch (_) {}
  }
}
