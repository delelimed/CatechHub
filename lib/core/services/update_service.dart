import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';

// GlobalKey per la navigazione dalle notifiche
// Deve essere inizializzata in main.dart
GlobalKey<NavigatorState>? navigatorKey;

/// Controllo opzionale aggiornamenti da GitHub (disattivato di default per privacy).
class UpdateService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Metodo per impostare la navigatorKey
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
  }

  static Future<void> initNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const settings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) async {
        // Apri la pagina di aggiornamento
        final payload = response.payload;
        if (payload == 'update_available' && navigatorKey != null) {
          final context = navigatorKey!.currentContext;
          if (context != null) {
            GoRouter.of(context).go('/updates');
          }
        }
      },
    );
  }

  static Future<void> checkForUpdates() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse(
          'https://api.github.com/repos/CatechHub-dev/CatechHub/releases/latest',
        ),
      );

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

  static bool _isVersionNewer(String current, String latest) {
    return isVersionNewerStatic(current, latest);
  }

  static bool isVersionNewerStatic(String current, String latest) {
    final currentParts = current.split('.').map(int.parse).toList();
    final latestParts = latest.split('.').map(int.parse).toList();

    for (var i = 0; i < latestParts.length; i++) {
      if (i >= currentParts.length) return true;
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  static Future<void> _showUpdateNotification(String version) async {
    const androidDetails = AndroidNotificationDetails(
      'update_channel_id',
      'Aggiornamenti App',
      channelDescription: 'Notifiche per i nuovi aggiornamenti di CatechHub',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const platformDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      id: 0,
      title: 'Aggiornamento disponibile',
      body: 'Versione $version. Tocca per aprire la pagina Aggiornamenti.',
      notificationDetails: platformDetails,
      payload: 'update_available', // Payload per aprire la pagina
    );
  }
}
