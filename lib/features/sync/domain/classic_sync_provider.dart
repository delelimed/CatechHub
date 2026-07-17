import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/classic_sync_models.dart';
import 'classic_connection_manager.dart';
import 'classic_sync_engine.dart';

/// Bridge tra la logica di dominio (sync engine, connection manager) e la UI.
///
/// CONTESTO PROGETTO:
/// ClassicSyncNotifier è il controller centrale dello stato di
/// sincronizzazione. Utilizza Riverpod (StateNotifier) per gestire:
///
/// 1. Polling background ogni 60 secondi — ricerca automatica di
///    dispositivi fidati nelle vicinanze per la sync automatica.
/// 2. Coda multi-dispositivo — fino a 10 dispositivi, elaborati
///    sequenzialmente (vietato aprire socket RFCOMM in parallelo).
/// 3. Leader Election — confronto lessicografico degli ID dispositivo
///    per stabilire chi fa da server e chi da client.
/// 4. Backoff esponenziale — su fallimenti di connessione (max 5 tentativi).
/// 5. Conferma utente — per ruolo "Altro Catechista", blocca la sync
///    e mostra un prompt di conferma all'utente.
/// 6. Scadenza chiavi — notifica UI per rinnovo pairing ogni 30 giorni.
///
/// Provider esposti:
/// - classicSyncProvider: stato completo della sync
/// - classicPairedProvider: bool se esiste almeno un device associato
/// - classicSyncRoleProvider: ruolo corrente del dispositivo
/// - classicSessionSyncedProvider: se la sessione ha gia sincronizzato
/// - classicBackgroundSyncProvider: se sync background attiva
/// - classicAwaitingConfirmationProvider: se in attesa conferma utente
///
/// Stato della UI di sincronizzazione Bluetooth Classico.
class ClassicSyncUiState {
  final ClassicSyncStatus status;
  final ClassicSyncRole role;
  final String? pairedDeviceName;
  final bool isPaired;
  final bool isKeyExpired;
  final bool isKeyRenewalNeeded;
  final int? daysUntilKeyExpiry;
  final DateTime? keyExpiryDate;
  final DateTime? lastSyncAt;
  final double syncProgress;
  final String? errorMessage;
  final int sentRecords;
  final int receivedRecords;
  final bool sessionSynced;
  final ClassicTransportType transportType;
  final ClassicConnectionState connectionState;
  final List<TrustedDevice> trustedDevices;
  final String? customDeviceName;
  final bool isBackgroundSyncActive;
  final int currentQueueIndex;
  final int totalQueueSize;
  final String? syncingDeviceName;
  final bool awaitingConfirmation;
  final String? pendingConfirmationDeviceId;
  final int pendingChangesCount;

  const ClassicSyncUiState({
    this.status = ClassicSyncStatus.idle,
    this.role = ClassicSyncRole.mioDispositivo,
    this.pairedDeviceName,
    this.isPaired = false,
    this.isKeyExpired = false,
    this.isKeyRenewalNeeded = false,
    this.daysUntilKeyExpiry,
    this.keyExpiryDate,
    this.lastSyncAt,
    this.syncProgress = 0.0,
    this.errorMessage,
    this.sentRecords = 0,
    this.receivedRecords = 0,
    this.sessionSynced = false,
    this.transportType = ClassicTransportType.none,
    this.connectionState = ClassicConnectionState.idle,
    this.trustedDevices = const [],
    this.customDeviceName,
    this.isBackgroundSyncActive = false,
    this.currentQueueIndex = 0,
    this.totalQueueSize = 0,
    this.syncingDeviceName,
    this.awaitingConfirmation = false,
    this.pendingConfirmationDeviceId,
    this.pendingChangesCount = 0,
  });

  ClassicSyncUiState copyWith({
    ClassicSyncStatus? status,
    ClassicSyncRole? role,
    String? pairedDeviceName,
    bool? isPaired,
    bool? isKeyExpired,
    bool? isKeyRenewalNeeded,
    int? daysUntilKeyExpiry,
    DateTime? keyExpiryDate,
    DateTime? lastSyncAt,
    double? syncProgress,
    String? errorMessage,
    int? sentRecords,
    int? receivedRecords,
    bool? sessionSynced,
    ClassicTransportType? transportType,
    ClassicConnectionState? connectionState,
    List<TrustedDevice>? trustedDevices,
    String? customDeviceName,
    bool? isBackgroundSyncActive,
    int? currentQueueIndex,
    int? totalQueueSize,
    String? syncingDeviceName,
    bool? awaitingConfirmation,
    String? pendingConfirmationDeviceId,
    int? pendingChangesCount,
  }) {
    return ClassicSyncUiState(
      status: status ?? this.status,
      role: role ?? this.role,
      pairedDeviceName: pairedDeviceName ?? this.pairedDeviceName,
      isPaired: isPaired ?? this.isPaired,
      isKeyExpired: isKeyExpired ?? this.isKeyExpired,
      isKeyRenewalNeeded: isKeyRenewalNeeded ?? this.isKeyRenewalNeeded,
      daysUntilKeyExpiry: daysUntilKeyExpiry ?? this.daysUntilKeyExpiry,
      keyExpiryDate: keyExpiryDate ?? this.keyExpiryDate,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      syncProgress: syncProgress ?? this.syncProgress,
      errorMessage: errorMessage ?? this.errorMessage,
      sentRecords: sentRecords ?? this.sentRecords,
      receivedRecords: receivedRecords ?? this.receivedRecords,
      sessionSynced: sessionSynced ?? this.sessionSynced,
      transportType: transportType ?? this.transportType,
      connectionState: connectionState ?? this.connectionState,
      trustedDevices: trustedDevices ?? this.trustedDevices,
      customDeviceName: customDeviceName ?? this.customDeviceName,
      isBackgroundSyncActive:
          isBackgroundSyncActive ?? this.isBackgroundSyncActive,
      currentQueueIndex: currentQueueIndex ?? this.currentQueueIndex,
      totalQueueSize: totalQueueSize ?? this.totalQueueSize,
      syncingDeviceName: syncingDeviceName ?? this.syncingDeviceName,
      awaitingConfirmation: awaitingConfirmation ?? this.awaitingConfirmation,
      pendingConfirmationDeviceId:
          pendingConfirmationDeviceId ?? this.pendingConfirmationDeviceId,
      pendingChangesCount: pendingChangesCount ?? this.pendingChangesCount,
    );
  }

  String get statusMessage {
    switch (status) {
      case ClassicSyncStatus.idle:
        return 'Pronto';
      case ClassicSyncStatus.pairing:
        return 'Associazione in corso...';
      case ClassicSyncStatus.scanning:
        return 'Scansione dispositivi...';
      case ClassicSyncStatus.connecting:
        return 'Connessione in corso...';
      case ClassicSyncStatus.connected:
        return 'Connesso';
      case ClassicSyncStatus.syncing:
        final deviceInfo = syncingDeviceName != null
            ? ' con $syncingDeviceName'
            : '';
        if (totalQueueSize > 1) {
          return 'Sincronizzazione$deviceInfo (${currentQueueIndex + 1}/$totalQueueSize)...';
        }
        return 'Sincronizzazione$deviceInfo in corso...';
      case ClassicSyncStatus.completed:
        return 'Sincronizzazione completata';
      case ClassicSyncStatus.error:
        return errorMessage ?? 'Errore sconosciuto';
      case ClassicSyncStatus.keyExpired:
        return 'Chiave scaduta. Associa nuovamente i dispositivi.';
    }
  }

  String get connectionStateLabel {
    switch (connectionState) {
      case ClassicConnectionState.idle:
        return 'Inattivo';
      case ClassicConnectionState.checkingCapabilities:
        return 'Verifica Bluetooth...';
      case ClassicConnectionState.classicServerListening:
        return 'Server Classic in ascolto...';
      case ClassicConnectionState.classicClientConnecting:
        return 'Connessione Classic (Client)...';
      case ClassicConnectionState.connected:
        return 'Connesso via RFCOMM';
      case ClassicConnectionState.error:
        return 'Errore';
    }
  }
}

/// Notifier per la gestione dello stato di sincronizzazione Bluetooth Classico.
///
/// Gestisce:
/// 1. Il polling periodico in background (ogni 60 secondi)
/// 2. I comportamenti basati sul ruolo (mioDispositivo, altroCatechista, responsabile)
/// 3. La coda di sincronizzazione multi-dispositivo (topologia a stella, fino a 10)
/// 4. La Leader Election deterministica per ogni sessione
/// 5. Il backoff esponenziale sui fallimenti di connessione
class ClassicSyncNotifier extends StateNotifier<ClassicSyncUiState> {
  final ClassicConnectionManager _connectionManager =
      ClassicConnectionManager();
  final ClassicSyncEngine _syncEngine = ClassicSyncEngine();

  StreamSubscription? _connStateSubscription;

  Timer? _backgroundTimer;

  List<TrustedDevice> _syncQueue = [];

  final Map<String, int> _backoffCounters = {};

  bool _isSyncInProgress = false;

  Completer<bool>? _confirmationCompleter;

  static const Duration _connectionTimeout = Duration(seconds: 15);
  static const Duration _backgroundPollingInterval = Duration(seconds: 60);
  static const int _maxBackoffCount = 5;

  ClassicSyncNotifier() : super(const ClassicSyncUiState()) {
    _init();
  }

  Future<void> _init() async {
    await loadPairingState();

    _connectionManager.initialize();

    // Avvia il server di sincronizzazione persistente se già associato
    if (state.isPaired) {
      await _connectionManager.startPersistentSyncServer();
    }

    _connStateSubscription =
        _connectionManager.onStateChanged.listen((connState) {
      final syncStatus = _mapConnectionStateToSyncStatus(connState);
      state = state.copyWith(
        connectionState: connState,
        transportType: _connectionManager.activeTransport,
        status: syncStatus,
      );
    });

    _connectionManager.onMessage.listen((msg) {
      if (msg.contains('Fallback') || msg.contains('Timeout')) {
        state = state.copyWith(errorMessage: msg);
      }
    });

    _startBackgroundPolling();
  }

  ClassicSyncStatus _mapConnectionStateToSyncStatus(
      ClassicConnectionState connState) {
    switch (connState) {
      case ClassicConnectionState.idle:
        return ClassicSyncStatus.idle;
      case ClassicConnectionState.checkingCapabilities:
      case ClassicConnectionState.classicClientConnecting:
      case ClassicConnectionState.classicServerListening:
        return ClassicSyncStatus.connecting;
      case ClassicConnectionState.connected:
        return ClassicSyncStatus.connected;
      case ClassicConnectionState.error:
        return ClassicSyncStatus.error;
    }
  }

  // ──────────────────────────────────────────────
  //  POLLING IN BACKGROUND (ogni 60 secondi)
  // ──────────────────────────────────────────────

  void _startBackgroundPolling() {
    _backgroundTimer?.cancel();

    if (!state.isPaired) return;
    if (state.role == ClassicSyncRole.responsabile) return;

    _backgroundTimer = Timer.periodic(_backgroundPollingInterval, (_) {
      _backgroundPollingCycle();
    });
  }

  void _stopBackgroundPolling() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
  }

  Future<void> _backgroundPollingCycle() async {
    if (_isSyncInProgress) return;

    final btEnabled = await BluetoothClassicService.checkBluetoothEnabled();
    if (!btEnabled) return;

    final hasPermissions =
        await BluetoothClassicService.ensureClassicPermissions();
    if (!hasPermissions) return;

    _syncQueue = await ClassicPairingService.getSyncQueue();
    if (_syncQueue.isEmpty) return;

    state = state.copyWith(
      isBackgroundSyncActive: true,
      totalQueueSize: _syncQueue.length,
    );

    await _processSyncQueue();

    state = state.copyWith(
      isBackgroundSyncActive: false,
      currentQueueIndex: 0,
      totalQueueSize: 0,
      syncingDeviceName: null,
    );
  }

  // ──────────────────────────────────────────────
  //  CODA DI SINCRONIZZAZIONE MULTI-DISPOSITIVO
  //  Fino a 10 dispositivi, elaborati sequenzialmente.
  //  È tassativamente vietato aprire piu socket RFCOMM in parallelo.
  // ──────────────────────────────────────────────

  Future<void> _processSyncQueue() async {
    _isSyncInProgress = true;

    try {
      for (var i = 0; i < _syncQueue.length; i++) {
        final device = _syncQueue[i];

        if (!device.isValid) continue;

        final backoff = _backoffCounters[device.deviceId] ?? 0;
        if (backoff >= _maxBackoffCount) {
          _backoffCounters.remove(device.deviceId);
          continue;
        }

        if (backoff > 0) {
          _backoffCounters[device.deviceId] = backoff - 1;
          continue;
        }

        state = state.copyWith(
          currentQueueIndex: i,
          syncingDeviceName: device.cleanDisplayName,
          status: ClassicSyncStatus.scanning,
        );

        // Leader Election per questo dispositivo
        final myDeviceId = await ClassicPairingService.getOrCreateDeviceId();
        final pairingRole =
            ClassicConnectionManager.electRole(myDeviceId, device.deviceId);

        // Tenta la connessione con timeout rigido di 15 secondi
        final connected = await _connectToDevice(
          device: device,
          pairingRole: pairingRole,
        );

        if (!connected) {
          _backoffCounters[device.deviceId] = backoff + 1;
          await _connectionManager.disconnect();
          continue;
        }

        // Connessione stabilita: esegui la sync in base al ruolo
        await _syncWithDeviceByRole(device);

        // Chiudi la connessione per questo dispositivo e passa al successivo
        await _connectionManager.disconnect();
        await _connectionManager.resetPairingEngine();
      }
    } finally {
      _isSyncInProgress = false;
    }
  }

  Future<bool> _connectToDevice({
    required TrustedDevice device,
    required ClassicPairingRole pairingRole,
  }) async {
    final completer = Completer<bool>();

    final connSubscription =
        _connectionManager.onStateChanged.listen((connState) {
      if (connState == ClassicConnectionState.connected) {
        if (!completer.isCompleted) completer.complete(true);
      } else if (connState == ClassicConnectionState.error) {
        if (!completer.isCompleted) completer.complete(false);
      }
    });

    await _connectionManager.connectWithFallback(
      pairingRole: pairingRole,
      peerMacAddress: device.macAddress,
      role: state.role,
    );

    if (_connectionManager.isConnected) {
      connSubscription.cancel();
      return true;
    }

    try {
      final result = await completer.future.timeout(
        _connectionTimeout,
        onTimeout: () => false,
      );
      connSubscription.cancel();
      return result;
    } catch (_) {
      connSubscription.cancel();
      return false;
    }
  }

  /// Esegue la sincronizzazione con un dispositivo in base al ruolo.
  Future<void> _syncWithDeviceByRole(TrustedDevice device) async {
    switch (state.role) {
      case ClassicSyncRole.mioDispositivo:
        await _syncMioDispositivo(device);
        break;
      case ClassicSyncRole.altroCatechista:
        await _syncAltroCatechista(device);
        break;
      case ClassicSyncRole.responsabile:
        await _syncResponsabile(device);
        break;
    }
  }

  /// Sincronizzazione automatica per "Mio Dispositivo".
  Future<void> _syncMioDispositivo(TrustedDevice device) async {
    state = state.copyWith(
      status: ClassicSyncStatus.syncing,
      syncingDeviceName: device.cleanDisplayName,
    );

    try {
      final result = await _syncEngine.performSyncForDevice(
        remoteDeviceId: device.deviceId,
      );

      if (result.success) {
        _backoffCounters.remove(device.deviceId);
      } else {
        final current = _backoffCounters[device.deviceId] ?? 0;
        _backoffCounters[device.deviceId] = current + 1;
      }
    } catch (e) {
      final current = _backoffCounters[device.deviceId] ?? 0;
      _backoffCounters[device.deviceId] = current + 1;
    }
  }

  /// Sincronizzazione con conferma per "Altro Catechista".
  ///
  /// Calcola le differenze tra i timestamp dei record locali e quelli remoti.
  /// Se e solo se vengono rilevate variazioni, blocca il processo e mostra
  /// all'utente un prompt UI di conferma esplicita prima di eseguire il merge.
  Future<void> _syncAltroCatechista(TrustedDevice device) async {
    state = state.copyWith(
      status: ClassicSyncStatus.syncing,
      syncingDeviceName: device.cleanDisplayName,
    );

    try {
      final lastSync = await ClassicPairingService.getLastSyncTimestamp();
      final hasLocalChanges = await _syncEngine.hasPendingChanges(lastSync);

      if (hasLocalChanges) {
        state = state.copyWith(
          awaitingConfirmation: true,
          pendingConfirmationDeviceId: device.deviceId,
          pendingChangesCount: 1,
          status: ClassicSyncStatus.connected,
          errorMessage:
              'Variazioni rilevate. Conferma la sincronizzazione con '
              '${device.cleanDisplayName}.',
        );

        final confirmed = await _waitForConfirmation();

        if (!confirmed) {
          state = state.copyWith(
            awaitingConfirmation: false,
            pendingConfirmationDeviceId: null,
            pendingChangesCount: 0,
          );
          return;
        }
      }

      final result = await _syncEngine.performSyncForDevice(
        remoteDeviceId: device.deviceId,
      );

      state = state.copyWith(
        awaitingConfirmation: false,
        pendingConfirmationDeviceId: null,
        pendingChangesCount: 0,
      );

      if (result.success) {
        _backoffCounters.remove(device.deviceId);
      } else {
        final current = _backoffCounters[device.deviceId] ?? 0;
        _backoffCounters[device.deviceId] = current + 1;
      }
    } catch (e) {
      state = state.copyWith(
        awaitingConfirmation: false,
        pendingConfirmationDeviceId: null,
        pendingChangesCount: 0,
      );
      final current = _backoffCounters[device.deviceId] ?? 0;
      _backoffCounters[device.deviceId] = current + 1;
    }
  }

  /// Blocco per "Responsabile Catechismo".
  ///
  /// Solleva un'eccezione controllata e mostra un placeholder UI pulito,
  /// bloccando l'inizializzazione.
  Future<void> _syncResponsabile(TrustedDevice device) async {
    state = state.copyWith(
      status: ClassicSyncStatus.error,
      errorMessage:
          'Modalita "Responsabile" non ancora implementata. '
          'Seleziona "Mio Dispositivo" o "Altro Catechista" '
          'nelle impostazioni di sincronizzazione.',
    );
  }

  /// Attende la conferma dell'utente per la sincronizzazione.
  Future<bool> _waitForConfirmation() async {
    _confirmationCompleter = Completer<bool>();

    final timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (_confirmationCompleter != null &&
          !_confirmationCompleter!.isCompleted) {
        _confirmationCompleter!.complete(false);
      }
    });

    final result = await _confirmationCompleter!.future;
    timeoutTimer.cancel();
    _confirmationCompleter = null;
    return result;
  }

  /// Conferma la sincronizzazione in attesa (chiamato dalla UI).
  void confirmSync() {
    if (!state.awaitingConfirmation) return;
    if (_confirmationCompleter == null || _confirmationCompleter!.isCompleted) {
      return;
    }

    _confirmationCompleter!.complete(true);
  }

  /// Rifiuta la sincronizzazione in attesa (chiamato dalla UI).
  void rejectSync() {
    if (_confirmationCompleter != null &&
        !_confirmationCompleter!.isCompleted) {
      _confirmationCompleter!.complete(false);
    }

    state = state.copyWith(
      awaitingConfirmation: false,
      pendingConfirmationDeviceId: null,
      pendingChangesCount: 0,
      status: ClassicSyncStatus.idle,
      errorMessage: null,
    );
  }

  // ──────────────────────────────────────────────
  //  METODI PUBBLICI PER LA UI
  // ──────────────────────────────────────────────

  Future<void> loadPairingState() async {
    final trustedDevices =
        await ClassicPairingService.getAllTrustedDevices();
    final role = await ClassicPairingService.getSyncRole();
    final lastSync = await ClassicPairingService.getLastSyncTimestamp();
    final customName = await ClassicPairingService.getCustomDeviceName();
    final daysUntilExpiry =
        await ClassicPairingService.getDaysUntilKeyExpiry();
    final needsRenewal = await ClassicPairingService.hasDevicesNeedingRenewal();
    final isExpired = await ClassicPairingService.isAnyKeyExpired();

    if (trustedDevices.isNotEmpty) {
      final primaryDevice = trustedDevices.first;
      state = state.copyWith(
        isPaired: true,
        pairedDeviceName: primaryDevice.deviceName,
        role: role,
        lastSyncAt: lastSync,
        keyExpiryDate:
            primaryDevice.pairedAt.toUtc().add(const Duration(days: 30)),
        isKeyExpired: isExpired,
        isKeyRenewalNeeded: needsRenewal,
        daysUntilKeyExpiry: daysUntilExpiry,
        trustedDevices: trustedDevices,
        customDeviceName: customName,
      );
    } else {
      state = state.copyWith(
        isPaired: false,
        role: role,
        lastSyncAt: lastSync,
        trustedDevices: [],
        customDeviceName: customName,
        isKeyExpired: false,
        isKeyRenewalNeeded: false,
        daysUntilKeyExpiry: null,
      );
    }
  }

  Future<void> setCustomDeviceName(String name) async {
    await ClassicPairingService.saveCustomDeviceName(name);
    state = state.copyWith(customDeviceName: name);
  }

  Future<void> setSyncRole(ClassicSyncRole role) async {
    if (role == ClassicSyncRole.responsabile) {
      state = state.copyWith(
        status: ClassicSyncStatus.error,
        errorMessage: 'Modalita "Responsabile" non ancora implementata.',
      );
      return;
    }
    await ClassicPairingService.saveSyncRole(role);
    state = state.copyWith(role: role);

    _startBackgroundPolling();
  }

  Future<void> deleteTrustedDevice(String deviceId) async {
    await ClassicPairingService.removeTrustedDevice(deviceId);
    _backoffCounters.remove(deviceId);
    await _connectionManager.resetPairingEngine();
    await loadPairingState();

    _startBackgroundPolling();
  }

  Future<void> deleteAllTrustedDevices() async {
    await ClassicPairingService.removeAllTrustedDevices();
    _backoffCounters.clear();
    _stopBackgroundPolling();
    await _connectionManager.stopPersistentSyncServer();
    await loadPairingState();
  }

  Future<bool> ensureBluetoothReady() async {
    final hasPermissions =
        await BluetoothClassicService.ensureClassicPermissions();
    if (!hasPermissions) return false;
    final isEnabled = await BluetoothClassicService.checkBluetoothEnabled();
    if (!isEnabled) {
      state = state.copyWith(
        status: ClassicSyncStatus.error,
        errorMessage:
            'Bluetooth disattivato. Attivalo dalle impostazioni del telefono.',
      );
      return false;
    }
    return true;
  }

  Future<void> startScanAndSync() async {
    if (!state.isPaired) {
      state = state.copyWith(
        status: ClassicSyncStatus.error,
        errorMessage: 'Nessun dispositivo associato. Esegui prima il pairing.',
      );
      return;
    }

    if (state.role == ClassicSyncRole.responsabile) {
      state = state.copyWith(
        status: ClassicSyncStatus.error,
        errorMessage:
            'Modalita "Responsabile" non ancora implementata. '
            'Seleziona "Mio Dispositivo" o "Altro Catechista" '
            'nelle impostazioni di sincronizzazione.',
      );
      return;
    }

    if (_isSyncInProgress) {
      state = state.copyWith(
        errorMessage: 'Sincronizzazione gia in corso.',
      );
      return;
    }

    if (!await ensureBluetoothReady()) return;

    _syncQueue = await ClassicPairingService.getSyncQueue();
    if (_syncQueue.isEmpty) {
      state = state.copyWith(
        status: ClassicSyncStatus.error,
        errorMessage:
            'Nessun dispositivo fidato trovato per la sincronizzazione.',
      );
      return;
    }

    state = state.copyWith(
      status: ClassicSyncStatus.scanning,
      totalQueueSize: _syncQueue.length,
    );

    await _processSyncQueue();

    state = state.copyWith(
      status: ClassicSyncStatus.completed,
      sessionSynced: true,
      lastSyncAt: DateTime.now().toUtc(),
      syncProgress: 1.0,
      currentQueueIndex: 0,
      totalQueueSize: 0,
      syncingDeviceName: null,
    );
  }

  Future<void> forceSync() async {
    state = state.copyWith(
      sessionSynced: false,
      errorMessage: null,
      awaitingConfirmation: false,
      pendingConfirmationDeviceId: null,
      pendingChangesCount: 0,
    );

    await startScanAndSync();
  }

  Future<void> invalidatePairing() async {
    _stopBackgroundPolling();
    _backoffCounters.clear();
    await ClassicPairingService.invalidateAllPairings();
    await _connectionManager.disconnect();
    await _connectionManager.stopPersistentSyncServer();
    state = const ClassicSyncUiState();
  }

  void resetSession() {
    state = state.copyWith(sessionSynced: false);
  }

  @override
  void dispose() {
    _stopBackgroundPolling();
    _confirmationCompleter?.complete(false);
    _confirmationCompleter = null;
    _connStateSubscription?.cancel();
    _connectionManager.disconnect();
    _connectionManager.stopPersistentSyncServer();
    super.dispose();
  }
}

/// Provider principale per lo stato di sincronizzazione Bluetooth Classico.
final classicSyncProvider =
    StateNotifierProvider<ClassicSyncNotifier, ClassicSyncUiState>((ref) {
  return ClassicSyncNotifier();
});

/// Provider che indica se esiste almeno un dispositivo associato.
final classicPairedProvider = Provider<bool>((ref) {
  return ref.watch(classicSyncProvider).isPaired;
});

/// Provider che espone il ruolo di sincronizzazione corrente.
final classicSyncRoleProvider = Provider<ClassicSyncRole>((ref) {
  return ref.watch(classicSyncProvider).role;
});

/// Provider che indica se la sessione corrente ha gia sincronizzato.
final classicSessionSyncedProvider = Provider<bool>((ref) {
  return ref.watch(classicSyncProvider).sessionSynced;
});

/// Provider che espone il tipo di trasporto attivo.
final classicTransportProvider = Provider<ClassicTransportType>((ref) {
  return ref.watch(classicSyncProvider).transportType;
});

/// Provider che indica se e attiva una sincronizzazione in background.
final classicBackgroundSyncProvider = Provider<bool>((ref) {
  return ref.watch(classicSyncProvider).isBackgroundSyncActive;
});

/// Provider che indica se e in attesa di conferma utente.
final classicAwaitingConfirmationProvider = Provider<bool>((ref) {
  return ref.watch(classicSyncProvider).awaitingConfirmation;
});
