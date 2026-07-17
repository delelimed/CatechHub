/// Repository per la gestione delle presenze (attendance) su Hive.
///
/// In CateREG, fornisce operazioni CRUD per i record di presenza associati
/// a ogni incontro. Ogni record è salvato nella box Hive `attendance` con:
/// - meetingId (chiave univoca)
/// - date, classId, presence (mappa studentId -> "Presente"/"Assente"/"Giustificato")
/// Espone sia stream (per UI reattiva) che accesso sincrono (per calcoli offline
/// come il controllo di 2+ assenze consecutive).
import '../../core/storage/local_database.dart';
import '../../shared/utils/auth_utils.dart';
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
    final catechistName = getCurrentCatechistName();
    await _box.put(meetingId, {
      'meetingId': meetingId,
      'date': date.toIso8601String(),
      'classId': classId,
      'presence': presence,
      'lastModifiedBy': catechistName,
    });
  }
}
