import 'package:flutter/material.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/models/student_model.dart';
import './students_repository.dart';

class AutonomousExitsPage extends StatelessWidget {
  const AutonomousExitsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = StudentsRepository();
    final allStudents = repo.getAllStudentsSync();

    final autonomousStudents = allStudents
        .where((s) =>
            s.autonomousExits == null ||
            s.autonomousExits!.isEmpty ||
            s.autonomousExits!.toLowerCase().contains('autorizzato') ||
            s.autonomousExits!.toLowerCase().contains('si'))
        .toList();

    final nonAutonomousStudents = allStudents
        .where((s) =>
            s.autonomousExits != null &&
            s.autonomousExits!.isNotEmpty &&
            !s.autonomousExits!.toLowerCase().contains('autorizzato') &&
            !s.autonomousExits!.toLowerCase().contains('si'))
        .toList();

    autonomousStudents.sort((a, b) => a.surname.compareTo(b.surname));
    nonAutonomousStudents.sort((a, b) => a.surname.compareTo(b.surname));

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
            ),
            const SizedBox(height: 24),
            _Section(
              title: 'Prelevamento da padre/madre/altro',
              students: nonAutonomousStudents,
              color: Colors.orange,
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

  const _Section({
    required this.title,
    required this.students,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (students.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Nessun ragazzo in questa categoria.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          )
        else
          ...students.map(
            (student) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${student.surname} ${student.name}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF174A7E),
                    ),
                  ),
                  if (student.autonomousExits != null &&
                      student.autonomousExits!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      student.autonomousExits!,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
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
