// ══════════════════════════════════════════════════════════════════════════════
// responsabile_providers.dart — CatechHub (stream della modalità Responsabile)
//
// Espone stream combinatori delle entità della modalità "Responsabile
// Catechistico" affinché dashboard e sezioni di gestione possano agganciarsi
// ai dati in tempo reale con un solo watch.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/student_model.dart';
import '../classes/classes_repository.dart';
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

/// Stream degli studenti iscritti a una specifica classe.
final studentsOfClassProvider = StreamProvider.autoDispose
    .family<List<Student>, String>((ref, classId) {
  return StudentsRepository().getStudentsByClass(classId);
});