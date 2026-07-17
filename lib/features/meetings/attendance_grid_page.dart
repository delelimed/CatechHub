import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../shared/models/planning_meeting.dart';
import '../../shared/models/student_model.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../planning/planning_repository.dart';
import '../students/students_repository.dart';
import 'attendance_repository.dart';

class AttendanceGridPage extends ConsumerWidget {
  const AttendanceGridPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      final studentsRepo = StudentsRepository();
      final planningRepo = PlanningRepository();
      final attendanceRepo = AttendanceRepository();

      final allStudents = studentsRepo.getAllStudentsSync();
      if (allStudents.isEmpty) {
        return AppScaffold(
          title: 'Registro presenze',
          child: const Center(child: Text('Nessun ragazzo nel gruppo')),
        );
      }

      final meetings = planningRepo.getMeetingsSync()
          .where((m) => !m.isReunion)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      if (meetings.isEmpty) {
        return AppScaffold(
          title: 'Registro presenze',
          child: const Center(child: Text('Nessun incontro presente')),
        );
      }

      final allAttendance = attendanceRepo.getAttendanceSync();
      final attendanceByMeeting = <String, Map<String, String>>{};
      for (final record in allAttendance) {
        final mid = record['id'].toString();
        final presence = (record['presence'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ?? {};
        attendanceByMeeting[mid] = presence;
      }

      return AppScaffold(
        title: 'Registro presenze',
        child: _GridBody(
          students: allStudents,
          meetings: meetings,
          attendanceByMeeting: attendanceByMeeting,
        ),
      );
    } catch (e) {
      return AppScaffold(
        title: 'Registro presenze',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Errore caricamento dati: $e'),
          ),
        ),
      );
    }
  }
}

class _GridBody extends StatelessWidget {
  final List<Student> students;
  final List<PlanningMeeting> meetings;
  final Map<String, Map<String, String>> attendanceByMeeting;

  const _GridBody({
    required this.students,
    required this.meetings,
    required this.attendanceByMeeting,
  });

  @override
  Widget build(BuildContext context) {
    const studentColWidth = 160.0;
    const dateColWidth = 70.0;
    const rowHeight = 44.0;
    const headerH = 56.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Colonna fissa nomi
          SizedBox(
            width: studentColWidth,
            child: Column(
              children: [
                Container(
                  height: headerH + 4,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 12, top: 12),
                  child: const Text(
                    'Ragazzi',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF174A7E),
                    ),
                  ),
                ),
                ...students.map((s) {
                  return Container(
                    height: rowHeight,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
                      ),
                    ),
                    child: Text(
                      '${s.surname} ${s.name}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
              ],
            ),
          ),
          // Area scrollabile date
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                children: [
                  Container(
                    height: headerH,
                    margin: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: meetings.map((m) {
                        return SizedBox(
                          width: dateColWidth,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                DateFormat('dd/MM').format(m.date),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Color(0xFF174A7E),
                                ),
                              ),
                              Text(
                                DateFormat('MMM', 'it_IT').format(m.date).toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...students.map((s) {
                    return SizedBox(
                      height: rowHeight,
                      child: Row(
                        children: meetings.map((m) {
                          final presence = attendanceByMeeting[m.id];
                          final status = presence?[s.id];
                          final isPresent = status == 'Presente';
                          final isAbsent = status == 'Assente';

                          return SizedBox(
                            width: dateColWidth,
                            child: Center(
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isPresent
                                      ? Colors.green
                                      : isAbsent
                                          ? Colors.red
                                          : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Text(
                                    isPresent
                                        ? 'P'
                                        : isAbsent
                                            ? 'A'
                                            : '',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: isPresent
                                          ? Colors.black
                                          : isAbsent
                                              ? Colors.white
                                              : Colors.grey.shade300,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
