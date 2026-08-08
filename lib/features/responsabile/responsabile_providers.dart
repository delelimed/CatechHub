// ══════════════════════════════════════════════════════════════════════════════
// responsabile_providers.dart — CatechHub (stream per la vista alberia parrocchiale)
//
// Espone stream combinatori delle entità della modalità "Responsabile
// Catechistico" affinché la dashboard gerarchica possa agganciarsi ai dati
// in tempo reale con un solo watch.
// ══════════════════════════════════════════════════════════════════════════════

import'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/student_model.dart';
import '../classes/classes_repository.dart';
import '../meetings/attendance_repository.dart';
import '../students/students_repository.dart';
import 'audit_log_repository.dart';
import 'aula_repository.dart';
import 'parish_config_repository.dart';

/// Stream reattivo delle aule parrocchiali.
final aulasStreamProvider = StreamProvider((ref) {
  return ref.watch(aulaRepositoryProvider).getAulas();
});

/// Configurazione parrocchiale corrente (riutilizza il repository provider).
final parishConfigRepositoryProvider = Provider((ref) {
  return ParishConfigRepository();
});

/// Stream reattivo del Registro Trattamenti GDPR (voci più recenti prima).
final auditLogStreamProvider = StreamProvider((ref) {
  return AuditLogRepository().getAllLogs();
});

/// Stream delle classi (riuso dello stream del feature classes).
final parrocchiaClassesProvider = StreamProvider((ref) {
  return ClassesRepository().getClasses();
});

/// Stream degli studenti di tutta la parrocchia.
final parrocchiaStudentsProvider = StreamProvider((ref) {
  return StudentsRepository().getAllStudents();
});

/// Presenze aggregate per classe (mappa classId → lista record).
final presenzePerClasseProvider = StreamProvider((ref) {
  return AttendanceRepository()
      .getAttendance()
      .map((records) {
        final out = <String, List<Map<String, dynamic>>>{};
        for (final r in records) {
          final classId = r['classId']?.toString() ?? '';
          out.putIfAbsent(classId, () => []).add(r);
        }
        return out;
      });
});

/// Stream degli studenti iscritti a una specifica classe.
final studentsOfClassProvider = StreamProvider.autoDispose
    .family<List<Student>, String>((ref, classId) {
  return StudentsRepository().getStudentsByClass(classId);
});