import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:cryptography/cryptography.dart';

import '../../../core/services/bluetooth_permission_service.dart';
import 'p2p_security_service.dart';
import 'hive_sync_engine.dart';

enum P2PSyncRole { mioDispositivo, altroCatechista, responsabile }

enum P2PSyncStatus {
  idle,
  pairing,
  discovering,
  advertising,
  handshakeSent,
  handshakeReceived,
  pairingVerification,
  sessionEstablished,
  syncing,
  completed,
  error,
}

class P2PSyncState {
  final P2PSyncStatus status;
  final P2PSyncRole role;
  final bool isPairingMode;
  final bool isBackgroundSyncActive;
  final String? errorMessage;
  final String? connectedDeviceId;
  final String? connectedDeviceName;
  final String? connectedFingerprint;
  final DateTime? lastSyncAt;
  final int sentRecords;
  final int receivedRecords;
  final bool awaitingConfirmation;
  final String? pendingConfirmationDeviceName;
  final String? pendingConfirmationDeviceId;
  final bool isSessionEncrypted;
  final int nearbyAssociationsCount;
  final bool isDataUpToDate;
  final String? pairingCode;
  final String? remotePairingCode;
  final String? remoteDeviceFingerprint;

  const P2PSyncState({
    this.status = P2PSyncStatus.idle,
    this.role = P2PSyncRole.mioDispositivo,
    this.isPairingMode = false,
    this.isBackgroundSyncActive = false,
    this.errorMessage,
    this.connectedDeviceId,
    this.connectedDeviceName,
    this.connectedFingerprint,
    this.lastSyncAt,
    this.sentRecords = 0,
    this.receivedRecords = 0,
    this.awaitingConfirmation = false,
    this.pendingConfirmationDeviceName,
    this.pendingConfirmationDeviceId,
    this.isSessionEncrypted = false,
    this.nearbyAssociationsCount = 0,
    this.isDataUpToDate = false,
    this.pairingCode,
    this.remotePairingCode,
    this.remoteDeviceFingerprint,
  });

  P2PSyncState copyWith({
    P2PSyncStatus? status,
    P2PSyncRole? role,
    bool? isPairingMode,
    bool? isBackgroundSyncActive,
    String? errorMessage,
    String? connectedDeviceId,
    String? connectedDeviceName,
    String? connectedFingerprint,
    DateTime? lastSyncAt,
    int? sentRecords,
    int? receivedRecords,
    bool? awaitingConfirmation,
    String? pendingConfirmationDeviceName,
    String? pendingConfirmationDeviceId,
    bool? isSessionEncrypted,
    int? nearbyAssociationsCount,
    bool? isDataUpToDate,
    String? pairingCode,
    String? remotePairingCode,
    String? remoteDeviceFingerprint,
    bool clearError = false,
  }) {
    return P2PSyncState(
      status: status ?? this.status,
      role: role ?? this.role,
      isPairingMode: isPairingMode ?? this.isPairingMode,
      isBackgroundSyncActive:
          isBackgroundSyncActive ?? this.isBackgroundSyncActive,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      connectedDeviceId: connectedDeviceId ?? this.connectedDeviceId,
      connectedDeviceName: connectedDeviceName ?? this.connectedDeviceName,
      connectedFingerprint:
          connectedFingerprint ?? this.connectedFingerprint,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      sentRecords: sentRecords ?? this.sentRecords,
      receivedRecords: receivedRecords ?? this.receivedRecords,
      awaitingConfirmation:
          awaitingConfirmation ?? this.awaitingConfirmation,
      pendingConfirmationDeviceName:
          pendingConfirmationDeviceName ?? this.pendingConfirmationDeviceName,
      pendingConfirmationDeviceId:
          pendingConfirmationDeviceId ?? this.pendingConfirmationDeviceId,
      isSessionEncrypted: isSessionEncrypted ?? this.isSessionEncrypted,
      nearbyAssociationsCount:
          nearbyAssociationsCount ?? this.nearbyAssociationsCount,
      isDataUpToDate: isDataUpToDate ?? this.isDataUpToDate,
      pairingCode: pairingCode ?? this.pairingCode,
      remotePairingCode: remotePairingCode ?? this.remotePairingCode,
      remoteDeviceFingerprint:
          remoteDeviceFingerprint ?? this.remoteDeviceFingerprint,
    );
  }
}

class P2PSyncService {
  static final P2PSyncService _instance = P2PSyncService._();
  factory P2PSyncService() => _instance;
  P2PSyncService._();

  // CRITICO: Strategy.P2P_CLUSTER impone comunicazione esclusivamente
  // via WiFi Direct o Bluetooth (P2P assoluto). NESSUN dato transita
  // mai via internet, router, modem o altri dispositivi di rete.
  // L'API Nearby Connections di Google utilizza esclusivamente
  // connessioni P2P quando si usa questa strategia.

  final Nearby _nearby = Nearby();
  final P2PSecurityService _security = P2PSecurityService();

  final _stateController = StreamController<P2PSyncState>.broadcast();
  final _syncDataController =
      StreamController<Map<String, dynamic>>.broadcast();

  final List<SyncLogEntry> _syncLogs = [];
  static const int _maxLogEntries = 500;

  List<SyncLogEntry> get syncLogs => List.unmodifiable(_syncLogs);

  void addLog(String level, String message) {
    _syncLogs.add(SyncLogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
    ));
    if (_syncLogs.length > _maxLogEntries) {
      _syncLogs.removeAt(0);
    }
  }

  Stream<P2PSyncState> get onStateChanged => _stateController.stream;
  Stream<Map<String, dynamic>> get onSyncData => _syncDataController.stream;

  P2PSyncState _state = const P2PSyncState();
  P2PSyncState get currentState => _state;

  Timer? _pairingTimeoutTimer;
  Timer? _periodicSyncTimer;
  bool _initialized = false;
  bool _isSyncing = false;
  String? _pendingEndpointId;

  final Map<String, int> _endpointSyncPhase = {};
  static const int _syncPhaseIdle = 0;
  static const int _syncPhaseSentIndex = 1;
  static const int _syncPhaseSendDone = 2;
  static const int _syncPhaseReceiveDone = 3;
  static const int _syncPhaseComplete = 4;

  P2PIdentity? _pendingHandshakeIdentity;
  P2PSyncRole? _pendingHandshakeRemoteRole;

  Completer<void>? _pairingCompleter;

  final Map<String, SecretKeyData> _endpointSessionKeys = {};

  bool _continuousModeActive = false;
  final Set<String> _connectedEndpoints = {};
  final Set<String> _nearbyDiscoveredDevices = {};
  final Map<String, String> _nearbyEndpointToDevice = {};
  final Set<String> _sessionConfirmedDevices = {};
  bool _restartingEndpoints = false;
  StreamSubscription<BoxEvent>? _hiveBoxesSub;

  static const Duration _pairingTimeout = Duration(seconds: 120);
  static const Duration _reconnectDelay = Duration(seconds: 5);
  static const Duration _periodicSyncInterval = Duration(seconds: 60);
  static const String _serviceId = 'ch.catechhub.app';
  static const String _syncPrefix = 'CH_';

  void _emitState() => _stateController.add(_state);

  void _updateState(P2PSyncState newState) {
    _state = newState;
    _emitState();
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _security.refreshIdentityName();

    final hasAssociations = await _security.hasValidAssociation();
    if (hasAssociations) {
      _startContinuousMode();
    }
  }

  Future<void> _startContinuousMode() async {
    if (_continuousModeActive) return;
    _continuousModeActive = true;

    final permResult =
        await BluetoothPermissionService.checkAndRequestPermissions();
    if (!permResult.allGranted) return;

    _startAdvertising();
    _startDiscovery();
    _watchLocalChanges();
    _scheduleReconnectCycle();
    _startPeriodicSync();

    _updateState(_state.copyWith(
      isBackgroundSyncActive: true,
      clearError: true,
    ));
  }

  void _stopContinuousMode() {
    _continuousModeActive = false;
    _hiveBoxesSub?.cancel();
    _hiveBoxesSub = null;
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _nearbyDiscoveredDevices.clear();
    _nearbyEndpointToDevice.clear();
    _endpointSyncPhase.clear();
    _endpointSessionKeys.clear();
    _isSyncing = false;
    try {
      _nearby.stopAdvertising();
      _nearby.stopDiscovery();
    } catch (_) {}
  }

  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(_periodicSyncInterval, (_) {
      _performPeriodicSync();
    });
  }

  Future<void> _performPeriodicSync() async {
    if (_connectedEndpoints.isEmpty) return;

    for (final entry in _endpointSyncPhase.entries.toList()) {
      if (entry.value == _syncPhaseSentIndex) {
        _endpointSyncPhase.remove(entry.key);
        _isSyncing = false;
        addLog('WARN', 'Sync timeout per ${entry.key}, ripristino');
      }
    }

    if (_isSyncing) return;

    final endpoints = _connectedEndpoints.toList();
    if (endpoints.isNotEmpty) {
      await _performBidirectionalSync(endpoints.first);
    }

    _updateState(_state.copyWith(
      isDataUpToDate: _state.lastSyncAt != null &&
          DateTime.now().difference(_state.lastSyncAt!).inSeconds < 60,
    ));
  }

  Future<void> _startAdvertising() async {
    if (!_continuousModeActive) return;
    try {
      final identity = await _security.getLocalIdentity();
      await _nearby.startAdvertising(
        '$_syncPrefix${identity.deviceId}',
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
    } catch (_) {
      Future.delayed(const Duration(seconds: 3), _startAdvertising);
    }
  }

  Future<void> _startDiscovery() async {
    if (!_continuousModeActive) return;
    try {
      await _nearby.startDiscovery(
        _syncPrefix,
        Strategy.P2P_CLUSTER,
        onEndpointFound: (endpointId, name, serviceId) {
          if (!name.startsWith(_syncPrefix)) return;
          final deviceId = _extractDeviceId(name);
          if (deviceId == null) return;

          _nearbyEndpointToDevice[endpointId] = deviceId;
          _nearbyDiscoveredDevices.add(deviceId);
          _updateNearbyCount();

          Future(() async {
            if (_connectedEndpoints.contains(endpointId)) return;
            if (_endpointConnIdMap.containsValue(deviceId)) return;

            final assoc = await _security.getAssociation(deviceId);
            if (assoc != null && assoc.isValid) {
              await _nearby.requestConnection(
                '$_syncPrefix${assoc.deviceId}',
                endpointId,
                onConnectionInitiated: _onConnectionInitiated,
                onConnectionResult: _onConnectionResult,
                onDisconnected: _onDisconnected,
              );
            }
          });
        },
        onEndpointLost: (endpointId) {
          final deviceId = _nearbyEndpointToDevice.remove(endpointId);
          if (deviceId != null) {
            _nearbyDiscoveredDevices.remove(deviceId);
          }
          _updateNearbyCount();
        },
        serviceId: _serviceId,
      );
    } catch (_) {
      Future.delayed(const Duration(seconds: 3), _startDiscovery);
    }
  }

  void _updateNearbyCount() {
    _updateState(_state.copyWith(
      nearbyAssociationsCount: _nearbyDiscoveredDevices.length,
      isDataUpToDate: _state.lastSyncAt != null &&
          DateTime.now().difference(_state.lastSyncAt!).inSeconds < 60,
    ));
  }

  void _scheduleReconnectCycle() {
    if (!_continuousModeActive) return;
    Future.delayed(_reconnectDelay, () {
      _attemptKnownDeviceConnections();
      _scheduleReconnectCycle();
    });
  }

  Future<void> _attemptKnownDeviceConnections() async {
    if (!_continuousModeActive || _restartingEndpoints) return;

    for (final entry in _nearbyEndpointToDevice.entries.toList()) {
      final endpointId = entry.key;
      final deviceId = entry.value;

      if (_connectedEndpoints.contains(endpointId)) continue;
      if (_endpointConnIdMap.containsValue(deviceId)) continue;

      final assoc = await _security.getAssociation(deviceId);
      if (assoc != null && assoc.isValid) {
        await _nearby.requestConnection(
          '$_syncPrefix${assoc.deviceId}',
          endpointId,
          onConnectionInitiated: _onConnectionInitiated,
          onConnectionResult: _onConnectionResult,
          onDisconnected: _onDisconnected,
        );
      }
    }
  }

  void _watchLocalChanges() {
    _hiveBoxesSub?.cancel();
    final controllers = <StreamController<BoxEvent>>[];
    for (final boxName in HiveSyncEngine.syncableBoxes.keys) {
      try {
        final box = Hive.box<Map>(boxName);
        final ctrl = StreamController<BoxEvent>.broadcast();
        box.watch().listen((event) {
          if (!ctrl.isClosed) ctrl.add(event);
        });
        controllers.add(ctrl);
      } catch (_) {}
    }
    if (controllers.isEmpty) return;

    DateTime _lastChangeEmit = DateTime.now();
    final mergedCtrl = StreamController<BoxEvent>.broadcast();
    for (final ctrl in controllers) {
      ctrl.stream.listen((event) {
        if (!mergedCtrl.isClosed) mergedCtrl.add(event);
      });
    }
    _hiveBoxesSub = mergedCtrl.stream.listen((event) {
      final now = DateTime.now();
      if (now.difference(_lastChangeEmit).inMilliseconds >= 500) {
        _lastChangeEmit = now;
        _onLocalDataChanged();
      }
    });
  }

  Future<void> _onLocalDataChanged() async {
    if (_connectedEndpoints.isEmpty) return;
    if (_isSyncing) return;

    final engine = HiveSyncEngine();
    final lastSync = await engine.getLastSyncTimestamp();
    final modified = engine.extractModifiedRecords(lastSync);
    if (modified.isEmpty) return;

    for (final endpointId in _connectedEndpoints.toList()) {
      await _pushIncrementalSync(endpointId, modified);
    }
    await engine.saveLastSyncTimestamp(DateTime.now().toUtc());
  }

  Future<void> _pushIncrementalSync(
      String endpointId, List<SyncRecord> records) async {
    try {
      final modifiedKeys = records
          .map((r) => '${r.boxName}:${r.id}')
          .toList();
      if (modifiedKeys.isEmpty) return;

      final payload = jsonEncode({
        'type': 'p2p_sync_request',
        'keys': modifiedKeys,
      });
      await _sendEncryptedPayload(endpointId, payload);
    } catch (e) {
      debugPrint('[P2P] Incremental push error: $e');
    }
  }

  Future<void> setRole(P2PSyncRole role) async {
    if (role == P2PSyncRole.responsabile) {
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage:
            'Funzione Responsabile in fase di implementazione.',
      ));
      return;
    }
    _updateState(_state.copyWith(role: role));
  }

  Future<void> startPairingMode() async {
    addLog('INFO', 'Modalità associazione avviata');
    if (!_initialized) await init();

    final permResult =
        await BluetoothPermissionService.checkAndRequestPermissions();
    if (!permResult.allGranted) {
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage:
            permResult.errorMessage ?? 'Permessi insufficienti.',
      ));
      return;
    }

    _restartingEndpoints = true;
    try {
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
    } catch (_) {}

    _updateState(_state.copyWith(
      isPairingMode: true,
      status: P2PSyncStatus.pairing,
      clearError: true,
    ));

    try {
      final identity = await _security.getLocalIdentity();
      final displayName =
          '$_syncPrefix${identity.deviceId}';

      await _nearby.startAdvertising(
        displayName,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );

      await _nearby.startDiscovery(
        displayName,
        Strategy.P2P_CLUSTER,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: (_) {},
        serviceId: _serviceId,
      );

      _pairingTimeoutTimer = Timer(_pairingTimeout, () {
        if (_state.isPairingMode) {
          stopPairingMode();
          _updateState(_state.copyWith(
            status: P2PSyncStatus.error,
            errorMessage: 'Tempo scaduto per associazione.',
          ));
        }
      });
    } catch (e) {
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Errore avvio pairing: $e',
      ));
    }
  }

  Future<void> stopPairingMode() async {
    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = null;
    _pairingCompleter = null;
    _pendingEndpointId = null;
    _restartingEndpoints = false;
    try {
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
    } catch (_) {}

    _updateState(_state.copyWith(
      isPairingMode: false,
      status: P2PSyncStatus.idle,
    ));

    if (_continuousModeActive) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _startAdvertising();
        _startDiscovery();
      });
    }
  }

  void _onEndpointFound(
      String endpointId, String endpointName, String serviceId) {
    if (!endpointName.startsWith(_syncPrefix)) return;
    if (_pendingEndpointId != null) return;

    _pendingEndpointId = endpointId;

    _nearby.requestConnection(
      'CH_Pairing',
      endpointId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
  }

  Future<void> _onConnectionInitiated(
      String endpointId, ConnectionInfo info) async {
    if (_state.role == P2PSyncRole.responsabile) {
      await _nearby.rejectConnection(endpointId);
      return;
    }

    if (!_state.isPairingMode && !_continuousModeActive) {
      final deviceId = _extractDeviceId(info.endpointName);
      if (deviceId != null) {
        final association = await _security.getAssociation(deviceId);
        if (association == null || !association.isValid) {
          await _nearby.rejectConnection(endpointId);
          return;
        }
      } else {
        await _nearby.rejectConnection(endpointId);
        return;
      }
    }

    _pendingEndpointId = endpointId;

    await _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: _onPayloadReceived,
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      addLog('INFO', 'Dispositivo connesso');
      _pairingCompleter?.complete();
      _connectedEndpoints.add(endpointId);
      _sendHandshakePayload(endpointId);
      _updateState(_state.copyWith(
        status: P2PSyncStatus.sessionEstablished,
        connectedDeviceId: endpointId,
        isSessionEncrypted: false,
      ));
    } else {
      _pendingEndpointId = null;
      addLog('ERROR', 'Connessione fallita: $status');
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Connessione fallita: $status',
      ));
    }
  }

  void _onDisconnected(String endpointId) {
    addLog('INFO', 'Dispositivo disconnesso');
    _connectedEndpoints.remove(endpointId);
    _endpointConnIdMap.remove(endpointId);
    _endpointSessionKeys.remove(endpointId);
    _endpointSyncPhase.remove(endpointId);
    if (_pendingEndpointId == endpointId) {
      _pendingEndpointId = null;
    }
    if (_state.connectedDeviceId == endpointId) {
      _updateState(_state.copyWith(
        status: P2PSyncStatus.idle,
        connectedDeviceId: null,
        connectedDeviceName: null,
        connectedFingerprint: null,
        isSessionEncrypted: false,
      ));
    }
  }

  final Map<String, String> _endpointConnIdMap = {};

  String? _extractDeviceId(String endpointName) {
    try {
      if (endpointName.startsWith(_syncPrefix)) {
        return endpointName.substring(3);
      }
    } catch (_) {}
    return null;
  }

  bool _rolesAreCompatible(P2PSyncRole local, P2PSyncRole remote) {
    if (local == P2PSyncRole.responsabile ||
        remote == P2PSyncRole.responsabile) {
      return false;
    }
    return local != remote;
  }

  Future<void> _sendHandshakePayload(String endpointId) async {
    try {
      final qrPayload = await _security.generateQrPayload();
      final handshakeMsg = jsonEncode({
        'type': 'p2p_handshake',
        'payload': qrPayload,
        'timestamp':
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'role': _state.role.name,
      });
      await _sendPayload(endpointId, handshakeMsg);
      _updateState(_state.copyWith(status: P2PSyncStatus.handshakeSent));
    } catch (e) {
      debugPrint('[P2P] Handshake send error: $e');
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.bytes == null) return;
    try {
      final rawMessage = utf8.decode(payload.bytes!);
      _handleMessage(endpointId, rawMessage);
    } catch (e) {
      debugPrint('[P2P] Payload decode error: $e');
    }
  }

  Future<String> _tryDecryptMessage(
      String endpointId, String rawMessage) async {
    final sessionKey = _endpointSessionKeys[endpointId];
    if (sessionKey != null) {
      try {
        final encrypted = P2PEncryptedPayload.decode(rawMessage);
        return await _security.decryptPayload(encrypted, sessionKey);
      } catch (_) {}
    }
    return rawMessage;
  }

  Future<void> _handleMessage(
      String endpointId, String rawMessage) async {
    try {
      final message = await _tryDecryptMessage(endpointId, rawMessage);
      final decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic>) return;

      final type = decoded['type'] as String?;

      switch (type) {
        case 'p2p_handshake':
          await _handleHandshake(endpointId, decoded);
          break;
        case 'p2p_handshake_ack':
          await _handleHandshakeAck(endpointId, decoded);
          break;
        case 'p2p_auth_request':
          await _handleAuthRequest(endpointId, decoded);
          break;
        case 'p2p_auth_response':
          await _handleAuthResponse(endpointId, decoded);
          break;
        case 'p2p_sync_index':
          await _handleSyncIndex(endpointId, decoded);
          break;
        case 'p2p_sync_request':
          await _handleSyncRequest(endpointId, decoded);
          break;
        case 'p2p_sync_data':
          await _handleSyncData(endpointId, decoded);
          break;
        case 'p2p_sync_ack':
          await _handleSyncAck(endpointId, decoded);
          break;
      }
    } catch (e) {
      debugPrint('[P2P] Handle message error: $e');
    }
  }

  Future<void> _handleHandshake(
      String endpointId, Map<String, dynamic> message) async {
    final rawPayload = message['payload'] as String?;
    if (rawPayload == null) return;

    final remoteIdentity = P2PSecurityService.parseQrPayload(rawPayload);
    if (remoteIdentity == null) return;

    final remoteRoleStr = message['role'] as String?;
    final remoteRole = remoteRoleStr != null
        ? P2PSyncRole.values.firstWhere(
            (r) => r.name == remoteRoleStr,
            orElse: () => P2PSyncRole.mioDispositivo,
          )
        : P2PSyncRole.mioDispositivo;

    if (!_rolesAreCompatible(_state.role, remoteRole)) {
      addLog('ERROR',
          'Ruoli incompatibili: entrambi ${_state.role.name} '
          'con ${remoteIdentity.deviceName}');
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Ruoli incompatibili: entrambi i dispositivi sono '
            'impostati come "${_state.role.name}". '
            'Uno deve essere "mioDispositivo" e l\'altro "altroCatechista".',
      ));
      return;
    }

    final timestamp = message['timestamp'] as int? ?? 0;
    final age = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - timestamp;
    if (age.abs() > 120) {
      debugPrint('[P2P] Handshake expired');
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      return;
    }

    final existingAssoc =
        await _security.getAssociation(remoteIdentity.deviceId);

    if (existingAssoc != null &&
        !P2PSecurityService.publicKeyMatchesAssociation(
            existingAssoc, remoteIdentity.publicKeyBase64)) {
      debugPrint('[P2P] MITM DETECTED: public key mismatch for ${remoteIdentity.deviceId}');
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'MITM rilevato: la chiave pubblica del dispositivo '
            '${remoteIdentity.deviceName} non corrisponde a quella salvata.',
      ));
      return;
    }

    _endpointConnIdMap[endpointId] = remoteIdentity.deviceId;
    _connectedEndpoints.add(endpointId);

    final localIdentity = await _security.getLocalIdentity();
    final ack = jsonEncode({
      'type': 'p2p_handshake_ack',
      'payload': localIdentity.encode(),
      'role': _state.role.name,
    });

    if (existingAssoc != null) {
      await _sendEncryptedPayload(endpointId, ack);
      _updateState(_state.copyWith(
        status: P2PSyncStatus.sessionEstablished,
        connectedDeviceId: endpointId,
        connectedDeviceName: remoteIdentity.deviceName,
        connectedFingerprint: remoteIdentity.fingerprint,
        isSessionEncrypted: true,
      ));

      final iAmInitiator =
          localIdentity.deviceId.compareTo(remoteIdentity.deviceId) < 0;
      if (iAmInitiator) {
        final authRequest = jsonEncode({
          'type': 'p2p_auth_request',
          'deviceId': localIdentity.deviceId,
          'deviceName': localIdentity.deviceName,
        });
        await _sendEncryptedPayload(endpointId, authRequest);
      }
    } else {
      final sharedSecret = await _security.computeStaticSharedSecret(
        remoteIdentity.publicKeyBase64,
        forDeviceId: remoteIdentity.deviceId,
      );
      final code = P2PSecurityService.computePairingCode(sharedSecret);

      _pendingHandshakeIdentity = remoteIdentity;
      _pendingHandshakeRemoteRole = remoteRole;
      await _sendPayload(endpointId, ack);

      _updateState(_state.copyWith(
        status: P2PSyncStatus.pairingVerification,
        connectedDeviceId: endpointId,
        connectedDeviceName: remoteIdentity.deviceName,
        connectedFingerprint: remoteIdentity.fingerprint,
        isSessionEncrypted: true,
        pairingCode: code,
        remoteDeviceFingerprint: remoteIdentity.fingerprint,
      ));
    }
  }

  Future<void> _handleHandshakeAck(
      String endpointId, Map<String, dynamic> message) async {
    final rawPayload = message['payload'] as String?;
    if (rawPayload == null) return;
    final remoteIdentity = P2PSecurityService.parseQrPayload(rawPayload);
    if (remoteIdentity == null) return;

    final remoteRoleStr = message['role'] as String?;
    final remoteRole = remoteRoleStr != null
        ? P2PSyncRole.values.firstWhere(
            (r) => r.name == remoteRoleStr,
            orElse: () => P2PSyncRole.mioDispositivo,
          )
        : P2PSyncRole.mioDispositivo;

    if (!_rolesAreCompatible(_state.role, remoteRole)) {
      addLog('ERROR',
          'Ruoli incompatibili: entrambi ${_state.role.name} '
          'con ${remoteIdentity.deviceName}');
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Ruoli incompatibili: entrambi i dispositivi sono '
            'impostati come "${_state.role.name}". '
            'Uno deve essere "mioDispositivo" e l\'altro "altroCatechista".',
      ));
      return;
    }

    final existingAssoc =
        await _security.getAssociation(remoteIdentity.deviceId);

    if (existingAssoc != null &&
        !P2PSecurityService.publicKeyMatchesAssociation(
            existingAssoc, remoteIdentity.publicKeyBase64)) {
      debugPrint('[P2P] MITM DETECTED in ack: public key mismatch for ${remoteIdentity.deviceId}');
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'MITM rilevato: chiave pubblica alterata per ${remoteIdentity.deviceName}.',
      ));
      return;
    }

    _endpointConnIdMap[endpointId] = remoteIdentity.deviceId;
    _connectedEndpoints.add(endpointId);

    if (existingAssoc != null) {
      if (!_isSyncing) {
        await _saveAssociationIfNeeded(remoteIdentity, remoteRole: remoteRole);
      }

      _updateState(_state.copyWith(
        connectedFingerprint: remoteIdentity.fingerprint,
        connectedDeviceName: remoteIdentity.deviceName,
        isSessionEncrypted: true,
      ));

      final localIdentity = await _security.getLocalIdentity();
      final iAmInitiator =
          localIdentity.deviceId.compareTo(remoteIdentity.deviceId) < 0;

      if (iAmInitiator) {
        final authRequest = jsonEncode({
          'type': 'p2p_auth_request',
          'deviceId': localIdentity.deviceId,
          'deviceName': localIdentity.deviceName,
        });
        await _sendEncryptedPayload(endpointId, authRequest);
      }
    } else {
      final sharedSecret = await _security.computeStaticSharedSecret(
        remoteIdentity.publicKeyBase64,
        forDeviceId: remoteIdentity.deviceId,
      );
      final code = P2PSecurityService.computePairingCode(sharedSecret);

      _pendingHandshakeIdentity = remoteIdentity;
      _pendingHandshakeRemoteRole = remoteRole;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.pairingVerification,
        connectedFingerprint: remoteIdentity.fingerprint,
        connectedDeviceName: remoteIdentity.deviceName,
        isSessionEncrypted: true,
        pairingCode: code,
        remoteDeviceFingerprint: remoteIdentity.fingerprint,
      ));
    }
  }

  Future<void> _saveAssociationIfNeeded(P2PIdentity remoteIdentity,
      {P2PSyncRole? remoteRole}) async {
    try {
      final existing = await _security.getAssociation(remoteIdentity.deviceId);
      if (existing != null) {
        if (!P2PSecurityService.publicKeyMatchesAssociation(
            existing, remoteIdentity.publicKeyBase64)) {
          debugPrint('[P2P] MITM detected in _saveAssociationIfNeeded: '
              'key mismatch for ${remoteIdentity.deviceId}');
          return;
        }
        if (existing.deviceName != remoteIdentity.deviceName ||
            (remoteRole != null && existing.remoteRole != remoteRole.name)) {
          final updated = P2PDeviceAssociation(
            deviceId: existing.deviceId,
            deviceName: remoteIdentity.deviceName,
            publicKeyBase64: existing.publicKeyBase64,
            fingerprint: existing.fingerprint,
            sharedSecretBase64: existing.sharedSecretBase64,
            associatedAt: existing.associatedAt,
            devicePrivateKeyBase64: existing.devicePrivateKeyBase64,
            devicePublicKeyBase64: existing.devicePublicKeyBase64,
            localRole: existing.localRole,
            remoteRole: remoteRole?.name ?? existing.remoteRole,
          );
          await _security.saveAssociation(updated);
        }
        return;
      }

      final sharedSecret = await _security.computeStaticSharedSecret(
          remoteIdentity.publicKeyBase64,
          forDeviceId: remoteIdentity.deviceId);

      await _security.registerAndSaveAssociation(
        deviceId: remoteIdentity.deviceId,
        deviceName: remoteIdentity.deviceName,
        publicKeyBase64: remoteIdentity.publicKeyBase64,
        fingerprint: remoteIdentity.fingerprint,
        sharedSecretBase64: sharedSecret,
        localRole: _state.role.name,
        remoteRole: remoteRole?.name,
      );

      addLog('INFO', 'Associazione salvata per ${remoteIdentity.deviceName}');
    } catch (e) {
      addLog('ERROR', 'Errore salvataggio associazione: $e');
    }
  }

  Future<void> _handleAuthRequest(
      String endpointId, Map<String, dynamic> message) async {
    final deviceId = message['deviceId'] as String?;
    final deviceName = message['deviceName'] as String? ?? 'Sconosciuto';

    if (_state.role != P2PSyncRole.altroCatechista) {
      final ack = jsonEncode({
        'type': 'p2p_auth_response',
        'accepted': true,
        'deviceId': deviceId,
      });
      await _sendEncryptedPayload(endpointId, ack);
      return;
    }

    if (deviceId != null && _sessionConfirmedDevices.contains(deviceId)) {
      final ack = jsonEncode({
        'type': 'p2p_auth_response',
        'accepted': true,
        'deviceId': deviceId,
      });
      await _sendEncryptedPayload(endpointId, ack);
      return;
    }

    _updateState(_state.copyWith(
      awaitingConfirmation: true,
      pendingConfirmationDeviceName: deviceName,
      pendingConfirmationDeviceId: deviceId,
      status: P2PSyncStatus.sessionEstablished,
    ));
  }

  Future<void> _handleAuthResponse(
      String endpointId, Map<String, dynamic> message) async {
    final accepted = message['accepted'] == true;
    if (!accepted) {
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Sync rifiutata dal dispositivo remoto.',
      ));
      return;
    }

    await _performBidirectionalSync(endpointId);
  }

  Future<void> _performBidirectionalSync(String endpointId) async {
    if (_endpointSyncPhase[endpointId] != null &&
        _endpointSyncPhase[endpointId] != _syncPhaseIdle &&
        _endpointSyncPhase[endpointId] != _syncPhaseComplete) {
      return;
    }
    _endpointSyncPhase[endpointId] = _syncPhaseSentIndex;
    _isSyncing = true;

    _updateState(_state.copyWith(status: P2PSyncStatus.syncing));

    try {
      final engine = HiveSyncEngine();
      final lastSync = await engine.getLastSyncTimestamp();
      final localIndex = engine.buildLocalIndex();

      final indexPayload = jsonEncode({
        'type': 'p2p_sync_index',
        'index': localIndex.map((e) => e.toJson()).toList(),
        'since': lastSync.toUtc().toIso8601String(),
      });
      await _sendEncryptedPayload(endpointId, indexPayload);
    } catch (e) {
      _isSyncing = false;
      _endpointSyncPhase[endpointId] = _syncPhaseIdle;
      addLog('ERROR', 'Errore sincronizzazione: $e');
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Errore sincronizzazione: $e',
      ));
    }
  }

  void _checkSyncComplete(String endpointId) {
    final phase = _endpointSyncPhase[endpointId] ?? _syncPhaseIdle;
    if (phase == _syncPhaseComplete) return;
    if (phase == _syncPhaseSendDone || phase == _syncPhaseReceiveDone) {
      _endpointSyncPhase[endpointId] = _syncPhaseComplete;
      _isSyncing = false;
      addLog('INFO', 'Sincronizzazione completata con $endpointId');
      _updateState(_state.copyWith(
        status: P2PSyncStatus.completed,
        lastSyncAt: DateTime.now(),
      ));
    }
  }

  Future<SecretKeyData> _deriveSessionKey(String deviceId) async {
    final assoc = await _security.getAssociation(deviceId);
    if (assoc == null) {
      throw Exception('Associazione non trovata per $deviceId');
    }
    final localIdentity = await _security.getLocalIdentity();
    final isInitiator =
        localIdentity.deviceId.compareTo(deviceId) < 0;
    final session = await _security.createEphemeralSession(
      remoteDeviceId: deviceId,
      remoteDeviceName: assoc.deviceName,
      remotePublicKeyBase64: assoc.publicKeyBase64,
      isInitiator: isInitiator,
    );
    return session.sessionKey;
  }

  Future<void> _ensureSessionKey(String endpointId) async {
    if (_endpointSessionKeys.containsKey(endpointId)) return;
    final deviceId = _endpointConnIdMap[endpointId];
    if (deviceId == null) return;
    try {
      final key = await _deriveSessionKey(deviceId);
      _endpointSessionKeys[endpointId] = key;
    } catch (e) {
      addLog('ERROR', 'Errore derivazione chiave sessione: $e');
    }
  }

  Future<void> _sendEncryptedPayload(
      String endpointId, String plainText) async {
    await _ensureSessionKey(endpointId);
    final sessionKey = _endpointSessionKeys[endpointId];
    if (sessionKey == null) {
      addLog('ERROR', 'Nessuna chiave di sessione per $endpointId');
      return;
    }
    try {
      final encrypted =
          await _security.encryptPayload(plainText, sessionKey);
      await _sendPayload(endpointId, encrypted.encode());
    } catch (e) {
      addLog('ERROR', 'Errore cifratura payload: $e');
    }
  }

  Future<void> _sendPayload(String endpointId, String data) async {
    try {
      await _nearby.sendBytesPayload(
        endpointId,
        Uint8List.fromList(utf8.encode(data)),
      );
    } catch (e) {
      debugPrint('[P2P] Send error: $e');
    }
  }

  Future<void> _handleSyncIndex(
      String endpointId, Map<String, dynamic> message) async {
    try {
      _endpointSyncPhase[endpointId] = _syncPhaseSentIndex;
      final engine = HiveSyncEngine();
      final localIndex = engine.buildLocalIndex();

      final remoteIndexData = message['index'] as List<dynamic>? ?? [];
      final remoteIndex = remoteIndexData
          .map((e) => SyncIndexEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      final neededFromRemote = engine.computeNeededRecords(remoteIndex);
      final neededFromLocal =
          engine.computeNeededRecordsFromLocal(localIndex, remoteIndex);

      if (neededFromLocal.isNotEmpty) {
        final localRecords = engine.fetchRecords(neededFromLocal);
        final recordsPayload = jsonEncode({
          'type': 'p2p_sync_data',
          'records': engine.serializeRecords(localRecords),
        });
        await _sendEncryptedPayload(endpointId, recordsPayload);
      }
      _endpointSyncPhase[endpointId] = _syncPhaseSendDone;

      if (neededFromRemote.isNotEmpty) {
        final requestPayload = jsonEncode({
          'type': 'p2p_sync_request',
          'keys': neededFromRemote,
        });
        await _sendEncryptedPayload(endpointId, requestPayload);
      } else {
        _endpointSyncPhase[endpointId] = _syncPhaseReceiveDone;
        _checkSyncComplete(endpointId);
      }
    } catch (e) {
      addLog('ERROR', 'Errore elaborazione indice: $e');
      _endpointSyncPhase[endpointId] = _syncPhaseIdle;
      _isSyncing = false;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Errore elaborazione indice: $e',
      ));
    }
  }

  Future<void> _handleSyncRequest(
      String endpointId, Map<String, dynamic> message) async {
    try {
      final engine = HiveSyncEngine();
      final keys = (message['keys'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      if (keys.isEmpty) {
        _endpointSyncPhase[endpointId] = _syncPhaseSendDone;
        _checkSyncComplete(endpointId);
        return;
      }

      final records = engine.fetchRecords(keys);
      final recordsPayload = jsonEncode({
        'type': 'p2p_sync_data',
        'records': engine.serializeRecords(records),
      });
      await _sendEncryptedPayload(endpointId, recordsPayload);

      _endpointSyncPhase[endpointId] = _syncPhaseSendDone;
      _checkSyncComplete(endpointId);
    } catch (e) {
      addLog('ERROR', 'Errore risposta richiesta sync: $e');
    }
  }

  Future<void> _handleSyncData(
      String endpointId, Map<String, dynamic> message) async {
    try {
      final engine = HiveSyncEngine();
      final recordsData = message['records'] as List<dynamic>? ?? [];
      final records = engine.deserializeRecords(recordsData);

      final result = await engine.applyRemoteRecords(records);

      _endpointSyncPhase[endpointId] = _syncPhaseReceiveDone;

      await engine.saveLastSyncTimestamp(result.syncTimestamp);

      final ack = jsonEncode({
        'type': 'p2p_sync_ack',
        'received': result.receivedRecords,
      });
      await _sendEncryptedPayload(endpointId, ack);

      _checkSyncComplete(endpointId);
    } catch (e) {
      addLog('ERROR', 'Errore applicazione dati: $e');
      _endpointSyncPhase[endpointId] = _syncPhaseIdle;
      _isSyncing = false;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Errore applicazione dati: $e',
      ));
    }
  }

  Future<void> _handleSyncAck(
      String endpointId, Map<String, dynamic> message) async {
    _endpointSyncPhase[endpointId] = _syncPhaseSendDone;
    _checkSyncComplete(endpointId);
  }

  Future<void> confirmPairingCode() async {
    if (_state.status != P2PSyncStatus.pairingVerification) return;
    if (_state.connectedDeviceId == null) return;

    final endpointId = _state.connectedDeviceId!;
    final remoteIdentity = _pendingHandshakeIdentity;
    if (remoteIdentity == null) {
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Errore: identità remota persa durante verifica.',
      ));
      return;
    }

    final existing = await _security.getAssociation(remoteIdentity.deviceId);
    if (existing != null) {
      _updateState(_state.copyWith(
        status: P2PSyncStatus.sessionEstablished,
        pairingCode: null,
        remotePairingCode: null,
      ));
      return;
    }

    final localIdentity = await _security.getLocalIdentity();

    await _saveAssociationIfNeeded(remoteIdentity,
        remoteRole: _pendingHandshakeRemoteRole);

    _pendingHandshakeIdentity = null;
    _pendingHandshakeRemoteRole = null;

    _updateState(_state.copyWith(
      status: P2PSyncStatus.sessionEstablished,
      pairingCode: null,
      remotePairingCode: null,
    ));

    final iAmInitiator =
        localIdentity.deviceId.compareTo(remoteIdentity.deviceId) < 0;

    if (iAmInitiator) {
      final authRequest = jsonEncode({
        'type': 'p2p_auth_request',
        'deviceId': localIdentity.deviceId,
        'deviceName': localIdentity.deviceName,
      });
      await _sendEncryptedPayload(endpointId, authRequest);
    }
  }

  Future<void> rejectPairingCode() async {
    if (_state.status != P2PSyncStatus.pairingVerification) return;
    if (_state.connectedDeviceId == null) return;

    final endpointId = _state.connectedDeviceId!;
    try {
      await _nearby.disconnectFromEndpoint(endpointId);
    } catch (_) {}
    _connectedEndpoints.remove(endpointId);
    _pendingEndpointId = null;
    _pendingHandshakeIdentity = null;
    _pendingHandshakeRemoteRole = null;

    _updateState(_state.copyWith(
      status: P2PSyncStatus.idle,
      connectedDeviceId: null,
      connectedDeviceName: null,
      connectedFingerprint: null,
      isSessionEncrypted: false,
      pairingCode: null,
      remotePairingCode: null,
      errorMessage: 'Codice di verifica non corrispondente. '
          'Possibile attacco MitM: associazione annullata.',
    ));
  }

  Future<void> confirmSync() async {
    if (!_state.awaitingConfirmation) return;

    final endpointId = _state.connectedDeviceId;
    final confirmedDeviceId = _state.pendingConfirmationDeviceId;

    if (confirmedDeviceId != null) {
      _sessionConfirmedDevices.add(confirmedDeviceId);
    }

    _updateState(_state.copyWith(
      awaitingConfirmation: false,
      pendingConfirmationDeviceName: null,
      pendingConfirmationDeviceId: null,
      status: P2PSyncStatus.sessionEstablished,
    ));

    if (endpointId != null) {
      final ack = jsonEncode({
        'type': 'p2p_auth_response',
        'accepted': true,
      });
      await _sendEncryptedPayload(endpointId, ack);
    }
  }

  Future<void> rejectSync() async {
    if (!_state.awaitingConfirmation) return;

    final endpointId = _state.connectedDeviceId;

    _updateState(_state.copyWith(
      awaitingConfirmation: false,
      pendingConfirmationDeviceName: null,
      pendingConfirmationDeviceId: null,
      status: P2PSyncStatus.idle,
    ));

    if (endpointId != null) {
      final ack = jsonEncode({
        'type': 'p2p_auth_response',
        'accepted': false,
      });
      await _sendEncryptedPayload(endpointId, ack);
    }
  }

  Future<void> sendSyncData(
      String endpointId, Map<String, dynamic> data) async {
    final payload = jsonEncode({
      'type': 'p2p_sync_data',
      ...data,
    });
    await _sendEncryptedPayload(endpointId, payload);
  }

  Future<void> startBackgroundSync() async {
    addLog('INFO', 'Sincronizzazione automatica attivata');
    _startContinuousMode();
  }

  void stopBackgroundSync() {
    addLog('INFO', 'Sincronizzazione automatica disattivata');
    _stopContinuousMode();
    _updateState(_state.copyWith(isBackgroundSyncActive: false));
  }

  Future<void> triggerManualSync() async {
    addLog('INFO', 'Sincronizzazione manuale richiesta');
    if (_connectedEndpoints.isEmpty) {
      addLog('INFO', 'Nessun dispositivo connesso, ricerca in corso...');
      _attemptKnownDeviceConnections();
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (_connectedEndpoints.isNotEmpty) break;
      }
    }
    final endpoints = _connectedEndpoints.toList();
    if (endpoints.isNotEmpty) {
      addLog('INFO', 'Avvio sincronizzazione con dispositivo connesso');
      await _performBidirectionalSync(endpoints.first);
    } else {
      addLog('WARN', 'Nessun dispositivo trovato per la sincronizzazione');
    }
  }

  void dispose() {
    _pairingTimeoutTimer?.cancel();
    _periodicSyncTimer?.cancel();
    _hiveBoxesSub?.cancel();
    stopPairingMode();
    _stopContinuousMode();
    _nearbyDiscoveredDevices.clear();
    _nearbyEndpointToDevice.clear();
    _sessionConfirmedDevices.clear();
    _pendingHandshakeIdentity = null;
    _endpointSyncPhase.clear();
    _endpointSessionKeys.clear();
    _initialized = false;
    _stateController.close();
    _syncDataController.close();
  }
}

class SyncLogEntry {
  final DateTime timestamp;
  final String level;
  final String message;

  const SyncLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });
}

class P2PResponsabileHandler {
  Future<void> syncAll() async {
    throw UnsupportedError(
      'Funzione Responsabile non ancora implementata.',
    );
  }
}