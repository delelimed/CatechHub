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
// SICUREZZA TLS:
//   Usa un bundle di CA root embeddato (Mozilla) invece del pinning
//   di certificati foglia. Vantaggi:
//   - Non dipende dai certificati di sistema (funziona anche se mancanti/vecchi)
//   - Le root CA cambiano molto raramente (anni, non mesi)
//   - Validazione completa della catena di certificati
//   - Protezione MITM: accetta solo cert firmati da CA fidate
//   - Sopravvive 6+ mesi senza aggiornamenti app (finché root CA non cambiano)
//
// DIPENDENZE:
//   - http: chiamata API GitHub
//   - flutter_local_notifications: notifica locale
//   - package_info_plus: versione corrente dell'app
//   - path_provider: directory per pulizia APK
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io' show HttpClient, SecurityContext;

import 'package:flutter/foundation.dart';
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

/// Singleton per il SecurityContext con CA bundle embeddato.
/// Viene inizializzato una sola volta al primo utilizzo.
SecurityContext? _pinnedSecurityContext;

/// Inizializza il SecurityContext caricando il bundle CA embeddato.
/// Fail-closed: se il bundle non è disponibile, restituisce null e i
/// chiamanti devono interrompere la connessione (NON degradare a trust store di sistema).
Future<SecurityContext?> _initSecurityContext() async {
  if (_pinnedSecurityContext != null) {
    return _pinnedSecurityContext;
  }
  try {
    final context = SecurityContext(withTrustedRoots: false);
    final caBundle = await rootBundle.load('assets/certs/cacert.pem');
    context.setTrustedCertificatesBytes(caBundle.buffer.asUint8List());
    _pinnedSecurityContext = context;
    return context;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Errore inizializzazione SecurityContext: $e');
    }
    return null;
  }
}

/// Crea un [HttpClient] con il bundle CA embeddato per i domini GitHub.
///
/// Esclude la trust store di sistema e usa SOLO le CA root embeddate.
/// Se il bundle non è disponibile, restituisce `null`: il chiamante deve
/// saltare la connessione (fail-closed) anziché degradare alla trust store.
HttpClient? createPinnedHttpClient() {
  // Nota: l'inizializzazione asincrona del context avviene nel primo uso
  // tramite createPinnedClient(). Qui restituiamo null per forzare
  // l'uso del percorso asincrono corretto.
  return null;
}

/// Crea un [IOClient] (package:http) con il bundle CA embeddato.
///
/// Restituisce `null` se il bundle CA non è caricabile: i chiamanti
/// devono interrompere l'operazione (fail-closed) e NON degradare
/// a un client non sicuro.
///
/// Il client va chiuso dal chiamante con `close()` al termine.
Future<IOClient?> createPinnedClient() async {
  final context = await _initSecurityContext();
  if (context == null) {
    if (kDebugMode) {
      debugPrint('Client HTTP non creato: bundle CA non disponibile');
    }
    return null;
  }
  final client = HttpClient(context: context);
  return IOClient(client);
}

/// Controllo opzionale aggiornamenti da GitHub (disattivabile in privacy).
class UpdateService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
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
    final status = await Permission.notification.status;
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
  }

  static Future<bool> openNotificationSettings() => openAppSettings();

  /// Controlla se esiste una release più recente su GitHub.
  /// Se sì, mostra notifica locale "Aggiornamento disponibile".
  /// La connessione usa il bundle CA embeddato per prevenire MitM.
  static Future<void> checkForUpdates() async {
    IOClient? httpClient;
    try {
      httpClient = await createPinnedClient();
      if (httpClient == null) {
        if (kDebugMode) {
          debugPrint(
            'Controllo aggiornamenti saltato: bundle CA non disponibile',
          );
        }
        return;
      }
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
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
    } finally {
      httpClient?.close();
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