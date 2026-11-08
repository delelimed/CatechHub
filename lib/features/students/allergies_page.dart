import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/class_scoped_providers.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/models/student_model.dart';
import './students_repository.dart';

/// Schermata di consultazione allergie: elenca in ordine alfabetico
/// tutti gli studenti che hanno almeno un'allergia registrata, mostrando
/// nome, cognome e descrizione allergia.
/// Legge i dati dal Box `students` via [StudentsRepository.getAllStudentsSync]
/// e filtra sul campo [Student.allergies].
/// Flusso: accessibile dalla navigazione globale come report rapido.
class AllergiesPage extends ConsumerWidget {
  const AllergiesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return AppScaffold(
      title: 'Allergie',
      child: ref
          .watch(currentClassStudentsSyncProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                Center(child: Text('Errore caricamento ragazzi: $error')),
            data: (allStudents) {
              final studentsWithAllergies = Student.sortedBySurname(
                allStudents.where(
                  (s) => s.allergies != null && s.allergies!.isNotEmpty,
                ),
              );
              if (studentsWithAllergies.isEmpty) {
                return Center(
                  child: Text(
                    'Nessun ragazzo con allergie segnate.',
                    style: TextStyle(
                      color: isDark ? Colors.grey.shade400 : Colors.grey,
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: studentsWithAllergies.length,
                itemBuilder: (context, index) {
                  final student = studentsWithAllergies[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.surfaceContainer
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? colorScheme.outline.withValues(alpha: 0.2)
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${student.surname} ${student.name}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isDark
                                ? colorScheme.primary
                                : const Color(0xFF174A7E),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          student.allergies!,
                          style: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
    );
  }
}
