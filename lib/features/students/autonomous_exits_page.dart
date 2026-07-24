import 'package:flutter/material.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/models/student_model.dart';
import './students_repository.dart';

/// Schermata di consultazione uscite: raggruppa gli studenti in tre
/// sezioni distinte — autorizzati a uscire da soli (autonomo),
/// prelevamento dai genitori e prelevamento da altro (con dettaglio).
/// Legge i dati dal Box `students` via [StudentsRepository.getAllStudentsSync]
/// e filtra sul campo [Student.autonomousExits].
/// Flusso: accessibile dalla navigazione globale per verifica rapida
/// delle autorizzazioni uscita.
class AutonomousExitsPage extends StatelessWidget {
  const AutonomousExitsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = StudentsRepository();
    final allStudents = repo.getAllStudentsSync();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final autonomousStudents = Student.sortedBySurname(
      allStudents.where(
        (s) =>
            s.autonomousExits != null &&
            s.autonomousExits!.isNotEmpty &&
            s.autonomousExits!.toLowerCase().contains('autonomo'),
      ),
    );

    final accompaniedByParentsStudents = Student.sortedBySurname(
      allStudents.where(
        (s) =>
            s.autonomousExits != null &&
            s.autonomousExits!.isNotEmpty &&
            s.autonomousExits!.toLowerCase().contains('genitori'),
      ),
    );

    final accompaniedByOthersStudents = Student.sortedBySurname(
      allStudents.where(
        (s) =>
            s.autonomousExits != null &&
            s.autonomousExits!.isNotEmpty &&
            s.autonomousExits!.toLowerCase().startsWith('altro:'),
      ),
    );

    return AppScaffold(
      title: 'Uscite Autonome',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _Section(
              title: 'Autorizzati ad uscire da soli',
              students: autonomousStudents,
              color: Colors.green,
              showExitDetails: false,
              isDark: isDark,
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 24),
            _Section(
              title: 'Prelevamento dai genitori',
              students: accompaniedByParentsStudents,
              color: Colors.blue,
              showExitDetails: true,
              isDark: isDark,
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 24),
            _Section(
              title: 'Prelevamento da altro',
              students: accompaniedByOthersStudents,
              color: Colors.orange,
              showExitDetails: true,
              isDark: isDark,
              colorScheme: colorScheme,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Student> students;
  final Color color;
  final bool showExitDetails;
  final bool isDark;
  final ColorScheme colorScheme;

  const _Section({
    required this.title,
    required this.students,
    required this.color,
    required this.showExitDetails,
    required this.isDark,
    required this.colorScheme,
  });

  String? _extractExitDetail(String autonomousExits) {
    if (autonomousExits.toLowerCase().startsWith('altro:')) {
      return autonomousExits.replaceFirst(RegExp(r'altro:', caseSensitive: false), '').trim();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(
                color == Colors.green
                    ? Icons.check_circle_outline
                    : color == Colors.blue
                        ? Icons.family_restroom_rounded
                        : Icons.person_rounded,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: color,
                ),
              ),
              if (students.isNotEmpty) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    students.length.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (students.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? colorScheme.surfaceContainer : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Nessun ragazzo in questa categoria.',
              style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
          )
        else
          ...students.map(
            (student) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? colorScheme.surfaceContainer : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${student.surname} ${student.name}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
                    ),
                  ),
                  if (showExitDetails &&
                      student.autonomousExits != null &&
                      student.autonomousExits!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_rounded,
                            size: 14,
                            color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _extractExitDetail(student.autonomousExits!) ??
                                  student.autonomousExits!,
                              style: TextStyle(
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
