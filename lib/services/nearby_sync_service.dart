import 'dart:async';
import 'dart:convert';


import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:nearby_connections/nearby_connections.dart';

import '../core/services/bluetooth_permission_service.dart';
import '../models/association_models.dart';
import 'security_service.dart';
import '../core/storage/local_database.dart';

enum SyncRole { mioDispositivo, altroCatechista, responsabile }

enum NearbySyncStatus { idle, pairing, scanning, connecting, connected, syncing, completed, error }

class NearbySyncState {
  final NearbySyncStatus status;
  final SyncRole role;
  final bool isPairingMode;
  final bool isBackgroundSyncActive;
  final String? errorMessage;
  final String? connectedDeviceId;
  final String? connectedDeviceName;
  final DateTime? lastSyncAt;
  final int sentRecords;
  final int receivedRecords;
  final bool awaitingConfirmation;
  final String? pendingConfirmationDeviceName;

  const NearbySyncState({
    this.status = NearbySyncStatus.idle,
    this.role = SyncRole.mioDispositivo,
    this.isPairingMode = false,
    this.isBackgroundSyncActive = false,
    this.errorMessage,
    this.connectedDeviceId,
    this.connectedDeviceName,
    this.lastSyncAt,
    this.sentRecords = 0,
    this.receivedRecords = 0,
    this.awaitingConfirmation = false,
    this.pendingConfirmationDeviceName,
  });

  NearbySyncState copyWith({
    NearbySyncStatus? status,
    SyncRole? role,
    bool? isPairingMode,
    bool? isBackgroundSyncActive,
    String? errorMessage,
    String? connectedDeviceId,
    String? connectedDeviceName,
    DateTime? lastSyncAt,
    int? sentRecords,
    int? receivedRecords,
    bool? awaitingConfirmation,
    String? pendingConfirmationDeviceName,
    bool clearError = false,
  }) {
    return NearbySyncState(
      status: status ?? this.status,
      role: role ?? this.role,
      isPairingMode: isPairingMode ?? this.isPairingMode,
      isBackgroundSyncActive: isBackgroundSyncActive ?? this.isBackgroundSyncActive,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      connectedDeviceId: connectedDeviceId ?? this.connectedDeviceId,
      connectedDeviceName: connectedDeviceName ?? this.connectedDeviceName,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      sentRecords: sentRecords ?? this.sentRecords,
      receivedRecords: receivedRecords ?? this.receivedRecords,
      awaitingConfirmation: awaitingConfirmation ?? this.awaitingConfirmation,
      pendingConfirmationDeviceName:
          pendingConfirmationDeviceName ?? this.pendingConfirmationDeviceName,
    );
  }
}

class NearbySyncService {
  static final NearbySyncService _instance = NearbySyncService._();
  factory NearbySyncService() => _instance;
  NearbySyncService._();

  final Nearby _nearby = Nearby();
  final AssociationSecurityService _security = AssociationSecurityService();
  final _stateController = StreamController<NearbySyncState>.broadcast();

  final StreamController<Map<String, dynamic>> _syncRequestController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<NearbySyncState> get onStateChanged => _stateController.stream;
  Stream<Map<String, dynamic>> get onSyncRequest => _syncRequestController.stream;

  NearbySyncState _state = const NearbySyncState();
  NearbySyncState get currentState => _state;

  Timer? _backgroundTimer;
  Timer? _pairingTimeoutTimer;
  bool _initialized = false;
  bool _isSyncing = false;
  String? _pendingEndpointId;

  Completer<void>? _pairingCompleter;

  static const Duration _backgroundInterval = Duration(minutes: 5);
  static const Duration _pairingTimeout = Duration(seconds: 120);
  static const String _serviceId = 'ch.catechhub.app';

  void _emitState() => _stateController.add(_state);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
  }

  void _updateState(NearbySyncState newState) {
    _state = newState;
    _emitState();
  }

  Future<void> startPairingMode() async {
    if (!_initialized) await init();

    final permResult = await BluetoothPermissionService.checkAndRequestPermissions();
    if (!permResult.allGranted) {
      _updateState(_state.copyWith(
        status: NearbySyncStatus.error,
        errorMessage: permResult.errorMessage ?? 'Permessi insufficienti per la condivisione.',
      ));
      return;
    }

    _updateState(_state.copyWith(
      isPairingMode: true,
      status: NearbySyncStatus.pairing,
      clearError: true,
    ));

    try {
      final deviceId = await _security.getOrCreateDeviceId();
      final displayName = 'CatechHub_${deviceId.length > 16 ? deviceId.substring(0, 16) : deviceId}';

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
            status: NearbySyncStatus.error,
            errorMessage: 'Tempo scaduto per l\'associazione. Riprova.',
          ));
        }
      });
    } catch (e) {
      _updateState(_state.copyWith(
        status: NearbySyncStatus.error,
        errorMessage: 'Errore avvio pairing: $e',
      ));
    }
  }

  Future<void> stopPairingMode() async {
    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = null;
    _pairingCompleter = null;
    _pendingEndpointId = null;
    try {
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
      await _nearby.stopAllEndpoints();
    } catch (_) {}

    _updateState(_state.copyWith(
      isPairingMode: false,
      status: NearbySyncStatus.idle,
    ));
  }

  void _onEndpointFound(String endpointId, String endpointName, String serviceId) {
    if (!endpointName.startsWith('CatechHub_')) return;
    if (_pendingEndpointId != null) return;

    _pendingEndpointId = endpointId;

    _nearby.requestConnection(
      'CatechHub_Pairing',
      endpointId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
  }

  Future<void> _onConnectionInitiated(
      String endpointId, ConnectionInfo info) async {
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
        status: NearbySyncStatus.connected,
        connectedDeviceId: endpointId,
      ));
    } else {
      _pendingEndpointId = null;
    }
  }

  void _onDisconnected(String endpointId) {
    if (_pendingEndpointId == endpointId) {
      _pendingEndpointId = null;
    }
    if (_state.connectedDeviceId == endpointId) {
      _updateState(_state.copyWith(
        status: NearbySyncStatus.idle,
        connectedDeviceId: null,
        connectedDeviceName: null,
      ));
    }
  }

  String? _extractDeviceId(String endpointName) {
    try {
      if (endpointName.startsWith('CatechHub_')) {
        return endpointName.substring(9);
      }
    } catch (_) {}
    return null;
  }

  String _getLocalDeviceName() {
    try {
      final auth = LocalDatabase.auth();
      final name = auth.get('local_user_name', defaultValue: '') as String;
      if (name.trim().isNotEmpty) return name.trim();
    } catch (_) {}
    return 'Dispositivo CatechHub';
  }

  Future<void> _sendHandshakePayload(String endpointId) async {
    try {
      final deviceId = await _security.getOrCreateDeviceId();
      final deviceName = _getLocalDeviceName();
      final publicKeyHex = await _security.getLocalPublicKeyHex();

      final handshake = QrHandshake(
        deviceId: deviceId,
        deviceName: deviceName,
        publicKeyHex: publicKeyHex,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      await _sendPayload(endpointId, handshake.encode());
    } catch (_) {}
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.bytes == null) return;

    try {
      final message = utf8.decode(payload.bytes!);
      _handleMessage(endpointId, message);
    } catch (e) {
      debugPrint('[NearbySync] Payload decode error: $e');
    }
  }

  Future<void> _handleMessage(String endpointId, String message) async {
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('deviceId') && decoded.containsKey('publicKeyHex')) {
          await _handleHandshake(endpointId, message);
          return;
        }
        final type = decoded['type'] as String?;
        if (type == 'sync_index') {
          await _handleSyncIndex(endpointId, decoded);
          return;
        }
        if (type == 'sync_request') {
          await _handleSyncRequest(endpointId, decoded);
          return;
        }
        if (type == 'sync_data') {
          await _handleSyncData(endpointId, decoded);
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _handleHandshake(String endpointId, String message) async {
    final handshake = QrHandshake.decode(message);
    if (handshake == null || !handshake.isFresh) {
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _pendingEndpointId = null;
      return;
    }

    if (_state.isPairingMode) {
      final existing = await _security.getAssociation(handshake.deviceId);
      if (existing != null) {
        try {
          await _nearby.disconnectFromEndpoint(endpointId);
        } catch (_) {}
        _pendingEndpointId = null;
        return;
      }
    }

    try {
      final sharedSecret = await _security.computeSharedSecretHex(handshake.publicKeyHex);

      final association = DeviceAssociation(
        deviceId: handshake.deviceId,
        deviceName: handshake.deviceName,
        sharedSecretHex: sharedSecret,
        associatedAt: DateTime.now(),
      );

      await _security.saveAssociation(association);

      if (_state.isPairingMode) {
        _updateState(_state.copyWith(
          status: NearbySyncStatus.completed,
          connectedDeviceId: endpointId,
          connectedDeviceName: handshake.deviceName,
        ));

        Future.delayed(const Duration(seconds: 2), () {
          stopPairingMode();
        });
      }
    } catch (e) {
      debugPrint('[NearbySync] Handshake error: $e');
    }
  }

  Future<void> _sendPayload(String endpointId, String data) async {
    try {
      await _nearby.sendBytesPayload(
        endpointId,
        Uint8List.fromList(utf8.encode(data)),
      );
    } catch (_) {}
  }

  Future<void> startBackgroundSync() async {
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer.periodic(_backgroundInterval, (_) {
      _backgroundSyncCycle();
    });
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

    final permResult = await BluetoothPermissionService.checkAndRequestPermissions();
    if (!permResult.allGranted) return;

    _isSyncing = true;
    _updateState(_state.copyWith(status: NearbySyncStatus.scanning));

    try {
      final syncName = 'CatechHub_Sync_${DateTime.now().millisecondsSinceEpoch}';
      final completer = Completer<void>();

      await _nearby.startAdvertising(
        syncName,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );

      await _nearby.startDiscovery(
        syncName,
        Strategy.P2P_CLUSTER,
        onEndpointFound: (endpointId, name, serviceId) {
          if (!name.startsWith('CatechHub_')) return;
          final deviceId = _extractDeviceId(name);
          if (deviceId == null) return;
          Future(() async {
            final assoc = await _security.getAssociation(deviceId);
            if (assoc != null && assoc.isValid) {
              if (!completer.isCompleted) completer.complete();
              _nearby.requestConnection(
                syncName,
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

      await completer.future.timeout(const Duration(seconds: 15), onTimeout: () {});
      await _nearby.stopDiscovery();

      if (_state.role == SyncRole.altroCatechista && _state.awaitingConfirmation == false) {
        _updateState(_state.copyWith(
          awaitingConfirmation: true,
          pendingConfirmationDeviceName: 'Catechista',
          status: NearbySyncStatus.idle,
        ));
        _isSyncing = false;
        return;
      }

      if (_state.role == SyncRole.mioDispositivo && _state.connectedDeviceId != null) {
        await sendLocalIndex(_state.connectedDeviceId!);
      }
    } catch (_) {
    } finally {
      await _nearby.stopAdvertising();
      await _nearby.stopAllEndpoints();
      _isSyncing = false;
      _updateState(_state.copyWith(status: NearbySyncStatus.idle));
    }
  }

  Future<void> _handleSyncIndex(
      String endpointId, Map<String, dynamic> message) async {
    final remoteIndex = message['records'] as List<dynamic>? ?? [];
    final neededRecords = <Map<String, String>>[];

    for (final entry in remoteIndex) {
      final entryMap = entry as Map<String, dynamic>;
      final remoteId = entryMap['id'] as String;
      final remoteBox = entryMap['box'] as String;
      final remoteUpdatedAt = DateTime.tryParse(
            entryMap['updated_at'] as String? ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);

      try {
        final box = Hive.box<Map>(remoteBox);
        final localData = LocalDatabase.toStringDynamicMap(box.get(remoteId));
        if (localData.isNotEmpty) {
          final localUpdatedAt = DateTime.tryParse(
                localData['updatedAt']?.toString() ?? '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          if (remoteUpdatedAt.isAfter(localUpdatedAt)) {
            neededRecords.add({'id': remoteId, 'box': remoteBox});
          }
        } else {
          neededRecords.add({'id': remoteId, 'box': remoteBox});
        }
      } catch (_) {}
    }

    if (neededRecords.isNotEmpty) {
      final request = jsonEncode({
        'type': 'sync_request',
        'ids': neededRecords,
      });

      final sharedSecret = await _getSharedSecretForEndpoint(endpointId);
      if (sharedSecret != null) {
        final encrypted = await _security.encryptPayload(request, sharedSecret);
        await _sendPayload(endpointId, encrypted);
      }
    }
  }

  Future<void> _handleSyncRequest(
      String endpointId, Map<String, dynamic> message) async {
    final sharedSecret = await _getSharedSecretForEndpoint(endpointId);
    if (sharedSecret == null) return;

    try {
      final encrypted = message['payload'] as String? ?? '';
      Map<String, dynamic> data;
      if (encrypted.isNotEmpty) {
        final decrypted = await _security.decryptPayload(encrypted, sharedSecret);
        data = jsonDecode(decrypted) as Map<String, dynamic>;
      } else {
        data = message;
      }

      final ids = data['ids'] as List<dynamic>? ?? [];
      final records = <Map<String, dynamic>>[];

      for (final entry in ids) {
        final entryMap = entry as Map<String, dynamic>;
        final recordId = entryMap['id'] as String;
        final boxName = entryMap['box'] as String;

        try {
          final box = Hive.box<Map>(boxName);
          final rawData = LocalDatabase.toStringDynamicMap(box.get(recordId));
          if (rawData.isNotEmpty) {
            records.add({
              'id': recordId,
              'box': boxName,
              'data': rawData,
              'updated_at': rawData['updatedAt']?.toString() ?? '',
            });
          }
        } catch (_) {}
      }

      if (records.isNotEmpty) {
        final response = jsonEncode({
          'type': 'sync_data',
          'records': records,
        });
        final responseEncrypted =
            await _security.encryptPayload(response, sharedSecret);
        await _sendPayload(endpointId, jsonEncode({
          'type': 'sync_data',
          'payload': responseEncrypted,
        }));
      }
    } catch (_) {}
  }

  Future<void> _handleSyncData(
      String endpointId, Map<String, dynamic> message) async {
    final sharedSecret = await _getSharedSecretForEndpoint(endpointId);
    if (sharedSecret == null) return;

    try {
      final encrypted = message['payload'] as String? ??
          message['encrypted'] as String? ??
          '';
      if (encrypted.isEmpty) {
        final rawRecords = message['records'] as List<dynamic>? ?? [];
        await _applyRawRecords(rawRecords);
        return;
      }

      final decrypted =
          await _security.decryptPayload(encrypted, sharedSecret);
      final data = jsonDecode(decrypted) as Map<String, dynamic>;
      final records = data['records'] as List<dynamic>? ?? [];
      await _applyRawRecords(records);

      _updateState(_state.copyWith(
        receivedRecords: _state.receivedRecords + records.length,
        lastSyncAt: DateTime.now(),
      ));
    } catch (_) {}
  }

  Future<void> _applyRawRecords(List<dynamic> records) async {
    for (final recordData in records) {
      final record = recordData as Map<String, dynamic>;
      final recordId = record['id'] as String;
      final boxName = record['box'] as String;

      try {
        final box = Hive.box<Map>(boxName);
        final localData = LocalDatabase.toStringDynamicMap(box.get(recordId));
        final remoteUpdatedAt = DateTime.tryParse(
              record['updated_at']?.toString() ??
                  record['updatedAt']?.toString() ??
                  '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);

        if (localData.isEmpty && record.containsKey('data')) {
          await box.put(
              recordId, Map<String, dynamic>.from(record['data'] as Map));
        } else if (localData.isNotEmpty) {
          final localUpdatedAt = DateTime.tryParse(
                localData['updatedAt']?.toString() ?? '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          if (remoteUpdatedAt.isAfter(localUpdatedAt)) {
            final merged = Map<String, dynamic>.from(localData);
            if (record.containsKey('data')) {
              merged.addAll(
                  Map<String, dynamic>.from(record['data'] as Map));
            }
            merged['updatedAt'] = remoteUpdatedAt.toIso8601String();
            await box.put(recordId, merged);
          }
        }
      } catch (_) {}
    }
  }

  Future<String?> _getSharedSecretForEndpoint(String endpointId) async {
    final allSecrets = await _security.getAllAssociations();
    for (final assoc in allSecrets) {
      final secret = assoc.sharedSecretHex;
      if (secret.isNotEmpty) return secret;
    }
    return null;
  }

  void confirmSync() {
    if (!_state.awaitingConfirmation) return;
    _updateState(_state.copyWith(
      awaitingConfirmation: false,
      pendingConfirmationDeviceName: null,
    ));
  }

  void rejectSync() {
    if (!_state.awaitingConfirmation) return;
    _updateState(_state.copyWith(
      awaitingConfirmation: false,
      pendingConfirmationDeviceName: null,
      status: NearbySyncStatus.idle,
    ));
  }

  Future<void> setRole(SyncRole role) async {
    if (role == SyncRole.mioDispositivo || role == SyncRole.altroCatechista) {
      _updateState(_state.copyWith(role: role));
    }
  }

  Future<void> sendLocalIndex(String endpointId) async {
    final index = <Map<String, dynamic>>[];
    for (final boxName in _syncableBoxes) {
      try {
        final box = Hive.box<Map>(boxName);
        for (final key in box.keys) {
          final data = LocalDatabase.toStringDynamicMap(box.get(key));
          final updatedAt =
              data['updatedAt']?.toString() ?? data['createdAt']?.toString() ?? '';
          index.add({'id': key.toString(), 'box': boxName, 'updated_at': updatedAt});
        }
      } catch (_) {}
    }

    final sharedSecret = await _getSharedSecretForEndpoint(endpointId);
    if (sharedSecret != null) {
      final payload = jsonEncode({
        'type': 'sync_index',
        'records': index,
      });
      final encrypted = await _security.encryptPayload(payload, sharedSecret);
      await _sendPayload(endpointId, encrypted);
    }
  }

  static const List<String> _syncableBoxes = [
    LocalDatabase.studentsBox,
    LocalDatabase.classesBox,
    LocalDatabase.planningBox,
    LocalDatabase.attendanceBox,
    LocalDatabase.documentsBox,
    LocalDatabase.documentDeliveriesBox,
    LocalDatabase.contactNotesBox,
    LocalDatabase.studentDailyNotesBox,
  ];

  void dispose() {
    _pairingTimeoutTimer?.cancel();
    _backgroundTimer?.cancel();
    stopPairingMode();
    stopBackgroundSync();
    _stateController.close();
    _syncRequestController.close();
  }
}

class ResponsabileSyncManager {
  Future<void> syncAll() async {
    throw UnsupportedError(
      'Funzione Responsabile non ancora implementata.',
    );
  }
}
