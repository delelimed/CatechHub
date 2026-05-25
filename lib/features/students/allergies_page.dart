import 'package:flutter/material.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/models/student_model.dart';
import './students_repository.dart';

class AllergiesPage extends StatelessWidget {
  const AllergiesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = StudentsRepository();
    final allStudents = repo.getAllStudentsSync();

    final studentsWithAllergies = allStudents
        .where((s) => s.allergies != null && s.allergies!.isNotEmpty)
        .toList();

    studentsWithAllergies.sort((a, b) => a.surname.compareTo(b.surname));

    return AppScaffold(
      title: 'Allergie',
      child: studentsWithAllergies.isEmpty
          ? const Center(
              child: Text(
                'Nessun ragazzo con allergie segnate.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: studentsWithAllergies.length,
              itemBuilder: (context, index) {
                final student = studentsWithAllergies[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${student.surname} ${student.name}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF174A7E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        student.allergies!,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
