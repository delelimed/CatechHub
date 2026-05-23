import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  // Inizializza le notifiche locali
  static Future<void> initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        if (response.payload != null) {
          final url = Uri.parse(response.payload!);
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          }
        }
      },
    );
  }

  // Controlla se esiste una nuova versione su GitHub
  static Future<void> checkForUpdates() async {
    // 1. Richiedi il permesso per le notifiche (necessario su Android 13+)
    if (await Permission.notification.request().isGranted) {
      try {
        // 2. Recupera la versione attuale dell'app
        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version; // Es. "1.0.0"

        // 3. Interroga le API di GitHub per l'ultima release
        final response = await http.get(
          Uri.parse('https://api.github.com/repos/delelimed/CatechHub/releases/latest'),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final String latestVersion = (data['tag_name'] as String).replaceAll('v', ''); // Rimuove l'eventuale 'v'
          final String downloadUrl = data['html_url']; // Link alla pagina della release o direttamente all'APK se preferisci

          // 4. Confronta le versioni (confronto base, espandibile se usi sub-versioni complesse)
          if (_isVersionNewer(currentVersion, latestVersion)) {
            _showUpdateNotification(latestVersion, downloadUrl);
          }
        }
      } catch (e) {
        // Gestisci silenziosamente l'errore per non bloccare l'avvio dell'app in assenza di rete
        print('Errore durante il controllo aggiornamenti: $e');
      }
    }
  }

  // Semplice helper per confrontare le stringhe di versione (Es. 1.0.1 > 1.0.0)
  static bool _isVersionNewer(String current, String latest) {
    List<int> currentParts = current.split('.').map(int.parse).toList();
    List<int> latestParts = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < latestParts.length; i++) {
      if (i >= currentParts.length) return true;
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  // Mostra la notifica di sistema
  static Future<void> _showUpdateNotification(String version, String url) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'update_channel_id',
      'Aggiornamenti App',
      channelDescription: 'Notifiche per i nuovi aggiornamenti di CatechHub',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      0,
      'Aggiornamento Disponibile!',
      'È presente la versione $version. Tocca qui per scaricarla.',
      platformDetails,
      payload: url, // Passiamo il link come payload per aprirlo al clic
    );
  }
}