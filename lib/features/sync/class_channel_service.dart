// ══════════════════════════════════════════════════════════════════════════════
// class_channel_service.dart — CatechHub (Canale Classe: chiavi e cifratura)
//
// Modulo "Rete Catechistica Parrocchiale". Gestisce la Class_Encryption_Key
// per ogni classe e la cifratura/decifratura dei payload di classe nel sync P2P.
//
// PRINCIPIO (Isolamento Dati):
//   - I dati di classe viaggiano SEMPRE cifrati AES-256-GCM con la chiave
//     per-classe. Un dispositivo "Senza Titolo" che non possiede la chiave
//     riceve i blob come opachi (relay) e NON può leggerli.
//   - Il titolo viene esteso dal Responsabile/Catechista Titolare tramite
//     QR handshake (createKeyGrant → QR) o bootstrap in-band durante il sync
//     per i membri riconosciuti della classe.
//
// FORMATO BLOB CIFRATO:
//   { "v": 1, "keyId": "<sha256 della chiave>", "sealed": "<base64 nonce||ct||tag>" }
//   Il payload in chiaro è il JSON dei record serializzati (SyncRecord[]).
//
// DIPENDENZE:
//   - cryptography: AES-256-GCM + SHA-256 in Dart puro (testabile su VM).
//   - QRDataService: confezionamento del grant con PIN (come il data share).
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:hive/hive.dart';

import '../../core/services/qr_data_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/class_channel_key.dart';

class ClassChannelService {
  ClassChannelService._();

  /// OVERRIDE SOLO PER TEST: chiave derivata deterministicamente.
  static String? debugSeedOverride;

  /// Genera una chiave AES-256 (32 byte) casuale.
  static String generateKeyBase64() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    return base64Encode(bytes);
  }

  static Future<Uint8List> _sha256(List<int> input) async {
    final hash = await Sha256().hash(input);
    return Uint8List.fromList(hash.bytes);
  }

  /// Fingerprint della chiave (primi 16 esadecimali dello SHA-256).
  static Future<String> computeKeyId(String keyBase64) async {
    final hash = await _sha256(base64Decode(keyBase64));
    return hash
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .substring(0, 16);
  }

  static Uint8List _secureBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Future<Uint8List> _classKeyBytes(String keyBase64) async {
    // L'override di test è ammesso SOLO in debug: in release un downgrade a
    // chiavi deterministiche sarebbe un backdoor.
    final seed = kDebugMode ? debugSeedOverride : null;
    if (seed != null) {
      return _sha256(utf8.encode('$seed:$keyBase64'));
    }
    return Uint8List.fromList(base64Decode(keyBase64));
  }

  /// AAD di contesto: vincola ogni ciphertext alla classe a cui appartiene.
  /// Impedisce la sostituzione di un blob cifrato con uno di un'altra classe
  /// (ciphertext substitution) anche in presenza di chiavi coincidenti.
  static Uint8List _aadContext(String classUniqueCode) {
    return Uint8List.fromList(
      utf8.encode('CatechHub_ClassChannel_v1:$classUniqueCode'),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHIAVI E TITOLO
  // ─────────────────────────────────────────────────────────────────────────

  static Box<Map> get _keysBox => LocalDatabase.classChannelKeys();
  static Box<Map> get _ciphertextBox => LocalDatabase.classChannelCiphertext();

  /// Restituisce la chiave per [classId], se questo dispositivo ha titolo.
  static ClassChannelKey? getKeyByClassId(String classId) {
    try {
      final raw = _keysBox.get(classId);
      if (raw == null) return null;
      final key = ClassChannelKey.fromMap(
        classId,
        LocalDatabase.toStringDynamicMap(raw),
      );
      return key.isActive ? key : null;
    } catch (_) {
      return null;
    }
  }

  /// Restituisce la chiave per [classUniqueCode] (ricerca per valore).
  static ClassChannelKey? getKeyByUniqueCode(String classUniqueCode) {
    if (classUniqueCode.isEmpty) return null;
    try {
      for (final entry in _keysBox.toMap().entries) {
        final key = ClassChannelKey.fromMap(
          entry.key,
          LocalDatabase.toStringDynamicMap(
            Map<String, dynamic>.from(entry.value),
          ),
        );
        if (key.isActive && key.classUniqueCode == classUniqueCode) {
          return key;
        }
      }
    } catch (_) {}
    return null;
  }

  /// true se questo dispositivo possiede una chiave attiva per la classe.
  static bool hasTitle(String classUniqueCode) =>
      getKeyByUniqueCode(classUniqueCode) != null;

  /// Crea (o restituisce) la chiave della classe [classId]. Da usare SOLO
  /// quando il dispositivo è autorizzato (Titolare/Responsabile/membro).
  static Future<ClassChannelKey> getOrCreateKey({
    required String classId,
    required String classUniqueCode,
    required String className,
    String grantorCatechistId = '',
  }) async {
    final existing = getKeyByClassId(classId);
    if (existing != null) return existing;

    final keyBase64 = generateKeyBase64();
    final key = ClassChannelKey(
      classId: classId,
      classUniqueCode: classUniqueCode,
      className: className,
      keyBase64: keyBase64,
      keyId: await computeKeyId(keyBase64),
      grantorCatechistId: grantorCatechistId,
      grantedAt: DateTime.now().toUtc(),
    );
    _keysBox.put(classId, key.toMap());
    return key;
  }

  /// Salva una chiave ricevuta (bootstrap in-band o import QR).
  /// Ritorna la chiave salvata, o null se già presente una chiave attiva.
  static Future<ClassChannelKey?> storeKey({
    required String classId,
    required String classUniqueCode,
    required String className,
    required String keyBase64,
    String grantorCatechistId = '',
  }) async {
    if (keyBase64.isEmpty) return null;
    final existing = getKeyByClassId(classId);
    if (existing != null && existing.keyId == await computeKeyId(keyBase64)) {
      return existing;
    }
    final key = ClassChannelKey(
      classId: classId,
      classUniqueCode: classUniqueCode,
      className: className,
      keyBase64: keyBase64,
      keyId: await computeKeyId(keyBase64),
      grantorCatechistId: grantorCatechistId,
      grantedAt: DateTime.now().toUtc(),
    );
    _keysBox.put(classId, key.toMap());
    return key;
  }

  /// Revoca il titolo locale per la classe [classId] (la chiave resta ma
  /// marcata inattiva). I dati cifrati con la vecchia chiave non saranno più
  /// leggibili dai nuovi payload (la chiave verrà ruotata dal Titolare).
  static void revokeTitle(String classId) {
    final raw = _keysBox.get(classId);
    if (raw == null) return;
    final key = ClassChannelKey.fromMap(
      classId,
      LocalDatabase.toStringDynamicMap(raw),
    );
    _keysBox.put(classId, key.copyWith(isActive: false).toMap());
  }

  /// Ruota la chiave della classe (nuova chiave casuale). Usata dopo una
  /// revoca per invalidare i titoli concessi in precedenza.
  static Future<ClassChannelKey> rotateKey({
    required String classId,
    required String classUniqueCode,
    required String className,
    String grantorCatechistId = '',
  }) async {
    final keyBase64 = generateKeyBase64();
    final key = ClassChannelKey(
      classId: classId,
      classUniqueCode: classUniqueCode,
      className: className,
      keyBase64: keyBase64,
      keyId: await computeKeyId(keyBase64),
      grantorCatechistId: grantorCatechistId,
      grantedAt: DateTime.now().toUtc(),
    );
    _keysBox.put(classId, key.toMap());
    return key;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CIFRATURA / DECIFRATURA DEI RECORD DI CLASSE
  // ─────────────────────────────────────────────────────────────────────────

  /// Cifra i record serializzati della classe [classUniqueCode].
  /// Ritorna il blob opaco da trasmettere nella rete P2P.
  static Future<Map<String, dynamic>?> encryptRecords(
    String classUniqueCode,
    List<Map<String, dynamic>> records,
  ) async {
    if (records.isEmpty) return null;
    final key = getKeyByUniqueCode(classUniqueCode);
    if (key == null) return null;

    final plain = utf8.encode(jsonEncode(records));
    final keyBytes = await _classKeyBytes(key.keyBase64);
    final nonce = _secureBytes(12);

    // AAD di contesto: lega il ciphertext alla classe di provenienza.
    // Impedisce la sostituzione/cross-class di un blob cifrato.
    final aad = _aadContext(classUniqueCode);

    final box = await AesGcm.with256bits().encrypt(
      plain,
      secretKey: SecretKey(keyBytes),
      nonce: nonce,
      aad: aad,
    );
    // Formato sealed = nonce || ct || tag (identico al vecchio output GCM).
    final sealed = box.concatenation();

    return {'v': 1, 'keyId': key.keyId, 'sealed': base64Encode(sealed)};
  }

  /// Decifra un blob prodotto da [encryptRecords]. Ritorna i record in chiaro
  /// o `null` se la chiave non è disponibile o la decifratura fallisce.
  static Future<List<Map<String, dynamic>>?> decryptRecords(
    String classUniqueCode,
    Map<String, dynamic> blob,
  ) async {
    final key = getKeyByUniqueCode(classUniqueCode);
    if (key == null) return null;

    final expectedKeyId = blob['keyId']?.toString();
    if (expectedKeyId != null &&
        expectedKeyId.isNotEmpty &&
        expectedKeyId != key.keyId) {
      return null;
    }

    final sealedBase64 = blob['sealed']?.toString();
    if (sealedBase64 == null || sealedBase64.isEmpty) return null;
    try {
      final sealed = base64Decode(sealedBase64);
      if (sealed.length < 12 + 16) return null;
      final keyBytes = await _classKeyBytes(key.keyBase64);

      final aad = _aadContext(classUniqueCode);

      final box = SecretBox.fromConcatenation(
        sealed,
        nonceLength: 12,
        macLength: 16,
      );
      final plain = utf8.decode(
        await AesGcm.with256bits().decrypt(
          box,
          secretKey: SecretKey(keyBytes),
          aad: aad,
        ),
      );
      final decoded = jsonDecode(plain);
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RELAY: BLOB CIFRATI RICEVUTI SENZA TITOLO
  // ─────────────────────────────────────────────────────────────────────────

  /// Conserva un blob cifrato di una classe senza titolo (relay). Se in
  /// seguito si ottiene il titolo, il blob potrà essere decifrato.
  static void storeRelayedCiphertext(
    String classUniqueCode,
    Map<String, dynamic> blob,
  ) {
    if (classUniqueCode.isEmpty) return;
    final existing = _ciphertextBox.get(classUniqueCode);
    final existingMap = existing is Map
        ? LocalDatabase.toStringDynamicMap(existing)
        : const <String, dynamic>{};
    final incomingTs =
        blob['receivedAt']?.toString() ??
        DateTime.now().toUtc().toIso8601String();
    if (existingMap.isNotEmpty &&
        (existingMap['updatedAt']?.toString() ?? '').compareTo(incomingTs) >
            0) {
      return;
    }
    _ciphertextBox.put(classUniqueCode, {
      'updatedAt': incomingTs,
      'receivedAt': DateTime.now().toUtc().toIso8601String(),
      'blob': blob,
    });
  }

  /// Restituisce (e rimuove) il blob relayed della classe, se presente.
  static Map<String, dynamic>? takeRelayedCiphertext(String classUniqueCode) {
    final raw = _ciphertextBox.get(classUniqueCode);
    if (raw == null) return null;
    _ciphertextBox.delete(classUniqueCode);
    final map = LocalDatabase.toStringDynamicMap(raw);
    final blob = map['blob'];
    return blob is Map ? Map<String, dynamic>.from(blob) : null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // QR HANDshake: CONCESSIONE DEL TITOLO
  // ─────────────────────────────────────────────────────────────────────────

  /// Costruisce la mappa grant da mostrare come QR code. Il grant è la chiave
  /// della classe cifrata dal PIN scelto (vedi QRDataService.createPackage).
  static Map<String, dynamic> buildGrantMap({
    required ClassChannelKey key,
    required String grantorName,
  }) {
    return {
      'v': 1,
      'type': 'class_key_grant',
      'classId': key.classId,
      'classUniqueCode': key.classUniqueCode,
      'className': key.className,
      'keyBase64': key.keyBase64,
      'keyId': key.keyId,
      'grantorName': grantorName,
      'issuedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Confeziona il grant in un DataPackage cifrato dal [pin] e lo segmenta
  /// in chunk QR (riusando il flusso del data share).
  static Future<List<Map<String, dynamic>>> createKeyGrantChunks(
    Map<String, dynamic> grantMap,
    String pin,
  ) async {
    final package = await QRDataService.createPackage(grantMap, pin);
    final compressed = QRDataService.compressData(package.toMap());
    final segments = QRDataService.segmentData(compressed);
    return segments
        .asMap()
        .entries
        .map(
          (e) => QRDataService.createQRChunk(
            e.value,
            e.key,
            segments.length,
          ).toMap(),
        )
        .toList();
  }

  /// Importa un grant dal [assembledData] (dati QR assemblati) verificando il
  /// [pin]. Ritorna la chiave salvata o `null` se il grant è scaduto/invalido.
  static Future<ClassChannelKey?> importKeyGrant(
    String assembledData,
    String pin,
  ) async {
    final payload = await QRDataService.extractPackageData(assembledData, pin);
    if (payload['type'] != 'class_key_grant') return null;
    final classId = payload['classId']?.toString() ?? '';
    final classUniqueCode = payload['classUniqueCode']?.toString() ?? '';
    final keyBase64 = payload['keyBase64']?.toString() ?? '';
    if (classId.isEmpty || classUniqueCode.isEmpty || keyBase64.isEmpty) {
      return null;
    }
    return storeKey(
      classId: classId,
      classUniqueCode: classUniqueCode,
      className: payload['className']?.toString() ?? '',
      keyBase64: keyBase64,
      grantorCatechistId: payload['grantorName']?.toString() ?? '',
    );
  }
}
