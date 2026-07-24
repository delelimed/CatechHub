import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  Timer? _backgroundTimer;
  Timer? _pairingTimeoutTimer;
  bool _initialized = false;
  bool _isSyncing = false;
  String? _pendingEndpointId;

  P2PSession? _currentSession;
  P2PSession? get currentSession => _currentSession;

  Completer<void>? _pairingCompleter;

  static const Duration _backgroundInterval = Duration(minutes: 5);
  static const Duration _pairingTimeout = Duration(seconds: 120);
  static const String _serviceId = 'ch.catechhub.app';

  void _emitState() => _stateController.add(_state);

  void _updateState(P2PSyncState newState) {
    _state = newState;
    _emitState();
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
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

    _updateState(_state.copyWith(
      isPairingMode: true,
      status: P2PSyncStatus.pairing,
      clearError: true,
    ));

    try {
      final identity = await _security.getLocalIdentity();
      final displayName =
          'CH_${identity.deviceId.length > 16 ? identity.deviceId.substring(0, 16) : identity.deviceId}';

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
    _currentSession = null;
    try {
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
      await _nearby.stopAllEndpoints();
    } catch (_) {}

    _updateState(_state.copyWith(
      isPairingMode: false,
      status: P2PSyncStatus.idle,
    ));
  }

  void _onEndpointFound(
      String endpointId, String endpointName, String serviceId) {
    if (!endpointName.startsWith('CH_')) return;
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
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage:
            'Funzione Responsabile in fase di implementazione.',
      ));
      return;
    }

    if (!_state.isPairingMode) {
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
    if (_pendingEndpointId == endpointId) {
      _pendingEndpointId = null;
    }
    if (_state.connectedDeviceId == endpointId) {
      _currentSession = null;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.idle,
        connectedDeviceId: null,
        connectedDeviceName: null,
        connectedFingerprint: null,
        isSessionEncrypted: false,
      ));
    }
  }

  String? _extractDeviceId(String endpointName) {
    try {
      if (endpointName.startsWith('CH_')) {
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
      final message = utf8.decode(payload.bytes!);
      _handleMessage(endpointId, message);
    } catch (e) {
      debugPrint('[P2P] Payload decode error: $e');
    }
  }

  Future<void> _handleMessage(
      String endpointId, String message) async {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic>) return;

      final type = decoded['type'] as String?;

      switch (type) {
        case 'p2p_handshake':
          await _handleHandshake(endpointId, decoded);
          break;
        case 'p2p_handshake_ack':
          await _handleHandshakeAck(decoded);
          break;
        case 'p2p_auth_request':
          await _handleAuthRequest(endpointId, decoded);
          break;
        case 'p2p_auth_response':
          await _handleAuthResponse(decoded);
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
      _pendingEndpointId = null;
      return;
    }

    final remoteFingerprint = remoteIdentity.fingerprint;

    _updateState(_state.copyWith(
      status: P2PSyncStatus.handshakeReceived,
      connectedDeviceId: endpointId,
      connectedDeviceName: remoteIdentity.deviceName,
      connectedFingerprint: remoteFingerprint,
    ));

    if (_state.role == P2PSyncRole.altroCatechista) {
      _updateState(_state.copyWith(
        awaitingConfirmation: true,
        pendingConfirmationDeviceName: remoteIdentity.deviceName,
        pendingConfirmationDeviceId: remoteIdentity.deviceId,
        status: P2PSyncStatus.sessionEstablished,
      ));
      return;
    }

    await _establishSession(endpointId, remoteIdentity, isInitiator: false);
  }

  Future<void> _handleHandshakeAck(
      Map<String, dynamic> message) async {
    final rawPayload = message['payload'] as String?;
    if (rawPayload == null) return;
    final remoteIdentity = P2PSecurityService.parseQrPayload(rawPayload);
    if (remoteIdentity == null) return;

    _updateState(_state.copyWith(
      connectedFingerprint: remoteIdentity.fingerprint,
      connectedDeviceName: remoteIdentity.deviceName,
      isSessionEncrypted: true,
    ));

    // Initiator starts sync after receiving ack
    if (_currentSession != null && _state.connectedDeviceId != null) {
      await _performBidirectionalSync(_state.connectedDeviceId!, _currentSession!);
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
      Map<String, dynamic> message) async {
    final accepted = message['accepted'] == true;
    if (!accepted) {
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Sync rifiutata dal dispositivo remoto.',
      ));
      return;
    }
  }

  Future<void> _establishSession(
      String endpointId, P2PIdentity remoteIdentity, {bool isInitiator = false}) async {
    try {
      final session = await _security.createEphemeralSession(
        remoteDeviceId: remoteIdentity.deviceId,
        remoteDeviceName: remoteIdentity.deviceName,
        remotePublicKeyBase64: remoteIdentity.publicKeyBase64,
        isInitiator: isInitiator,
      );

      _currentSession = session;

      final localIdentity = await _security.getLocalIdentity();
      final ack = jsonEncode({
        'type': 'p2p_handshake_ack',
        'payload': localIdentity.encode(),
        'nonce': base64Encode(session.handshakeNonce),
      });
      await _sendEncryptedPayload(endpointId, ack);

      _updateState(_state.copyWith(
        status: P2PSyncStatus.sessionEstablished,
        isSessionEncrypted: true,
      ));

      // Start bidirectional sync after session is established
      await _performBidirectionalSync(endpointId, session);
    } catch (e) {
      debugPrint('[P2P] Session establish error: $e');
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Errore stabilimento sessione cifrata.',
      ));
    }
  }

  /// Performs bidirectional sync using HiveSyncEngine with LWW conflict resolution
  /// Syncs all 13 Hive boxes securely using the established session key
  Future<void> _performBidirectionalSync(String endpointId, P2PSession session) async {
    if (_isSyncing) return;
    _isSyncing = true;

    _updateState(_state.copyWith(status: P2PSyncStatus.syncing));

    try {
      final engine = HiveSyncEngine();
      final lastSync = await engine.getLastSyncTimestamp();

      // Build local index
      final localIndex = engine.buildLocalIndex();

      // Send local index to remote
      final indexPayload = jsonEncode({
        'type': 'p2p_sync_index',
        'index': localIndex.map((e) => e.toJson()).toList(),
        'since': lastSync.toUtc().toIso8601String(),
      });
      await _sendEncryptedPayload(endpointId, indexPayload);

      // Wait for remote index and data
      // The response will come through _handleSyncIndex and _handleSyncData
      // We'll use a completer to wait for the sync to complete
      final completer = Completer<SyncResult>();

      // Set up one-time listeners for sync response
      late final StreamSubscription<P2PSyncState> stateSub;
      stateSub = onStateChanged.listen((state) {
        if (state.status == P2PSyncStatus.completed || state.status == P2PSyncStatus.error) {
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

      // Wait for sync to complete (with timeout)
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

      if (result.success) {
        _updateState(_state.copyWith(
          status: P2PSyncStatus.completed,
          lastSyncAt: result.syncTimestamp,
          sentRecords: result.sentRecords,
          receivedRecords: result.receivedRecords,
        ));
      } else {
        _updateState(_state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: result.error,
        ));
      }
    } catch (e) {
      _isSyncing = false;
      debugPrint('[P2P] Sync error: $e');
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Errore sincronizzazione: $e',
      ));
    }
  }

  Future<void> _sendEncryptedPayload(
      String endpointId, String plainText) async {
    if (_currentSession != null) {
      try {
        final encrypted = await _security.encryptPayload(
            plainText, _currentSession!.sessionKey);
        await _sendPayload(endpointId, encrypted.encode());
      } catch (_) {
        await _sendPayload(endpointId, plainText);
      }
    } else {
      await _sendPayload(endpointId, plainText);
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
      final engine = HiveSyncEngine();
      final localIndex = engine.buildLocalIndex();

      // Parse remote index
      final remoteIndexData = message['index'] as List<dynamic>? ?? [];
      final remoteIndex = remoteIndexData
          .map((e) => SyncIndexEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      // Compute what we need from remote
      final neededFromRemote = engine.computeNeededRecords(remoteIndex);

      // Compute what remote needs from us
      final neededFromLocal = engine.computeNeededRecordsFromLocal(localIndex, remoteIndex);

      // Send our records that remote needs
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

      // Request records we need from remote
      if (neededFromRemote.isNotEmpty) {
        final requestPayload = jsonEncode({
          'type': 'p2p_sync_request',
          'keys': neededFromRemote,
        });
        await _sendEncryptedPayload(endpointId, requestPayload);
      }

      // If we have nothing to exchange, we're done
      if (neededFromRemote.isEmpty && neededFromLocal.isEmpty) {
        _updateState(_state.copyWith(
          status: P2PSyncStatus.completed,
          sentRecords: sentCount,
          receivedRecords: 0,
        ));
      } else {
        // Wait for remote to respond with records
        // State will be updated in _handleSyncData
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

      if (keys.isEmpty) return;

      // Fetch and send requested records
      final records = engine.fetchRecords(keys);
      final recordsPayload = jsonEncode({
        'type': 'p2p_sync_data',
        'records': engine.serializeRecords(records),
      });
      await _sendEncryptedPayload(endpointId, recordsPayload);
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

      // Apply remote records with LWW conflict resolution
      final result = await engine.applyRemoteRecords(records);

      _updateState(_state.copyWith(
        status: P2PSyncStatus.completed,
        sentRecords: _state.sentRecords,
        receivedRecords: result.receivedRecords,
        lastSyncAt: result.syncTimestamp,
      ));

      // Save sync timestamp
      await engine.saveLastSyncTimestamp(result.syncTimestamp);
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
    // Sync acknowledged by remote
    _updateState(_state.copyWith(
      status: P2PSyncStatus.completed,
    ));
  }

  void confirmSync() {
    if (!_state.awaitingConfirmation) return;

    _updateState(_state.copyWith(
      awaitingConfirmation: false,
      pendingConfirmationDeviceName: null,
      pendingConfirmationDeviceId: null,
      status: P2PSyncStatus.sessionEstablished,
    ));
  }

  void rejectSync() {
    if (!_state.awaitingConfirmation) return;
    _updateState(_state.copyWith(
      awaitingConfirmation: false,
      pendingConfirmationDeviceName: null,
      pendingConfirmationDeviceId: null,
      status: P2PSyncStatus.idle,
    ));
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
    _backgroundTimer?.cancel();
    _backgroundTimer =
        Timer.periodic(_backgroundInterval, (_) => _backgroundSyncCycle());
    _updateState(_state.copyWith(isBackgroundSyncActive: true));
  }

  void stopBackgroundSync() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _updateState(_state.copyWith(isBackgroundSyncActive: false));
  }

  Future<void> _backgroundSyncCycle() async {
    if (_isSyncing) return;
    final associations = await _security.getAllAssociations();
    if (associations.isEmpty) return;

    final permResult =
        await BluetoothPermissionService.checkAndRequestPermissions();
    if (!permResult.allGranted) return;

    _isSyncing = true;
    _updateState(_state.copyWith(status: P2PSyncStatus.discovering));

    try {
      await _nearby.startDiscovery(
        'CH_Sync',
        Strategy.P2P_CLUSTER,
        onEndpointFound: (endpointId, name, serviceId) {
          if (!name.startsWith('CH_')) return;
          final deviceId = _extractDeviceId(name);
          if (deviceId == null) return;

          Future(() async {
            final assoc = await _security.getAssociation(deviceId);
            if (assoc != null && assoc.isValid) {
              if (_state.role == P2PSyncRole.mioDispositivo) {
                _nearby.requestConnection(
                  'CH_Sync',
                  endpointId,
                  onConnectionInitiated: _onConnectionInitiated,
                  onConnectionResult: _onConnectionResult,
                  onDisconnected: _onDisconnected,
                );
              }
            }
          });
        },
        onEndpointLost: (_) {},
        serviceId: _serviceId,
      );

      await Future.delayed(const Duration(seconds: 15));
      await _nearby.stopDiscovery();
    } catch (_) {
    } finally {
      await _nearby.stopAllEndpoints();
      _isSyncing = false;
      _updateState(_state.copyWith(status: P2PSyncStatus.idle));
    }
  }

  void dispose() {
    _pairingTimeoutTimer?.cancel();
    _backgroundTimer?.cancel();
    stopPairingMode();
    stopBackgroundSync();
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
