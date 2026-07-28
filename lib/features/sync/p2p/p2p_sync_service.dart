import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:cryptography/cryptography.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/services/bluetooth_permission_service.dart';
import '../../../core/storage/local_database.dart';
import 'p2p_security_service.dart';
import 'hive_sync_engine.dart';

enum P2PSyncRole { mioDispositivo, altroCatechista, responsabile }

enum P2PSyncStatus {
  idle,
  pairing,
  discovering,
  advertising,
  pairingAdvertiseOnly,
  pairingDiscoverOnly,
  handshakeSent,
  handshakeReceived,
  pairingVerification,
  sessionEstablished,
  syncing,
  onboardingSync,
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
  final bool authenticatedByRemote;
  final int totalRecordsToExchange;
  final int sentRecordsCount;
  final int receivedRecordsCount;
  final bool largeSyncInProgress;
  final bool awaitingSessionPermission;
  final String? pendingSessionDeviceName;
  final String? expirationWarning;
  final int expiringDevicesCount;

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
    this.authenticatedByRemote = false,
    this.totalRecordsToExchange = 0,
    this.sentRecordsCount = 0,
    this.receivedRecordsCount = 0,
    this.largeSyncInProgress = false,
    this.awaitingSessionPermission = false,
    this.pendingSessionDeviceName,
    this.expirationWarning,
    this.expiringDevicesCount = 0,
  });

  double get syncProgressPercent {
    if (totalRecordsToExchange == 0) return 0;
    return ((sentRecordsCount + receivedRecordsCount) / totalRecordsToExchange)
        .clamp(0.0, 1.0);
  }

  P2PSyncState copyWith({
    bool? authenticatedByRemote,
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
    int? totalRecordsToExchange,
    int? sentRecordsCount,
    int? receivedRecordsCount,
    bool? largeSyncInProgress,
    bool? awaitingSessionPermission,
    String? pendingSessionDeviceName,
    String? expirationWarning,
    int? expiringDevicesCount,
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
      authenticatedByRemote:
          authenticatedByRemote ?? this.authenticatedByRemote,
      totalRecordsToExchange:
          totalRecordsToExchange ?? this.totalRecordsToExchange,
      sentRecordsCount: sentRecordsCount ?? this.sentRecordsCount,
      receivedRecordsCount:
          receivedRecordsCount ?? this.receivedRecordsCount,
      largeSyncInProgress:
          largeSyncInProgress ?? this.largeSyncInProgress,
      awaitingSessionPermission:
          awaitingSessionPermission ?? this.awaitingSessionPermission,
      pendingSessionDeviceName:
          pendingSessionDeviceName ?? this.pendingSessionDeviceName,
      expirationWarning:
          expirationWarning ?? this.expirationWarning,
      expiringDevicesCount:
          expiringDevicesCount ?? this.expiringDevicesCount,
    );
  }
}

class _SyncPhase2 {
  bool indexSent = false;
  bool sendDone = false;
  bool receiveDone = false;
  bool complete = false;

  bool get isComplete => complete;
  bool get isIdle => !indexSent && !sendDone && !receiveDone && !complete;

  void reset() {
    indexSent = false;
    sendDone = false;
    receiveDone = false;
    complete = false;
  }
}

class _PendingHandshakeData {
  final String endpointId;
  final String remoteId;
  final String remoteName;
  final String remoteNonce;
  final P2PSyncRole remoteRole;
  final String? remoteClassId;

  const _PendingHandshakeData({
    required this.endpointId,
    required this.remoteId,
    required this.remoteName,
    required this.remoteNonce,
    required this.remoteRole,
    this.remoteClassId,
  });
}

/// In-memory association data computed from QR scan but not yet committed to Hive.
/// Saved to Hive only after pairing code verification via confirmPairingCode().
class _PendingAssociationData {
  final String deviceId;
  final String deviceName;
  final String publicKeyBase64;
  final String fingerprint;
  final String sharedSecretBase64;

  const _PendingAssociationData({
    required this.deviceId,
    required this.deviceName,
    required this.publicKeyBase64,
    required this.fingerprint,
    required this.sharedSecretBase64,
  });
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
  final _logController = StreamController<void>.broadcast();

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
    if (!_logController.isClosed) {
      _logController.add(null);
    }
  }

  void clearLogs() {
    _syncLogs.clear();
    addLog('INFO', 'Log cancellati dall\'utente');
  }

  Stream<P2PSyncState> get onStateChanged => _stateController.stream;
  Stream<Map<String, dynamic>> get onSyncData => _syncDataController.stream;
  Stream<void> get onLogChanged => _logController.stream;

  P2PSyncState _state = const P2PSyncState();
  P2PSyncState get currentState => _state;

  Timer? _pairingTimeoutTimer;
  Timer? _periodicSyncTimer;
  bool _initialized = false;
  bool _isSyncing = false;
  String? _pendingEndpointId;

  final Map<String, _SyncPhase2> _endpointSyncPhase = {};

  P2PIdentity? _pendingHandshakeIdentity;
  P2PSyncRole? _pendingHandshakeRemoteRole;

  Completer<void>? _pairingCompleter;

  final Map<String, SecretKeyData> _endpointSessionKeys = {};

  bool _continuousModeActive = false;
  final Set<String> _connectedEndpoints = {};
  final Set<String> _nearbyDiscoveredDevices = {};
  final Map<String, String> _nearbyEndpointToDevice = {};
  final Map<String, String> _endpointConnIdMap = {};
  final Set<String> _sessionConfirmedDevices = {};
  bool _restartingEndpoints = false;

  bool _sessionSyncAllowed = false;

  String? _sessionPairingNonce;
  String? _remoteSessionPairingNonce;
  final Map<String, _PendingHandshakeData> _pendingHandshakeData = {};
  final Map<String, _PendingAssociationData> _pendingAssociations = {};

  StreamSubscription<BoxEvent>? _hiveBoxesSub;
  final List<StreamSubscription<BoxEvent>> _boxSubscriptions = [];
  final List<StreamController<BoxEvent>> _boxControllers = [];
  StreamController<BoxEvent>? _mergedController;

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

    addLog('INFO', 'Inizializzazione P2P Sync Service');
    await _security.refreshIdentityName();

    final hasAssociations = await _security.hasValidAssociation();
    addLog('DEBUG', 'Associazioni valide trovate: $hasAssociations');
    if (hasAssociations) {
      _checkExpiringAssociations();
      _startContinuousMode();
    }
  }

  Future<void> _checkExpiringAssociations() async {
    try {
      final associations = await _security.getAllAssociations();
      int nearExpiryCount = 0;
      String? earliestName;
      int minDays = 30;

      for (final assoc in associations) {
        final days = assoc.daysRemaining;
        if (days <= 5 && days > 0) {
          nearExpiryCount++;
          if (days < minDays) {
            minDays = days;
            earliestName = assoc.deviceName;
          }
        }
      }

      if (nearExpiryCount > 0 && earliestName != null) {
        final warning = nearExpiryCount == 1
            ? '$earliestName scade tra $minDays giorni'
            : '$nearExpiryCount dispositivi scadono tra $minDays giorni';
        _updateState(_state.copyWith(
          expirationWarning: warning,
          expiringDevicesCount: nearExpiryCount,
        ));
        addLog('WARN', warning);
      }
    } catch (_) {}
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
    for (final sub in _boxSubscriptions) {
      sub.cancel();
    }
    _boxSubscriptions.clear();
    for (final ctrl in _boxControllers) {
      ctrl.close();
    }
    _boxControllers.clear();
    _mergedController?.close();
    _mergedController = null;
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _nearbyDiscoveredDevices.clear();
    _nearbyEndpointToDevice.clear();
    _endpointSyncPhase.clear();
    _endpointSessionKeys.clear();
    _isSyncing = false;
    _sessionPairingNonce = null;
    _remoteSessionPairingNonce = null;
    try {
      _nearby.stopAdvertising();
      _nearby.stopDiscovery();
    } catch (_) {}
  }

  void resetSessionPermission() {
    _sessionSyncAllowed = false;
    _updateState(_state.copyWith(
      awaitingSessionPermission: false,
      pendingSessionDeviceName: null,
    ));
  }

  void grantSessionPermission() {
    _sessionSyncAllowed = true;
    addLog('INFO', 'Permesso sessione concesso');
    _updateState(_state.copyWith(
      awaitingSessionPermission: false,
      pendingSessionDeviceName: null,
    ));
  }

  void denySessionPermission() {
    _sessionSyncAllowed = false;
    addLog('INFO', 'Permesso sessione negato');
    _updateState(_state.copyWith(
      awaitingSessionPermission: false,
      pendingSessionDeviceName: null,
      isBackgroundSyncActive: false,
    ));
    _stopContinuousMode();
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
      if (entry.value.indexSent && !entry.value.complete) {
        entry.value.reset();
        _isSyncing = false;
        addLog('WARN', 'Sync timeout per ${entry.key}, ripristino');
      }
    }

    if (_isSyncing) return;

    final endpoints = _connectedEndpoints.toList();
    if (endpoints.isNotEmpty) {
      addLog('DEBUG', 'Periodic sync con ${endpoints.first}');
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
      addLog('DEBUG', 'Avvio advertising come ${identity.deviceId}');
      await _nearby.startAdvertising(
        '$_syncPrefix${identity.deviceId}',
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
      addLog('DEBUG', 'Advertising avviato con successo');
    } catch (e) {
      addLog('WARN', 'Errore advertising: $e, riprovo tra 3s');
      Future.delayed(const Duration(seconds: 3), _startAdvertising);
    }
  }

  Future<void> _startDiscovery() async {
    if (!_continuousModeActive) return;
    try {
      addLog('DEBUG', 'Avvio discovery per $_syncPrefix');
      await _nearby.startDiscovery(
        _syncPrefix,
        Strategy.P2P_CLUSTER,
        onEndpointFound: (endpointId, name, serviceId) {
          addLog('DEBUG', 'Endpoint trovato: $name ($endpointId)');
          if (!name.startsWith(_syncPrefix)) return;
          final deviceId = _extractDeviceId(name);
          if (deviceId == null) return;

          _nearbyEndpointToDevice[endpointId] = deviceId;
          _nearbyDiscoveredDevices.add(deviceId);
          _updateNearbyCount();

          Future(() async {
            if (_connectedEndpoints.contains(endpointId)) {
              addLog('DEBUG', '  già connesso a $endpointId');
              return;
            }
            if (_endpointConnIdMap.containsValue(deviceId)) {
              addLog('DEBUG', '  già connesso a $deviceId');
              return;
            }

            final assoc = await _security.getAssociation(deviceId);
            if (assoc != null && assoc.isValid) {
              if (!_sessionSyncAllowed && _state.role == P2PSyncRole.altroCatechista) {
                addLog('DEBUG', '  permesso sessione non concesso per $deviceId');
                _updateState(_state.copyWith(
                  awaitingSessionPermission: true,
                  pendingSessionDeviceName: assoc.deviceName,
                ));
                return;
              }
              addLog('DEBUG', '  associazione valida, richiedo connessione a $deviceId');
              await _nearby.requestConnection(
                '$_syncPrefix${assoc.deviceId}',
                endpointId,
                onConnectionInitiated: _onConnectionInitiated,
                onConnectionResult: _onConnectionResult,
                onDisconnected: _onDisconnected,
              );
            } else {
              addLog('DEBUG', '  nessuna associazione valida per $deviceId');
            }
          });
        },
        onEndpointLost: (endpointId) {
          addLog('DEBUG', 'Endpoint perso: $endpointId');
          final deviceId = _nearbyEndpointToDevice.remove(endpointId);
          if (deviceId != null) {
            _nearbyDiscoveredDevices.remove(deviceId);
          }
          _updateNearbyCount();
        },
        serviceId: _serviceId,
      );
      addLog('DEBUG', 'Discovery avviato con successo');
    } catch (e) {
      addLog('WARN', 'Errore discovery: $e, riprovo tra 3s');
      Future.delayed(const Duration(seconds: 3), _startDiscovery);
    }
  }

  Future<void> _updateNearbyCount() async {
    int associatedCount = 0;
    for (final deviceId in _nearbyDiscoveredDevices) {
      final assoc = await _security.getAssociation(deviceId);
      if (assoc != null) associatedCount++;
    }
    _updateState(_state.copyWith(
      nearbyAssociationsCount: associatedCount,
      isDataUpToDate: _state.lastSyncAt != null &&
          DateTime.now().difference(_state.lastSyncAt!).inSeconds < 60,
    ));
  }

  void _scheduleReconnectCycle() {
    if (!_continuousModeActive) return;
    Future.delayed(_reconnectDelay, () {
      if (!_continuousModeActive) return;
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
        if (!_sessionSyncAllowed && _state.role == P2PSyncRole.altroCatechista) {
          _updateState(_state.copyWith(
            awaitingSessionPermission: true,
            pendingSessionDeviceName: assoc.deviceName,
          ));
          continue;
        }
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
    for (final sub in _boxSubscriptions) {
      sub.cancel();
    }
    _boxSubscriptions.clear();
    for (final ctrl in _boxControllers) {
      ctrl.close();
    }
    _boxControllers.clear();
    _mergedController?.close();
    _mergedController = null;

    addLog('DEBUG', 'Avvio osservazione modifiche locali');
    for (final boxName in HiveSyncEngine.syncableBoxes.keys) {
      try {
        final box = Hive.box<Map>(boxName);
        final ctrl = StreamController<BoxEvent>.broadcast();
        _boxControllers.add(ctrl);
        final sub = box.watch().listen((event) {
          if (!ctrl.isClosed) ctrl.add(event);
        });
        _boxSubscriptions.add(sub);
      } catch (_) {}
    }
    if (_boxControllers.isEmpty) {
      addLog('WARN', 'Nessun box Hive disponibile per watch');
      return;
    }
    addLog('DEBUG', 'Watch attivato su ${_boxControllers.length} box Hive');

    DateTime _lastChangeEmit = DateTime.now();
    _mergedController = StreamController<BoxEvent>.broadcast();
    for (final ctrl in _boxControllers) {
      ctrl.stream.listen((event) {
        if (_mergedController != null && !_mergedController!.isClosed) {
          _mergedController!.add(event);
        }
      });
    }
    _hiveBoxesSub = _mergedController!.stream.listen((event) {
      final now = DateTime.now();
      if (now.difference(_lastChangeEmit).inMilliseconds >= 500) {
        _lastChangeEmit = now;
        _onLocalDataChanged();
      }
    });
  }

  Future<void> _onLocalDataChanged() async {
    if (_connectedEndpoints.isEmpty) return;
    if (_isSyncing) {
      addLog('DEBUG', 'Modifica locale ignorata: sync in corso');
      return;
    }

    final engine = HiveSyncEngine();
    final lastSync = await engine.getLastSyncTimestamp();
    final modified = engine.extractModifiedRecords(lastSync);
    if (modified.isEmpty) {
      addLog('DEBUG', 'Modifica locale rilevata ma nessun nuovo record');
      return;
    }
    addLog('INFO', 'Modifiche locali rilevate: ${modified.length} record da sincronizzare');

    for (final endpointId in _connectedEndpoints.toList()) {
      await _pushIncrementalSync(endpointId, modified);
    }
    await engine.saveLastSyncTimestamp(DateTime.now().toUtc());
  }

  Future<void> _pushIncrementalSync(
      String endpointId, List<SyncRecord> records) async {
    try {
      if (records.isEmpty) return;

      addLog('INFO', 'Invio incrementale: ${records.length} nuovi/modificati record');
      final engine = HiveSyncEngine();
      final recordsPayload = jsonEncode({
        'type': 'p2p_sync_data',
        'records': engine.serializeRecords(records),
      });
      await _sendEncryptedPayload(endpointId, recordsPayload);
      addLog('INFO', 'Invio incrementale completato');
    } catch (e) {
      addLog('ERROR', 'Errore invio incrementale: $e');
    }
  }

  Future<void> setRole(P2PSyncRole role) async {
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
        _syncPrefix,
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
    } finally {
      _restartingEndpoints = false;
    }
  }

  /// Avvia solo advertising (nessun discovery).
  /// Usato dal dispositivo che mostra il QR per primo.
  /// Non invia richieste di connessione, attende solo richieste in entrata.
  Future<void> startPairingAdvertiseOnly() async {
    addLog('INFO', 'Modalità advertising-only avviata (mostra QR, attende)');
    if (!_initialized) await init();

    final permResult =
        await BluetoothPermissionService.checkAndRequestPermissions();
    if (!permResult.allGranted) {
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: permResult.errorMessage ?? 'Permessi insufficienti.',
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
      status: P2PSyncStatus.pairingAdvertiseOnly,
      clearError: true,
      connectedDeviceId: null,
      connectedDeviceName: null,
    ));

    try {
      final identity = await _security.getLocalIdentity();
      final displayName = '$_syncPrefix${identity.deviceId}';

      await _nearby.startAdvertising(
        displayName,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );

      addLog('DEBUG', 'Advertising-only avviato come $displayName');

      _pairingTimeoutTimer = Timer(_pairingTimeout, () {
        if (_state.isPairingMode) {
          stopPairingMode();
          _updateState(_state.copyWith(
            status: P2PSyncStatus.error,
            errorMessage: 'Tempo scaduto: nessun dispositivo si è connesso.',
          ));
        }
      });
    } catch (e) {
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Errore avvio advertising: $e',
      ));
    } finally {
      _restartingEndpoints = false;
    }
  }

  /// Avvia solo discovery per trovare il dispositivo target.
  /// [targetEndpoint] è l'endpoint name (deviceId) ottenuto dal QR code scansionato.
  /// Usato dal dispositivo che scansiona il QR per primo.
  Future<void> startPairingDiscoverOnly(String targetEndpoint) async {
    addLog('INFO', 'Modalità discover-only avviata per trovare $targetEndpoint');
    if (!_initialized) await init();

    final permResult =
        await BluetoothPermissionService.checkAndRequestPermissions();
    if (!permResult.allGranted) {
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: permResult.errorMessage ?? 'Permessi insufficienti.',
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
      status: P2PSyncStatus.pairingDiscoverOnly,
      clearError: true,
      connectedDeviceId: null,
      connectedDeviceName: null,
    ));

    final fullTargetName = '$_syncPrefix$targetEndpoint';

    try {
      await _nearby.startDiscovery(
        _syncPrefix,
        Strategy.P2P_CLUSTER,
        onEndpointFound: (endpointId, name, serviceId) {
          if (!name.startsWith(_syncPrefix)) return;
          addLog('DEBUG', 'Trovato endpoint: $name ($endpointId)');
          if (name != fullTargetName) {
            addLog('DEBUG', 'Ignoro $name, cerco $fullTargetName');
            return;
          }
          if (_pendingEndpointId != null) return;
          _pendingEndpointId = endpointId;

          addLog('INFO', 'Trovato dispositivo target $name, richiedo connessione');
          _nearby.requestConnection(
            '${_syncPrefix}${targetEndpoint}_conn',
            endpointId,
            onConnectionInitiated: _onConnectionInitiated,
            onConnectionResult: _onConnectionResult,
            onDisconnected: _onDisconnected,
          );
        },
        onEndpointLost: (endpointId) {
          addLog('DEBUG', 'Endpoint perso: $endpointId');
        },
        serviceId: _serviceId,
      );

      addLog('DEBUG', 'Discovery avviato per $fullTargetName');

      _pairingTimeoutTimer = Timer(_pairingTimeout, () {
        if (_state.isPairingMode) {
          stopPairingMode();
          _updateState(_state.copyWith(
            status: P2PSyncStatus.error,
            errorMessage: 'Tempo scaduto: dispositivo $targetEndpoint non trovato.',
          ));
        }
      });
    } catch (e) {
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Errore avvio discovery: $e',
      ));
    } finally {
      _restartingEndpoints = false;
    }
  }

  Future<void> stopPairingMode() async {
    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = null;
    _pairingCompleter = null;

    for (final endpointId in _connectedEndpoints.toList()) {
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
    }

    _connectedEndpoints.clear();
    _endpointConnIdMap.clear();
    _endpointSessionKeys.clear();
    _endpointSyncPhase.clear();
    _pendingEndpointId = null;
    _pendingHandshakeIdentity = null;
    _pendingHandshakeRemoteRole = null;
    _nearbyDiscoveredDevices.clear();
    _nearbyEndpointToDevice.clear();
    _sessionConfirmedDevices.clear();
    _pendingHandshakeData.clear();
    _pendingAssociations.clear();
    _restartingEndpoints = false;

    try {
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
    } catch (_) {}

    _updateState(_state.copyWith(
      isPairingMode: false,
      status: P2PSyncStatus.idle,
      connectedDeviceId: null,
      connectedDeviceName: null,
      connectedFingerprint: null,
      isSessionEncrypted: false,
      pairingCode: null,
      remotePairingCode: null,
      errorMessage: null,
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
    addLog('DEBUG', 'Connessione iniziata da $endpointId: ${info.endpointName}');
    if (_state.role == P2PSyncRole.responsabile) {
      addLog('WARN', 'Rifiuto connessione: ruolo responsabile');
      await _nearby.rejectConnection(endpointId);
      return;
    }

    if (!_state.isPairingMode) {
      final deviceId = _extractDeviceId(info.endpointName);
      if (deviceId != null) {
        final association = await _security.getAssociation(deviceId);
        if (association == null || !association.isValid) {
          addLog('WARN', 'Rifiuto connessione: nessuna associazione valida per $deviceId');
          await _nearby.rejectConnection(endpointId);
          return;
        }
        addLog('DEBUG', 'Associazione valida trovata per $deviceId, accetto connessione');
      } else {
        addLog('WARN', 'Rifiuto connessione: impossibile estrarre deviceId');
        await _nearby.rejectConnection(endpointId);
        return;
      }
    } else {
      if (!info.endpointName.startsWith(_syncPrefix)) {
        addLog('WARN', 'Rifiuto connessione pairing: prefisso non valido ${info.endpointName}');
        await _nearby.rejectConnection(endpointId);
        return;
      }
      addLog('DEBUG', 'Modalità pairing: accetto connessione da ${info.endpointName}');
    }
    _pendingEndpointId = endpointId;

    await _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: _onPayloadReceived,
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      addLog('INFO', 'Dispositivo connesso: $endpointId');
      _pendingEndpointId = null;
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
      if (_state.isPairingMode && _connectedEndpoints.isNotEmpty) {
        addLog('WARN',
            'Doppia connessione rifiutata in pairing: $endpointId');
      } else {
        addLog('ERROR', 'Connessione fallita per $endpointId: $status');
        _updateState(_state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: 'Connessione fallita: $status',
        ));
      }
    }
  }

  void _onDisconnected(String endpointId) {
    addLog('INFO', 'Dispositivo disconnesso');
    _connectedEndpoints.remove(endpointId);
    final deviceId = _endpointConnIdMap.remove(endpointId);
    _endpointSessionKeys.remove(endpointId);
    _endpointSyncPhase.remove(endpointId);
    if (_pendingEndpointId == endpointId) {
      _pendingEndpointId = null;
    }
    if (_state.isPairingMode && deviceId != null) {
      if (_pendingAssociations.containsKey(deviceId)) {
        addLog('INFO', 'Associazione pendente rimossa per $deviceId (disconnessione)');
        _pendingAssociations.remove(deviceId);
      }
      _pendingHandshakeData.remove(endpointId);
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

  Future<void> _cleanupEndpoint(String endpointId) async {
    try {
      await _nearby.disconnectFromEndpoint(endpointId);
    } catch (_) {}
    _connectedEndpoints.remove(endpointId);
    _endpointConnIdMap.remove(endpointId);
    _endpointSessionKeys.remove(endpointId);
    _endpointSyncPhase.remove(endpointId);
    if (_pendingEndpointId == endpointId) {
      _pendingEndpointId = null;
    }
  }

  String? _extractDeviceId(String endpointName) {
    try {
      if (endpointName.startsWith(_syncPrefix)) {
        return endpointName.substring(3);
      }
    } catch (_) {}
    return null;
  }

  bool _rolesAreCompatible(P2PSyncRole local, P2PSyncRole remote) {
    return local == remote;
  }

  String _getCurrentClassId() {
    try {
      final box = LocalDatabase.classes();
      const uid = AuthService.localUserId;
      for (final key in box.keys) {
        final data = Map<String, dynamic>.from(box.get(key) as Map);
        final ids = (data['catechistIds'] as List? ?? []).map((e) => e.toString()).toList();
        if (ids.contains(uid)) {
          return key.toString();
        }
      }
    } catch (_) {}
    return '';
  }

  Future<void> _sendHandshakePayload(String endpointId) async {
    try {
      _sessionPairingNonce = P2PSecurityService.secureRandom(16)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final localIdentity = await _security.getLocalIdentity();
      final handshakeMsg = jsonEncode({
        'type': 'p2p_handshake',
        'senderId': localIdentity.deviceId,
        'senderName': localIdentity.deviceName,
        'timestamp':
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'role': _state.role.name,
        'sessionNonce': _sessionPairingNonce,
        'classId': _getCurrentClassId(),
      });
      addLog('DEBUG', 'Invio handshake a $endpointId (nonce: ${_sessionPairingNonce?.substring(0, 8)}...)');
      await _sendPayload(endpointId, handshakeMsg);
      _updateState(_state.copyWith(status: P2PSyncStatus.handshakeSent));
      addLog('DEBUG', 'Handshake inviato a $endpointId');
    } catch (e) {
      addLog('ERROR', 'Errore invio handshake: $e');
    }
  }

  /// Returns the agreed pairing nonce deterministically:
  /// both sides sort the two nonces and pick the first.
  String? _agreedPairingNonce() {
    final a = _sessionPairingNonce;
    final b = _remoteSessionPairingNonce;
    if (a == null && b == null) return null;
    if (a == null) return b;
    if (b == null) return a;
    final sorted = [a, b]..sort();
    return sorted.first;
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.bytes == null) {
      addLog('WARN', 'Payload ricevuto senza bytes da $endpointId');
      return;
    }
    try {
      final rawMessage = utf8.decode(payload.bytes!);
      addLog('DEBUG', 'Payload ricevuto da $endpointId (${rawMessage.length} bytes)');
      _handleMessage(endpointId, rawMessage);
    } catch (e) {
      addLog('ERROR', 'Errore decodifica payload: $e');
    }
  }

  Future<String> _tryDecryptMessage(
      String endpointId, String rawMessage) async {
    final sessionKey = _endpointSessionKeys[endpointId];
    if (sessionKey != null) {
      try {
        final encrypted = P2PEncryptedPayload.decode(rawMessage);
        final decrypted = await _security.decryptPayload(encrypted, sessionKey);
        final wrapper = jsonDecode(decrypted);
        if (wrapper is Map<String, dynamic>) {
          final senderId = wrapper['senderId'] as String?;
          final senderPublicKey = wrapper['senderPublicKey'] as String?;
          final expectedDeviceId = _endpointConnIdMap[endpointId];
          if (senderId != null && expectedDeviceId != null &&
              senderId != expectedDeviceId) {
            addLog('ERROR',
                'Mittente non corrisponde: $senderId vs $expectedDeviceId');
            return rawMessage;
          }
          if (senderPublicKey != null && expectedDeviceId != null) {
            final assoc = await _security.getAssociation(expectedDeviceId);
            if (assoc != null && !P2PSecurityService.publicKeyMatchesAssociation(
                assoc, senderPublicKey)) {
              addLog('ERROR',
                  'Chiave pubblica mittente non corrisponde per $senderId');
              return rawMessage;
            }
          }
          final data = wrapper['data'] as String?;
          if (data != null) return data;
        }
        return wrapper is String ? wrapper : decrypted;
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

      addLog('DEBUG', 'Messaggio ricevuto: $type da $endpointId');

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
        case 'p2p_association_confirmed':
          await _handleAssociationConfirmed(endpointId, decoded);
          break;
        case 'p2p_association_ack':
          addLog('DEBUG', 'ACK associazione ricevuto dal remoto');
          _updateState(_state.copyWith(authenticatedByRemote: true));
          break;
        case 'p2p_ready_for_verification':
          await _handleReadyForVerification(endpointId, decoded);
          break;
        case 'p2p_pairing_rejected':
          await _handlePairingRejected(endpointId, decoded);
          break;
      }
    } catch (e) {
      addLog('ERROR', 'Errore gestione messaggio da $endpointId: $e');
    }
  }

  Future<void> _handleHandshake(
      String endpointId, Map<String, dynamic> message) async {
    addLog('DEBUG', 'Handshake ricevuto da $endpointId');

    final remoteId = message['senderId'] as String?;
    final remoteName = message['senderName'] as String? ?? 'Sconosciuto';

    if (remoteId == null) {
      addLog('WARN', 'Handshake senza senderId da $endpointId');
      await _cleanupEndpoint(endpointId);
      return;
    }

    final association = await _security.getAssociation(remoteId);

    if (association == null && _state.isPairingMode) {
      addLog('DEBUG',
          'Handshake da $remoteName ($remoteId) in pairing mode, nessuna associazione ancora. '
          'Attendo che l\'utente scansioni il QR.');

      final remoteRoleStr = message['role'] as String?;
      final remoteRole = remoteRoleStr != null
          ? P2PSyncRole.values.firstWhere(
              (r) => r.name == remoteRoleStr,
              orElse: () => P2PSyncRole.mioDispositivo,
            )
          : P2PSyncRole.mioDispositivo;

      _remoteSessionPairingNonce = message['sessionNonce'] as String?;
      _endpointConnIdMap[endpointId] = remoteId;
      _connectedEndpoints.add(endpointId);

      _pendingHandshakeData[endpointId] = _PendingHandshakeData(
        endpointId: endpointId,
        remoteId: remoteId,
        remoteName: remoteName,
        remoteNonce: _remoteSessionPairingNonce ?? '',
        remoteRole: remoteRole,
        remoteClassId: message['classId'] as String?,
      );

      _updateState(_state.copyWith(
        status: P2PSyncStatus.sessionEstablished,
        connectedDeviceId: endpointId,
        connectedDeviceName: remoteName,
        isSessionEncrypted: false,
      ));
      return;
    }

    if (association == null) {
      addLog('ERROR', 'Nessuna associazione trovata per $remoteId.');
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Nessuna associazione trovata per $remoteName.',
      ));
      return;
    }
    addLog('DEBUG', 'Handshake da: $remoteName ($remoteId)');

    final remoteRoleStr = message['role'] as String?;
    final remoteRole = remoteRoleStr != null
        ? P2PSyncRole.values.firstWhere(
            (r) => r.name == remoteRoleStr,
            orElse: () => P2PSyncRole.mioDispositivo,
          )
        : P2PSyncRole.mioDispositivo;

    if (!_rolesAreCompatible(_state.role, remoteRole)) {
      addLog('ERROR',
          'Ruoli incompatibili: locale=${_state.role.name} '
          'remoto=${remoteRole.name} con $remoteName');
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Ruoli incompatibili: i due dispositivi devono '
            'avere lo stesso ruolo. Entrambi "mioDispositivo" o '
            'entrambi "altroCatechista".',
      ));
      return;
    }
    addLog('DEBUG',
        'Ruoli compatibili: ${_state.role.name} <-> ${remoteRole.name}');

    final remoteClassId = message['classId'] as String? ?? '';
    final localClassId = _getCurrentClassId();
    if (remoteClassId.isNotEmpty && localClassId.isNotEmpty && remoteClassId != localClassId) {
      addLog('ERROR',
          'Classi diverse: locale=$localClassId remoto=$remoteClassId con $remoteName');
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Classi diverse: impossibile sincronizzare con $remoteName. '
            'La sincronizzazione Bluetooth è consentita solo tra dispositivi della stessa classe.',
      ));
      return;
    }

    final timestamp = message['timestamp'] as int? ?? 0;
    final age = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - timestamp;
    if (age.abs() > 120) {
      addLog('WARN', 'Handshake scaduto per $endpointId (età: ${age.abs()}s), disconnessione');
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      return;
    }

    _remoteSessionPairingNonce = message['sessionNonce'] as String?;
    _endpointConnIdMap[endpointId] = remoteId;
    _connectedEndpoints.add(endpointId);

    final localIdentity = await _security.getLocalIdentity();

    if (!_state.isPairingMode) {
      addLog('DEBUG', 'Handshake: associazione esistente, invio ack cifrato');
      final ack = jsonEncode({
        'type': 'p2p_handshake_ack',
        'senderId': localIdentity.deviceId,
        'senderName': localIdentity.deviceName,
        'role': _state.role.name,
        'sessionNonce': _sessionPairingNonce ?? '',
        'classId': _getCurrentClassId(),
      });
      await _sendEncryptedPayload(endpointId, ack);
      _updateState(_state.copyWith(
        status: P2PSyncStatus.sessionEstablished,
        connectedDeviceId: endpointId,
        connectedDeviceName: remoteName,
        connectedFingerprint: association.fingerprint,
        isSessionEncrypted: true,
      ));

      final iAmInitiator =
          localIdentity.deviceId.compareTo(remoteId) < 0;
      addLog('DEBUG', 'Sono iniziatore: $iAmInitiator');
      if (iAmInitiator) {
        final authRequest = jsonEncode({
          'type': 'p2p_auth_request',
          'deviceId': localIdentity.deviceId,
          'deviceName': localIdentity.deviceName,
        });
        await _sendEncryptedPayload(endpointId, authRequest);
        addLog('DEBUG', 'Auth request inviata a $endpointId');
      }
    } else {
      addLog('DEBUG',
          'Handshake: associazione trovata, calcolo pairing code');

      final sharedSecret = await _security.computeStaticSharedSecret(
          association.publicKeyBase64);

      final ack = jsonEncode({
        'type': 'p2p_handshake_ack',
        'senderId': localIdentity.deviceId,
        'senderName': localIdentity.deviceName,
        'role': _state.role.name,
        'sessionNonce': _sessionPairingNonce ?? '',
        'classId': _getCurrentClassId(),
      });
      await _sendPayload(endpointId, ack);

      if (_state.isPairingMode) {
        final code = P2PSecurityService.computePairingCode(
          sharedSecret,
          sessionNonce: _agreedPairingNonce(),
        );

        _pendingHandshakeIdentity = P2PIdentity(
          deviceId: remoteId,
          deviceName: remoteName,
          username: '',
          publicKeyBase64: association.publicKeyBase64,
          fingerprint: association.fingerprint,
          connectionEndpoint: '',
        );
        _pendingHandshakeRemoteRole = remoteRole;

        addLog('INFO', 'Codice pairing calcolato ma attendo conferma remota');

        _updateState(_state.copyWith(
          status: P2PSyncStatus.sessionEstablished,
          connectedDeviceId: endpointId,
          connectedDeviceName: remoteName,
          connectedFingerprint: association.fingerprint,
          isSessionEncrypted: true,
          pairingCode: code,
        ));
      } else {
        _updateState(_state.copyWith(
          status: P2PSyncStatus.sessionEstablished,
          connectedDeviceId: endpointId,
          connectedDeviceName: remoteName,
          connectedFingerprint: association.fingerprint,
          isSessionEncrypted: true,
        ));
      }
    }
  }

  Future<void> _handleHandshakeAck(
      String endpointId, Map<String, dynamic> message) async {
    addLog('DEBUG', 'Handshake ACK ricevuto da $endpointId');

    final remoteId = message['senderId'] as String?;
    final remoteName = message['senderName'] as String? ?? 'Sconosciuto';

    if (remoteId == null) {
      addLog('WARN', 'Handshake ACK senza senderId da $endpointId');
      return;
    }

    final association = await _security.getAssociation(remoteId);

    if (association == null && _state.isPairingMode) {
      addLog('DEBUG',
          'Handshake ACK da $remoteName ($remoteId) in pairing mode, '
          'nessuna associazione ancora. Attendo scansione QR.');

      final remoteRoleStr = message['role'] as String?;
      final remoteRole = remoteRoleStr != null
          ? P2PSyncRole.values.firstWhere(
              (r) => r.name == remoteRoleStr,
              orElse: () => P2PSyncRole.mioDispositivo,
            )
          : P2PSyncRole.mioDispositivo;

      _remoteSessionPairingNonce =
          message['sessionNonce'] as String? ?? _remoteSessionPairingNonce;
      _endpointConnIdMap[endpointId] = remoteId;
      _connectedEndpoints.add(endpointId);

      _pendingHandshakeData[endpointId] ??= _PendingHandshakeData(
        endpointId: endpointId,
        remoteId: remoteId,
        remoteName: remoteName,
        remoteNonce: _remoteSessionPairingNonce ?? '',
        remoteRole: remoteRole,
        remoteClassId: message['classId'] as String?,
      );
      return;
    }

    if (association == null) {
      addLog('ERROR', 'Nessuna associazione trovata per $remoteId in ACK');
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Nessuna associazione trovata per $remoteName.',
      ));
      return;
    }
    addLog('DEBUG',
        'Handshake ACK da: $remoteName ($remoteId)');

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
          'con $remoteName');
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Ruoli incompatibili: i due dispositivi devono '
            'avere lo stesso ruolo. Entrambi "mioDispositivo" o '
            'entrambi "altroCatechista".',
      ));
      return;
    }

    final remoteClassId = message['classId'] as String? ?? '';
    final localClassId = _getCurrentClassId();
    if (remoteClassId.isNotEmpty && localClassId.isNotEmpty && remoteClassId != localClassId) {
      addLog('ERROR',
          'Classi diverse: locale=$localClassId remoto=$remoteClassId con $remoteName');
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Classi diverse: impossibile sincronizzare con $remoteName. '
            'La sincronizzazione Bluetooth è consentita solo tra dispositivi della stessa classe.',
      ));
      return;
    }

    _endpointConnIdMap[endpointId] = remoteId;
    _connectedEndpoints.add(endpointId);

    if (!_state.isPairingMode) {
      _updateState(_state.copyWith(
        connectedFingerprint: association.fingerprint,
        connectedDeviceName: remoteName,
        isSessionEncrypted: true,
      ));

      final localIdentity = await _security.getLocalIdentity();
      final iAmInitiator =
          localIdentity.deviceId.compareTo(remoteId) < 0;

      if (iAmInitiator) {
        final authRequest = jsonEncode({
          'type': 'p2p_auth_request',
          'deviceId': localIdentity.deviceId,
          'deviceName': localIdentity.deviceName,
        });
        await _sendEncryptedPayload(endpointId, authRequest);
        addLog('DEBUG', 'Auth request inviata a $endpointId');
      }
    } else {
      _remoteSessionPairingNonce =
          message['sessionNonce'] as String? ?? _remoteSessionPairingNonce;
      final sharedSecret = await _security.computeStaticSharedSecret(
        association.publicKeyBase64,
      );
      final code = P2PSecurityService.computePairingCode(
        sharedSecret,
        sessionNonce: _agreedPairingNonce(),
      );

      _pendingHandshakeIdentity = P2PIdentity(
        deviceId: remoteId,
        deviceName: remoteName,
        username: '',
        publicKeyBase64: association.publicKeyBase64,
        fingerprint: association.fingerprint,
        connectionEndpoint: '',
      );
      _pendingHandshakeRemoteRole = remoteRole;

      addLog('INFO', 'Codice pairing calcolato in ACK ma attendo conferma remota');
      _updateState(_state.copyWith(
        status: P2PSyncStatus.sessionEstablished,
        connectedFingerprint: association.fingerprint,
        connectedDeviceName: remoteName,
        isSessionEncrypted: true,
        pairingCode: code,
        remoteDeviceFingerprint: association.fingerprint,
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
          addLog('ERROR', 'MITM detected in _saveAssociationIfNeeded: '
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
          remoteIdentity.publicKeyBase64);

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

  void readyForVerification(String endpointId) async {
    addLog('INFO', 'Pronto per verifica pairing, invio notifica a $endpointId');
    final localIdentity = await _security.getLocalIdentity();
    final ready = jsonEncode({
      'type': 'p2p_ready_for_verification',
      'deviceId': localIdentity.deviceId,
      'deviceName': localIdentity.deviceName,
    });
    await _sendPayload(endpointId, ready);
  }

  Future<void> _handleReadyForVerification(
      String endpointId, Map<String, dynamic> message) async {
    addLog('INFO', 'Notifica pronta per verifica ricevuta dal remoto');

    _pendingHandshakeData.remove(endpointId);

    final remoteId = _endpointConnIdMap[endpointId];
    if (remoteId == null) {
      addLog('WARN', 'Nessun remoteId mappato per $endpointId');
      return;
    }

    String code;
    if (_state.pairingCode != null && _state.status == P2PSyncStatus.sessionEstablished) {
      code = _state.pairingCode!;
      addLog('DEBUG', 'Uso pairing code già calcolato');
    } else {
      final assoc = await _security.getAssociation(remoteId);
      if (assoc != null) {
        code = P2PSecurityService.computePairingCode(
          assoc.sharedSecretBase64,
          sessionNonce: _agreedPairingNonce(),
        );
        addLog('DEBUG', 'Pairing code calcolato da associazione Hive');
      } else {
        final pendingAssoc = _pendingAssociations[remoteId];
        if (pendingAssoc == null) {
          addLog('ERROR', 'Nessuna associazione (né Hive né pending) trovata per $remoteId');
          return;
        }
        code = P2PSecurityService.computePairingCode(
          pendingAssoc.sharedSecretBase64,
          sessionNonce: _agreedPairingNonce(),
        );
        addLog('DEBUG', 'Pairing code calcolato da associazione pendente');
      }
    }

    _updateState(_state.copyWith(
      status: P2PSyncStatus.pairingVerification,
      connectedDeviceId: endpointId,
      pairingCode: code,
    ));
    addLog('INFO', 'Passaggio a pairingVerification dopo notifica remota');
  }

  Future<void> _handlePairingRejected(
      String endpointId, Map<String, dynamic> message) async {
    addLog('INFO', 'Pairing rifiutato dal dispositivo remoto');
    final deviceId = _endpointConnIdMap[endpointId];
    if (deviceId != null) {
      _pendingAssociations.remove(deviceId);
      addLog('INFO', 'Associazione pendente rimossa per $deviceId (rifiuto remoto)');
    }
    _pendingHandshakeData.remove(endpointId);
    try {
      await _nearby.disconnectFromEndpoint(endpointId);
    } catch (_) {}
    _connectedEndpoints.remove(endpointId);
    _endpointConnIdMap.remove(endpointId);
    _endpointSessionKeys.remove(endpointId);
    _pendingEndpointId = null;
    _pendingHandshakeIdentity = null;
    _pendingHandshakeRemoteRole = null;
    _updateState(_state.copyWith(
      status: P2PSyncStatus.error,
      isPairingMode: false,
      connectedDeviceId: null,
      connectedDeviceName: null,
      connectedFingerprint: null,
      isSessionEncrypted: false,
      pairingCode: null,
      remotePairingCode: null,
      errorMessage: message['reason'] as String? ?? 'Associazione annullata dal remoto.',
    ));
  }

  /// Memorizza i dati di un'associazione scansionata dal QR ma non ancora verificata.
  /// L'associazione verrà salvata in Hive solo dopo confirmPairingCode().
  Future<void> storePendingAssociation({
    required String deviceId,
    required String deviceName,
    required String publicKeyBase64,
    required String fingerprint,
    required String sharedSecretBase64,
  }) async {
    addLog('INFO', 'storePendingAssociation per $deviceName ($deviceId)');
    _pendingAssociations[deviceId] = _PendingAssociationData(
      deviceId: deviceId,
      deviceName: deviceName,
      publicKeyBase64: publicKeyBase64,
      fingerprint: fingerprint,
      sharedSecretBase64: sharedSecretBase64,
    );
  }

  /// Completa il pairing dopo che il secondo QR è stato scansionato.
  /// Usa i dati in memoria (_pendingAssociations) invece di Hive,
  /// perché l'associazione non è ancora stata salvata.
  Future<void> completePairingAfterQrScan(String remoteDeviceId) async {
    addLog('INFO', 'completePairingAfterQrScan per $remoteDeviceId');

    String? endpointId;
    String? remoteNonce;
    for (final entry in _pendingHandshakeData.entries.toList()) {
      if (entry.value.remoteId == remoteDeviceId) {
        endpointId = entry.key;
        remoteNonce = entry.value.remoteNonce;
        break;
      }
    }

    if (endpointId == null) {
      for (final entry in _endpointConnIdMap.entries.toList()) {
        if (entry.value == remoteDeviceId) {
          endpointId = entry.key;
          break;
        }
      }
    }

    if (endpointId == null) {
      addLog('ERROR', 'Nessun endpoint trovato per $remoteDeviceId');
      return;
    }

    final pendingAssoc = _pendingAssociations[remoteDeviceId];
    if (pendingAssoc == null) {
      addLog('ERROR', 'Nessun dato associazione pendente per $remoteDeviceId');
      return;
    }

    if (remoteNonce != null) {
      _remoteSessionPairingNonce = remoteNonce;
    }

    final code = P2PSecurityService.computePairingCode(
      pendingAssoc.sharedSecretBase64,
      sessionNonce: _agreedPairingNonce(),
    );

    _pendingHandshakeIdentity = P2PIdentity(
      deviceId: remoteDeviceId,
      deviceName: pendingAssoc.deviceName,
      username: '',
      publicKeyBase64: pendingAssoc.publicKeyBase64,
      fingerprint: pendingAssoc.fingerprint,
      connectionEndpoint: '',
    );

    _pendingHandshakeData.remove(endpointId);

    _updateState(_state.copyWith(
      status: P2PSyncStatus.pairingVerification,
      connectedDeviceId: endpointId,
      connectedDeviceName: pendingAssoc.deviceName,
      connectedFingerprint: pendingAssoc.fingerprint,
      isSessionEncrypted: true,
      pairingCode: code,
      remoteDeviceFingerprint: pendingAssoc.fingerprint,
    ));
    addLog('INFO', 'Codice pairing generato dopo scan secondo QR');

    readyForVerification(endpointId);
  }

  Future<void> _handleAuthRequest(
      String endpointId, Map<String, dynamic> message) async {
    final deviceId = message['deviceId'] as String?;
    final deviceName = message['deviceName'] as String? ?? 'Sconosciuto';
    addLog('INFO', 'Richiesta autenticazione da $deviceName ($deviceId)');

    if (_state.role != P2PSyncRole.altroCatechista) {
      addLog('INFO', 'Auto-accettazione auth per $deviceName (ruolo: ${_state.role.name})');
      final ack = jsonEncode({
        'type': 'p2p_auth_response',
        'accepted': true,
        'deviceId': deviceId,
      });
      await _sendEncryptedPayload(endpointId, ack);
      _updateState(_state.copyWith(authenticatedByRemote: true));
      return;
    }

    if (deviceId != null && _sessionConfirmedDevices.contains(deviceId)) {
      addLog('INFO', 'Auth già confermata per $deviceName, rieinvio risposta');
      final ack = jsonEncode({
        'type': 'p2p_auth_response',
        'accepted': true,
        'deviceId': deviceId,
      });
      await _sendEncryptedPayload(endpointId, ack);
      return;
    }

    addLog('INFO', 'In attesa conferma utente per sincronizzazione con $deviceName');
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
      addLog('WARN', 'Sync rifiutata dal dispositivo remoto');
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Sync rifiutata dal dispositivo remoto.',
      ));
      return;
    }

    addLog('INFO', 'Autenticazione accettata dal remoto, avvio sync');
    _updateState(_state.copyWith(authenticatedByRemote: true));
    await _performBidirectionalSync(endpointId);
  }

  Future<void> _performBidirectionalSync(String endpointId) async {
    final phase = _endpointSyncPhase[endpointId] ??= _SyncPhase2();
    if (!phase.isIdle && !phase.complete) {
      addLog('DEBUG', 'Sync già in corso per $endpointId');
      return;
    }
    phase.reset();
    phase.indexSent = true;
    _isSyncing = true;

    _updateState(_state.copyWith(status: P2PSyncStatus.syncing));
    addLog('INFO', 'Avvio sincronizzazione bidirezionale con $endpointId');

    try {
      final engine = HiveSyncEngine();
      final lastSync = await engine.getLastSyncTimestamp();
      final localIndex = engine.buildLocalIndex();
      addLog('DEBUG',
          'Indice locale costruito: ${localIndex.length} record, lastSync: $lastSync');

      final indexPayload = jsonEncode({
        'type': 'p2p_sync_index',
        'index': localIndex.map((e) => e.toJson()).toList(),
        'since': lastSync.toUtc().toIso8601String(),
      });
      await _sendEncryptedPayload(endpointId, indexPayload);
      addLog('DEBUG', 'Indice sync inviato a $endpointId');
    } catch (e) {
      _isSyncing = false;
      _endpointSyncPhase.remove(endpointId);
      addLog('ERROR', 'Errore sincronizzazione: $e');
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Errore sincronizzazione: $e',
      ));
    }
  }

  void _checkSyncComplete(String endpointId) {
    final phase = _endpointSyncPhase[endpointId];
    if (phase == null || phase.complete) return;
    if (phase.sendDone && phase.receiveDone) {
      phase.complete = true;
      phase.indexSent = false;
      phase.sendDone = false;
      phase.receiveDone = false;
      _isSyncing = false;
      addLog('INFO', 'Sincronizzazione completata con $endpointId '
          '(${_state.totalRecordsToExchange} record totali)');

      try {
        for (final entry in HiveSyncEngine.syncableBoxes.entries) {
          final box = Hive.box<Map>(entry.key);
          addLog('DEBUG', 'Box ${entry.key}: ${box.length} record');
        }
      } catch (_) {}

      _ensureLocalCatechistInClasses();

      _updateState(_state.copyWith(
        status: P2PSyncStatus.completed,
        lastSyncAt: DateTime.now(),
        totalRecordsToExchange: 0,
        sentRecordsCount: 0,
        receivedRecordsCount: 0,
        largeSyncInProgress: false,
      ));
    }
  }

  void _ensureLocalCatechistInClasses() {
    try {
      final box = LocalDatabase.classes();
      const localId = AuthService.localUserId;
      for (final key in box.keys) {
        final data = LocalDatabase.toStringDynamicMap(box.get(key));
        final ids = (data['catechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        if (!ids.contains(localId)) {
          ids.add(localId);
          data['catechistIds'] = ids;
          box.put(key, data);
          addLog('INFO', 'Aggiunto catechista locale alla classe ${data['name']}');
        }
      }
    } catch (e) {
      addLog('ERROR', 'Errore _ensureLocalCatechistInClasses: $e');
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
      final localIdentity = await _security.getLocalIdentity();
      final wrapped = jsonEncode({
        'senderId': localIdentity.deviceId,
        'senderFingerprint': localIdentity.fingerprint,
        'senderPublicKey': localIdentity.publicKeyBase64,
        'data': plainText,
      });
      final encrypted =
          await _security.encryptPayload(wrapped, sessionKey);
      final payloadStr = encrypted.encode();
      addLog('DEBUG', 'Invio payload cifrato a $endpointId (tipo: ${_extractType(plainText)})');
      await _sendPayload(endpointId, payloadStr);
    } catch (e) {
      addLog('ERROR', 'Errore cifratura payload: $e');
    }
  }

  String _extractType(String plainText) {
    try {
      final map = jsonDecode(plainText);
      return map['type']?.toString() ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  Future<void> _sendPayload(String endpointId, String data) async {
    try {
      addLog('DEBUG', 'Invio ${data.length} bytes a $endpointId');
      await _nearby.sendBytesPayload(
        endpointId,
        Uint8List.fromList(utf8.encode(data)),
      );
    } catch (e) {
      addLog('ERROR', 'Errore invio payload a $endpointId: $e');
    }
  }

  Future<void> _handleSyncIndex(
      String endpointId, Map<String, dynamic> message) async {
    final phase = _endpointSyncPhase[endpointId] ??= _SyncPhase2();
    if (!phase.isIdle && !phase.complete) {
      addLog('DEBUG', 'Sync index ignorato: sync già in corso per $endpointId');
      return;
    }
    phase.reset();
    try {
      phase.indexSent = true;
      final engine = HiveSyncEngine();
      final localIndex = engine.buildLocalIndex();

      final remoteIndexData = message['index'] as List<dynamic>? ?? [];
      final remoteIndex = remoteIndexData
          .map((e) => SyncIndexEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      addLog('INFO',
          'Indice remoto ricevuto: ${remoteIndex.length} record, locale: ${localIndex.length}');

      final neededFromRemote = engine.computeNeededRecords(remoteIndex);
      final neededFromLocal =
          engine.computeNeededRecordsFromLocal(localIndex, remoteIndex);

      final totalToExchange = neededFromRemote.length + neededFromLocal.length;
      addLog('INFO',
          'Scambio necessario: $totalToExchange record '
          '(invio ${neededFromLocal.length}, ricezione ${neededFromRemote.length})');

      _updateState(_state.copyWith(
        totalRecordsToExchange: totalToExchange,
        sentRecordsCount: 0,
        receivedRecordsCount: 0,
        largeSyncInProgress: totalToExchange > 50,
      ));

      if (totalToExchange > 50) {
        addLog('INFO',
            'Sincronizzazione estesa rilevata: $totalToExchange record. '
            'Verrà mostrato l\'avanzamento.');
      }

      if (neededFromLocal.isNotEmpty) {
        final localRecords = engine.fetchRecords(neededFromLocal);
        addLog('INFO', 'Invio ${localRecords.length} record al remoto');
        _updateState(_state.copyWith(
          sentRecordsCount: localRecords.length,
        ));
        final recordsPayload = jsonEncode({
          'type': 'p2p_sync_data',
          'records': engine.serializeRecords(localRecords),
        });
        await _sendEncryptedPayload(endpointId, recordsPayload);
        addLog('INFO', 'Invio completato: ${localRecords.length} record');
      }
      phase.sendDone = true;

      if (neededFromRemote.isNotEmpty) {
        addLog('INFO',
            'Richiesta ${neededFromRemote.length} record dal remoto');
        final requestPayload = jsonEncode({
          'type': 'p2p_sync_request',
          'keys': neededFromRemote,
        });
        await _sendEncryptedPayload(endpointId, requestPayload);
      } else {
        addLog('INFO', 'Nessun record necessario dal remoto');
        phase.receiveDone = true;
        _checkSyncComplete(endpointId);
      }
    } catch (e) {
      addLog('ERROR', 'Errore elaborazione indice: $e');
      _endpointSyncPhase.remove(endpointId);
      _isSyncing = false;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Errore elaborazione indice: $e',
      ));
    }
  }

  Future<void> _handleSyncRequest(
      String endpointId, Map<String, dynamic> message) async {
    final phase = _endpointSyncPhase[endpointId] ??= _SyncPhase2();
    try {
      final engine = HiveSyncEngine();
      final keys = (message['keys'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      addLog('DEBUG', 'Richiesta sync ricevuta per ${keys.length} record');

      if (keys.isEmpty) {
        phase.sendDone = true;
        _checkSyncComplete(endpointId);
        return;
      }

      final records = engine.fetchRecords(keys);
      addLog('INFO', 'Invio ${records.length} record richiesti');
      _updateState(_state.copyWith(
        sentRecordsCount: _state.sentRecordsCount + records.length,
      ));
      final recordsPayload = jsonEncode({
        'type': 'p2p_sync_data',
        'records': engine.serializeRecords(records),
      });
      await _sendEncryptedPayload(endpointId, recordsPayload);
      addLog('INFO', 'Invio ${records.length} record completato');

      phase.sendDone = true;
      _checkSyncComplete(endpointId);
    } catch (e) {
      addLog('ERROR', 'Errore risposta richiesta sync: $e');
      _endpointSyncPhase.remove(endpointId);
      _isSyncing = false;
    }
  }

  Future<void> _handleSyncData(
      String endpointId, Map<String, dynamic> message) async {
    final phase = _endpointSyncPhase[endpointId] ??= _SyncPhase2();
    try {
      final engine = HiveSyncEngine();
      final recordsData = message['records'] as List<dynamic>? ?? [];
      final records = engine.deserializeRecords(recordsData);
      addLog('DEBUG',
          'Dati sync ricevuti: ${records.length} record da applicare');

      final result = await engine.applyRemoteRecords(records);
      addLog('INFO',
          'Applicati ${result.receivedRecords} record, ${result.conflictsResolved} conflitti risolti');

      _updateState(_state.copyWith(
        receivedRecordsCount: _state.receivedRecordsCount + result.receivedRecords,
        largeSyncInProgress:
            _state.totalRecordsToExchange > 50 &&
            _state.sentRecordsCount + _state.receivedRecordsCount + result.receivedRecords <
                _state.totalRecordsToExchange,
      ));

      phase.receiveDone = true;
      addLog('DEBUG', 'ReceiveDone per $endpointId');

      await engine.saveLastSyncTimestamp(result.syncTimestamp);

      final ack = jsonEncode({
        'type': 'p2p_sync_ack',
        'received': result.receivedRecords,
      });
      await _sendEncryptedPayload(endpointId, ack);
      addLog('DEBUG', 'Sync ACK inviato a $endpointId');

      _checkSyncComplete(endpointId);
    } catch (e) {
      addLog('ERROR', 'Errore applicazione dati: $e');
      _endpointSyncPhase.remove(endpointId);
      _isSyncing = false;
      _updateState(_state.copyWith(
        status: P2PSyncStatus.error,
        errorMessage: 'Errore applicazione dati: $e',
      ));
    }
  }

  Future<void> _handleSyncAck(
      String endpointId, Map<String, dynamic> message) async {
    final phase = _endpointSyncPhase[endpointId];
    if (phase == null) {
      addLog('WARN', 'Sync ACK ignorato: nessuna sync attiva per $endpointId');
      return;
    }
    phase.sendDone = true;
    addLog('DEBUG', 'Sync ACK ricevuto per $endpointId, sendDone=true');
    _checkSyncComplete(endpointId);
  }

  Future<void> _handleAssociationConfirmed(
      String endpointId, Map<String, dynamic> message) async {
    addLog('INFO', 'Associazione confermata dal dispositivo remoto');
    final deviceId = message['deviceId'] as String?;
    if (deviceId != null) {
      _sessionConfirmedDevices.add(deviceId);
    }
    _updateState(_state.copyWith(
      status: P2PSyncStatus.completed,
      authenticatedByRemote: true,
    ));

    if (!_continuousModeActive) {
      addLog('INFO', 'Avvio modalità continua dopo conferma remota');
      _startContinuousMode();
    }

    final localIdentity = await _security.getLocalIdentity();
    final ack = jsonEncode({
      'type': 'p2p_association_ack',
      'deviceId': localIdentity.deviceId,
      'deviceName': localIdentity.deviceName,
    });
    await _sendEncryptedPayload(endpointId, ack);
    addLog('INFO', 'Conferma associazione inviata al dispositivo remoto');
  }

  Future<void> finalizeAssociation(String endpointId, String remoteDeviceId) async {
    addLog('INFO', 'Finalizzazione associazione con $remoteDeviceId');
    await _ensureSessionKey(endpointId);
    final localIdentity = await _security.getLocalIdentity();
    final confirmed = jsonEncode({
      'type': 'p2p_association_confirmed',
      'deviceId': localIdentity.deviceId,
      'deviceName': localIdentity.deviceName,
    });
    await _sendEncryptedPayload(endpointId, confirmed);
    _sessionConfirmedDevices.add(remoteDeviceId);
    _updateState(_state.copyWith(
      status: P2PSyncStatus.completed,
      authenticatedByRemote: true,
    ));

    if (!_continuousModeActive) {
      addLog('INFO', 'Avvio modalità continua dopo finalizzazione');
      _startContinuousMode();
    }

    addLog('INFO', 'Associazione finalizzata con $remoteDeviceId');
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
    if (existing == null) {
      final pending = _pendingAssociations[remoteIdentity.deviceId];
      if (pending != null) {
        await _security.registerAndSaveAssociation(
          deviceId: pending.deviceId,
          deviceName: pending.deviceName,
          publicKeyBase64: pending.publicKeyBase64,
          fingerprint: pending.fingerprint,
          sharedSecretBase64: pending.sharedSecretBase64,
          localRole: _state.role.name,
          remoteRole: _pendingHandshakeRemoteRole?.name,
        );
        addLog('INFO', 'Associazione salvata in Hive dopo verifica per ${pending.deviceName}');
      } else {
        await _saveAssociationIfNeeded(remoteIdentity,
            remoteRole: _pendingHandshakeRemoteRole);
      }
    }

    _pendingAssociations.remove(remoteIdentity.deviceId);
    _pendingHandshakeIdentity = null;
    _pendingHandshakeRemoteRole = null;

    _updateState(_state.copyWith(
      status: P2PSyncStatus.sessionEstablished,
      pairingCode: null,
      remotePairingCode: null,
    ));

    await _ensureSessionKey(endpointId);

    final localIdentity = await _security.getLocalIdentity();
    addLog('INFO', 'Codice pairing confermato, invio conferma associazione');
    final confirmed = jsonEncode({
      'type': 'p2p_association_confirmed',
      'deviceId': localIdentity.deviceId,
      'deviceName': localIdentity.deviceName,
    });
    await _sendEncryptedPayload(endpointId, confirmed);

    _updateState(_state.copyWith(
      status: P2PSyncStatus.completed,
      authenticatedByRemote: true,
    ));

    if (!_continuousModeActive) {
      addLog('INFO', 'Avvio modalità continua dopo associazione');
      _startContinuousMode();
    }

    final iAmInitiator = localIdentity.deviceId.compareTo(remoteIdentity.deviceId) < 0;
    if (iAmInitiator) {
      addLog('INFO', 'Avvio sincronizzazione immediata dopo associazione');
      await _performBidirectionalSync(endpointId);
    }

    _ensureLocalCatechistInClasses();

    addLog('INFO', 'Associazione completata con successo');
  }

  Future<void> rejectPairingCode() async {
    if (_state.status != P2PSyncStatus.pairingVerification) return;
    if (_state.connectedDeviceId == null) return;

    final endpointId = _state.connectedDeviceId!;

    try {
      final rejectMsg = jsonEncode({
        'type': 'p2p_pairing_rejected',
        'reason': 'Codice di verifica non corrispondente',
      });
      await _sendPayload(endpointId, rejectMsg);
    } catch (_) {}

    try {
      await _nearby.disconnectFromEndpoint(endpointId);
    } catch (_) {}
    _connectedEndpoints.remove(endpointId);
    _endpointConnIdMap.remove(endpointId);
    _endpointSessionKeys.remove(endpointId);
    _endpointSyncPhase.remove(endpointId);
    _pendingEndpointId = null;
    _pendingHandshakeIdentity = null;
    _pendingHandshakeRemoteRole = null;
    _pendingAssociations.clear();

    _updateState(_state.copyWith(
      status: P2PSyncStatus.idle,
      isPairingMode: false,
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
    if (!_state.awaitingConfirmation) {
      addLog('WARN', 'confirmSync chiamato senza richiesta in sospeso');
      return;
    }

    addLog('INFO', 'Sync confermata dall\'utente');
    final endpointId = _state.connectedDeviceId;
    final confirmedDeviceId = _state.pendingConfirmationDeviceId;

    if (confirmedDeviceId != null) {
      _sessionConfirmedDevices.add(confirmedDeviceId);
      addLog('DEBUG', 'Dispositivo $confirmedDeviceId aggiunto ai confermati');
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
      addLog('DEBUG', 'Risposta auth positiva inviata a $endpointId');
    }
  }

  Future<void> rejectSync() async {
    if (!_state.awaitingConfirmation) {
      addLog('WARN', 'rejectSync chiamato senza richiesta in sospeso');
      return;
    }

    addLog('INFO', 'Sync rifiutata dall\'utente');
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
      addLog('DEBUG', 'Risposta auth negativa inviata a $endpointId');
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

  Future<void> removeAssociationAndCleanup(String deviceId) async {
    addLog('INFO', 'Rimozione associazione e pulizia connessione per $deviceId');
    for (final entry in _endpointConnIdMap.entries.toList()) {
      if (entry.value == deviceId) {
        await _cleanupEndpoint(entry.key);
      }
    }
    if (_endpointConnIdMap.containsValue(deviceId)) {
      _nearbyDiscoveredDevices.remove(deviceId);
      _updateNearbyCount();
    }
    _sessionConfirmedDevices.remove(deviceId);
    await _security.removeAssociation(deviceId);
    addLog('INFO', 'Associazione rimossa per $deviceId');
  }

  Future<void> triggerManualSync() async {
    addLog('INFO', 'Sincronizzazione manuale richiesta');
    if (_connectedEndpoints.isEmpty) {
      addLog('INFO', 'Nessun dispositivo connesso, avvio discovery...');
      if (!_continuousModeActive) {
        _startContinuousMode();
      }
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (_connectedEndpoints.isNotEmpty) break;
      }
    }
    final endpoints = _connectedEndpoints.toList();
    if (endpoints.isNotEmpty) {
      final endpointId = endpoints.first;
      if (_state.status == P2PSyncStatus.sessionEstablished &&
          _state.authenticatedByRemote) {
        addLog('INFO', 'Avvio sincronizzazione con dispositivo connesso');
        await _performBidirectionalSync(endpointId);
      } else {
        addLog('INFO',
            'Connessione presente ma handshake/auth non completato, '
            'attendere...');
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (_state.status == P2PSyncStatus.sessionEstablished &&
              _state.authenticatedByRemote) {
            await _performBidirectionalSync(endpointId);
            return;
          }
        }
        addLog('WARN',
            'Timeout attesa handshake/auth per $endpointId');
      }
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
    _pendingHandshakeData.clear();
    _pendingAssociations.clear();
    _endpointSyncPhase.clear();
    _endpointSessionKeys.clear();
    _initialized = false;
    _stateController.close();
    _syncDataController.close();
    _logController.close();
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