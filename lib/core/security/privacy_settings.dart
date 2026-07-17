// ══════════════════════════════════════════════════════════════════════════════
// privacy_settings.dart — CatechHub (impostazioni privacy e sicurezza)
//
// Gestisce le preferenze di privacy dell'utente, persistite nella Hive
// box auth 'registroBox'. Le impostazioni sono accessibili tramite
// Riverpod StateNotifier (privacySettingsProvider).
//
// CONTESTO PROGETTO:
//   CatechHub mette la privacy al centro del design. Queste impostazioni
//   controllano:
//   - lockOnBackground: blocca la sessione dopo 120s in background
//   - blockScreenshots: attiva FLAG_SECURE su Android (impedisce screenshot)
//   - checkUpdatesOnStart: controlla aggiornamenti all'avvio/resume
//   - allowRemoteFeedback: abilita survey Wiredash
//
//   Tutti i valori defaultano a true (massima sicurezza). L'utente può
//   modificarli da PrivacySecurityPage (route: /privacy-security).
//   applyNativeOptions() viene chiamato in main.dart all'avvio per
//   applicare FLAG_SECURE prima ancora che l'utente veda la UI.
// ══════════════════════════════════════════════════════════════════════════════

//import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../services/update_service.dart';
import '../storage/local_database.dart';
import 'screen_security.dart';

/// Preferenze di privacy e sicurezza (archivio Hive cifrato `registroBox`).
class PrivacySettings {
  const PrivacySettings({
    required this.lockOnBackground,
    required this.blockScreenshots,
    required this.checkUpdatesOnStart,
    required this.allowRemoteFeedback,
    this.absenceThreshold = 6,
  });

  /// Blocca la sessione dopo 120s in background. Letto da
  /// SessionLifecycleObserver per avviare il timer al pause.
  final bool lockOnBackground;

  /// Attiva FLAG_SECURE su Android (impedisce screenshot/registrazione).
  /// Applicato tramite MethodChannel a ScreenSecurity.setEnabled().
  final bool blockScreenshots;

  /// Controlla aggiornamenti GitHub all'avvio e al resume dal background.
  final bool checkUpdatesOnStart;

  /// Abilita survey e feedback remoti tramite Wiredash.
  final bool allowRemoteFeedback;

  /// Soglia minima di assenze per mostrare un ragazzo nella dashboard.
  final int absenceThreshold;

  static const defaults = PrivacySettings(
    lockOnBackground: true,
    blockScreenshots: true,
    checkUpdatesOnStart: true,
    allowRemoteFeedback: true,
  );
}

final privacySettingsProvider =
    StateNotifierProvider<PrivacySettingsNotifier, PrivacySettings>(
      (ref) => PrivacySettingsNotifier(),
    );

class PrivacySettingsNotifier extends StateNotifier<PrivacySettings> {
  PrivacySettingsNotifier() : super(loadFromStorage());

  static PrivacySettings loadFromStorage() {
    final box = LocalDatabase.auth();
    return PrivacySettings(
      lockOnBackground: box.get(
        'privacy_lock_on_background',
        defaultValue: true,
      ),
      blockScreenshots: box.get(
        'privacy_block_screenshots',
        defaultValue: true,
      ),
      checkUpdatesOnStart: box.get('privacy_check_updates', defaultValue: true),
      allowRemoteFeedback: box.get(
        'privacy_allow_feedback',
        defaultValue: true,
      ),
      absenceThreshold: box.get(
        'absence_threshold',
        defaultValue: 6,
      ),
    );
  }

  Future<void> _persist() async {
    final box = LocalDatabase.auth();
    await box.put('privacy_lock_on_background', state.lockOnBackground);
    await box.put('privacy_block_screenshots', state.blockScreenshots);
    await box.put('privacy_check_updates', state.checkUpdatesOnStart);
    await box.put('privacy_allow_feedback', state.allowRemoteFeedback);
    await box.put('absence_threshold', state.absenceThreshold);
  }

  Future<void> setLockOnBackground(bool value) async {
    state = PrivacySettings(
      lockOnBackground: value,
      blockScreenshots: state.blockScreenshots,
      checkUpdatesOnStart: state.checkUpdatesOnStart,
      allowRemoteFeedback: state.allowRemoteFeedback,
      absenceThreshold: state.absenceThreshold,
    );
    await _persist();
  }

  Future<void> setBlockScreenshots(bool value) async {
    state = PrivacySettings(
      lockOnBackground: state.lockOnBackground,
      blockScreenshots: value,
      checkUpdatesOnStart: state.checkUpdatesOnStart,
      allowRemoteFeedback: state.allowRemoteFeedback,
      absenceThreshold: state.absenceThreshold,
    );
    await _persist();
    await ScreenSecurity.setEnabled(value);
  }

  Future<void> setCheckUpdatesOnStart(bool value) async {
    state = PrivacySettings(
      lockOnBackground: state.lockOnBackground,
      blockScreenshots: state.blockScreenshots,
      checkUpdatesOnStart: value,
      allowRemoteFeedback: state.allowRemoteFeedback,
      absenceThreshold: state.absenceThreshold,
    );
    await _persist();
    if (value) {
      UpdateService.checkForUpdates();
    }
  }

  Future<void> setAllowRemoteFeedback(bool value) async {
    state = PrivacySettings(
      lockOnBackground: state.lockOnBackground,
      blockScreenshots: state.blockScreenshots,
      checkUpdatesOnStart: state.checkUpdatesOnStart,
      allowRemoteFeedback: value,
      absenceThreshold: state.absenceThreshold,
    );
    await _persist();
  }

  Future<void> setAbsenceThreshold(int value) async {
    state = PrivacySettings(
      lockOnBackground: state.lockOnBackground,
      blockScreenshots: state.blockScreenshots,
      checkUpdatesOnStart: state.checkUpdatesOnStart,
      allowRemoteFeedback: state.allowRemoteFeedback,
      absenceThreshold: value,
    );
    await _persist();
  }

  /// Applica le opzioni native (FLAG_SECURE, ecc.) all'avvio dell'app.
  static Future<void> applyNativeOptions(PrivacySettings settings) async {
    await ScreenSecurity.setEnabled(settings.blockScreenshots);
  }
}
