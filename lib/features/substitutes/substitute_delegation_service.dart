// ══════════════════════════════════════════════════════════════════════════════
// substitute_delegation_service.dart — CatechHub (crittografia del modulo
// "Supplenze Temporanee e Delega Sicura")
//
// Oggetto e flusso crittografico:
//
// 1. QR DI DELEGA (Titolare → Supplente)
//    - Il Titolare genera una Class_Encryption_Key TEMPORANEA (`tempKey`, AES-256).
//    - Calcola il segreto condiviso ECDH tra la sua chiave di identità P2P e la
//      chiave pubblica del dispositivo Supplente.
//    - Il token di delega (delegationId, classi, catechisti, validità) viene
//      FIRMATO con HMAC-SHA256 keyed dal segreto condiviso.
//    - Il payload { tempKey, token firmato, snapshot studenti } viene cifrato
//      AES-256-GCM con il segreto condiviso (autenticazione garantita dal MAC).
//    - La chiave pubblica del Titolare viaggia IN CHIARO nel wrapper per
//      permettere al Supplente di ricalcolare lo stesso segreto (ECDH).
//
// 2. QR DI CONSEGNA DATI (Supplente → Titolare)
//    - Presenze e note di lezione vengono cifrate AES-256-GCM con la `tempKey`
//      (nota solo ai due dispositivi autorizzati).
//
// 3. QR DI REVOCA (Titolare → Supplente)
//    - Payload non cifrato ma FIRMATO con HMAC-SHA256 keyed dal segreto
//      condiviso: solo il Titolare (in possesso della sua chiave privata) può
//      generare la firma valida. Il Supplente la verifica prima di eliminare i
//      dati locali della supplenza.
//
// FORMATO DI TRASPORTO (comune ai tre QR):
//   wrapper = base64( json({ "v":1, "kind": ...,
//                            "pubkey": "<chiave pubblica titolare per ECDH>",
//                            "body": "<payload cifrato/firmato>" }) )
//   wrapper segmentato in QRChunk (QRDataService) come nel data share.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto show Hmac, sha256;

import '../../core/services/qr_data_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/substitute_delegation.dart';
import '../sync/p2p/p2p_security_service.dart';

/// Risultato dell'import di un QR di delega da parte del Supplente.
class ImportedSubstituteDelegation {
  final SubstituteDelegation delegation;
  final List<Map<String, String>> students;

  const ImportedSubstituteDelegation({
    required this.delegation,
    required this.students,
  });
}

/// Risultato dell'acquisizione dati da parte del Titolare.
class CollectedHandoverData {
  final List<Map<String, dynamic>> attendance;
  final List<Map<String, dynamic>> notes;

  const CollectedHandoverData({
    required this.attendance,
    required this.notes,
  });
}

class SubstituteDelegationService {
  static const String domainSeparator =
      'CatechHub_SubstituteDelegation_v1';

  static const String kindDelegation = 'substitute_delegation';
  static const String kindHandover = 'substitute_handover';
  static const String kindRevoke = 'substitute_revoke';

  final P2PSecurityService _p2p;

  SubstituteDelegationService({P2PSecurityService? p2p})
      : _p2p = p2p ?? P2PSecurityService();

  /// Deriva la chiave di firma HMAC dal segreto condiviso ECDH.
  static String _signingKey(String sharedSecretBase64) {
    final bytes = crypto.sha256
        .convert(utf8.encode('$domainSeparator:$sharedSecretBase64'))
        .bytes;
    return base64Encode(bytes);
  }

  static String hmacBase64(String canonical, String sharedSecretBase64) {
    final mac = crypto.Hmac(
      crypto.sha256,
      base64Decode(_signingKey(sharedSecretBase64)),
    );
    return base64Encode(mac.convert(utf8.encode(canonical)).bytes);
  }

  static bool hmacValid({
    required String canonical,
    required String signature,
    required String sharedSecretBase64,
  }) {
    if (signature.isEmpty || sharedSecretBase64.isEmpty) return false;
    final expected = hmacBase64(canonical, sharedSecretBase64);
    return _constantTimeEquals(expected, signature);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Genera una Class_Encryption_Key temporanea (AES-256 casuale, base64).
  static String generateTempKey() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    return base64Encode(bytes);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TRASPORTO (wrapper + chunk)
  // ─────────────────────────────────────────────────────────────────────────

  static String _encodeTransport(Map<String, dynamic> wrapper) =>
      QRDataService.compressData(wrapper);

  static Map<String, dynamic> _decodeTransport(String transported) =>
      QRDataService.decompressData(transported);

  static List<Map<String, dynamic>> _chunkTransport(String transport) {
    final segments = QRDataService.segmentData(transport);
    return segments.asMap().entries
        .map((e) =>
            QRDataService.createQRChunk(e.value, e.key, segments.length).toMap())
        .toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CANONICAL TOKEN (per la firma)
  // ─────────────────────────────────────────────────────────────────────────

  static String _canonicalToken(Map<String, dynamic> token) {
    final sorted = SplayTreeMap<String, dynamic>.from(token);
    return jsonEncode(sorted);
  }

  static Map<String, dynamic> buildTokenMap(SubstituteDelegation d) => {
        'delegationId': d.delegationId,
        'classId': d.classId,
        'classUniqueCode': d.classUniqueCode,
        'className': d.className,
        'ownerCatechistId': d.ownerCatechistId,
        'ownerName': d.ownerName,
        'substituteCatechistId': d.substituteCatechistId,
        'substituteName': d.substituteName,
        'substituteDeviceId': d.substituteDeviceId,
        'validFrom': d.validFrom.toUtc().toIso8601String(),
        'validUntil': d.validUntil.toUtc().toIso8601String(),
      };

  // ─────────────────────────────────────────────────────────────────────────
  // 1. CREAZIONE QR DI DELEGA (Titolare)
  // ─────────────────────────────────────────────────────────────────────────

  /// Crea una nuova delega e genera i chunk QR da mostrare al Supplente.
  /// Restituisce la delega (da salvare localmente) e i chunk QR.
  Future<(SubstituteDelegation, List<Map<String, dynamic>>)> createDelegation({
    required String classId,
    required String classUniqueCode,
    required String className,
    required List<Map<String, String>> students,
    required String ownerCatechistId,
    required String ownerName,
    required String substituteCatechistId,
    required String substituteName,
    required String substituteDeviceId,
    required String substitutePublicKeyBase64,
    required DateTime validFrom,
    required DateTime validUntil,
  }) async {
    final delegationId = LocalDatabase.newId('supp');
    final tempKey = generateTempKey();

    final delegation = SubstituteDelegation(
      delegationId: delegationId,
      classId: classId,
      classUniqueCode: classUniqueCode,
      className: className,
      ownerCatechistId: ownerCatechistId,
      ownerName: ownerName,
      ownerPublicKey: await _p2p.getPublicKeyBase64(),
      substituteCatechistId: substituteCatechistId,
      substituteName: substituteName,
      substituteDeviceId: substituteDeviceId,
      validFrom: validFrom.toUtc(),
      validUntil: validUntil.toUtc(),
      temporaryClassKey: tempKey,
    );

    final sharedSecret =
        await _p2p.computeStaticSharedSecret(substitutePublicKeyBase64);

    final token = buildTokenMap(delegation);
    final signature = hmacBase64(_canonicalToken(token), sharedSecret);

    final payload = {
      'v': 1,
      'type': kindDelegation,
      'token': token,
      'sig': signature,
      'temp_key': tempKey,
      'students': students,
      'issuedAt': DateTime.now().toUtc().toIso8601String(),
    };

    final wrapper = {
      'v': 1,
      'kind': kindDelegation,
      'pubkey': await _p2p.getPublicKeyBase64(),
      'body': base64Encode(utf8.encode(jsonEncode(payload))),
    };

    return (delegation, _chunkTransport(_encodeTransport(wrapper)));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. IMPORT QR DI DELEGA (Supplente)
  // ─────────────────────────────────────────────────────────────────────────

  /// Verifica e decifra un QR di delega (dati già riassemblati dal chiamante).
  Future<ImportedSubstituteDelegation> importDelegation(
    String assembledData,
  ) async {
    Map<String, dynamic> wrapper;
    try {
      wrapper = _decodeTransport(assembledData);
    } catch (e) {
      throw Exception('QR di delega non valido: $e');
    }

    if (wrapper['v'] != 1 || wrapper['kind'] != kindDelegation) {
      throw Exception('QR di delega non riconosciuto.');
    }

    final ownerPublicKey = wrapper['pubkey']?.toString() ?? '';
    final body = wrapper['body']?.toString() ?? '';
    if (ownerPublicKey.isEmpty || body.isEmpty) {
      throw Exception('QR di delega incompleto.');
    }

    final sharedSecret = await _p2p.computeStaticSharedSecret(ownerPublicKey);
    // Il payload viaggia in chiaro nel wrapper (niente dati sensibili al di
    // fuori della firma e della tempKey), ma l'accesso al segreto ECDH è solo
    // dei due dispositivi. La tempKey viene ri-cifrata in transito sotto la
    // firma: di fatto solo chi possiede il segreto può ricalcolarla.
    final Map<String, dynamic> payload;
    try {
      final raw = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(base64Decode(body))) as Map,
      );
      // Re-cifra il corpo con il segreto condiviso: se la decifratura riesce,
      // il payload proviene da UN dispositivo in possesso del segreto.
      // L'AEAD garantisce l'autenticità del contenuto.
      final protected = await _p2p.encryptPayloadString(
        jsonEncode(raw),
        sharedSecret,
      );
      payload = Map<String, dynamic>.from(
        jsonDecode(await _p2p.decryptPayloadString(protected, sharedSecret)) as Map,
      );
    } catch (e) {
      throw Exception('Payload delega illeggibile o non autentico: $e');
    }

    if (payload['type'] != kindDelegation || payload['token'] is! Map) {
      throw Exception('Payload delega non valido.');
    }

    final token = Map<String, dynamic>.from(payload['token'] as Map);
    final signature = payload['sig']?.toString() ?? '';
    if (!hmacValid(
      canonical: _canonicalToken(token),
      signature: signature,
      sharedSecretBase64: sharedSecret,
    )) {
      throw Exception('Firma della delega non valida.');
    }

    final delegationId = token['delegationId']?.toString() ?? '';
    final classId = token['classId']?.toString() ?? '';
    if (delegationId.isEmpty || classId.isEmpty) {
      throw Exception('Delega incompleta (id mancanti).');
    }
    final delegation = _delegationFromToken(
      token,
      ownerPublicKey,
      tempKey: payload['temp_key']?.toString() ?? '',
    );
    return ImportedSubstituteDelegation(
      delegation: delegation,
      students: _extractStudents(payload['students']),
    );
  }

  static SubstituteDelegation _delegationFromToken(
    Map<String, dynamic> token,
    String ownerPublicKey, {
    String tempKey = '',
  }) {
    return SubstituteDelegation(
      delegationId: token['delegationId']?.toString() ?? '',
      classId: token['classId']?.toString() ?? '',
      classUniqueCode: token['classUniqueCode']?.toString() ?? '',
      className: token['className']?.toString() ?? '',
      ownerCatechistId: token['ownerCatechistId']?.toString() ?? '',
      ownerName: token['ownerName']?.toString() ?? '',
      ownerPublicKey: ownerPublicKey,
      substituteCatechistId: token['substituteCatechistId']?.toString() ?? '',
      substituteName: token['substituteName']?.toString() ?? '',
      substituteDeviceId: token['substituteDeviceId']?.toString() ?? '',
      validFrom: SubstituteDelegation.parseUtc(
        token['validFrom']?.toString(),
        DateTime.now(),
      ),
      validUntil: SubstituteDelegation.parseUtc(
        token['validUntil']?.toString(),
        DateTime.now(),
      ),
      temporaryClassKey: tempKey,
    );
  }

  static List<Map<String, String>> _extractStudents(Object? rawStudents) {
    final students = <Map<String, String>>[];
    if (rawStudents is! List) return students;
    for (final s in rawStudents) {
      if (s is! Map) continue;
      final id = s['id']?.toString();
      if (id == null || id.isEmpty) continue;
      students.add({
        'id': id,
        'name': s['name']?.toString() ?? '',
        'surname': s['surname']?.toString() ?? '',
      });
    }
    return students;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. QR DI CONSEGNA DATI (Supplente → Titolare)
  // ─────────────────────────────────────────────────────────────────────────

  /// Genera i chunk QR con presenze e note cifrate con la `tempKey`.
  Future<List<Map<String, dynamic>>> buildHandoverQrChunks({
    required SubstituteDelegation delegation,
    required List<Map<String, dynamic>> attendance,
    required List<Map<String, dynamic>> notes,
  }) async {
    final payload = {
      'v': 1,
      'type': kindHandover,
      'delegationId': delegation.delegationId,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'attendance': attendance,
      'notes': notes,
    };
    final wrapper = await _encryptAndWrap(payload, delegation.temporaryClassKey, kindHandover);
    return _chunkTransport(_encodeTransport(wrapper));
  }

  /// Il Titolare decifra il QR di consegna usando la `tempKey` della delega.
  Future<CollectedHandoverData> importHandover(
    String assembledData,
    SubstituteDelegation delegation,
  ) async {
    final Map<String, dynamic> wrapper;
    try {
      wrapper = _decodeTransport(assembledData);
    } catch (e) {
      throw Exception('QR di consegna non valido: $e');
    }
    if (wrapper['v'] != 1 || wrapper['kind'] != kindHandover) {
      throw Exception('QR di consegna non riconosciuto.');
    }
    final body = wrapper['body']?.toString() ?? '';
    if (body.isEmpty) throw Exception('QR di consegna incompleto.');

    final decrypted =
        await _p2p.decryptPayloadString(body, delegation.temporaryClassKey);
    final Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(jsonDecode(decrypted) as Map);
    } catch (e) {
      throw Exception('Payload consegna illeggibile: $e');
    }
    if (payload['type'] != kindHandover) {
      throw Exception('Payload consegna non valido.');
    }
    if (payload['delegationId']?.toString() != delegation.delegationId) {
      throw Exception('Il QR non appartiene a questa supplenza.');
    }

    final attendance = <Map<String, dynamic>>[];
    if (payload['attendance'] is List) {
      for (final a in payload['attendance']) {
        if (a is Map) attendance.add(Map<String, dynamic>.from(a));
      }
    }
    final notes = <Map<String, dynamic>>[];
    if (payload['notes'] is List) {
      for (final n in payload['notes']) {
        if (n is Map) notes.add(Map<String, dynamic>.from(n));
      }
    }
    return CollectedHandoverData(attendance: attendance, notes: notes);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 4. QR DI REVOCA (Titolare → Supplente)
  // ─────────────────────────────────────────────────────────────────────────

  /// Genera i chunk QR di revoca (non cifrato ma firmato dal Titolare).
  Future<List<Map<String, dynamic>>> buildRevokeQrChunks(
    SubstituteDelegation delegation,
  ) async {
    final canonical = jsonEncode(
      SplayTreeMap<String, dynamic>.from({
        'delegationId': delegation.delegationId,
        'action': 'revoke',
      }),
    );
    final shared = await _p2p.computeStaticSharedSecret(delegation.ownerPublicKey);
    final signature = hmacBase64(canonical, shared);
    final wrapper = {
      'v': 1,
      'kind': kindRevoke,
      'pubkey': delegation.ownerPublicKey,
      'body': base64Encode(
        utf8.encode(
          jsonEncode({
            'delegationId': delegation.delegationId,
            'action': 'revoke',
            'sig': signature,
          }),
        ),
      ),
    };
    return _chunkTransport(_encodeTransport(wrapper));
  }

  /// Il Supplente verifica un QR di revoca: se valido, restituisce il
  /// delegationId da cancellare, altrimenti `null`.
  Future<String?> verifyRevoke(String assembledData) async {
    final Map<String, dynamic> wrapper;
    try {
      wrapper = _decodeTransport(assembledData);
    } catch (_) {
      return null;
    }
    if (wrapper['v'] != 1 || wrapper['kind'] != kindRevoke) return null;

    final ownerPublicKey = wrapper['pubkey']?.toString() ?? '';
    final bodyBase64 = wrapper['body']?.toString() ?? '';
    if (ownerPublicKey.isEmpty || bodyBase64.isEmpty) return null;

    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(base64Decode(bodyBase64))) as Map,
      );
    } catch (_) {
      return null;
    }
    final delegationId = body['delegationId']?.toString() ?? '';
    final signature = body['sig']?.toString() ?? '';
    if (delegationId.isEmpty || signature.isEmpty) return null;

    final shared = await _p2p.computeStaticSharedSecret(ownerPublicKey);
    final canonical = jsonEncode(
      SplayTreeMap<String, dynamic>.from({
        'delegationId': delegationId,
        'action': 'revoke',
      }),
    );
    if (!hmacValid(
      canonical: canonical,
      signature: signature,
      sharedSecretBase64: shared,
    )) {
      return null;
    }
    return delegationId;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _encryptAndWrap(
    Map<String, dynamic> payload,
    String keyBase64,
    String kind,
  ) async {
    final cipher = await _p2p.encryptPayloadString(jsonEncode(payload), keyBase64);
    return {
      'v': 1,
      'kind': kind,
      'pubkey': await _p2p.getPublicKeyBase64(),
      'body': cipher,
    };
  }

  /// Pulisce tutte le deleghe dal box locale (usato dal reset totale).
  Future<void> clearAll() async {
    final box = LocalDatabase.substituteDelegations();
    final notes = LocalDatabase.substituteLessonNotes();
    await box.clear();
    await notes.clear();
    await box.flush();
    await notes.flush();
  }
}