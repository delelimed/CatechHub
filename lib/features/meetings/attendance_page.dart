/// Pagina di appello per un singolo incontro.
///
/// In CateREG, questa schermata consente al catechista di selezionare una data
/// di incontro e registrare la presenza di ogni ragazzo della propria classe.
/// Ogni studente viene visualizzato con nome, cognome e un indicatore cromatico:
/// - sfondo rosso se ha 2+ assenze consecutive consecutive
/// - pulsanti "Presente" (verde) e "Assente" (rosso) per ogni studente
/// - supporto a futuri swipe gesture per cambiare stato rapidamente
/// Le presenze vengono salvate su Hive tramite [AttendanceRepository].
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_service.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/planning_meeting.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../classes/classes_provider.dart';
import '../students/students_provider.dart';
import 'attendance_repository.dart';

class _Student {
  final String id;
  final String name;
  final String surname;
  final bool hasTwoConsecutiveAbsences;

  _Student({
    required this.id,
    required this.name,
    required this.surname,
    required this.hasTwoConsecutiveAbsences,
  });
}

final _studentsWithHistoryProvider =
    StreamProvider.autoDispose.family<List<_Student>, String>((ref, currentMeetingId) {
  final studentsRepo = ref.watch(studentsRepoProvider);
  final attendanceRepo = AttendanceRepository();

  return studentsRepo.getAllStudents().map((students) {
    final attendance = attendanceRepo.getAttendanceSync()
      ..sort((a, b) {
        final aDate = DateTime.tryParse(a['date']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(b['date']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

    final studentHistory = <String, List<String>>{};
    for (final record in attendance.where((a) => a['id'] != currentMeetingId)) {
      final presenceMap = Map<String, dynamic>.from(record['presence'] as Map? ?? {});
      presenceMap.forEach((studentId, value) {
        studentHistory.putIfAbsent(studentId, () => []);
        if (studentHistory[studentId]!.length < 2) {
          studentHistory[studentId]!.add(value.toString());
        }
      });
    }

    final sorted = [...students]..sort((a, b) {
      final bySurname =
          a.surname.toLowerCase().compareTo(b.surname.toLowerCase());
      if (bySurname != 0) return bySurname;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return sorted.map((student) {
      final history = studentHistory[student.id] ?? [];
      final hasTwoConsecutiveAbsences =
          history.length >= 2 && history[0] == 'Assente' && history[1] == 'Assente';

      return _Student(
        id: student.id,
        name: student.name,
        surname: student.surname,
        hasTwoConsecutiveAbsences: hasTwoConsecutiveAbsences,
      );
    }).toList();
  });
});

class AttendancePage extends ConsumerStatefulWidget {
  final dynamic meeting;

  const AttendancePage({
    super.key,
    required this.meeting,
  });

  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  Map<String, String> presence = {};

  @override
  void initState() {
    super.initState();
    final existing =
        AttendanceRepository().getAttendanceForMeeting(widget.meeting?.id ?? '');
    if (existing != null) {
      presence = Map<String, String>.from(existing['presence'] as Map? ?? {});
    }
  }

  Future<void> _save() async {
    if (widget.meeting == null || widget.meeting.id == null) return;

    await AttendanceRepository().saveAttendance(
      meetingId: widget.meeting.id,
      date: widget.meeting.date,
      classId: widget.meeting.classId,
      presence: presence,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Presenze salvate')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final meeting = widget.meeting;
    if (meeting is PlanningMeeting && meeting.isReunion) {
      return AppScaffold(
        title: 'Appello presenze',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Le riunioni non prevedono l\'appello dei ragazzi.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    final classesAsync = ref.watch(classesStreamProvider);
    final studentsWithHistoryAsync =
        ref.watch(_studentsWithHistoryProvider(widget.meeting?.id ?? ''));
    const uid = AuthService.localUserId;

    return AppScaffold(
      title: 'Appello presenze',
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: isDark ? colorScheme.primary : const Color(0xFF174A7E),
        foregroundColor: isDark ? colorScheme.onPrimary : Colors.white,
        icon: const Icon(Icons.save_rounded),
        label: const Text('Salva'),
        onPressed: _save,
      ),
      child: classesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore nel caricamento classi: $e')),
        data: (classes) {
          final myClass = classes.firstWhere(
            (c) => c.catechistIds.contains(uid),
            orElse: () => SchoolClass(
              id: '',
              name: '',
              studentIds: [],
              catechistIds: [],
            ),
          );

          if (myClass.id.isEmpty) {
            return const Center(
              child: Text('Nessun gruppo assegnato per questo profilo'),
            );
          }

          return studentsWithHistoryAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Errore nel caricamento studenti: $e')),
            data: (allStudents) {
              final students = allStudents
                  .where((s) => myClass.studentIds.contains(s.id))
                  .toList()
                ..sort((a, b) {
                  final bySurname =
                      a.surname.toLowerCase().compareTo(b.surname.toLowerCase());
                  if (bySurname != 0) return bySurname;
                  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                });

              if (students.isEmpty) {
                return const Center(
                  child: Text('Nessun ragazzo presente nel tuo gruppo'),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: students.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final s = students[index];
                  final value = presence[s.id];

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: s.hasTwoConsecutiveAbsences
                          ? (isDark ? Colors.red.shade900.withValues(alpha: 0.2) : Colors.red.shade50)
                          : (isDark ? colorScheme.surfaceContainer : Colors.white),
                      borderRadius: BorderRadius.circular(20),
                      border: s.hasTwoConsecutiveAbsences
                          ? Border.all(color: isDark ? Colors.red.shade700.withValues(alpha: 0.4) : Colors.red.shade200, width: 1)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.3)
                              : Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: s.hasTwoConsecutiveAbsences
                              ? (isDark ? Colors.red.shade800.withValues(alpha: 0.3) : Colors.red.shade100)
                              : (isDark ? colorScheme.primaryContainer.withValues(alpha: 0.3) : Colors.blue.shade50),
                          child: Icon(
                            Icons.person,
                            color: s.hasTwoConsecutiveAbsences
                                ? (isDark ? Colors.red.shade300 : Colors.red.shade900)
                                : (isDark ? colorScheme.primary : const Color(0xFF174A7E)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${s.name} ${s.surname}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: s.hasTwoConsecutiveAbsences
                                      ? (isDark ? Colors.red.shade300 : Colors.red.shade900)
                                      : (isDark ? colorScheme.onSurface : Colors.black87),
                                ),
                              ),
                              if (s.hasTwoConsecutiveAbsences)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '2+ assenze consecutive!',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.red.shade400 : Colors.red.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            _PresenceButton(
                              label: 'Presente',
                              selected: value == 'Presente',
                              color: Colors.green,
                              onTap: () => setState(() => presence[s.id] = 'Presente'),
                            ),
                            const SizedBox(width: 8),
                            _PresenceButton(
                              label: 'Assente',
                              selected: value == 'Assente',
                              color: Colors.red,
                              onTap: () => setState(() => presence[s.id] = 'Assente'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _PresenceButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _PresenceButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}
