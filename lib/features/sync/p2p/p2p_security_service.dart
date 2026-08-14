import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto show Hmac, sha256;
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
    bool clearApproval = false,
  }) {
    return P2PDeviceAssociation(
      deviceId: deviceId,
      deviceName: deviceName,
      publicKeyBase64: publicKeyBase64,
      fingerprint: fingerprint,
      sharedSecretBase64: sharedSecretBase64,
      associatedAt: associatedAt,
      devicePrivateKeyBase64: devicePrivateKeyBase64,
      devicePublicKeyBase64: devicePublicKeyBase64,
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
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'publicKey': publicKeyBase64,
        'fingerprint': fingerprint,
        'sharedSecret': sharedSecretBase64,
        'associatedAt': associatedAt.toUtc().toIso8601String(),
        'privKey': devicePrivateKeyBase64,
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
      };

  factory P2PDeviceAssociation.fromJson(Map<String, dynamic> json) =>
      P2PDeviceAssociation(
        deviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String? ?? '',
        publicKeyBase64: json['publicKey'] as String,
        fingerprint: json['fingerprint'] as String? ?? '',
        sharedSecretBase64: json['sharedSecret'] as String,
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
        debugPrint('P2PSecurityService.getOrCreateIdentityKeyPair: stored key corrupted, regenerating: $e');
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

  Future<P2PIdentity> getLocalIdentity() async {
    final stored = await _secureStorage.read(key: _localIdentityKey);
    if (stored != null && stored.isNotEmpty) {
      try {
        return P2PIdentity.fromJson(jsonDecode(stored) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('P2PSecurityService.getLocalIdentity: stored identity corrupted, regenerating: $e');
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
  }) async {
    Uint8List remoteKeyBytes;
    try {
      remoteKeyBytes = base64Decode(remotePublicKeyBase64);
    } catch (_) {
      throw FormatException('Chiave pubblica remota non valida: formato base64 errato in createEphemeralSession');
    }
    final identityKeyPair = await getOrCreateIdentityKeyPair();

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: identityKeyPair,
      remotePublicKey: SimplePublicKey(remoteKeyBytes, type: KeyPairType.x25519),
    );
    final sharedBytes = await sharedSecret.extractBytes();

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

  Future<void> saveAssociation(P2PDeviceAssociation association) async {
    await _assocBox.put(association.deviceId, association.toJson());
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
      if (!assoc.isValid) {
        await removeAssociation(deviceId);
        return null;
      }
      return assoc;
    } catch (e) {
      debugPrint('P2PSecurityService.getAssociation error for $deviceId: $e');
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
        if (assoc.isValid) {
          associations.add(assoc);
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
  static String computePairingCode(String sharedSecretBase64, {String? sessionNonce}) {
    final secretBytes = base64Decode(sharedSecretBase64);
    final combined = sessionNonce != null
        ? crypto.sha256.convert(utf8.encode(sessionNonce)).bytes + secretBytes
        : secretBytes;
    final hash = crypto.sha256.convert(combined);
    final code = ((hash.bytes[0] << 16) | (hash.bytes[1] << 8) | hash.bytes[2]) % 1000000;
    return code.toString().padLeft(6, '0');
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
  // del Responsabile. L'approvazione è un certificato firmato con HMAC-SHA256
  // (segreto del Responsabile). Il segreto viene distribuito una sola volta al
  // dispositivo che funge da PRIMARY tramite il "QR di fiducia" del
  // Responsabile; gli altri dispositivi verificano il certificato ricevuto.

  static const _parishApprovalSecretKey = 'parish_approval_secret';
  static const _responsabileTrustInfoKey = 'responsabile_trust_info';
  static const _localApprovalKey = 'local_device_approval';

  Future<String?> getParishApprovalSecret() =>
      _secureStorage.read(key: _parishApprovalSecretKey);

  /// Genera (e memorizza) il segreto di approvazione della parrocchia.
  /// Chiamato dal dispositivo del Responsabile alla prima approvazione.
  Future<String> getOrCreateParishApprovalSecret() async {
    final existing = await getParishApprovalSecret();
    if (existing != null && existing.isNotEmpty) return existing;
    final secret = base64Encode(secureRandom(32));
    await _secureStorage.write(
        key: _parishApprovalSecretKey, value: secret);
    return secret;
  }

  Future<bool> hasParishApprovalSecret() async =>
      (await getParishApprovalSecret())?.isNotEmpty ?? false;

  /// Firma un certificato di approvazione per un nuovo dispositivo.
  /// Il segreto viene creato alla prima chiamata. Usato dal dispositivo
  /// del Responsabile per approvare (via QR o scambio P2P diretto) i
  /// dispositivi autorizzati a sincronizzare le classi.
  Future<AssociatedDevice> signDeviceApproval({
    required String deviceId,
    required String catechistId,
    required String publicKeyBase64,
    String? deviceName,
  }) async {
    final secret = await getOrCreateParishApprovalSecret();
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
      signerPublicKey: identity.publicKeyBase64,
    );
    final signature = _signApprovalCertificate(certificate, secret);
    return certificate.copyWith(approvalSignature: signature);
  }

  static String _signApprovalCertificate(
      AssociatedDevice cert, String secret) {
    return signApprovalPayload(cert.canonicalPayload, secret);
  }

  /// Firma HMAC-SHA256 (base64) di un payload canonico con [secret].
  /// Esposto staticamente per essere testabile senza secure storage.
  static String signApprovalPayload(String canonicalPayload, String secret) {
    final mac = crypto.Hmac(crypto.sha256, utf8.encode(secret));
    return base64Encode(mac.convert(utf8.encode(canonicalPayload)).bytes);
  }

  /// Verifica (tempo-costante) una firma HMAC-SHA256 di un payload canonico.
  static bool verifyApprovalSignature({
    required String canonicalPayload,
    required String signature,
    required String secret,
  }) {
    if (signature.isEmpty || secret.isEmpty) return false;
    return _constantTimeEquals(
      signApprovalPayload(canonicalPayload, secret),
      signature,
    );
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Verifica il certificato di approvazione usando il segreto del
  /// Responsabile. Richiede che il dispositivo possieda il segreto (es.
  /// il dispositivo primario che ha scansionato il QR di fiducia).
  Future<bool> verifyApprovalWithParishSecret(
      AssociatedDevice cert) async {
    if (!cert.authorizedByResponsabile ||
        cert.approvalSignature == null ||
        cert.approvalSignature!.isEmpty) {
      return false;
    }
    final secret = await getParishApprovalSecret();
    if (secret == null || secret.isEmpty) return false;
    final expected = _signApprovalCertificate(cert, secret);
    return _constantTimeEquals(expected, cert.approvalSignature!);
  }

  /// Salva le informazioni di fiducia del Responsabile su un dispositivo
  /// verificatore (es. il PRIMARY che scansiona il QR di fiducia).
  Future<void> storeResponsabileTrustInfo({
    required String responsabileDeviceId,
    required String approvalSecret,
    String? responsabileName,
  }) async {
    await _secureStorage.write(
      key: _responsabileTrustInfoKey,
      value: jsonEncode({
        'responsabileDeviceId': responsabileDeviceId,
        'approvalSecret': approvalSecret,
        'responsabileName': responsabileName ?? '',
        'storedAt': DateTime.now().toUtc().toIso8601String(),
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
  ///   Responsabile (verificato con il segreto locale, se presente).
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
    );
    return verifyApprovalWithParishSecret(cert);
  }
}

Future<String> _computeFingerprint(SimplePublicKey publicKey) async {
  final hash = await _sha256Algo.hash(publicKey.bytes);
  final hex = _bytesToHex(hash.bytes);
  return '${hex.substring(0, 8)}:${hex.substring(8, 16)}:'
      '${hex.substring(16, 24)}:${hex.substring(24, 32)}';
}
