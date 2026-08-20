// ══════════════════════════════════════════════════════════════════════════════
// screen_security.dart — CatechHub (blocco screenshot FLAG_SECURE)
//
// Comunica con il layer nativo Kotlin per attivare/disattivare
// FLAG_SECURE sull'Activity Android, impedendo screenshot e
// registrazione dello schermo.
//
// CONTESTO PROGETTO:
//   Requisito privacy: i dati sensibili dei minori (nomi, date di
//   nascita, numeri di telefono, allergie) non devono poter essere
//   fotografati o registrati da altre app. FLAG_SECURE è una misura
//   di sicurezza difensiva che impedisce:
//   - Screenshot fisici (tasto volume giù + power)
//   - Screenshot software (Android recents)
//   - Screen recording malware
//   - App di mirroring non autorizzate
//
//   Il canale nativo è: com.delelimed.catechhub/security
//   Lo stesso canale viene usato per ottenere android.os.Build.VERSION.SDK_INT
//   in BluetoothPermissionService.
//
// CHIAMATO DA:
//   - PrivacySettings.applyNativeOptions() all'avvio
//   - PrivacySettingsNotifier.setBlockScreenshots() al cambiamento
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/services.dart';

/// Errore del blocco screenshot (FLAG_SECURE).
///
/// Lanciato quando l'abilitazione del blocco non può essere applicata o
/// verificata: fail-closed, il chiamante deve avvisare l'utente invece di
/// lasciare i dati esposti a screenshot/registrazione silenziosamente.
class ScreenSecurityException implements Exception {
  final String message;
  ScreenSecurityException(this.message);

  @override
  String toString() => 'ScreenSecurityException: $message';
}

/// Blocca screenshot e registrazione schermo su Android (FLAG_SECURE).
class ScreenSecurity {
  static const _channel = MethodChannel('com.delelimed.catechhub/security');

  /// Attiva/disattiva FLAG_SECURE.
  ///
  /// M2 (fail-closed): quando si ABILITA il blocco e l'operazione non può
  /// essere applicata/verificata (canale nativo assente, errore, verifica
  /// fallita, piattaforma non Android), lancia [ScreenSecurityException]
  /// invece di continuare silenziosamente come se lo screenshot fosse bloccato.
  /// La disattivazione è best-effort (scelta esplicita dell'utente).
  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) {
      if (enabled) {
        throw ScreenSecurityException(
          'Blocco screenshot non supportato su questa piattaforma.',
        );
      }
      return;
    }
    try {
      await _channel.invokeMethod<void>('setSecureFlag', {'enabled': enabled});
    } on PlatformException catch (e) {
      if (enabled) {
        throw ScreenSecurityException(
          'Impossibile applicare il blocco screenshot: '
          '${e.message ?? e.code}',
        );
      }
    } on MissingPluginException {
      if (enabled) {
        throw ScreenSecurityException(
          'Blocco screenshot non disponibile: canale nativo assente.',
        );
      }
    }
  }
}
