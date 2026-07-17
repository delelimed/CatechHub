// ══════════════════════════════════════════════════════════════════════════════
// update_service.dart — CatechHub (controllo aggiornamenti da GitHub)
//
// Verifica periodicamente la disponibilità di nuove versioni dell'app
// sul repository GitHub e notifica l'utente tramite notifica locale.
//
// CONTESTO PROGETTO:
//   Il controllo aggiornamenti è OPZIONALE e disattivabile dall'utente
//   in PrivacySettings (checkUpdatesOnStart). Di default è attivo.
//   Il servizio:
//   1. Chiama l'API GitHub releases/latest
//   2. Confronta la versione corrente (package_info_plus) con l'ultima
//   3. Se più recente, mostra una notifica locale "Aggiornamento disponibile"
//   4. Toccare la notifica naviga a /updates (pagina download APK)
//
//   La navigazione dalle notifiche usa un GlobalKey<NavigatorState>
//   inizializzato in main.dart (navigatorKey).
//
//   cleanupOldApks() cancella file .apk residui dopo l'installazione
//   per liberare spazio. Viene chiamato sia all'avvio (native) che qui.
//
//   L'installazione APK usa un MethodChannel nativo (com.delelimed.catechhub/update)
//   che sfrutta FileProvider per evitare errori "package parsing error"
//   su Android 7+ (API 24+).
//
// DIPENDENZE:
//   - http: chiamata API GitHub
//   - flutter_local_notifications: notifica locale
//   - package_info_plus: versione corrente dell'app
//   - path_provider: directory per pulizia APK
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';

/// GlobalKey per la navigazione dalle notifiche.
/// Inizializzato in main.dart e usato per navigare a /updates
/// quando l'utente tocca la notifica di aggiornamento disponibile.
GlobalKey<NavigatorState>? navigatorKey;

/// MethodChannel nativo per operazioni di update (install APK, cleanup)
const _updateChannel = MethodChannel('com.delelimed.catechhub/update');

/// Controllo opzionale aggiornamenti da GitHub (disattivabile in privacy).
class UpdateService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static void setNavigatorKey(GlobalKey<NavigatorState> key) { navigatorKey = key; }

  /// Inizializza il plugin notifiche con callback di navigazione.
  static Future<void> initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) async {
        if (response.payload == 'update_available' && navigatorKey?.currentContext != null) {
          GoRouter.of(navigatorKey!.currentContext!).go('/updates');
        }
      },
    );
  }

  static Future<PermissionStatus> notificationPermissionStatus() => Permission.notification.status;
  static Future<PermissionStatus> requestNotificationPermission() => Permission.notification.request();
  static Future<bool> isNotificationPermissionGranted() async {
    final status = await notificationPermissionStatus();
    return status == PermissionStatus.granted || status == PermissionStatus.limited;
  }
  static Future<bool> openNotificationSettings() => openAppSettings();

  /// Controlla se esiste una release più recente su GitHub.
  /// Se sì, mostra notifica locale "Aggiornamento disponibile".
  static Future<void> checkForUpdates() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/delelimed/CatechHub/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;
      final data = json.decode(response.body) as Map<String, dynamic>;
      final latestVersion = (data['tag_name'] as String).replaceAll('v', '');
      if (_isVersionNewer(currentVersion, latestVersion)) {
        await _showUpdateNotification(latestVersion);
      }
    } catch (e) {
      print('Errore controllo aggiornamenti: $e');
    }
  }

  static bool _isVersionNewer(String current, String latest) => isVersionNewerStatic(current, latest);

  /// Confronto semantico tra due versioni (es. "1.0.3" < "1.1.0").
  static bool isVersionNewerStatic(String current, String latest) {
    final c = current.split('.').map(int.parse).toList();
    final l = latest.split('.').map(int.parse).toList();
    for (var i = 0; i < l.length; i++) {
      if (i >= c.length) return true;
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return false;
  }

  static Future<void> _showUpdateNotification(String version) async {
    const androidDetails = AndroidNotificationDetails(
      'update_channel_id', 'Aggiornamenti App',
      channelDescription: 'Notifiche per i nuovi aggiornamenti di CatechHub',
      importance: Importance.max, priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    await _notificationsPlugin.show(
      id: 0, title: 'Aggiornamento disponibile',
      body: 'Versione $version. Tocca per aprire la pagina Aggiornamenti.',
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: 'update_available',
    );
  }

  /// Installa un APK usando il MethodChannel nativo (FileProvider).
  /// Evita errori "package parsing error" su Android 7+.
  static Future<void> installApk(String apkPath) async {
    try {
      await _updateChannel.invokeMethod('installApk', {'apkPath': apkPath});
    } on PlatformException catch (e) {
      print('Errore installazione APK: ${e.message}');
      rethrow;
    }
  }

  /// Elimina file .apk residui dalle directory dell'app.
  /// Chiamato all'avvio dell'app (native side) e opzionalmente qui.
  static Future<void> cleanupOldApks() async {
    try {
      await _updateChannel.invokeMethod('cleanupOldApks');
    } on PlatformException catch (e) {
      print('Errore cleanup APK: ${e.message}');
    }
  }
}