import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/student_relation_model.dart';
import '../../shared/utils/auth_utils.dart';

final studentRelationsRepositoryProvider = Provider<StudentRelationsRepository>(
  (ref) {
    return StudentRelationsRepository();
  },
);

class StudentRelationsRepository {
  final _box = LocalDatabase.studentRelations();

  Stream<List<StudentRelation>> watchByClass(String classUniqueCode) {
    return LocalDatabase.watchList(
      _box,
      (id, data) => StudentRelation.fromMap(id, data),
    ).map(
      (relations) => relations
          .where((relation) => relation.classUniqueCode == classUniqueCode)
          .toList(),
    );
  }

  List<StudentRelation> getByClassSync(String classUniqueCode) {
    return LocalDatabase.values(
      _box,
      (id, data) => StudentRelation.fromMap(id, data),
    ).where((relation) => relation.classUniqueCode == classUniqueCode).toList();
  }

  StudentRelation? getBetween(String firstId, String secondId) {
    final raw = _box.get(StudentRelation.idFor(firstId, secondId));
    if (raw == null) return null;
    return StudentRelation.fromMap(
      StudentRelation.idFor(firstId, secondId),
      LocalDatabase.toStringDynamicMap(raw),
    );
  }

  Future<void> save({
    required String firstId,
    required String secondId,
    required StudentRelationType type,
    required String classUniqueCode,
  }) async {
    if (firstId == secondId) {
      throw ArgumentError('Un ragazzo non può essere associato a sé stesso');
    }
    final id = StudentRelation.idFor(firstId, secondId);
    final existing = _box.get(id);
    final existingMap = existing == null
        ? null
        : LocalDatabase.toStringDynamicMap(existing);
    final now = DateTime.now();
    final ids = [firstId, secondId]..sort();
    final relation = StudentRelation(
      id: id,
      studentAId: ids[0],
      studentBId: ids[1],
      type: type,
      classUniqueCode: classUniqueCode,
      createdAt:
          DateTime.tryParse(existingMap?['createdAt']?.toString() ?? '') ?? now,
      updatedAt: now,
      lastModifiedBy: getCurrentCatechistName(),
    );
    await _box.put(id, relation.toMap());
  }

  Future<void> delete(String firstId, String secondId) async {
    await _box.delete(StudentRelation.idFor(firstId, secondId));
  }
}
