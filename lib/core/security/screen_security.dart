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

/// Blocca screenshot e registrazione schermo su Android (FLAG_SECURE).
class ScreenSecurity {
  static const _channel =
      MethodChannel('com.delelimed.catechhub/security');

  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setSecureFlag', {'enabled': enabled});
    } catch (_) {
      // Ignora su emulatori o build senza canale nativo.
    }
  }
}
