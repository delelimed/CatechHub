// ══════════════════════════════════════════════════════════════════════════════
// meeting_notification_service.dart — CatechHub (notifiche incontri/riunioni)
// ══════════════════════════════════════════════════════════════════════════════
//
// Servizio per la pianificazione e gestione delle notifiche locali
// per gli incontri di catechismo e le riunioni.
// Le notifiche vengono inviate il giorno prima dell'evento all'orario
// scelto dall'utente nelle impostazioni.
//
// Il servizio usa un Box Hive dedicato (meeting_notifications_box) che
// contiene SOLO la data e il titolo dell'incontro/riunione - NESSUN
// altro dato sensibile. Il box principale criptato (planning_box) non
// viene mai decriptato da questo servizio.
//
// DIPENDENZE:
//   - flutter_local_notifications: per notifiche locali programmate
//   - permission_handler: per permesso notifiche (Android 13+)
//   - hive_flutter: per lettura box meeting_notifications_box
// ══════════════════════════════════════════════════════════════════════════════


import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import '../../core/storage/local_database.dart';
import '../../shared/models/planning_meeting.dart';

/// Servizio per la gestione delle notifiche degli incontri/riunioni.
///
/// Responsabilità:
/// 1. Inizializzare il plugin notifiche locali con canale dedicato
/// 2. Sincronizzare il box meeting_notifications_box con il planning_box
/// 3. Programmare notifiche per il giorno prima di ogni incontro
/// 4. Gestire permessi notifiche Android 13+
/// 5. Annullare notifiche quando incontri vengono eliminati/modificati
class MeetingNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _notificationChannelId = 'meeting_reminder_channel';
  static const String _notificationChannelName = 'Promemoria Incontri';
  static const String _notificationChannelDescription =
      'Notifiche il giorno prima di incontri e riunioni';

  /// Chiavi per le impostazioni notifiche (salvate in authBox)
  static const _enabledKey = 'meeting_notifications_enabled';
  static const _timeKey = 'meeting_notifications_time';

  /// Flag per evitare inizializzazioni multiple
  static bool _initialized = false;

  /// Inizializza il fuso orario (chiamare prima di initialize()).
  static void initializeTimeZones() {
    tz_data.initializeTimeZones();
  }

  /// Inizializza il servizio notifiche.
  ///
  /// Deve essere chiamato una sola volta all'avvio dell'app (in main.dart).
  /// Configura il canale notifiche Android e richiede i permessi necessari.
  static Future<void> initialize() async {
    if (_initialized) return;

    // 1. Configura canale notifiche Android
    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const settings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Crea il canale notifiche dedicato
    await _createNotificationChannel();

    // 2. Richiedi permesso notifiche se necessario (Android 13+)
    await _requestNotificationPermissionIfNeeded();

    _initialized = true;
  }

  /// Crea il canale notifiche Android dedicato agli incontri.
  static Future<void> _createNotificationChannel() async {
    const androidChannel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: _notificationChannelDescription,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// Richiede il permesso notifiche se non già concesso (Android 13+).
  static Future<void> _requestNotificationPermissionIfNeeded() async {
    final status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }
  }

  /// Callback quando l'utente tocca una notifica.
  static void _onNotificationTapped(NotificationResponse response) {
    // Navigazione opzionale alla pagina planning
    // Per ora apriamo l'app alla home
    print('Notifica incontro toccata: ${response.payload}');
  }

  /// Verifica se le notifiche incontri sono abilitate.
  static bool get areNotificationsEnabled {
    final box = LocalDatabase.auth();
    return box.get(_enabledKey, defaultValue: true) as bool;
  }

  /// Verifica se il permesso notifiche è concesso.
  static Future<bool> get isPermissionGranted async {
    final status = await Permission.notification.status;
    return status.isGranted || status.isLimited;
  }

  /// Ottiene l'orario configurato per le notifiche (formato "HH:mm").
  /// Default: "19:00"
  static String get notificationTime {
    final box = LocalDatabase.auth();
    return box.get(_timeKey, defaultValue: '19:00') as String;
  }

  /// Abilita/disabilita le notifiche incontri.
  static Future<void> setEnabled(bool enabled) async {
    final box = LocalDatabase.auth();
    await box.put(_enabledKey, enabled);

    if (enabled) {
      await rescheduleAllNotifications();
    } else {
      await cancelAllNotifications();
    }
  }

  /// Imposta l'orario per le notifiche (formato "HH:mm").
  static Future<void> setNotificationTime(String time) async {
    final box = LocalDatabase.auth();
    await box.put(_timeKey, time);

    if (areNotificationsEnabled) {
      await rescheduleAllNotifications();
    }
  }

  /// Sincronizza il box meeting_notifications_box con il planning_box.
  ///
  /// Il box meeting_notifications_box contiene SOLO:
  /// - id (String): stesso ID del meeting
  /// - date (String): data ISO 8601 dell'incontro
  /// - title (String): titolo dell'incontro
  /// - isReunion (bool): true se riunione, false se incontro catechismo
  ///
  /// Nessun altro dato sensibile viene copiato.
  static Future<void> syncWithPlanning() async {
    if (!areNotificationsEnabled) return;

    final planningBox = LocalDatabase.planning();
    final notificationsBox = LocalDatabase.meetingNotifications();

    // Ottieni tutti i meeting attuali
    final meetings = <String, Map<String, dynamic>>{};
    for (final key in planningBox.keys) {
      final data = planningBox.get(key);
      if (data != null) {
        meetings[key.toString()] = Map<String, dynamic>.from(data);
      }
    }

    // Sincronizza: aggiorna/inserisci meeting esistenti
    for (final entry in meetings.entries) {
      final data = entry.value;
      final dateStr = data['date']?.toString() ?? '';
      final title = data['title']?.toString() ?? '';
      final isReunion = data['isReunion'] == true;

      if (dateStr.isNotEmpty && title.isNotEmpty) {
        await notificationsBox.put(entry.key, {
          'date': dateStr,
          'title': title,
          'isReunion': isReunion,
        });
      }
    }

    // Rimuovi notifiche per meeting non più esistenti
    final notificationKeys = notificationsBox.keys.toList();
    for (final key in notificationKeys) {
      if (!meetings.containsKey(key)) {
        await _cancelNotificationForMeeting(key.toString());
        await notificationsBox.delete(key);
      }
    }

    // Riprogramma tutte le notifiche
    await rescheduleAllNotifications();
  }

  /// Riprogramma tutte le notifiche basandosi sul box meeting_notifications_box.
  static Future<void> rescheduleAllNotifications() async {
    if (!areNotificationsEnabled) return;

    final hasPermission = await isPermissionGranted;
    if (!hasPermission) {
      print('Permesso notifiche non concesso, impossibile programmare');
      return;
    }

    // Annulla tutte le notifiche esistenti
    await _notificationsPlugin.cancelAll();

    final notificationsBox = LocalDatabase.meetingNotifications();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final key in notificationsBox.keys) {
      final data = notificationsBox.get(key);
      if (data == null) continue;

      final dateStr = data['date']?.toString() ?? '';
      final title = data['title']?.toString() ?? '';
      final isReunion = data['isReunion'] as bool? ?? false;

      if (dateStr.isEmpty || title.isEmpty) continue;

      final meetingDate = DateTime.tryParse(dateStr);
      if (meetingDate == null) continue;

      // Calcola il giorno prima dell'incontro
      final notificationDate = DateTime(
        meetingDate.year,
        meetingDate.month,
        meetingDate.day,
      ).subtract(const Duration(days: 1));

      // Se la data di notifica è già passata, salta
      if (notificationDate.isBefore(today)) continue;

      // Parse orario notifica
      final timeParts = notificationTime.split(':');
      if (timeParts.length != 2) continue;

      final hour = int.tryParse(timeParts[0]) ?? 19;
      final minute = int.tryParse(timeParts[1]) ?? 0;

      final scheduledDateTime = DateTime(
        notificationDate.year,
        notificationDate.month,
        notificationDate.day,
        hour,
        minute,
      );

      // Se l'orario è già passato oggi, salta
      if (scheduledDateTime.isBefore(now)) continue;

      await _scheduleNotification(
        id: key.hashCode,
        title: isReunion ? 'Riunione domani' : 'Incontro domani',
        body: title,
        scheduledDate: scheduledDateTime,
        payload: key.toString(),
      );
    }
  }

  /// Programma una singola notifica.
  static Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _notificationChannelId,
      _notificationChannelName,
      channelDescription: _notificationChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/launcher_icon',
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: _toTZDateTime(scheduledDate),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: null,
      payload: payload,
    );
  }

  /// Annulla la notifica per un meeting specifico.
  static Future<void> _cancelNotificationForMeeting(String meetingId) async {
    await _notificationsPlugin.cancel(id: meetingId.hashCode);
  }

  /// Annulla tutte le notifiche programmate.
  static Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }

  /// Converte DateTime in TZDateTime per zonedSchedule.
  static tz.TZDateTime _toTZDateTime(DateTime dateTime) {
    return tz.TZDateTime.from(dateTime, tz.local);
  }

  /// Aggiunge/aggiorna un singolo meeting nel box notifiche e programma la notifica.
  static Future<void> addOrUpdateMeeting(PlanningMeeting meeting) async {
    final notificationsBox = LocalDatabase.meetingNotifications();

    // Salva solo data e titolo
    await notificationsBox.put(meeting.id, {
      'date': meeting.date.toIso8601String(),
      'title': meeting.title,
      'isReunion': meeting.isReunion,
    });

    // Se le notifiche sono abilitate, programma per questo meeting
    if (areNotificationsEnabled) {
      await _scheduleNotificationForMeeting(meeting);
    }
  }

  /// Rimuove un meeting dal box notifiche e cancella la notifica programmata.
  static Future<void> removeMeeting(String meetingId) async {
    final notificationsBox = LocalDatabase.meetingNotifications();
    await notificationsBox.delete(meetingId);
    await _notificationsPlugin.cancel(id: meetingId.hashCode);
  }

  /// Programma la notifica per un singolo meeting.
  static Future<void> _scheduleNotificationForMeeting(PlanningMeeting meeting) async {
    final timeParts = notificationTime.split(':');
    if (timeParts.length != 2) return;

    final hour = int.tryParse(timeParts[0]) ?? 19;
    final minute = int.tryParse(timeParts[1]) ?? 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final meetingDate = DateTime(
      meeting.date.year,
      meeting.date.month,
      meeting.date.day,
    );

    // Notifica il giorno prima
    final notificationDate = meetingDate.subtract(const Duration(days: 1));

    // Se la data di notifica è già passata, non programmare
    if (notificationDate.isBefore(today)) return;

    final scheduledDateTime = DateTime(
      notificationDate.year,
      notificationDate.month,
      notificationDate.day,
      hour,
      minute,
    );

    // Se l'orario è già passato oggi, non programmare
    if (scheduledDateTime.isBefore(now)) return;

    await _scheduleNotification(
      id: meeting.id.hashCode,
      title: meeting.isReunion ? 'Riunione domani' : 'Incontro domani',
      body: meeting.title,
      scheduledDate: scheduledDateTime,
      payload: meeting.id,
    );
  }
}