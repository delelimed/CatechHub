import 'dart:convert';

/// Modello dati del feature di sincronizzazione Bluetooth Classico RFCOMM.
///
/// CONTESTO PROGETTO:
/// CateREG permette la sincronizzazione P2P offline tra dispositivi di
/// catechisti tramite Bluetooth Classico (RFCOMM). Non c'è un server
/// centrale: i dati risiedono solo sui dispositivi e vengono sincronizzati
/// quando i catechisti sono fisicamente vicini.
///
/// Questo file contiene TUTTI i modelli dati, enum e classi serializzabili
/// usati dal protocollo di sincronizzazione:
/// - Stati della macchina a stati (pairing, connessione, sync)
/// - Payload del QR code per lo scambio di chiavi
/// - Record CRDT per la sincronizzazione LWW (Last-Write-Wins)
/// - Modello TrustedDevice per la persistenza dei dispositivi fidati
/// - Costanti UUID del servizio Bluetooth
///
/// ARCHITETTURA:
/// data/    → modelli serializzabili (DTO)
/// domain/  → logica di connessione, sync engine, provider Riverpod
/// presentation/ → UI (pairing page, dashboard)
// ──────────────────────────────────────────────
//  ENUM: ClassicPairingRole
//  Ruolo eletto automaticamente tramite Leader Election.
//  Determina chi fa da server e chi da client nella connessione RFCOMM.
// ──────────────────────────────────────────────

enum ClassicPairingRole {
  dispositivoA,
  dispositivoB,
}

// ──────────────────────────────────────────────
//  ENUM: ClassicSyncRole
//  Ruolo di sincronizzazione del catechista.
//  Ogni dispositivo puo' essere:
//  - mioDispositivo: sync automatica senza conferma
//  - altroCatechista: sync con conferma esplicita dell'utente
//  - responsabile: riservato (non ancora implementato)
// ──────────────────────────────────────────────

enum ClassicSyncRole {
  mioDispositivo,
  altroCatechista,
  responsabile,
}

// ──────────────────────────────────────────────
//  ENUM: ClassicPairingState
//  Macchina a stati del protocollo di accoppiamento bidirezionale.
//  Fasi: A mostra QR -> B scannerizza -> B mostra QR -> A scannerizza.
//  Questo scambio incrociato garantisce che entrambi i dispositivi
//  abbiano la chiave pubblica ECDH dell'altro.
// ──────────────────────────────────────────────

enum ClassicPairingState {
  idle,
  fase1_A_mostraQR,
  fase1_B_scansionaQR,
  verifyingHardware,
  fase2_B_mostraQR,
  fase2_A_scansionaQR,
  completato,
  errore,
}

// ──────────────────────────────────────────────
//  ENUM: ClassicTransportType
// ──────────────────────────────────────────────

enum ClassicTransportType {
  classic,
  none,
}

// ──────────────────────────────────────────────
//  ENUM: ClassicConnectionState
// ──────────────────────────────────────────────

enum ClassicConnectionState {
  idle,
  checkingCapabilities,
  classicServerListening,
  classicClientConnecting,
  connected,
  error,
}

// ──────────────────────────────────────────────
//  ENUM: ClassicSyncStatus
// ──────────────────────────────────────────────

enum ClassicSyncStatus {
  idle,
  pairing,
  scanning,
  connecting,
  connected,
  syncing,
  completed,
  error,
  keyExpired,
}

// ──────────────────────────────────────────────
//  CLASS: ClassicPairingData (Payload QR Code)
//  Contiene i dati serializzati nel QR code per lo scambio di chiavi
//  ECDH tra i due dispositivi durante la fase di pairing.
// ──────────────────────────────────────────────

class ClassicPairingData {
  final String deviceId;
  final String? macAddress;
  final String deviceName;
  final String sharedKey;
  final DateTime createdAt;
  final ClassicSyncRole syncRole;
  final String? sessionNonce;

  const ClassicPairingData({
    required this.deviceId,
    this.macAddress,
    required this.deviceName,
    required this.sharedKey,
    required this.createdAt,
    this.syncRole = ClassicSyncRole.mioDispositivo,
    this.sessionNonce,
  });

  /// La chiave di sessione scade dopo 30 giorni dalla creazione del pairing.
  bool get isExpired {
    final now = DateTime.now().toUtc();
    final expiry = createdAt.toUtc().add(const Duration(days: 30));
    return now.isAfter(expiry);
  }

  /// Tempo rimanente prima della scadenza della chiave (usato dalla UI).
  Duration get timeUntilExpiry {
    final now = DateTime.now().toUtc();
    final expiry = createdAt.toUtc().add(const Duration(days: 30));
    if (now.isAfter(expiry)) return Duration.zero;
    return expiry.difference(now);
  }

  String get cleanDisplayName {
    if (deviceName.startsWith(ClassicUuids.deviceNamePrefix)) {
      final cleaned = deviceName.substring(ClassicUuids.deviceNamePrefix.length);
      return cleaned.isNotEmpty ? cleaned : deviceName;
    }
    return deviceName;
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      if (macAddress != null && macAddress!.isNotEmpty)
        'macAddress': macAddress,
      'deviceName': deviceName,
      'sharedKey': sharedKey,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'syncRole': syncRole.index,
      if (sessionNonce != null) 'sessionNonce': sessionNonce,
    };
  }

  factory ClassicPairingData.fromMap(Map<String, dynamic> map) {
    return ClassicPairingData(
      deviceId: map['deviceId'] ?? '',
      macAddress: map['macAddress'] as String?,
      deviceName: map['deviceName'] ?? '',
      sharedKey: map['sharedKey'] ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String).toUtc(),
      syncRole: () {
        final rawRole = map['syncRole'];
        if (rawRole is int && rawRole >= 0 && rawRole < ClassicSyncRole.values.length) {
          return ClassicSyncRole.values[rawRole];
        }
        if (rawRole is String) {
          return ClassicSyncRole.values.firstWhere(
            (e) => e.name == rawRole,
            orElse: () => ClassicSyncRole.mioDispositivo,
          );
        }
        return ClassicSyncRole.mioDispositivo;
      }(),
      sessionNonce: map['sessionNonce'] as String?,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory ClassicPairingData.fromJson(String json) {
    return ClassicPairingData.fromMap(
        jsonDecode(json) as Map<String, dynamic>);
  }

  static bool controllareCoerenzaRuoli(
    ClassicSyncRole ruoloLocale,
    ClassicSyncRole ruoloRicevuto,
  ) {
    return ruoloLocale == ruoloRicevuto;
  }

  static const String roleCoherenceErrorMessage =
      'Errore di configurazione: i due dispositivi devono avere '
      'lo stesso ruolo impostato (entrambi "Mio Dispositivo" '
      'o entrambi "Altro Catechista").';
}

// ──────────────────────────────────────────────
//  CLASS: TrustedDevice (Tabella DB locale)
//  Memorizzato nel Box Hive trusted_devices_box.
//  Contiene la chiave di sessione derivata da ECDH + HKDF per
//  cifrare i dati durante la sincronizzazione.
// ──────────────────────────────────────────────

class TrustedDevice {
  final String deviceId;
  final String deviceName;
  final String publicKey;
  final String syncRole;
  final DateTime pairedAt;
  final DateTime? lastSyncedAt;
  final String? sessionNonce;
  final DateTime? keyRenewalAt;
  final String? macAddress;

  bool get isValid {
    final now = DateTime.now().toUtc();
    final expiry = pairedAt.toUtc().add(const Duration(days: 30));
    return now.isBefore(expiry);
  }

  /// Indica se la chiave e in fase di scadenza (ultimi 5 giorni).
  bool get isKeyRenewalNeeded {
    if (keyRenewalAt == null) return false;
    return DateTime.now().toUtc().isAfter(keyRenewalAt!);
  }

  /// Indica se la chiave e scaduta.
  bool get isKeyExpired {
    final now = DateTime.now().toUtc();
    final expiry = pairedAt.toUtc().add(const Duration(days: 30));
    return now.isAfter(expiry);
  }

  Duration get timeUntilExpiry {
    final now = DateTime.now().toUtc();
    final expiry = pairedAt.toUtc().add(const Duration(days: 30));
    if (now.isAfter(expiry)) return Duration.zero;
    return expiry.difference(now);
  }

  String get cleanDisplayName {
    if (deviceName.startsWith(ClassicUuids.deviceNamePrefix)) {
      final cleaned = deviceName.substring(ClassicUuids.deviceNamePrefix.length);
      return cleaned.isNotEmpty ? cleaned : deviceName;
    }
    return deviceName;
  }

  const TrustedDevice({
    required this.deviceId,
    required this.deviceName,
    required this.publicKey,
    required this.syncRole,
    required this.pairedAt,
    this.lastSyncedAt,
    this.sessionNonce,
    this.keyRenewalAt,
    this.macAddress,
  });

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'publicKey': publicKey,
      'syncRole': syncRole,
      'pairedAt': pairedAt.toUtc().toIso8601String(),
      if (lastSyncedAt != null)
        'lastSyncedAt': lastSyncedAt!.toUtc().toIso8601String(),
      if (sessionNonce != null) 'sessionNonce': sessionNonce,
      if (keyRenewalAt != null)
        'keyRenewalAt': keyRenewalAt!.toUtc().toIso8601String(),
      if (macAddress != null) 'macAddress': macAddress,
    };
  }

  factory TrustedDevice.fromMap(Map<String, dynamic> map) {
    return TrustedDevice(
      deviceId: map['deviceId'] ?? '',
      deviceName: map['deviceName'] ?? '',
      publicKey: map['publicKey'] ?? '',
      syncRole: map['syncRole'] ?? ClassicSyncRole.mioDispositivo.name,
      pairedAt: DateTime.parse(map['pairedAt'] as String).toUtc(),
      lastSyncedAt: map['lastSyncedAt'] != null
          ? DateTime.tryParse(map['lastSyncedAt'] as String)?.toUtc()
          : null,
      sessionNonce: map['sessionNonce'] as String?,
      keyRenewalAt: map['keyRenewalAt'] != null
          ? DateTime.tryParse(map['keyRenewalAt'] as String)?.toUtc()
          : null,
      macAddress: map['macAddress'] as String?,
    );
  }

  TrustedDevice copyWith({
    String? deviceId,
    String? deviceName,
    String? publicKey,
    String? syncRole,
    DateTime? pairedAt,
    DateTime? lastSyncedAt,
    String? sessionNonce,
    DateTime? keyRenewalAt,
    String? macAddress,
    bool clearLastSyncedAt = false,
    bool clearMacAddress = false,
  }) {
    return TrustedDevice(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      publicKey: publicKey ?? this.publicKey,
      syncRole: syncRole ?? this.syncRole,
      pairedAt: pairedAt ?? this.pairedAt,
      lastSyncedAt:
          clearLastSyncedAt ? null : (lastSyncedAt ?? this.lastSyncedAt),
      sessionNonce: sessionNonce ?? this.sessionNonce,
      keyRenewalAt: keyRenewalAt ?? this.keyRenewalAt,
      macAddress: clearMacAddress ? null : (macAddress ?? this.macAddress),
    );
  }
}

// ──────────────────────────────────────────────
//  CLASS: ClassicPairingFlowState (Stato UI accoppiamento)
// ──────────────────────────────────────────────

class ClassicPairingFlowState {
  final ClassicPairingState pairingState;
  final ClassicPairingRole? myRole;
  final ClassicPairingData? localPairingData;
  final ClassicPairingData? scannedPairingData;
  final String? remoteDeviceId;
  final String? remoteMacAddress;
  final String? errorMessage;
  final bool isProcessing;

  const ClassicPairingFlowState({
    this.pairingState = ClassicPairingState.idle,
    this.myRole,
    this.localPairingData,
    this.scannedPairingData,
    this.remoteDeviceId,
    this.remoteMacAddress,
    this.errorMessage,
    this.isProcessing = false,
  });

  ClassicPairingFlowState copyWith({
    ClassicPairingState? pairingState,
    ClassicPairingRole? myRole,
    ClassicPairingData? localPairingData,
    ClassicPairingData? scannedPairingData,
    String? remoteDeviceId,
    String? remoteMacAddress,
    String? errorMessage,
    bool? isProcessing,
  }) {
    return ClassicPairingFlowState(
      pairingState: pairingState ?? this.pairingState,
      myRole: myRole ?? this.myRole,
      localPairingData: localPairingData ?? this.localPairingData,
      scannedPairingData: scannedPairingData ?? this.scannedPairingData,
      remoteDeviceId: remoteDeviceId ?? this.remoteDeviceId,
      remoteMacAddress: remoteMacAddress ?? this.remoteMacAddress,
      errorMessage: errorMessage,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }
}

// ──────────────────────────────────────────────
//  CLASS: ClassicUuids
//  Costanti di configurazione del servizio Bluetooth.
//  appServiceUuid identifica il servizio CatechHub per SDP discovery.
//  deviceNamePrefix marca i device come CatechHub_ per filtro discovery.
// ──────────────────────────────────────────────

class ClassicUuids {
  /// UUID univoco del servizio CatechHub per discovery e connessione RFCOMM.
  /// Usato sia dal server (listenUsingRfcommWithServiceRecord) che dal
  /// client (createRfcommSocketToServiceRecord) per discovery basata su SDP.
  static const String appServiceUuid =
      '4a8f1234-c21a-4b9d-bc32-123456789abc';

  static const String deviceNamePrefix = 'CatechHub_';
}

// ──────────────────────────────────────────────
//  CLASS: SyncableRecord (CRDT LWW)
//  Rappresenta un singolo record di database da sincronizzare.
//  Usa la strategia Last-Write-Wins: il record con updatedAt piu'
//  recente vince in caso di conflitto. Supporta cancellazione logica
//  tramite flag isDeleted (tombstone).
// ──────────────────────────────────────────────

class SyncableRecord {
  final String id;
  final String boxName;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const SyncableRecord({
    required this.id,
    required this.boxName,
    required this.data,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  bool winsOver(SyncableRecord other) {
    return updatedAt.isAfter(other.updatedAt);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'box': boxName,
      'data': data,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'isDeleted': isDeleted,
    };
  }

  factory SyncableRecord.fromMap(Map<String, dynamic> map) {
    return SyncableRecord(
      id: map['id'] ?? '',
      boxName: map['box'] ?? '',
      data: Map<String, dynamic>.from(map['data'] ?? {}),
      createdAt: DateTime.parse(map['createdAt'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updatedAt'] as String).toUtc(),
      isDeleted: map['isDeleted'] == true,
    );
  }

  factory SyncableRecord.fromLocalRecord({
    required String id,
    required String boxName,
    required Map<String, dynamic> data,
  }) {
    final createdAt =
        DateTime.tryParse(data['createdAt']?.toString() ?? '')?.toUtc() ??
            DateTime.now().toUtc();
    final updatedAt =
        DateTime.tryParse(data['updatedAt']?.toString() ?? '')?.toUtc() ??
            DateTime.now().toUtc();
    final isDeleted = data['isDeleted'] == true;

    return SyncableRecord(
      id: id,
      boxName: boxName,
      data: Map<String, dynamic>.from(data),
      createdAt: createdAt,
      updatedAt: updatedAt,
      isDeleted: isDeleted,
    );
  }
}

// ──────────────────────────────────────────────
//  CLASS: SyncResult
//  Risultato di una sessione di sincronizzazione. Restituito da
//  ClassicSyncEngine.performSync() e consumato dal provider Riverpod
//  per aggiornare la UI con il numero di record inviati/ricevuti.
// ──────────────────────────────────────────────

class SyncResult {
  final bool success;
  final int sentRecords;
  final int receivedRecords;
  final DateTime syncTimestamp;
  final String? error;

  const SyncResult({
    required this.success,
    this.sentRecords = 0,
    this.receivedRecords = 0,
    required this.syncTimestamp,
    this.error,
  });

  @override
  String toString() {
    if (!success) return 'Sync fallita: $error';
    return 'Sync completata: $sentRecords inviati, $receivedRecords ricevuti';
  }
}
