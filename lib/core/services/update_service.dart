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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/io_client.dart';
import 'package:go_router/go_router.dart';

import 'crypto_utils.dart';

/// GlobalKey per la navigazione dalle notifiche.
/// Inizializzato in main.dart e usato per navigare a /updates
/// quando l'utente tocca la notifica di aggiornamento disponibile.
GlobalKey<NavigatorState>? navigatorKey;

/// MethodChannel nativo per operazioni di update (install APK, cleanup)
const _updateChannel = MethodChannel('com.delelimed.catechhub/update');

/// SHA-256 fingerprints (base64) dei certificati attendibili per
/// api.github.com. Il valore è l'hash SHA-256 della codifica DER del
/// certificato, in Base64.
///
/// Aggiornare alla rotazione dei certificati GitHub (solitamente rinnovati
/// via Sectigo). Per ottenere i fingerprint correnti:
///   `openssl s_client -connect api.github.com:443 -servername api.github.com -showcerts </dev/null`
///   quindi per ogni certificato del chain:
///   `openssl x509 -in cert.pem -outform DER | openssl dgst -sha256 -binary | base64`
///
/// La lista contiene il certificato foglia + il certificato intermedio
/// (Sectigo Public Server Authentication CA DV E36) + la root ECDSA: si
/// pinna così la catena reale osservata, non un valore fittizio.
const _pinnedGitHubFingerprints = <String>[
  // Foglia — api.github.com (Let's Encrypt/Sectigo, verificato da openssl)
  'tCtq6FIU8x8+9dSOEYCkb7nA19j+j9ICJWZQzVLgWeg=',
  // Foglia — github.com (download APK e digest: browser_download_url)
  'F/j9Lj/SwRP8uXctikuruFIt0G3QeUkVpP+YsbaGOgA=',
  // Foglia — objects.githubusercontent.com (redirect finale download APK)
  'cfEHfbN3/XuNaDgNpm+mgjijA7KRG8t3CzsqQmaTz4Q=',
  // Intermedio — Sectigo Public Server Authentication CA DV E36
  'hz8LqA46wiJlbf0EFYzBXCkn1C1dBfAd7kpH60OpFt8=',
  // Root — Sectigo USERTrust ECC / Root E46
  '6muJ7WkHogn/kYhnb7Fk56ztiUuJlt++XOW7zCLeTd0=',
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
    final fingerprint = base64Encode(sha256BytesSync(derBytes));
    return _pinnedGitHubFingerprints.any((f) => f == fingerprint);
  } catch (_) {
    return false;
  }
}

/// Crea un [HttpClient] con certificate pinning per i domini GitHub.
///
/// Esclude la trust store di sistema e accetta SOLO certificati il cui
/// fingerprint (leaf o intermedio) è in [_pinnedGitHubFingerprints] (true
/// pinning). Se la lista è vuota, restituisce `null`: il chiamante deve
/// saltare la connessione (fail-closed) anziché degradare alla trust store.
HttpClient? createPinnedHttpClient() {
  if (_pinnedGitHubFingerprints.isEmpty) {
    // Fail-closed: mai connettersi senza un allowlist di fingerprint
    // esplicito. Un fallback alla trust store di sistema con un commento
    // "pinning" sarebbe una falsa sicurezza (e il check veniva silenziosamente
    // disabilitato da una lista vuota).
    return null;
  }
  final context = SecurityContext(withTrustedRoots: false);
  return HttpClient(context: context)
    ..badCertificateCallback = (cert, host, port) {
      if (host.endsWith('api.github.com') ||
          host.endsWith('github.com') ||
          host.endsWith('objects.githubusercontent.com')) {
        return _checkPinnedCertificate(cert);
      }
      return false;
    };
}

/// Controllo opzionale aggiornamenti da GitHub (disattivabile in privacy).
class UpdateService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
  }

  /// Client HTTP (package:http) con certificate pinning per i domini GitHub
  /// usati dall'aggiornamento (API, download APK, digest). Restituisce `null`
  /// se il pinning non è configurato: i chiamanti devono interrompere
  /// l'operazione (fail-closed) e NON degradare a un client non pinnato.
  ///
  /// Il client va chiuso dal chiamante con `close()` al termine.
  static IOClient? createPinnedClient() {
    final raw = createPinnedHttpClient();
    return raw == null ? null : IOClient(raw);
  }

  /// Inizializza il plugin notifiche con callback di navigazione.
  static Future<void> initNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/launcher_icon',
    );
    const settings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) async {
        if (response.payload == 'update_available' &&
            navigatorKey?.currentContext != null) {
          GoRouter.of(navigatorKey!.currentContext!).go('/updates');
        }
      },
    );
  }

  static Future<PermissionStatus> notificationPermissionStatus() =>
      Permission.notification.status;
  static Future<PermissionStatus> requestNotificationPermission() =>
      Permission.notification.request();
  static Future<bool> isNotificationPermissionGranted() async {
    final status = await notificationPermissionStatus();
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
  }

  static Future<bool> openNotificationSettings() => openAppSettings();

  /// Controlla se esiste una release più recente su GitHub.
  /// Se sì, mostra notifica locale "Aggiornamento disponibile".
  /// La connessione usa certificate pinning per prevenire MitM.
  static Future<void> checkForUpdates() async {
    try {
      final pinnedClient = createPinnedHttpClient();
      if (pinnedClient == null) {
        // Nessun fingerprint di pinning configurato: non ci colleghiamo.
        if (kDebugMode) {
          debugPrint(
            'Controllo aggiornamenti saltato: pinning non configurato',
          );
        }
        return;
      }
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final httpClient = IOClient(pinnedClient);
      final response = await httpClient
          .get(
            Uri.parse(
              'https://api.github.com/repos/delelimed/CatechHub/releases/latest',
            ),
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
      debugPrint('Errore controllo aggiornamenti: $e');
    }
  }

  static bool _isVersionNewer(String current, String latest) =>
      isVersionNewerStatic(current, latest);

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
      'update_channel_id',
      'Aggiornamenti App',
      channelDescription: 'Notifiche per i nuovi aggiornamenti di CatechHub',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/launcher_icon',
    );
    await _notificationsPlugin.show(
      id: 0,
      title: 'Aggiornamento disponibile',
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
      debugPrint('Errore installazione APK: ${e.message}');
      rethrow;
    }
  }

  /// Elimina file .apk residui dalle directory dell'app.
  /// Chiamato all'avvio dell'app (native side) e opzionalmente qui.
  static Future<void> cleanupOldApks() async {
    try {
      await _updateChannel.invokeMethod('cleanupOldApks');
    } on PlatformException catch (e) {
      debugPrint('Errore cleanup APK: ${e.message}');
    }
  }
}
