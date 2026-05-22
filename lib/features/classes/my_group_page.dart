import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_service.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/student_model.dart';

import '../classes/classes_provider.dart';
import '../meetings/attendance_repository.dart';
import '../students/students_provider.dart';
import 'print_service.dart';

/// Modello di supporto locale che unisce lo studente alle sue statistiche e assenze consecutive
class _StudentWithStats {
  final Student student;
  final int totalPresence;
  final int totalAbsence;
  final int consecutiveAbsences;

  _StudentWithStats({
    required this.student,
    required this.totalPresence,
    required this.totalAbsence,
    required this.consecutiveAbsences,
  });
}

final _groupStudentsStatsProvider = StreamProvider.autoDispose
    .family<List<_StudentWithStats>, List<String>>((ref, studentIds) {
      final studentsRepo = ref.read(studentsRepoProvider);
      final attendanceRepo = AttendanceRepository();

      final studentsStream = studentsRepo.getAllStudents();

      return studentsStream.asyncMap((allStudents) async {
        final attendance = attendanceRepo.getAttendanceSync()
          ..sort((a, b) {
            final aDate =
                DateTime.tryParse(a['date']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bDate =
                DateTime.tryParse(b['date']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });

        final studentIdsSet = studentIds.toSet();
        final classStudents = allStudents
            .where((s) => studentIdsSet.contains(s.id))
            .toList();

        final totalPresenceMap = <String, int>{};
        final totalAbsenceMap = <String, int>{};
        final consecutiveAbsencesMap = <String, int>{};
        final breakConsecutiveMap = <String, bool>{};

        for (final s in classStudents) {
          totalPresenceMap[s.id] = 0;
          totalAbsenceMap[s.id] = 0;
          consecutiveAbsencesMap[s.id] = 0;
          breakConsecutiveMap[s.id] = false;
        }

        for (final data in attendance) {
          final presence = Map<String, dynamic>.from(
            data['presence'] as Map? ?? {},
          );

          for (final entry in presence.entries) {
            final studentId = entry.key.toString();
            if (!studentIdsSet.contains(studentId)) continue;

            final status = entry.value?.toString();
            if (status == 'Presente') {
              totalPresenceMap[studentId] =
                  (totalPresenceMap[studentId] ?? 0) + 1;
              breakConsecutiveMap[studentId] = true;
            } else if (status == 'Assente') {
              totalAbsenceMap[studentId] =
                  (totalAbsenceMap[studentId] ?? 0) + 1;
              if (breakConsecutiveMap[studentId] == false) {
                consecutiveAbsencesMap[studentId] =
                    (consecutiveAbsencesMap[studentId] ?? 0) + 1;
              }
            }
          }
        }

        return classStudents.map((s) {
          return _StudentWithStats(
            student: s,
            totalPresence: totalPresenceMap[s.id] ?? 0,
            totalAbsence: totalAbsenceMap[s.id] ?? 0,
            consecutiveAbsences: consecutiveAbsencesMap[s.id] ?? 0,
          );
        }).toList();
      });
    });

class MyGroupPage extends ConsumerWidget {
  const MyGroupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(classesStreamProvider);
    const uid = AuthService.localUserId;

    final isDesktop = MediaQuery.of(context).size.width > 900;

    return AppScaffold(
      title: 'Il mio gruppo',
      child: classesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (classes) {
          final myClass = classes.firstWhere(
            (c) => c.catechistIds.contains(uid),
            orElse: () =>
                SchoolClass(id: '', name: '', studentIds: [], catechistIds: []),
          );

          if (myClass.id.isEmpty) {
            return const Center(child: Text('Nessun gruppo assegnato'));
          }

          final studentsStatsAsync = ref.watch(
            _groupStudentsStatsProvider(myClass.studentIds),
          );

          return studentsStatsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Errore nel caricamento dati: $e')),
            data: (studentsWithStats) {
              return Column(
                children: [
                  const SizedBox(height: 12),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: isDesktop
                        ? _DesktopActions(
                            classId: myClass.id,
                            className: myClass.name,
                            students: studentsWithStats,
                          )
                        : _MobileActions(
                            classId: myClass.id,
                            className: myClass.name,
                            students: studentsWithStats,
                          ),
                  ),

                  const SizedBox(height: 14),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _ClassHeader(name: myClass.name),
                  ),

                  const SizedBox(height: 10),

                  Expanded(
                    child: studentsWithStats.isEmpty
                        ? const Center(child: Text('Nessun ragazzo presente'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: studentsWithStats.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final item = studentsWithStats[i];

                              return _StudentCard(
                                student: item.student,
                                compact: !isDesktop,
                                present: item.totalPresence,
                                absent: item.totalAbsence,
                                consecutiveAbsences: item.consecutiveAbsences,
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// =========================
/// MOBILE ACTIONS
/// =========================
class _MobileActions extends StatelessWidget {
  final String classId;
  final String className;
  final List<_StudentWithStats> students;

  const _MobileActions({
    required this.classId,
    required this.className,
    required this.students,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.checklist_rounded,
                label: 'Gestione appelli',
                compact: true,
                isPrimary: true,
                onTap: () {
                  context.push('/attendance-meetings', extra: classId);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: Icons.print_rounded,
                label: 'Stampa appelli',
                compact: true,
                onTap: () async {
                  await PrintService.printAttendanceReport(
                    className: className,
                    students: students.map((s) {
                      return PrintStudentData(
                        fullName: '${s.student.name} ${s.student.surname}',
                        present: s.totalPresence,
                        absent: s.totalAbsence,
                        consecutiveAbsences: s.consecutiveAbsences,
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// =========================
/// DESKTOP ACTIONS
/// =========================
class _DesktopActions extends StatelessWidget {
  final String classId;
  final String className;
  final List<_StudentWithStats> students;

  const _DesktopActions({
    required this.classId,
    required this.className,
    required this.students,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.checklist_rounded,
            label: 'Gestione appelli',
            isPrimary: true,
            onTap: () {
              context.push('/attendance-meetings', extra: classId);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(
            icon: Icons.print_rounded,
            label: 'Stampa appelli',
            onTap: () async {
              await PrintService.printAttendanceReport(
                className: className,
                students: students.map((s) {
                  return PrintStudentData(
                    fullName: '${s.student.name} ${s.student.surname}',
                    present: s.totalPresence,
                    absent: s.totalAbsence,
                    consecutiveAbsences: s.consecutiveAbsences,
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// =========================
/// ACTION BUTTON
/// =========================
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool compact;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = const Color(0xFF174A7E);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: compact ? 10 : 14,
          horizontal: 12,
        ),
        decoration: BoxDecoration(
          color: isPrimary ? color : color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: compact ? 18 : 22,
              color: isPrimary ? Colors.white : color,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w600,
                  color: isPrimary ? Colors.white : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================
/// CLASS HEADER
/// =========================
class _ClassHeader extends StatelessWidget {
  final String name;

  const _ClassHeader({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_rounded, color: Color(0xFF174A7E)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

/// =========================
/// STUDENT CARD
/// =========================
class _StudentCard extends StatelessWidget {
  final Student student;
  final bool compact;
  final int present;
  final int absent;
  final int consecutiveAbsences;

  const _StudentCard({
    required this.student,
    required this.compact,
    required this.present,
    required this.absent,
    required this.consecutiveAbsences,
  });

  @override
  Widget build(BuildContext context) {
    final hasWarning = consecutiveAbsences >= 2;

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: hasWarning ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: hasWarning
            ? Border.all(color: Colors.red.shade200, width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: compact ? 16 : 20,
            backgroundColor: hasWarning
                ? Colors.red.shade100
                : Colors.blue.shade50,
            child: Icon(
              Icons.person,
              color: hasWarning ? Colors.red.shade900 : const Color(0xFF174A7E),
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${student.name} ${student.surname}',
                  style: TextStyle(
                    fontSize: compact ? 13 : 15,
                    fontWeight: FontWeight.w600,
                    color: hasWarning ? Colors.red.shade900 : Colors.black87,
                  ),
                ),
                if (hasWarning)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '$consecutiveAbsences assenze di fila!',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$present',
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$absent',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
