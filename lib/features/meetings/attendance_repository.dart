import '../../core/storage/local_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final attendanceRepositoryProvider =
    Provider<AttendanceRepository>((ref) {
  return AttendanceRepository();
});

class AttendanceRepository {
  final _box = LocalDatabase.attendance();

  Stream<List<Map<String, dynamic>>> getAttendance() {
    return LocalDatabase.watchList(
      _box,
      (id, data) => {'id': id, ...data},
    );
  }

  List<Map<String, dynamic>> getAttendanceSync() {
    return LocalDatabase.values(
      _box,
      (id, data) => {'id': id, ...data},
    );
  }

  Map<String, dynamic>? getAttendanceForMeeting(String meetingId) {
    final data = _box.get(meetingId);
    if (data == null) return null;
    return LocalDatabase.toStringDynamicMap(data);
  }

  Future<void> saveAttendance({
    required String meetingId,
    required DateTime date,
    required String classId,
    required Map<String, String> presence,
  }) async {
    await _box.put(meetingId, {
      'meetingId': meetingId,
      'date': date.toIso8601String(),
      'classId': classId,
      'presence': presence,
    });
  }
}
