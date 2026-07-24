import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

import '../../../core/storage/local_database.dart';

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

  SyncIndexEntry({
    required this.id,
    required this.boxName,
    required this.updatedAt,
    required this.checksum,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'box': boxName,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'checksum': checksum,
      };

  factory SyncIndexEntry.fromJson(Map<String, dynamic> json) =>
      SyncIndexEntry(
        id: json['id'] as String,
        boxName: json['box'] as String,
        updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
        checksum: json['checksum'] as String? ?? '',
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

class HiveSyncEngine {
  static final HiveSyncEngine _instance = HiveSyncEngine._();
  factory HiveSyncEngine() => _instance;
  HiveSyncEngine._();

  static const _syncableBoxes = {
    LocalDatabase.studentsBox: 'students',
    LocalDatabase.classesBox: 'classes',
    LocalDatabase.planningBox: 'planning',
    LocalDatabase.attendanceBox: 'attendance',
    LocalDatabase.documentsBox: 'documents',
    LocalDatabase.documentDeliveriesBox: 'document_deliveries',
    LocalDatabase.contactNotesBox: 'contact_notes',
    LocalDatabase.studentDailyNotesBox: 'student_daily_notes',
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
    final json = jsonEncode(normalized);
    return sha256.convert(utf8.encode(json)).toString().substring(0, 12);
  }

  List<SyncIndexEntry> buildLocalIndex() {
    final index = <SyncIndexEntry>[];

    for (final entry in _syncableBoxes.entries) {
      final boxName = entry.key;
      try {
        final box = Hive.box<Map>(boxName);
        for (final key in box.keys) {
          final id = key.toString();
          final raw = box.get(key);
          if (raw == null) continue;
          final data = LocalDatabase.toStringDynamicMap(raw);
          final updatedAt =
              DateTime.tryParse(data['updatedAt']?.toString() ?? '')
                      ?.toUtc() ??
                  DateTime.fromMillisecondsSinceEpoch(0).toUtc();
          final checksum = _computeRecordChecksum(data);
          index.add(SyncIndexEntry(
            id: id,
            boxName: boxName,
            updatedAt: updatedAt,
            checksum: checksum,
          ));
        }
      } catch (_) {}
    }

    return index;
  }

  List<SyncRecord> extractModifiedRecords(DateTime since) {
    final records = <SyncRecord>[];

    for (final entry in _syncableBoxes.entries) {
      final boxName = entry.key;
      try {
        final box = Hive.box<Map>(boxName);
        for (final key in box.keys) {
          final id = key.toString();
          final raw = box.get(key);
          if (raw == null) continue;
          final data = LocalDatabase.toStringDynamicMap(raw);
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
        if (localRaw == null) {
          needed.add(
              '${remote.boxName}:${remote.id}');
          continue;
        }
        final localData = LocalDatabase.toStringDynamicMap(localRaw);
        final localUpdatedAt =
            DateTime.tryParse(localData['updatedAt']?.toString() ?? '')
                    ?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0).toUtc();

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

  List<SyncRecord> fetchRecords(List<String> recordKeys) {
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
        records.add(SyncRecord.fromHiveEntry(
          id: recordId,
          boxName: boxName,
          entry: data,
        ));
      } catch (_) {}
    }

    return records;
  }

  Future<SyncResult> applyRemoteRecords(
    List<SyncRecord> records,
  ) async {
    var appliedCount = 0;
    var conflictsResolved = 0;

    for (final remote in records) {
      if (!_syncableBoxes.containsKey(remote.boxName)) continue;

      try {
        final box = Hive.box<Map>(remote.boxName);
        final localRaw = box.get(remote.id);

        if (localRaw == null) {
          if (!remote.isDeleted) {
            await box.put(remote.id, remote.data);
            appliedCount++;
          }
          continue;
        }

        final localData = LocalDatabase.toStringDynamicMap(localRaw);
        final localUpdatedAt =
            DateTime.tryParse(localData['updatedAt']?.toString() ?? '')
                    ?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0).toUtc();

        if (remote.updatedAt.isAfter(localUpdatedAt)) {
          if (remote.isDeleted) {
            final merged = Map<String, dynamic>.from(localData);
            merged['isDeleted'] = true;
            merged['updatedAt'] = remote.updatedAt.toIso8601String();
            await box.put(remote.id, merged);
          } else {
            await box.put(remote.id, remote.data);
          }
          appliedCount++;
        } else if (remote.updatedAt == localUpdatedAt) {
          final merged = Map<String, dynamic>.from(localData);
          bool changed = false;
          remote.data.forEach((k, v) {
            if (!merged.containsKey(k) || merged[k] != v) {
              merged[k] = v;
              changed = true;
            }
          });
          if (changed) {
            merged['updatedAt'] = DateTime.now().toUtc().toIso8601String();
            await box.put(remote.id, merged);
            appliedCount++;
            conflictsResolved++;
          }
        }
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
  }) async {
    try {
      final neededFromRemote = computeNeededRecords(remoteIndex);

      var sentCount = 0;
      var receivedCount = 0;

      final neededFromLocal = computeNeededRecords(localIndex);
      if (neededFromLocal.isNotEmpty) {
        final localRecords = fetchRecords(neededFromLocal);
        sentCount = localRecords.length;
      }

      if (neededFromRemote.isNotEmpty) {
        final remoteRecords = await fetchRemoteRecords(neededFromRemote);
        final result = await applyRemoteRecords(remoteRecords);
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
  }) async {
    final records = extractModifiedRecords(
        DateTime.fromMillisecondsSinceEpoch(0));

    for (final record in records) {
      encryptRecord(record.data);
    }
  }
}
