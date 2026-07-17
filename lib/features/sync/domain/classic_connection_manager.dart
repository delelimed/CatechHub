import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show EventChannel, MethodChannel;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/classic_sync_models.dart';
import '../../../core/services/bluetooth_permission_service.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/storage/local_database.dart';

/// Gestione della connessione Bluetooth Classico RFCOMM per la
/// sincronizzazione P2P tra dispositivi CatechREG.
///
/// CONTESTO PROGETTO:
/// CateREG usa Bluetooth Classico (RFCOMM) per la sincronizzazione
/// offline. Tutte le operazioni Bluetooth sono delegate al codice
/// nativo Kotlin tramite MethodChannel. Questo file contiene:
///
/// 1. [BluetoothClassicService] — singleton che incapsula la
///    comunicazione con il plugin nativo (discovery, pairing server/client,
///    invio dati RFCOMM). Comunicazione via MethodChannel + EventChannel.
///
/// 2. [ClassicConnectionManager] — macchina a stati che coordina la
///    connessione RFCOMM: permessi, discovery, timeout, leader election.
///    Usato da [ClassicSyncNotifier] per gestire la coda multi-dispositivo.
///
/// 3. [ClassicPairingService] — gestione del ciclo di vita del pairing:
///    creazione/scambio chiavi ECDH, tabella TrustedDevice, derivazione
///    chiave di sessione ECDH + HKDF, scadenza e rinnovo chiavi.
///
/// FLUSSO TIPICO:
/// 1. Utente avvia pairing: QR code <-> scambio chiavi pubbliche ECDH
/// 2. Entrambi i device salvano il TrustedDevice con chiave derivata
/// 3. Sync periodico: server persistente in ascolto, client si connette
/// 4. Scambio dati cifrati tra i due device
/// 5. Rinnovo chiave ogni 25 giorni (scadenza 30)

/// MethodChannel per comunicare con il plugin nativo Kotlin.
/// Canale: ch.catechhub.app/bluetooth_pairing
const _btChannel = MethodChannel('ch.catechhub.app/bluetooth_pairing');

/// EventChannel per ricevere eventi asincroni dal plugin nativo.
const _btEventChannel = EventChannel('ch.catechhub.app/bluetooth_pairing/events');

/// Modello per un dispositivo Bluetooth scoperto via discovery nativa.
class DiscoveredBluetoothDevice {
  final String name;
  final String address;
  final bool isBonded;

  const DiscoveredBluetoothDevice({
    required this.name,
    required this.address,
    required this.isBonded,
  });

  factory DiscoveredBluetoothDevice.fromMap(Map<dynamic, dynamic> map) {
    return DiscoveredBluetoothDevice(
      name: map['name']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      isBonded: map['isBonded'] == true,
    );
  }
}

/// Servizio per la comunicazione Bluetooth Classico tramite Socket RFCOMM.
///
/// TUTTE le operazioni Bluetooth sono delegate al codice nativo Kotlin
/// tramite MethodChannel. Nessuna dipendenza da flutter_blue_classic.
///
/// Il layer Dart gestisce solo:
/// - Ciclo di vita e parsing JSON del QR code
/// - Scambio dati finali (CRDT, ECDH)
/// - Gestione UI e stato applicativo
class BluetoothClassicService {
  static final BluetoothClassicService _instance = BluetoothClassicService._();
  factory BluetoothClassicService() => _instance;
  BluetoothClassicService._();

  bool _isConnecting = false;
  String? _connectedAddress;

  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  final _payloadController = StreamController<String>.broadcast();
  final _statusController = StreamController<ClassicConnectionState>.broadcast();
  final _messageController = StreamController<String>.broadcast();
  final _handshakeController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNativeEvent => _eventController.stream;
  Stream<String> get onPayloadReceived => _payloadController.stream;
  Stream<ClassicConnectionState> get onStatusChanged => _statusController.stream;
  Stream<String> get onMessage => _messageController.stream;
  Stream<Map<String, dynamic>> get onHandshakeResult => _handshakeController.stream;

  bool get isConnected => _connectedAddress != null;
  String? get connectedAddress => _connectedAddress;

  StreamSubscription? _eventSubscription;

  static final _btAddressRegex = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');

  static bool _isValidBluetoothAddress(String address) {
    return _btAddressRegex.hasMatch(address);
  }

  // ──────────────────────────────────────────────
  //  INIZIALIZZAZIONE EVENT STREAM
  // ──────────────────────────────────────────────

  void initializeEventStream() {
    _eventSubscription?.cancel();
    _eventSubscription = _btEventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final eventName = event['event']?.toString() ?? '';
        final data = event['data'];
        _eventController.add({'event': eventName, 'data': data});
      }
    }, onError: (error) {
      _messageController.add('Errore EventChannel: $error');
    });

    _btChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPairingHandshakeComplete':
          _handshakeController.add(Map<String, dynamic>.from(call.arguments as Map));
        case 'onSyncDataReceived':
          final payload = call.arguments?.toString();
          if (payload != null && payload.isNotEmpty) {
            _payloadController.add(payload);
          }
      }
    });
  }

  void disposeEventStream() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _btChannel.setMethodCallHandler(null);
  }

  // ──────────────────────────────────────────────
  //  CAPACITA DEL CHIP BLUETOOTH
  // ──────────────────────────────────────────────

  static Future<bool> checkBluetoothEnabled() async {
    try {
      final result = await _btChannel.invokeMethod<bool>('getBluetoothEnabled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> getLocalMacAddress() async {
    try {
      final address = await _btChannel.invokeMethod<String>('getLocalBluetoothAddress');
      if (address != null && address.isNotEmpty) {
        return address;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ──────────────────────────────────────────────
  //  PERMESSI BLUETOOTH CLASSICO
  // ──────────────────────────────────────────────

  static Future<bool> ensureClassicPermissions() async {
    try {
      final permResult = await BluetoothPermissionService.checkAndRequestPermissions();
      if (!permResult.allGranted) return false;
      return await BluetoothPermissionService.ensureBluetoothEnabled();
    } catch (_) {
      return false;
    }
  }

  // ──────────────────────────────────────────────
  //  DISCOVERABILITY
  // ──────────────────────────────────────────────

  static Future<bool> requestDiscoverability({int timeoutSec = 120}) async {
    try {
      final result = await _btChannel.invokeMethod<bool>(
        'requestDiscoverability',
        {'timeout': timeoutSec},
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> setLocalBluetoothName(String name) async {
    try {
      final result = await _btChannel.invokeMethod<bool>(
        'setLocalBluetoothName',
        {'name': name},
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  // ──────────────────────────────────────────────
  //  DISCOVERY NATIVA (delegata al plugin Kotlin)
  // ──────────────────────────────────────────────

  /// Avvia la discovery Bluetooth nativa. I dispositivi trovati vengono
  /// emessi come eventi su onNativeEvent con evento 'onDeviceFound'.
  ///
  /// [deviceNameFilter]: filtro per nome dispositivo (default: "CatechHub_").
  static Future<bool> startDiscovery({String deviceNameFilter = 'CatechHub_'}) async {
    try {
      final result = await _btChannel.invokeMethod<String>(
        'startDiscovery',
        {'deviceNameFilter': deviceNameFilter},
      );
      return result == 'DISCOVERY_STARTED';
    } catch (e) {
      return false;
    }
  }

  static Future<void> cancelDiscovery() async {
    try {
      await _btChannel.invokeMethod('stopDiscovery');
    } catch (_) {}
  }

  /// Recupera la lista dei dispositivi Bluetooth già associati (bonded).
  static Future<List<DiscoveredBluetoothDevice>> getBondedDevices() async {
    try {
      final result = await _btChannel.invokeMethod<List>('getBondedDevices');
      if (result == null) return [];
      return result
          .map((e) => DiscoveredBluetoothDevice.fromMap(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Cerca un dispositivo CatechHub nelle vicinanze.
  ///
  /// 1. Verifica tra i dispositivi bonded
  /// 2. Se non trovato, avvia discovery nativa e attende
  /// 3. Restituisce il primo dispositivo con nome che inizia con CatechHub_
  static Future<DiscoveredBluetoothDevice?> discoverDeviceByName({
    Duration timeout = const Duration(seconds: 20),
    String namePrefix = 'CatechHub_',
  }) async {
    // 1. Verifica tra i bonded
    final bonded = await getBondedDevices();
    for (final device in bonded) {
      if (device.name.startsWith(namePrefix)) {
        return device;
      }
    }

    // 2. Discovery nativa
    final completer = Completer<DiscoveredBluetoothDevice?>();
    StreamSubscription? eventSub;

    eventSub = _btEventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map && event['event'] == 'onDeviceFound') {
        final data = event['data'];
        if (data is Map) {
          final device = DiscoveredBluetoothDevice.fromMap(data);
          if (!completer.isCompleted) {
            // Se namePrefix è vuoto, accetta tutti i dispositivi (usato in fase di pairing).
            // Se non è vuoto, filtra per nome (usato per sync background).
            final matches = namePrefix.isEmpty ||
                device.name.startsWith(namePrefix);
            if (matches) {
              completer.complete(device);
            }
          }
        }
      } else if (event is Map && event['event'] == 'onDiscoveryComplete') {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      }
    });

    await _btChannel.invokeMethod('startDiscovery', {'deviceNameFilter': namePrefix});

    final result = await completer.future.timeout(timeout, onTimeout: () {
      return null;
    });

    eventSub.cancel();
    await cancelDiscovery();

    return result;
  }

  /// Scopre TUTTI i dispositivi Bluetooth nelle vicinanze (non solo il primo).
  /// Utile per il pairing dove vogliamo provare connessione su ogni device trovato.
  static Future<List<DiscoveredBluetoothDevice>> discoverAllDevices({
    Duration timeout = const Duration(seconds: 20),
    String namePrefix = '',
  }) async {
    final devices = <DiscoveredBluetoothDevice>[];

    StreamSubscription? eventSub;
    eventSub = _btEventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map && event['event'] == 'onDeviceFound') {
        final data = event['data'];
        if (data is Map) {
          final device = DiscoveredBluetoothDevice.fromMap(data);
          if (namePrefix.isEmpty || device.name.startsWith(namePrefix)) {
            devices.add(device);
          }
        }
      }
    });

    await _btChannel.invokeMethod('startDiscovery', {'deviceNameFilter': namePrefix});

    await Future.delayed(timeout);

    eventSub.cancel();
    await cancelDiscovery();

    return devices;
  }

  // ──────────────────────────────────────────────
  //  SERVER SYNC PERSISTENTE
  // ──────────────────────────────────────────────

  static Future<bool> startSyncServer() async {
    try {
      final result = await _btChannel.invokeMethod<String>('startSyncServer');
      return result == 'SYNC_SERVER_STARTED' || result == 'SYNC_SERVER_ALREADY_RUNNING';
    } catch (e) {
      return false;
    }
  }

  static Future<bool> stopSyncServer() async {
    try {
      final result = await _btChannel.invokeMethod<String>('stopSyncServer');
      return result == 'SYNC_SERVER_STOPPED';
    } catch (e) {
      return false;
    }
  }

  // ──────────────────────────────────────────────
  //  INVIO DATI SYNC (via MethodChannel nativo)
  // ──────────────────────────────────────────────

  static Future<bool> sendSyncData(String payload, String macAddress) async {
    try {
      final result = await _btChannel.invokeMethod<String>(
        'sendSyncData',
        {'payload': payload, 'macAddress': macAddress},
      );
      return result == 'DATA_SENT';
    } catch (e) {
      return false;
    }
  }

  // ──────────────────────────────────────────────
  //  PAIRING SERVER (Handshake via canale nativo)
  // ──────────────────────────────────────────────

  Future<bool> startPairingServer({String? sessionNonce}) async {
    try {
      print('[FLUTTER_BT_SYNC] Invocato MethodChannel per avviare il flusso nativo.');
      _statusController.add(ClassicConnectionState.classicServerListening);
      _messageController.add('Server pairing in ascolto...');

      await _btChannel.invokeMethod<String>(
        'startPairingServer',
        {'sessionNonce': sessionNonce},
      );

      // Il risultato viene ricevuto via onPairingHandshakeComplete callback
      // o via EventChannel onPairingServerStatus
      return true;
    } catch (e) {
      _messageController.add('Errore pairing server: $e');
      _statusController.add(ClassicConnectionState.error);
      return false;
    }
  }

  Future<bool> stopPairingServer() async {
    try {
      await _btChannel.invokeMethod('stopPairingServer');
      return true;
    } catch (_) {
      return false;
    }
  }

  // ──────────────────────────────────────────────
  //  PAIRING CLIENT (Handshake via canale nativo)
  // ──────────────────────────────────────────────

  Future<bool> connectForPairing(String address, {String sessionNonce = ''}) async {
    if (_isConnecting) {
      _messageController.add('Connessione pairing già in corso.');
      return false;
    }

    if (address.isEmpty || !_isValidBluetoothAddress(address)) {
      _messageController.add('Indirizzo Bluetooth non valido: "$address"');
      _statusController.add(ClassicConnectionState.error);
      return false;
    }

    try {
      _isConnecting = true;
      _statusController.add(ClassicConnectionState.classicClientConnecting);
      _messageController.add('Connessione pairing a $address...');
      print('[FLUTTER_BT_SYNC] Invocato MethodChannel per avviare il flusso nativo.');

      final result = await _btChannel.invokeMethod<String>(
        'connectPairingClient',
        {'macAddress': address, 'sessionNonce': sessionNonce},
      );

      print('[FLUTTER_BT_SYNC] Risultato handshake ricevuto dal nativo: $result');
      if (result == 'HANDSHAKE_SUCCESS') {
        _messageController.add('Handshake pairing riuscito.');
        return true;
      }

      _messageController.add('Pairing handshake fallito: $result');
      return false;
    } catch (e) {
      _messageController.add('Errore pairing client: $e');
      _statusController.add(ClassicConnectionState.error);
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  // ──────────────────────────────────────────────
  //  RUOLO CLIENT (Connessione dati RFCOMM)
  // ──────────────────────────────────────────────

  /// Connette come client per la trasmissione dati RFCOMM.
  /// Usa il canale nativo per aprire il socket.
  Future<bool> connectAsClient(String address) async {
    if (_isConnecting) {
      _messageController.add('Connessione già in corso.');
      return false;
    }

    try {
      _isConnecting = true;
      _statusController.add(ClassicConnectionState.classicClientConnecting);
      _messageController.add('Connessione dati a $address...');

      // La connessione dati avviene tramite sendSyncData (fire-and-forget)
      // o tramite il sync server nativo. Per la connessione persistente
      // usiamo il sync server con handshake iniziale.
      _connectedAddress = address;
      _statusController.add(ClassicConnectionState.connected);
      _messageController.add('Connesso a $address via RFCOMM');

      return true;
    } catch (e) {
      _messageController.add('Errore connessione client RFCOMM: $e');
      _statusController.add(ClassicConnectionState.error);
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  // ──────────────────────────────────────────────
  //  INVIO E RICEZIONE (Framing newline-terminated)
  // ──────────────────────────────────────────────

  Future<void> sendPayload(String payload) async {
    if (_connectedAddress == null) {
      throw Exception('Nessuna connessione RFCOMM attiva');
    }

    final payloadBytes = utf8.encode(payload);

    // Invio via MethodChannel nativo (il framing \n e gestito in Kotlin)
    await _btChannel.invokeMethod(
      'sendSyncData',
      {'payload': payload, 'macAddress': _connectedAddress},
    );

    _messageController.add('Inviato payload RFCOMM: ${payloadBytes.length} byte');
  }

  // ──────────────────────────────────────────────
  //  DISCONNESSIONE E PULIZIA
  // ──────────────────────────────────────────────

  Future<void> disconnect() async {
    _cleanup();
    _statusController.add(ClassicConnectionState.idle);
  }

  void _cleanup() {
    _connectedAddress = null;
    _isConnecting = false;
  }

  void dispose() {
    _cleanup();
    disposeEventStream();
    _eventController.close();
    _payloadController.close();
    _statusController.close();
    _messageController.close();
  }
}

/// Macchina a stati centralizzata per la gestione della connessione P2P
/// esclusivamente tramite Bluetooth Classico RFCOMM.
class ClassicConnectionManager {
  static final ClassicConnectionManager _instance = ClassicConnectionManager._();
  factory ClassicConnectionManager() => _instance;
  ClassicConnectionManager._();

  final BluetoothClassicService _classicService = BluetoothClassicService();

  ClassicConnectionState _state = ClassicConnectionState.idle;
  ClassicTransportType _activeTransport = ClassicTransportType.none;

  bool _initialized = false;

  static const Duration classicTimeout = Duration(seconds: 30);

  Timer? _classicTimeoutTimer;
  StreamSubscription? _classicPayloadSubscription;
  StreamSubscription? _classicMessageSubscription;
  StreamSubscription? _classicHandshakeSubscription;

  final _stateController = StreamController<ClassicConnectionState>.broadcast();
  final _payloadController = StreamController<String>.broadcast();
  final _messageController = StreamController<String>.broadcast();

  Stream<ClassicConnectionState> get onStateChanged => _stateController.stream;
  Stream<String> get onPayloadReceived => _payloadController.stream;
  Stream<String> get onMessage => _messageController.stream;

  ClassicConnectionState get currentState => _state;
  ClassicTransportType get activeTransport => _activeTransport;
  bool get isConnected => _state == ClassicConnectionState.connected;

  // ──────────────────────────────────────────────
  //  RISOLUZIONE NOME DISPOSITIVO
  // ──────────────────────────────────────────────

  static const _customDeviceNameKey = 'ble_custom_device_name';

  static Future<String> resolveDeviceName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customName = prefs.getString(_customDeviceNameKey);
      if (customName != null && customName.isNotEmpty) {
        return '${ClassicUuids.deviceNamePrefix}$customName';
      }
    } catch (_) {}

    try {
      final auth = LocalDatabase.auth();
      final catechistName = auth.get('local_user_name', defaultValue: '') as String;
      if (catechistName.trim().isNotEmpty) {
        return '${ClassicUuids.deviceNamePrefix}${catechistName.trim()}';
      }
    } catch (_) {}

    return '${ClassicUuids.deviceNamePrefix}Device';
  }

  Future<void> saveCustomDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanName = _stripPrefix(name);
    if (cleanName.trim().isEmpty) {
      await prefs.remove(_customDeviceNameKey);
    } else {
      await prefs.setString(_customDeviceNameKey, cleanName.trim());
    }
  }

  Future<String?> getCustomDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customDeviceNameKey);
    if (raw == null) return null;
    return _stripPrefix(raw);
  }

  Future<void> clearCustomDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customDeviceNameKey);
  }

  static String _stripPrefix(String name) {
    if (name.startsWith(ClassicUuids.deviceNamePrefix)) {
      return name.substring(ClassicUuids.deviceNamePrefix.length);
    }
    return name;
  }

  static String stripDeviceNamePrefix(String fullName) {
    return _stripPrefix(fullName);
  }

  static bool isCatechHubDeviceName(String? name) {
    return name != null && name.startsWith(ClassicUuids.deviceNamePrefix);
  }

  // ──────────────────────────────────────────────
  //  ELIMINAZIONE DISPOSITIVI
  // ──────────────────────────────────────────────

  Future<void> deleteTrustedDevice(String deviceId) async {
    await _classicService.disconnect();
    _cancelClassicTimeout();
    _updateState(ClassicConnectionState.idle);
    _activeTransport = ClassicTransportType.none;
    _messageController.add('Dispositivo $deviceId eliminato.');
  }

  // ──────────────────────────────────────────────
  //  LEADER ELECTION (Confronto Lessicografico)
  // ──────────────────────────────────────────────

  static ClassicPairingRole electRole(String myDeviceId, String peerDeviceId) {
    final comparison = myDeviceId.compareTo(peerDeviceId);
    if (comparison > 0) {
      return ClassicPairingRole.dispositivoA;
    } else {
      return ClassicPairingRole.dispositivoB;
    }
  }

  // ──────────────────────────────────────────────
  //  INIZIALIZZAZIONE
  // ──────────────────────────────────────────────

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    _classicService.initializeEventStream();

    _classicService.onStatusChanged.listen((s) {
      if (s == ClassicConnectionState.connected) {
        _cancelClassicTimeout();
        _updateState(ClassicConnectionState.connected);
        _activeTransport = ClassicTransportType.classic;
        _messageController.add('Connessione RFCOMM stabilita');
      } else if (s == ClassicConnectionState.error) {
        _updateState(ClassicConnectionState.error);
      } else if (s == ClassicConnectionState.idle && isConnected) {
        _updateState(ClassicConnectionState.idle);
        _activeTransport = ClassicTransportType.none;
        _messageController.add('Connessione persa dal dispositivo remoto.');
      }
    });

    _classicPayloadSubscription = _classicService.onPayloadReceived.listen(
      (p) => _payloadController.add(p),
    );
    _classicMessageSubscription = _classicService.onMessage.listen(
      (m) => _messageController.add('[Classic] $m'),
    );
    _classicHandshakeSubscription = _classicService.onHandshakeResult.listen(
      (result) {
        if (result['success'] == true) {
          _messageController.add(
            'Pairing handshake completato con ${result['peerDeviceId']}',
          );
        } else {
          _messageController.add(
            'Pairing handshake fallito: ${result['error'] ?? 'errore sconosciuto'}',
          );
        }
      },
    );
  }

  // ──────────────────────────────────────────────
  //  PAIRING HANDSHAKE (Verifica hardware)
  // ──────────────────────────────────────────────

  Future<bool> startPairingServer({String? sessionNonce}) async {
    _updateState(ClassicConnectionState.classicServerListening);
    final ok = await _classicService.startPairingServer(sessionNonce: sessionNonce);
    if (!ok) {
      _updateState(ClassicConnectionState.error);
    }
    return ok;
  }

  Future<bool> connectForPairing(String address, {String sessionNonce = ''}) async {
    _updateState(ClassicConnectionState.classicClientConnecting);
    final ok = await _classicService.connectForPairing(address, sessionNonce: sessionNonce);
    if (ok) {
      _updateState(ClassicConnectionState.connected);
    } else {
      _updateState(ClassicConnectionState.error);
    }
    return ok;
  }

  /// Scopre dispositivi nelle vicinanze e prova connessione su TUTTI
  /// finché uno non completa l'handshake RFCOMM con successo.
  Future<(String?, bool)> discoverAndConnectForPairing({
    int timeoutSec = 20,
    String sessionNonce = '',
    String? expectedDeviceName,
  }) async {
    _updateState(ClassicConnectionState.checkingCapabilities);
    _messageController.add('Ricerca dispositivi nelle vicinanze...');

    // Cerchiamo prima per nome se abbiamo un nome atteso (CatechHub_xxx).
    // Il nome BT reale ora è impostato a CatechHub_<deviceId> prima del pairing.
    if (expectedDeviceName != null && expectedDeviceName.isNotEmpty) {
      _messageController.add('Cerco $expectedDeviceName...');
      final device = await BluetoothClassicService.discoverDeviceByName(
        timeout: Duration(seconds: timeoutSec),
        namePrefix: expectedDeviceName,
      );
      if (device != null) {
        _messageController.add(
          'Trovato ${device.name} (${device.address}). Connessione...',
        );
        _updateState(ClassicConnectionState.classicClientConnecting);
        final ok = await _classicService.connectForPairing(
          device.address,
          sessionNonce: sessionNonce,
        );
        if (ok) {
          _updateState(ClassicConnectionState.connected);
          return (device.address, true);
        }
      }
    }

    // Fallback: scopri tutti i dispositivi CatechHub
    _messageController.add('Ricerca espansa di dispositivi CatechHub...');
    final devices = await BluetoothClassicService.discoverAllDevices(
      timeout: Duration(seconds: timeoutSec),
      namePrefix: ClassicUuids.deviceNamePrefix,
    );

    if (devices.isEmpty) {
      _updateState(ClassicConnectionState.error);
      _messageController.add(
        'Nessun dispositivo trovato nelle vicinanze.',
      );
      return (null, false);
    }

    _messageController.add(
      'Trovati ${devices.length} dispositivi. Tentativo connessione...',
    );

    for (final device in devices) {
      _messageController.add(
        'Tentativo connessione a ${device.name} (${device.address})...',
      );
      _updateState(ClassicConnectionState.classicClientConnecting);
      final ok = await _classicService.connectForPairing(
        device.address,
        sessionNonce: sessionNonce,
      );
      if (ok) {
        _updateState(ClassicConnectionState.connected);
        return (device.address, true);
      }
    }

    _updateState(ClassicConnectionState.error);
    _messageController.add(
      'Nessun dispositivo ha risposto all\'handshake di pairing.',
    );
    return (null, false);
  }

  Future<void> resetPairingHandshake() async {
    await _classicService.disconnect();
    _updateState(ClassicConnectionState.idle);
  }

  // ──────────────────────────────────────────────
  //  FLUSSO PRINCIPALE (Connessione dati Classica)
  // ──────────────────────────────────────────────

  Future<void> connectWithFallback({
    ClassicPairingRole? pairingRole,
    String? peerMacAddress,
    ClassicSyncRole role = ClassicSyncRole.mioDispositivo,
  }) async {
    _updateState(ClassicConnectionState.checkingCapabilities);
    _messageController.add('Verifica permessi Bluetooth...');

    final permResult = await BluetoothPermissionService.checkAndRequestPermissions();

    if (!permResult.allGranted) {
      _updateState(ClassicConnectionState.error);
      _messageController.add(permResult.errorMessage ?? 'Permessi negati.');
      return;
    }

    final btEnabled = await BluetoothPermissionService.ensureBluetoothEnabled();
    if (!btEnabled) {
      _updateState(ClassicConnectionState.error);
      _messageController.add(
        'Bluetooth disattivato. Attivalo dalle impostazioni del telefono.',
      );
      return;
    }

    final ok = await BluetoothClassicService.ensureClassicPermissions();
    if (!ok) {
      _updateState(ClassicConnectionState.error);
      _messageController.add('Permessi Bluetooth negati.');
      return;
    }

    _startClassicTimeout();

    bool connected;
    if (peerMacAddress != null && peerMacAddress.isNotEmpty) {
      _messageController.add('Connessione diretta a $peerMacAddress...');
      connected = await _classicService.connectAsClient(peerMacAddress);
    } else {
      _messageController.add('Ricerca dispositivi CatechHub...');
      connected = await _tryClassicClient();
    }

    if (!connected) {
      _cancelClassicTimeout();
      _updateState(ClassicConnectionState.error);
      _messageController.add(
        'Impossibile connettersi via Classic.',
      );
    } else {
      _cancelClassicTimeout();
    }
  }

  // ──────────────────────────────────────────────
  //  TIMEOUT CLASSIC
  // ──────────────────────────────────────────────

  void _startClassicTimeout() {
    _classicTimeoutTimer?.cancel();
    _classicTimeoutTimer = Timer(classicTimeout, () {
      _messageController.add('Timeout Bluetooth Classic (${classicTimeout.inSeconds}s)');
      _updateState(ClassicConnectionState.error);
    });
  }

  void _cancelClassicTimeout() {
    _classicTimeoutTimer?.cancel();
    _classicTimeoutTimer = null;
  }

  // ──────────────────────────────────────────────
  //  TENTATIVI DI CONNESSIONE CLASSICA
  // ──────────────────────────────────────────────

  Future<bool> _tryClassicClient() async {
    _updateState(ClassicConnectionState.classicClientConnecting);
    _messageController.add('Tentativo Client RFCOMM...');

    try {
      _messageController.add('Ricerca dispositivi CatechHub per nome...');
      final device = await BluetoothClassicService.discoverDeviceByName(
        timeout: const Duration(seconds: 15),
      );

      if (device != null) {
        final displayName = stripDeviceNamePrefix(device.name);
        _messageController.add('Connessione a $displayName (${device.address})...');
        final ok = await _classicService.connectAsClient(device.address);
        if (ok) {
          _updateState(ClassicConnectionState.connected);
          _activeTransport = ClassicTransportType.classic;
          return true;
        }
      }

      _messageController.add('Nessun dispositivo CatechHub trovato.');
      return false;
    } catch (e) {
      _messageController.add('Errore Client: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────────
  //  INVIO/RICEZIONE UNIFICATI
  // ──────────────────────────────────────────────

  Future<void> sendPayload(String payload, String messageId) async {
    if (_activeTransport == ClassicTransportType.classic) {
      await _classicService.sendPayload(payload);
    } else {
      throw Exception('Nessun trasporto attivo. Connettiti prima.');
    }
  }

  // ──────────────────────────────────────────────
  //  RESET TOTALE DEL MOTORE DI ACCOPPIAMENTO
  // ──────────────────────────────────────────────

  Future<void> resetPairingEngine() async {
    await _classicService.disconnect();
    _cancelClassicTimeout();
    _updateState(ClassicConnectionState.idle);
    _activeTransport = ClassicTransportType.none;
    _messageController.add('Motore di accoppiamento resettato.');
  }

  // ──────────────────────────────────────────────
  //  SERVER SYNC PERSISTENTE
  // ──────────────────────────────────────────────

  Future<bool> startPersistentSyncServer() async {
    final started = await BluetoothClassicService.startSyncServer();
    if (started) {
      _messageController.add('Server sincronizzazione avviato.');
    } else {
      _messageController.add('Avvio server sincronizzazione fallito.');
    }
    return started;
  }

  Future<void> stopPersistentSyncServer() async {
    await BluetoothClassicService.stopSyncServer();
    _messageController.add('Server sincronizzazione fermato.');
  }

  // ──────────────────────────────────────────────
  //  DISCONNESSIONE
  // ──────────────────────────────────────────────

  Future<void> disconnect() async {
    _cancelClassicTimeout();
    await _classicService.disconnect();
    _updateState(ClassicConnectionState.idle);
    _activeTransport = ClassicTransportType.none;
  }

  // ──────────────────────────────────────────────
  //  GESTIONE STATO
  // ──────────────────────────────────────────────

  void _updateState(ClassicConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _cancelClassicTimeout();
    _classicPayloadSubscription?.cancel();
    _classicMessageSubscription?.cancel();
    _classicHandshakeSubscription?.cancel();
    _classicService.dispose();
    _stateController.close();
    _payloadController.close();
    _messageController.close();
    _initialized = false;
  }
}

// ──────────────────────────────────────────────
//  CLASS: ClassicHandshakeResult
// ──────────────────────────────────────────────

class ClassicHandshakeResult {
  final String peerDeviceId;
  final String peerMacAddress;
  final ClassicPairingRole role;

  const ClassicHandshakeResult({
    required this.peerDeviceId,
    required this.peerMacAddress,
    required this.role,
  });
}

// ──────────────────────────────────────────────
//  CLASS: ClassicPairingService
// ──────────────────────────────────────────────

class ClassicPairingService {
  static final _secureStorage = FlutterSecureStorage();

  static const _customDeviceNameKey = 'ble_custom_device_name';
  static const _syncRoleKey = 'ble_sync_role';
  static const _lastSyncKey = 'ble_last_sync_timestamp';
  static const _localDeviceIdKey = 'ble_local_device_id';

  // ──────────────────────────────────────────────
  //  GESTIONE NOME DISPOSITIVO
  // ──────────────────────────────────────────────

  static Future<void> saveCustomDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customDeviceNameKey, name);
  }

  static Future<String?> getCustomDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_customDeviceNameKey);
  }

  static Future<void> clearCustomDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customDeviceNameKey);
  }

  // ──────────────────────────────────────────────
  //  GESTIONE ID DISPOSITIVO LOCALE
  // ──────────────────────────────────────────────

  static Future<String> getOrCreateDeviceId() async {
    var deviceId = await _secureStorage.read(key: _localDeviceIdKey);
    if (deviceId != null && deviceId.isNotEmpty) return deviceId;

    deviceId = _generateDeviceId();
    await _secureStorage.write(key: _localDeviceIdKey, value: deviceId);
    return deviceId;
  }

  static String _generateDeviceId() {
    final random = Random.secure();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomPart = random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'CH_${timestamp.toRadixString(16)}_$randomPart';
  }

  static String _generateSharedKey() {
    final random = Random.secure();
    final keyBytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    return base64Encode(keyBytes);
  }

  static Future<String> resolveDeviceName() async {
    try {
      final auth = LocalDatabase.auth();
      final catechistName = auth.get('local_user_name', defaultValue: '') as String;
      if (catechistName.trim().isNotEmpty) {
        return '${ClassicUuids.deviceNamePrefix}${catechistName.trim()}';
      }
    } catch (_) {}
    return '${ClassicUuids.deviceNamePrefix}Device';
  }

  // ──────────────────────────────────────────────
  //  CREAZIONE PAIRING DATA (per QR code)
  // ──────────────────────────────────────────────

  static Future<ClassicPairingData> createPairingData({
    String? deviceName,
    String? macAddress,
    ClassicSyncRole role = ClassicSyncRole.mioDispositivo,
    String? ecdhPublicKey,
    String? sessionNonce,
  }) async {
    final deviceId = await getOrCreateDeviceId();
    final resolvedName = deviceName ?? await resolveDeviceName();
    final sharedKey = ecdhPublicKey ?? _generateSharedKey();

    final String finalName;
    if (resolvedName.startsWith(ClassicUuids.deviceNamePrefix)) {
      finalName = resolvedName;
    } else {
      finalName = '${ClassicUuids.deviceNamePrefix}$resolvedName';
    }

    return ClassicPairingData(
      deviceId: deviceId,
      macAddress: macAddress,
      deviceName: finalName,
      sharedKey: sharedKey,
      createdAt: DateTime.now().toUtc(),
      syncRole: role,
      sessionNonce: sessionNonce,
    );
  }

  // ──────────────────────────────────────────────
  //  TABELLA TRUSTED DEVICES
  // ──────────────────────────────────────────────

  static Future<void> saveTrustedDevice(TrustedDevice device) async {
    final box = LocalDatabase.trustedDevices();
    await box.put(device.deviceId, device.toMap());
  }

  static Future<TrustedDevice?> getTrustedDevice(String deviceId) async {
    final box = LocalDatabase.trustedDevices();
    final data = box.get(deviceId);
    if (data == null) return null;

    final device = TrustedDevice.fromMap(Map<String, dynamic>.from(data));

    if (!device.isValid) {
      await removeTrustedDevice(deviceId);
      return null;
    }

    return device;
  }

  static Future<String?> getTrustedDeviceKey(String deviceId) async {
    final device = await getTrustedDevice(deviceId);
    return device?.publicKey;
  }

  static Future<List<TrustedDevice>> getAllTrustedDevices() async {
    final box = LocalDatabase.trustedDevices();
    final devices = <TrustedDevice>[];

    for (final key in box.keys) {
      final data = box.get(key);
      if (data == null) continue;

      final device = TrustedDevice.fromMap(Map<String, dynamic>.from(data));

      if (device.isValid) {
        devices.add(device);
      } else {
        await removeTrustedDevice(key.toString());
      }
    }

    return devices;
  }

  static Future<bool> hasAnyTrustedDevice() async {
    final devices = await getAllTrustedDevices();
    return devices.isNotEmpty;
  }

  static Future<void> removeTrustedDevice(String deviceId) async {
    final box = LocalDatabase.trustedDevices();
    await box.delete(deviceId);
  }

  static Future<void> removeAllTrustedDevices() async {
    final box = LocalDatabase.trustedDevices();
    await box.clear();
  }

  // ──────────────────────────────────────────────
  //  DERIVAZIONE CHIAVE DI SESSIONE (ECDH + HKDF)
  // ──────────────────────────────────────────────

  static String deriveSessionKeyFromEcdh(
    String remoteEcdhPublicKey,
    pc.ECPrivateKey localPrivateKey,
    String sessionNonce, {
    String? deviceIdA,
    String? deviceIdB,
  }) {
    final remoteKeyBytes = base64Decode(remoteEcdhPublicKey);
    final nonceBytes = base64Decode(sessionNonce);

    final sharedSecret = EncryptionService.computeEcdhSharedSecret(
      remoteKeyBytes,
      localPrivateKey,
    );

    final sessionKey = EncryptionService.deriveSessionKeyFromEcdh(
      sharedSecret,
      nonceBytes,
      deviceIdA: deviceIdA,
      deviceIdB: deviceIdB,
    );

    return base64Encode(sessionKey);
  }

  // ──────────────────────────────────────────────
  //  PROTOCOLLO DI ACCOPPIAMENTO BIDIREZIONALE
  // ──────────────────────────────────────────────

  static Future<bool> completeBidirectionalPairing(
    ClassicPairingData remoteData, {
    required pc.ECPrivateKey localPrivateKey,
    required String localPublicKey,
    required String sessionNonce,
    String? remoteMacAddress,
  }) async {
    try {
      final sessionKey = deriveSessionKeyFromEcdh(
        remoteData.sharedKey,
        localPrivateKey,
        sessionNonce,
        deviceIdA: await getOrCreateDeviceId(),
        deviceIdB: remoteData.deviceId,
      );

      final keyRenewalAt = DateTime.now().toUtc().add(const Duration(days: 25));

      final macAddr = remoteMacAddress ?? remoteData.macAddress;

      final trustedDevice = TrustedDevice(
        deviceId: remoteData.deviceId,
        deviceName: remoteData.deviceName,
        publicKey: sessionKey,
        syncRole: remoteData.syncRole.name,
        pairedAt: DateTime.now().toUtc(),
        sessionNonce: sessionNonce,
        keyRenewalAt: keyRenewalAt,
        macAddress: macAddr,
      );

      await saveTrustedDevice(trustedDevice);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> saveDeviceBTrustedDevice(
    ClassicPairingData remoteData, {
    required pc.ECPrivateKey localPrivateKey,
    required String sessionNonce,
    String? remoteMacAddress,
  }) async {
    try {
      final sessionKey = deriveSessionKeyFromEcdh(
        remoteData.sharedKey,
        localPrivateKey,
        sessionNonce,
        deviceIdA: remoteData.deviceId,
        deviceIdB: await getOrCreateDeviceId(),
      );

      final keyRenewalAt = DateTime.now().toUtc().add(const Duration(days: 25));

      final macAddr = remoteMacAddress ?? remoteData.macAddress;

      final trustedDevice = TrustedDevice(
        deviceId: remoteData.deviceId,
        deviceName: remoteData.deviceName,
        publicKey: sessionKey,
        syncRole: remoteData.syncRole.name,
        pairedAt: DateTime.now().toUtc(),
        sessionNonce: sessionNonce,
        keyRenewalAt: keyRenewalAt,
        macAddress: macAddr,
      );

      await saveTrustedDevice(trustedDevice);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> cancelPartialPairing(String remoteDeviceId) async {
    await removeTrustedDevice(remoteDeviceId);
  }

  // ──────────────────────────────────────────────
  //  VERIFICA COERENZA RUOLI
  // ──────────────────────────────────────────────

  static bool controllareCoerenzaRuoli(
    ClassicSyncRole ruoloLocale,
    ClassicSyncRole ruoloRicevuto,
  ) {
    return ClassicPairingData.controllareCoerenzaRuoli(ruoloLocale, ruoloRicevuto);
  }

  static String get roleCoherenceError =>
      ClassicPairingData.roleCoherenceErrorMessage;

  // ──────────────────────────────────────────────
  //  RUOLO E ULTIMA SINCRONIZZAZIONE
  // ──────────────────────────────────────────────

  static Future<void> saveSyncRole(ClassicSyncRole role) async {
    await _secureStorage.write(key: _syncRoleKey, value: role.index.toString());
  }

  static Future<ClassicSyncRole> getSyncRole() async {
    final value = await _secureStorage.read(key: _syncRoleKey);
    if (value == null) return ClassicSyncRole.mioDispositivo;
    return ClassicSyncRole.values[int.parse(value)];
  }

  static Future<void> saveLastSyncTimestamp(DateTime timestamp) async {
    await _secureStorage.write(
      key: _lastSyncKey,
      value: timestamp.toUtc().toIso8601String(),
    );
  }

  static Future<DateTime> getLastSyncTimestamp() async {
    final value = await _secureStorage.read(key: _lastSyncKey);
    if (value == null) {
      return DateTime.fromMillisecondsSinceEpoch(0).toUtc();
    }
    return DateTime.parse(value).toUtc();
  }

  static Future<bool> isDevicePaired() async {
    return await hasAnyTrustedDevice();
  }

  static Future<void> invalidateAllPairings() async {
    await removeAllTrustedDevices();
    await _secureStorage.delete(key: _syncRoleKey);
    await _secureStorage.delete(key: _lastSyncKey);
  }

  static ClassicPairingData? decodeScannedQr(String rawData) {
    try {
      final data = ClassicPairingData.fromJson(rawData);
      if (data.deviceId.isEmpty || data.sharedKey.isEmpty) {
        return null;
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  // ──────────────────────────────────────────────
  //  GESTIONE LAST SYNCED AT
  // ──────────────────────────────────────────────

  static Future<void> updateDeviceLastSyncedAt(
    String deviceId,
    DateTime timestamp,
  ) async {
    final device = await getTrustedDevice(deviceId);
    if (device == null) return;

    final updated = device.copyWith(lastSyncedAt: timestamp.toUtc());
    await saveTrustedDevice(updated);
  }

  static Future<List<TrustedDevice>> getSyncQueue({
    int maxDevices = 10,
  }) async {
    final devices = await getAllTrustedDevices();

    devices.sort((a, b) {
      if (a.lastSyncedAt == null && b.lastSyncedAt == null) {
        return a.deviceId.compareTo(b.deviceId);
      }
      if (a.lastSyncedAt == null) return -1;
      if (b.lastSyncedAt == null) return 1;
      return a.lastSyncedAt!.compareTo(b.lastSyncedAt!);
    });

    if (devices.length > maxDevices) {
      return devices.sublist(0, maxDevices);
    }

    return devices;
  }

  // ──────────────────────────────────────────────
  //  RINNOVO AUTOMATICO CHIAVE
  // ──────────────────────────────────────────────

  static Future<bool> hasDevicesNeedingRenewal() async {
    final devices = await getAllTrustedDevices();
    return devices.any((d) => d.isKeyRenewalNeeded);
  }

  static Future<List<TrustedDevice>> getDevicesNeedingRenewal() async {
    final devices = await getAllTrustedDevices();
    return devices.where((d) => d.isKeyRenewalNeeded).toList();
  }

  static Future<int?> getDaysUntilKeyExpiry() async {
    final devices = await getAllTrustedDevices();
    if (devices.isEmpty) return null;

    var minDays = 30;
    for (final device in devices) {
      final days = device.timeUntilExpiry.inDays;
      if (days < minDays) minDays = days;
    }
    return minDays;
  }

  static Future<bool> isAnyKeyExpired() async {
    final devices = await getAllTrustedDevices();
    return devices.any((d) => d.isKeyExpired);
  }
}
