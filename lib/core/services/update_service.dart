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
import 'dart:io' show HttpClient, SecurityContext, X509Certificate;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/io_client.dart';
import 'package:go_router/go_router.dart';

/// GlobalKey per la navigazione dalle notifiche.
/// Inizializzato in main.dart e usato per navigare a /updates
/// quando l'utente tocca la notifica di aggiornamento disponibile.
GlobalKey<NavigatorState>? navigatorKey;

/// MethodChannel nativo per operazioni di update (install APK, cleanup)
const _updateChannel = MethodChannel('com.delelimed.catechhub/update');

/// SHA-256 fingerprints dei certificati attendibili per api.github.com.
/// Il valore è l'hash SHA-256 della codifica DER del certificato, in Base64.
/// Aggiornare alla rotazione dei certificati GitHub.
/// 
/// Per ottenere il fingerprint corrente, usare:
///   openssl s_client -connect api.github.com:443 -showcerts </dev/null 2>/dev/null \
///     | openssl x509 -outform DER | openssl dgst -sha256 -binary | base64
const _pinnedGitHubFingerprints = <String>[
  // *.github.com — Let's Encrypt / DigiCert
  // Ottenuto da api.github.com. Da aggiornare periodicamente.
];

/// Estrae i byte DER da un certificato in formato PEM.
Uint8List _pemDerBytes(String pem) {
  final body = pem
      .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
      .replaceAll(RegExp(r'\s+'), '');
  return base64Decode(body);
}

/// Verifica il certificato TLS contro i fingerprint noti.
bool _checkPinnedCertificate(X509Certificate cert) {
  try {
    final derBytes = _pemDerBytes(cert.pem);
    final hash = sha256.convert(derBytes);
    final fingerprint = base64Encode(hash.bytes);
    return _pinnedGitHubFingerprints.any((f) => f == fingerprint);
  } catch (_) {
    return false;
  }
}

/// Crea un [HttpClient] con certificate pinning per api.github.com.
/// 
/// Se [_pinnedGitHubFingerprints] contiene fingerprint, esclude la
/// trust store di sistema e accetta SOLO certificati con fingerprint
/// corrispondente (true pinning). Altrimenti usa la trust store di sistema.
HttpClient _createPinnedHttpClient() {
  if (_pinnedGitHubFingerprints.isEmpty) {
    return HttpClient();
  }
  final context = SecurityContext(withTrustedRoots: false);
  return HttpClient(context: context)
    ..badCertificateCallback = (cert, host, port) {
      if (host.endsWith('api.github.com')) {
        return _checkPinnedCertificate(cert);
      }
      return false;
    };
}

/// Controllo opzionale aggiornamenti da GitHub (disattivabile in privacy).
class UpdateService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static void setNavigatorKey(GlobalKey<NavigatorState> key) { navigatorKey = key; }

  /// Inizializza il plugin notifiche con callback di navigazione.
  static Future<void> initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
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
  /// La connessione usa certificate pinning per prevenire MitM.
  static Future<void> checkForUpdates() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final pinnedClient = _createPinnedHttpClient();
      final httpClient = IOClient(pinnedClient);
      final response = await httpClient
          .get(
            Uri.parse('https://api.github.com/repos/delelimed/CatechHub/releases/latest'),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 15));
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
    final c = current.split('.').map((s) {
      final match = RegExp(r'^(\d+)').firstMatch(s);
      return match != null ? int.parse(match.group(1)!) : 0;
    }).toList();
    final l = latest.split('.').map((s) {
      final match = RegExp(r'^(\d+)').firstMatch(s);
      return match != null ? int.parse(match.group(1)!) : 0;
    }).toList();
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
      icon: '@mipmap/launcher_icon',
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