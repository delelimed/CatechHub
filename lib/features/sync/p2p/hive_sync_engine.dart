import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:hive/hive.dart';

import '../../../core/storage/local_database.dart';
import '../crdt/sync_crdt.dart';
import 'p2p_security_service.dart';

final _syncAad = Uint8List.fromList(
  utf8.encode('CatechHub_Context_Sync_v1'),
);

class SyncRecord {
  final String id;
  final String boxName;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const SyncRecord({
    required this.id,
    required this.boxName,
    required this.data,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  bool winsOver(SyncRecord other) {
    return updatedAt.isAfter(other.updatedAt);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'box': boxName,
        'data': data,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'isDeleted': isDeleted,
      };

  factory SyncRecord.fromJson(Map<String, dynamic> json) => SyncRecord(
        id: json['id'] as String,
        boxName: json['box'] as String,
        data: Map<String, dynamic>.from(json['data'] ?? {}),
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
        isDeleted: json['isDeleted'] == true,
      );

  factory SyncRecord.fromHiveEntry({
    required String id,
    required String boxName,
    required Map<String, dynamic> entry,
  }) {
    final createdAt =
        DateTime.tryParse(entry['createdAt']?.toString() ?? '')?.toUtc() ??
            DateTime.now().toUtc();
    final updatedAt =
        DateTime.tryParse(entry['updatedAt']?.toString() ?? '')?.toUtc() ??
            createdAt;
    return SyncRecord(
      id: id,
      boxName: boxName,
      data: Map<String, dynamic>.from(entry),
      createdAt: createdAt,
      updatedAt: updatedAt,
      isDeleted: entry['isDeleted'] == true,
    );
  }
}

class SyncIndexEntry {
  final String id;
  final String boxName;
  final DateTime updatedAt;
  final String checksum;
  final bool isDeleted;

  SyncIndexEntry({
    required this.id,
    required this.boxName,
    required this.updatedAt,
    required this.checksum,
    this.isDeleted = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'box': boxName,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'checksum': checksum,
        'isDeleted': isDeleted,
      };

  factory SyncIndexEntry.fromJson(Map<String, dynamic> json) =>
      SyncIndexEntry(
        id: json['id'] as String,
        boxName: json['box'] as String,
        updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
        checksum: json['checksum'] as String? ?? '',
        isDeleted: json['isDeleted'] == true,
      );
}

class SyncResult {
  final bool success;
  final int sentRecords;
  final int receivedRecords;
  final DateTime syncTimestamp;
  final String? error;
  final int conflictsResolved;

  const SyncResult({
    required this.success,
    this.sentRecords = 0,
    this.receivedRecords = 0,
    required this.syncTimestamp,
    this.error,
    this.conflictsResolved = 0,
  });

  String get summary {
    if (!success) return 'Sync fallita: $error';
    return 'Sync OK: $sentRecords inv, $receivedRecords ric, $conflictsResolved conflitti';
  }
}

/// Scope per-classe per la sincronizzazione.
///
/// Quando impostato, solo i record appartenenti alle classi indicate vengono
/// sincronizzati. Se la lista è vuota/`null`, vengono sincronizzate tutte le
/// classi (modalità "Mio Dispositivo").
class SyncClassScope {
  final String classId;
  final String classUniqueCode;

  const SyncClassScope({
    required this.classId,
    required this.classUniqueCode,
  });

  bool get isAll => false;
}

/// Determina se un record (per box/id/dati) appartiene ad almeno uno degli
/// scope classe. Se [scopes] è `null` o vuoto restituisce sempre `true`
/// (sincronizza tutte le classi).
bool _recordMatchesScope({
  required String boxName,
  required String id,
  required Map<String, dynamic> data,
  List<SyncClassScope>? scopes,
}) {
  // `null` = nessun filtro (tutte le classi). Lista vuota = nessuna classe
  // condivisa → nessun record corrisponde.
  if (scopes == null) return true;
  if (scopes.isEmpty) return false;

  // Catechesi slegate dalle classi (classUniqueCode vuoto): condivisibili
  // e visibili in tutte le classi → vengono sincronizzate con qualsiasi scope.
  if (boxName == LocalDatabase.catechesiBox) {
    final code = data['classUniqueCode']?.toString() ?? '';
    if (code.isEmpty) return true;
  }

  // Aule/stanze della parrocchia: dati globali di logistica, condivisi con
  // qualsiasi scope classe (i catechisti le vedono nello snapshot degli slot).
  if (boxName == LocalDatabase.aulaBox) {
    return true;
  }

  for (final scope in scopes) {
    if (_recordMatchesSingleScope(
      boxName: boxName,
      id: id,
      data: data,
      scope: scope,
    )) {
      return true;
    }
  }
  return false;
}

/// Determina se un record appartiene a un singolo scope classe.
bool _recordMatchesSingleScope({
  required String boxName,
  required String id,
  required Map<String, dynamic> data,
  required SyncClassScope scope,
}) {
  // Il record della classe stessa: match per id o uniqueCode.
  if (boxName == LocalDatabase.classesBox) {
    return id == scope.classId ||
        data['uniqueCode']?.toString() == scope.classUniqueCode;
  }

  // Record con classId esplicito (students, planning, attendance).
  final classId = data['classId']?.toString();
  if (classId != null && classId.isNotEmpty) {
    return classId == scope.classId;
  }

  // Record con classUniqueCode (documents, catechesi, contact_notes,
  // student_daily_notes, avvisi, attachments).
  final classCode = data['classUniqueCode']?.toString();
  if (classCode != null && classCode.isNotEmpty) {
    return classCode == scope.classUniqueCode;
  }

  // Box associativi senza campo classe diretto: risolviamo tramite il padre.
  if (boxName == LocalDatabase.documentDeliveriesBox) {
    try {
      final docRaw = Hive.box<Map>(LocalDatabase.documentsBox).get(id);
      if (docRaw != null) {
        final doc = LocalDatabase.toStringDynamicMap(docRaw);
        return doc['classUniqueCode']?.toString() == scope.classUniqueCode;
      }
    } catch (_) {}
    return false;
  }

  if (boxName == LocalDatabase.meetingCatechesiBox) {
    try {
      final meetingRaw = Hive.box<Map>(LocalDatabase.planningBox).get(id);
      if (meetingRaw != null) {
        final meeting = LocalDatabase.toStringDynamicMap(meetingRaw);
        return meeting['classId']?.toString() == scope.classId;
      }
    } catch (_) {}
    return false;
  }

  return false;
}

class HiveSyncEngine {
  static final HiveSyncEngine _instance = HiveSyncEngine._();
  factory HiveSyncEngine() => _instance;
  HiveSyncEngine._();

  static const syncableBoxes = {
    LocalDatabase.studentsBox: 'students',
    LocalDatabase.classesBox: 'classes',
    LocalDatabase.planningBox: 'planning',
    LocalDatabase.attendanceBox: 'attendance',
    LocalDatabase.documentsBox: 'documents',
    LocalDatabase.documentDeliveriesBox: 'document_deliveries',
    LocalDatabase.attachmentsBox: 'attachments',
    LocalDatabase.contactNotesBox: 'contact_notes',
    LocalDatabase.catechesiBox: 'catechesi',
    LocalDatabase.meetingCatechesiBox: 'meeting_catechesi',
    LocalDatabase.studentDailyNotesBox: 'student_daily_notes',
    LocalDatabase.aulaBox: 'aulas',
  };

  static const _lastSyncKey = 'p2p_last_sync_timestamp';

  Future<DateTime> getLastSyncTimestamp() async {
    final auth = LocalDatabase.auth();
    final stored = auth.get(_lastSyncKey);
    if (stored == null) {
      return DateTime.fromMillisecondsSinceEpoch(0).toUtc();
    }
    return DateTime.parse(stored as String).toUtc();
  }

  Future<void> saveLastSyncTimestamp(DateTime timestamp) async {
    final auth = LocalDatabase.auth();
    await auth.put(_lastSyncKey, timestamp.toUtc().toIso8601String());
  }

  static String _computeRecordChecksum(Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.from(data);
    normalized.remove('updatedAt');
    normalized.remove('createdAt');
    normalized.remove('nameLocked');
    final json = jsonEncode(normalized);
    return sha256.convert(utf8.encode(json)).toString().substring(0, 12);
  }

  List<SyncIndexEntry> buildLocalIndex([List<SyncClassScope>? scopes]) {
    final index = <SyncIndexEntry>[];

    for (final entry in syncableBoxes.entries) {
      final boxName = entry.key;
      try {
        final box = Hive.box<Map>(boxName);
        for (final key in box.keys) {
          final id = key.toString();
          final raw = box.get(key);
          if (raw == null) continue;
          final data = LocalDatabase.toStringDynamicMap(raw);
          if (!_recordMatchesScope(
            boxName: boxName,
            id: id,
            data: data,
            scopes: scopes,
          )) {
            continue;
          }
          final updatedAt =
              DateTime.tryParse(data['updatedAt']?.toString() ?? '')
                      ?.toUtc() ??
                  DateTime.fromMillisecondsSinceEpoch(0).toUtc();
          final isDeleted = data['isDeleted'] == true;
          final checksum = _computeRecordChecksum(data);
          index.add(SyncIndexEntry(
            id: id,
            boxName: boxName,
            updatedAt: updatedAt,
            checksum: checksum,
            isDeleted: isDeleted,
          ));
        }
      } catch (_) {}
    }

    return index;
  }

  List<SyncRecord> extractModifiedRecords(DateTime since,
      [List<SyncClassScope>? scopes]) {
    final records = <SyncRecord>[];

    for (final entry in syncableBoxes.entries) {
      final boxName = entry.key;
      try {
        final box = Hive.box<Map>(boxName);
        for (final key in box.keys) {
          final id = key.toString();
          final raw = box.get(key);
          if (raw == null) continue;
          final data = LocalDatabase.toStringDynamicMap(raw);
          if (!_recordMatchesScope(
            boxName: boxName,
            id: id,
            data: data,
            scopes: scopes,
          )) {
            continue;
          }
          final updatedAt =
              DateTime.tryParse(data['updatedAt']?.toString() ?? '')
                      ?.toUtc() ??
                  DateTime.fromMillisecondsSinceEpoch(0).toUtc();

          if (updatedAt.isAfter(since.toUtc())) {
            records.add(SyncRecord.fromHiveEntry(
              id: id,
              boxName: boxName,
              entry: data,
            ));
          }
        }
      } catch (_) {}
    }

    return records;
  }

  List<String> computeNeededRecords(
    List<SyncIndexEntry> remoteIndex,
  ) {
    final needed = <String>[];

    for (final remote in remoteIndex) {
      try {
        final box = Hive.box<Map>(remote.boxName);
        final localRaw = box.get(remote.id);
        final localIsDeleted = localRaw != null
            ? (LocalDatabase.toStringDynamicMap(localRaw)['isDeleted'] == true)
            : false;

        if (localRaw == null) {
          if (!remote.isDeleted) {
            needed.add(
                '${remote.boxName}:${remote.id}');
          }
          continue;
        }
        final localData = LocalDatabase.toStringDynamicMap(localRaw);
        final localUpdatedAt =
            DateTime.tryParse(localData['updatedAt']?.toString() ?? '')
                    ?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0).toUtc();

        if (remote.isDeleted && !localIsDeleted) {
          needed.add(
              '${remote.boxName}:${remote.id}');
          continue;
        }

        if (remote.updatedAt.isAfter(localUpdatedAt)) {
          needed.add(
              '${remote.boxName}:${remote.id}');
        } else if (remote.updatedAt == localUpdatedAt) {
          final localChecksum = _computeRecordChecksum(localData);
          if (remote.checksum != localChecksum) {
            needed.add(
                '${remote.boxName}:${remote.id}');
          }
        }
      } catch (_) {
        needed.add(
            '${remote.boxName}:${remote.id}');
      }
    }

    return needed;
  }

  List<SyncRecord> fetchRecords(List<String> recordKeys,
      [List<SyncClassScope>? scopes]) {
    final records = <SyncRecord>[];

    for (final key in recordKeys) {
      final parts = key.split(':');
      if (parts.length != 2) continue;
      final boxName = parts[0];
      final recordId = parts[1];

      try {
        final box = Hive.box<Map>(boxName);
        final raw = box.get(recordId);
        if (raw == null) continue;
        final data = LocalDatabase.toStringDynamicMap(raw);
        if (!_recordMatchesScope(
          boxName: boxName,
          id: recordId,
          data: data,
          scopes: scopes,
        )) {
          continue;
        }
        records.add(SyncRecord.fromHiveEntry(
          id: recordId,
          boxName: boxName,
          entry: data,
        ));
      } catch (_) {}
    }

    return records;
  }

  /// Salva un conflitto di sync nel box dedicato.
  Future<void> _saveConflict({
    required String boxName,
    required String recordId,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    required List<String> conflictingFields,
  }) async {
    try {
      final box = Hive.box<Map>(LocalDatabase.syncConflictsBox);
      final conflictKey = '$boxName:$recordId';
      await box.put(conflictKey, {
        'boxName': boxName,
        'recordId': recordId,
        'localData': localData,
        'remoteData': remoteData,
        'conflictingFields': conflictingFields,
        'detectedAt': DateTime.now().toUtc().toIso8601String(),
        'resolved': false,
      });
    } catch (_) {}
  }

  /// Esegue un merge field-by-field tra dati locali e remoti.
  /// Restituisce la mappa mergiata e l'elenco dei campi in conflitto.
  ///
  /// Quando [secretKey] è fornita (canale P2P associato), i campi divergenti
  /// vengono risolti con il Last-Write-Wins FIRMATO ([SignedLww.remoteWins]):
  /// il timestamp più recente vince solo se la sua firma HMAC è valida, così
  /// un dispositivo non può "inventare" un aggiornamento più recente di
  /// quello reale. Senza chiave si usa il confronto timestamp legacy.
  Map<String, dynamic> _mergeFields({
    required String boxName,
    required String recordId,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    required DateTime localUpdatedAt,
    required DateTime remoteUpdatedAt,
    String? secretKey,
    Set<String> excludeFields = const {},
  }) {
    final merged = Map<String, dynamic>.from(localData);
    final conflictFields = <String>[];

    final localUpdatedIso = localUpdatedAt.toUtc().toIso8601String();
    final remoteUpdatedIso = remoteUpdatedAt.toUtc().toIso8601String();
    final localSignature = localData['updatedAtSignature'] as String?;
    final remoteSignature = remoteData['updatedAtSignature'] as String?;

    final remoteWins = (secretKey != null && secretKey.isNotEmpty)
        ? SignedLww.remoteWins(
            boxName: boxName,
            recordId: recordId,
            localUpdatedAtIso: localUpdatedIso,
            localSignature: localSignature,
            remoteUpdatedAtIso: remoteUpdatedIso,
            remoteSignature: remoteSignature,
            secretKey: secretKey,
          )
        : remoteUpdatedAt.isAfter(localUpdatedAt);

    final nearConcurrent =
        localUpdatedAt.difference(remoteUpdatedAt).inSeconds.abs() <= 5;

    for (final entry in remoteData.entries) {
      final field = entry.key;
      final remoteValue = entry.value;

      // Campi tecnici da non considerare nei conflitti
      if (field == 'updatedAt' ||
          field == 'createdAt' ||
          field == 'lastModifiedBy' ||
          field == 'updatedAtSignature' ||
          excludeFields.contains(field)) {
        continue;
      }

      if (!merged.containsKey(field)) {
        // Solo remoto ha questo campo: lo prendiamo
        merged[field] = remoteValue;
      } else if (merged[field] != remoteValue) {
        // Stesso campo, valori diversi: potenziale conflitto.
        // La priorità è decisa dal LWW firmato (o dal timestamp legacy).
        if (remoteWins) {
          merged[field] = remoteValue;
        }
        // else: keep local value (already in merged)

        // Timestamp ravvicinati o uguali: conflitto reale da mostrare.
        if (nearConcurrent) {
          conflictFields.add(field);
        }
      }
      // Se sono uguali, non fare nulla
    }

    if (conflictFields.isNotEmpty) {
      merged['_conflicts'] = conflictFields;
    }

    return merged;
  }

  Future<SyncResult> applyRemoteRecords(
    List<SyncRecord> records, {
    List<SyncClassScope>? scopes,
    String? secretKey,
  }) async {
    var appliedCount = 0;
    var conflictsResolved = 0;
    final newConflicts = <String, List<String>>{};

    for (final remote in records) {
      if (!syncableBoxes.containsKey(remote.boxName)) continue;

      try {
        final box = Hive.box<Map>(remote.boxName);
        final localRaw = box.get(remote.id);
        final isClassBox = remote.boxName == 'classes';
        final isAttendanceBox = remote.boxName == LocalDatabase.attendanceBox;

        if (!_recordMatchesScope(
          boxName: remote.boxName,
          id: remote.id,
          data: remote.data,
          scopes: scopes,
        )) {
          continue;
        }

        if (localRaw == null) {
          if (!remote.isDeleted) {
            final data = Map<String, dynamic>.from(remote.data);
            data.remove('_conflicts');
            if (isClassBox && data['nameLocked'] != true) {
              data['nameLocked'] = true;
            }
            await box.put(remote.id, data);
            appliedCount++;
          }
          continue;
        }

        final localData = LocalDatabase.toStringDynamicMap(localRaw);
        final localUpdatedAt =
            DateTime.tryParse(localData['updatedAt']?.toString() ?? '')
                    ?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0).toUtc();
        final localIsDeleted = localData['isDeleted'] == true;

        if (remote.isDeleted && !localIsDeleted) {
          final merged = Map<String, dynamic>.from(localData);
          merged['isDeleted'] = true;
          merged['updatedAt'] = remote.updatedAt.toIso8601String();
          await box.put(remote.id, merged);
          appliedCount++;
          continue;
        }

        if (localIsDeleted && !remote.isDeleted) {
          final data = Map<String, dynamic>.from(remote.data);
          data.remove('_conflicts');
          if (isClassBox && data['nameLocked'] != true) {
            data['nameLocked'] = true;
          }
          await box.put(remote.id, data);
          appliedCount++;
          continue;
        }

        final merged = _mergeFields(
          boxName: remote.boxName,
          recordId: remote.id,
          localData: localData,
          remoteData: remote.data,
          localUpdatedAt: localUpdatedAt,
          remoteUpdatedAt: remote.updatedAt,
          secretKey: secretKey,
          excludeFields:
              isAttendanceBox ? const {'presence', 'presenceMeta'} : const {},
        );

        if (isAttendanceBox) {
          // Merge CRDT delle presenze: per-studente Last-Write-Wins usando
          // i meta-dati `presenceMeta` (due tablet possono inserire presenze
          // sullo stesso incontro e i risultati convergono senza conflitti).
          final crdt = AttendanceCrdt.mergePresence(
            localData: localData,
            remoteData: remote.data,
          );
          merged['presence'] = crdt['presence'];
          merged['presenceMeta'] = crdt['presenceMeta'];
        }

        final conflictFields =
            (merged['_conflicts'] as List<String>?) ?? [];
        merged.remove('_conflicts');
        // La firma del timestamp è un dato di trasporto: non va persistita.
        merged.remove('updatedAtSignature');

        if (isClassBox) {
          merged['nameLocked'] = (localData['nameLocked'] ?? true) ||
              (remote.data['nameLocked'] == true);
        }

        final now = DateTime.now().toUtc();
        merged['updatedAt'] = now.toIso8601String();
        await box.put(remote.id, merged);

        if (conflictFields.isNotEmpty) {
          final conflictKey = '${remote.boxName}:${remote.id}';
          newConflicts[conflictKey] = conflictFields;
          await _saveConflict(
            boxName: remote.boxName,
            recordId: remote.id,
            localData: localData,
            remoteData: remote.data,
            conflictingFields: conflictFields,
          );
        }

        appliedCount++;
        conflictsResolved += conflictFields.isEmpty ? 1 : 0;
      } catch (_) {}
    }

    await saveLastSyncTimestamp(DateTime.now().toUtc());

    return SyncResult(
      success: true,
      receivedRecords: appliedCount,
      syncTimestamp: DateTime.now().toUtc(),
      conflictsResolved: conflictsResolved,
    );
  }

  List<Map<String, dynamic>> serializeRecords(List<SyncRecord> records) {
    return records.map((r) => r.toJson()).toList();
  }

  /// Firma i timestamp (`updatedAt`) dei record con il shared secret del
  /// canale P2P, prima dell'invio. Inserisce `updatedAtSignature` nella
  /// mappa `data` di ogni record; il ricevente la usa in [SignedLww.remoteWins]
  /// per accettare il LWW solo se il timestamp più recente è autentico.
  List<SyncRecord> signRecordsForChannel(
    List<SyncRecord> records,
    String? secretKey,
  ) {
    if (secretKey == null || secretKey.isEmpty) return records;
    return records.map((r) {
      if (r.isDeleted) return r;
      final data = Map<String, dynamic>.from(r.data);
      data['updatedAtSignature'] = SignedLww.sign(
        boxName: r.boxName,
        recordId: r.id,
        updatedAtIso: r.updatedAt.toUtc().toIso8601String(),
        secretKey: secretKey,
      );
      return SyncRecord(
        id: r.id,
        boxName: r.boxName,
        data: data,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        isDeleted: r.isDeleted,
      );
    }).toList();
  }

  List<SyncRecord> deserializeRecords(List<dynamic> jsonList) {
    return jsonList.map((j) {
      final map = Map<String, dynamic>.from(j as Map);
      return SyncRecord.fromJson(map);
    }).toList();
  }

  Future<SyncResult> syncWithRemote({
    required List<SyncIndexEntry> localIndex,
    required List<SyncIndexEntry> remoteIndex,
    required Future<List<SyncRecord>> Function(List<String> neededKeys)
        fetchRemoteRecords,
    List<SyncClassScope>? scopes,
    String? secretKey,
  }) async {
    try {
      final neededFromRemote = computeNeededRecords(remoteIndex);

      var sentCount = 0;
      var receivedCount = 0;

      final neededFromLocal = computeNeededRecords(localIndex);
      if (neededFromLocal.isNotEmpty) {
        final localRecords = fetchRecords(neededFromLocal, scopes);
        sentCount = localRecords.length;
      }

      if (neededFromRemote.isNotEmpty) {
        final remoteRecords = await fetchRemoteRecords(neededFromRemote);
        final result = await applyRemoteRecords(
          remoteRecords,
          scopes: scopes,
          secretKey: secretKey,
        );
        receivedCount = result.receivedRecords;
      }

      return SyncResult(
        success: true,
        sentRecords: sentCount,
        receivedRecords: receivedCount,
        syncTimestamp: DateTime.now().toUtc(),
      );
    } catch (e) {
      return SyncResult(
        success: false,
        error: e.toString(),
        syncTimestamp: DateTime.now().toUtc(),
      );
    }
  }

  Future<void> exportToJson({
    required String Function(Map<String, dynamic>) encryptRecord,
    List<SyncClassScope>? scopes,
  }) async {
    final records = extractModifiedRecords(
        DateTime.fromMillisecondsSinceEpoch(0), scopes);

    for (final record in records) {
      encryptRecord(record.data);
    }
  }

  /// Encrypts a payload using the session key (AES-GCM)
  static Future<String> encryptPayload(
    String plainText,
    SecretKey sessionKey,
  ) async {
    final nonce = Uint8List.fromList(_secureRandom(12));
    final secretBox = await AesGcm.with256bits().encrypt(
      utf8.encode(plainText),
      secretKey: sessionKey,
      nonce: nonce,
      aad: _syncAad,
    );

    final payload = P2PEncryptedPayload(
      nonce: Uint8List.fromList(secretBox.nonce),
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      mac: Uint8List.fromList(secretBox.mac.bytes),
      useChacha: false,
    );
    return payload.encode();
  }

  /// Decrypts a payload using the session key (AES-GCM)
  static Future<String> decryptPayload(
    String encryptedPayload,
    SecretKey sessionKey,
  ) async {
    final encrypted = P2PEncryptedPayload.decode(encryptedPayload);
    final secretBox = SecretBox(
      encrypted.ciphertext,
      nonce: encrypted.nonce,
      mac: Mac(encrypted.mac),
    );

    final plainBytes = await AesGcm.with256bits().decrypt(
      secretBox,
      secretKey: sessionKey,
      aad: _syncAad,
    );

    return utf8.decode(plainBytes);
  }

  /// Performs a full bidirectional sync with a remote device
  /// Uses LWW (Last-Write-Wins) conflict resolution based on updatedAt
  /// 
  /// [sessionKey] - The shared session key from P2PSecurityService (ECDH + HKDF derived)
  /// [fetchRemoteIndex] - Function to fetch remote index
  /// [fetchRemoteRecords] - Function to fetch remote records by keys
  /// [sendLocalIndex] - Function to send local index to remote
  /// [sendLocalRecords] - Function to send local records to remote
  /// [onProgress] - Optional progress callback (sent, received, total)
  Future<SyncResult> performFullSync({
    required SecretKey sessionKey,
    required Future<List<SyncIndexEntry>> Function() fetchRemoteIndex,
    required Future<List<SyncRecord>> Function(List<String> keys) fetchRemoteRecords,
    required Future<void> Function(List<SyncIndexEntry> index) sendLocalIndex,
    required Future<void> Function(List<SyncRecord> records) sendLocalRecords,
    void Function(int sent, int received, int total)? onProgress,
    List<SyncClassScope>? scopes,
  }) async {
    try {
      // Step 1: Build local index
      final localIndex = buildLocalIndex(scopes);
      
      // Step 2: Send local index to remote
      await sendLocalIndex(localIndex);
      
      // Step 3: Fetch remote index
      final remoteIndex = await fetchRemoteIndex();
      
      // Step 4: Compute what we need from remote
      final neededFromRemote = computeNeededRecords(remoteIndex);
      
      // Step 5: Compute what remote needs from us
      final neededFromLocal = computeNeededRecordsFromLocal(localIndex, remoteIndex);
      
      // Step 6: Send our records that remote needs
      var sentCount = 0;
      if (neededFromLocal.isNotEmpty) {
        final localRecords = fetchRecords(neededFromLocal, scopes);
        await sendLocalRecords(localRecords);
        sentCount = localRecords.length;
      }
      
      // Step 7: Fetch and apply remote records we need
      var receivedCount = 0;
      var conflictsResolved = 0;
      
      if (neededFromRemote.isNotEmpty) {
        final remoteRecords = await fetchRemoteRecords(neededFromRemote);
        
        // Apply with conflict resolution
        final result = await applyRemoteRecords(
          remoteRecords,
          scopes: scopes,
        );
        receivedCount = result.receivedRecords;
        conflictsResolved = result.conflictsResolved;
      }
      
      onProgress?.call(sentCount, receivedCount, sentCount + receivedCount);
      
      return SyncResult(
        success: true,
        sentRecords: sentCount,
        receivedRecords: receivedCount,
        syncTimestamp: DateTime.now().toUtc(),
        conflictsResolved: conflictsResolved,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        error: e.toString(),
        syncTimestamp: DateTime.now().toUtc(),
      );
    }
  }

  /// Computes which local records the remote needs based on index comparison
  List<String> computeNeededRecordsFromLocal(
    List<SyncIndexEntry> localIndex,
    List<SyncIndexEntry> remoteIndex,
  ) {
    final needed = <String>[];
    final remoteIndexMap = {for (final e in remoteIndex) '${e.boxName}:${e.id}': e};
    
    for (final local in localIndex) {
      final key = '${local.boxName}:${local.id}';
      final remote = remoteIndexMap[key];
      
      if (remote == null) {
        if (!local.isDeleted) {
          needed.add(key);
        }
      } else if (remote.isDeleted && !local.isDeleted) {
        needed.add(key);
      } else if (local.updatedAt.isAfter(remote.updatedAt)) {
        if (!local.isDeleted) {
          needed.add(key);
        }
      } else if (local.updatedAt == remote.updatedAt && local.checksum != remote.checksum) {
        needed.add(key);
      }
    }
    
    return needed;
  }

  /// Generates cryptographically secure random bytes
  static Uint8List _secureRandom(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}
