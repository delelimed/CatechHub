// ══════════════════════════════════════════════════════════════════════════════
// bluetooth_permission_service.dart — CatechHub (gestione permessi BT)
//
// Servizio centralizzato per richiedere e verificare i permessi Bluetooth
// su Android, con supporto differenziato per API 30 (Android 11) e 31+.
//
// CONTESTO PROGETTO:
//   Il modulo di sincronizzazione P2P (Bluetooth RFCOMM) richiede permessi
//   runtime variabili in base alla versione Android:
//   - Android 11 (API 30): ACCESS_FINE_LOCATION (richiesto da Android per
//     la scansione Bluetooth, anche se CatechHub non usa la posizione)
//   - Android 12+ (API 31+): BLUETOOTH_SCAN, BLUETOOTH_CONNECT,
//     BLUETOOTH_ADVERTISE (localizzazione NON necessaria)
//
//   Questo servizio viene chiamato PRIMA di qualsiasi operazione BT
//   (scansione discovery o connessione RFCOMM) per garantire che
//   l'utente abbia concesso i permessi necessari.
//
// FLUSSO:
//   1. checkAndRequestPermissions() determina i permessi per SDK
//   2. Se negati (prima volta): mostra rationale dialog
//   3. Se negati permanentemente: invita ad aprire Impostazioni
//   4. Verifica anche Bluetooth attivo e GPS (solo API 30)
//
// DIPENDENZE:
//   - permission_handler: richiesta permessi runtime
//   - MethodChannel 'ch.catechhub.app/bluetooth_pairing': stato BT nativo
//   - MethodChannel 'com.delelimed.catechhub/security': SDK version
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Risultato della verifica dei permessi Bluetooth.
class PermissionCheckResult {
  /// Tutti i permessi richiesti sono stati concessi.
  final bool allGranted;

  /// Almeno un permesso è stato negato permanentemente.
  final bool hasPermanentlyDenied;

  /// Elenco dei permessi negati (non permanentemente).
  final List<Permission> deniedPermissions;

  /// Elenco dei permessi negati permanentemente.
  final List<Permission> permanentlyDeniedPermissions;

  /// Messaggio di errore leggibile per l'utente.
  final String? errorMessage;

  const PermissionCheckResult({
    required this.allGranted,
    required this.hasPermanentlyDenied,
    required this.deniedPermissions,
    required this.permanentlyDeniedPermissions,
    this.errorMessage,
  });

  factory PermissionCheckResult.success() => const PermissionCheckResult(
        allGranted: true,
        hasPermanentlyDenied: false,
        deniedPermissions: [],
        permanentlyDeniedPermissions: [],
      );

  factory PermissionCheckResult.failure({
    required String message,
    List<Permission> denied = const [],
    List<Permission> permanent = const [],
  }) =>
      PermissionCheckResult(
        allGranted: false,
        hasPermanentlyDenied: permanent.isNotEmpty,
        deniedPermissions: denied,
        permanentlyDeniedPermissions: permanent,
        errorMessage: message,
      );
}

/// Servizio centralizzato per la gestione dei permessi Bluetooth su Android.
class BluetoothPermissionService {
  static final BluetoothPermissionService _instance =
      BluetoothPermissionService._();
  factory BluetoothPermissionService() => _instance;
  BluetoothPermissionService._();

  /// Verifica e richiede tutti i permessi Bluetooth necessari.
  /// Chiamare PRIMA di scansione o connessione RFCOMM.
  static Future<PermissionCheckResult> checkAndRequestPermissions({
    BuildContext? context,
  }) async {
    if (!Platform.isAndroid) {
      return PermissionCheckResult.success();
    }

    final permissions = await _getRequiredPermissions();
    final sdkInt = await _getAndroidSdkVersion();

    final statuses = <Permission, PermissionStatus>{};
    for (final perm in permissions) {
      statuses[perm] = await perm.status;
    }

    final notGranted = <Permission>[];
    final permanentlyDenied = <Permission>[];

    for (final entry in statuses.entries) {
      if (entry.value.isGranted || entry.value.isLimited) continue;
      if (entry.value.isPermanentlyDenied) {
        permanentlyDenied.add(entry.key);
      } else {
        notGranted.add(entry.key);
      }
    }

    if (permanentlyDenied.isNotEmpty) {
      final names = permanentlyDenied.map(_permissionName).join(', ');
      return PermissionCheckResult.failure(
        message:
            'I seguenti permessi sono stati bloccati definitivamente: $names. '
            'Abilitali manualmente nelle Impostazioni dell\'app.',
        permanent: permanentlyDenied,
      );
    }

    if (notGranted.isNotEmpty) {
      if (context != null) {
        final shouldShowRationale = await _shouldShowRationale(notGranted);
        if (shouldShowRationale) {
          final userAgreed = await _showRationaleDialog(context, notGranted, sdkInt);
          if (!userAgreed) {
            return PermissionCheckResult.failure(
              message: 'I permessi Bluetooth sono necessari per la sincronizzazione.',
              denied: notGranted,
            );
          }
        }
      }

      final results = await notGranted.request();
      final stillDenied = <Permission>[];
      final nowPermanentlyDenied = <Permission>[];

      for (final entry in results.entries) {
        if (entry.value.isGranted || entry.value.isLimited) continue;
        if (entry.value.isPermanentlyDenied) {
          nowPermanentlyDenied.add(entry.key);
        } else {
          stillDenied.add(entry.key);
        }
      }

      if (nowPermanentlyDenied.isNotEmpty) {
        final names = nowPermanentlyDenied.map(_permissionName).join(', ');
        return PermissionCheckResult.failure(
          message: 'I seguenti permessi sono stati bloccati: $names. Abilitali nelle Impostazioni.',
          permanent: nowPermanentlyDenied,
        );
      }

      if (stillDenied.isNotEmpty) {
        final names = stillDenied.map(_permissionName).join(', ');
        return PermissionCheckResult.failure(
          message: 'Permessi negati: $names. Servono per la sincronizzazione Bluetooth.',
          denied: stillDenied,
        );
      }
    }

    return PermissionCheckResult.success();
  }

  /// Restituisce i permessi necessari per Nearby Connections in base alla versione Android.
  static Future<List<Permission>> _getRequiredPermissions() async {
    final sdkInt = await _getAndroidSdkVersion();
    final perms = <Permission>[];
    if (sdkInt >= 31) {
      perms.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ]);
      if (sdkInt >= 32) {
        perms.add(Permission.nearbyWifiDevices);
      }
    } else {
      perms.add(Permission.locationWhenInUse);
    }
    return perms;
  }

  static Future<int> _getAndroidSdkVersion() async {
    try {
      const channel = MethodChannel('com.delelimed.catechhub/security');
      final version = await channel.invokeMethod<int>('getAndroidSdkVersion');
      return version ?? 30;
    } catch (_) {
      return 30;
    }
  }

  static Future<bool> _shouldShowRationale(List<Permission> permissions) async {
    for (final perm in permissions) {
      if (await perm.shouldShowRequestRationale) return true;
    }
    return false;
  }

  static Future<bool> _showRationaleDialog(BuildContext context, List<Permission> permissions, int sdkInt) async {
    final message = StringBuffer(
      'Per sincronizzare il registro con l\'altro catechista accanto a te, CatechHub ha bisogno dell\'accesso al Bluetooth.',
    );
    if (permissions.contains(Permission.locationWhenInUse)) {
      message.write(
        '\n\nSu questa versione di Android, la localizzazione è necessaria per rilevare i dispositivi Bluetooth. La tua posizione NON viene salvata o condivisa.',
      );
    }
    if (permissions.contains(Permission.bluetoothScan) || permissions.contains(Permission.bluetoothConnect)) {
      message.write('\n\nConsenti l\'accesso al Bluetooth per procedere.');
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.bluetooth, color: Theme.of(ctx).colorScheme.primary, size: 48),
        title: const Text('Permesso Bluetooth'),
        content: Text(message.toString()),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Consenti')),
        ],
      ),
    );
    return result ?? false;
  }

  static Future<void> showPermanentlyDeniedDialog(BuildContext context, {required String message}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.bluetooth_disabled, color: Theme.of(ctx).colorScheme.error, size: 48),
        title: const Text('Bluetooth disattivato'),
        content: Text(message.isEmpty
            ? 'L\'accesso al Bluetooth è disattivato. Per sincronizzare, abilita i permessi nelle impostazioni.'
            : message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annulla')),
          FilledButton(
            onPressed: () async { Navigator.of(ctx).pop(); await openAppSettings(); },
            child: const Text('Apri Impostazioni'),
          ),
        ],
      ),
    );
  }

  static const _btChannel = MethodChannel('ch.catechhub.app/bluetooth_pairing');

  static Future<bool> isBluetoothEnabled() async {
    try {
      final result = await _btChannel.invokeMethod<bool>('getBluetoothEnabled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> ensureBluetoothEnabled() async {
    if (await isBluetoothEnabled()) return true;
    try {
      await _btChannel.invokeMethod('requestBluetoothEnable');
      await Future.delayed(const Duration(milliseconds: 500));
      return await isBluetoothEnabled();
    } catch (_) {
      return await isBluetoothEnabled();
    }
  }

  static Future<bool> isLocationServicesEnabled() async {
    final sdkInt = await _getAndroidSdkVersion();
    if (sdkInt >= 31) return true;
    try {
      final status = await Permission.locationWhenInUse.status;
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  static String _permissionName(Permission permission) {
    switch (permission) {
      case Permission.bluetoothScan: return 'Scansione Bluetooth';
      case Permission.bluetoothConnect: return 'Connessione Bluetooth';
      case Permission.bluetoothAdvertise: return 'Pubblicità Bluetooth';
      case Permission.locationWhenInUse: return 'Localizzazione';
      case Permission.nearbyWifiDevices: return 'Wi-Fi nelle vicinanze';
      default: return permission.toString();
    }
  }
}
