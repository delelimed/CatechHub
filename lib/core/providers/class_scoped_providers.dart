import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/current_class_provider.dart';
import '../../features/catechesi/catechesi_repository.dart';
import '../../features/classes/classes_provider.dart';
import '../../features/contact_notes/avvisi_repository.dart';
import '../../features/contact_notes/contact_notes_repository.dart';
import '../../features/documents/documents_repository.dart';
import '../../features/meetings/attendance_repository.dart';
import '../../features/planning/planning_repository.dart';
import '../../features/students/student_daily_notes_repository.dart';
import '../../features/students/students_provider.dart';
import '../../shared/models/catechesi_model.dart';
import '../../shared/models/avviso_template_model.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/planning_meeting.dart';
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

/// Provider che restituisce il codice univoco della classe corrente
/// (stringa vuota se nessuna classe selezionata).
final currentClassUniqueCodeProvider = Provider<String>((ref) {
  final details = ref.watch(currentClassDetailsProvider);
  return details?.uniqueCode ?? '';
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
  final classCode = ref.watch(currentClassUniqueCodeProvider);
  if (classCode.isEmpty) return const Stream.empty();
  final repo = ref.read(documentsRepositoryProvider);
  return repo.getDocumentsByClass(classCode);
});

/// Lista sincrona dei documenti della classe corrente.
final currentClassDocumentsSyncProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final classCode = ref.watch(currentClassUniqueCodeProvider);
  if (classCode.isEmpty) return [];
  final repo = ref.read(documentsRepositoryProvider);
  return repo.getDocumentsByClassSync(classCode);
});

/// Stream delle note di contatto della classe corrente.
final currentClassContactNotesProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final classCode = ref.watch(currentClassUniqueCodeProvider);
  if (classCode.isEmpty) return const Stream.empty();
  final repo = ref.read(contactNotesRepositoryProvider);
  return repo.getNotesByClass(classCode);
});

/// Lista sincrona delle note di contatto della classe corrente.
final currentClassContactNotesSyncProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final classCode = ref.watch(currentClassUniqueCodeProvider);
  if (classCode.isEmpty) return [];
  final repo = ref.read(contactNotesRepositoryProvider);
  return repo.getNotesByClassSync(classCode);
});

/// Stream delle catechesi: le catechesi non sono legate a una classe,
/// quindi vengono mostrate in tutte le classi dell'utente.
final currentClassCatechesiProvider = StreamProvider.autoDispose<List<Catechesi>>((ref) {
  final repo = ref.read(catechesiRepositoryProvider);
  return repo.watchCatechesi();
});

/// Lista sincrona delle catechesi (non legate a una classe).
final currentClassCatechesiSyncProvider = Provider<List<Catechesi>>((ref) {
  final repo = ref.read(catechesiRepositoryProvider);
  return repo.getCatechesiSync();
});

/// Stream delle note giornaliere degli studenti della classe corrente.
final currentClassDailyNotesProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final classCode = ref.watch(currentClassUniqueCodeProvider);
  if (classCode.isEmpty) return const Stream.empty();
  final repo = ref.read(studentDailyNotesRepositoryProvider);
  return repo.getNotesByClass(classCode);
});

/// Lista sincrona delle note giornaliere della classe corrente.
final currentClassDailyNotesSyncProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final classCode = ref.watch(currentClassUniqueCodeProvider);
  if (classCode.isEmpty) return [];
  final repo = ref.read(studentDailyNotesRepositoryProvider);
  return repo.getNotesByClassSync(classCode);
});

/// Stream degli avvisi della classe corrente.
final currentClassAvvisiProvider = StreamProvider.autoDispose<List<AvvisoTemplate>>((ref) {
  final classCode = ref.watch(currentClassUniqueCodeProvider);
  if (classCode.isEmpty) return const Stream.empty();
  final repo = ref.read(avvisiRepoProvider);
  return repo.watchByClass(classCode);
});

/// Lista sincrona degli avvisi della classe corrente.
final currentClassAvvisiSyncProvider = Provider<List<AvvisoTemplate>>((ref) {
  final classCode = ref.watch(currentClassUniqueCodeProvider);
  if (classCode.isEmpty) return [];
  final repo = ref.read(avvisiRepoProvider);
  return repo.getByClassSync(classCode);
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
    error: (_, _) => null,
  );
});