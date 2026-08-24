import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:cryptography/cryptography.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/services/bluetooth_permission_service.dart';
import '../../../core/storage/encrypted_file_storage.dart';
import '../../../core/storage/local_database.dart';
import '../../gdpr/hard_delete_service.dart';
import '../../gdpr/tombstone_model.dart';
import '../../gdpr/tombstone_repository.dart';
import '../../gdpr/tombstone_service.dart';
import '../class_channel_service.dart';
import '../data/association_models.dart';
import '../parish_channel_service.dart';
import 'p2p_security_service.dart';
import 'hive_sync_engine.dart';
import '../../../shared/models/class_model.dart' show generateClassUniqueCode;

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
  associationAccountConfig,
  associationClassInfo,
  associationVerifying,
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
  final bool awaitingCatechistIdChoice;
  final String? pendingCatechistChoiceLocalId;
  final String? pendingCatechistChoiceRemoteId;
  final String? pendingCatechistChoiceRemoteName;
  final String? pendingCatechistChoiceDefault;
  // ── Handshake ordinato (account → classe) + stato sync continuo ───────
  final bool isAssociationHandshakeActive;
  final String associationHandshakeStep;
  final bool continuousSyncVerified;
  final String? remoteSyncState;
  final DateTime? lastSyncStartedAt;
  final DateTime? lastSyncEndedAt;

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
    this.awaitingCatechistIdChoice = false,
    this.pendingCatechistChoiceLocalId,
    this.pendingCatechistChoiceRemoteId,
    this.pendingCatechistChoiceRemoteName,
    this.pendingCatechistChoiceDefault,
    this.isAssociationHandshakeActive = false,
    this.associationHandshakeStep = 'idle',
    this.continuousSyncVerified = false,
    this.remoteSyncState,
    this.lastSyncStartedAt,
    this.lastSyncEndedAt,
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
    bool? awaitingCatechistIdChoice,
    String? pendingCatechistChoiceLocalId,
    String? pendingCatechistChoiceRemoteId,
    String? pendingCatechistChoiceRemoteName,
    String? pendingCatechistChoiceDefault,
    bool? isAssociationHandshakeActive,
    String? associationHandshakeStep,
    bool? continuousSyncVerified,
    String? remoteSyncState,
    DateTime? lastSyncStartedAt,
    DateTime? lastSyncEndedAt,
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
      connectedFingerprint: connectedFingerprint ?? this.connectedFingerprint,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      sentRecords: sentRecords ?? this.sentRecords,
      receivedRecords: receivedRecords ?? this.receivedRecords,
      awaitingConfirmation: awaitingConfirmation ?? this.awaitingConfirmation,
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
      receivedRecordsCount: receivedRecordsCount ?? this.receivedRecordsCount,
      largeSyncInProgress: largeSyncInProgress ?? this.largeSyncInProgress,
      awaitingSessionPermission:
          awaitingSessionPermission ?? this.awaitingSessionPermission,
      pendingSessionDeviceName:
          pendingSessionDeviceName ?? this.pendingSessionDeviceName,
      expirationWarning: expirationWarning ?? this.expirationWarning,
      expiringDevicesCount: expiringDevicesCount ?? this.expiringDevicesCount,
      awaitingCatechistIdChoice:
          awaitingCatechistIdChoice ?? this.awaitingCatechistIdChoice,
      pendingCatechistChoiceLocalId:
          pendingCatechistChoiceLocalId ?? this.pendingCatechistChoiceLocalId,
      pendingCatechistChoiceRemoteId:
          pendingCatechistChoiceRemoteId ?? this.pendingCatechistChoiceRemoteId,
      pendingCatechistChoiceRemoteName:
          pendingCatechistChoiceRemoteName ??
          this.pendingCatechistChoiceRemoteName,
      pendingCatechistChoiceDefault:
          pendingCatechistChoiceDefault ?? this.pendingCatechistChoiceDefault,
      isAssociationHandshakeActive:
          isAssociationHandshakeActive ?? this.isAssociationHandshakeActive,
      associationHandshakeStep:
          associationHandshakeStep ?? this.associationHandshakeStep,
      continuousSyncVerified:
          continuousSyncVerified ?? this.continuousSyncVerified,
      remoteSyncState: remoteSyncState ?? this.remoteSyncState,
      lastSyncStartedAt: lastSyncStartedAt ?? this.lastSyncStartedAt,
      lastSyncEndedAt: lastSyncEndedAt ?? this.lastSyncEndedAt,
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
  final List<String> remoteSharedClassIds;
  final String? remoteCatechistId;
  final bool remoteHasClasses;

  const _PendingHandshakeData({
    required this.endpointId,
    required this.remoteId,
    required this.remoteName,
    required this.remoteNonce,
    required this.remoteRole,
    this.remoteClassId,
    this.remoteSharedClassIds = const [],
    this.remoteCatechistId,
    this.remoteHasClasses = false,
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

/// Chiave di sessione a breve scadenza, valida per una specifica finestra
/// temporale. Viene rigenerata a ogni rotazione (30 minuti).
class _EndpointSessionKey {
  final int windowIndex;
  final SecretKeyData key;

  const _EndpointSessionKey({required this.windowIndex, required this.key});
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
    _syncLogs.add(
      SyncLogEntry(
        timestamp: DateTime.now(),
        level: level,
        message: _redactLog(message),
      ),
    );
    if (_syncLogs.length > _maxLogEntries) {
      _syncLogs.removeAt(0);
    }
    if (!_logController.isClosed) {
      _logController.add(null);
    }
  }

  /// M4 — Privacy nei log: il viewer in-app mostra i log di sync, quindi le
  /// PII (email, telefoni, identificativi di persona) vengono mascherate
  /// PRIMA della registrazione. I nomi/deviceName sono già esclusi dai
  /// messaggi di log (si usano solo gli ID di sessione).
  static String _redactLog(String message) {
    var m = message;
    // Email e telefoni (prefisso internazionale opzionale + >=9 cifre).
    m = m.replaceAllMapped(_emailRe, (match) => '[email]');
    m = m.replaceAllMapped(_phoneRe, (match) => '[telefono]');
    // catechistId e campi anagrafici espliciti nei log.
    m = m
        .replaceAllMapped(
          RegExp(r'(catechistId\s*=\s*)([^\s,\)]+)'),
          (match) => 'catechistId=[nascosto]',
        )
        .replaceAllMapped(
          RegExp(r'(sender(?:FirstName|LastName)\s*=\s*)([^\s,\)]+)'),
          (match) => '${match.group(1)}[nascosto]',
        );
    return m;
  }

  static final _emailRe = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');
  static final _phoneRe = RegExp(r'(?<![\w])\+?\d[\d\s./-]{7,}\d(?!\w)');

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
  Timer? _confirmationTimeoutTimer;
  Timer? _sessionKeyRotationTimer;
  bool _initialized = false;
  bool _isSyncing = false;
  DateTime? _lastSyncStartTime;
  String? _pendingEndpointId;

  final Map<String, _SyncPhase2> _endpointSyncPhase = {};

  P2PIdentity? _pendingHandshakeIdentity;
  P2PSyncRole? _pendingHandshakeRemoteRole;
  String? _pendingHandshakeRemoteCatechistId;

  /// Classi scelte dall'utente durante l'associazione quando il ruolo è
  /// "Altro Catechista". Solo queste classi vengono condivise con il remoto.
  /// Set vuoto = nessuna selezione (si usano le classi comuni).
  /// Viene azzerato al termine della modalità associazione.
  Set<String> _associationSharedClassIds = {};

  /// Profilo anagrafico che il MITTENTE imposta per l'altro catechista
  /// quando il ruolo è "Altro Catechista" (nome, cognome, numero). Viene
  /// trasmesso al dispositivo ricevente così che l'account venga configurato
  /// con i dati inseriti da chi condivide.
  Map<String, String> _associationRemoteProfile = {};

  /// Profilo anagrafico RICEVUTO dall'handshake del dispositivo remoto
  /// (caso "Altro Catechista"): il ricevente lo applica al proprio account
  /// al termine dell'associazione se non ha ancora un profilo configurato.
  Map<String, String>? _pendingHandshakeRemoteProfile;

  /// Anagrafica del PEER (nome+cognome dichiarati nel payload `p2p_identity`).
  /// Usata come FALLBACK per configurare l'account di un dispositivo ricevente
  /// appena configurato quando il mittente non ha fornito un profilo esplicito:
  /// in modalità normale ("Mio Dispositivo") i due dispositivi appartengono
  /// alla stessa persona, quindi l'anagrafica del mittente È quella corretta.
  String _peerFirstName = '';
  String _peerLastName = '';

  /// Mappa endpoint → catechistId del dispositivo remoto, raccolto dall'handshake.
  /// Permette di distinguere un altro dispositivo dello STESSO catechista
  /// (stesso catechistId → sincronizza tutte le classi) da un catechista
  /// diverso (catechistId diverso → solo le classi condivise).
  final Map<String, String> _endpointRemoteCatechistId = {};

  /// Mappa endpoint → true se il dispositivo remoto dichiara di avere già
  /// un'identità (almeno una classe) associata al proprio catechistId.
  final Map<String, bool> _endpointRemoteHasClasses = {};

  /// Mappa endpoint → classi condivise con un catechista diverso.
  final Map<String, Set<String>> _endpointSharedClassIds = {};

  /// Capacità del canale classe (cifratura per-classe) dell'endpoint remoto.
  /// Default `false` = peer non aggiornato → si usa il formato legacy in chiaro.
  final Map<String, bool> _endpointSupportsClassChannel = {};

  /// Capacità del canale parrocchiale globale dell'endpoint remoto.
  final Map<String, bool> _endpointSupportsParishChannel = {};

  /// Stato della risoluzione di un conflitto di catechistId tra due dispositivi
  /// della stessa persona ("Mio Dispositivo"). Quando entrambi i dispositivi
  /// hanno già classi con un catechistId diverso, chiediamo all'utente quale
  /// identità conservare (default: quella della classe che invia).
  String? _pendingChoiceEndpoint;
  P2PIdentity? _pendingChoiceRemoteIdentity;

  // ─── Handshake ordinato (account → classe) ───────────────────────────────
  /// Fase ordinata per endpoint: idle → accountSent → accountConfirmed →
  /// classSent → classConfirmed → verifyingContinuous → completed
  final Map<String, String> _associationHandshakeStep = {};
  final Map<String, Timer> _handshakeTimeoutTimers = {};
  static const Duration _accountAckTimeout = Duration(seconds: 15);
  static const Duration _classAckTimeout = Duration(seconds: 15);
  static const Duration _continuousVerifyTimeout = Duration(seconds: 30);

  // ─── Stato sync continuo (inizio/fine) ─────────────────────────────────
  /// Stato remoto per endpoint: 'idle' | 'syncing'
  final Map<String, String> _remoteSyncState = {};
  final Map<String, Timer> _syncStateWatchdog = {};
  final Map<String, DateTime> _remoteSyncStartAt = {};
  static const Duration _syncStateWatchdogTimeout = Duration(seconds: 60);
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  Timer? _heartbeatTimer;
  bool _continuousSyncVerified = false;

  /// Chiavi di sessione per endpoint, con rotazione per finestra temporale:
  /// per ogni endpoint manteniamo solo le chiavi della finestra corrente e
  /// della finestra precedente (per gestire i messaggi in transito al confine
  /// della rotazione). Ogni chiave scade dopo `sessionKeyRotation`.
  final Map<String, List<_EndpointSessionKey>> _endpointSessionKeys = {};

  /// Chiavi EFIMERE locali per endpoint (forward secrecy). Generata per ogni
  /// connessione, MAI persistita: vive solo in memoria e viene rimossa alla
  /// chiusura della sessione. Se un attaccante compromette in futuro le
  /// chiavi statiche di identità, NON può ricostruire le sessioni passate.
  final Map<String, SimpleKeyPairData> _endpointLocalEphemeral = {};

  /// Chiave pubblica efimera locale (base64) per endpoint: viene precalcolata
  /// alla generazione della coppia efimera ed usata nell'handshake/ack.
  final Map<String, String> _endpointLocalEphemeralPub = {};

  /// Chiave pubblica efimera del peer remoto, ricevuta nell'handshake.
  final Map<String, String> _endpointRemoteEphemeralPub = {};

  /// Chiave pubblica per-associazione del peer remoto (M5), ricevuta nel
  /// payload cifrato `p2p_identity`. Usata per mescolare il DH dedicato
  /// dell'associazione nella chiave di sessione.
  final Map<String, String> _endpointRemoteAssocPub = {};

  bool _continuousModeActive = false;
  final Set<String> _connectedEndpoints = {};
  final Set<String> _nearbyDiscoveredDevices = {};
  final Map<String, String> _nearbyEndpointToDevice = {};
  final Map<String, String> _endpointConnIdMap = {};
  final Set<String> _sessionConfirmedDevices = {};
  final Set<String> _authRequestSent = {};
  bool _restartingEndpoints = false;

  bool _isInitiator = false;

  String? _sessionPairingNonce;
  String? _remoteSessionPairingNonce;
  final Map<String, _PendingHandshakeData> _pendingHandshakeData = {};
  final Map<String, _PendingAssociationData> _pendingAssociations = {};

  /// Pairing codes computed during pairing, keyed by deviceId.
  /// Persists across endpoint reconnections so the PIN stays stable.
  final Map<String, String> _pairingCodesByDeviceId = {};

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
        _updateState(
          _state.copyWith(
            expirationWarning: warning,
            expiringDevicesCount: nearExpiryCount,
          ),
        );
        // M4: il nome del dispositivo (PII) NON viene registrato nei log.
        addLog('WARN', '$nearExpiryCount dispositivo/i in scadenza');
      }
    } catch (_) {}
  }

  Future<void> _startContinuousMode() async {
    if (_continuousModeActive) return;
    _continuousModeActive = true;

    try {
      final associations = await _security.getAllAssociations();
      if (associations.isNotEmpty) {
        final storedRole = associations.first.localRole;
        if (storedRole != null) {
          _updateState(
            _state.copyWith(
              role: P2PSyncRole.values.firstWhere(
                (r) => r.name == storedRole,
                orElse: () => P2PSyncRole.mioDispositivo,
              ),
            ),
          );
        }
      }
    } catch (_) {}

    final permResult =
        await BluetoothPermissionService.checkAndRequestPermissions();
    if (!permResult.allGranted) return;

    _startAdvertising();
    _startDiscovery();
    _watchLocalChanges();
    _scheduleReconnectCycle();
    _startPeriodicSync();
    _startSessionKeyRotation();
    _startHeartbeat();

    _updateState(
      _state.copyWith(isBackgroundSyncActive: true, clearError: true),
    );
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
    _sessionKeyRotationTimer?.cancel();
    _sessionKeyRotationTimer = null;
    _nearbyDiscoveredDevices.clear();
    _nearbyEndpointToDevice.clear();
    _endpointSyncPhase.clear();
    _endpointSessionKeys.clear();
    _endpointLocalEphemeral.clear();
    _endpointLocalEphemeralPub.clear();
    _endpointRemoteEphemeralPub.clear();
    _endpointRemoteAssocPub.clear();
    _isSyncing = false;
    _sessionPairingNonce = null;
    _remoteSessionPairingNonce = null;
    // Pulisci handshake ordinato e watchdog stato sync
    for (final t in _handshakeTimeoutTimers.values) {
      t.cancel();
    }
    _handshakeTimeoutTimers.clear();
    _associationHandshakeStep.clear();
    for (final t in _syncStateWatchdog.values) {
      t.cancel();
    }
    _syncStateWatchdog.clear();
    _remoteSyncState.clear();
    _remoteSyncStartAt.clear();
    _continuousSyncVerified = false;
    _stopHeartbeat();
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

  void _cancelConfirmationTimeout() {
    _confirmationTimeoutTimer?.cancel();
    _confirmationTimeoutTimer = null;
  }

  Future<void> _performPeriodicSync() async {
    if (_connectedEndpoints.isEmpty) return;

    if (_state.awaitingConfirmation || !_state.authenticatedByRemote) {
      addLog('DEBUG', 'Periodic sync saltato: attesa autenticazione');
      return;
    }

    for (final entry in _endpointSyncPhase.entries.toList()) {
      if (entry.value.indexSent && !entry.value.complete) {
        entry.value.reset();
        _isSyncing = false;
        addLog('WARN', 'Sync timeout per ${entry.key}, ripristino');
      }
    }

    if (_isSyncing) return;

    final endpoints = _connectedEndpoints.toList();
    for (final endpointId in endpoints) {
      addLog('DEBUG', 'Periodic sync con $endpointId');
      await _performBidirectionalSync(endpointId);
    }

    _updateState(
      _state.copyWith(
        isDataUpToDate:
            _state.lastSyncAt != null &&
            DateTime.now().difference(_state.lastSyncAt!).inSeconds < 60,
      ),
    );
  }

  Future<void> _startAdvertising() async {
    if (!_continuousModeActive) return;
    try {
      await _nearby.stopAdvertising();
    } catch (_) {}
    try {
      final identity = await _security.getLocalIdentity();
      addLog('DEBUG', 'Avvio advertising come ${identity.deviceId}');
      await _nearby.startAdvertising(
        identity.deviceId,
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
      await _nearby.stopDiscovery();
    } catch (_) {}
    try {
      addLog('DEBUG', 'Avvio discovery per $_syncPrefix');
      await _nearby.startDiscovery(
        _syncPrefix,
        Strategy.P2P_CLUSTER,
        onEndpointFound: (endpointId, name, serviceId) {
          addLog('DEBUG', 'Endpoint trovato: $endpointId');
          if (!name.startsWith(_syncPrefix)) return;
          final deviceId = _extractDeviceId(name);
          if (deviceId == null) return;

          _nearbyEndpointToDevice[endpointId] = deviceId;
          _nearbyDiscoveredDevices.add(deviceId);
          _updateNearbyCount();

Future(() async {
            try {
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
                addLog(
                  'DEBUG',
                  '  associazione valida, richiedo connessione a $deviceId',
                );
                final localIdentity = await _security.getLocalIdentity();
                await _nearby.requestConnection(
                  localIdentity.deviceId,
                  endpointId,
                  onConnectionInitiated: _onConnectionInitiated,
                  onConnectionResult: _onConnectionResult,
                  onDisconnected: _onDisconnected,
                );
              } else {
                addLog('DEBUG', '  nessuna associazione valida per $deviceId');
              }
            } catch (e) {
              addLog('ERROR', 'Errore durante connessione a $deviceId: $e');
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
    _updateState(
      _state.copyWith(
        nearbyAssociationsCount: associatedCount,
        isDataUpToDate:
            _state.lastSyncAt != null &&
            DateTime.now().difference(_state.lastSyncAt!).inSeconds < 60,
      ),
    );
  }

  void _scheduleReconnectCycle() {
    if (!_continuousModeActive) return;
    _doReconnectCycle();
  }

  Future<void> _doReconnectCycle() async {
    if (!_continuousModeActive) return;
    await Future.delayed(_reconnectDelay);
    if (!_continuousModeActive) return;
    await _attemptKnownDeviceConnections();
    _doReconnectCycle();
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
        final localIdentity = await _security.getLocalIdentity();
        await _nearby.requestConnection(
          localIdentity.deviceId,
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

    DateTime lastChangeEmit = DateTime.now();
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
      if (now.difference(lastChangeEmit).inMilliseconds >= 500) {
        lastChangeEmit = now;
        _onLocalDataChanged();
      }
    });
  }

  Future<void> _onLocalDataChanged() async {
    if (_connectedEndpoints.isEmpty) return;
    if (_state.awaitingConfirmation || !_state.authenticatedByRemote) {
      addLog('DEBUG', 'Modifica locale ignorata: attesa autenticazione');
      return;
    }
    if (_isSyncing) {
      if (_lastSyncStartTime != null &&
          DateTime.now().difference(_lastSyncStartTime!).inSeconds > 60) {
        addLog(
          'WARN',
          '_isSyncing bloccato da >60s, reset forzato in _onLocalDataChanged',
        );
        _isSyncing = false;
        _lastSyncStartTime = null;
      } else {
        addLog('DEBUG', 'Modifica locale ignorata: sync in corso');
        return;
      }
    }

    final engine = HiveSyncEngine();
    final lastSync = await engine.getLastSyncTimestamp();

    var sentAny = false;
    for (final endpointId in _connectedEndpoints.toList()) {
      final scope = await _currentSyncScope(endpointId);
      final modified = await engine.extractModifiedRecords(lastSync, scope);
      if (modified.isEmpty) continue;
      addLog(
        'INFO',
        'Modifiche locali rilevate: ${modified.length} record da sincronizzare',
      );
      await _pushIncrementalSync(endpointId, modified);
      sentAny = true;
    }
    if (sentAny) {
      await engine.saveLastSyncTimestamp(DateTime.now().toUtc());
    }
  }

  Future<void> _pushIncrementalSync(
    String endpointId,
    List<SyncRecord> records,
  ) async {
    try {
      if (records.isEmpty) return;

      addLog(
        'INFO',
        'Invio incrementale: ${records.length} nuovi/modificati record',
      );
      final attachmentBytes = await _collectAttachmentBytes(records);
      // H4/H5: passa dal canale classe (niente record studenti in chiaro) e
      // esclude i record tombstoned dal lato invio.
      final channelPayload = await _buildSyncDataPayload(
        records: records,
        endpointId: endpointId,
      );
      final recordsPayload = jsonEncode({
        'type': 'p2p_sync_data',
        ...channelPayload,
        if (attachmentBytes.isNotEmpty) 'attachments': attachmentBytes,
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

  /// Imposta le classi scelte dall'utente per l'associazione corrente.
  /// Quando il ruolo è "Altro Catechista", solo queste classi vengono
  /// sincronizzate con il dispositivo remoto. Set vuoto = tutte le classi
  /// (o, se impossibile, nessuna): la decisione viene presa nello scope.
  Future<void> setAssociationSharedClasses(Set<String>? classIds) async {
    _associationSharedClassIds = (classIds == null || classIds.isEmpty)
        ? {}
        : Set<String>.from(classIds);
    addLog(
      'INFO',
      'Classi condivise associazione: ${_associationSharedClassIds.isEmpty ? 'tutte/nessuna' : _associationSharedClassIds.join(', ')}',
    );
  }

  /// Imposta il profilo anagrafico (nome, cognome, numero) che il mittente
  /// fornisce per l'ALTRO catechista durante l'associazione con ruolo
  /// "Altro Catechista". Il profilo viene trasmesso all'handshake e applicato
  /// dal dispositivo ricevente per configurare il proprio account.
  /// [catechistId] è opzionale: se presente (es. selezione dalla rubrica in
  /// modalità Responsabile), il dispositivo ricevente lo adotta come identità
  /// stabile così da coincidere con le assegnazioni già presenti nelle classi.
  Future<void> setAssociationRemoteProfile({
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? catechistId,
  }) async {
    _associationRemoteProfile = {
      if (firstName != null && firstName.trim().isNotEmpty)
        'firstName': firstName.trim(),
      if (lastName != null && lastName.trim().isNotEmpty)
        'lastName': lastName.trim(),
      if (phoneNumber != null && phoneNumber.trim().isNotEmpty)
        'phoneNumber': phoneNumber.trim(),
      if (catechistId != null && catechistId.trim().isNotEmpty)
        'catechistId': catechistId.trim(),
    };
    // Privacy: il log NON deve contenere il profilo anagrafico (nome, cognome,
    // telefono) del catechista remoto — sono dati personali di un collega e
    // il log è visibile in UI ed esportabile. Si logga solo la presenza.
    addLog(
      'INFO',
      'Profilo remoto associazione configurato '
          '(nome: ${(_associationRemoteProfile['firstName'] ?? '').isNotEmpty}, '
          'cognome: ${(_associationRemoteProfile['lastName'] ?? '').isNotEmpty}, '
          'telefono: ${(_associationRemoteProfile['phoneNumber'] ?? '').isNotEmpty})',
    );
  }

  /// Profilo anagrafico ricevuto dall'handshake del dispositivo remoto
  /// (caso "Altro Catechista"). `null` se il mittente non lo ha fornito.
  Map<String, String>? get pendingRemoteProfile =>
      _pendingHandshakeRemoteProfile == null ||
          _pendingHandshakeRemoteProfile!.isEmpty
      ? null
      : Map.unmodifiable(_pendingHandshakeRemoteProfile!);

  Future<void> startPairingMode() async {
    addLog('INFO', 'Modalità associazione avviata');
    if (!_initialized) await init();

    final permResult =
        await BluetoothPermissionService.checkAndRequestPermissions();
    if (!permResult.allGranted) {
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: permResult.errorMessage ?? 'Permessi insufficienti.',
        ),
      );
      return;
    }

    _restartingEndpoints = true;
    try {
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (_) {}

    _updateState(
      _state.copyWith(
        isPairingMode: true,
        status: P2PSyncStatus.pairing,
        clearError: true,
      ),
    );

    try {
      final identity = await _security.getLocalIdentity();
      final displayName = identity.deviceId;

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
          _updateState(
            _state.copyWith(
              status: P2PSyncStatus.error,
              errorMessage: 'Tempo scaduto per associazione.',
            ),
          );
        }
      });
    } catch (e) {
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: 'Errore avvio pairing: $e',
        ),
      );
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
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: permResult.errorMessage ?? 'Permessi insufficienti.',
        ),
      );
      return;
    }

    _restartingEndpoints = true;
    try {
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (_) {}

    _updateState(
      _state.copyWith(
        isPairingMode: true,
        status: P2PSyncStatus.pairingAdvertiseOnly,
        clearError: true,
        connectedDeviceId: null,
        connectedDeviceName: null,
        pairingCode: null,
        remotePairingCode: null,
        isSessionEncrypted: false,
      ),
    );

    try {
      final identity = await _security.getLocalIdentity();
      final displayName = identity.deviceId;

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
          _updateState(
            _state.copyWith(
              status: P2PSyncStatus.error,
              errorMessage: 'Tempo scaduto: nessun dispositivo si è connesso.',
            ),
          );
        }
      });
    } catch (e) {
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: 'Errore avvio advertising: $e',
        ),
      );
    } finally {
      _restartingEndpoints = false;
    }
  }

  /// Avvia solo discovery per trovare il dispositivo target.
  /// [targetEndpoint] è l'endpoint name (deviceId) ottenuto dal QR code scansionato.
  /// Usato dal dispositivo che scansiona il QR per primo.
  Future<void> startPairingDiscoverOnly(String targetEndpoint) async {
    addLog(
      'INFO',
      'Modalità discover-only avviata per trovare $targetEndpoint',
    );
    if (!_initialized) await init();

    final permResult =
        await BluetoothPermissionService.checkAndRequestPermissions();
    if (!permResult.allGranted) {
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: permResult.errorMessage ?? 'Permessi insufficienti.',
        ),
      );
      return;
    }

    _restartingEndpoints = true;
    try {
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (_) {}

    _updateState(
      _state.copyWith(
        isPairingMode: true,
        status: P2PSyncStatus.pairingDiscoverOnly,
        clearError: true,
        connectedDeviceId: null,
        connectedDeviceName: null,
        pairingCode: null,
        remotePairingCode: null,
        isSessionEncrypted: false,
      ),
    );

    final fullTargetName = targetEndpoint.startsWith(_syncPrefix)
        ? targetEndpoint
        : '$_syncPrefix$targetEndpoint';

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

          addLog(
            'INFO',
            'Trovato dispositivo target $name, richiedo connessione',
          );
          _security.getLocalIdentity().then((identity) {
            _nearby.requestConnection(
              identity.deviceId,
              endpointId,
              onConnectionInitiated: _onConnectionInitiated,
              onConnectionResult: _onConnectionResult,
              onDisconnected: _onDisconnected,
            );
          });
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
          _updateState(
            _state.copyWith(
              status: P2PSyncStatus.error,
              errorMessage:
                  'Tempo scaduto: dispositivo $targetEndpoint non trovato.',
            ),
          );
        }
      });
    } catch (e) {
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: 'Errore avvio discovery: $e',
        ),
      );
    } finally {
      _restartingEndpoints = false;
    }
  }

  Future<void> stopPairingMode() async {
    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = null;
    _pendingEndpointId = null;
    try {
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
      await _nearby.stopAllEndpoints();
    } catch (_) {}

    _connectedEndpoints.clear();
    _endpointConnIdMap.clear();
    _endpointSessionKeys.clear();
    _endpointLocalEphemeral.clear();
    _endpointLocalEphemeralPub.clear();
    _endpointRemoteEphemeralPub.clear();
    _endpointRemoteAssocPub.clear();
    _endpointSyncPhase.clear();
    _pendingEndpointId = null;
    _pendingHandshakeIdentity = null;
    _pendingHandshakeRemoteRole = null;
    _pendingHandshakeRemoteCatechistId = null;
    _sessionConfirmedDevices.clear();
    _pendingHandshakeData.clear();
    _pendingAssociations.clear();
    _restartingEndpoints = false;
    _isSyncing = false;
    _sessionPairingNonce = null;
    _remoteSessionPairingNonce = null;
    _associationSharedClassIds = {};
    _associationRemoteProfile = {};
    _pendingHandshakeRemoteProfile = null;
    _peerFirstName = '';
    _peerLastName = '';
    _endpointRemoteCatechistId.clear();
    _endpointRemoteHasClasses.clear();
    _endpointSharedClassIds.clear();
    _endpointSupportsClassChannel.clear();
    _endpointSupportsParishChannel.clear();
    _pendingChoiceEndpoint = null;
    _pendingChoiceRemoteIdentity = null;
    for (final t in _handshakeTimeoutTimers.values) {
      t.cancel();
    }
    _handshakeTimeoutTimers.clear();
    _associationHandshakeStep.clear();
    for (final t in _syncStateWatchdog.values) {
      t.cancel();
    }
    _syncStateWatchdog.clear();
    _remoteSyncState.clear();
    _remoteSyncStartAt.clear();
    _continuousSyncVerified = false;
    _stopHeartbeat();

    _updateState(
      _state.copyWith(
        isPairingMode: false,
        status: P2PSyncStatus.idle,
        connectedDeviceId: null,
        connectedDeviceName: null,
        connectedFingerprint: null,
        isSessionEncrypted: false,
        awaitingCatechistIdChoice: false,
        pendingCatechistChoiceLocalId: null,
        pendingCatechistChoiceRemoteId: null,
        pendingCatechistChoiceRemoteName: null,
        isAssociationHandshakeActive: false,
        associationHandshakeStep: 'idle',
        continuousSyncVerified: false,
        remoteSyncState: null,
        lastSyncStartedAt: null,
        lastSyncEndedAt: null,
        pendingCatechistChoiceDefault: null,
        pairingCode: null,
        remotePairingCode: null,
        errorMessage: null,
      ),
    );

    if (_continuousModeActive) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (_continuousModeActive && !_state.isPairingMode) {
          _startAdvertising();
          _startDiscovery();
        }
      });
    }
  }

  void _onEndpointFound(
    String endpointId,
    String endpointName,
    String serviceId,
  ) {
    if (!endpointName.startsWith(_syncPrefix)) return;
    if (_pendingEndpointId != null) return;

    _pendingEndpointId = endpointId;

    _security.getLocalIdentity().then((identity) {
      _nearby.requestConnection(
        identity.deviceId,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    });
  }

  Future<void> _onConnectionInitiated(
    String endpointId,
    ConnectionInfo info,
  ) async {
    addLog(
      'DEBUG',
      'Connessione iniziata da $endpointId: ${info.endpointName}',
    );

    if (!_state.isPairingMode) {
      final deviceId = _extractDeviceId(info.endpointName);
      if (deviceId != null) {
        final association = await _security.getAssociation(deviceId);
        if (association == null || !association.isValid) {
          addLog(
            'WARN',
            'Rifiuto connessione: nessuna associazione valida per $deviceId',
          );
          await _nearby.rejectConnection(endpointId);
          return;
        }
        addLog(
          'DEBUG',
          'Associazione valida trovata per $deviceId, accetto connessione',
        );
      } else {
        addLog('WARN', 'Rifiuto connessione: impossibile estrarre deviceId');
        await _nearby.rejectConnection(endpointId);
        return;
      }
    } else {
      if (!info.endpointName.startsWith(_syncPrefix)) {
        addLog(
          'WARN',
          'Rifiuto connessione pairing: prefisso non valido ${info.endpointName}',
        );
        await _nearby.rejectConnection(endpointId);
        return;
      }
      addLog(
        'DEBUG',
        'Modalità pairing: accetto connessione da ${info.endpointName}',
      );
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
      _connectedEndpoints.add(endpointId);
      _sendHandshakePayload(endpointId);
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.sessionEstablished,
          connectedDeviceId: endpointId,
          isSessionEncrypted: false,
        ),
      );
    } else {
      _pendingEndpointId = null;
      if (_state.isPairingMode && _connectedEndpoints.isNotEmpty) {
        addLog('WARN', 'Doppia connessione rifiutata in pairing: $endpointId');
      } else {
        addLog('ERROR', 'Connessione fallita per $endpointId: $status');
        _updateState(
          _state.copyWith(
            status: P2PSyncStatus.error,
            errorMessage: 'Connessione fallita: $status',
          ),
        );
      }
    }
  }

  void _onDisconnected(String endpointId) {
    addLog('INFO', 'Dispositivo disconnesso');
    _connectedEndpoints.remove(endpointId);
    final deviceId = _endpointConnIdMap.remove(endpointId);
    _endpointSessionKeys.remove(endpointId);
    _endpointLocalEphemeral.remove(endpointId);
    _endpointLocalEphemeralPub.remove(endpointId);
    _endpointRemoteEphemeralPub.remove(endpointId);
    _endpointRemoteAssocPub.remove(endpointId);
    _endpointSyncPhase.remove(endpointId);
    _authRequestSent.remove(endpointId);
    _endpointRemoteCatechistId.remove(endpointId);
    _endpointRemoteHasClasses.remove(endpointId);
    _endpointSharedClassIds.remove(endpointId);
    _endpointSupportsClassChannel.remove(endpointId);
    _endpointSupportsParishChannel.remove(endpointId);
    _associationHandshakeStep.remove(endpointId);
    _handshakeTimeoutTimers.remove(endpointId)?.cancel();
    _remoteSyncState.remove(endpointId);
    _remoteSyncStartAt.remove(endpointId);
    _syncStateWatchdog.remove(endpointId)?.cancel();
    _isSyncing = false;
    if (_pendingEndpointId == endpointId) {
      _pendingEndpointId = null;
    }
    if (_state.isPairingMode && deviceId != null) {
      // During pairing, keep the pending association so that if the device
      // reconnects (possibly with a new endpoint ID), the pairing can continue
      // with the same PIN. Only remove the handshake data for this endpoint.
      addLog(
        'DEBUG',
        'Disconnessione durante pairing: mantengo associazione pendente per $deviceId',
      );
      _pendingHandshakeData.remove(endpointId);
    }
    if (_state.connectedDeviceId == endpointId) {
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.idle,
          connectedDeviceId: null,
          connectedDeviceName: null,
          connectedFingerprint: null,
          isSessionEncrypted: false,
        ),
      );
    }
  }

  Future<void> _cleanupEndpoint(String endpointId) async {
    try {
      await _nearby.disconnectFromEndpoint(endpointId);
    } catch (_) {}
    _connectedEndpoints.remove(endpointId);
    _endpointConnIdMap.remove(endpointId);
    _endpointSessionKeys.remove(endpointId);
    // Forward secrecy: rimuove la chiave efimera dalla memoria. La chiave
    // privata efimera NON è mai persistita, quindi una volta scartata la
    // sessione passata non può essere ricostruita nemmeno con la compromissione
    // successiva delle chiavi statiche di identità.
    _endpointLocalEphemeral.remove(endpointId);
    _endpointLocalEphemeralPub.remove(endpointId);
    _endpointRemoteEphemeralPub.remove(endpointId);
    _endpointRemoteAssocPub.remove(endpointId);
    _endpointSyncPhase.remove(endpointId);
    _endpointRemoteCatechistId.remove(endpointId);
    _endpointRemoteHasClasses.remove(endpointId);
    _endpointSharedClassIds.remove(endpointId);
    _endpointSupportsClassChannel.remove(endpointId);
    _endpointSupportsParishChannel.remove(endpointId);
    _associationHandshakeStep.remove(endpointId);
    _handshakeTimeoutTimers.remove(endpointId)?.cancel();
    _remoteSyncState.remove(endpointId);
    _remoteSyncStartAt.remove(endpointId);
    _syncStateWatchdog.remove(endpointId)?.cancel();
    if (_pendingEndpointId == endpointId) {
      _pendingEndpointId = null;
    }
  }

  String? _extractDeviceId(String endpointName) {
    try {
      if (endpointName.startsWith(_syncPrefix)) {
        // Handle old buggy format: CH_CH_xxx (double prefix) → strip first CH_
        if (endpointName.length > 3 &&
            endpointName.startsWith(_syncPrefix, 3)) {
          return endpointName.substring(3);
        }
        // Handle correct format: CH_xxx (deviceId itself)
        return endpointName;
      }
    } catch (_) {}
    return null;
  }

  bool _rolesAreCompatible(P2PSyncRole local, P2PSyncRole remote) {
    return true;
  }

  String _getCurrentClassId() {
    try {
      final box = LocalDatabase.classes();
      const uid = AuthService.localUserId;
      for (final key in box.keys) {
        final data = Map<String, dynamic>.from(box.get(key) as Map);
        final ids = (data['catechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        if (ids.contains(uid)) {
          return key.toString();
        }
      }
    } catch (_) {}
    return '';
  }

  /// Classi da annunciare nell'handshake: se durante l'associazione sono state
  /// scelte classi condivise (ruolo "Altro Catechista"), annuncia quelle;
  /// altrimenti la classe corrente.
  List<String> _handshakeSharedClassIds() {
    if (_associationSharedClassIds.isNotEmpty) {
      return _associationSharedClassIds.toList();
    }
    final current = _getCurrentClassId();
    return current.isNotEmpty ? [current] : [];
  }

  /// Classe principale da annunciare nell'handshake (campo legacy `classId`),
  /// per compatibilità con i dispositivi con versione precedente.
  String _handshakeClassId() {
    final ids = _handshakeSharedClassIds();
    return ids.isNotEmpty ? ids.first : '';
  }

  /// Estrae il profilo anagrafico (nome, cognome, numero) che il mittente
  /// ha impostato per l'altro catechista (ruolo "Altro Catechista").
  /// Restituisce una mappa vuota se non presente o non valida.
  Map<String, String> _parseRemoteProfile(Map<String, dynamic> message) {
    final raw = message['remoteProfile'];
    if (raw is! Map) return const {};
    final profile = <String, String>{};
    final firstName = (raw['firstName'] as String?)?.trim() ?? '';
    final lastName = (raw['lastName'] as String?)?.trim() ?? '';
    final phoneNumber = (raw['phoneNumber'] as String?)?.trim() ?? '';
    if (firstName.isNotEmpty || lastName.isNotEmpty) {
      if (firstName.isNotEmpty) profile['firstName'] = firstName;
      if (lastName.isNotEmpty) profile['lastName'] = lastName;
      if (phoneNumber.isNotEmpty) profile['phoneNumber'] = phoneNumber;
    }
    // Identità stabile opzionale (rubrica del Responsabile): il ricevente
    // la adotta come proprio catechistId dopo la configurazione dell'account.
    final catechistId = (raw['catechistId'] as String?)?.trim() ?? '';
    if (catechistId.isNotEmpty) profile['catechistId'] = catechistId;
    return profile;
  }

  /// Determina le classi condivise con l'endpoint [endpointId].
  ///
  /// Priorità:
  /// 1. Le classi scelte esplicitamente durante l'associazione
  ///    (`_associationSharedClassIds`).
  /// 2. Le classi offerte dal remoto nell'handshake (`sharedClassIds`).
  /// 3. Fallback legacy: la classe corrente del remoto (`classId`).
  Set<String> _resolveSharedClassIdsForEndpoint(
    String endpointId,
    List<String> remoteClassIds,
    String? remoteClassId,
  ) {
    final shared = <String>{..._associationSharedClassIds};
    shared.addAll(remoteClassIds);
    if (remoteClassId != null && remoteClassId.isNotEmpty) {
      shared.add(remoteClassId);
    }
    return shared;
  }

  /// Restituisce l'insieme di classi condivise con l'endpoint [endpointId].
  ///
  /// `null` = tutte le classi (stesso catechista su un suo altro dispositivo
  /// oppure due dispositivi associati come "Mio Dispositivo").
  /// Set vuoto = nessuna classe condivisa (nessun sync).
  Future<Set<String>?> _sharedClassIdsForEndpoint(String? endpointId) async {
    final localCatechistId = AuthService.getCatechistId();

    String? remoteCatechistId;
    Set<String>? remoteShared;
    // Ruoli salvati nell'associazione (fonte più affidabile, per-associazione).
    String? assocLocalRole;
    String? assocRemoteRole;
    if (endpointId != null) {
      remoteShared = _endpointSharedClassIds[endpointId];
      final deviceId = _endpointConnIdMap[endpointId];
      if (deviceId != null) {
        try {
          final assoc = await _security.getAssociation(deviceId);
          if (assoc != null) {
            // Il catechistId salvato nell'associazione (aggiornato dopo il
            // pairing) ha la precedenza su quello catturato al volo nell'handshake.
            if (assoc.catechistId != null && assoc.catechistId!.isNotEmpty) {
              remoteCatechistId = assoc.catechistId;
            }
            assocLocalRole = assoc.localRole;
            assocRemoteRole = assoc.remoteRole;
          }
        } catch (_) {}
      }
      remoteCatechistId ??= _endpointRemoteCatechistId[endpointId];
    }

    // Stesso catechista (su un suo altro dispositivo): tutte le classi.
    if (remoteCatechistId != null && remoteCatechistId == localCatechistId) {
      addLog(
        'DEBUG',
        'Sync scope: stesso catechista ($remoteCatechistId), tutte le classi',
      );
      return null;
    }

    // Due dispositivi associati come "Mio Dispositivo" sono la STESSA persona:
    // anche se il catechistId non fosse ancora stato unificato, sincronizziamo
    // tutte le classi (fallback che risolve i pairing precedenti al fix).
    if (assocLocalRole == P2PSyncRole.mioDispositivo.name &&
        assocRemoteRole == P2PSyncRole.mioDispositivo.name) {
      addLog(
        'DEBUG',
        'Sync scope: mio dispositivo su entrambi i lati, tutte le classi',
      );
      return null;
    }

    final candidates = <String>{..._associationSharedClassIds};
    if (remoteShared != null) candidates.addAll(remoteShared);

    // Nessuna selezione esplicita: usiamo le classi associate a entrambi i
    // catechisti (classi comuni), così un dispositivo rilevato in modalità
    // continua sincronizza solo le classi in comune.
    if (candidates.isEmpty) {
      candidates.addAll(_commonClassIds(localCatechistId, remoteCatechistId));
    }

    return candidates;
  }

  /// Restituisce lo scope di sincronizzazione per un endpoint specifico.
  ///
  /// La distinzione si basa sul `catechistId` (identità stabile della persona,
  /// NON sul nome, che è liberamente modificabile):
  /// - stesso `catechistId` del remoto → stessa persona su un suo altro
  ///   dispositivo → sincronizza TUTTE le classi (`null`);
  /// - `catechistId` diverso → altro catechista → SOLO le classi condivise
  ///   (scelte durante l'associazione o comuni a entrambi).
  ///
  /// Questo scope viene usato per l'INVIO (indice locale, record da spedire):
  /// viene limitato alle classi in cui il catechista locale è associato.
  Future<List<SyncClassScope>?> _currentSyncScope([String? endpointId]) async {
    final shared = await _sharedClassIdsForEndpoint(endpointId);
    if (shared == null) {
      return null;
    }
    if (shared.isEmpty) {
      addLog('WARN', 'Sync scope: nessuna classe condivisa per $endpointId');
      return const [];
    }

    final localClasses = _getClassIdsForCatechist(AuthService.getCatechistId());
    final sendClasses = shared.where(localClasses.contains).toSet();
    if (sendClasses.isEmpty && localClasses.isNotEmpty) {
      addLog(
        'WARN',
        'Sync scope: nessuna classe comune con $endpointId, nessun invio',
      );
      return const [];
    }
    return _buildScopes(sendClasses);
  }

  /// Scope per la RICEZIONE: classi condivise senza restrizione alle classi
  /// del catechista locale. Consente a un dispositivo che si sta unendo a una
  /// classe (es. onboarding) di ricevere i dati di classi non ancora sue.
  Future<List<SyncClassScope>?> _currentReceiveScope(String? endpointId) async {
    final shared = await _sharedClassIdsForEndpoint(endpointId);
    if (shared == null) return null;
    return _buildScopes(shared);
  }

  /// Costruisce la lista di [SyncClassScope] per le classi [classIds].
  List<SyncClassScope> _buildScopes(Set<String> classIds) {
    final box = LocalDatabase.classes();
    final scopes = <SyncClassScope>[];
    for (final classId in classIds) {
      final data = LocalDatabase.toStringDynamicMap(box.get(classId));
      final uniqueCode = data['uniqueCode']?.toString() ?? '';
      scopes.add(SyncClassScope(classId: classId, classUniqueCode: uniqueCode));
    }
    return scopes;
  }

  /// Classi in cui è associato il catechista identificato da [catechistId]
  /// (come creatore o come catechista associato).
  Set<String> _getClassIdsForCatechist(String? catechistId) {
    if (catechistId == null || catechistId.isEmpty) return {};
    try {
      final box = LocalDatabase.classes();
      final ids = <String>{};
      for (final key in box.keys) {
        final data = LocalDatabase.toStringDynamicMap(box.get(key));
        final creator = data['creatorCatechistId']?.toString() ?? '';
        final associated = (data['associatedCatechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        if (catechistId == creator || associated.contains(catechistId)) {
          ids.add(key.toString());
        }
      }
      return ids;
    } catch (_) {}
    return {};
  }

  /// Classi associate a ENTRAMBI i catechisti ([localCat] e [remoteCat]).
  Set<String> _commonClassIds(String? localCat, String? remoteCat) {
    if (localCat == null ||
        localCat.isEmpty ||
        remoteCat == null ||
        remoteCat.isEmpty) {
      return {};
    }
    return _getClassIdsForCatechist(
      localCat,
    ).intersection(_getClassIdsForCatechist(remoteCat));
  }

  Future<void> _sendHandshakePayload(String endpointId) async {
    try {
      _sessionPairingNonce = P2PSecurityService.secureRandom(
        16,
      ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final localIdentity = await _security.getLocalIdentity();
      // Forward secrecy: chiave efimera generata per QUESTA connessione.
      // Non viene mai persistita; la chiave privata resta solo in memoria e
      // viene scartata alla chiusura della sessione.
      final ephemeral = await _security.generateEphemeralKeyPair();
      final ephemeralPub = await ephemeral.extractPublicKey();
      _endpointLocalEphemeral[endpointId] = ephemeral;
      _endpointLocalEphemeralPub[endpointId] = base64Encode(ephemeralPub.bytes);
      // H2: l'handshake in chiaro trasporta SOLO i dati di bootstrap necessari
      // a stabilire la sessione (nonce, chiave efimera, ruoli). Le PII
      // (nome, cognome, telefono, catechistId, classi condivise, certificato
      // di approvazione) viaggiano ESCLUSIVAMENTE nel payload cifrato
      // `p2p_identity`, mai sul canale BLE in broadcast.
      final handshakeMsg = jsonEncode({
        'type': 'p2p_handshake',
        'v': 2,
        'senderId': localIdentity.deviceId,
        'senderName': localIdentity.deviceName,
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'role': _state.role.name,
        'sessionNonce': _sessionPairingNonce,
        'ephemeralPub': base64Encode(ephemeralPub.bytes),
        'supportsClassChannel': true,
        'supportsParishChannel': true,
      });
      addLog('DEBUG', 'Invio handshake a $endpointId');
      await _sendPayload(endpointId, handshakeMsg);
      _updateState(_state.copyWith(status: P2PSyncStatus.handshakeSent));
      addLog('DEBUG', 'Handshake inviato a $endpointId');
    } catch (e) {
      addLog('ERROR', 'Errore invio handshake: $e');
    }
  }

  /// Chiave pubblica efimera locale per [endpointId] (forward secrecy),
  /// precalcolata alla generazione della coppia efimera.
  String _localEphemeralPubForEndpoint(String endpointId) =>
      _endpointLocalEphemeralPub[endpointId] ?? '';

  /// Invia il payload cifrato `p2p_identity` con i dati di IDENTITÀ del
  /// dispositivo locale (nome, cognome, catechistId, classi condivise,
  /// profilo anagrafico dell'altro catechista e certificato di approvazione).
  ///
  /// H2: queste informazioni NON devono mai transitare sul canale BLE in
  /// chiaro (broadcast). Viaggiano esclusivamente dentro il payload cifrato
  /// AES-GCM della sessione stabilita ([_sendEncryptedPayload]).
  Future<void> _sendIdentityPayload(String endpointId) async {
    try {
      final localIdentity = await _security.getLocalIdentity();
      final localApproval = await _security.getLocalApproval();
      // M5: la chiave pubblica per-associazione del dispositivo locale viene
      // scambiata in modo autenticato (payload cifrato della sessione): il
      // peer la usa per mescolare il DH dedicato dell'associazione nella
      // chiave di sessione. Senza di essa non c'è alcun downgrade: la
      // sessione resta TripleDH, semplicemente senza il fattore extra.
      final remoteDeviceId = _endpointConnIdMap[endpointId];
      final localAssoc = remoteDeviceId != null
          ? await _security.getAssociation(remoteDeviceId)
          : null;
      final assocPub = localAssoc?.devicePublicKeyBase64 ?? '';
      final msg = jsonEncode({
        'type': 'p2p_identity',
        'senderId': localIdentity.deviceId,
        'senderFirstName': localIdentity.firstName,
        'senderLastName': localIdentity.lastName,
        'classId': _handshakeClassId(),
        'sharedClassIds': _handshakeSharedClassIds(),
        'catechistId': AuthService.getCatechistId(),
        'hasClasses': _hasCatechistIdentity(AuthService.getCatechistId()),
        // H2/H4: capacità dei canali per-classe e parrocchiale. Devon
        // viaggiare anche nell'identità cifrata perché _handleIdentity le
        // riapplica: senza questi flag il ricevente le azzerava (il payload
        // handshake le aveva impostate a true), causando l'omissione dei
        // record di classe e l'assenza del catechista remoto dalla classe.
        'supportsClassChannel': true,
        'supportsParishChannel': true,
        if (assocPub.isNotEmpty) 'assocPub': assocPub,
        // Profilo anagrafico dell'altro catechista (ruolo "Altro Catechista"):
        // il ricevente lo usa per configurare il proprio account.
        if (_associationRemoteProfile.isNotEmpty)
          'remoteProfile': _associationRemoteProfile,
        // Certificato di approvazione del Responsabile (se il dispositivo è
        // già stato approvato): il peer lo verifica con la trust root della
        // parrocchia quando la modalità Responsabile è attiva.
        if (localApproval != null && localApproval.isApproved)
          'approvalCert': localApproval.toJson(),
      });
      await _sendEncryptedPayload(endpointId, msg);
      addLog('DEBUG', 'Identità inviata a $endpointId');
    } catch (e) {
      addLog('ERROR', 'Errore invio identità a $endpointId: $e');
    }
  }

  /// Riceve il payload cifrato `p2p_identity` dal peer e aggiorna lo stato
  /// dell'identità remota dichiarata (catechistId, classi condivise, profilo
  /// anagrafico) e allega il certificato di approvazione se verificabile.
  Future<void> _handleIdentity(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final senderId = message['senderId'] as String?;
    if (senderId == null) return;
    addLog('DEBUG', 'Identità ricevuta da $senderId');

    final remoteCatechistId = message['catechistId'] as String?;
    if (remoteCatechistId != null && remoteCatechistId.isNotEmpty) {
      _endpointRemoteCatechistId[endpointId] = remoteCatechistId;
      _pendingHandshakeRemoteCatechistId = remoteCatechistId;
    }
    _endpointRemoteHasClasses[endpointId] = message['hasClasses'] == true;
    _endpointSupportsClassChannel[endpointId] =
        message['supportsClassChannel'] == true;
    _endpointSupportsParishChannel[endpointId] =
        message['supportsParishChannel'] == true;
    _endpointSharedClassIds[endpointId] = _resolveSharedClassIdsForEndpoint(
      endpointId,
      (message['sharedClassIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      message['classId'] as String?,
    );
    _pendingHandshakeRemoteProfile = _parseRemoteProfile(message);

    // M5: registra la chiave pubblica per-associazione del peer e applica il
    // fattore di associazione alla chiave di sessione (crypto per-associazione
    // ora realmente usata). La vecchia chiave resta nel set di decifratura
    // per i messaggi in transito, così il passaggio è indolore.
    final assocPub = message['assocPub'] as String? ?? '';
    if (assocPub.isNotEmpty) {
      _endpointRemoteAssocPub[endpointId] = assocPub;
      await _applyAssociationUpgrade(endpointId);
    }

    // Anagrafica (nome/cognome) per il controllo anti-associazione errata.
    // Conservata anche come fallback per la configurazione dell'account del
    // ricevente quando il mittente non fornisce un profilo esplicito.
    final firstName = message['senderFirstName'] as String? ?? '';
    final lastName = message['senderLastName'] as String? ?? '';
    if (firstName.isNotEmpty || lastName.isNotEmpty) {
      _peerFirstName = firstName;
      _peerLastName = lastName;
      final current = _pendingHandshakeIdentity;
      if (current != null) {
        _pendingHandshakeIdentity = P2PIdentity(
          deviceId: current.deviceId,
          deviceName: current.deviceName,
          username: current.username,
          publicKeyBase64: current.publicKeyBase64,
          fingerprint: current.fingerprint,
          connectionEndpoint: current.connectionEndpoint,
          firstName: firstName,
          lastName: lastName,
        );
      }
    }

    // Catena di fiducia (H3): verifica e allega il certificato di approvazione
    // e lo vincola all'identità dichiarata.
    await _attachApprovalFromHandshake(senderId, message);
  }

  /// Deriva il pairing code dal shared secret, dai nonces concordati e dalle
  /// chiavi efimere (Fase 2 — item 6). Entrambi i dispositivi devono usare lo
  /// stesso nonce concordato per garantire che i codice di verifica
  /// corrispondano. Se un nonce è mancante, si aspetta fino a 3 secondi per
  /// riceverlo prima di procedere.
  ///
  /// Le chiavi efimere vengono ordinate in modo canonico prima di essere
  /// incluse, così entrambi i peer producono lo stesso input al SAS.
  Future<String?> _computePairingCode({
    required String remoteId,
    required String? localNonce,
    required String? remoteNonce,
    String? endpointId,
  }) async {
    // Check if we already have a pairing code stored for this device
    // (persists across endpoint reconnections during pairing).
    final cachedCode = _pairingCodesByDeviceId[remoteId];
    if (cachedCode != null && _state.isPairingMode) {
      addLog('DEBUG', 'Riutilizzo pairing code memorizzato per $remoteId');
      return cachedCode;
    }

    addLog(
      'INFO',
      '_computePairingCode: remote=$remoteId, localNonce present=${localNonce != null}, remoteNonce present=${remoteNonce != null}',
    );

    final effectiveLocalNonce = localNonce ?? _sessionPairingNonce;
    final effectiveRemoteNonce = remoteNonce ?? _remoteSessionPairingNonce;

    // Attendi fino a 3 secondi che entrambi i nonce siano disponibili.
    // Questo evita race condition in cui un dispositivo riceve la richiesta
    // di verifica prima di aver generato il proprio nonce di sessione.
    if (effectiveLocalNonce == null || effectiveRemoteNonce == null) {
      addLog('WARN', 'Nonce mancante, attesa 3s per sincronizzazione...');
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (effectiveLocalNonce == null && _sessionPairingNonce != null) {
          addLog('DEBUG', 'Nonce locale ricevuto dopo attesa');
          break;
        }
        if (effectiveRemoteNonce == null &&
            _remoteSessionPairingNonce != null) {
          addLog('DEBUG', 'Nonce remoto ricevuto dopo attesa');
          break;
        }
      }
    }

    final finalLocalNonce = localNonce ?? _sessionPairingNonce;
    final finalRemoteNonce = remoteNonce ?? _remoteSessionPairingNonce;

    String? agreedNonce;

    if (finalLocalNonce != null && finalRemoteNonce != null) {
      final sorted = <String>[finalLocalNonce, finalRemoteNonce]..sort();
      agreedNonce = '${sorted[0]}${sorted[1]}';
      addLog(
        'DEBUG',
        'Nonce concordati (combinazione deterministica di entrambi)',
      );
    } else if (finalLocalNonce != null) {
      agreedNonce = finalLocalNonce;
      addLog('WARN', 'Solo nonce locale disponibile, codice non univoco');
    } else if (finalRemoteNonce != null) {
      agreedNonce = finalRemoteNonce;
      addLog('WARN', 'Solo nonce remoto disponibile, codice non univoco');
    } else {
      addLog('WARN', 'Nessun nonce disponibile, pairing code senza nonce');
    }

    final association = _pendingAssociations[remoteId];
    if (association == null) {
      addLog('WARN', 'Nessun shared secret trovato per $remoteId');
      return null;
    }

    final sharedSecret = association.sharedSecretBase64;
    addLog(
      'DEBUG',
      'Calcolo codice con agreedNonce present=${agreedNonce != null}, sharedSecret present',
    );
    final code = P2PSecurityService.computePairingCode(
      sharedSecret,
      sessionNonce: agreedNonce,
      // Fase 2 — item 6: vincola il SAS alle chiavi efimere della sessione
      // (detezione MitM sullo scambio delle chiavi efimere).
      localEphemeralPub: endpointId != null
          ? _endpointLocalEphemeralPub[endpointId]
          : null,
      remoteEphemeralPub: endpointId != null
          ? _endpointRemoteEphemeralPub[endpointId]
          : null,
    );

    // Store the pairing code by deviceId so it persists across endpoint
    // reconnections during the pairing session.
    if (_state.isPairingMode) {
      _pairingCodesByDeviceId[remoteId] = code;
    }

    // Privacy: il codice pairing NON viene loggato. È il segreto di
    // autenticazione a breve termine per l'associazione; un log (anche
    // DEBUG) lo esporrebbe a chiunque legga il log di sync.
    return code;
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.bytes == null) {
      addLog('WARN', 'Payload ricevuto senza bytes da $endpointId');
      return;
    }
    try {
      final rawMessage = utf8.decode(payload.bytes!);
      addLog(
        'DEBUG',
        'Payload ricevuto da $endpointId (${rawMessage.length} bytes)',
      );
      _handleMessage(endpointId, rawMessage);
    } catch (e) {
      addLog('ERROR', 'Errore decodifica payload: $e');
    }
  }

  Future<String> _tryDecryptMessage(
    String endpointId,
    String rawMessage,
  ) async {
    final keys = _endpointSessionKeys[endpointId];
    if (keys != null && keys.isNotEmpty) {
      // Tenta con tutte le chiavi della finestra corrente e precedente:
      // i messaggi in transito al confine della rotazione sono decifrabili
      // con la chiave della finestra in cui sono stati cifrati.
      for (final entry in keys) {
        try {
          final encrypted = P2PEncryptedPayload.decode(rawMessage);
          final decrypted = await _security.decryptPayload(
            encrypted,
            entry.key,
          );
          final wrapper = jsonDecode(decrypted);
          if (wrapper is Map<String, dynamic>) {
            final senderId = wrapper['senderId'] as String?;
            final senderPublicKey = wrapper['senderPublicKey'] as String?;
            final expectedDeviceId = _endpointConnIdMap[endpointId];
            if (senderId != null &&
                expectedDeviceId != null &&
                senderId != expectedDeviceId) {
              addLog(
                'ERROR',
                'Mittente non corrisponde: $senderId vs $expectedDeviceId',
              );
              return rawMessage;
            }
            if (senderPublicKey != null && expectedDeviceId != null) {
              final assoc = await _security.getAssociation(expectedDeviceId);
              if (assoc != null &&
                  !P2PSecurityService.publicKeyMatchesAssociation(
                    assoc,
                    senderPublicKey,
                  )) {
                addLog(
                  'ERROR',
                  'Chiave pubblica mittente non corrisponde per $senderId',
                );
                return rawMessage;
              }
            }
            final data = wrapper['data'] as String?;
            if (data != null) return data;
          }
          return wrapper is String ? wrapper : decrypted;
        } catch (_) {}
      }
    }
    return rawMessage;
  }

  Future<void> _handleMessage(String endpointId, String rawMessage) async {
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
        case 'p2p_identity':
          await _handleIdentity(endpointId, decoded);
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
        case 'p2p_sync_complete':
          await _handleSyncComplete(endpointId, decoded);
          break;
        case 'p2p_association_confirmed':
          await _handleAssociationConfirmed(endpointId, decoded);
          break;
        case 'p2p_association_ack':
          addLog('DEBUG', 'ACK associazione ricevuto dal remoto');
          _updateState(_state.copyWith(authenticatedByRemote: true));
          break;
        case 'p2p_catechist_id_choice':
          await _handleCatechistIdChoice(endpointId, decoded);
          break;
        case 'p2p_ready_for_verification':
          await _handleReadyForVerification(endpointId, decoded);
          break;
        case 'p2p_pairing_rejected':
          await _handlePairingRejected(endpointId, decoded);
          break;
        case 'p2p_tombstone':
          await _handleTombstone(endpointId, decoded);
          break;
        case 'p2p_revoked_devices':
          await _handleRevokedDevices(endpointId, decoded);
          break;
        case 'p2p_parish_channel':
          await _handleParishChannel(endpointId, decoded);
          break;
        case 'p2p_account_config':
          await _handleAccountConfig(endpointId, decoded);
          break;
        case 'p2p_account_config_ack':
          await _handleAccountConfigAck(endpointId, decoded);
          break;
        case 'p2p_class_info':
          await _handleClassInfo(endpointId, decoded);
          break;
        case 'p2p_class_info_ack':
          await _handleClassInfoAck(endpointId, decoded);
          break;
        case 'p2p_sync_state':
          await _handleSyncState(endpointId, decoded);
          break;
        case 'p2p_continuous_sync_ping':
          await _handleContinuousSyncPing(endpointId, decoded);
          break;
        case 'p2p_continuous_sync_pong':
          await _handleContinuousSyncPong(endpointId, decoded);
          break;
      }
    } catch (e) {
      addLog('ERROR', 'Errore gestione messaggio da $endpointId: $e');
    }
  }

  Future<void> _handleHandshake(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
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
      addLog(
        'DEBUG',
        'Handshake da $remoteName ($remoteId) in pairing mode, nessuna associazione ancora. '
            'Attendo che l\'utente scansioni il QR.',
      );

      // Sicurezza: rifiuta handshake in pairing troppo vecchi o nel futuro
      // (replay / clock skew eccessivo).
      final hsTimestamp = message['timestamp'] as int? ?? 0;
      if (hsTimestamp > 0) {
        final hsAge =
            (DateTime.now().millisecondsSinceEpoch ~/ 1000) - hsTimestamp;
        if (hsAge.abs() > 300) {
          addLog(
            'WARN',
            'Handshake pairing scaduto per $endpointId (età: ${hsAge.abs()}s), disconnessione',
          );
          await _cleanupEndpoint(endpointId);
          return;
        }
      }

      final remoteRoleStr = message['role'] as String?;
      final remoteRole = remoteRoleStr != null
          ? P2PSyncRole.values.firstWhere(
              (r) => r.name == remoteRoleStr,
              orElse: () => P2PSyncRole.mioDispositivo,
            )
          : P2PSyncRole.mioDispositivo;

      final remoteCatechistId = message['catechistId'] as String?;
      _remoteSessionPairingNonce = message['sessionNonce'] as String?;
      _endpointConnIdMap[endpointId] = remoteId;
      _connectedEndpoints.add(endpointId);
      // Forward secrecy: registra la chiave efimera del remoto e genera la
      // propria chiave efimera per questa connessione (se non già presente).
      _endpointRemoteEphemeralPub[endpointId] =
          message['ephemeralPub'] as String? ?? '';
      if (_endpointLocalEphemeral[endpointId] == null) {
        final localEphemeral = await _security.generateEphemeralKeyPair();
        _endpointLocalEphemeral[endpointId] = localEphemeral;
        final localEphemeralPub = await localEphemeral.extractPublicKey();
        _endpointLocalEphemeralPub[endpointId] = base64Encode(
          localEphemeralPub.bytes,
        );
      }

      if (remoteCatechistId != null && remoteCatechistId.isNotEmpty) {
        _endpointRemoteCatechistId[endpointId] = remoteCatechistId;
      }
      final remoteHasClasses = message['hasClasses'] == true;
      _endpointRemoteHasClasses[endpointId] = remoteHasClasses;
      _endpointSupportsClassChannel[endpointId] =
          message['supportsClassChannel'] == true;
      _endpointSupportsParishChannel[endpointId] =
          message['supportsParishChannel'] == true;
      _pendingHandshakeRemoteProfile = _parseRemoteProfile(message);
      final remoteShared = _resolveSharedClassIdsForEndpoint(
        endpointId,
        (message['sharedClassIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        message['classId'] as String?,
      );
      _endpointSharedClassIds[endpointId] = remoteShared;

      _pendingHandshakeData[endpointId] = _PendingHandshakeData(
        endpointId: endpointId,
        remoteId: remoteId,
        remoteName: remoteName,
        remoteNonce: _remoteSessionPairingNonce ?? '',
        remoteRole: remoteRole,
        remoteClassId: message['classId'] as String?,
        remoteSharedClassIds:
            (message['sharedClassIds'] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toList(),
        remoteCatechistId: remoteCatechistId,
        remoteHasClasses: remoteHasClasses,
      );

      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.sessionEstablished,
          connectedDeviceId: endpointId,
          connectedDeviceName: remoteName,
          isSessionEncrypted: false,
        ),
      );
      return;
    }

    if (association == null) {
      addLog('ERROR', 'Nessuna associazione trovata per $remoteId.');
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: 'Nessuna associazione trovata per $remoteName.',
        ),
      );
      return;
    }
    addLog('DEBUG', 'Handshake da: $remoteId');

    // ─── Catena di fiducia (modalità Responsabile) ─────────────────────────
    // Se il peer trasporta un certificato di approvazione del Responsabile,
    // lo verifichiamo e lo alleghiamo all'associazione (se la modalità
    // Responsabile è attiva e il segreto della parrocchia è disponibile).
    await _attachApprovalFromHandshake(remoteId, message);

    // Quando la modalità Responsabile è ATTIVA, il dispositivo remoto deve
    // essere stato preventivamente approvato dal Responsabile. Se non lo è
    // (o la sua approvazione non è verificabile), il sync viene rifiutato.
    final syncAllowed = await _security.isSyncAllowedFromDevice(remoteId);
    if (!syncAllowed) {
      addLog(
        'ERROR',
        'Catena di fiducia: $remoteName ($remoteId) non è stato approvato '
            'dal Responsabile. Sincronizzazione rifiutata.',
      );
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage:
              'Sincronizzazione rifiutata: $remoteName non è stato approvato '
              'dal Responsabile per la sync delle classi.',
        ),
      );
      return;
    }

    final remoteRoleStr = message['role'] as String?;
    final remoteRole = remoteRoleStr != null
        ? P2PSyncRole.values.firstWhere(
            (r) => r.name == remoteRoleStr,
            orElse: () => P2PSyncRole.mioDispositivo,
          )
        : P2PSyncRole.mioDispositivo;

    if (!_rolesAreCompatible(_state.role, remoteRole)) {
      addLog(
        'ERROR',
        'Ruoli incompatibili: locale=${_state.role.name} '
            'remoto=${remoteRole.name} con $remoteName',
      );
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage:
              'Ruoli incompatibili: i due dispositivi devono '
              'avere lo stesso ruolo. Entrambi "mioDispositivo" o '
              'entrambi "altroCatechista".',
        ),
      );
      return;
    }
    addLog(
      'DEBUG',
      'Ruoli compatibili: ${_state.role.name} <-> ${remoteRole.name}',
    );

    // Registra identità e classi condivise: lo scope di sincronizzazione
    // viene deciso confrontando il catechistId (stesso catechista → tutte
    // le classi; diverso → solo le classi condivise). Non blocchiamo più
    // qui per classe corrente diversa: la distinzione per classe è demandata
    // allo scope, che filtra i record per le sole classi condivise.
    final remoteCatechistId = message['catechistId'] as String?;
    if (remoteCatechistId != null && remoteCatechistId.isNotEmpty) {
      _endpointRemoteCatechistId[endpointId] = remoteCatechistId;
    }
    _endpointRemoteHasClasses[endpointId] = message['hasClasses'] == true;
    final remoteShared = _resolveSharedClassIdsForEndpoint(
      endpointId,
      (message['sharedClassIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      message['classId'] as String?,
    );
    _endpointSharedClassIds[endpointId] = remoteShared;

    final timestamp = message['timestamp'] as int? ?? 0;
    final age = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - timestamp;
    if (age.abs() > 120) {
      addLog(
        'WARN',
        'Handshake scaduto per $endpointId (età: ${age.abs()}s), disconnessione',
      );
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
    // Forward secrecy: registra la chiave efimera del remoto e genera la
    // propria chiave efimera per questa connessione (se non già presente).
    _endpointRemoteEphemeralPub[endpointId] =
        message['ephemeralPub'] as String? ?? '';
    if (_endpointLocalEphemeral[endpointId] == null) {
      final localEphemeral = await _security.generateEphemeralKeyPair();
      _endpointLocalEphemeral[endpointId] = localEphemeral;
      final localEphemeralPub = await localEphemeral.extractPublicKey();
      _endpointLocalEphemeralPub[endpointId] = base64Encode(
        localEphemeralPub.bytes,
      );
    }

    final localIdentity = await _security.getLocalIdentity();

    if (!_state.isPairingMode) {
      addLog('DEBUG', 'Handshake: associazione esistente, invio ack cifrato');
      // H2: l'ack trasporta solo dati di bootstrap (nessuna PII in chiaro
      // sul canale BLE). L'identità viaggia nel payload cifrato
      // `p2p_identity`, inviato subito dopo l'ack.
      final ack = jsonEncode({
        'type': 'p2p_handshake_ack',
        'senderId': localIdentity.deviceId,
        'senderName': localIdentity.deviceName,
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'role': _state.role.name,
        'sessionNonce': _sessionPairingNonce ?? '',
        'ephemeralPub': _localEphemeralPubForEndpoint(endpointId),
        'supportsClassChannel': true,
        'supportsParishChannel': true,
      });
      await _sendEncryptedPayload(endpointId, ack);
      // H2: invia l'identità (PII) SOLO nel payload cifrato di sessione.
      await _sendIdentityPayload(endpointId);
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.sessionEstablished,
          connectedDeviceId: endpointId,
          connectedDeviceName: remoteName,
          connectedFingerprint: association.fingerprint,
          isSessionEncrypted: true,
        ),
      );

      final iAmInitiator = localIdentity.deviceId.compareTo(remoteId) <= 0;
      _isInitiator = iAmInitiator;
      addLog('DEBUG', 'Sono iniziatore: $iAmInitiator');
      if (iAmInitiator && !_authRequestSent.contains(endpointId)) {
        _authRequestSent.add(endpointId);
        final authRequest = jsonEncode({
          'type': 'p2p_auth_request',
          'deviceId': localIdentity.deviceId,
          'deviceName': localIdentity.deviceName,
        });
        await _sendEncryptedPayload(endpointId, authRequest);
        addLog('DEBUG', 'Auth request inviata a $endpointId');
      }
    } else {
      addLog('DEBUG', 'Handshake: associazione trovata, calcolo pairing code');

      // H2: l'ack trasporta solo dati di bootstrap (nessuna PII in chiaro
      // sul canale BLE). L'identità viaggia nel payload cifrato
      // `p2p_identity`, inviato subito dopo l'ack.
      final ack = jsonEncode({
        'type': 'p2p_handshake_ack',
        'senderId': localIdentity.deviceId,
        'senderName': localIdentity.deviceName,
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'role': _state.role.name,
        'sessionNonce': _sessionPairingNonce ?? '',
        'ephemeralPub': _localEphemeralPubForEndpoint(endpointId),
        'supportsClassChannel': true,
        'supportsParishChannel': true,
      });
      await _sendPayload(endpointId, ack);

      if (_state.isPairingMode) {
        final code = await _computePairingCode(
          remoteId: remoteId,
          localNonce: _sessionPairingNonce,
          remoteNonce: _remoteSessionPairingNonce,
          endpointId: endpointId,
        );

        _pendingHandshakeRemoteProfile = _parseRemoteProfile(message);
        _pendingHandshakeIdentity = P2PIdentity(
          deviceId: remoteId,
          deviceName: remoteName,
          username: '',
          publicKeyBase64: association.publicKeyBase64,
          fingerprint: association.fingerprint,
          connectionEndpoint: '',
          firstName: message['senderFirstName'] as String? ?? '',
          lastName: message['senderLastName'] as String? ?? '',
        );
        _pendingHandshakeRemoteRole = remoteRole;
        _pendingHandshakeRemoteCatechistId = message['catechistId'] as String?;

        addLog('INFO', 'Codice pairing calcolato ma attendo conferma remota');

        _updateState(
          _state.copyWith(
            status: P2PSyncStatus.sessionEstablished,
            connectedDeviceId: endpointId,
            connectedDeviceName: remoteName,
            connectedFingerprint: association.fingerprint,
            isSessionEncrypted: true,
            pairingCode: code,
          ),
        );
      } else {
        _updateState(
          _state.copyWith(
            status: P2PSyncStatus.sessionEstablished,
            connectedDeviceId: endpointId,
            connectedDeviceName: remoteName,
            connectedFingerprint: association.fingerprint,
            isSessionEncrypted: true,
          ),
        );
      }
    }
  }

  Future<void> _handleHandshakeAck(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    addLog('DEBUG', 'Handshake ACK ricevuto da $endpointId');

    final remoteId = message['senderId'] as String?;
    final remoteName = message['senderName'] as String? ?? 'Sconosciuto';

    if (remoteId == null) {
      addLog('WARN', 'Handshake ACK senza senderId da $endpointId');
      return;
    }

    // M6 — freshness: un ACK riprodotto (replay) deve essere rifiutato.
    // L'ACK, come l'handshake, trasporta un timestamp: se è più vecchio di
    // 120s (o nel futuro oltre lo skew di orologio) il pairing viene
    // interrotto, così una registrazione BLE intercettata non può essere
    // riusata per ricavare il pairing code.
    final ackTimestamp = message['timestamp'] as int? ?? 0;
    if (ackTimestamp > 0) {
      final ackAge =
          (DateTime.now().millisecondsSinceEpoch ~/ 1000) - ackTimestamp;
      if (ackAge.abs() > 120) {
        addLog(
          'WARN',
          'M6: handshake ACK scaduto per $endpointId (età: ${ackAge.abs()}s), '
              'disconnessione',
        );
        try {
          await _nearby.disconnectFromEndpoint(endpointId);
        } catch (_) {}
        _connectedEndpoints.remove(endpointId);
        _pendingEndpointId = null;
        return;
      }
    }

    final association = await _security.getAssociation(remoteId);

    if (association == null && _state.isPairingMode) {
      addLog(
        'DEBUG',
        'Handshake ACK da $remoteId in pairing mode, '
            'nessuna associazione ancora. Attendo scansione QR.',
      );

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
      // Forward secrecy: registra la chiave efimera del remoto e genera la
      // propria se non già presente.
      _endpointRemoteEphemeralPub[endpointId] =
          message['ephemeralPub'] as String? ?? '';
      if (_endpointLocalEphemeral[endpointId] == null) {
        final localEphemeral = await _security.generateEphemeralKeyPair();
        _endpointLocalEphemeral[endpointId] = localEphemeral;
        final localEphemeralPub = await localEphemeral.extractPublicKey();
        _endpointLocalEphemeralPub[endpointId] = base64Encode(
          localEphemeralPub.bytes,
        );
      }

      final ackRemoteCatechistId = message['catechistId'] as String?;
      if (ackRemoteCatechistId != null && ackRemoteCatechistId.isNotEmpty) {
        _endpointRemoteCatechistId[endpointId] = ackRemoteCatechistId;
      }
    _endpointRemoteHasClasses[endpointId] = message['hasClasses'] == true;
    // Non declassare le capacità già stabilite dall'handshake: se l'identità
    // non riporta il flag (peer che lo omette), mantieni il valore precedente
    // invece di azzerarlo a false.
    if (message.containsKey('supportsClassChannel')) {
      _endpointSupportsClassChannel[endpointId] =
          message['supportsClassChannel'] == true;
    }
    if (message.containsKey('supportsParishChannel')) {
      _endpointSupportsParishChannel[endpointId] =
          message['supportsParishChannel'] == true;
    }
      final ackSharedClasses = _resolveSharedClassIdsForEndpoint(
        endpointId,
        (message['sharedClassIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        message['classId'] as String?,
      );
      _endpointSharedClassIds[endpointId] = ackSharedClasses;
      _pendingHandshakeRemoteProfile = _parseRemoteProfile(message);

      _pendingHandshakeData[endpointId] ??= _PendingHandshakeData(
        endpointId: endpointId,
        remoteId: remoteId,
        remoteName: remoteName,
        remoteNonce: _remoteSessionPairingNonce ?? '',
        remoteRole: remoteRole,
        remoteClassId: message['classId'] as String?,
        remoteSharedClassIds:
            (message['sharedClassIds'] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toList(),
        remoteCatechistId: message['catechistId'] as String?,
        remoteHasClasses: message['hasClasses'] == true,
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
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: 'Nessuna associazione trovata per $remoteName.',
        ),
      );
      return;
    }
    addLog('DEBUG', 'Handshake ACK da: $remoteId');

    final remoteRoleStr = message['role'] as String?;
    final remoteRole = remoteRoleStr != null
        ? P2PSyncRole.values.firstWhere(
            (r) => r.name == remoteRoleStr,
            orElse: () => P2PSyncRole.mioDispositivo,
          )
        : P2PSyncRole.mioDispositivo;

    if (!_rolesAreCompatible(_state.role, remoteRole)) {
      addLog(
        'ERROR',
        'Ruoli incompatibili: entrambi ${_state.role.name} '
            'con $remoteName',
      );
      try {
        await _nearby.disconnectFromEndpoint(endpointId);
      } catch (_) {}
      _connectedEndpoints.remove(endpointId);
      _pendingEndpointId = null;
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage:
              'Ruoli incompatibili: i due dispositivi devono '
              'avere lo stesso ruolo. Entrambi "mioDispositivo" o '
              'entrambi "altroCatechista".',
        ),
      );
      return;
    }

    final remoteClassId = message['classId'] as String? ?? '';
    addLog(
      'DEBUG',
      'Handshake ACK: remoto=$remoteName, classId=$remoteClassId, '
          'catechistId=${message['catechistId']}',
    );

    final ackRemoteCatechistId = message['catechistId'] as String?;
    if (ackRemoteCatechistId != null && ackRemoteCatechistId.isNotEmpty) {
      _endpointRemoteCatechistId[endpointId] = ackRemoteCatechistId;
    }
    _endpointRemoteHasClasses[endpointId] = message['hasClasses'] == true;
    _endpointSupportsClassChannel[endpointId] =
        message['supportsClassChannel'] == true;
    _endpointSupportsParishChannel[endpointId] =
        message['supportsParishChannel'] == true;
    final ackSharedClasses = _resolveSharedClassIdsForEndpoint(
      endpointId,
      (message['sharedClassIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      remoteClassId,
    );
    _endpointSharedClassIds[endpointId] = ackSharedClasses;

    _endpointConnIdMap[endpointId] = remoteId;
    _connectedEndpoints.add(endpointId);
    // Forward secrecy: registra la chiave efimera del remoto ricevuta
    // nell'ack e genera la propria se non già presente.
    _endpointRemoteEphemeralPub[endpointId] =
        message['ephemeralPub'] as String? ?? '';
    if (_endpointLocalEphemeral[endpointId] == null) {
      final localEphemeral = await _security.generateEphemeralKeyPair();
      _endpointLocalEphemeral[endpointId] = localEphemeral;
      final localEphemeralPub = await localEphemeral.extractPublicKey();
      _endpointLocalEphemeralPub[endpointId] = base64Encode(
        localEphemeralPub.bytes,
      );
    }

    if (!_state.isPairingMode) {
      _updateState(
        _state.copyWith(
          connectedFingerprint: association.fingerprint,
          connectedDeviceName: remoteName,
          isSessionEncrypted: true,
        ),
      );

      final localIdentity = await _security.getLocalIdentity();
      final iAmInitiator = localIdentity.deviceId.compareTo(remoteId) <= 0;
      _isInitiator = iAmInitiator;

      // H2: invia l'identità (PII) SOLO nel payload cifrato di sessione,
      // prima dell'auth request così il ricevente ha l'identità quando
      // calcola lo scope di sincronizzazione.
      await _sendIdentityPayload(endpointId);

      if (iAmInitiator && !_authRequestSent.contains(endpointId)) {
        _authRequestSent.add(endpointId);
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
      final code = await _computePairingCode(
        remoteId: remoteId,
        localNonce: _sessionPairingNonce,
        remoteNonce: _remoteSessionPairingNonce,
        endpointId: endpointId,
      );

      _pendingHandshakeRemoteProfile = _parseRemoteProfile(message);
      _pendingHandshakeIdentity = P2PIdentity(
        deviceId: remoteId,
        deviceName: remoteName,
        username: '',
        publicKeyBase64: association.publicKeyBase64,
        fingerprint: association.fingerprint,
        connectionEndpoint: '',
        firstName: message['senderFirstName'] as String? ?? '',
        lastName: message['senderLastName'] as String? ?? '',
      );
      _pendingHandshakeRemoteRole = remoteRole;
      _pendingHandshakeRemoteCatechistId = message['catechistId'] as String?;

      addLog(
        'INFO',
        'Codice pairing calcolato in ACK ma attendo conferma remota',
      );
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.sessionEstablished,
          connectedFingerprint: association.fingerprint,
          connectedDeviceName: remoteName,
          isSessionEncrypted: true,
          pairingCode: code,
          remoteDeviceFingerprint: association.fingerprint,
        ),
      );
    }
  }

  /// Verifica il certificato di approvazione trasportato nell'handshake e, se
  /// valido, lo allega all'associazione locale. Senza segreto della parrocchia
  /// (dispositivo non configurato come verifica) il certificato viene comunque
  /// salvato come metadato, così il device potrà essere approvato in seguito.
  Future<void> _attachApprovalFromHandshake(
    String remoteId,
    Map<String, dynamic> message,
  ) async {
    try {
      final rawCert = message['approvalCert'];
      if (rawCert is! Map) return;
      final cert = AssociatedDevice.fromJson(
        Map<String, dynamic>.from(rawCert),
      );
      if (!cert.isApproved) return;

      final assoc = await _security.getAssociation(remoteId);
      if (assoc == null) return;
      if (assoc.authorizedByResponsabile) return;

      final responsabileMode = await _security.isResponsabileModeActive();
      final hasTrustRoot = await _security.hasTrustRoot();
      var valid = false;
      if (responsabileMode && hasTrustRoot) {
        valid = await _security.verifyApprovalCertificate(cert);
      }

      // H3: l'identità dichiarata deve essere AUTENTICATA dal certificato
      // firmato. Il certificato è valido solo se:
      //   1. la chiave pubblica del dispositivo nel certificato coincide con
      //      quella dell'associazione (il certificato non può essere usato da
      //      un dispositivo diverso dal firmato);
      //   2. il catechistId dichiarato coincide con quello del certificato
      //      (un dispositivo rogue non può impersonare un catechista membro).
      if (valid) {
        final certMatchesDevice =
            cert.publicKey.isNotEmpty &&
            cert.publicKey == assoc.publicKeyBase64;
        final claimedCat = message['catechistId'] as String?;
        final certCat = cert.catechistId;
        final identityMatches =
            claimedCat == null || claimedCat.isEmpty || certCat == claimedCat;
        if (!certMatchesDevice || !identityMatches) {
          addLog(
            'WARN',
            'H3: certificato non vincolato all\'identità dichiarata per '
                '$remoteId (device key match=$certMatchesDevice, '
                'catechistId match=$identityMatches). Approvazione non elevata.',
          );
          valid = false;
        }
      }

      final updated = assoc.copyWith(
        // Il flag viene alzato SOLO se il certificato è stato verificato
        // contro la trust root della parrocchia. In caso contrario il
        // certificato viene comunque conservato come metadato (verifica
        // differita), ma senza elevare l'autorizzazione: un certificato non
        // verificato non deve mai valere come approvazione.
        authorizedByResponsabile: valid,
        timestampApproval: cert.timestampApproval,
        approvedByDeviceId: cert.approvedByDeviceId,
        approvalSignature: cert.approvalSignature,
        approvalSignerPublicKey: cert.signerPublicKey,
        approvalExpiresAt: cert.expiresAt,
      );
      await _security.saveAssociation(updated);

      addLog(
        valid ? 'INFO' : 'WARN',
        valid
            ? 'Certificato di approvazione verificato e allegato per $remoteId'
            : 'Certificato di approvazione ricevuto per $remoteId (trust root parrocchia non disponibile, verifica differita)',
      );
    } catch (e) {
      addLog('WARN', 'Errore attach approval da handshake: $e');
    }
  }

  Future<void> _saveAssociationIfNeeded(
    P2PIdentity remoteIdentity, {
    P2PSyncRole? remoteRole,
    String? catechistId,
  }) async {
    try {
      final existing = await _security.getAssociation(remoteIdentity.deviceId);
      if (existing != null) {
        if (!P2PSecurityService.publicKeyMatchesAssociation(
          existing,
          remoteIdentity.publicKeyBase64,
        )) {
          addLog(
            'ERROR',
            'MITM detected in _saveAssociationIfNeeded: '
                'key mismatch for ${remoteIdentity.deviceId}',
          );
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
            catechistId: existing.catechistId,
            lastSyncAt: existing.lastSyncAt,
          );
          await _security.saveAssociation(updated);
        }
        return;
      }

      final sharedSecret = await _security.computeStaticSharedSecret(
        remoteIdentity.publicKeyBase64,
      );

      await _security.registerAndSaveAssociation(
        deviceId: remoteIdentity.deviceId,
        deviceName: remoteIdentity.deviceName,
        publicKeyBase64: remoteIdentity.publicKeyBase64,
        fingerprint: remoteIdentity.fingerprint,
        sharedSecretBase64: sharedSecret,
        localRole: _state.role.name,
        remoteRole: remoteRole?.name,
        catechistId: catechistId,
      );

      addLog('INFO', 'Associazione salvata per ${remoteIdentity.deviceId}');
    } catch (e) {
      addLog('ERROR', 'Errore salvataggio associazione: $e');
    }
  }

  Future<void> readyForVerification(String endpointId) async {
    try {
      addLog(
        'INFO',
        'Pronto per verifica pairing, invio notifica a $endpointId',
      );
      final localIdentity = await _security.getLocalIdentity();
      final ready = jsonEncode({
        'type': 'p2p_ready_for_verification',
        'deviceId': localIdentity.deviceId,
        'deviceName': localIdentity.deviceName,
      });
      await _sendPayload(endpointId, ready);
    } catch (e) {
      addLog('ERROR', 'Errore in readyForVerification: $e');
    }
  }

  Future<void> _handleReadyForVerification(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    addLog('INFO', 'Notifica pronta per verifica ricevuta dal remoto');

    final remoteId = _endpointConnIdMap[endpointId];
    if (remoteId == null) {
      addLog('WARN', 'Nessun remoteId mappato per $endpointId');
      return;
    }

    if (_pendingHandshakeData.containsKey(endpointId)) {
      final hs = _pendingHandshakeData[endpointId]!;
      _pendingHandshakeRemoteRole = hs.remoteRole;
      _pendingHandshakeRemoteCatechistId = hs.remoteCatechistId;
    }
    _pendingHandshakeData.remove(endpointId);

    // FIX: sul dispositivo che ha scansionato per primo il QR, l'identità
    // remota è disponibile solo come associazione pendente: senza questo
    // passaggio confirmPairingCode() fallisce con "identità remota persa".
    if (_pendingHandshakeIdentity == null) {
      final pending = _pendingAssociations[remoteId];
      if (pending != null) {
        _pendingHandshakeIdentity = P2PIdentity(
          deviceId: pending.deviceId,
          deviceName: pending.deviceName,
          username: '',
          publicKeyBase64: pending.publicKeyBase64,
          fingerprint: pending.fingerprint,
          connectionEndpoint: '',
        );
        addLog(
          'DEBUG',
          'Identità remota ricostruita dall\'associazione pendente per $remoteId',
        );
      } else {
        addLog(
          'WARN',
          'Nessuna identità remota disponibile per $remoteId prima della verifica',
        );
      }
    }

    String? code;
    if (_state.pairingCode != null &&
        _state.status == P2PSyncStatus.sessionEstablished) {
      code = _state.pairingCode!;
      addLog('DEBUG', 'Uso pairing code già calcolato');
    } else {
      for (int attempt = 0; attempt < 20; attempt++) {
        code = await _computePairingCode(
          remoteId: remoteId,
          localNonce: _sessionPairingNonce,
          remoteNonce: _remoteSessionPairingNonce,
          endpointId: endpointId,
        );
        if (code != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (code == null) {
        addLog(
          'ERROR',
          'Impossibile calcolare il codice di pairing per $remoteId dopo 10s',
        );
        return;
      }
      addLog('DEBUG', 'Pairing code calcolato');
    }

    await _ensureSessionKey(endpointId);

    // H2: scambio dell'identità (PII) nel payload cifrato di sessione,
    // mai sul canale BLE in chiaro.
    await _sendIdentityPayload(endpointId);

    _updateState(
      _state.copyWith(
        status: P2PSyncStatus.pairingVerification,
        connectedDeviceId: endpointId,
        pairingCode: code,
      ),
    );
    addLog('INFO', 'Passaggio a pairingVerification dopo notifica remota');
  }

  Future<void> _handlePairingRejected(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    addLog('INFO', 'Pairing rifiutato dal dispositivo remoto');
    final deviceId = _endpointConnIdMap[endpointId];
    if (deviceId != null) {
      _pendingAssociations.remove(deviceId);
      addLog(
        'INFO',
        'Associazione pendente rimossa per $deviceId (rifiuto remoto)',
      );
    }
    _pendingHandshakeData.remove(endpointId);
    try {
      await _nearby.disconnectFromEndpoint(endpointId);
    } catch (_) {}
    _connectedEndpoints.remove(endpointId);
    _endpointConnIdMap.remove(endpointId);
    _endpointSessionKeys.remove(endpointId);
    _endpointLocalEphemeral.remove(endpointId);
    _endpointLocalEphemeralPub.remove(endpointId);
    _endpointRemoteEphemeralPub.remove(endpointId);
    _endpointRemoteAssocPub.remove(endpointId);
    _pendingEndpointId = null;
    _pendingHandshakeIdentity = null;
    _pendingHandshakeRemoteRole = null;
    _updateState(
      _state.copyWith(
        status: P2PSyncStatus.error,
        isPairingMode: false,
        connectedDeviceId: null,
        connectedDeviceName: null,
        connectedFingerprint: null,
        isSessionEncrypted: false,
        pairingCode: null,
        remotePairingCode: null,
        errorMessage:
            message['reason'] as String? ??
            'Associazione annullata dal remoto.',
      ),
    );
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
    addLog('INFO', 'storePendingAssociation per $deviceId');
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
        addLog(
          'DEBUG',
          'Trovato in _pendingHandshakeData: endpoint=$endpointId',
        );
        break;
      }
    }

    if (endpointId == null) {
      for (final entry in _endpointConnIdMap.entries.toList()) {
        if (entry.value == remoteDeviceId) {
          endpointId = entry.key;
          addLog('DEBUG', 'Trovato in _endpointConnIdMap: $endpointId');
          break;
        }
      }
    }

    if (endpointId == null) {
      if (_connectedEndpoints.isNotEmpty) {
        endpointId = _connectedEndpoints.first;
        addLog(
          'WARN',
          'Usato primo endpoint connesso come fallback: $endpointId',
        );
      } else {
        addLog('ERROR', 'Nessun endpoint trovato per $remoteDeviceId');
        return;
      }
    }

    final pendingAssoc = _pendingAssociations[remoteDeviceId];
    if (pendingAssoc == null) {
      addLog('ERROR', 'Nessun dato associazione pendente per $remoteDeviceId');
      return;
    }

    // Propaga il ruolo remoto e catechistId da _pendingHandshakeData prima di rimuoverlo.
    final handshakeData = _pendingHandshakeData[endpointId];
    if (handshakeData != null) {
      _pendingHandshakeRemoteRole = handshakeData.remoteRole;
      _pendingHandshakeRemoteCatechistId = handshakeData.remoteCatechistId;
    }

    // Se il nonce remoto non è ancora disponibile dall'handshake,
    // usa la variabile di istanza che viene aggiornata quando
    // il messaggio di handshake viene ricevuto.
    remoteNonce ??= _remoteSessionPairingNonce?.isNotEmpty == true
        ? _remoteSessionPairingNonce
        : null;
    if (remoteNonce != null) {
      _remoteSessionPairingNonce = remoteNonce;
    }

    // Attendi brevemente se il nonce remoto non è ancora disponibile,
    // per garantire che entrambi i dispositivi usino lo stesso
    // nonce concordato nel calcolo del codice di pairing.
    if (remoteNonce == null && _remoteSessionPairingNonce == null) {
      addLog('WARN', 'Nonce remoto non ancora disponibile, attesa 1s');
      await Future.delayed(const Duration(seconds: 1));
      remoteNonce = _remoteSessionPairingNonce;
    }

    final code = await _computePairingCode(
      remoteId: remoteDeviceId,
      localNonce: _sessionPairingNonce,
      remoteNonce: remoteNonce,
      endpointId: endpointId,
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

    _updateState(
      _state.copyWith(
        status: P2PSyncStatus.pairingVerification,
        connectedDeviceId: endpointId,
        connectedDeviceName: pendingAssoc.deviceName,
        connectedFingerprint: pendingAssoc.fingerprint,
        isSessionEncrypted: true,
        pairingCode: code,
        remoteDeviceFingerprint: pendingAssoc.fingerprint,
      ),
    );
    addLog('INFO', 'Codice pairing generato dopo scan secondo QR');

    await readyForVerification(endpointId);
  }

  Future<void> _handleAuthRequest(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final deviceId = message['deviceId'] as String?;
    final deviceName = message['deviceName'] as String? ?? 'Sconosciuto';

    // La sincronizzazione è sempre automatica: auto-accetta l'auth.
    addLog('INFO', 'Auto-accettazione auth per $deviceName');

    final ack = jsonEncode({
      'type': 'p2p_auth_response',
      'accepted': true,
      'deviceId': deviceId,
    });
    await _sendEncryptedPayload(endpointId, ack);
    _updateState(_state.copyWith(authenticatedByRemote: true));
  }

  Future<void> _handleAuthResponse(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final accepted = message['accepted'] == true;
    if (!accepted) {
      addLog('WARN', 'Sync rifiutata dal dispositivo remoto');
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: 'Sync rifiutata dal dispositivo remoto.',
        ),
      );
      return;
    }

    addLog('INFO', 'Autenticazione accettata dal remoto');

    _updateState(_state.copyWith(authenticatedByRemote: true));
    await _performBidirectionalSync(endpointId);
  }

  Future<Map<String, String>> _collectAttachmentBytes(
    List<SyncRecord> records,
  ) async {
    final attachments = <String, String>{};
    for (final record in records) {
      if (record.boxName == LocalDatabase.attachmentsBox) {
        try {
          final encrypted = await EncryptedFileStorage.readRawEncrypted(
            record.id,
          );
          attachments[record.id] = base64Encode(encrypted);
        } catch (e) {
          addLog('DEBUG', 'File allegato non trovato per ${record.id}: $e');
        }
      }
    }
    if (attachments.isNotEmpty) {
      addLog('INFO', 'Inclusi ${attachments.length} file allegati nel sync');
    }
    return attachments;
  }

  Future<void> _saveReceivedAttachmentFiles(
    Map<String, dynamic>? attachments,
  ) async {
    if (attachments == null || attachments.isEmpty) return;
    int saved = 0;
    for (final entry in attachments.entries) {
      try {
        final bytes = base64Decode(entry.value as String);
        await EncryptedFileStorage.writeRawEncrypted(entry.key, bytes);
        saved++;
      } catch (e) {
        addLog('ERROR', 'Errore salvataggio allegato ${entry.key}: $e');
      }
    }
    if (saved > 0) {
      addLog('INFO', 'Salvati $saved file allegati ricevuti');
    }
  }

  /// Verifica se il [catechistId] è presente come creatore o catechista
  /// associato in almeno una classe locale.
  bool _hasCatechistIdentity(String? catechistId) {
    if (catechistId == null || catechistId.isEmpty) return false;
    final box = LocalDatabase.classes();
    final keys = box.keys.toList();
    for (final key in keys) {
      final data = LocalDatabase.toStringDynamicMap(box.get(key));
      if (data['creatorCatechistId']?.toString() == catechistId) return true;
      final associated = data['associatedCatechistIds'] as List<dynamic>?;
      if (associated != null &&
          associated.any((e) => e.toString() == catechistId)) {
        return true;
      }
    }
    return false;
  }

  /// Adotta il [remoteCatechistId] come identità stabile di questo dispositivo
  /// quando il remoto è un catechista già presente nelle classi locali e il
  /// dispositivo locale NON ha ancora una propria identità (dispositivo fresco
  /// che si unisce come "Mio Dispositivo" a un altro dispositivo della stessa
  /// persona).
  ///
  /// In questo modo un nuovo dispositivo dello stesso catechista eredita il
  /// `catechistId` del primario: diventa "come fosse il primario" (pieni
  /// diritti, sincronizzazione di tutte le classi) e NON incrementa il numero
  /// di catechisti della classe.
  Future<void> _maybeAdoptRemoteCatechistId(String? remoteCatechistId) async {
    if (remoteCatechistId == null || remoteCatechistId.isEmpty) return;
    if (_state.role != P2PSyncRole.mioDispositivo) return;
    // Adozione consentita solo se ANCHE il remoto è un "Mio Dispositivo":
    // due dispositivi della stessa persona. Se il remoto è un altro
    // catechista, l'identità resta separata.
    if (_pendingHandshakeRemoteRole != null &&
        _pendingHandshakeRemoteRole != P2PSyncRole.mioDispositivo) {
      return;
    }

    final localCatechistId = AuthService.getCatechistId();
    if (localCatechistId == remoteCatechistId) return;
    if (_hasCatechistIdentity(localCatechistId)) return;

    addLog(
      'INFO',
      'Adozione catechistId "$remoteCatechistId" (dispositivo della stessa persona)',
    );
    AuthService.adoptCatechistId(remoteCatechistId);
  }

  Future<void> _performBidirectionalSync(String endpointId) async {
    final phase = _endpointSyncPhase[endpointId] ??= _SyncPhase2();
    if (!phase.isIdle && !phase.complete) {
      addLog('DEBUG', 'Sync già in corso per $endpointId');
      return;
    }

    if (_isSyncing &&
        _lastSyncStartTime != null &&
        DateTime.now().difference(_lastSyncStartTime!).inSeconds > 60) {
      addLog('WARN', 'Rilevato _isSyncing bloccato da >60s, reset');
      _isSyncing = false;
    }

    phase.reset();
    phase.indexSent = true;

    _lastSyncStartTime = DateTime.now();
    _isSyncing = true;

    try {
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.syncing,
          lastSyncStartedAt: DateTime.now(),
        ),
      );
      addLog('INFO', 'Avvio sincronizzazione bidirezionale con $endpointId');
      // Scambio stato inizio sync (anti-blocco)
      await _sendSyncState(endpointId, 'sync_start');

      final engine = HiveSyncEngine();
      final lastSync = await engine.getLastSyncTimestamp();
      final sendScope = await _currentSyncScope(endpointId);
      var localIndex = await engine.buildLocalIndex(sendScope);
      // H5 — non pubblicare nell'indice gli studenti tombstoned, così il peer
      // non li richiede nemmeno.
      final tombstoned = _tombstonedEntityIds();
      if (tombstoned.isNotEmpty) {
        localIndex = localIndex
            .where(
              (e) =>
                  !(e.boxName == LocalDatabase.studentsBox &&
                      tombstoned.contains(e.id)),
            )
            .toList();
      }
      addLog(
        'DEBUG',
        'Indice locale costruito: ${localIndex.length} record, lastSync: $lastSync',
      );

      // H5 — propaga i tombstone GDPR ad ogni sync, così un dispositivo che
      // era offline alla cancellazione non conserva/ripropaga la PII.
      await _sendTombstonesToEndpoint(endpointId);
      // M1 — propaga la blacklist delle revoche firmata ad ogni sync.
      await _sendRevocationsToEndpoint(endpointId);

      final indexPayload = jsonEncode({
        'type': 'p2p_sync_index',
        'index': localIndex.map((e) => e.toJson()).toList(),
        'since': lastSync.toUtc().toIso8601String(),
      });
      await _sendEncryptedPayload(endpointId, indexPayload);
      addLog('DEBUG', 'Indice sync inviato a $endpointId');
    } catch (e) {
      _isSyncing = false;
      _lastSyncStartTime = null;
      _endpointSyncPhase.remove(endpointId);
      addLog('ERROR', 'Errore sincronizzazione: $e');
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: 'Errore sincronizzazione: $e',
        ),
      );
    }
  }

  Future<void> _checkSyncComplete(String endpointId) async {
    final phase = _endpointSyncPhase[endpointId];
    if (phase == null || phase.complete) return;
    if (phase.sendDone && phase.receiveDone) {
      phase.complete = true;
      phase.indexSent = false;
      phase.sendDone = false;
      phase.receiveDone = false;
      _isSyncing = false;
      _lastSyncStartTime = null;

      // Send explicit sync complete signal to remote so it knows
      // the data exchange is fully finished on our side.
      try {
        final completePayload = jsonEncode({'type': 'p2p_sync_complete'});
        await _sendEncryptedPayload(endpointId, completePayload);
        addLog('DEBUG', 'Segnale p2p_sync_complete inviato a $endpointId');
      } catch (e) {
        addLog('WARN', 'Errore invio sync complete: $e');
      }

      // Scambio stato fine sync (anti-blocco) — informa il remoto che abbiamo terminato
      try {
        await _sendSyncState(endpointId, 'sync_end');
      } catch (e) {
        addLog('WARN', 'Errore invio sync_end: $e');
      }

      addLog(
        'INFO',
        'Sincronizzazione completata con $endpointId '
            '(${_state.totalRecordsToExchange} record totali)',
      );

      try {
        for (final entry in HiveSyncEngine.syncableBoxes.entries) {
          final box = Hive.box<Map>(entry.key);
          addLog('DEBUG', 'Box ${entry.key}: ${box.length} record');
        }
      } catch (_) {}

      _ensureLocalCatechistInClasses();

      await _applyPendingRemoteProfileIfNeeded();

      final now = DateTime.now();
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.completed,
          lastSyncAt: now,
          lastSyncEndedAt: now,
          totalRecordsToExchange: 0,
          sentRecordsCount: 0,
          receivedRecordsCount: 0,
          largeSyncInProgress: false,
        ),
      );

      _updateAssociationLastSync(endpointId, now);
    }
  }

/// Applica il profilo anagrafico ricevuto dall'handshake (ruolo "Altro
/// Catechista") al dispositivo ricevente: configura l'account locale con
/// nome, cognome e numero inseriti da chi condivide.
///
/// Se il profilo locale NON è ancora configurato (dispositivo nuovo / join),
/// lo configura con i dati del mittente.
///
/// Se il profilo locale È già configurato, verifica che l'anagrafica
/// (nome+cognome, normalizzata senza spazi/maiuscole) corrisponda a quella
/// del mittente. Se NON corrisponde, logga un warning ma NON sovrascrive
/// il profilo locale. Le classi verranno comunque aggiunte accanto a quelle
/// esistenti (merge additivo).
Future<void> _applyPendingRemoteProfileIfNeeded() async {
    final auth = AuthService();
    if (auth.isProfileConfigured) {
      final profile = _pendingHandshakeRemoteProfile;
      if (profile == null || profile.isEmpty) return;

      // Profilo già configurato: verifica corrispondenza anagrafica
      final firstName = profile['firstName'] ?? '';
      final lastName = profile['lastName'] ?? '';
      if (firstName.trim().isEmpty || lastName.trim().isEmpty) return;
      final remoteAnagrafica = AuthService.anagraficaKey(firstName, lastName);
      final localAnagrafica = AuthService.getLocalAnagraficaKey();
      if (remoteAnagrafica.isNotEmpty && remoteAnagrafica != localAnagrafica) {
        addLog(
          'WARN',
          'Anagrafica mittente ($remoteAnagrafica) diversa da locale ($localAnagrafica). '
          'Il profilo locale NON viene sovrascritto. Le classi verranno aggiunte accanto a quelle esistenti.',
        );
      } else {
        addLog(
          'INFO',
          'Anagrafica mittente corrisponde a quella locale. '
          'Le classi ricevute verranno aggiunte accanto a quelle esistenti.',
        );
      }
      _pendingHandshakeRemoteProfile = null;
      return;
    }

    // Account NON ancora configurato (dispositivo nuovo / onboarding "join"):
    // configura l'account con i dati condivisi dall'inviante. Se il mittente
    // non ha fornito un profilo esplicito ("Altro Catechista"), usa come
    // fallback l'anagrafica del peer dichiarata nel payload `p2p_identity`:
    // in modalità normale i due dispositivi appartengono alla stessa persona,
    // quindi l'anagrafica del mittente è quella corretta per il ricevente.
    var profile = _pendingHandshakeRemoteProfile;
    if (profile == null ||
        profile.isEmpty ||
        (profile['firstName'] ?? '').trim().isEmpty ||
        (profile['lastName'] ?? '').trim().isEmpty) {
      if (_peerFirstName.trim().isEmpty || _peerLastName.trim().isEmpty) {
        addLog(
          'WARN',
          'Nessun profilo disponibile per configurare l\'account del ricevente',
        );
        return;
      }
      profile = {
        'firstName': _peerFirstName,
        'lastName': _peerLastName,
        if (_pendingHandshakeRemoteProfile?['phoneNumber']?.isNotEmpty == true)
          'phoneNumber': _pendingHandshakeRemoteProfile!['phoneNumber']!,
        if (_pendingHandshakeRemoteProfile?['catechistId']?.isNotEmpty == true)
          'catechistId': _pendingHandshakeRemoteProfile!['catechistId']!,
      };
      addLog(
        'INFO',
        'Nessun profilo esplicito dal mittente: uso l\'anagrafica del peer '
            'per configurare l\'account del ricevente',
      );
    }

    final firstName = profile['firstName'] ?? '';
    final lastName = profile['lastName'] ?? '';
    if (firstName.trim().isEmpty || lastName.trim().isEmpty) return;

    addLog(
      'INFO',
      'Configuro account del dispositivo ricevente con il profilo '
          'fornito dal mittente: $firstName $lastName',
    );

    final ok = await auth.setupInitialProfile(
      firstName: firstName,
      lastName: lastName,
      phoneNumber: profile['phoneNumber'],
      createClass: false,
    );

    if (ok) {
      addLog('INFO', 'Account configurato con i dati del mittente');
      // Identità stabile opzionale (es. rubrica del Responsabile): adottata
      // DOPO la configurazione dell'account, così il catechistId coincide con
      // le assegnazioni già presenti nelle classi ricevute.
      final adoptedId = profile['catechistId'];
      if (adoptedId != null && adoptedId.isNotEmpty) {
        AuthService.adoptCatechistId(adoptedId);
        addLog('INFO', 'CatechistId adottato dal profilo condiviso');
        await _security.refreshIdentityName();
        await _security.refreshIdentityAnagrafica();
      }
    } else {
      addLog(
        'WARN',
        'Impossibile configurare l\'account con il profilo remoto',
      );
    }
    _pendingHandshakeRemoteProfile = null;
  }

  Future<void> _updateAssociationLastSync(
    String endpointId,
    DateTime now,
  ) async {
    final deviceId = _endpointConnIdMap[endpointId];
    if (deviceId == null) return;
    try {
      final assoc = await _security.getAssociation(deviceId);
      if (assoc != null) {
        await _security.saveAssociation(assoc.copyWith(lastSyncAt: now));
      }
    } catch (_) {}
  }

  /// [endpointId] permette di risolvere il catechistId del ricevente anche
  /// quando non è ancora noto nell'handshake pendente (late binding).
  void _updateClassAfterPairing({String? endpointId}) {
    try {
      final box = LocalDatabase.classes();
      const localId = AuthService.localUserId;
      final localCatechistId = AuthService.getCatechistId();
      final remoteRole = _pendingHandshakeRemoteRole;

      // Risoluzione tardiva del catechistId del ricevente: handshake →
      // endpoint corrente → profilo remoto inserito dall'inviante.
      String? remoteCatechistId;
      if (_pendingHandshakeRemoteCatechistId?.isNotEmpty == true) {
        remoteCatechistId = _pendingHandshakeRemoteCatechistId;
      } else if (endpointId != null) {
        final viaEndpoint = _endpointRemoteCatechistId[endpointId];
        if (viaEndpoint?.isNotEmpty == true) remoteCatechistId = viaEndpoint;
      }
      if (remoteCatechistId == null || remoteCatechistId.isEmpty) {
        final fromProfile = _associationRemoteProfile['catechistId'];
        if (fromProfile is String && fromProfile.isNotEmpty) {
          remoteCatechistId = fromProfile;
        }
      }

      // Per un ALTRO catechista/responsabile aggiorniamo SOLO le classi
      // scelte durante l'associazione (se presenti). Per un dispositivo
      // della stessa persona ("Mio Dispositivo") tutte le classi.
      final sharedClassIds = _associationSharedClassIds;
      final isMioDispositivo = remoteRole == P2PSyncRole.mioDispositivo;

      // Idempotenza per endpoint: senza catechistId noto non c'è nulla da
      // aggiungere (l'aggiunta avverrà alla conferma account); con
      // endpointId valorizzato l'aggiunta è gestita qui una sola volta in
      // base allo stato effettivo delle classi.
      if (!isMioDispositivo && endpointId != null) {
        if (remoteCatechistId == null || remoteCatechistId.isEmpty) {
          addLog(
            'WARN',
            'CatechistId del ricevente non ancora noto: aggiunta alla classe '
            'rinviata alla conferma account',
          );
          return;
        }
      } else if (!isMioDispositivo &&
          (remoteCatechistId == null || remoteCatechistId.isEmpty)) {
        addLog(
          'WARN',
          'CatechistId del ricevente non ancora noto: aggiunta alla classe '
          'rinviata alla conferma account',
        );
      }

      for (final key in box.keys) {
        final data = LocalDatabase.toStringDynamicMap(box.get(key));
        final ids = (data['catechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        if (!ids.contains(localId)) continue;

        // Catechista diverso: salta le classi non condivise. Se non è stata
        // fatta una selezione esplicita, ci limitiamo alle classi in cui il
        // catechista locale è effettivamente associato, così un dispositivo
        // remoto non viene aggiunto a classi non condivise con lui.
        final isLocalClass =
            (data['creatorCatechistId']?.toString() ?? '') ==
                localCatechistId ||
            (data['associatedCatechistIds'] as List? ?? [])
                .map((e) => e.toString())
                .contains(localCatechistId);
        if (!isMioDispositivo) {
          if (sharedClassIds.isNotEmpty) {
            if (!sharedClassIds.contains(key.toString())) continue;
          } else if (!isLocalClass) {
            continue;
          }
        }

        Map<String, int> counts = {};
        if (data['catechistDeviceCounts'] is Map) {
          counts = (data['catechistDeviceCounts'] as Map).map(
            (k, v) => MapEntry(k.toString(), (v as num).toInt()),
          );
        }

        List<String> associatedIds = [];
        if (data['associatedCatechistIds'] is List) {
          associatedIds = (data['associatedCatechistIds'] as List)
              .map((e) => e.toString())
              .toList();
        }

        if (remoteRole == P2PSyncRole.mioDispositivo) {
          final current = counts[localCatechistId] ?? 1;
          counts[localCatechistId] = current + 1;
          addLog(
            'INFO',
            'Incrementato conteggio dispositivi per $localCatechistId a ${counts[localCatechistId]}',
          );
        } else if (!isMioDispositivo &&
            remoteCatechistId != null &&
            remoteCatechistId.isNotEmpty &&
            remoteCatechistId != localCatechistId) {
          final alreadyAssociated = associatedIds.contains(remoteCatechistId);
          if (!alreadyAssociated) {
            associatedIds.add(remoteCatechistId);
            final current = counts[remoteCatechistId] ?? 0;
            counts[remoteCatechistId] = current + 1;
            addLog(
              'INFO',
              'Aggiunto catechista $remoteCatechistId alla classe ${data['name']}',
            );
          }

          if ((data['creatorCatechistId'] as String? ?? '').isEmpty) {
            data['creatorCatechistId'] = localCatechistId;
          }
        }

        data['catechistDeviceCounts'] = counts;
        data['associatedCatechistIds'] = associatedIds;
        box.put(key, data);
        addLog('INFO', 'Classe aggiornata dopo pairing');
      }
    } catch (e) {
      addLog('ERROR', 'Errore aggiornamento classe dopo pairing: $e');
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
          addLog(
            'INFO',
            'Aggiunto catechista locale alla classe ${data['name']}',
          );
        }
      }
    } catch (e) {
      addLog('ERROR', 'Errore _ensureLocalCatechistInClasses: $e');
    }
  }

  String _getCombinedSessionNonce() {
    final local = _sessionPairingNonce;
    final remote = _remoteSessionPairingNonce;
    if (local != null && remote != null) {
      final sorted = <String>[local, remote]..sort();
      return '${sorted[0]}${sorted[1]}';
    }
    return local ?? remote ?? '';
  }

  Future<SecretKeyData> _deriveSessionKey(
    String deviceId, {
    DateTime? at,
    String? endpointId,
  }) async {
    final assoc = await _security.getAssociation(deviceId);
    if (assoc == null) {
      throw Exception('Associazione non trovata per $deviceId');
    }
    final localIdentity = await _security.getLocalIdentity();
    final isInitiator = localIdentity.deviceId.compareTo(deviceId) < 0;
    final session = await _security.createEphemeralSession(
      remoteDeviceId: deviceId,
      remoteDeviceName: assoc.deviceName,
      remotePublicKeyBase64: assoc.publicKeyBase64,
      isInitiator: isInitiator,
      sessionNonce: _getCombinedSessionNonce(),
      at: at,
      localEphemeralKeyPair: endpointId != null
          ? _endpointLocalEphemeral[endpointId]
          : null,
      remoteEphemeralPublicKeyBase64: endpointId != null
          ? _endpointRemoteEphemeralPub[endpointId]
          : null,
    );
    var sessionKey = session.sessionKey;
    // M5: quando entrambi i peer hanno scambiato la chiave per-associazione
    // (via p2p_identity cifrato), la chiave di sessione incorpora il DH
    // dedicato dell'associazione. La chiave per-associazione è ora "viva".
    if (endpointId != null) {
      final remoteAssocPub = _endpointRemoteAssocPub[endpointId];
      final localKeyPair = assoc.keyPair;
      if (remoteAssocPub != null &&
          remoteAssocPub.isNotEmpty &&
          localKeyPair != null) {
        sessionKey = await _security.applyAssociationFactor(
          sessionKey: sessionKey,
          localAssociationKeyPair: localKeyPair,
          remoteAssociationPublicBase64: remoteAssocPub,
        );
      }
    }
    return sessionKey;
  }

  /// Garantisce che per [endpointId] siano disponibili le chiavi di sessione
  /// della finestra corrente e di quella precedente, rimuovendo le chiavi
  /// scadute. La rotazione è quindi "pigra" (avviene alla prima trasmissione
  /// della nuova finestra) e viene completata periodicamente dal timer di
  /// rotazione.
  Future<void> _ensureSessionKey(String endpointId, {DateTime? at}) async {
    final currentWindow = P2PSecurityService.sessionWindowIndex(at);
    final keepWindows = <int>{
      currentWindow,
      P2PSecurityService.previousWindowIndex(currentWindow),
    };

    final existing = _endpointSessionKeys[endpointId];
    if (existing != null &&
        existing.any((k) => k.windowIndex == currentWindow)) {
      final stale = existing.where((k) => !keepWindows.contains(k.windowIndex));
      if (stale.isNotEmpty) {
        _endpointSessionKeys[endpointId] = existing
            .where((k) => keepWindows.contains(k.windowIndex))
            .toList();
      }
      return;
    }

    final deviceId = _endpointConnIdMap[endpointId];
    if (deviceId == null) {
      throw Exception('Nessun deviceId mappato per endpoint $endpointId');
    }

    final pending = _pendingAssociations[deviceId];
    if (pending == null && await _security.getAssociation(deviceId) == null) {
      throw Exception(
        'Impossibile derivare chiave sessione: associazione non trovata per $deviceId',
      );
    }

    // Deriva le chiavi per finestra corrente e precedente (convergenza tra i
    // due peer senza handshake aggiuntivi: stessa finestra → stessa chiave).
    final keys = <_EndpointSessionKey>[];
    for (final window in keepWindows) {
      final windowStart = P2PSecurityService.sessionWindowStart(window);
      if (pending != null) {
        final localIdentity = await _security.getLocalIdentity();
        final isInitiator = localIdentity.deviceId.compareTo(deviceId) < 0;
        final session = await _security.createEphemeralSession(
          remoteDeviceId: deviceId,
          remoteDeviceName: pending.deviceName,
          remotePublicKeyBase64: pending.publicKeyBase64,
          isInitiator: isInitiator,
          sessionNonce: _getCombinedSessionNonce(),
          at: windowStart,
          localEphemeralKeyPair: _endpointLocalEphemeral[endpointId],
          remoteEphemeralPublicKeyBase64:
              _endpointRemoteEphemeralPub[endpointId],
        );
        keys.add(
          _EndpointSessionKey(windowIndex: window, key: session.sessionKey),
        );
      } else {
        keys.add(
          _EndpointSessionKey(
            windowIndex: window,
            key: await _deriveSessionKey(
              deviceId,
              at: windowStart,
              endpointId: endpointId,
            ),
          ),
        );
      }
    }
    _endpointSessionKeys[endpointId] = keys;
  }

  /// M5 — Applica il fattore di associazione alla chiave di sessione corrente
  /// dopo lo scambio della chiave per-associazione (payload `p2p_identity`).
  /// La chiave aggiornata diventa quella attiva per l'INVIO; la chiave
  /// precedente resta nel set di decifratura per i messaggi in transito, così
  /// il passaggio non interrompe la comunicazione.
  Future<void> _applyAssociationUpgrade(String endpointId) async {
    final deviceId = _endpointConnIdMap[endpointId];
    if (deviceId == null) return;
    final keys = _endpointSessionKeys[endpointId];
    if (keys == null || keys.isEmpty) return;
    final currentWindow = P2PSecurityService.sessionWindowIndex();
    if (!keys.any((k) => k.windowIndex == currentWindow)) return;

    // Durante il pairing iniziale, l'associazione non è ancora stata salvata
    // (viene salvata alla ricezione di p2p_association_confirmed).
    // In questo caso saltiamo l'upgrade e riproveremo al prossimo giro
    // (es. rotazione chiavi o nuova connessione).
    final assocExists = await _security.getAssociation(deviceId);
    if (assocExists == null) {
      addLog('DEBUG', 'M5: associazione non ancora salvata per $deviceId, upgrade rimandato');
      return;
    }

    try {
      final upgraded = await _deriveSessionKey(
        deviceId,
        at: P2PSecurityService.sessionWindowStart(currentWindow),
        endpointId: endpointId,
      );
      final oldCurrent = keys
          .where((k) => k.windowIndex == currentWindow)
          .toList();
      final others = keys.where((k) => k.windowIndex != currentWindow).toList();
      _endpointSessionKeys[endpointId] = [
        _EndpointSessionKey(windowIndex: currentWindow, key: upgraded),
        ...others,
        ...oldCurrent,
      ];
      addLog('INFO', 'M5: fattore di associazione attivo per $endpointId');
    } catch (e) {
      addLog('WARN', 'M5: upgrade associazione fallito per $endpointId: $e');
    }
  }

  /// Restituisce la chiave di sessione attiva (finestra corrente) per
  /// [endpointId], o null se non disponibile.
  SecretKeyData? _currentSessionKey(String endpointId, {DateTime? at}) {
    final keys = _endpointSessionKeys[endpointId];
    if (keys == null || keys.isEmpty) return null;
    final currentWindow = P2PSecurityService.sessionWindowIndex(at);
    for (final k in keys) {
      if (k.windowIndex == currentWindow) return k.key;
    }
    return null;
  }

  /// Rotazione periodica: rigenera la chiave di sessione di tutti gli endpoint
  /// connessi alla scadenza della finestra corrente.
  void _startSessionKeyRotation() {
    _sessionKeyRotationTimer?.cancel();
    _sessionKeyRotationTimer = Timer.periodic(
      P2PSecurityService.sessionKeyRotation,
      (_) => _rotateSessionKeys(),
    );
  }

  Future<void> _rotateSessionKeys() async {
    for (final endpointId in _endpointConnIdMap.keys.toList()) {
      try {
        await _ensureSessionKey(endpointId);
      } catch (e) {
        addLog('WARN', 'Rotazione chiave fallita per $endpointId: $e');
      }
    }
  }

  Future<void> _sendEncryptedPayload(
    String endpointId,
    String plainText,
  ) async {
    await _ensureSessionKey(endpointId);
    final sessionKey = _currentSessionKey(endpointId);
    if (sessionKey == null) {
      addLog('ERROR', 'Nessuna chiave di sessione per $endpointId');
      throw Exception('Nessuna chiave di sessione per $endpointId');
    }
    final localIdentity = await _security.getLocalIdentity();
    final wrapped = jsonEncode({
      'senderId': localIdentity.deviceId,
      'senderFingerprint': localIdentity.fingerprint,
      'senderPublicKey': localIdentity.publicKeyBase64,
      'data': plainText,
    });
    final encrypted = await _security.encryptPayload(wrapped, sessionKey);
    final payloadStr = encrypted.encode();
    addLog(
      'DEBUG',
      'Invio payload cifrato a $endpointId (tipo: ${_extractType(plainText)})',
    );
    await _sendPayload(endpointId, payloadStr);
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
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    if (_state.awaitingConfirmation || !_state.authenticatedByRemote) {
      addLog('DEBUG', 'Sync index ignorato: attesa autenticazione');
      return;
    }
    final phase = _endpointSyncPhase[endpointId] ??= _SyncPhase2();
    if (!phase.isIdle && !phase.complete) {
      addLog('DEBUG', 'Sync index ignorato: sync già in corso per $endpointId');
      return;
    }
    phase.reset();
    try {
      phase.indexSent = true;
      final engine = HiveSyncEngine();
      final sendScope = await _currentSyncScope(endpointId);
      var localIndex = await engine.buildLocalIndex(sendScope);
      // H5 — non pubblicare nell'indice gli studenti tombstoned.
      final tombstoned = _tombstonedEntityIds();
      if (tombstoned.isNotEmpty) {
        localIndex = localIndex
            .where(
              (e) =>
                  !(e.boxName == LocalDatabase.studentsBox &&
                      tombstoned.contains(e.id)),
            )
            .toList();
      }

      // Canale parrocchiale globale: scambia riunioni e avvisi parrocchiali
      // (in chiaro per la rete) insieme all'indice delle classi.
      await sendParishChannel(endpointId);

      // H5 — propaga i tombstone GDPR ad ogni sync (dispositivi offline).
      await _sendTombstonesToEndpoint(endpointId);
      // M1 — propaga la blacklist delle revoche firmata ad ogni sync.
      await _sendRevocationsToEndpoint(endpointId);

      final remoteIndexData = message['index'] as List<dynamic>? ?? [];
      final remoteIndex = remoteIndexData
          .map((e) => SyncIndexEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      addLog(
        'INFO',
        'Indice remoto ricevuto: ${remoteIndex.length} record, locale: ${localIndex.length}',
      );

      final neededFromRemote = await engine.computeNeededRecords(remoteIndex);
      final neededFromLocal = engine.computeNeededRecordsFromLocal(
        localIndex,
        remoteIndex,
      );

      final totalToExchange = neededFromRemote.length + neededFromLocal.length;
      addLog(
        'INFO',
        'Scambio necessario: $totalToExchange record '
            '(invio ${neededFromLocal.length}, ricezione ${neededFromRemote.length})',
      );

      _updateState(
        _state.copyWith(
          totalRecordsToExchange: totalToExchange,
          sentRecordsCount: 0,
          receivedRecordsCount: 0,
          largeSyncInProgress: totalToExchange > 50,
        ),
      );

      if (totalToExchange > 50) {
        addLog(
          'INFO',
          'Sincronizzazione estesa rilevata: $totalToExchange record. '
              'Verrà mostrato l\'avanzamento.',
        );
      }

      if (neededFromLocal.isNotEmpty) {
        final localRecords = await engine.fetchRecords(
          neededFromLocal,
          sendScope,
        );
        addLog('INFO', 'Invio ${localRecords.length} record al remoto');
        _updateState(_state.copyWith(sentRecordsCount: localRecords.length));
        final attachmentBytes = await _collectAttachmentBytes(localRecords);
        final channelPayload = await _buildSyncDataPayload(
          records: localRecords,
          endpointId: endpointId,
        );
        final recordsPayload = jsonEncode({
          'type': 'p2p_sync_data',
          ...channelPayload,
          if (attachmentBytes.isNotEmpty) 'attachments': attachmentBytes,
        });
        await _sendEncryptedPayload(endpointId, recordsPayload);
        addLog('INFO', 'Invio completato: ${localRecords.length} record');
      } else {
        final emptyPayload = jsonEncode({
          'type': 'p2p_sync_data',
          'records': [],
        });
        await _sendEncryptedPayload(endpointId, emptyPayload);
        addLog(
          'DEBUG',
          'Invio segnale sync_data vuoto (nessun record da inviare)',
        );
      }
      phase.sendDone = true;

      if (neededFromRemote.isNotEmpty) {
        addLog(
          'INFO',
          'Richiesta ${neededFromRemote.length} record dal remoto',
        );
        final requestPayload = jsonEncode({
          'type': 'p2p_sync_request',
          'keys': neededFromRemote,
        });
        await _sendEncryptedPayload(endpointId, requestPayload);
      } else {
        addLog('INFO', 'Nessun record necessario dal remoto, invio segnale');
        final emptyRequest = jsonEncode({
          'type': 'p2p_sync_request',
          'keys': [],
        });
        await _sendEncryptedPayload(endpointId, emptyRequest);
        phase.receiveDone = true;
        await _checkSyncComplete(endpointId);
      }
    } catch (e) {
      addLog('ERROR', 'Errore elaborazione indice: $e');
      _endpointSyncPhase.remove(endpointId);
      _isSyncing = false;
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: 'Errore elaborazione indice: $e',
        ),
      );
    }
  }

  Future<void> _handleSyncRequest(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final phase = _endpointSyncPhase[endpointId] ??= _SyncPhase2();
    try {
      final engine = HiveSyncEngine();
      final sendScope = await _currentSyncScope(endpointId);
      final keys =
          (message['keys'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      addLog('DEBUG', 'Richiesta sync ricevuta per ${keys.length} record');

      if (keys.isEmpty) {
        phase.sendDone = true;
        await _checkSyncComplete(endpointId);
        return;
      }

      final records = await engine.fetchRecords(keys, sendScope);
      addLog('INFO', 'Invio ${records.length} record richiesti');
      _updateState(
        _state.copyWith(
          sentRecordsCount: _state.sentRecordsCount + records.length,
        ),
      );
      final attachmentBytes = await _collectAttachmentBytes(records);
      final channelPayload = await _buildSyncDataPayload(
        records: records,
        endpointId: endpointId,
      );
      final recordsPayload = jsonEncode({
        'type': 'p2p_sync_data',
        ...channelPayload,
        if (attachmentBytes.isNotEmpty) 'attachments': attachmentBytes,
      });
      await _sendEncryptedPayload(endpointId, recordsPayload);
      addLog('INFO', 'Invio ${records.length} record completato');

      phase.sendDone = true;
      await _checkSyncComplete(endpointId);
    } catch (e) {
      addLog('ERROR', 'Errore risposta richiesta sync: $e');
      _endpointSyncPhase.remove(endpointId);
      _isSyncing = false;
    }
  }

  Future<void> _handleSyncData(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final phase = _endpointSyncPhase[endpointId];
    if (phase == null || phase.isIdle) {
      if (_state.awaitingConfirmation || !_state.authenticatedByRemote) {
        addLog('DEBUG', 'Dati incrementali ignorati: attesa autenticazione');
        return;
      }
      try {
        final engine = HiveSyncEngine();
        final receiveScope = await _currentReceiveScope(endpointId);
        final records = await _deserializeChannelRecords(
          endpointId,
          message['records'],
        );
        // Diritto all'Oblio: ignora record di entita' Tombstoned.
        final tombstoned = _tombstonedEntityIds();
        final filtered = records
            .where(
              (r) =>
                  !(r.boxName == LocalDatabase.studentsBox &&
                      tombstoned.contains(r.id)),
            )
            .toList();
        if (records.isNotEmpty) {
          final secretKey = await _secretKeyForEndpoint(endpointId);
          await engine.applyRemoteRecords(
            filtered,
            scopes: receiveScope,
            secretKey: secretKey,
          );
          await engine.saveLastSyncTimestamp(DateTime.now().toUtc());
          addLog(
            'DEBUG',
            'Dati incrementali applicati: ${filtered.length} record',
          );
        }
        await _saveReceivedAttachmentFiles(
          message['attachments'] as Map<String, dynamic>?,
        );
        final ack = jsonEncode({
          'type': 'p2p_sync_ack',
          'received': filtered.length,
        });
        await _sendEncryptedPayload(endpointId, ack);
      } catch (e) {
        addLog('ERROR', 'Errore applicazione dati incrementali: $e');
      }
      return;
    }
    try {
      final engine = HiveSyncEngine();
      final receiveScope = await _currentReceiveScope(endpointId);
      final records = await _deserializeChannelRecords(
        endpointId,
        message['records'],
      );
      addLog(
        'DEBUG',
        'Dati sync ricevuti: ${records.length} record da applicare',
      );

      // Diritto all'Oblio: ignora i record delle entità eliminate.
      final tombstoned = _tombstonedEntityIds();
      final filtered = records
          .where(
            (r) =>
                !(r.boxName == LocalDatabase.studentsBox &&
                    tombstoned.contains(r.id)),
          )
          .toList();

      final secretKey = await _secretKeyForEndpoint(endpointId);
      final result = await engine.applyRemoteRecords(
        filtered,
        scopes: receiveScope,
        secretKey: secretKey,
      );
      addLog(
        'INFO',
        'Applicati ${result.receivedRecords} record, ${result.conflictsResolved} conflitti risolti',
      );
      await _saveReceivedAttachmentFiles(
        message['attachments'] as Map<String, dynamic>?,
      );

      _updateState(
        _state.copyWith(
          receivedRecordsCount:
              _state.receivedRecordsCount + result.receivedRecords,
          largeSyncInProgress:
              _state.totalRecordsToExchange > 50 &&
              _state.sentRecordsCount +
                      _state.receivedRecordsCount +
                      result.receivedRecords <
                  _state.totalRecordsToExchange,
        ),
      );

      phase.receiveDone = true;
      addLog('DEBUG', 'ReceiveDone per $endpointId');

      await engine.saveLastSyncTimestamp(result.syncTimestamp);

      final ack = jsonEncode({
        'type': 'p2p_sync_ack',
        'received': result.receivedRecords,
      });
      await _sendEncryptedPayload(endpointId, ack);
      addLog('DEBUG', 'Sync ACK inviato a $endpointId');

      await _checkSyncComplete(endpointId);
    } catch (e) {
      addLog('ERROR', 'Errore applicazione dati: $e');
      if (_endpointSyncPhase.containsKey(endpointId)) {
        _endpointSyncPhase.remove(endpointId);
        _isSyncing = false;
        _updateState(
          _state.copyWith(
            status: P2PSyncStatus.error,
            errorMessage: 'Errore applicazione dati: $e',
          ),
        );
      }
    }
  }

  Future<void> _handleSyncAck(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final phase = _endpointSyncPhase[endpointId];
    if (phase == null) {
      addLog('DEBUG', 'Sync ACK ignorato: nessuna sync attiva per $endpointId');
      return;
    }
    phase.sendDone = true;
    addLog('DEBUG', 'Sync ACK ricevuto per $endpointId, sendDone=true');
    await _checkSyncComplete(endpointId);
  }

  Future<void> _handleSyncComplete(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final phase = _endpointSyncPhase[endpointId];
    if (phase == null) {
      addLog('DEBUG', 'Sync complete ignorato: nessuna sync attiva per $endpointId');
      return;
    }
    // The remote has finished sending all its data. We can mark receiveDone
    // if we haven't already, and check for completion.
    phase.receiveDone = true;
    addLog('INFO', 'Segnale sync complete ricevuto da $endpointId');
    await _checkSyncComplete(endpointId);
  }

  Future<void> _handleAssociationConfirmed(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    addLog('INFO', 'Associazione confermata dal dispositivo remoto');
    final deviceId = message['deviceId'] as String?;
    final alreadyConfirmed =
        deviceId != null && _sessionConfirmedDevices.contains(deviceId);
    if (deviceId != null) {
      _sessionConfirmedDevices.add(deviceId);
      final pending = _pendingAssociations[deviceId];
      if (pending != null) {
        final existing = await _security.getAssociation(deviceId);
        if (existing == null) {
          await _security.registerAndSaveAssociation(
            deviceId: pending.deviceId,
            deviceName: pending.deviceName,
            publicKeyBase64: pending.publicKeyBase64,
            fingerprint: pending.fingerprint,
            sharedSecretBase64: pending.sharedSecretBase64,
            localRole: _state.role.name,
            remoteRole: _pendingHandshakeRemoteRole?.name,
            catechistId: _pendingHandshakeRemoteCatechistId,
          );
          addLog(
            'INFO',
            'Associazione salvata in Hive su conferma remota per ${pending.deviceName}',
          );
        }
        _pendingAssociations.remove(deviceId);
      } else {
        addLog(
          'WARN',
          'Nessuna associazione pendente per $deviceId in _handleAssociationConfirmed',
        );
        final remoteIdentity = _pendingHandshakeIdentity;
        if (remoteIdentity != null) {
          await _saveAssociationIfNeeded(
            remoteIdentity,
            remoteRole: _pendingHandshakeRemoteRole,
            catechistId: _pendingHandshakeRemoteCatechistId,
          );
        }
      }

      // Aggiorna l'associazione con il catechistId remoto. La conferma
      // trasporta il catechistId RISOLTO (dopo l'eventuale adozione), quindi
      // è la fonte più affidabile.
      final msgCatechistId =
          (message['catechistId'] as String?)?.trim().isNotEmpty == true
          ? message['catechistId'] as String
          : null;
      final remoteCatechistId =
          msgCatechistId ?? _pendingHandshakeRemoteCatechistId;
      if (remoteCatechistId != null) {
        _endpointRemoteCatechistId[endpointId] = remoteCatechistId;
        final saved = await _security.getAssociation(deviceId);
        if (saved != null) {
          await _security.saveAssociation(
            saved.copyWith(catechistId: remoteCatechistId),
          );
        }
        await _maybeAdoptRemoteCatechistId(remoteCatechistId);
      }
    }

    final wasPairingVerification =
        _state.status == P2PSyncStatus.pairingVerification;

    if (wasPairingVerification) {
      if (!alreadyConfirmed) {
        _updateClassAfterPairing();
      } else {
        addLog(
          'DEBUG',
          'Conferma remota già gestita per $deviceId, aggiornamento classe saltato',
        );
      }
      _pairingTimeoutTimer?.cancel();
      _pairingTimeoutTimer = null;
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.completed,
          authenticatedByRemote: true,
          isPairingMode: false,
        ),
      );

      if (!_continuousModeActive) {
        addLog('INFO', 'Avvio modalità continua dopo conferma remota');
        _startContinuousMode();
      }

      // Applica il profilo anagrafico ricevuto (nome, cognome, telefono)
      // per configurare l'account del dispositivo ricevente.
      await _applyPendingRemoteProfileIfNeeded();
    } else {
      addLog(
        'DEBUG',
        'Conferma remota ricevuta prima della verifica locale, associazione salvata',
      );
    }

    final localIdentity = await _security.getLocalIdentity();
    final ack = jsonEncode({
      'type': 'p2p_association_ack',
      'deviceId': localIdentity.deviceId,
      'deviceName': localIdentity.deviceName,
    });
    await _sendPayload(endpointId, ack);
    addLog('DEBUG', 'ACK associazione inviato (non cifrato)');
  }

  Future<void> confirmPairingCode() async {
    // Allow proceeding if status is already completed (remote confirmed first).
    // In that case we still need to complete local side (save association, etc.)
    // but won't send another confirmation.
    final alreadyCompleted = _state.status == P2PSyncStatus.completed;
    if (!alreadyCompleted && _state.status != P2PSyncStatus.pairingVerification) {
      return;
    }
    if (_state.connectedDeviceId == null) return;

    final endpointId = _state.connectedDeviceId!;
    final remoteIdentity = _pendingHandshakeIdentity;
    if (remoteIdentity == null) {
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: 'Errore: identità remota persa durante verifica.',
        ),
      );
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
          catechistId: _pendingHandshakeRemoteCatechistId,
        );
        addLog(
          'INFO',
          'Associazione salvata in Hive dopo verifica per ${pending.deviceName}',
        );
      } else {
        await _saveAssociationIfNeeded(
          remoteIdentity,
          remoteRole: _pendingHandshakeRemoteRole,
          catechistId: _pendingHandshakeRemoteCatechistId,
        );
      }
    }

    // Aggiorna l'associazione con il catechistId remoto
    if (_pendingHandshakeRemoteCatechistId != null) {
      final saved = await _security.getAssociation(remoteIdentity.deviceId);
      if (saved != null) {
        await _security.saveAssociation(
          saved.copyWith(catechistId: _pendingHandshakeRemoteCatechistId),
        );
      }
    }

    // Un dispositivo fresco che si unisce come "Mio Dispositivo" eredita il
    // catechistId del primario prima di inviare la conferma.
    //
    // PRIMA, verifichiamo una possibile discordanza: se entrambi i dispositivi
    // della stessa persona hanno già classi con due catechistId DIVERSI,
    // chiediamo all'utente quale identità conservare (default: la classe che
    // invia). La sincronizzazione come "Mio Dispositivo" DEVE unificare il
    // catechistId; per un "Altro Catechista" il catechistId NON va mai
    // sincronizzato/adottato.
    final remoteCatechistId = _pendingHandshakeRemoteCatechistId;
    final localCatechistId = AuthService.getCatechistId();
    final remoteHasId = _endpointRemoteHasClasses[endpointId] == true;
    final isSamePersonPair =
        _state.role == P2PSyncRole.mioDispositivo &&
        _pendingHandshakeRemoteRole == P2PSyncRole.mioDispositivo;

    if (isSamePersonPair &&
        remoteCatechistId != null &&
        remoteCatechistId.isNotEmpty &&
        remoteCatechistId != localCatechistId &&
        _hasCatechistIdentity(localCatechistId) &&
        remoteHasId) {
      final defaultId = _computeDefaultCatechistId(
        localCatechistId,
        remoteCatechistId,
      );
      // Solo il dispositivo che NON possiede l'identità di default sospende il
      // flusso e chiede all'utente (l'altro mantiene la propria identità).
      if (defaultId != null && defaultId == remoteCatechistId) {
        addLog(
          'INFO',
          'Discordanza catechistId: locale=$localCatechistId, remoto=$remoteCatechistId. '
              'Chiedo all\'utente quale identità conservare (default: $defaultId)',
        );
        _pendingChoiceEndpoint = endpointId;
        _pendingChoiceRemoteIdentity = remoteIdentity;
        _updateState(
          _state.copyWith(
            awaitingCatechistIdChoice: true,
            pendingCatechistChoiceLocalId: localCatechistId,
            pendingCatechistChoiceRemoteId: remoteCatechistId,
            pendingCatechistChoiceRemoteName: remoteIdentity.deviceName,
            pendingCatechistChoiceDefault: defaultId,
          ),
        );
        return; // attende la scelta dell'utente via chooseCatechistId()
      }
    }

    // --- Verifica identità anagrafica (anti-associazione errata) ---
    // Vale SOLO per coppie "Mio Dispositivo" (stessa persona) e solo quando il
    // dispositivo locale ha GIÀ un'identità/classe: l'anagrafica del nuovo
    // dispositivo deve corrispondere a quella locale, altrimenti l'associazione
    // viene bloccata con un errore (possibile dispositivo di un'altra persona).
    //
    // Per "Altro Catechista" l'anagrafica diversa è attesa e NON blocca.
    if (isSamePersonPair && _hasCatechistIdentity(localCatechistId)) {
      final remoteAnagraficaKey = AuthService.anagraficaKey(
        remoteIdentity.firstName,
        remoteIdentity.lastName,
      );
      if (remoteAnagraficaKey.isNotEmpty &&
          remoteAnagraficaKey != AuthService.getLocalAnagraficaKey()) {
        addLog(
          'ERROR',
          'Mismatch anagrafica in coppia Mio-Dispositivo: locale='
              '${AuthService.getLocalAnagraficaKey()}, remoto=$remoteAnagraficaKey '
              '(${remoteIdentity.deviceName}). Associazione bloccata.',
        );
        _pendingChoiceEndpoint = null;
        _pendingChoiceRemoteIdentity = null;
        _updateState(
          _state.copyWith(
            status: P2PSyncStatus.error,
            errorMessage:
                'Identità anagrafica non corrispondente: il dispositivo '
                '"${remoteIdentity.deviceName}" è configurato con un nome '
                'diverso da quello del tuo account. Verifica di aver '
                'selezionato il dispositivo corretto.',
          ),
        );
        return; // blocca l'associazione
      }
    }

    await _maybeAdoptRemoteCatechistId(remoteCatechistId);

    if (!alreadyCompleted) {
      await _completePairing(endpointId, remoteIdentity);
    } else {
      // Remote already confirmed, just finalize local state
      _pairingCodesByDeviceId.remove(remoteIdentity.deviceId);
      _pendingAssociations.remove(remoteIdentity.deviceId);

      // Handshake ordinato: se siamo l'iniziatore e l'handshake non è ancora
      // partito, avvialo; altrimenti attendi l'account config dal mittente.
      final localIdentityForTardy = await _security.getLocalIdentity();
      final tardyIsInitiator =
          localIdentityForTardy.deviceId.compareTo(remoteIdentity.deviceId) <= 0;
      if (tardyIsInitiator) {
        try {
          addLog('INFO', 'Avvio handshake ordinato dopo conferma tardiva (iniziatore)');
          // Associaz. già salvata in Hive nel ramo precedente, avvia handshake
          await _security.getAssociation(remoteIdentity.deviceId);
          // Assicura modalità continua attiva
          if (!_continuousModeActive) await _startContinuousMode();
          await Future.delayed(const Duration(milliseconds: 300));
          await startOrderedHandshake(endpointId);
        } catch (e) {
          addLog('WARN', 'Handshake tardivo fallito: $e');
        }
      } else {
        addLog('INFO', 'Conferma tardiva come ricevente: attendo account config dal mittente');
        if (!_continuousModeActive) await _startContinuousMode();
      }

      _pendingHandshakeIdentity = null;
      _pendingHandshakeRemoteRole = null;
      _pendingHandshakeRemoteCatechistId = null;
      _pendingChoiceEndpoint = null;
      _pendingChoiceRemoteIdentity = null;
      _peerFirstName = '';
      _peerLastName = '';

      _pairingTimeoutTimer?.cancel();
      _pairingTimeoutTimer = null;
      _updateState(
        _state.copyWith(
          isPairingMode: false,
          pairingCode: null,
          remotePairingCode: null,
          awaitingCatechistIdChoice: false,
        ),
      );
      addLog('INFO', 'Pairing già confermato dal remoto, completato lato locale (handshake ordinato in attesa se ricevente)');
    }
  }

  /// Completa l'associazione (invio conferma cifrata, aggiornamento classi,
  /// modalità continua e prima sincronizzazione). Usata sia dal flusso normale
  /// che dopo la scelta del catechistId in caso di discordanza.
  Future<void> _completePairing(
    String endpointId,
    P2PIdentity remoteIdentity,
  ) async {
    final localIdentity = await _security.getLocalIdentity();
    final confirmed = jsonEncode({
      'type': 'p2p_association_confirmed',
      'deviceId': localIdentity.deviceId,
      'deviceName': localIdentity.deviceName,
      'catechistId': AuthService.getCatechistId(),
    });

    final iAmInitiator =
        localIdentity.deviceId.compareTo(remoteIdentity.deviceId) <= 0;

    try {
      await _ensureSessionKey(endpointId);
      // H2: invia l'identità (PII) SOLO nel payload cifrato di sessione.
      await _sendIdentityPayload(endpointId);
      await _sendEncryptedPayload(endpointId, confirmed);
      addLog('DEBUG', 'Conferma associazione inviata (cifrata)');
    } catch (e) {
      addLog('ERROR', 'Invio conferma associazione fallito: $e');
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.error,
          errorMessage: 'Errore invio conferma: $e',
          pairingCode: null,
          remotePairingCode: null,
          isPairingMode: false,
          awaitingCatechistIdChoice: false,
        ),
      );
      return;
    }

    // Idempotenza: evita doppi conteggi di dispositivi/catechisti se il flusso
    // viene completato più volte per lo stesso dispositivo.
    final isNewPairing = !_sessionConfirmedDevices.contains(remoteIdentity.deviceId);
    if (isNewPairing) {
      _sessionConfirmedDevices.add(remoteIdentity.deviceId);
      // L'aggiunta del catechista alla classe viene gestita dall'handshake
      // ordinato (step 1) per l'inviante; per il ricevente che non invia
      // account, manteniamo il comportamento legacy come fallback se non
      // parte l'handshake ordinato (compatibilità).
      if (!iAmInitiator) {
        _updateClassAfterPairing();
      }
    } else {
      addLog(
        'DEBUG',
        'Pairing già completato per ${remoteIdentity.deviceName}, aggiornamento classe saltato',
      );
    }

    _pendingAssociations.remove(remoteIdentity.deviceId);
    _pendingHandshakeIdentity = null;
    _pendingHandshakeRemoteRole = null;
    _pendingHandshakeRemoteCatechistId = null;
    _pendingChoiceEndpoint = null;
    _pendingChoiceRemoteIdentity = null;
    _pairingCodesByDeviceId.remove(remoteIdentity.deviceId);

    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = null;
    _updateState(
      _state.copyWith(
        status: P2PSyncStatus.completed,
        authenticatedByRemote: true,
        isPairingMode: false,
        pairingCode: null,
        remotePairingCode: null,
        awaitingCatechistIdChoice: false,
      ),
    );

    if (!_continuousModeActive) {
      addLog('INFO', 'Avvio modalità continua dopo associazione');
      _startContinuousMode();
    }

    if (iAmInitiator) {
      // Handshake ordinato: inviante aggiunge catechista, invia account → classe
      await Future.delayed(const Duration(milliseconds: 500));
      addLog('INFO', 'Avvio handshake ordinato (account → classe → verifica continuo) per $endpointId');
      await startOrderedHandshake(endpointId);
    } else {
      addLog('INFO', 'In attesa di handshake ordinato dal dispositivo inviante (_receiver_)');
      // Il ricevente resta in attesa di p2p_account_config; nessun sync immediato.
      // Il via libera arriverà dopo la verifica del sync continuo.
    }

    _ensureLocalCatechistInClasses();

    // Fallback legacy: applica profilo se handshake ordinato non è partito
    // (compatibilità con dispositivi precedenti).
    if (!_associationHandshakeStep.containsKey(endpointId)) {
      await _applyPendingRemoteProfileIfNeeded();
    }

    addLog('INFO', 'Associazione completata con successo (handshake ordinato in corso se iniziatore)');
  }

  /// Identità di default da conservare in caso di discordanza tra due
  /// catechistId della stessa persona: quella associata alla classe che invia
  /// (il creatore della classe condivisa). Deterministico su entrambi i
  /// dispositivi. Fallback sicuro: l'identità locale.
  String? _computeDefaultCatechistId(String localCat, String remoteCat) {
    final sharedIds = <String>{
      ..._associationSharedClassIds,
      ..._endpointSharedClassIds.values.expand((s) => s),
    };
    final creators = <String, String>{};
    if (sharedIds.isNotEmpty) {
      try {
        final box = LocalDatabase.classes();
        for (final key in box.keys) {
          if (!sharedIds.contains(key.toString())) continue;
          final data = LocalDatabase.toStringDynamicMap(box.get(key));
          final creator = data['creatorCatechistId']?.toString() ?? '';
          creators[key.toString()] = creator;
        }
      } catch (_) {}
    }
    return computeDefaultCatechistId(localCat, remoteCat, creators);
  }

  /// Invocato dall'UI quando l'utente sceglie quale catechistId conservare in
  /// caso di discordanza. Propaga la scelta al dispositivo remoto e completa
  /// l'associazione.
  Future<void> chooseCatechistId(String chosenId) async {
    if (chosenId.isEmpty) return;
    final endpointId = _pendingChoiceEndpoint;
    final remoteIdentity = _pendingChoiceRemoteIdentity;
    if (endpointId == null || remoteIdentity == null) {
      addLog('WARN', 'chooseCatechistId senza contesto di risoluzione attivo');
      return;
    }

    final localCat = AuthService.getCatechistId();
    if (chosenId != localCat) {
      addLog(
        'INFO',
        'Utente ha scelto il catechistId "$chosenId" (precedente: $localCat)',
      );
      AuthService.adoptCatechistId(chosenId);
    }

    final saved = await _security.getAssociation(remoteIdentity.deviceId);
    if (saved != null) {
      await _security.saveAssociation(saved.copyWith(catechistId: chosenId));
    }

    try {
      final msg = jsonEncode({
        'type': 'p2p_catechist_id_choice',
        'catechistId': chosenId,
      });
      await _sendEncryptedPayload(endpointId, msg);
      addLog('DEBUG', 'Scelta catechistId inviata (cifrata)');
    } catch (e) {
      addLog('ERROR', 'Invio scelta catechistId fallito: $e');
    }

    _endpointRemoteCatechistId[endpointId] = chosenId;

    _pendingChoiceEndpoint = null;
    _pendingChoiceRemoteIdentity = null;
    _updateState(
      _state.copyWith(
        awaitingCatechistIdChoice: false,
        pendingCatechistChoiceLocalId: null,
        pendingCatechistChoiceRemoteId: null,
        pendingCatechistChoiceRemoteName: null,
        pendingCatechistChoiceDefault: null,
      ),
    );

    await _completePairing(endpointId, remoteIdentity);
  }

  /// Gestisce la scelta del catechistId ricevuta dall'altro dispositivo.
  /// L'altro lato (quello che mantiene l'identità di default) riceve la scelta,
  /// che può confermare la propria identità o (nel caso di override) adottare
  /// quella scelta dall'utente remoto.
  Future<void> _handleCatechistIdChoice(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final chosenId = message['catechistId'] as String?;
    if (chosenId == null || chosenId.isEmpty) return;
    addLog('INFO', 'Scelta catechistId remota ricevuta');

    _endpointRemoteCatechistId[endpointId] = chosenId;

    final deviceId = _endpointConnIdMap[endpointId];
    if (deviceId != null) {
      final saved = await _security.getAssociation(deviceId);
      if (saved != null) {
        await _security.saveAssociation(saved.copyWith(catechistId: chosenId));
      }
    }

    // Adotta la stessa identità SOLO se siamo due dispositivi della stessa
    // persona ("Mio Dispositivo"). Mai per un "Altro Catechista".
    if (_state.role == P2PSyncRole.mioDispositivo &&
        _pendingHandshakeRemoteRole == P2PSyncRole.mioDispositivo) {
      final localCat = AuthService.getCatechistId();
      if (chosenId != localCat) {
        addLog(
          'INFO',
          'Adozione catechistId remoto "$chosenId" in seguito alla scelta condivisa',
        );
        AuthService.adoptCatechistId(chosenId);
      }
    }

    // Ricomputa lo scope e riavvia subito la sincronizzazione per convergere.
    final phase = _endpointSyncPhase[endpointId];
    if (phase == null || phase.isIdle) {
      await _performBidirectionalSync(endpointId);
    }
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
    _endpointLocalEphemeral.remove(endpointId);
    _endpointLocalEphemeralPub.remove(endpointId);
    _endpointRemoteEphemeralPub.remove(endpointId);
    _endpointRemoteAssocPub.remove(endpointId);
    _endpointSyncPhase.remove(endpointId);
    _pendingEndpointId = null;
    _pendingHandshakeIdentity = null;
    _pendingHandshakeRemoteRole = null;
    _pendingHandshakeRemoteCatechistId = null;
    _pendingAssociations.clear();
    _pairingCodesByDeviceId.clear();

    _updateState(
      _state.copyWith(
        status: P2PSyncStatus.idle,
        isPairingMode: false,
        connectedDeviceId: null,
        connectedDeviceName: null,
        connectedFingerprint: null,
        isSessionEncrypted: false,
        pairingCode: null,
        remotePairingCode: null,
        errorMessage:
            'Codice di verifica non corrispondente. '
            'Possibile attacco MitM: associazione annullata.',
      ),
    );
  }

  Future<void> confirmSync() async {
    if (!_state.awaitingConfirmation) {
      addLog('WARN', 'confirmSync chiamato senza richiesta in sospeso');
      return;
    }

    _cancelConfirmationTimeout();
    addLog('INFO', 'Sync confermata dall\'utente');
    final endpointId = _state.connectedDeviceId;
    final confirmedDeviceId = _state.pendingConfirmationDeviceId;

    final alreadyAuthed = _state.authenticatedByRemote;

    if (endpointId != null && !alreadyAuthed && !_isInitiator) {
      final ack = jsonEncode({'type': 'p2p_auth_response', 'accepted': true});
      try {
        await _sendEncryptedPayload(endpointId, ack);
        addLog('DEBUG', 'Risposta auth positiva inviata a $endpointId');
      } catch (e) {
        addLog('ERROR', 'Invio risposta auth fallito: $e');
        _updateState(
          _state.copyWith(
            awaitingConfirmation: false,
            status: P2PSyncStatus.error,
            errorMessage: 'Errore invio risposta auth: $e',
          ),
        );
        return;
      }
    }

    if (confirmedDeviceId != null) {
      _sessionConfirmedDevices.add(confirmedDeviceId);
      addLog('DEBUG', 'Dispositivo $confirmedDeviceId aggiunto ai confermati');
    }

    _updateState(
      _state.copyWith(
        awaitingConfirmation: false,
        authenticatedByRemote: true,
        pendingConfirmationDeviceName: null,
        pendingConfirmationDeviceId: null,
        status: P2PSyncStatus.sessionEstablished,
      ),
    );

    if (endpointId != null && alreadyAuthed) {
      addLog('INFO', 'Avvio sincronizzazione dopo conferma utente (initiator)');
      await _performBidirectionalSync(endpointId);
    }
  }

  Future<void> rejectSync() async {
    if (!_state.awaitingConfirmation) {
      addLog('WARN', 'rejectSync chiamato senza richiesta in sospeso');
      return;
    }

    _cancelConfirmationTimeout();
    addLog('INFO', 'Sync rifiutata dall\'utente');
    final endpointId = _state.connectedDeviceId;

    if (endpointId != null) {
      final ack = jsonEncode({'type': 'p2p_auth_response', 'accepted': false});
      try {
        await _sendEncryptedPayload(endpointId, ack);
        addLog('DEBUG', 'Risposta auth negativa inviata a $endpointId');
      } catch (e) {
        addLog('ERROR', 'Invio risposta auth negativa fallito: $e');
      }
    }

    _updateState(
      _state.copyWith(
        awaitingConfirmation: false,
        pendingConfirmationDeviceName: null,
        pendingConfirmationDeviceId: null,
        status: P2PSyncStatus.idle,
      ),
    );
  }

  Future<void> sendSyncData(
    String endpointId,
    Map<String, dynamic> data,
  ) async {
    final payload = jsonEncode({'type': 'p2p_sync_data', ...data});
    await _sendEncryptedPayload(endpointId, payload);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CANALE CLASSE: cifratura per-classe dei record sync (Rete Parrocchiale)
  // ─────────────────────────────────────────────────────────────────────────

  /// Determina il codice univoco della classe a cui appartiene un record,
  /// o `null` per record non legati a una classe (inclusi i record della
  /// classe stessa, che restano in chiaro per il bootstrap del titolo).
  String? _recordClassUniqueCode(SyncRecord record) {
    try {
      if (record.boxName == LocalDatabase.classesBox) return null;
      final data = record.data;
      final code = data['classUniqueCode']?.toString();
      if (code != null && code.isNotEmpty) return code;
      final classId = data['classId']?.toString();
      if (classId != null && classId.isNotEmpty) {
        final raw = LocalDatabase.classes().get(classId);
        if (raw != null) {
          final code2 = LocalDatabase.toStringDynamicMap(
            raw,
          )['uniqueCode']?.toString();
          if (code2 != null && code2.isNotEmpty) return code2;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Risolve classId + nome dal codice univoco di una classe.
  ({String classId, String name})? _classInfoByUniqueCode(
    String classUniqueCode,
  ) {
    try {
      final box = LocalDatabase.classes();
      for (final key in box.keys) {
        final data = LocalDatabase.toStringDynamicMap(box.get(key));
        if (data['uniqueCode']?.toString() == classUniqueCode) {
          return (
            classId: key.toString(),
            name: data['name']?.toString() ?? '',
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// true se il dispositivo remoto ha TITOLO sulla classe [classUniqueCode]
  /// (è un membro riconosciuto della classe), oppure se sta facendo onboarding
  /// senza classi (bootstrap del titolo da parte di chi condivide la classe).
  bool _remoteHasClassTitle(String endpointId, String classUniqueCode) {
    final remoteCat = _endpointRemoteCatechistId[endpointId];
    if (remoteCat == null || remoteCat.isEmpty) {
      return _endpointRemoteHasClasses[endpointId] == false;
    }
    try {
      final box = LocalDatabase.classes();
      for (final key in box.keys) {
        final data = LocalDatabase.toStringDynamicMap(box.get(key));
        if (data['uniqueCode']?.toString() != classUniqueCode) continue;
        final creator = data['creatorCatechistId']?.toString() ?? '';
        final catechists = (data['catechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        final associated = (data['associatedCatechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        return remoteCat == creator ||
            catechists.contains(remoteCat) ||
            associated.contains(remoteCat);
      }
    } catch (_) {}
    return false;
  }

  /// Shared secret dell'associazione verso [endpointId], usato per
  /// verificare i timestamp firmati ricevuti (SignedLww). Null se il peer
  /// non è associato.
  Future<String?> _secretKeyForEndpoint(String endpointId) async {
    final deviceId =
        _endpointConnIdMap[endpointId] ?? _nearbyEndpointToDevice[endpointId];
    if (deviceId == null) return null;
    try {
      return await _security.getSharedSecret(deviceId);
    } catch (_) {
      return null;
    }
  }

  /// Firma i timestamp dei [records] con il shared secret dell'associazione
  /// verso [endpointId]. Se il peer non è ancora associato (o non c'è una
  /// chiave condivisa) i record partono senza firma: il ricevente userà il
  /// confronto timestamp legacy.
  Future<List<SyncRecord>> _signRecordsForEndpoint(
    String? endpointId,
    List<SyncRecord> records,
  ) async {
    if (endpointId == null || records.isEmpty) return records;
    final deviceId =
        _endpointConnIdMap[endpointId] ?? _nearbyEndpointToDevice[endpointId];
    if (deviceId == null) return records;
    String? secretKey;
    try {
      secretKey = await _security.getSharedSecret(deviceId);
    } catch (_) {}
    if (secretKey == null || secretKey.isEmpty) return records;
    final engine = HiveSyncEngine();
    return engine.signRecordsForChannel(records, secretKey);
  }

  /// Costruisce il campo `records` del messaggio `p2p_sync_data`.
  ///
  /// - Se il peer supporta il canale classe (cifratura per-classe), i record
  ///   vengono raggruppati per classe e cifrati con la Class_Encryption_Key.
  ///   Ai membri riconosciuti della classe viene allegata anche la chiave
  ///   (bootstrap del titolo); agli altri solo il blob opaco (relay).
  /// - Se il peer è vecchio (nessun flag), si usa il formato legacy in chiaro.
  Future<Map<String, dynamic>> _buildSyncDataPayload({
    required List<SyncRecord> records,
    String? endpointId,
  }) async {
    final targetEndpoint = endpointId;
    final classChannelEnabled =
        targetEndpoint != null &&
        _endpointSupportsClassChannel[targetEndpoint] == true;

    // Diritto all'Oblio (H5): mai inviare dati di studenti eliminati tramite
    // tombstone, anche se il record live è ancora presente sul box locale.
    final tombstoned = _tombstonedEntityIds();
    if (tombstoned.isNotEmpty) {
      final before = records.length;
      records = records
          .where(
            (r) =>
                !(r.boxName == LocalDatabase.studentsBox &&
                    tombstoned.contains(r.id)),
          )
          .toList();
      if (records.length != before) {
        addLog(
          'WARN',
          'H5: esclusi ${before - records.length} record tombstoned dalla sync',
        );
      }
    }

    // Firma i timestamp prima dell'invio: il ricevente accetta il LWW solo
    // con firma valida (vedi SignedLww.remoteWins).
    final signed = await _signRecordsForEndpoint(endpointId, records);

    if (!classChannelEnabled || records.isEmpty) {
      // H4: nessun fallback in chiaro per i dati delle classi. Se il peer non
      // supporta il canale classe (versione legacy), i record SCOPERITI
      // (senza classe, es. configurazione globale) vengono comunque inviati;
      // i record delle classi (studenti e relativi) NON vengono trasmessi in
      // chiaro: un peer che farebbe da relay non deve poter leggere i dati di
      // una classe di cui non è membro.
      final engine = HiveSyncEngine();
      final scopedOut = signed
          .where((r) => _recordClassUniqueCode(r) != null)
          .length;
      if (scopedOut > 0) {
        addLog(
          'WARN',
          'H4: $scopedOut record di classe omessi (peer senza canale classe, '
              'niente fallback in chiaro)',
        );
      }
      final plain = signed
          .where((r) => _recordClassUniqueCode(r) == null)
          .toList();
      return {'records': engine.serializeRecords(plain)};
    }

    final plain = <Map<String, dynamic>>[];
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final record in signed) {
      final code = _recordClassUniqueCode(record);
      if (code == null) {
        plain.add(record.toJson());
      } else {
        grouped.putIfAbsent(code, () => []).add(record.toJson());
      }
    }

    final enc = <String, dynamic>{};
    for (final entry in grouped.entries) {
      final code = entry.key;
      final classInfo = _classInfoByUniqueCode(code);
      if (classInfo != null &&
          ClassChannelService.getKeyByUniqueCode(code) == null) {
        await ClassChannelService.getOrCreateKey(
          classId: classInfo.classId,
          classUniqueCode: code,
          className: classInfo.name,
        );
      }
      final blob = await ClassChannelService.encryptRecords(code, entry.value);
      if (blob == null) {
        // H4: mai inviare record di classe in chiaro. Se la cifratura per
        // classe non è disponibile, i record vengono OMESSI (il ricevente li
        // riceverà via grant/relay) invece di esporli in chiaro.
        addLog(
          'WARN',
          'H4: cifratura classe $code non disponibile, ${entry.value.length} '
              'record omessi (no plaintext fallback)',
        );
        continue;
      }
      if (_remoteHasClassTitle(targetEndpoint, code)) {
        final key = ClassChannelService.getKeyByUniqueCode(code);
        if (key != null) {
          blob['key'] = key.toMap();
        }
      }
      enc[code] = blob;
    }

    if (enc.isEmpty && plain.isEmpty) {
      return {'records': <dynamic>[]};
    }
    return {
      'records': {'enc': enc, 'plain': plain},
    };
  }

  /// Deserializza il campo `records` di un messaggio `p2p_sync_data`,
  /// gestendo sia il formato legacy (List) sia quello del canale classe
  /// (Map `{enc, plain}`). I blob delle classi senza titolo vengono
  /// conservati in relay e NON applicati.
  Future<List<SyncRecord>> _deserializeChannelRecords(
    String endpointId,
    dynamic recordsField,
  ) async {
    final engine = HiveSyncEngine();
    if (recordsField is List) {
      return engine.deserializeRecords(recordsField);
    }
    if (recordsField is! Map) return [];
    final map = Map<String, dynamic>.from(recordsField);
    final results = <SyncRecord>[];

    results.addAll(
      engine.deserializeRecords(map['plain'] as List<dynamic>? ?? const []),
    );

    final enc = map['enc'] as Map<String, dynamic>? ?? {};
    for (final entry in enc.entries) {
      final code = entry.key;
      if (entry.value is! Map) continue;
      final blob = Map<String, dynamic>.from(entry.value as Map);

      final keyData = blob['key'];
      if (keyData is Map) {
        final keyMap = Map<String, dynamic>.from(keyData);
        await ClassChannelService.storeKey(
          classId: keyMap['classId']?.toString() ?? '',
          classUniqueCode: code,
          className: keyMap['className']?.toString() ?? '',
          keyBase64: keyMap['keyBase64']?.toString() ?? '',
          grantorCatechistId: keyMap['grantorCatechistId']?.toString() ?? '',
        );
        blob.remove('key');
      }

      final decrypted = await ClassChannelService.decryptRecords(code, blob);
      if (decrypted != null) {
        results.addAll(engine.deserializeRecords(decrypted));
      } else {
        // Nessun titolo (o chiave non disponibile): relay-only.
        ClassChannelService.storeRelayedCiphertext(code, blob);
        addLog('INFO', 'Relay: blob classe $code ricevuto senza titolo');
      }
    }
    return results;
  }

  /// Applica gli eventuali blob cifrati "relay" della classe [classUniqueCode]
  /// una volta ottenuto il titolo. Usato dopo l'import di un grant QR.
  Future<void> tryApplyRelayedCiphertext(String classUniqueCode) async {
    final blob = ClassChannelService.takeRelayedCiphertext(classUniqueCode);
    if (blob == null) return;
    final decrypted = await ClassChannelService.decryptRecords(
      classUniqueCode,
      blob,
    );
    if (decrypted == null) {
      addLog(
        'WARN',
        'Relay blob per $classUniqueCode non decifrabile dopo il grant',
      );
      return;
    }
    try {
      final engine = HiveSyncEngine();
      final records = engine.deserializeRecords(decrypted);
      final result = await engine.applyRemoteRecords(records, scopes: null);
      addLog(
        'INFO',
        'Applicati ${result.receivedRecords} record relayed della classe '
            '$classUniqueCode dopo acquisizione titolo',
      );
    } catch (e) {
      addLog('ERROR', 'Errore applicazione record relayed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HANDSHAKE ORDINATO: account → classe → verifica sync continuo
  // Protocollo richiesto:
  //  1. Inviante (normale/responsabile) aggiunge catechista alla classe e invia
  //     informazioni account (nome, cognome, id, telefono) al ricevente.
  //  2. Ricevente configura account e invia conferma (p2p_account_config_ack).
  //  3. Inviante invia informazioni classe (p2p_class_info), ricevente registra.
  //  4. Ricevente invia conferma registrazione (p2p_class_info_ack).
  //  5. Verifica sincronizzazione costante con scambio stato inizio/fine.
  //  Solo al termine → via libera (continuousSyncVerified = true).
  // ─────────────────────────────────────────────────────────────────────────

  /// Avvia l'handshake ordinato per [endpointId] dal lato INVANTE.
  /// Chiamato DOPO la conferma del pairing (association salvata) sul dispositivo
  /// che ha il ruolo di mittente (normale o responsabile).
  Future<void> startOrderedHandshake(String endpointId) async {
    if (_associationHandshakeStep.containsKey(endpointId) &&
        _associationHandshakeStep[endpointId] != 'idle') {
      addLog('DEBUG', 'Handshake ordinato già in corso per $endpointId');
      return;
    }
    // Step 1: aggiungi catechista alla classe localmente (idempotente)
    try {
      _updateClassAfterPairing(endpointId: endpointId);
      addLog('INFO', 'Handshake ordinato: catechista aggiunto alla classe locale');
    } catch (e) {
      addLog('WARN', 'Errore aggiunta catechista alla classe: $e');
    }

    // Diagnostica: un peer che non dichiara supporto canale classe/parrocchia
    // è probabilmente una versione precedente senza handshake ordinato.
    if (_endpointSupportsClassChannel[endpointId] != true ||
        _endpointSupportsParishChannel[endpointId] != true) {
      addLog(
        'WARN',
        'Peer $endpointId senza supporto handshake/canali dichiarato: '
        'possibile versione app precedente, la conferma account potrebbe '
        'non arrivare',
      );
    }

    _associationHandshakeStep[endpointId] = 'accountSent';
    _updateState(
      _state.copyWith(
        isAssociationHandshakeActive: true,
        associationHandshakeStep: 'accountSent',
        continuousSyncVerified: false,
      ),
    );
    await _sendAccountConfig(endpointId);

    // Watchdog: se la conferma account non arriva entro timeout, ritenta o fallisce
    _handshakeTimeoutTimers[endpointId]?.cancel();
    _handshakeTimeoutTimers[endpointId] = Timer(_accountAckTimeout, () {
      final step = _associationHandshakeStep[endpointId];
      if (step == 'accountSent') {
        addLog('WARN', 'Timeout conferma account per $endpointId, ritento invio');
        _sendAccountConfig(endpointId);
        // Re-arm second timeout → errore
        _handshakeTimeoutTimers[endpointId]?.cancel();
        _handshakeTimeoutTimers[endpointId] = Timer(_accountAckTimeout, () {
          if (_associationHandshakeStep[endpointId] == 'accountSent') {
            addLog('ERROR', 'Handshake ordinato fallito: nessuna conferma account');
            _failOrderedHandshake(endpointId, 'Timeout conferma configurazione account');
          }
        });
      }
    });
  }

  Future<void> _sendAccountConfig(String endpointId) async {
    try {
      final localCatechistId = AuthService.getCatechistId();
      // Profilo da inviare: se l'associazione ha un profilo remoto esplicito
      // (altroCatechista con dati inseriti dall'inviante) usa quello,
      // altrimenti usa il profilo locale (mioDispositivo / responsabile).
      String firstName = '';
      String lastName = '';
      String phone = '';
      String catechistId = localCatechistId;
      if (_associationRemoteProfile.isNotEmpty) {
        firstName = _associationRemoteProfile['firstName'] ?? '';
        lastName = _associationRemoteProfile['lastName'] ?? '';
        phone = _associationRemoteProfile['phoneNumber'] ?? '';
        if ((_associationRemoteProfile['catechistId'] ?? '').isNotEmpty) {
          catechistId = _associationRemoteProfile['catechistId']!;
        }
      } else {
        final box = LocalDatabase.auth();
        firstName = box.get('first_name', defaultValue: '') as String? ?? '';
        lastName = box.get('last_name', defaultValue: '') as String? ?? '';
        phone = box.get('phone_number', defaultValue: '') as String? ?? '';
      }
      final msg = jsonEncode({
        'type': 'p2p_account_config',
        'firstName': firstName,
        'lastName': lastName,
        'catechistId': catechistId,
        'phoneNumber': phone,
        'senderRole': _state.role.name,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      await _sendEncryptedPayload(endpointId, msg);
      addLog('INFO', 'Account config inviata a $endpointId');
      _updateState(
        _state.copyWith(
          status: P2PSyncStatus.associationAccountConfig,
          associationHandshakeStep: 'accountSent',
        ),
      );
    } catch (e) {
      addLog('ERROR', 'Errore invio account config a $endpointId: $e');
      _failOrderedHandshake(endpointId, 'Errore invio configurazione account: $e');
    }
  }

  Future<void> _handleAccountConfig(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final firstName = (message['firstName'] as String?)?.trim() ?? '';
    final lastName = (message['lastName'] as String?)?.trim() ?? '';
    final catechistId = (message['catechistId'] as String?)?.trim() ?? '';
    final phone = (message['phoneNumber'] as String?)?.trim() ?? '';

    addLog('INFO', 'Account config ricevuta da $endpointId');

    // Marca handshake attivo anche sul ricevente
    _associationHandshakeStep[endpointId] = 'accountReceived';
    _updateState(
      _state.copyWith(
        isAssociationHandshakeActive: true,
        associationHandshakeStep: 'accountReceived',
        status: P2PSyncStatus.associationAccountConfig,
      ),
    );

    bool accepted = false;
    String reason = '';
    try {
      // Se il profilo locale non è configurato, configuralo con i dati ricevuti
      final auth = AuthService();
      if (!auth.isProfileConfigured) {
        if (firstName.isEmpty || lastName.isEmpty) {
          reason = 'Dati account incompleti (nome/cognome mancanti)';
        } else {
          final ok = await auth.setupInitialProfile(
            firstName: firstName,
            lastName: lastName,
            phoneNumber: phone.isEmpty ? null : phone,
            createClass: false,
          );
          if (ok) {
            if (catechistId.isNotEmpty) {
              AuthService.adoptCatechistId(catechistId);
              await _security.refreshIdentityName();
              await _security.refreshIdentityAnagrafica();
            }
            accepted = true;
            addLog('INFO', 'Account configurato dal ricevente con dati inviante');
          } else {
            reason = 'Impossibile configurare account';
          }
        }
      } else {
        // Profilo già esistente: verifica coerenza anagrafica (non sovrascrive)
        final localKey = AuthService.getLocalAnagraficaKey();
        final remoteKey = AuthService.anagraficaKey(firstName, lastName);
        if (remoteKey.isNotEmpty && remoteKey != localKey) {
          addLog(
            'WARN',
            'Anagrafica account ricevuta diversa dalla locale '
            '($remoteKey vs $localKey) — non sovrascrivo',
          );
        }
        // Se il catechistId ricevuto è diverso e il dispositivo non ha classi,
        // adotto solo se è lo stesso individuo (mioDispositivo)
        if (catechistId.isNotEmpty && catechistId != AuthService.getCatechistId()) {
          final senderRoleStr = message['senderRole'] as String? ?? '';
          final isSamePerson = senderRoleStr == P2PSyncRole.mioDispositivo.name &&
              _state.role == P2PSyncRole.mioDispositivo;
          if (isSamePerson && !_hasCatechistIdentity(AuthService.getCatechistId())) {
            AuthService.adoptCatechistId(catechistId);
            addLog('INFO', 'CatechistId adottato da account config');
          }
        }
        accepted = true;
      }
      // Memorizza profilo per eventuale uso successivo
      _pendingHandshakeRemoteProfile = {
        'firstName': firstName,
        'lastName': lastName,
        if (phone.isNotEmpty) 'phoneNumber': phone,
        if (catechistId.isNotEmpty) 'catechistId': catechistId,
      };
      if (catechistId.isNotEmpty) {
        _endpointRemoteCatechistId[endpointId] = catechistId;
      }
    } catch (e) {
      reason = 'Eccezione configurazione: $e';
      addLog('ERROR', 'Errore configurazione account ricevente: $e');
    }

    final ack = jsonEncode({
      'type': 'p2p_account_config_ack',
      'accepted': accepted,
      'reason': reason,
      // Identificativo effettivo del ricevente (anche dopo eventuale adozione):
      // consente all'inviante di associare il catechista del ricevente alla
      // classe condivisa selezionata.
      'catechistId': AuthService.getCatechistId(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    try {
      await _sendEncryptedPayload(endpointId, ack);
      addLog('INFO', 'Conferma account config inviata a $endpointId (accepted=$accepted)');
    } catch (e) {
      addLog('ERROR', 'Errore invio ack account config: $e');
    }

    if (accepted) {
      _associationHandshakeStep[endpointId] = 'accountConfirmed';
      _updateState(
        _state.copyWith(associationHandshakeStep: 'accountConfirmed'),
      );
    } else {
      _failOrderedHandshake(endpointId, reason);
    }
  }

  Future<void> _handleAccountConfigAck(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final accepted = message['accepted'] == true;
    _handshakeTimeoutTimers[endpointId]?.cancel();

    if (!accepted) {
      final reason = message['reason'] as String? ?? 'Rifiutata';
      addLog('WARN', 'Conferma account NEGATIVA da $endpointId: $reason');
      _failOrderedHandshake(endpointId, 'Ricevente ha rifiutato config account: $reason');
      return;
    }

    addLog('INFO', 'Conferma account POSITIVA ricevuta da $endpointId');
    _associationHandshakeStep[endpointId] = 'accountConfirmed';
    _updateState(
      _state.copyWith(associationHandshakeStep: 'accountConfirmed'),
    );

    // Late binding: memorizza il catechistId effettivo del ricevente e
    // aggiorna la/e classe condivisa/e selezionata aggiungendolo.
    final remoteCatechistId = (message['catechistId'] as String?)?.trim() ?? '';
    if (remoteCatechistId.isNotEmpty) {
      _endpointRemoteCatechistId[endpointId] = remoteCatechistId;
      if (_pendingHandshakeRemoteCatechistId?.isNotEmpty != true) {
        _pendingHandshakeRemoteCatechistId = remoteCatechistId;
      }
      try {
        _updateClassAfterPairing(endpointId: endpointId);
      } catch (e) {
        addLog('WARN', 'Errore aggiornamento classe con catechista ricevente: $e');
      }
    }

    // Step 3: invia informazioni classe
    _associationHandshakeStep[endpointId] = 'classSent';
    _updateState(
      _state.copyWith(
        status: P2PSyncStatus.associationClassInfo,
        associationHandshakeStep: 'classSent',
      ),
    );
    await _sendClassInfo(endpointId);

    _handshakeTimeoutTimers[endpointId]?.cancel();
    _handshakeTimeoutTimers[endpointId] = Timer(_classAckTimeout, () {
      if (_associationHandshakeStep[endpointId] == 'classSent') {
        addLog('WARN', 'Timeout conferma classe per $endpointId, ritento');
        _sendClassInfo(endpointId);
        _handshakeTimeoutTimers[endpointId]?.cancel();
        _handshakeTimeoutTimers[endpointId] = Timer(_classAckTimeout, () {
          if (_associationHandshakeStep[endpointId] == 'classSent') {
            addLog('ERROR', 'Handshake ordinato fallito: nessuna conferma classe');
            _failOrderedHandshake(endpointId, 'Timeout conferma registrazione classe');
          }
        });
      }
    });
  }

  Future<void> _sendClassInfo(String endpointId) async {
    try {
      // Raccogli classi condivise per questo endpoint
      final sharedIds = await _sharedClassIdsForEndpoint(endpointId);
      List<Map<String, dynamic>> classesPayload = [];
      final classKeysPayload = <String, dynamic>{};
      if (sharedIds == null) {
        // Tutte le classi (stesso catechista)
        final box = LocalDatabase.classes();
        for (final key in box.keys) {
          final data = LocalDatabase.toStringDynamicMap(box.get(key));
          classesPayload.add({'id': key.toString(), 'data': data});
          // Includi chiave di canale per bootstrap titolo sul ricevente
          final uniqueCode = data['uniqueCode']?.toString() ?? '';
          if (uniqueCode.isNotEmpty) {
            try {
              var cKey = ClassChannelService.getKeyByUniqueCode(uniqueCode);
              cKey ??= await ClassChannelService.getOrCreateKey(
                classId: key.toString(),
                classUniqueCode: uniqueCode,
                className: data['name']?.toString() ?? key.toString(),
              );
              classKeysPayload[key.toString()] = cKey.toMap();
            } catch (_) {}
          }
        }
      } else if (sharedIds.isNotEmpty) {
        final box = LocalDatabase.classes();
        for (final id in sharedIds) {
          final data = LocalDatabase.toStringDynamicMap(box.get(id));
          if (data.isNotEmpty) {
            classesPayload.add({'id': id, 'data': data});
            final uniqueCode = data['uniqueCode']?.toString() ?? '';
            if (uniqueCode.isNotEmpty) {
              try {
                var cKey = ClassChannelService.getKeyByUniqueCode(uniqueCode);
                cKey ??= await ClassChannelService.getOrCreateKey(
                  classId: id,
                  classUniqueCode: uniqueCode,
                  className: data['name']?.toString() ?? id,
                );
                classKeysPayload[id] = cKey.toMap();
              } catch (_) {}
            }
          }
        }
      } else {
        // fallback: classe corrente
        final current = _getCurrentClassId();
        if (current.isNotEmpty) {
          final data = LocalDatabase.toStringDynamicMap(
            LocalDatabase.classes().get(current),
          );
          if (data.isNotEmpty) {
            classesPayload.add({'id': current, 'data': data});
            final uniqueCode = data['uniqueCode']?.toString() ?? '';
            if (uniqueCode.isNotEmpty) {
              try {
                var cKey = ClassChannelService.getKeyByUniqueCode(uniqueCode);
                cKey ??= await ClassChannelService.getOrCreateKey(
                  classId: current,
                  classUniqueCode: uniqueCode,
                  className: data['name']?.toString() ?? current,
                );
                classKeysPayload[current] = cKey.toMap();
              } catch (_) {}
            }
          }
        }
      }

      final msg = jsonEncode({
        'type': 'p2p_class_info',
        'classes': classesPayload,
        'classKeys': classKeysPayload,
        'sharedClassIds': sharedIds?.toList() ?? [],
        'senderRole': _state.role.name,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      await _sendEncryptedPayload(endpointId, msg);
      addLog('INFO', 'Class info inviata a $endpointId (${classesPayload.length} classi, ${classKeysPayload.length} chiavi)');
    } catch (e) {
      addLog('ERROR', 'Errore invio class info: $e');
      _failOrderedHandshake(endpointId, 'Errore invio informazioni classe: $e');
    }
  }

  Future<void> _handleClassInfo(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    addLog('INFO', 'Class info ricevuta da $endpointId');
    _associationHandshakeStep[endpointId] = 'classReceived';
    _updateState(
      _state.copyWith(
        isAssociationHandshakeActive: true,
        associationHandshakeStep: 'classReceived',
        status: P2PSyncStatus.associationClassInfo,
      ),
    );

    bool accepted = false;
    String reason = '';
    int applied = 0;
    try {
      final classes = (message['classes'] as List<dynamic>? ?? []);
      final box = LocalDatabase.classes();
      for (final entry in classes) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        final id = map['id']?.toString() ?? '';
        final dataRaw = map['data'];
        if (id.isEmpty || dataRaw is! Map) continue;
        final data = Map<String, dynamic>.from(dataRaw);
        // Merge: se la classe esiste già, preserva nameLocked e aggiorna campi
        final existing = box.get(id);
        if (existing != null) {
          final ex = LocalDatabase.toStringDynamicMap(existing);
          // Non sovrascrivere uniqueCode / id
          data['uniqueCode'] ??= ex['uniqueCode'];
          data['nameLocked'] = (ex['nameLocked'] == true) || (data['nameLocked'] == true);
        } else {
          // Nuova classe: assicurati che campi obbligatori esistano
          data['uniqueCode'] ??= data['uniqueCode'] ?? _generateUniqueCode();
          data['nameLocked'] ??= true;
        }
        // Assicura che il catechista locale sia incluso
        const localId = AuthService.localUserId;
        final catechistIds = (data['catechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        if (!catechistIds.contains(localId)) {
          catechistIds.add(localId);
          data['catechistIds'] = catechistIds;
        }
        await box.put(id, data);
        applied++;

        // Applica chiave di canale trasmessa dall'inviante (bootstrap titolo).
        // Non generare una chiave divergente: se il mittente ha fornito la chiave,
        // memorizzala; altrimenti lascia senza titolo (verrà fornita al prossimo
        // sync via enc+key).
        final uniqueCode = data['uniqueCode']?.toString() ?? '';
        final keysMap = message['classKeys'] as Map<String, dynamic>? ?? const {};
        final rawKey = keysMap[id] ?? keysMap[uniqueCode];
        if (rawKey is Map) {
          try {
            await ClassChannelService.storeKey(
              classId: id,
              classUniqueCode: uniqueCode.isNotEmpty
                  ? uniqueCode
                  : rawKey['classUniqueCode']?.toString() ?? '',
              className: data['name']?.toString() ?? id,
              keyBase64: rawKey['keyBase64']?.toString() ?? '',
              grantorCatechistId: rawKey['grantorCatechistId']?.toString() ?? '',
            );
          } catch (_) {}
        }
        // Fallback legacy: se nessuna chiave è stata trasmessa e il dispositivo
        // non ha titolo, non creare chiavi divergenti qui — la chiave arriverà
        // con il prossimo sync in-band (enc+key) dal membro titolare.
      }
      await box.flush();
      accepted = true;
      addLog('INFO', 'Class info applicata: $applied classi registrate');

      // Aggiorna associazioni endpoint
      final shared = (message['sharedClassIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toSet();
      if (shared.isNotEmpty) {
        _endpointSharedClassIds[endpointId] = shared;
      }

      // Dopo registrazione classe, prova ad applicare eventuali blob relay
      for (final entry in classes) {
        if (entry is! Map) continue;
        final data = Map<String, dynamic>.from(entry['data'] as Map? ?? {});
        final code = data['uniqueCode']?.toString() ?? '';
        if (code.isNotEmpty) {
          await tryApplyRelayedCiphertext(code);
        }
      }

      // Assicura che il catechista locale sia nelle classi
      _ensureLocalCatechistInClasses();
    } catch (e) {
      reason = 'Errore registrazione classe: $e';
      addLog('ERROR', 'Errore handleClassInfo: $e');
    }

    final ack = jsonEncode({
      'type': 'p2p_class_info_ack',
      'accepted': accepted,
      'applied': applied,
      'reason': reason,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    try {
      await _sendEncryptedPayload(endpointId, ack);
      addLog('INFO', 'Conferma registrazione classe inviata (accepted=$accepted, applied=$applied)');
    } catch (e) {
      addLog('ERROR', 'Errore invio ack classe: $e');
    }

    if (accepted) {
      _associationHandshakeStep[endpointId] = 'classConfirmed';
      _updateState(
        _state.copyWith(associationHandshakeStep: 'classConfirmed'),
      );
      // Avvia verifica sync continuo anche sul ricevente (verrà confermata dal pong)
      _startContinuousSyncVerification(endpointId, isInitiator: false);
    } else {
      _failOrderedHandshake(endpointId, reason);
    }
  }

  Future<void> _handleClassInfoAck(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final accepted = message['accepted'] == true;
    _handshakeTimeoutTimers[endpointId]?.cancel();

    if (!accepted) {
      final reason = message['reason'] as String? ?? 'Rifiutata';
      addLog('WARN', 'Conferma classe NEGATIVA da $endpointId: $reason');
      _failOrderedHandshake(endpointId, 'Ricevente ha rifiutato classe: $reason');
      return;
    }

    final applied = message['applied'] as int? ?? 0;
    addLog('INFO', 'Conferma classe POSITIVA ricevuta da $endpointId (applied=$applied)');
    _associationHandshakeStep[endpointId] = 'classConfirmed';
    _updateState(
      _state.copyWith(associationHandshakeStep: 'classConfirmed'),
    );

    // Step 5: verifica sincronizzazione costante
    await _startContinuousSyncVerification(endpointId, isInitiator: true);
  }

  void _failOrderedHandshake(String endpointId, String reason) {
    _handshakeTimeoutTimers[endpointId]?.cancel();
    _handshakeTimeoutTimers.remove(endpointId);
    _associationHandshakeStep[endpointId] = 'failed';
    _updateState(
      _state.copyWith(
        isAssociationHandshakeActive: false,
        associationHandshakeStep: 'failed',
        status: P2PSyncStatus.error,
        errorMessage: reason,
      ),
    );
    addLog('ERROR', 'Handshake ordinato fallito per $endpointId: $reason');
  }

  String _generateUniqueCode() => generateClassUniqueCode();

  // ── Verifica sincronizzazione costante (tentativo) ────────────────────────

  Future<void> _startContinuousSyncVerification(
    String endpointId, {
    required bool isInitiator,
  }) async {
    _associationHandshakeStep[endpointId] = 'verifyingContinuous';
    _updateState(
      _state.copyWith(
        associationHandshakeStep: 'verifyingContinuous',
        status: P2PSyncStatus.associationVerifying,
      ),
    );

    // Invia ping di verifica (lo scambio stato sync_start/end verrà testato
    // anche tramite un tentativo reale di sync bidirezionale).
    try {
      final ping = jsonEncode({
        'type': 'p2p_continuous_sync_ping',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isInitiator': isInitiator,
      });
      await _sendEncryptedPayload(endpointId, ping);
      addLog('INFO', 'Continuous sync ping inviato a $endpointId');
    } catch (e) {
      addLog('WARN', 'Errore invio continuous ping: $e');
    }

    // Avvia in parallelo un tentativo reale di sincronizzazione bidirezionale
    // (verifica che lo scambio dati funzioni end-to-end).
    try {
      addLog('INFO', 'Tentativo sincronizzazione costante: avvio sync di verifica');
      await _performBidirectionalSync(endpointId);
    } catch (e) {
      addLog('WARN', 'Sync di verifica fallita (verrà ritentata via pong): $e');
    }

    // Watchdog: se entro timeout non arriva pong + sync_end, fallisce
    _handshakeTimeoutTimers[endpointId]?.cancel();
    _handshakeTimeoutTimers[endpointId] = Timer(_continuousVerifyTimeout, () {
      if (_associationHandshakeStep[endpointId] == 'verifyingContinuous' &&
          !_continuousSyncVerified) {
        addLog('WARN', 'Timeout verifica sync continuo per $endpointId');
        // Fallback: se il sync bidirezionale è comunque completato, considera verificato
        if (_state.status == P2PSyncStatus.completed) {
          _completeOrderedHandshake(endpointId);
        } else {
          _failOrderedHandshake(endpointId, 'Timeout verifica sincronizzazione costante');
        }
      }
    });
  }

  Future<void> _handleContinuousSyncPing(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    addLog('INFO', 'Continuous sync PING ricevuto da $endpointId');
    // Risponde con pong
    try {
      final pong = jsonEncode({
        'type': 'p2p_continuous_sync_pong',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'receivedPingAt': message['timestamp'],
      });
      await _sendEncryptedPayload(endpointId, pong);
      addLog('INFO', 'Continuous sync PONG inviato a $endpointId');
    } catch (e) {
      addLog('WARN', 'Errore invio pong: $e');
    }

    // Anche il ricevente avvia un tentativo di sync per verificare la continuità
    try {
      if (_endpointSyncPhase[endpointId] == null || _endpointSyncPhase[endpointId]!.isIdle) {
        await _performBidirectionalSync(endpointId);
      }
    } catch (e) {
      addLog('WARN', 'Sync verifica lato ricevente fallita: $e');
    }
  }

  Future<void> _handleContinuousSyncPong(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    addLog('INFO', 'Continuous sync PONG ricevuto da $endpointId — sincronizzazione costante verificata');
    _handshakeTimeoutTimers[endpointId]?.cancel();
    _completeOrderedHandshake(endpointId);
  }

  void _completeOrderedHandshake(String endpointId) {
    _handshakeTimeoutTimers[endpointId]?.cancel();
    _handshakeTimeoutTimers.remove(endpointId);
    _associationHandshakeStep[endpointId] = 'completed';
    _continuousSyncVerified = true;
    _updateState(
      _state.copyWith(
        isAssociationHandshakeActive: false,
        associationHandshakeStep: 'completed',
        continuousSyncVerified: true,
        status: P2PSyncStatus.completed,
        lastSyncAt: DateTime.now(),
      ),
    );
    addLog('INFO', 'Handshake ordinato COMPLETATO con via libera per $endpointId — sincronizzazione costante funzionante');
  }

  // ── Scambio stato inizio/fine sync (anti-blocco) ────────────────────────

  Future<void> _sendSyncState(
    String endpointId,
    String state, {
    String? detail,
  }) async {
    try {
      final payload = <String, dynamic>{
        'type': 'p2p_sync_state',
        'state': state, // sync_start | sync_end | heartbeat
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isSyncing': state == 'sync_start',
      };
      if (detail != null) payload['detail'] = detail;
      final msg = jsonEncode(payload);
      await _sendEncryptedPayload(endpointId, msg);
      addLog('DEBUG', 'Stato sync inviato a $endpointId: $state');
    } catch (e) {
      addLog('WARN', 'Errore invio stato sync $state: $e');
    }

    if (state == 'sync_start') {
      _updateState(
        _state.copyWith(lastSyncStartedAt: DateTime.now(), remoteSyncState: 'syncing'),
      );
    } else if (state == 'sync_end') {
      _updateState(
        _state.copyWith(lastSyncEndedAt: DateTime.now(), remoteSyncState: 'idle'),
      );
    }
  }

  Future<void> _handleSyncState(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final state = message['state'] as String? ?? 'unknown';
    final isSyncing = message['isSyncing'] == true;
    _remoteSyncState[endpointId] = isSyncing ? 'syncing' : 'idle';

    if (state == 'sync_start') {
      _remoteSyncStartAt[endpointId] = DateTime.now();
      addLog('INFO', 'Stato remoto $endpointId: INIZIO sincronizzazione');
      _updateState(
        _state.copyWith(remoteSyncState: 'syncing', lastSyncStartedAt: DateTime.now()),
      );
      // Watchdog: se non arriva sync_end entro 60s, sblocca
      _syncStateWatchdog[endpointId]?.cancel();
      _syncStateWatchdog[endpointId] = Timer(_syncStateWatchdogTimeout, () {
        final lastStart = _remoteSyncStartAt[endpointId];
        if (lastStart != null &&
            _remoteSyncState[endpointId] == 'syncing' &&
            DateTime.now().difference(lastStart).inSeconds >= 60) {
          addLog('WARN', 'Watchdog: sincronizzazione remota bloccata da >60s per $endpointId — reset forzato');
          _remoteSyncState[endpointId] = 'idle';
          _syncStateWatchdog[endpointId]?.cancel();
          _updateState(_state.copyWith(remoteSyncState: 'idle'));
          // Sblocca eventuale sync locale bloccata
          if (_isSyncing &&
              _lastSyncStartTime != null &&
              DateTime.now().difference(_lastSyncStartTime!).inSeconds > 60) {
            addLog('WARN', 'Sblocco _isSyncing locale da watchdog stato remoto');
            _isSyncing = false;
            _lastSyncStartTime = null;
            _endpointSyncPhase.remove(endpointId);
          }
        }
      });
    } else if (state == 'sync_end') {
      _syncStateWatchdog[endpointId]?.cancel();
      _remoteSyncState[endpointId] = 'idle';
      addLog('INFO', 'Stato remoto $endpointId: FINE sincronizzazione');
      _updateState(
        _state.copyWith(remoteSyncState: 'idle', lastSyncEndedAt: DateTime.now()),
      );
    } else if (state == 'heartbeat') {
      addLog('DEBUG', 'Heartbeat ricevuto da $endpointId');
      _syncStateWatchdog[endpointId]?.cancel();
      // Heartbeat resetta il watchdog se il remoto è in syncing
      if (_remoteSyncState[endpointId] == 'syncing') {
        _syncStateWatchdog[endpointId] = Timer(_syncStateWatchdogTimeout, () {
          addLog('WARN', 'Watchdog heartbeat: sync remota bloccata per $endpointId — reset');
          _remoteSyncState[endpointId] = 'idle';
          _updateState(_state.copyWith(remoteSyncState: 'idle'));
        });
      }
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      if (_connectedEndpoints.isEmpty) return;
      for (final endpointId in _connectedEndpoints.toList()) {
        // Invia heartbeat solo se non in sync attivo (evita spam)
        if (_isSyncing) continue;
        try {
          await _sendSyncState(endpointId, 'heartbeat');
        } catch (_) {}
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CANALE PARROCCHIALE GLOBALE (riunioni + avvisi, in chiaro per la rete)
  // ─────────────────────────────────────────────────────────────────────────

  /// Invia il payload del canale parrocchiale globale all'endpoint.
  Future<void> sendParishChannel(String endpointId) async {
    if (_endpointSupportsParishChannel[endpointId] != true) {
      addLog(
        'DEBUG',
        'Canale parrocchiale saltato: peer non aggiornato ($endpointId)',
      );
      return;
    }
    try {
      final payload = ParishChannelService.buildChannelPayload();
      final msg = jsonEncode({
        'type': 'p2p_parish_channel',
        'payload': payload,
      });
      await _sendEncryptedPayload(endpointId, msg);
      addLog('INFO', 'Canale parrocchiale inviato a $endpointId');
    } catch (e) {
      addLog('ERROR', 'Invio canale parrocchiale fallito: $e');
    }
  }

  /// Invia il canale parrocchiale globale a tutti i dispositivi connessi.
  /// Best-effort: gli endpoint non aggiornati vengono saltati.
  Future<void> sendParishChannelToAll() async {
    final endpoints = _connectedEndpoints.toList();
    if (endpoints.isEmpty) {
      addLog('DEBUG', 'Canale parrocchiale: nessun dispositivo connesso');
      return;
    }
    for (final endpointId in endpoints) {
      await sendParishChannel(endpointId);
    }
  }

  /// Riceve e applica il payload del canale parrocchiale globale.
  Future<void> _handleParishChannel(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final payload = message['payload'];
    if (payload is! Map) {
      addLog('WARN', 'Canale parrocchiale ricevuto senza payload valido');
      return;
    }
    try {
      final applied = await ParishChannelService.applyChannelPayload(
        Map<String, dynamic>.from(payload),
      );
      addLog(
        'INFO',
        'Canale parrocchiale applicato: $applied record da $endpointId',
      );
      // Risposta bidirezionale: il remoto riceve anche i nostri dati.
      await sendParishChannel(endpointId);
    } catch (e) {
      addLog('ERROR', 'Errore applicazione canale parrocchiale: $e');
    }
  }

  /// Propaga un [Tombstone] a tutti i dispositivi attualmente connessi.
  ///
  /// Ogni destinatario riceve una copia FIRMATA con il shared secret statico
  /// del canale P2P dedicato (ECDH static-static), così da poter verificare
  /// l'autenticità. Best-effort: se un endpoint fallisce, gli altri restano attivi.
  Future<void> broadcastTombstone(Tombstone tombstone) async {
    final endpoints = _connectedEndpoints.toList();
    if (endpoints.isEmpty) {
      addLog('DEBUG', 'Broadcast tombstone: nessun dispositivo connesso');
      return;
    }

    final identity = await _security.getLocalIdentity();
    final base = tombstone.toMap()..['signerDeviceId'] = identity.deviceId;

    for (final endpointId in endpoints) {
      final remoteId = _endpointConnIdMap[endpointId];
      if (remoteId == null) continue;
      try {
        final assoc = await _security.getAssociation(remoteId);
        if (assoc == null || assoc.publicKeyBase64.isEmpty) continue;
        final secret = await _security.computeStaticSharedSecret(
          assoc.publicKeyBase64,
        );
        final signedPayload = jsonEncode({
          'type': 'p2p_tombstone',
          'tombstone': TombstoneService.withSignature(base, secret),
        });
        await _sendEncryptedPayload(endpointId, signedPayload);
        addLog(
          'INFO',
          'Tombstone propagato a $endpointId (${base['entityType']}/${base['entityId']})',
        );
      } catch (e) {
        addLog('ERROR', 'Invio tombstone a $endpointId fallito: $e');
      }
    }
  }

  /// Invia i tombstone locali (Diritto all'Oblio) all'endpoint, firmati con il
  /// segreto ECDH statico dell'associazione. Usato durante OGNI sync: così un
  /// dispositivo rimasto OFFLINE alla propagazione iniziale apprende comunque
  /// le cancellazioni appena si riconnette, evitando che conservi e ripropaghi
  /// la PII del minore.
  Future<void> _sendTombstonesToEndpoint(String endpointId) async {
    final remoteId = _endpointConnIdMap[endpointId];
    if (remoteId == null) return;
    try {
      final assoc = await _security.getAssociation(remoteId);
      if (assoc == null || assoc.publicKeyBase64.isEmpty) return;
      final secret = await _security.computeStaticSharedSecret(
        assoc.publicKeyBase64,
      );
      final identity = await _security.getLocalIdentity();
      final repo = TombstoneRepository();
      final tombstones = repo.getAll();
      if (tombstones.isEmpty) return;
      int sent = 0;
      for (final ts in tombstones) {
        final base = ts.toMap()..['signerDeviceId'] = identity.deviceId;
        final msg = jsonEncode({
          'type': 'p2p_tombstone',
          'tombstone': TombstoneService.withSignature(base, secret),
        });
        await _sendEncryptedPayload(endpointId, msg);
        sent++;
      }
      addLog(
        'INFO',
        'Tombstones inviati a $endpointId: $sent cancellazioni GDPR',
      );
    } catch (e) {
      addLog('WARN', 'Invio tombstones a $endpointId fallito: $e');
    }
  }

  /// Invia la blacklist delle revoche firmata (M1) all'endpoint durante ogni
  /// sync. Solo il Responsabile possiede la chiave di firma, quindi la revoca
  /// è autenticata: un dispositivo rogue non può propagare revoche fasulle.
  Future<void> _sendRevocationsToEndpoint(String endpointId) async {
    try {
      final signed = await _security.signRevocationList();
      if (signed == null || (signed['revocations'] as List? ?? []).isEmpty) {
        return;
      }
      final msg = jsonEncode({
        'type': 'p2p_revoked_devices',
        'payload': signed,
      });
      await _sendEncryptedPayload(endpointId, msg);
      addLog(
        'INFO',
        'M1: revoche firmate inviate a $endpointId '
            '(${(signed['revocations'] as List).length} dispositivi)',
      );
    } catch (e) {
      addLog('WARN', 'M1: invio revoche a $endpointId fallito: $e');
    }
  }

  /// Riceve la blacklist delle revoche firmata dal Responsabile (M1). La
  /// verifica Ed25519 contro la trust root impedisce l'iniezione di revoche
  /// fasulle; le revoche valide vengono unite alla blacklist locale.
  Future<void> _handleRevokedDevices(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    try {
      final payload = message['payload'];
      if (payload is! Map) return;
      final valid = await _security.verifyRevocationList(
        Map<String, dynamic>.from(payload),
      );
      if (!valid) {
        addLog(
          'WARN',
          'M1: revoche rifiutate da $endpointId (firma Ed25519 non valida)',
        );
        return;
      }
      final revocations = (payload['revocations'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (revocations.isEmpty) return;
      await _security.importRevokedDevices(revocations);
      addLog(
        'INFO',
        'M1: importate ${revocations.length} revoche firmate da $endpointId',
      );
    } catch (e) {
      addLog('WARN', 'M1: gestione revoche da $endpointId fallita: $e');
    }
  }

  /// ID delle entità eliminati tramite tombstone (per esclusione durante sync).
  Set<String> _tombstonedEntityIds() {
    try {
      final box = LocalDatabase.tombstones();
      return box.keys
          .map(
            (key) => LocalDatabase.toStringDynamicMap(box.get(key))['entityId'],
          )
          .whereType<String>()
          .toSet();
    } catch (_) {
      return {};
    }
  }

  /// Riceve e applica un tombstone remoto dopo aver verificato la firma ECDH.
  Future<void> _handleTombstone(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final remoteId = _endpointConnIdMap[endpointId];
    final ts = message['tombstone'];
    if (remoteId == null || ts is! Map<String, dynamic>) {
      addLog('WARN', 'Tombstone ricevuto senza dati validi da $endpointId');
      return;
    }

    try {
      final assoc = await _security.getAssociation(remoteId);
      if (assoc == null || assoc.publicKeyBase64.isEmpty) {
        addLog(
          'WARN',
          'Tombstone ignorato: nessuna associazione per $remoteId',
        );
        return;
      }
      final secret = await _security.computeStaticSharedSecret(
        assoc.publicKeyBase64,
      );
      if (!TombstoneService.verify(ts, secret)) {
        addLog(
          'WARN',
          'Tombstone con firma non valida da $remoteId — ignorato',
        );
        return;
      }

      // A7: verifica della firma Ed25519 per-dispositivo. La firma è
      // asimmetrica e attribuibile al device firmatario ([signerEd25519PublicKey]).
      // Un dispositivo compromesso può firmare solo tombstone a proprio nome,
      // non spacciarli per un altro device. Fallback retrocompatibile: un
      // tombstone proveniente da una versione precedente (senza firma Ed25519)
      // resta accettato se l'HMAC ECDH è valido, ma viene loggato.
      final edSignature = ts['signatureEd25519']?.toString() ?? '';
      final edPublicKey = ts['signerEd25519PublicKey']?.toString() ?? '';
      if (edSignature.isNotEmpty && edPublicKey.isNotEmpty) {
        final edValid = await P2PSecurityService.verifyTombstoneSignature(
          canonicalPayload: TombstoneService.canonical(ts),
          signature: edSignature,
          publicKeyBase64: edPublicKey,
        );
        if (!edValid) {
          addLog(
            'WARN',
            'Tombstone con firma Ed25519 non valida da $remoteId — ignorato',
          );
          return;
        }
      } else {
        addLog(
          'WARN',
          'Tombstone senza firma Ed25519 da $remoteId '
          '(versione precedente) — accettato solo via HMAC',
        );
      }

      // In modalità Responsabile, solo i dispositivi approvati dal
      // Responsabile possono propagare tombstone: la firma HMAC usa un
      // segreto ECDH simmetrico, condiviso con TUTTI i dispositivi
      // associati, quindi un peer a privilegio ridotto non deve poter
      // iniettare tombstone nell'approval-only mode.
      final responsabileMode = await _security.isResponsabileModeActive();
      if (responsabileMode &&
          (!assoc.authorizedByResponsabile ||
              assoc.approvalSignature == null ||
              assoc.approvalSignature!.isEmpty)) {
        addLog(
          'WARN',
          'Tombstone da dispositivo non approvato ($remoteId) in modalità '
              'Responsabile — ignorato',
        );
        return;
      }

      final applied = await HardDeleteService.applyRemoteTombstone(ts);
      addLog(
        applied ? 'INFO' : 'WARN',
        'Tombstone ${applied ? 'applicato' : 'non applicato'} '
        '(entity ${ts['entityId']}) da $remoteId',
      );
    } catch (e) {
      addLog('ERROR', 'Errore gestione tombstone: $e');
    }
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
    addLog(
      'INFO',
      'Rimozione associazione e pulizia connessione per $deviceId',
    );
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
      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (_connectedEndpoints.isNotEmpty) break;
      }
    }

    final endpoints = _connectedEndpoints.toList();
    if (endpoints.isNotEmpty) {
      final endpointId = endpoints.first;
      if (_state.status == P2PSyncStatus.completed) {
        addLog('INFO', 'Sessione già completata, avvio nuova sincronizzazione');
        await _performBidirectionalSync(endpointId);
      } else if (_state.status == P2PSyncStatus.sessionEstablished &&
          _state.authenticatedByRemote) {
        addLog('INFO', 'Avvio sincronizzazione con dispositivo connesso');
        await _performBidirectionalSync(endpointId);
      } else {
        addLog(
          'INFO',
          'Connessione presente ma handshake/auth non completato, '
              'attendere...',
        );
        for (int i = 0; i < 60; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (_state.status == P2PSyncStatus.sessionEstablished &&
              _state.authenticatedByRemote) {
            await _performBidirectionalSync(endpointId);
            return;
          } else if (_state.status == P2PSyncStatus.completed) {
            await _performBidirectionalSync(endpointId);
            return;
          }
        }
        addLog('WARN', 'Timeout attesa handshake/auth per $endpointId');
      }
    } else {
      addLog('WARN', 'Nessun dispositivo trovato per la sincronizzazione');
    }
  }

  void dispose() {
    _pairingTimeoutTimer?.cancel();
    _periodicSyncTimer?.cancel();
    _sessionKeyRotationTimer?.cancel();
    _confirmationTimeoutTimer?.cancel();
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
    _endpointLocalEphemeral.clear();
    _endpointLocalEphemeralPub.clear();
    _endpointRemoteEphemeralPub.clear();
    _endpointRemoteAssocPub.clear();
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
    throw UnsupportedError('Funzione Responsabile non ancora implementata.');
  }
}

/// Determina in modo deterministico quale catechistId conservare quando due
/// dispositivi della stessa persona ("Mio Dispositivo") presentano identità
/// diverse. Default: quello della classe che invia/crea la classe condivisa
/// (il creatore), se presente tra [localCat]/[remoteCat]; altrimenti [localCat].
String computeDefaultCatechistId(
  String localCat,
  String remoteCat,
  Map<String, String> classCreators,
) {
  for (final creator in classCreators.values) {
    if (creator == localCat) return localCat;
    if (creator == remoteCat) return remoteCat;
  }
  return localCat;
}
