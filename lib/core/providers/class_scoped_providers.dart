import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/current_class_provider.dart';
import '../../core/storage/local_database.dart';
import '../../features/catechesi/catechesi_repository.dart';
import '../../features/classes/classes_repository.dart';
import '../../features/classes/classes_provider.dart';
import '../../features/contact_notes/contact_notes_repository.dart';
import '../../features/documents/documents_repository.dart';
import '../../features/meetings/attendance_repository.dart';
import '../../features/meetings/planning_repository.dart';
import '../../features/students/student_daily_notes_repository.dart';
import '../../features/students/students_repository.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/student_model.dart';

/// ═══════════════════════════════════════════════════════════════════════════════
/// PROVIDERS SCOPATI PER CLASSE
///
/// Questi provider filtrano automaticamente i dati in base alla classe
/// attualmente selezionata ([currentClassProvider]). Quando l'utente
/// cambia classe, tutti questi provider si aggiornano automaticamente.
/// ═══════════════════════════════════════════════════════════════════════════════

/// Provider che restituisce l'ID della classe corrente (stringa vuota se nessuna).
final currentClassIdProvider = Provider<String>((ref) {
  return ref.watch(currentClassProvider) ?? '';
});

/// Stream degli studenti della classe corrente.
final currentClassStudentsProvider = StreamProvider.autoDispose<List<Student>>((ref) {
  final classId = ref.watch(currentClassIdProvider);
  if (classId.isEmpty) return const Stream.empty();
  final repo = ref.read(studentsRepoProvider);
  return repo.getStudentsByClass(classId);
});

/// Lista sincrona degli studenti della classe corrente.
final currentClassStudentsSyncProvider = Provider<List<Student>>((ref) {
  final classId = ref.watch(currentClassIdProvider);
  if (classId.isEmpty) return [];
  final repo = ref.read(studentsRepoProvider);
  return repo.getStudentsByClassSync(classId);
});

/// Stream degli incontri (planning) della classe corrente.
final currentClassPlanningProvider = StreamProvider.autoDispose<List<PlanningMeeting>>((ref) {
  final classId = ref.watch(currentClassIdProvider);
  if (classId.isEmpty) return const Stream.empty();
  final repo = ref.read(planningRepositoryProvider);
  return repo.getPlanningByClass(classId);
});

/// Lista sincrona degli incontri della classe corrente.
final currentClassPlanningSyncProvider = Provider<List<PlanningMeeting>>((ref) {
  final classId = ref.watch(currentClassIdProvider);
  if (classId.isEmpty) return [];
  final repo = ref.read(planningRepositoryProvider);
  return repo.getPlanningByClassSync(classId);
});

/// Stream delle presenze della classe corrente.
final currentClassAttendanceProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final classId = ref.watch(currentClassIdProvider);
  if (classId.isEmpty) return const Stream.empty();
  final repo = ref.read(attendanceRepositoryProvider);
  return repo.getAttendanceByClass(classId);
});

/// Lista sincrona delle presenze della classe corrente.
final currentClassAttendanceSyncProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final classId = ref.watch(currentClassIdProvider);
  if (classId.isEmpty) return [];
  final repo = ref.read(attendanceRepositoryProvider);
  return repo.getAttendanceByClassSync(classId);
});

/// Stream dei documenti della classe corrente.
final currentClassDocumentsProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final classId = ref.watch(currentClassIdProvider);
  if (classId.isEmpty) return const Stream.empty();
  final repo = ref.read(documentsRepositoryProvider);
  return repo.getDocumentsByClass(classId);
});

/// Lista sincrona dei documenti della classe corrente.
final currentClassDocumentsSyncProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final classId = ref.watch(currentClassIdProvider);
  if (classId.isEmpty) return [];
  final repo = ref.read(documentsRepositoryProvider);
  return repo.getDocumentsByClassSync(classId);
});

/// Stream delle note di contatto della classe corrente.
final currentClassContactNotesProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final classId = ref.watch(currentClassIdProvider);
  if (classId.isEmpty) return const Stream.empty();
  final repo = ref.read(contactNotesRepositoryProvider);
  return repo.getNotesByClass(classId);
});

/// Lista sincrona delle note di contatto della classe corrente.
final currentClassContactNotesSyncProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final classId = ref.watch(currentClassIdProvider);
  if (classId.isEmpty) return [];
  final repo = ref.read(contactNotesRepositoryProvider);
  return repo.getNotesByClassSync(classId);
});

/// Stream delle catechesi della classe corrente.
final currentClassCatechesiProvider = StreamProvider.autoDispose<List<Catechesi>>((ref) {
  final classId = ref.watch(currentClassIdProvider);
  if (classId.isEmpty) return const Stream.empty();
  final repo = ref.read(catechesiRepositoryProvider);
  return repo.getCatechesiByClass(classId);
});

/// Lista sincrona delle catechesi della classe corrente.
final currentClassCatechesiSyncProvider = Provider<List<Catechesi>>((ref) {
  final classId = ref.watch(currentClassIdProvider);
  if (classId.isEmpty) return [];
  final repo = ref.read(catechesiRepositoryProvider);
  return repo.getCatechesiByClassSync(classId);
});

/// Stream delle note giornaliere degli studenti della classe corrente.
final currentClassDailyNotesProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final classId = ref.watch(currentClassIdProvider);
  if (classId.isEmpty) return const Stream.empty();
  final repo = ref.read(studentDailyNotesRepositoryProvider);
  return repo.getNotesByClass(classId);
});

/// Lista sincrona delle note giornaliere della classe corrente.
final currentClassDailyNotesSyncProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final classId = ref.watch(currentClassIdProvider);
  if (classId.isEmpty) return [];
  final repo = ref.read(studentDailyNotesRepositoryProvider);
  return repo.getNotesByClassSync(classId);
});

/// Stream delle classi dell'utente corrente (già esiste come myClassesProvider).
/// Manteniamo questo alias per chiarezza.
final myClassesStreamProvider = Provider.autoDispose<List<SchoolClass>>((ref) {
  return ref.watch(myClassesProvider);
});

/// Provider per ottenere una classe specifica per ID.
final classByIdProvider = Provider.family<SchoolClass?, String>((ref, classId) {
  final classesAsync = ref.watch(classesStreamProvider);
  return classesAsync.when(
    data: (classes) => classes.firstWhere(
      (c) => c.id == classId,
      orElse: () => SchoolClass(id: '', name: '', studentIds: [], catechistIds: []),
    ),
    loading: () => null,
    error: (_, __) => null,
  );
});