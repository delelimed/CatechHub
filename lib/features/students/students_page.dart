import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/app_scaffold.dart';
import '../../shared/models/student_model.dart';
import '../documents/documents_provider.dart';
import 'student_quick_view_page.dart';
import 'students_repository.dart';
import 'students_add_page.dart';
import 'edit_student_page.dart';

final studentsRepoProvider = Provider((ref) => StudentsRepository());

/// Schermata principale dell'area ragazzi: elenco completo degli studenti
/// con cards nominative, indicatori visivi di documenti mancanti (arancione)
/// e menu contestuale (visualizza, modifica, elimina).
/// Usa il modello [Student] tramite [StudentsRepository] (Box `students`).
/// Punto di ingresso del flusso "Anagrafica": da qui si naviga verso
/// [AddStudentPage], [EditStudentPage] e [StudentQuickViewPage].
class StudentsPage extends ConsumerWidget {
  const StudentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(studentsRepoProvider);

    return AppScaffold(
      title: 'Ragazzi',

      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF174A7E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuovo ragazzo'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AddStudentPage(),
            ),
          );
        },
      ),

      child: StreamBuilder<List<Student>>(
        stream: repo.getAllStudents(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return _EmptyState();
          }

          final students = Student.sortedBySurname(snapshot.data!);

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: students.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: 12),
            itemBuilder: (_, index) {
              final s = students[index];

              return _StudentCard(
                student: s,
                onView: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          StudentQuickViewPage(student: s),
                    ),
                  );
                },
                onEdit: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          EditStudentPage(student: s),
                    ),
                  );
                },
                onDelete: () {
                  repo.deleteStudent(s.id);
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// =========================
/// STUDENT CARD
/// =========================
class _StudentCard extends ConsumerWidget {
  final Student student;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _StudentCard({
    required this.student,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = '${student.surname} ${student.name}';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final gradientStart = isDark ? colorScheme.surfaceContainerLowest : Colors.white;
    final gradientEnd = isDark
        ? colorScheme.primaryContainer.withValues(alpha: 0.15)
        : Colors.blue.shade50.withValues(alpha: 0.35);
    final borderColor = isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.blue.shade100;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.4)
        : Colors.black.withValues(alpha: 0.04);
    final titleColor = isDark ? colorScheme.onSurface : const Color(0xFF174A7E);
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;
    final avatarColor = const Color(0xFF174A7E);

    // Controlla se ci sono documenti da consegnare
    final docsAsync = ref.watch(documentsStreamProvider);

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onView,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [gradientStart, gradientEnd],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            /// AVATAR
            CircleAvatar(
              radius: 26,
              backgroundColor: avatarColor,
              child: Text(
                student.surname.isNotEmpty
                    ? student.surname[0]
                    : (student.name.isNotEmpty ? student.name[0] : '?'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(width: 14),

            /// TEXT
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: titleColor,
                          ),
                        ),
                      ),
                      // Indicatore documenti mancanti
                      docsAsync.when(
                        loading: () => const SizedBox(),
                        error: (_, __) => const SizedBox(),
                        data: (documents) {
                          if (documents.isEmpty) return const SizedBox();

                          // Controlla se questo studente ha documenti mancanti
                          return _DocumentWarningIndicator(studentId: student.id, documents: documents);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Madre: ${student.motherName} ${student.motherSurname}',
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 13,
                    ),
                  ),

                  Text(
                    'Padre: ${student.fatherName} ${student.fatherSurname}',
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            /// MENU
            PopupMenuButton<String>(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onSelected: (value) {
                if (value == 'view') onView();
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'view',
                  child: Row(
                    children: [
                      Icon(Icons.visibility),
                      SizedBox(width: 10),
                      Text('Visualizza scheda'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit),
                      SizedBox(width: 10),
                      Text('Modifica'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete),
                      SizedBox(width: 10),
                      Text('Elimina'),
                    ],
                  ),
                ),
              ],
              icon: const Icon(Icons.more_vert),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentWarningIndicator extends ConsumerWidget {
  final String studentId;
  final List<Map<String, dynamic>> documents;

  const _DocumentWarningIndicator({
    required this.studentId,
    required this.documents,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int missingDocs = 0;

    for (final doc in documents) {
      final docId = doc['id'].toString();
      final deliveriesAsync = ref.watch(documentDeliveriesProvider(docId));

      deliveriesAsync.when(
        loading: () {},
        error: (_, __) {},
        data: (deliveries) {
          final delivery = deliveries[studentId];
          if (delivery == null || delivery['receivedAt'] == null) {
            missingDocs++;
          }
        },
      );
    }

    if (missingDocs == 0) return const SizedBox();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? Colors.orange.shade900.withValues(alpha: 0.3) : Colors.orange.shade100;
    final iconColor = isDark ? Colors.orange.shade300 : Colors.orange.shade800;
    final textColor = isDark ? Colors.orange.shade300 : Colors.orange.shade800;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_rounded,
            color: iconColor,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            '$missingDocs ${missingDocs == 1 ? "doc" : "doc"}',
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// =========================
/// EMPTY STATE
/// =========================
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final iconColor = isDark ? Colors.grey.shade600 : Colors.grey.shade400;
    final textColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline,
            size: 70,
            color: iconColor,
          ),
          const SizedBox(height: 12),
          Text(
            'Nessun ragazzo presente',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}