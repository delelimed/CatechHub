import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:nearby_connections/nearby_connections.dart';

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
    );
  }
}

class P2PSyncService {
  static final P2PSyncService _instance = P2PSyncService._();
  factory P2PSyncService() => _instance;
  P2PSyncService._();

  final Nearby _nearby = Nearby();
  final P2PSecurityService _security = P2PSecurityService();

  final _stateController = StreamController<P2PSyncState>.broadcast();
  final _syncDataController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<P2PSyncState> get onStateChanged => _stateController.stream;
  Stream<Map<String, dynamic>> get onSyncData => _syncDataController.stream;

  P2PSyncState _state = const P2PSyncState();
  P2PSyncState get currentState => _state;

  Timer? _pairingTimeoutTimer;
  bool _initialized = false;
  bool _isSyncing = false;
  String? _pendingEndpointId;

  Completer<void>? _pairingCompleter;

  bool _syncSendDone = false;
  bool _syncReceiveDone = false;

  String? _connectedDeviceId;

  bool _continuousModeActive = false;
  final Set<String> _connectedEndpoints = {};
  bool _restartingEndpoints = false;
  StreamSubscription<BoxEvent>? _hiveBoxesSub;

  static const Duration _pairingTimeout = Duration(seconds: 120);
  static const Duration _reconnectDelay = Duration(seconds: 5);
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

    _updateState(_state.copyWith(
      isBackgroundSyncActive: true,
      clearError: true,
    ));
  }

  void _stopContinuousMode() {
    _continuousModeActive = false;
    _hiveBoxesSub?.cancel();
    _hiveBoxesSub = null;
    try {
      _nearby.stopAdvertising();
      _nearby.stopDiscovery();
    } catch (_) {}
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

          Future(() async {
            if (_connectedEndpoints.contains(endpointId)) return;
            if (_pendingEndpointId != null) return;

            final assoc = await _security.getAssociation(deviceId);
            if (assoc != null && assoc.isValid) {
              _pendingEndpointId = endpointId;
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
        onEndpointLost: (_) {},
        serviceId: _serviceId,
      );
    } catch (_) {
      Future.delayed(const Duration(seconds: 3), _startDiscovery);
    }
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
    if (_pendingEndpointId != null) return;

    final associations = await _security.getAllAssociations();
    if (associations.isEmpty) return;

    try {
      await _nearby.stopDiscovery();
      await _nearby.startDiscovery(
        _syncPrefix,
        Strategy.P2P_CLUSTER,
        onEndpointFound: (endpointId, name, serviceId) {
          if (!name.startsWith(_syncPrefix)) return;
          final deviceId = _extractDeviceId(name);
          if (deviceId == null) return;

          Future(() async {
            if (_connectedEndpoints.contains(endpointId)) return;
            if (_connectedEndpoints.length >= associations.length) return;
            if (_pendingEndpointId != null) return;

            final assoc = await _security.getAssociation(deviceId);
            if (assoc != null && assoc.isValid) {
              _pendingEndpointId = endpointId;
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
        onEndpointLost: (_) {},
        serviceId: _serviceId,
      );
    } catch (_) {}
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
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Connessione fallita: $status',
      ));
    }
  }

  void _onDisconnected(String endpointId) {
    _connectedEndpoints.remove(endpointId);
    _endpointConnIdMap.remove(endpointId);
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

  Future<void> _sendHandshakePayload(String endpointId) async {
    try {
      final qrPayload = await _security.generateQrPayload();
      final handshakeMsg = jsonEncode({
        'type': 'p2p_handshake',
        'payload': qrPayload,
        'timestamp':
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
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

  Future<String> _tryDecryptMessage(String rawMessage) async {
    final secret = await _sharedSecretForConnection();
    if (secret != null) {
      try {
        return await _security.decryptPayloadString(rawMessage, secret);
      } catch (_) {}
    }
    return rawMessage;
  }

  Future<void> _handleMessage(
      String endpointId, String rawMessage) async {
    try {
      final message = await _tryDecryptMessage(rawMessage);
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

    _endpointConnIdMap[endpointId] = remoteIdentity.deviceId;
    _connectedDeviceId = remoteIdentity.deviceId;
    _connectedEndpoints.add(endpointId);
    await _saveAssociationIfNeeded(remoteIdentity);

    final localIdentity = await _security.getLocalIdentity();
    final ack = jsonEncode({
      'type': 'p2p_handshake_ack',
      'payload': localIdentity.encode(),
    });
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
  }

  Future<void> _handleHandshakeAck(
      String endpointId, Map<String, dynamic> message) async {
    final rawPayload = message['payload'] as String?;
    if (rawPayload == null) return;
    final remoteIdentity = P2PSecurityService.parseQrPayload(rawPayload);
    if (remoteIdentity == null) return;

    _endpointConnIdMap[endpointId] = remoteIdentity.deviceId;
    _connectedDeviceId = remoteIdentity.deviceId;
    _connectedEndpoints.add(endpointId);

    _updateState(_state.copyWith(
      connectedFingerprint: remoteIdentity.fingerprint,
      connectedDeviceName: remoteIdentity.deviceName,
      isSessionEncrypted: true,
    ));

    if (!_isSyncing) {
      await _saveAssociationIfNeeded(remoteIdentity);
    }

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
  }

  Future<void> _saveAssociationIfNeeded(P2PIdentity remoteIdentity) async {
    try {
      final existing = await _security.getAssociation(remoteIdentity.deviceId);
      if (existing != null) {
        if (existing.deviceName != remoteIdentity.deviceName) {
          final updated = P2PDeviceAssociation(
            deviceId: existing.deviceId,
            deviceName: remoteIdentity.deviceName,
            publicKeyBase64: existing.publicKeyBase64,
            fingerprint: existing.fingerprint,
            sharedSecretBase64: existing.sharedSecretBase64,
            associatedAt: existing.associatedAt,
          );
          await _security.saveAssociation(updated);
        }
        return;
      }

      final sharedSecret = await _security.computeStaticSharedSecret(
          remoteIdentity.publicKeyBase64);

      final association = P2PDeviceAssociation(
        deviceId: remoteIdentity.deviceId,
        deviceName: remoteIdentity.deviceName,
        publicKeyBase64: remoteIdentity.publicKeyBase64,
        fingerprint: remoteIdentity.fingerprint,
        sharedSecretBase64: sharedSecret,
        associatedAt: DateTime.now(),
      );

      await _security.saveAssociation(association);
      debugPrint('[P2P] Association saved for ${remoteIdentity.deviceName}');
    } catch (e) {
      debugPrint('[P2P] Error saving association: $e');
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
    if (_isSyncing) return;
    _isSyncing = true;
    _syncSendDone = false;
    _syncReceiveDone = false;

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

      final completer = Completer<SyncResult>();

      late final StreamSubscription<P2PSyncState> stateSub;
      stateSub = onStateChanged.listen((state) {
        if (state.status == P2PSyncStatus.completed ||
            state.status == P2PSyncStatus.error) {
          stateSub.cancel();
          if (!completer.isCompleted) {
            if (state.status == P2PSyncStatus.completed) {
              completer.complete(SyncResult(
                success: true,
                sentRecords: state.sentRecords,
                receivedRecords: state.receivedRecords,
                syncTimestamp: DateTime.now().toUtc(),
              ));
            } else {
              completer.complete(SyncResult(
                success: false,
                error: state.errorMessage ?? 'Sync failed',
                syncTimestamp: DateTime.now().toUtc(),
              ));
            }
          }
        }
      });

      final result = await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          stateSub.cancel();
          return SyncResult(
            success: false,
            error: 'Sync timeout',
            syncTimestamp: DateTime.now().toUtc(),
          );
        },
      );

      _isSyncing = false;
      _syncSendDone = false;
      _syncReceiveDone = false;

      if (result.success) {
        if (_state.connectedDeviceId == endpointId) {
          _updateState(_state.copyWith(
            status: P2PSyncStatus.completed,
            lastSyncAt: result.syncTimestamp,
            sentRecords: result.sentRecords,
            receivedRecords: result.receivedRecords,
          ));
        } else {
          _updateState(_state.copyWith(
            status: P2PSyncStatus.completed,
            lastSyncAt: result.syncTimestamp,
          ));
        }
      } else {
        _updateState(_state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: result.error,
        ));
      }
    } catch (e) {
      _isSyncing = false;
      _syncSendDone = false;
      _syncReceiveDone = false;
      debugPrint('[P2P] Sync error: $e');
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Errore sincronizzazione: $e',
      ));
    }
  }

  Future<String?> _sharedSecretForConnection() async {
    if (_connectedDeviceId == null) return null;
    return await _security.getSharedSecret(_connectedDeviceId!);
  }

  Future<void> _sendEncryptedPayload(
      String endpointId, String plainText) async {
    final deviceId = _endpointConnIdMap[endpointId];
    String? secret;
    if (deviceId != null) {
      secret = await _security.getSharedSecret(deviceId);
    }
    if (secret == null) {
      secret = await _sharedSecretForConnection();
    }
    if (secret != null) {
      try {
        final encrypted =
            await _security.encryptPayloadString(plainText, secret);
        await _sendPayload(endpointId, encrypted);
        return;
      } catch (_) {}
    }
    await _sendPayload(endpointId, plainText);
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
      final engine = HiveSyncEngine();
      final localIndex = engine.buildLocalIndex();

      final remoteIndexData = message['index'] as List<dynamic>? ?? [];
      final remoteIndex = remoteIndexData
          .map((e) => SyncIndexEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      final neededFromRemote = engine.computeNeededRecords(remoteIndex);
      final neededFromLocal =
          engine.computeNeededRecordsFromLocal(localIndex, remoteIndex);

      var sentCount = 0;
      if (neededFromLocal.isNotEmpty) {
        final localRecords = engine.fetchRecords(neededFromLocal);
        final recordsPayload = jsonEncode({
          'type': 'p2p_sync_data',
          'records': engine.serializeRecords(localRecords),
        });
        await _sendEncryptedPayload(endpointId, recordsPayload);
        sentCount = localRecords.length;
      }
      _syncSendDone = true;

      if (neededFromRemote.isNotEmpty) {
        final requestPayload = jsonEncode({
          'type': 'p2p_sync_request',
          'keys': neededFromRemote,
        });
        await _sendEncryptedPayload(endpointId, requestPayload);
        _syncReceiveDone = false;
      } else {
        _syncReceiveDone = true;
      }

      if (_syncSendDone && _syncReceiveDone) {
        _updateState(_state.copyWith(
          status: P2PSyncStatus.completed,
          sentRecords: sentCount,
          receivedRecords: 0,
        ));
      }
    } catch (e) {
      debugPrint('[P2P] Handle sync index error: $e');
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
        _syncSendDone = true;
        if (_syncSendDone && _syncReceiveDone) {
          _updateState(_state.copyWith(status: P2PSyncStatus.completed));
        }
        return;
      }

      final records = engine.fetchRecords(keys);
      final recordsPayload = jsonEncode({
        'type': 'p2p_sync_data',
        'records': engine.serializeRecords(records),
      });
      await _sendEncryptedPayload(endpointId, recordsPayload);

      _syncSendDone = true;

      if (_syncSendDone && _syncReceiveDone) {
        _updateState(_state.copyWith(status: P2PSyncStatus.completed));
      }
    } catch (e) {
      debugPrint('[P2P] Handle sync request error: $e');
    }
  }

  Future<void> _handleSyncData(
      String endpointId, Map<String, dynamic> message) async {
    try {
      final engine = HiveSyncEngine();
      final recordsData = message['records'] as List<dynamic>? ?? [];
      final records = engine.deserializeRecords(recordsData);

      final result = await engine.applyRemoteRecords(records);

      _syncReceiveDone = true;

      await engine.saveLastSyncTimestamp(result.syncTimestamp);

      if (_syncSendDone && _syncReceiveDone) {
        final ack = jsonEncode({
          'type': 'p2p_sync_ack',
          'received': result.receivedRecords,
        });
        await _sendEncryptedPayload(endpointId, ack);

        _updateState(_state.copyWith(
          status: P2PSyncStatus.completed,
          sentRecords: _state.sentRecords,
          receivedRecords: result.receivedRecords,
          lastSyncAt: result.syncTimestamp,
        ));
      }
    } catch (e) {
      debugPrint('[P2P] Handle sync data error: $e');
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Errore applicazione dati: $e',
      ));
    }
  }

  Future<void> _handleSyncAck(
      String endpointId, Map<String, dynamic> message) async {
    _syncSendDone = true;
    _syncReceiveDone = true;

    if (_state.connectedDeviceId == endpointId) {
      _updateState(_state.copyWith(
        status: P2PSyncStatus.completed,
      ));
    }
  }

  Future<void> confirmSync() async {
    if (!_state.awaitingConfirmation) return;

    final endpointId = _state.connectedDeviceId;

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
    _startContinuousMode();
  }

  void stopBackgroundSync() {
    _stopContinuousMode();
    _updateState(_state.copyWith(isBackgroundSyncActive: false));
  }

  Future<void> triggerManualSync() async {
    if (_connectedEndpoints.isEmpty) {
      _attemptKnownDeviceConnections();
      await Future.delayed(const Duration(seconds: 3));
    }
    final endpoints = _connectedEndpoints.toList();
    if (endpoints.isNotEmpty) {
      await _performBidirectionalSync(endpoints.first);
    }
  }

  void dispose() {
    _pairingTimeoutTimer?.cancel();
    _hiveBoxesSub?.cancel();
    stopPairingMode();
    _stopContinuousMode();
    _stateController.close();
    _syncDataController.close();
  }
}

class P2PResponsabileHandler {
  Future<void> syncAll() async {
    throw UnsupportedError(
      'Funzione Responsabile non ancora implementata.',
    );
  }
}