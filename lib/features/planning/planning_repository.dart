import '../../core/storage/local_database.dart';
import '../../shared/models/planning_meeting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final planningRepositoryProvider =
    Provider<PlanningRepository>((ref) {
  return PlanningRepository();
});

class PlanningRepository {
  final _box = LocalDatabase.planning();

  Stream<List<PlanningMeeting>> getMeetings() {
    return LocalDatabase.watchList(
      _box,
      (id, data) => PlanningMeeting.fromMap(id, data),
    );
  }

  List<PlanningMeeting> getMeetingsSync() {
    return LocalDatabase.values(
      _box,
      (id, data) => PlanningMeeting.fromMap(id, data),
    );
  }

  Future<void> addMeeting(PlanningMeeting m) async {
    if (_hasMeetingOnSameDay(m)) {
      throw Exception('Esiste gia un incontro per questo giorno');
    }

    final id = m.id.isEmpty ? LocalDatabase.newId('meeting') : m.id;
    await _box.put(id, m.toMap());
  }

  Future<void> updateMeeting(String id, PlanningMeeting m) async {
    if (_hasMeetingOnSameDay(m, excludedId: id)) {
      throw Exception('Esiste gia un incontro per questo giorno');
    }

    await _box.put(id, m.toMap());

    final attendanceBox = LocalDatabase.attendance();
    final attendance = attendanceBox.get(id);
    if (attendance != null) {
      final updatedAttendance = LocalDatabase.toStringDynamicMap(attendance);
      updatedAttendance['date'] = m.date.toIso8601String();
      updatedAttendance['classId'] = m.classId;
      await attendanceBox.put(id, updatedAttendance);
    }
  }

  Future<void> deleteMeeting(String id) async {
    await _box.delete(id);
    await LocalDatabase.attendance().delete(id);
  }

  bool _hasMeetingOnSameDay(PlanningMeeting m, {String? excludedId}) {
    final dateKey = DateTime(m.date.year, m.date.month, m.date.day);

    return getMeetingsSync().any((meeting) {
      if (meeting.id == excludedId) return false;
      final otherDate = DateTime(
        meeting.date.year,
        meeting.date.month,
        meeting.date.day,
      );
      return meeting.classId == m.classId && otherDate == dateKey;
    });
  }
}
