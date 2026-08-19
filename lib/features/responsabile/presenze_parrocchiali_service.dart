// ══════════════════════════════════════════════════════════════════════════════
// presenze_parrocchiali_service.dart — CatechHub (monitoraggio presenze parrocchiali)
//
// Responsabilità:
//  - vista aggregata delle presenze su tutta la parrocchia (tutte le classi);
//  - allerta "assenze prolungate": individua i ragazzi con N assenze
//    consecutive (soglia personalizzabile), evidenziati al Responsabile per
//    il contatto diretto con le famiglie.
//
// ORDINAMENTO PRESENZE: i record attendance sono chiave="" come meeting.id;
// vengono ordinati per data (campo `date` ISO) crescente per calcolare
// in modo corretto la sequenza di assenze consecutive.
// ══════════════════════════════════════════════════════════════════════════════

import '../../shared/models/class_model.dart';
import '../classes/classes_repository.dart';
import '../meetings/attendance_repository.dart';
import '../students/students_repository.dart';

/// Ragazzo in allarme per assenze prolungate.
class AllertaAssenza {
  final String studentId;
  final String fullName;
  final String className;
  final String classId;
  final int assenzeConsecutive;
  final int totaleAssenze;

  const AllertaAssenza({
    required this.studentId,
    required this.fullName,
    required this.className,
    required this.classId,
    required this.assenzeConsecutive,
    required this.totaleAssenze,
  });
}

/// Servizio di aggregazione presenze e allerta assenze parrocchiali.
class PresenzeParrocchialiService {
  const PresenzeParrocchialiService();

  /// Dati reattivi: presenze per classe (utile per la gerarchia).
  Stream<Map<String, List<Map<String, dynamic>>>> presenzePerClasse() {
    return AttendanceRepository().getAttendance().map(_groupByClass);
  }

  Map<String, List<Map<String, dynamic>>> _groupByClass(
    List<Map<String, dynamic>> records,
  ) {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final r in records) {
      final classId = r['classId']?.toString() ?? '';
      out.putIfAbsent(classId, () => []).add(r);
    }
    return out;
  }

  /// Calcola le assenze consecutive per ogni studente iscritto.
  ///
  /// [threshold] = soglia di assenze consecutive per essere segnalato.
  /// Usa solo record conseguesce con data nota. Se un ragazzo non ha presenze,
  /// non viene segnalato (dati insufficienti).
  Future<List<AllertaAssenza>> rilevaIstanza({
    required int threshold,
    List<SchoolClass>? classes,
    bool includiArchiviati = false,
  }) async {
    if (threshold <= 1) return const [];

    final classesRepo = ClassesRepository();
    final allClasses = classes ?? classesRepo.getClassesSync();
    final allStudents = await StudentsRepository().getAllStudentsSync();
    final studentsById = {for (final s in allStudents) s.id: s};

    final attendance = AttendanceRepository().getAttendanceSync()
      ..sort((a, b) {
        final da = DateTime.tryParse(a['date']?.toString() ?? '');
        final db = DateTime.tryParse(b['date']?.toString() ?? '');
        return (da ?? DateTime(0)).compareTo(db ?? DateTime(0));
      });

    final alerts = <AllertaAssenza>[];

    for (final cls in allClasses) {
      if (cls.archived && !includiArchiviati) continue;
      final classRecords = attendance
          .where((r) => r['classId']?.toString() == cls.id)
          .toList();
      // Sequenza per studente delle presenze (cronologiche).
      final sequences = <String, List<String>>{};
      for (final r in classRecords) {
        final presence = (r['presence'] as Map? ?? {});
        presence.forEach((sid, status) {
          sequences
              .putIfAbsent(sid.toString(), () => [])
              .add(status.toString());
        });
      }

      for (final entry in studentsById.entries) {
        final student = entry.value;
        if (student.classId != cls.id) continue;
        final seq = sequences[student.id];
        if (seq == null || seq.isEmpty) continue;

        // Conta assenze consecutive PARTENDO dalla più recente.
        var consecutive = 0;
        for (var i = seq.length - 1; i >= 0; i--) {
          if (seq[i] == 'Assente') {
            consecutive++;
          } else {
            break;
          }
        }
        if (consecutive >= threshold) {
          final totale = seq.where((s) => s == 'Assente').length;
          alerts.add(
            AllertaAssenza(
              studentId: student.id,
              fullName: '${student.name} ${student.surname}'.trim(),
              className: cls.name,
              classId: cls.id,
              assenzeConsecutive: consecutive,
              totaleAssenze: totale,
            ),
          );
        }
      }
    }

    alerts.sort((a, b) => b.assenzeConsecutive.compareTo(a.assenzeConsecutive));
    return alerts;
  }
}
