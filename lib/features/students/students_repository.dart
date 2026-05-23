import '../../core/storage/local_database.dart';
import '../../shared/models/student_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final studentsRepositoryProvider =
    Provider<StudentsRepository>((ref) {
  return StudentsRepository();
});

class StudentsRepository {
  final _box = LocalDatabase.students();

  Future<void> addStudent(Student student) async {
    final id = student.id.isEmpty ? LocalDatabase.newId('student') : student.id;
    await _box.put(id, student.toMap());
  }


  Stream<List<Student>> getAllStudents() {
    return LocalDatabase.watchList(
      _box,
      (id, data) => Student.fromMap(id, data),
    );
  }

  Stream<List<Student>> getStudents() => getAllStudents();

  List<Student> getAllStudentsSync() {
    return LocalDatabase.values(
      _box,
      (id, data) => Student.fromMap(id, data),
    );
  }

  Future<void> updateStudent(String id, Student student) async {
    await _box.put(id, student.toMap());
  }

  Future<void> deleteStudent(String id) async {
    await _box.delete(id);

    final classesBox = LocalDatabase.classes();
    for (final classKey in classesBox.keys) {
      final data = LocalDatabase.toStringDynamicMap(classesBox.get(classKey));
      final studentIds = (data['studentIds'] as List? ?? [])
          .map((value) => value.toString())
          .where((studentId) => studentId != id)
          .toList();
      data['studentIds'] = studentIds;
      await classesBox.put(classKey, data);
    }

    final attendanceBox = LocalDatabase.attendance();
    for (final attendanceKey in attendanceBox.keys) {
      final data = LocalDatabase.toStringDynamicMap(attendanceBox.get(attendanceKey));
      final presence = Map<String, dynamic>.from(data['presence'] as Map? ?? {});
      if (presence.remove(id) != null) {
        data['presence'] = presence;
        await attendanceBox.put(attendanceKey, data);
      }
    }

    final deliveriesBox = LocalDatabase.documentDeliveries();
    for (final deliveryKey in deliveriesBox.keys) {
      final data = LocalDatabase.toStringDynamicMap(deliveriesBox.get(deliveryKey));
      if (data.remove(id) != null) {
        await deliveriesBox.put(deliveryKey, data);
      }
    }
  }
}


