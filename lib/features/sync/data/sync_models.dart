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
