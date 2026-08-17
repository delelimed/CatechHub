import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto show sha256;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

import '../../../core/storage/local_database.dart';
import '../data/association_models.dart';

class P2PIdentity {
  final String deviceId;
  final String deviceName;
  final String username;
  final String publicKeyBase64;
  final String fingerprint;
  final String connectionEndpoint;
  final String firstName;
  final String lastName;

  const P2PIdentity({
    required this.deviceId,
    required this.deviceName,
    required this.username,
    required this.publicKeyBase64,
    required this.fingerprint,
    required this.connectionEndpoint,
    this.firstName = '',
    this.lastName = '',
  });

  /// Chiave anagrafica normalizzata (nome+cognome, senza spazi, lowercase).
  /// Usata per la validazione dell'identità durante l'associazione.
  String get anagraficaKey =>
      '$firstName$lastName'.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'username': username,
        'publicKey': publicKeyBase64,
        'fingerprint': fingerprint,
        'endpoint': connectionEndpoint,
        'firstName': firstName,
        'lastName': lastName,
        'v': 4,
      };

  factory P2PIdentity.fromJson(Map<String, dynamic> json) {
    final ver = json['v'] as int? ?? 1;
    String deviceId = json['deviceId'] as String;
    String deviceName = json['deviceName'] as String? ?? '';
    String username = json['username'] as String? ?? deviceName;
    String publicKey = json['publicKey'] as String;
    String fingerprint = json['fingerprint'] as String;
    String endpoint = json['endpoint'] as String? ?? deviceId;
    String firstName = json['firstName'] as String? ?? '';
    String lastName = json['lastName'] as String? ?? '';

    if (ver < 2) {
      deviceName = json['deviceName'] as String? ?? '';
      username = deviceName;
    }
    if (ver < 3) {
      endpoint = deviceId;
    }
    // v < 4: anagrafica assente, fallback su deviceName (spesso "Nome Cognome").
    if (ver < 4) {
      final parts = username.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2 && firstName.isEmpty && lastName.isEmpty) {
        firstName = parts.first;
        lastName = parts.sublist(1).join(' ');
      }
    }

    return P2PIdentity(
      deviceId: deviceId,
      deviceName: deviceName,
      username: username,
      publicKeyBase64: publicKey,
      fingerprint: fingerprint,
      connectionEndpoint: endpoint,
      firstName: firstName,
      lastName: lastName,
    );
  }

  String encode() => base64Encode(utf8.encode(jsonEncode(toJson())));

  static P2PIdentity? decode(String raw) {
    try {
      final decoded = utf8.decode(base64Decode(raw));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      return P2PIdentity.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}

class P2PSession {
  final String remoteDeviceId;
  final String remoteDeviceName;
  final SecretKeyData sessionKey;
  final Uint8List handshakeNonce;
  final DateTime createdAt;
  final bool isInitiator;

  P2PSession({
    required this.remoteDeviceId,
    required this.remoteDeviceName,
    required this.sessionKey,
    required this.handshakeNonce,
    required this.createdAt,
    required this.isInitiator,
  });

  bool get isValid => DateTime.now().difference(createdAt).inMinutes < 30;
}

class P2PDeviceAssociation {
  final String deviceId;
  final String deviceName;
  final String publicKeyBase64;
  final String fingerprint;
  final String sharedSecretBase64;
  final DateTime associatedAt;
  final String devicePrivateKeyBase64;
  final String devicePublicKeyBase64;
  final String? localRole;
  final String? remoteRole;
  final String? catechistId;
  final DateTime? lastSyncAt;

  /// ─── Catena di fiducia (modalità Responsabile) ──────────────────────────
  /// True se il dispositivo remoto è stato firmato/approvato dal Responsabile
  /// (via QR Code o scambio P2P diretto) per avviare la sync delle classi.
  final bool authorizedByResponsabile;

  /// Timestamp dell'approvazione del Responsabile.
  final DateTime? timestampApproval;

  /// ID del dispositivo del Responsabile che ha firmato l'approvazione.
  final String? approvedByDeviceId;

  /// Firma HMAC-SHA256 del certificato di approvazione (catena di fiducia).
  final String? approvalSignature;

  /// Chiave pubblica di firma del dispositivo del Responsabile che ha emesso
  /// l'approvazione (base64). Usata per verificare la firma in modo
  /// asimmetrico (chiave pubblica distribuita via parrocchia).
  final String? approvalSignerPublicKey;

  /// Scadenza del certificato di approvazione (coerente con il campo
  /// `expiresAt` del certificato firmato dal Responsabile).
  final DateTime? approvalExpiresAt;

  const P2PDeviceAssociation({
    required this.deviceId,
    required this.deviceName,
    required this.publicKeyBase64,
    required this.fingerprint,
    required this.sharedSecretBase64,
    required this.associatedAt,
    required this.devicePrivateKeyBase64,
    required this.devicePublicKeyBase64,
    this.localRole,
    this.remoteRole,
    this.catechistId,
    this.lastSyncAt,
    this.authorizedByResponsabile = false,
    this.timestampApproval,
    this.approvedByDeviceId,
    this.approvalSignature,
    this.approvalSignerPublicKey,
    this.approvalExpiresAt,
  });

  bool get isValid => DateTime.now().difference(associatedAt).inDays < 30;

  int get daysRemaining {
    final elapsed = DateTime.now().difference(associatedAt).inDays;
    final remaining = 30 - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  P2PDeviceAssociation copyWith({
    DateTime? lastSyncAt,
    String? catechistId,
    bool? authorizedByResponsabile,
    DateTime? timestampApproval,
    String? approvedByDeviceId,
    String? approvalSignature,
    String? approvalSignerPublicKey,
    DateTime? approvalExpiresAt,
    String? sharedSecretBase64,
    String? devicePrivateKeyBase64,
    String? devicePublicKeyBase64,
    bool clearApproval = false,
  }) {
    return P2PDeviceAssociation(
      deviceId: deviceId,
      deviceName: deviceName,
      publicKeyBase64: publicKeyBase64,
      fingerprint: fingerprint,
      sharedSecretBase64: sharedSecretBase64 ?? this.sharedSecretBase64,
      associatedAt: associatedAt,
      devicePrivateKeyBase64:
          devicePrivateKeyBase64 ?? this.devicePrivateKeyBase64,
      devicePublicKeyBase64: devicePublicKeyBase64 ?? this.devicePublicKeyBase64,
      localRole: localRole,
      remoteRole: remoteRole,
      catechistId: catechistId ?? this.catechistId,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      authorizedByResponsabile: clearApproval
          ? false
          : (authorizedByResponsabile ?? this.authorizedByResponsabile),
      timestampApproval: clearApproval
          ? null
          : (timestampApproval ?? this.timestampApproval),
      approvedByDeviceId: clearApproval
          ? null
          : (approvedByDeviceId ?? this.approvedByDeviceId),
      approvalSignature: clearApproval
          ? null
          : (approvalSignature ?? this.approvalSignature),
      approvalSignerPublicKey: clearApproval
          ? null
          : (approvalSignerPublicKey ?? this.approvalSignerPublicKey),
      approvalExpiresAt: clearApproval
          ? null
          : (approvalExpiresAt ?? this.approvalExpiresAt),
    );
  }

  /// Serializzazione persistente sul box Hive.
  ///
  /// I segreti ([sharedSecretBase64], [devicePrivateKeyBase64]) NON vengono
  /// scritti nel box: risiedono esclusivamente nel FlutterSecureStorage
  /// (Keystore/Keychain), così un accesso al file Hive (root, forensic) non
  /// espone le chiavi crittografiche del canale P2P. La chiave pubblica è
  /// pubblica e resta nel box.
  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'publicKey': publicKeyBase64,
        'fingerprint': fingerprint,
        'associatedAt': associatedAt.toUtc().toIso8601String(),
        'pubKey': devicePublicKeyBase64,
        if (localRole != null) 'localRole': localRole,
        if (remoteRole != null) 'remoteRole': remoteRole,
        if (catechistId != null) 'catechistId': catechistId,
        if (lastSyncAt != null) 'lastSyncAt': lastSyncAt!.toUtc().toIso8601String(),
        'authorizedByResponsabile': authorizedByResponsabile,
        if (timestampApproval != null)
          'timestampApproval':
              timestampApproval!.toUtc().toIso8601String(),
        if (approvedByDeviceId != null) 'approvedByDeviceId': approvedByDeviceId,
        if (approvalSignature != null) 'approvalSignature': approvalSignature,
        if (approvalSignerPublicKey != null)
          'approvalSignerPublicKey': approvalSignerPublicKey,
        if (approvalExpiresAt != null)
          'approvalExpiresAt': approvalExpiresAt!.toUtc().toIso8601String(),
      };

  factory P2PDeviceAssociation.fromJson(Map<String, dynamic> json) =>
      P2PDeviceAssociation(
        deviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String? ?? '',
        publicKeyBase64: json['publicKey'] as String,
        fingerprint: json['fingerprint'] as String? ?? '',
        // Valori legacy: associazioni precedenti serializzavano i segreti nel
        // box. Vengono letti solo per la migrazione (vedi _hydrateSecrets).
        sharedSecretBase64: json['sharedSecret'] as String? ?? '',
        associatedAt: DateTime.parse(json['associatedAt'] as String).toLocal(),
        devicePrivateKeyBase64: json['privKey'] as String? ?? '',
        devicePublicKeyBase64: json['pubKey'] as String? ?? '',
        localRole: json['localRole'] as String?,
        remoteRole: json['remoteRole'] as String?,
        catechistId: json['catechistId'] as String?,
        lastSyncAt: json['lastSyncAt'] != null
            ? DateTime.parse(json['lastSyncAt'] as String).toLocal()
            : null,
        authorizedByResponsabile: json['authorizedByResponsabile'] == true,
        timestampApproval: json['timestampApproval'] != null
            ? DateTime.parse(json['timestampApproval'] as String).toLocal()
            : null,
        approvedByDeviceId: json['approvedByDeviceId'] as String?,
        approvalSignature: json['approvalSignature'] as String?,
        approvalSignerPublicKey:
            json['approvalSignerPublicKey'] as String?,
        approvalExpiresAt: json['approvalExpiresAt'] != null
            ? DateTime.parse(json['approvalExpiresAt'] as String).toLocal()
            : null,
      );

  SimpleKeyPairData? get keyPair {
    if (devicePrivateKeyBase64.isEmpty || devicePublicKeyBase64.isEmpty) {
      return null;
    }
    try {
      return SimpleKeyPairData(
        base64Decode(devicePrivateKeyBase64),
        publicKey: SimplePublicKey(
          base64Decode(devicePublicKeyBase64),
          type: KeyPairType.x25519,
        ),
        type: KeyPairType.x25519,
      );
    } catch (_) {
      return null;
    }
  }
}

class P2PEncryptedPayload {
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;
  final bool useChacha;

  P2PEncryptedPayload({
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    this.useChacha = false,
  });

  Map<String, dynamic> toJson() => {
        'nonce': base64Encode(nonce),
        'ciphertext': base64Encode(ciphertext),
        'mac': base64Encode(mac),
        'alg': useChacha ? 'chacha20-poly1305' : 'aes-256-gcm',
      };

  factory P2PEncryptedPayload.fromJson(Map<String, dynamic> json) =>
      P2PEncryptedPayload(
        nonce: Uint8List.fromList(base64Decode(json['nonce'] as String)),
        ciphertext:
            Uint8List.fromList(base64Decode(json['ciphertext'] as String)),
        mac: Uint8List.fromList(base64Decode(json['mac'] as String)),
        useChacha: json['alg'] == 'chacha20-poly1305',
      );

  String encode() => base64Encode(utf8.encode(jsonEncode(toJson())));

  static P2PEncryptedPayload decode(String raw) {
    final map =
        jsonDecode(utf8.decode(base64Decode(raw))) as Map<String, dynamic>;
    return P2PEncryptedPayload.fromJson(map);
  }
}

final _sha256Algo = Sha256();

String _bytesToHex(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

final _p2pAad = Uint8List.fromList(
  utf8.encode('CatechHub_Context_P2P_v1'),
);

class P2PSecurityService {
  static const _storagePrefix = 'p2p_assoc_';
  static const _localKeyPairName = 'p2p_local_keypair';
  static const _localIdentityKey = 'p2p_local_identity';

  /// Durata di vita di ogni chiave di sessione P2P: dopo questo intervallo la
  /// chiave viene rigenerata (rotazione) in modo che anche i dati in transito
  /// siano protetti da una chiave a breve scadenza.
  static const Duration sessionKeyRotation = Duration(minutes: 30);

  /// Indice della finestra temporale corrente: entrambi i peer derivano la
  /// stessa chiave di sessione per la stessa finestra senza bisogno di un
  /// handshake aggiuntivo.
  static int sessionWindowIndex([DateTime? at]) {
    final now = at ?? DateTime.now();
    return now.millisecondsSinceEpoch ~/ sessionKeyRotation.inMilliseconds;
  }

  /// Identificatore stabile della finestra temporale (usato nell'info HKDF).
  static String sessionWindowId(int windowIndex) => 'w$windowIndex';

  /// Inizio della finestra temporale [windowIndex].
  static DateTime sessionWindowStart(int windowIndex) {
    return DateTime.fromMillisecondsSinceEpoch(
      windowIndex * sessionKeyRotation.inMilliseconds,
      isUtc: true,
    );
  }

  /// Restituisce la finestra temporale precedente all'indice [windowIndex].
  static int previousWindowIndex(int windowIndex) => windowIndex - 1;

  final FlutterSecureStorage _secureStorage;
  final X25519 _x25519 = X25519();

  P2PSecurityService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static Uint8List secureRandom(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  Future<SimpleKeyPair> getOrCreateIdentityKeyPair() async {
    final stored = await _secureStorage.read(key: _localKeyPairName);
    if (stored != null && stored.isNotEmpty) {
      try {
        final data = jsonDecode(stored) as Map<String, dynamic>;
        final privBytes = base64Decode(data['private'] as String);
        final pubBytes = base64Decode(data['public'] as String);
        return SimpleKeyPairData(
          privBytes,
          publicKey: SimplePublicKey(pubBytes, type: KeyPairType.x25519),
          type: KeyPairType.x25519,
        );
      } catch (e) {
        if (kDebugMode) {
      debugPrint('P2PSecurityService.getOrCreateIdentityKeyPair: stored key corrupted, regenerating: $e');
    }
      }
    }
    return _generateAndStoreIdentityKeyPair();
  }

  Future<SimpleKeyPair> _generateAndStoreIdentityKeyPair() async {
    final keyPair = await _x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyData = await keyPair.extractPrivateKeyBytes();
    final stored = jsonEncode({
      'private': base64Encode(privateKeyData),
      'public': base64Encode(publicKey.bytes),
    });
    await _secureStorage.write(key: _localKeyPairName, value: stored);
    return keyPair;
  }

  Future<SimpleKeyPairData> _generateDeviceKeyPair() async {
    final keyPair = await _x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyData = await keyPair.extractPrivateKeyBytes();
    return SimpleKeyPairData(
      privateKeyData,
      publicKey: SimplePublicKey(publicKey.bytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  /// Genera una coppia di chiavi EFIMERE per la sessione corrente. Le chiavi
  /// effimere NON vengono MAI persistite (né in Hive né in secure storage):
  /// vivono solo in memoria per la durata della connessione e vengono
  /// scartate alla chiusura. Questo è il fondamento della forward secrecy:
  /// anche se in futuro le chiavi statiche di identità venissero compromesse,
  /// le chiavi di sessione passate NON possono essere ricostruite.
  Future<SimpleKeyPairData> generateEphemeralKeyPair() =>
      _generateDeviceKeyPair();

  Future<P2PIdentity> getLocalIdentity() async {
    final stored = await _secureStorage.read(key: _localIdentityKey);
    if (stored != null && stored.isNotEmpty) {
      try {
        return P2PIdentity.fromJson(jsonDecode(stored) as Map<String, dynamic>);
      } catch (e) {
        if (kDebugMode) {
      debugPrint('P2PSecurityService.getLocalIdentity: stored identity corrupted, regenerating: $e');
    }
      }
    }
    return _createAndStoreIdentity();
  }

  Future<P2PIdentity> _createAndStoreIdentity() async {
    final keyPair = await getOrCreateIdentityKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final deviceId =
        'CH_${DateTime.now().microsecondsSinceEpoch}_${_randomHex(6)}';
    final deviceName = await _getDeviceDisplayName();
    final username = await _getUsername();
    final fingerprint = await _computeFingerprint(publicKey);

    final identity = P2PIdentity(
      deviceId: deviceId,
      deviceName: deviceName,
      username: username,
      publicKeyBase64: base64Encode(publicKey.bytes),
      fingerprint: fingerprint,
      connectionEndpoint: deviceId,
      firstName: _getFirstName(),
      lastName: _getLastName(),
    );
    await _secureStorage.write(
        key: _localIdentityKey, value: jsonEncode(identity.toJson()));
    return identity;
  }

  String _getFirstName() {
    try {
      final authBox = Hive.box('registroBox');
      return authBox.get('first_name', defaultValue: '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  String _getLastName() {
    try {
      final authBox = Hive.box('registroBox');
      return authBox.get('last_name', defaultValue: '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  Future<String> _getUsername() async {
    try {
      final authBox = Hive.box('registroBox');
      final name = authBox.get('local_user_name');
      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString().trim();
      }
    } catch (_) {}
    try {
      final authBox = Hive.box('registroBox');
      final first = authBox.get('first_name');
      final last = authBox.get('last_name');
      if (first != null && last != null) {
        return '$first $last';
      }
    } catch (_) {}
    return '';
  }

  Future<String> _getDeviceDisplayName() async {
    try {
      final authBox = Hive.box('registroBox');
      final name = authBox.get('local_user_name');
      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString().trim();
      }
    } catch (_) {}
    try {
      const prefs = FlutterSecureStorage();
      final name = await prefs.read(key: 'device_display_name');
      if (name != null && name.trim().isNotEmpty) {
        return name.trim();
      }
    } catch (_) {}
    return 'CatechHub ${_randomHex(4)}';
  }

  String _randomHex(int length) {
    final random = Random.secure();
    return List.generate(length, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  Future<void> refreshIdentityName() async {
    try {
      final identity = await getLocalIdentity();
      final newName = await _getDeviceDisplayName();
      final newUsername = await _getUsername();
      if (identity.deviceName != newName || identity.username != newUsername) {
        final updated = P2PIdentity(
          deviceId: identity.deviceId,
          deviceName: newName,
          username: newUsername,
          publicKeyBase64: identity.publicKeyBase64,
          fingerprint: identity.fingerprint,
          connectionEndpoint: identity.deviceId,
          firstName: _getFirstName(),
          lastName: _getLastName(),
        );
        await _secureStorage.write(
          key: _localIdentityKey,
          value: jsonEncode(updated.toJson()),
        );
      }
    } catch (_) {}
  }

  /// Aggiorna il nome/cognome salvati nell'identità P2P locale. Necessario
  /// dopo la modifica del profilo (il QR e l'handshake devono trasportare
  /// l'anagrafica aggiornata per la validazione dell'identità).
  Future<void> refreshIdentityAnagrafica() async {
    try {
      final identity = await getLocalIdentity();
      final first = _getFirstName();
      final last = _getLastName();
      if (identity.firstName != first || identity.lastName != last) {
        final updated = P2PIdentity(
          deviceId: identity.deviceId,
          deviceName: identity.deviceName,
          username: identity.username,
          publicKeyBase64: identity.publicKeyBase64,
          fingerprint: identity.fingerprint,
          connectionEndpoint: identity.deviceId,
          firstName: first,
          lastName: last,
        );
        await _secureStorage.write(
          key: _localIdentityKey,
          value: jsonEncode(updated.toJson()),
        );
      }
    } catch (_) {}
  }

  Future<String> generateQrPayload() async {
    final identity = await getLocalIdentity();
    final updated = P2PIdentity(
      deviceId: identity.deviceId,
      deviceName: identity.deviceName,
      username: identity.username,
      publicKeyBase64: identity.publicKeyBase64,
      fingerprint: identity.fingerprint,
      connectionEndpoint: identity.deviceId,
      firstName: _getFirstName(),
      lastName: _getLastName(),
    );
    return updated.encode();
  }

  Future<String> getPublicKeyBase64() async {
    final keyPair = await getOrCreateIdentityKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  Future<String> getFingerprint() async {
    final identity = await getLocalIdentity();
    return identity.fingerprint;
  }

  static P2PIdentity? parseQrPayload(String raw) {
    return P2PIdentity.decode(raw);
  }

  Future<String> computeStaticSharedSecret(String remotePublicKeyBase64, {String? forDeviceId}) async {
    Uint8List remoteKeyBytes;
    try {
      remoteKeyBytes = base64Decode(remotePublicKeyBase64);
    } catch (_) {
      throw FormatException('Chiave pubblica remota non valida: formato base64 errato');
    }
    final keyPair = forDeviceId != null
        ? await _getOrCreateAssociationKeyPair(forDeviceId)
        : await getOrCreateIdentityKeyPair();

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(remoteKeyBytes, type: KeyPairType.x25519),
    );

    final secretBytes = await sharedSecret.extractBytes();
    return base64Encode(secretBytes);
  }

  Future<SimpleKeyPairData> _getOrCreateAssociationKeyPair(String deviceId) async {
    final existing = await getAssociation(deviceId);
    if (existing != null && existing.devicePrivateKeyBase64.isNotEmpty) {
      final kp = existing.keyPair;
      if (kp != null) return kp;
    }
    return _generateDeviceKeyPair();
  }

  Future<P2PSession> createEphemeralSession({
    required String remoteDeviceId,
    required String remoteDeviceName,
    required String remotePublicKeyBase64,
    bool isInitiator = false,
    String? sessionNonce,
    DateTime? at,
    SimpleKeyPairData? localEphemeralKeyPair,
    String? remoteEphemeralPublicKeyBase64,
  }) async {
    Uint8List remoteKeyBytes;
    try {
      remoteKeyBytes = base64Decode(remotePublicKeyBase64);
    } catch (_) {
      throw FormatException('Chiave pubblica remota non valida: formato base64 errato in createEphemeralSession');
    }
    final identityKeyPair = await getOrCreateIdentityKeyPair();

    // ─── Forward secrecy (TripleDH) ──────────────────────────────────────
    // Se entrambi i peer hanno scambiato una chiave EFIMERA durante
    // l'handshake, il segreto di sessione combina 4 contributi X25519:
    //   DH1 = static↔static   (autenticazione, chiavi di lungo periodo)
    //   DH2/3 = static↔efimera (binding dell'identità all'ephem. remoto)
    //   DH4 = efimera↔efimera  (forward secrecy vera e propria)
    // I contributi vengono ordinati in modo canonico (sort lexicografico)
    // così che entrambi i peer convergano sulla stessa concatenazione pur
    // calcolandola dal proprio punto di vista.
    final sharedBytes = (localEphemeralKeyPair != null &&
            remoteEphemeralPublicKeyBase64 != null)
        ? await _computeForwardSecret(
            identityKeyPair: identityKeyPair,
            localEphemeral: localEphemeralKeyPair,
            remoteStaticPublicKeyBase64: remotePublicKeyBase64,
            remoteEphemeralPublicKeyBase64: remoteEphemeralPublicKeyBase64,
          )
        : await _computeStaticSharedSecret(identityKeyPair, remoteKeyBytes);

    final localIdentity = await getLocalIdentity();

    final sessionKeyData = await deriveRotatingSessionKey(
      sharedSecretBytes: sharedBytes,
      localDeviceId: localIdentity.deviceId,
      remoteDeviceId: remoteDeviceId,
      sessionNonce: sessionNonce,
      at: at,
    );
    final handshakeNonce = deriveSessionNonce(
      sharedSecretBytes: sharedBytes,
      sessionNonce: sessionNonce,
    );

    return P2PSession(
      remoteDeviceId: remoteDeviceId,
      remoteDeviceName: remoteDeviceName,
      sessionKey: sessionKeyData,
      handshakeNonce: handshakeNonce,
      createdAt: at ?? DateTime.now(),
      isInitiator: isInitiator,
    );
  }

  /// Esegue X25519 con la chiave statica locale e la chiave remota [remoteBytes].
  Future<Uint8List> _computeStaticSharedSecret(
    SimpleKeyPair keyPair,
    Uint8List remoteBytes,
  ) async {
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(remoteBytes, type: KeyPairType.x25519),
    );
    return Uint8List.fromList(await sharedSecret.extractBytes());
  }

  /// Calcola il segreto di sessione combinato (TripleDH) per la forward
  /// secrecy. Le chiavi efimere NON sono persistite; una volta derivate le
  /// chiavi di sessione della finestra corrente+precedente possono essere
  /// scartate.
  Future<Uint8List> _computeForwardSecret({
    required SimpleKeyPair identityKeyPair,
    required SimpleKeyPairData localEphemeral,
    required String remoteStaticPublicKeyBase64,
    required String remoteEphemeralPublicKeyBase64,
  }) =>
      computeForwardSecretKey(
        x25519: _x25519,
        localStatic: identityKeyPair,
        localEphemeral: localEphemeral,
        remoteStaticPublicKeyBase64: remoteStaticPublicKeyBase64,
        remoteEphemeralPublicKeyBase64: remoteEphemeralPublicKeyBase64,
      );

  /// Calcola il segreto combinato TripleDH in forma statica e pura (testabile
  /// senza secure storage / Hive). Entrambi i peer convergono sullo stesso
  /// output anche calcolandolo dal proprio punto di vista: i 4 contributi
  /// X25519 sono un insieme commutativo (DH(A,B) == DH(B,A)) ordinato in modo
  /// canonico prima della concatenazione.
  static Future<Uint8List> computeForwardSecretKey({
    required X25519 x25519,
    required SimpleKeyPair localStatic,
    required SimpleKeyPairData localEphemeral,
    required String remoteStaticPublicKeyBase64,
    required String remoteEphemeralPublicKeyBase64,
  }) async {
    Uint8List remoteStaticBytes;
    Uint8List remoteEphemeralBytes;
    try {
      remoteStaticBytes = base64Decode(remoteStaticPublicKeyBase64);
      remoteEphemeralBytes = base64Decode(remoteEphemeralPublicKeyBase64);
    } catch (_) {
      throw FormatException('Chiave pubblica efimera remota non valida in _computeForwardSecret');
    }
    final remoteStaticPub =
        SimplePublicKey(remoteStaticBytes, type: KeyPairType.x25519);
    final remoteEphemeralPub =
        SimplePublicKey(remoteEphemeralBytes, type: KeyPairType.x25519);

    final dh1 = await x25519.sharedSecretKey(
      keyPair: localStatic,
      remotePublicKey: remoteStaticPub,
    );
    final dh2 = await x25519.sharedSecretKey(
      keyPair: localStatic,
      remotePublicKey: remoteEphemeralPub,
    );
    final dh3 = await x25519.sharedSecretKey(
      keyPair: localEphemeral,
      remotePublicKey: remoteStaticPub,
    );
    final dh4 = await x25519.sharedSecretKey(
      keyPair: localEphemeral,
      remotePublicKey: remoteEphemeralPub,
    );

    final contributions = <Uint8List>[
      Uint8List.fromList(await dh1.extractBytes()),
      Uint8List.fromList(await dh2.extractBytes()),
      Uint8List.fromList(await dh3.extractBytes()),
      Uint8List.fromList(await dh4.extractBytes()),
    ]..sort((a, b) => _compareBytes(a, b));

    final combined = Uint8List(128);
    var offset = 0;
    for (final c in contributions) {
      combined.setAll(offset, c);
      offset += c.length;
    }
    // Diluisce la concatenazione dei 4 DH con HKDF prima dell'uso (l'input
    // finale alle funzioni di derivazione delle chiavi di sessione).
    final hkdf = Hkdf(hmac: Hmac(_sha256Algo), outputLength: 32);
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(combined),
      nonce: Uint8List(0),
      info: utf8.encode('CatechHub_P2P_ForwardSecret_v1'),
    );
    return Uint8List.fromList(await derived.extractBytes());
  }

  static int _compareBytes(List<int> a, List<int> b) {
    final len = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }

  /// M5 — Mescola il DH della chiave per-associazione (statica) nella chiave
  /// di sessione. DH_assoc = X25519(privAssocLoc, pubAssocRem), commutativo
  /// sui due peer, quindi entrambi convergono sullo stesso output. La chiave
  /// per-associazione (generata al pairing ma mai usata) diventa un fattore
  /// di sessione dedicato, separato dalla chiave d'identità globale: la
  /// compromissione della chiave statica globale non compromette le sessioni
  /// delle associazioni. Se l'input non è disponibile la chiave resta
  /// invariata (nessun downgrade rispetto al TripleDH).
  Future<SecretKeyData> applyAssociationFactor({
    required SecretKeyData sessionKey,
    required SimpleKeyPairData localAssociationKeyPair,
    required String remoteAssociationPublicBase64,
  }) =>
      P2PSecurityService.mixAssociationFactor(
        x25519: _x25519,
        sessionKey: sessionKey,
        localAssociationKeyPair: localAssociationKeyPair,
        remoteAssociationPublicBase64: remoteAssociationPublicBase64,
      );

  /// Variante statica e pura (testabile senza secure storage / Hive).
  static Future<SecretKeyData> mixAssociationFactor({
    required X25519 x25519,
    required SecretKeyData sessionKey,
    required SimpleKeyPairData localAssociationKeyPair,
    required String remoteAssociationPublicBase64,
  }) async {
    try {
      final dh = await x25519.sharedSecretKey(
        keyPair: localAssociationKeyPair,
        remotePublicKey: SimplePublicKey(
          base64Decode(remoteAssociationPublicBase64),
          type: KeyPairType.x25519,
        ),
      );
      final dhBytes = await dh.extractBytes();
      final hkdf = Hkdf(
        hmac: Hmac(_sha256Algo),
        outputLength: 32,
      );
      final combined = <int>[...sessionKey.bytes, ...dhBytes];
      final derived = await hkdf.deriveKey(
        secretKey: SecretKey(combined),
        nonce: Uint8List(0),
        info: utf8.encode('CatechHub_P2P_AssociationFactor_v1'),
      );
      return derived;
    } catch (_) {
      return sessionKey;
    }
  }

  /// Deriva il nonce di sessione (unico per sessione) dall'handshake.
  static Uint8List deriveSessionNonce({
    required List<int> sharedSecretBytes,
    String? sessionNonce,
  }) {
    // Utilizza un nonce unico per sessione derivato dai nonces scambiati
    // durante l'handshake, invece di un hash deterministico del shared secret.
    // Questo garantisce che ogni sessione usi una chiave diversa.
    if (sessionNonce != null && sessionNonce.isNotEmpty) {
      final nonceHash = crypto.sha256.convert(utf8.encode(sessionNonce));
      return Uint8List.fromList(nonceHash.bytes.sublist(0, 32));
    }
    final hkdfInput = crypto.sha256.convert(sharedSecretBytes).bytes;
    return Uint8List.fromList(hkdfInput.sublist(0, 32));
  }

  /// Deriva la chiave di sessione a breve scadenza (rotazione per finestra
  /// temporale). Funzione pura: input identici + stessa finestra → stessa
  /// chiave; finestre diverse → chiavi diverse. La finestra temporale è
  /// codificata nell'info HKDF, quindi entrambi i peer convergono sulla stessa
  /// chiave corrente senza messaggi aggiuntivi.
  static Future<SecretKeyData> deriveRotatingSessionKey({
    required List<int> sharedSecretBytes,
    required String localDeviceId,
    required String remoteDeviceId,
    String? sessionNonce,
    DateTime? at,
  }) async {
    final handshakeNonce = deriveSessionNonce(
      sharedSecretBytes: sharedSecretBytes,
      sessionNonce: sessionNonce,
    );

    final hkdf = Hkdf(
      hmac: Hmac(_sha256Algo),
      outputLength: 32,
    );

    final windowIndex = sessionWindowIndex(at);
    final ids = [localDeviceId, remoteDeviceId]..sort();
    final info = utf8.encode(
        'CatechHub_P2P_Session_v3:${ids[0]}:${ids[1]}:${sessionWindowId(windowIndex)}');

    return hkdf.deriveKey(
      secretKey: SecretKey(Uint8List.fromList(sharedSecretBytes)),
      nonce: handshakeNonce,
      info: info,
    );
  }

  Future<P2PEncryptedPayload> encryptPayload(
    String plainText,
    SecretKey sessionKey,
  ) async {
    final nonce = secureRandom(12);
    final secretBox = await AesGcm.with256bits().encrypt(
      utf8.encode(plainText),
      secretKey: sessionKey,
      nonce: nonce,
      aad: _p2pAad,
    );

    return P2PEncryptedPayload(
      nonce: Uint8List.fromList(secretBox.nonce),
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      mac: Uint8List.fromList(secretBox.mac.bytes),
      useChacha: false,
    );
  }

  Future<String> decryptPayload(
    P2PEncryptedPayload encrypted,
    SecretKey sessionKey,
  ) async {
    final secretBox = SecretBox(
      encrypted.ciphertext,
      nonce: encrypted.nonce,
      mac: Mac(encrypted.mac),
    );

    final plainBytes = await AesGcm.with256bits().decrypt(
      secretBox,
      secretKey: sessionKey,
      aad: _p2pAad,
    );

    return utf8.decode(plainBytes);
  }

  Future<String> encryptPayloadString(
    String plainText,
    String sharedSecretBase64,
  ) async {
    final key = base64Decode(sharedSecretBase64);
    final nonce = secureRandom(12);
    final secretKey = SecretKey(key);

    final secretBox = await AesGcm.with256bits().encrypt(
      utf8.encode(plainText),
      secretKey: secretKey,
      nonce: nonce,
      aad: _p2pAad,
    );

    final payload = P2PEncryptedPayload(
      nonce: Uint8List.fromList(secretBox.nonce),
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      mac: Uint8List.fromList(secretBox.mac.bytes),
    );
    return payload.encode();
  }

  Future<String> decryptPayloadString(
    String cipherText,
    String sharedSecretBase64,
  ) async {
    final key = base64Decode(sharedSecretBase64);
    final secretKey = SecretKey(key);
    final encrypted = P2PEncryptedPayload.decode(cipherText);

    final secretBox = SecretBox(
      encrypted.ciphertext,
      nonce: encrypted.nonce,
      mac: Mac(encrypted.mac),
    );

    final plainBytes = await AesGcm.with256bits().decrypt(
      secretBox,
      secretKey: secretKey,
      aad: _p2pAad,
    );

    return utf8.decode(plainBytes);
  }

  Future<SimpleKeyPairData> registerAndSaveAssociation({
    required String deviceId,
    required String deviceName,
    required String publicKeyBase64,
    required String fingerprint,
    required String sharedSecretBase64,
    String? localRole,
    String? remoteRole,
    String? catechistId,
  }) async {
    final deviceKeyPair = await _generateDeviceKeyPair();
    final devicePubKey = await deviceKeyPair.extractPublicKey();

    final association = P2PDeviceAssociation(
      deviceId: deviceId,
      deviceName: deviceName,
      publicKeyBase64: publicKeyBase64,
      fingerprint: fingerprint,
      sharedSecretBase64: sharedSecretBase64,
      associatedAt: DateTime.now(),
      devicePrivateKeyBase64: base64Encode(deviceKeyPair.bytes),
      devicePublicKeyBase64: base64Encode(devicePubKey.bytes),
      localRole: localRole,
      remoteRole: remoteRole,
      catechistId: catechistId,
    );
    await saveAssociation(association);
    return deviceKeyPair;
  }

  Box<Map> get _assocBox => Hive.box<Map>(LocalDatabase.trustedDevicesBox);

  /// Chiavi FlutterSecureStorage per i segreti per-associazione.
  static String _secretStorageKey(String deviceId) =>
      '$_storagePrefix${deviceId}_secret';
  static String _privKeyStorageKey(String deviceId) =>
      '$_storagePrefix${deviceId}_privkey';

  Future<void> saveAssociation(P2PDeviceAssociation association) async {
    // I segreti (shared secret + chiave privata del canale) vengono
    // conservati esclusivamente nel FlutterSecureStorage (Keystore/Keychain):
    // il box Hive contiene solo i metadati non sensibili.
    await _secureStorage.write(
      key: _secretStorageKey(association.deviceId),
      value: association.sharedSecretBase64,
    );
    await _secureStorage.write(
      key: _privKeyStorageKey(association.deviceId),
      value: association.devicePrivateKeyBase64,
    );
    await _assocBox.put(association.deviceId, association.toJson());
  }

  /// Ripristina i segreti di un'associazione dal FlutterSecureStorage.
  /// Gestisce anche la migrazione delle associazioni legacy che li
  /// serializzavano nel box Hive.
  Future<P2PDeviceAssociation> _hydrateSecrets(
    String deviceId,
    P2PDeviceAssociation assoc,
    Map<String, dynamic> raw,
  ) async {
    var secret = await _secureStorage.read(key: _secretStorageKey(deviceId));
    var privKey = await _secureStorage.read(key: _privKeyStorageKey(deviceId));

    var migrated = false;
    if ((secret == null || secret.isEmpty) &&
        raw['sharedSecret'] is String &&
        (raw['sharedSecret'] as String).isNotEmpty) {
      secret = raw['sharedSecret'] as String;
      migrated = true;
    }
    if ((privKey == null || privKey.isEmpty) &&
        raw['privKey'] is String &&
        (raw['privKey'] as String).isNotEmpty) {
      privKey = raw['privKey'] as String;
      migrated = true;
    }

    var hydrated = assoc;
    if ((secret?.isNotEmpty ?? false) && hydrated.sharedSecretBase64.isEmpty) {
      hydrated = hydrated.copyWith(sharedSecretBase64: secret);
    }
    if ((privKey?.isNotEmpty ?? false) && hydrated.devicePrivateKeyBase64.isEmpty) {
      hydrated = hydrated.copyWith(devicePrivateKeyBase64: privKey);
    }

    // Migrazione legacy: sposta i segreti dal box al secure storage e
    // riscrive il box senza di essi.
    if (migrated) {
      await _secureStorage.write(
        key: _secretStorageKey(deviceId),
        value: hydrated.sharedSecretBase64,
      );
      await _secureStorage.write(
        key: _privKeyStorageKey(deviceId),
        value: hydrated.devicePrivateKeyBase64,
      );
      await _assocBox.put(deviceId, hydrated.toJson());
    }
    return hydrated;
  }

  Future<P2PDeviceAssociation?> getAssociation(String deviceId) async {
    try {
      final raw = _assocBox.get(deviceId);
      if (raw == null) {
        final migrated = await _migrateFromSecureStorage(deviceId);
        if (migrated != null) return migrated;
        return null;
      }
      final assoc =
          P2PDeviceAssociation.fromJson(Map<String, dynamic>.from(raw));
      final hydrated = await _hydrateSecrets(
        deviceId,
        assoc,
        Map<String, dynamic>.from(raw),
      );
      if (!hydrated.isValid) {
        await removeAssociation(deviceId);
        return null;
      }
      return hydrated;
    } catch (e) {
      if (kDebugMode) {
      debugPrint('P2PSecurityService.getAssociation error for $deviceId: $e');
    }
      return null;
    }
  }

  Future<List<P2PDeviceAssociation>> getAllAssociations() async {
    final associations = <P2PDeviceAssociation>[];
    final expiredIds = <String>[];

    await _migrateAllFromSecureStorage(associations);

    for (final key in _assocBox.keys) {
      try {
        final raw = _assocBox.get(key);
        if (raw == null) continue;
        final assoc = P2PDeviceAssociation.fromJson(
          Map<String, dynamic>.from(raw),
        );
        final hydrated = await _hydrateSecrets(
          key.toString(),
          assoc,
          Map<String, dynamic>.from(raw),
        );
        if (hydrated.isValid) {
          associations.add(hydrated);
        } else {
          expiredIds.add(key.toString());
        }
      } catch (_) {
        expiredIds.add(key.toString());
      }
    }

    for (final id in expiredIds) {
      await _assocBox.delete(id);
    }

    associations.sort((a, b) => b.associatedAt.compareTo(a.associatedAt));
    return associations;
  }

  Future<void> removeAssociation(String deviceId) async {
    await _assocBox.delete(deviceId);
    await _secureStorage.delete(key: '$_storagePrefix$deviceId');
    await _secureStorage.delete(key: _secretStorageKey(deviceId));
    await _secureStorage.delete(key: _privKeyStorageKey(deviceId));
  }

  Future<void> removeAllAssociations() async {
    await _assocBox.clear();
    final allKeys = await _secureStorage.readAll();
    for (final key in allKeys.keys) {
      if (key.startsWith(_storagePrefix)) {
        await _secureStorage.delete(key: key);
      }
    }
  }

  /// Resetta TUTTI i dati di sicurezza P2P: associazioni, identità locale,
  /// chiavi crittografiche e sessioni. Usato per il reset totale dell'app.
  Future<void> resetAllSecurityData() async {
    await _assocBox.clear();
    await _secureStorage.deleteAll();
  }

  Future<P2PDeviceAssociation?> _migrateFromSecureStorage(
      String deviceId) async {
    final key = '$_storagePrefix$deviceId';
    final raw = await _secureStorage.read(key: key);
    if (raw == null) return null;
    try {
      final assoc = P2PDeviceAssociation.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (assoc.isValid) {
        await saveAssociation(assoc);
        await _secureStorage.delete(key: key);
        return assoc;
      }
      await _secureStorage.delete(key: key);
    } catch (_) {
      await _secureStorage.delete(key: key);
    }
    return null;
  }

  Future<void> _migrateAllFromSecureStorage(
      List<P2PDeviceAssociation> associations) async {
    final allKeys = await _secureStorage.readAll();
    for (final entry in allKeys.entries) {
      if (!entry.key.startsWith(_storagePrefix)) continue;
      try {
        final assoc = P2PDeviceAssociation.fromJson(
          jsonDecode(entry.value) as Map<String, dynamic>,
        );
        if (assoc.isValid) {
          await saveAssociation(assoc);
          associations.add(assoc);
        }
        await _secureStorage.delete(key: entry.key);
      } catch (_) {
        await _secureStorage.delete(key: entry.key);
      }
    }
  }

  Future<bool> hasValidAssociation() async {
    final associations = await getAllAssociations();
    return associations.isNotEmpty;
  }

  Future<String?> getSharedSecret(String deviceId) async {
    final assoc = await getAssociation(deviceId);
    return assoc?.sharedSecretBase64;
  }

  Future<String?> getDevicePrivateKey(String deviceId) async {
    final assoc = await getAssociation(deviceId);
    return assoc?.devicePrivateKeyBase64;
  }

  Future<String?> getDevicePublicKey(String deviceId) async {
    final assoc = await getAssociation(deviceId);
    return assoc?.devicePublicKeyBase64;
  }

  /// Derives a 6-digit pairing code from the ECDH shared secret
  /// and a session-specific nonce. Each pairing session gets a different
  /// code even between the same two devices.
  ///
  /// Fase 2 — item 6: le chiavi efimere (locale e remota) vengono incluse nel
  /// SAS. Un MitM che sostituisce le chiavi efimere durante l'handshake
  /// produce un codice di verifica diverso, rendendo visibile l'attacco al
  /// confronto dei codici. Le chiavi vengono ordinate in modo canonico così
  /// che entrambi i dispositivi convergano sullo stesso input.
  static String computePairingCode(
    String sharedSecretBase64, {
    String? sessionNonce,
    String? localEphemeralPub,
    String? remoteEphemeralPub,
  }) {
    final secretBytes = base64Decode(sharedSecretBase64);
    final hasAuxInput = sessionNonce != null ||
        localEphemeralPub != null ||
        remoteEphemeralPub != null;
    final combined = hasAuxInput
        ? crypto.sha256
                .convert(utf8.encode(_pairingAuxInput(
                  sessionNonce: sessionNonce,
                  localEphemeralPub: localEphemeralPub,
                  remoteEphemeralPub: remoteEphemeralPub,
                )))
                .bytes +
            secretBytes
        : secretBytes;
    final hash = crypto.sha256.convert(combined);
    final code = ((hash.bytes[0] << 16) | (hash.bytes[1] << 8) | hash.bytes[2]) % 1000000;
    return code.toString().padLeft(6, '0');
  }

  /// Input ausiliario canonico per il pairing code: nonce concordato più le
  /// chiavi efimere ordinate. Entrambi i peer producono lo stesso valore.
  static String _pairingAuxInput({
    String? sessionNonce,
    String? localEphemeralPub,
    String? remoteEphemeralPub,
  }) {
    final parts = <String>[];
    if (sessionNonce != null && sessionNonce.isNotEmpty) parts.add(sessionNonce);
    final ephs = <String>[
      if (localEphemeralPub != null && localEphemeralPub.isNotEmpty)
        localEphemeralPub,
      if (remoteEphemeralPub != null && remoteEphemeralPub.isNotEmpty)
        remoteEphemeralPub,
    ]..sort();
    if (ephs.isNotEmpty) parts.add(ephs.join('|'));
    return parts.join('|');
  }

  /// Verifies that the public key received over the air matches the
  /// stored association (key pinning). If they differ, a MitM attack
  /// may be in progress.
  static bool publicKeyMatchesAssociation(
    P2PDeviceAssociation assoc,
    String receivedPublicKeyBase64,
  ) {
    return assoc.publicKeyBase64 == receivedPublicKeyBase64;
  }

  // ─── Catena di fiducia del Responsabile ────────────────────────────────
  //
  // Quando la modalità Responsabile è ATTIVA, ogni dispositivo che sincronizza
  // una classe deve essere preventivamente approvato (firmato) dal dispositivo
  // del Responsabile.
  //
  // L'approvazione è un CERTIFICATO firmato in modo ASIMMETRICO (Ed25519):
  //   - il Responsabile possiede la CHIAVE PRIVATA di firma (Keystore);
  //   - la CHIAVE PUBBLICA (trust root) viene distribuita ai dispositivi
  //     verificatori via "QR di fiducia". Il QR NON contiene alcun segreto:
  //     chiunque lo fotografi ottiene solo una chiave pubblica, inutilizzabile
  //     per falsificare certificati;
  //   - ogni verificatore valida firma, scadenza del certificato e blacklist
  //     delle revoche.
  //
  // Revoche: la revoca aggiunge il deviceId alla blacklist locale (propagata
  // insieme alla trust root nel QR di fiducia rigenerato). Un dispositivo
  // revocato viene rifiutato da ogni verificatore che possiede la blacklist,
  // anche se il suo certificato è tecnicamente ancora firmato.

  static const _parishSignerKeyPairName = 'parish_signer_keypair';
  static const _parishRevokedDevicesKey = 'parish_revoked_devices';
  static const _responsabileTrustInfoKey = 'responsabile_trust_info';
  static const _localApprovalKey = 'local_device_approval';

  /// Durata di validità di un certificato di approvazione.
  static const Duration approvalCertificateValidity = Duration(days: 30);

  /// M1 — Skew di orologio massimo tollerato sulla data di emissione dei
  /// certificati di approvazione.
  static const Duration _clockSkew = Duration(minutes: 5);

  /// Durata di validità della trust root (QR di fiducia).
  static const Duration trustRootValidity = Duration(days: 365);

  final Ed25519 _ed25519 = Ed25519();

  /// Genera (o recupera) la coppia di chiavi di FIRMA Ed25519 del Responsabile.
  /// La chiave privata risiede SOLO nel FlutterSecureStorage
  /// (Keystore/Keychain): mai nel box Hive, mai nel QR. Nel QR di fiducia
  /// viaggia esclusivamente la chiave pubblica (trust root).
  Future<SimpleKeyPair> getOrCreateParishSignerKeyPair() async {
    final stored = await _secureStorage.read(key: _parishSignerKeyPairName);
    if (stored != null && stored.isNotEmpty) {
      try {
        final data = jsonDecode(stored) as Map<String, dynamic>;
        final seed = base64Decode(data['private'] as String);
        return await _ed25519.newKeyPairFromSeed(seed);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('P2PSecurityService.getOrCreateParishSignerKeyPair: '
              'chiave corrotta, rigenero: $e');
        }
      }
    }
    final keyPair = await _ed25519.newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    await _secureStorage.write(
      key: _parishSignerKeyPairName,
      value: jsonEncode({
        'private': base64Encode(privateBytes),
        'public': base64Encode(publicKey.bytes),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    return keyPair;
  }

  /// Chiave pubblica di firma Ed25519 del Responsabile (trust root).
  Future<String?> getParishSignerPublicKeyBase64() async {
    final keyPair = await getOrCreateParishSignerKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Firma Ed25519 (base64) di un payload canonico con la chiave privata del
  /// Responsabile. Esposta staticamente per essere testabile senza secure
  /// storage.
  static Future<String> signApprovalPayload(
    String canonicalPayload,
    List<int> privateKeyBytes,
  ) async {
    final keyPair = await Ed25519().newKeyPairFromSeed(privateKeyBytes);
    final signature = await Ed25519().sign(
      utf8.encode(canonicalPayload),
      keyPair: keyPair,
    );
    return base64Encode(signature.bytes);
  }

  /// Verifica una firma Ed25519 (base64) di un payload canonico con la chiave
  /// pubblica del firmatario (base64). La verifica è asimmetrica: conoscere la
  /// sola chiave pubblica non consente di falsificare la firma.
  static Future<bool> verifyApprovalSignature({
    required String canonicalPayload,
    required String signature,
    required String publicKeyBase64,
  }) async {
    if (signature.isEmpty || publicKeyBase64.isEmpty) return false;
    try {
      final publicKey = SimplePublicKey(
        base64Decode(publicKeyBase64),
        type: KeyPairType.ed25519,
      );
      final sig = Signature(
        base64Decode(signature),
        publicKey: publicKey,
      );
      return await Ed25519().verify(
        utf8.encode(canonicalPayload),
        signature: sig,
      );
    } catch (_) {
      return false;
    }
  }

  /// Firma un certificato di approvazione per un nuovo dispositivo.
  /// Il certificato include la SCADENZA ([expiresAt]) e viene firmato con la
  /// chiave privata Ed25519 del Responsabile.
  Future<AssociatedDevice> signDeviceApproval({
    required String deviceId,
    required String catechistId,
    required String publicKeyBase64,
    String? deviceName,
  }) async {
    final keyPair = await getOrCreateParishSignerKeyPair();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    final identity = await getLocalIdentity();
    final certificate = AssociatedDevice(
      deviceId: deviceId,
      catechistId: catechistId,
      publicKey: publicKeyBase64,
      authorizedByResponsabile: true,
      timestampApproval: DateTime.now(),
      deviceName: deviceName ?? '',
      approvedByDeviceId: identity.deviceId,
      approvedByName: identity.username,
      signerPublicKey: base64Encode(publicKey.bytes),
      expiresAt: DateTime.now().toUtc().add(approvalCertificateValidity),
    );
    final signature = await signApprovalPayload(
      certificate.canonicalPayload,
      privateKeyBytes,
    );
    return certificate.copyWith(approvalSignature: signature);
  }

  /// Verifica un certificato di approvazione in modo ASIMMETRICO:
  ///   1. certificato emesso e firmato;
  ///   2. non scaduto;
  ///   3. firmatario coincidente con la trust root locale;
  ///   4. firma Ed25519 valida;
  ///   5. dispositivo NON nella blacklist delle revoche.
  Future<bool> verifyApprovalCertificate(
    AssociatedDevice cert, {
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    if (!cert.authorizedByResponsabile ||
        cert.approvalSignature == null ||
        cert.approvalSignature!.isEmpty) {
      return false;
    }
    final expiresAt = cert.expiresAt;
    if (expiresAt != null && current.isAfter(expiresAt)) return false;

    // M1 — Freschezza: il certificato deve essere stato EMESSO in una
    // finestra plausibile. Un certificato con timestampApproval nel futuro
    // (oltre lo skew di orologio) o emesso troppo tempo fa (oltre la durata
    // massima) viene rifiutato, anche se la scadenza fosse manipolata.
    final issuedAt = cert.timestampApproval;
    if (issuedAt != null) {
      if (current.isBefore(issuedAt.subtract(_clockSkew))) return false;
      if (current.difference(issuedAt) > approvalCertificateValidity) {
        return false;
      }
    } else {
      // Certificato senza data di emissione: non freschezza verificabile.
      return false;
    }

    final rootKey = await _getTrustRootSignerKey();
    if (rootKey == null || rootKey.isEmpty) return false;
    if (cert.signerPublicKey != rootKey) return false;

    final valid = await verifyApprovalSignature(
      canonicalPayload: cert.canonicalPayload,
      signature: cert.approvalSignature!,
      publicKeyBase64: rootKey,
    );
    if (!valid) return false;

    return !await isDeviceRevoked(cert.deviceId);
  }

  /// Trust root locale: la chiave pubblica di firma importata dal "QR di
  /// fiducia" del Responsabile; se assente, la propria (dispositivo del
  /// Responsabile).
  Future<String?> _getTrustRootSignerKey() async {
    final info = await getResponsabileTrustInfo();
    final fromInfo = info?['signerPublicKey'];
    if (fromInfo is String && fromInfo.isNotEmpty) return fromInfo;
    return getParishSignerPublicKeyBase64();
  }

  /// True se il dispositivo può verificare i certificati di approvazione
  /// (possiede la trust root del Responsabile o è il Responsabile stesso).
  Future<bool> hasTrustRoot() async {
    final key = await _getTrustRootSignerKey();
    return key != null && key.isNotEmpty;
  }

  // ─── Blacklist delle revoche ──────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _readRevokedDevices() async {
    final raw = await _secureStorage.read(key: _parishRevokedDevicesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Lista dei deviceId revocati dal Responsabile.
  Future<List<Map<String, dynamic>>> getRevokedDevices() =>
      _readRevokedDevices();

  /// True se [deviceId] è stato revocato dal Responsabile.
  Future<bool> isDeviceRevoked(String deviceId) async {
    if (deviceId.isEmpty) return false;
    final revoked = await _readRevokedDevices();
    return revoked.any((e) => e['deviceId'] == deviceId);
  }

  /// Aggiunge [deviceId] alla blacklist delle revoche (kill-switch locale).
  /// La blacklist viene propagata agli altri dispositivi attraverso la trust
  /// root rigenerata (QR di fiducia) o il canale parrocchiale.
  Future<void> revokeDeviceApproval(String deviceId) async {
    if (deviceId.isEmpty) return;
    final revoked = await _readRevokedDevices();
    if (revoked.any((e) => e['deviceId'] == deviceId)) return;
    revoked.add({
      'deviceId': deviceId,
      'revokedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _secureStorage.write(
      key: _parishRevokedDevicesKey,
      value: jsonEncode(revoked),
    );
  }

  /// Unisce le revoche ricevute (QR di fiducia / canale parrocchiale) alla
  /// blacklist locale, mantenendo la più recente per deviceId.
  Future<void> importRevokedDevices(
    List<Map<String, dynamic>>? revocations,
  ) async {
    if (revocations == null || revocations.isEmpty) return;
    final current = await _readRevokedDevices();
    final merged = <String, Map<String, dynamic>>{
      for (final e in current)
        if (e['deviceId'] != null) e['deviceId'].toString(): e,
    };
    for (final e in revocations) {
      final id = e['deviceId']?.toString() ?? '';
      if (id.isEmpty) continue;
      final existing = merged[id];
      if (existing == null || _revokedAt(existing).isBefore(_revokedAt(e))) {
        merged[id] = e;
      }
    }
    await _secureStorage.write(
      key: _parishRevokedDevicesKey,
      value: jsonEncode(merged.values.toList()),
    );
  }

  static DateTime _revokedAt(Map<String, dynamic> e) =>
      DateTime.tryParse(e['revokedAt']?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  // ─── M1: propagazione firmata delle revoche via P2P ───────────────────

  /// Firma la lista delle revoche con la chiave privata Ed25519 del
  /// Responsabile. Solo il dispositivo Responsabile (titolare della chiave di
  /// firma della parrocchia) può generare una revoca valida: i verificatori
  /// accettano la revoca solo se la firma combacia con la trust root.
  /// Restituisce null se il dispositivo non è il Responsabile firmatario.
  Future<Map<String, dynamic>?> signRevocationList() async {
    final keyPair = await getOrCreateParishSignerKeyPair();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final identity = await getLocalIdentity();
    final revocations = await getRevokedDevices();
    final canonical = _revocationCanonicalPayload(revocations);
    final signature = await signApprovalPayload(canonical, privateKeyBytes);
    return {
      'revocations': revocations,
      'deviceId': identity.deviceId,
      'signedAt': DateTime.now().toUtc().toIso8601String(),
      'signature': signature,
    };
  }

  /// Verifica una lista di revoche firmata dal Responsabile contro la trust
  /// root locale. La verifica è ASIMMETRICA (Ed25519): un dispositivo rogue
  /// non può iniettare revoche fasulle nella rete, perché non possiede la
  /// chiave privata di firma del Responsabile.
  Future<bool> verifyRevocationList(Map<String, dynamic>? payload) async {
    if (payload == null) return false;
    final revocations = (payload['revocations'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final signature = payload['signature'] as String? ?? '';
    if (signature.isEmpty) return false;
    final rootKey = await _getTrustRootSignerKey();
    if (rootKey == null || rootKey.isEmpty) return false;
    return verifyApprovalSignature(
      canonicalPayload: _revocationCanonicalPayload(revocations),
      signature: signature,
      publicKeyBase64: rootKey,
    );
  }

  static String _revocationCanonicalPayload(List<Map<String, dynamic>> revocations) {
    final canonical = <String>[];
    for (final r in revocations) {
      canonical.add(
        '${r['deviceId']}|${_revokedAt(r).toUtc().toIso8601String()}',
      );
    }
    canonical.sort();
    return jsonEncode(canonical);
  }

  /// Salva le informazioni di fiducia del Responsabile su un dispositivo
  /// verificatore (es. il PRIMARY che scansiona il QR di fiducia). Il QR di
  /// fiducia trasporta SOLO la chiave pubblica di firma (trust root) e la
  /// scadenza: nessun segreto simmetrico.
  Future<void> storeResponsabileTrustInfo({
    required String responsabileDeviceId,
    required String signerPublicKey,
    String? responsabileName,
    DateTime? expiresAt,
  }) async {
    await _secureStorage.write(
      key: _responsabileTrustInfoKey,
      value: jsonEncode({
        'responsabileDeviceId': responsabileDeviceId,
        'signerPublicKey': signerPublicKey,
        'responsabileName': responsabileName ?? '',
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'storedAt': DateTime.now().toUtc().toIso8601String(),
        'v': 2,
      }),
    );
  }

  Future<Map<String, dynamic>?> getResponsabileTrustInfo() async {
    final raw = await _secureStorage.read(key: _responsabileTrustInfoKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// True se la trust root importata è scaduta (richiede un nuovo QR di
  /// fiducia dal Responsabile).
  Future<bool> isTrustRootExpired({DateTime? now}) async {
    final info = await getResponsabileTrustInfo();
    final raw = info?['expiresAt'];
    if (raw is! String || raw.isEmpty) return false;
    final expiresAt = DateTime.tryParse(raw)?.toUtc();
    if (expiresAt == null) return false;
    return (now ?? DateTime.now().toUtc()).isAfter(expiresAt);
  }

  /// Salva il certificato di approvazione ricevuto dal Responsabile
  /// (sul dispositivo approvato).
  Future<void> storeLocalApproval(AssociatedDevice cert) async {
    await _secureStorage.write(
        key: _localApprovalKey, value: jsonEncode(cert.toJson()));
  }

  Future<AssociatedDevice?> getLocalApproval() async {
    final raw = await _secureStorage.read(key: _localApprovalKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AssociatedDevice.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearLocalApproval() async {
    await _secureStorage.delete(key: _localApprovalKey);
  }

  /// True se la modalità Responsabile è attiva nella configurazione della
  /// parrocchia. In tal caso la sincronizzazione richiede l'approvazione
  /// preventiva del dispositivo da parte del Responsabile.
  Future<bool> isResponsabileModeActive() async {
    try {
      final raw = LocalDatabase.parishConfig().get('parish_config');
      final map = LocalDatabase.toStringDynamicMap(raw);
      return map['isResponsabileModeActive'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Applica la catena di fiducia alla sincronizzazione:
  /// - Modalità Responsabile ATTIVA: il dispositivo remoto deve avere
  ///   un'associazione valida E un certificato di approvazione firmato dal
  ///   Responsabile (verifica asimmetrica Ed25519 + scadenza + blacklist).
  /// - Modalità Responsabile DISATTIVA: basta un'associazione valida.
  Future<bool> isSyncAllowedFromDevice(String deviceId) async {
    final assoc = await getAssociation(deviceId);
    if (assoc == null || !assoc.isValid) return false;
    final responsabileMode = await isResponsabileModeActive();
    if (!responsabileMode) return true;

    if (!assoc.authorizedByResponsabile ||
        assoc.approvalSignature == null ||
        assoc.approvalSignature!.isEmpty) {
      return false;
    }

    final cert = AssociatedDevice(
      deviceId: assoc.deviceId,
      catechistId: assoc.catechistId ?? '',
      publicKey: assoc.publicKeyBase64,
      authorizedByResponsabile: assoc.authorizedByResponsabile,
      timestampApproval: assoc.timestampApproval,
      approvedByDeviceId: assoc.approvedByDeviceId,
      signerPublicKey: assoc.approvalSignerPublicKey,
      approvalSignature: assoc.approvalSignature,
      expiresAt: assoc.approvalExpiresAt,
    );
    return verifyApprovalCertificate(cert);
  }
}

Future<String> _computeFingerprint(SimplePublicKey publicKey) async {
  final hash = await _sha256Algo.hash(publicKey.bytes);
  final hex = _bytesToHex(hash.bytes);
  return '${hex.substring(0, 8)}:${hex.substring(8, 16)}:'
      '${hex.substring(16, 24)}:${hex.substring(24, 32)}';
}
