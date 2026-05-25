import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wiredash/wiredash.dart'; // <-- Importazione di Wiredash

import 'app/router.dart';
import 'core/auth/auth_provider.dart';
import 'core/storage/local_database.dart';
import 'core/analytics/analytics_service.dart';
import 'core/analytics/analytics_provider.dart';
import 'core/analytics/event_tracking_service.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT', null);
  await LocalDatabase.init();
  await AnalyticsService.init();

  // Inizializza il plugin delle notifiche locali
  await UpdateService.initNotifications();

  // Avvia il controllo degli aggiornamenti in background senza bloccare il main
  UpdateService.checkForUpdates();

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final router = ref.watch(appRouterProvider);
    final analyticsConsent = ref.watch(analyticsConsentProvider);

    // Inizializza event tracking
    EventTrackingService.init(analyticsConsent);

    // Mostra popup di consenso alla prima apertura
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showAnalyticsConsentIfNeeded(context, ref);
    });

    return Wiredash(
      projectId: const String.fromEnvironment('WIREDASH_PROJECT_ID'),
      secret: const String.fromEnvironment('WIREDASH_API_SECRET'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(primaryColor: const Color(0xFF174A7E)),
        navigatorKey: navigatorKey,
        home: authState.when(
          data: (_) {
            return Router(
              routerDelegate: router.routerDelegate,
              routeInformationParser: router.routeInformationParser,
              routeInformationProvider: router.routeInformationProvider,
            );
          },
          loading: () => const _LoadingScreen(),
          error: (err, _) => _ErrorScreen(message: 'Errore Auth: $err'),
        ),
      ),
    );
  }

  void _showAnalyticsConsentIfNeeded(BuildContext context, WidgetRef ref) {
    final box = LocalDatabase.auth();
    final hasShownConsent = box.get('consent_shown', defaultValue: false);

    if (!hasShownConsent && context.mounted) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (context.mounted) {
          _showConsentDialog(context, ref);
          box.put('consent_shown', true);
        }
      });
    }
  }

  void _showConsentDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Analisi e Feedback'),
        content: const Text(
          'Desideri permettere a CatechHub di raccogliere dati anonimi '
          'sulla tua esperienza utente? Questo ci aiuta a migliorare l\'app.\n\n'
          'Puoi cambiare questa preferenza in qualsiasi momento dalle impostazioni.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(analyticsConsentProvider.notifier).setConsent(false);
              EventTrackingService.setEnabled(false);
              Navigator.pop(context);
            },
            child: const Text('Rifiuta'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(analyticsConsentProvider.notifier).setConsent(true);
              EventTrackingService.setEnabled(true);
              Navigator.pop(context);
            },
            child: const Text('Accetta'),
          ),
        ],
      ),
    );
  }
}

// Widget interni leggeri per non appesantire l'albero con strutture duplicate
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Color(0xFF174A7E))),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String message;
  const _ErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// Servizio che gestisce il controllo delle release su GitHub e l'invio delle notifiche
class UpdateService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  /// Configura il sistema di notifiche locali e definisce l'azione al clic
  static Future<void> initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    // Corretto: adesso viene passata la variabile corretta definita poche righe sopra
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

  /// Verifica la presenza di nuove versioni richiedendo i permessi necessari
  static Future<void> checkForUpdates() async {
    // Richiede il permesso di notifica (fondamentale su Android 13+)
    if (await Permission.notification.request().isGranted) {
      try {
        // Recupera la versione corrente dell'APK installato
        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;

        // Richiesta HTTP alle API pubbliche di GitHub
        final response = await http.get(
          Uri.parse('https://api.github.com/repos/CatechHub-dev/CatechHub/releases/latest'),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final String latestVersion = (data['tag_name'] as String).replaceAll('v', '');
          final String downloadUrl = data['html_url'];

          // Se la versione su GitHub è più recente, mostra la notifica
          if (_isVersionNewer(currentVersion, latestVersion)) {
            _showUpdateNotification(latestVersion, downloadUrl);
          }
        }
      } catch (e) {
        // Fallisce silenziosamente per evitare crash se l'utente è offline all'avvio
        debugPrint('Errore controllo aggiornamenti: $e');
      }
    }
  }

  /// Algoritmo di confronto per versioni in formato semantico (es. 1.2.0 > 1.1.9)
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

  /// Genera e mostra la notifica push locale nel centro notifiche di Android
  static Future<void> _showUpdateNotification(String version, String url) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'update_channel_id',
    'Aggiornamenti App',
    channelDescription: 'Notifiche per i nuovi aggiornamenti di CatechHub',
    importance: Importance.max,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );

  const NotificationDetails platformDetails =
      NotificationDetails(android: androidDetails);

  await _notificationsPlugin.show(
    0,
    'Aggiornamento Disponibile!',
    'È presente la versione $version. Tocca qui per scaricarla.',
    platformDetails,
    payload: url,
  );
}
}