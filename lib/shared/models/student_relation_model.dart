enum StudentRelationType { friendship, enmity }

class StudentRelation {
  final String id;
  final String studentAId;
  final String studentBId;
  final StudentRelationType type;
  final String? classUniqueCode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String lastModifiedBy;

  const StudentRelation({
    required this.id,
    required this.studentAId,
    required this.studentBId,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.classUniqueCode,
    this.lastModifiedBy = '',
  });

  static String idFor(String firstId, String secondId) {
    final ids = [firstId, secondId]..sort();
    return '${ids[0]}__${ids[1]}';
  }

  factory StudentRelation.fromMap(String id, Map<String, dynamic> data) {
    final type = data['type'] == StudentRelationType.enmity.name
        ? StudentRelationType.enmity
        : StudentRelationType.friendship;
    return StudentRelation(
      id: id,
      studentAId: data['studentAId']?.toString() ?? '',
      studentBId: data['studentBId']?.toString() ?? '',
      type: type,
      classUniqueCode: data['classUniqueCode']?.toString(),
      createdAt:
          DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(data['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      lastModifiedBy: data['lastModifiedBy']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'studentAId': studentAId,
    'studentBId': studentBId,
    'type': type.name,
    'classUniqueCode': classUniqueCode,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'lastModifiedBy': lastModifiedBy,
  };
}
