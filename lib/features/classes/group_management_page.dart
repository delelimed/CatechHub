/// Pagina di gestione del gruppo (classe) in CateREG.
///
/// Consente al catechista di:
/// - Visualizzare e modificare il nome del proprio gruppo.
/// - Elencare i ragazzi assegnati con opzioni modifica/elimina.
/// - Aggiungere nuovi ragazzi tramite il FAB "Nuovo ragazzo".
///
/// Si basa su [classesStreamProvider] per ottenere la classe corrente
/// (filtrata per [AuthService.localUserId]) e su [StudentsRepository] per
/// leggere/scrivere i dati anagrafici dei ragazzi.
///
/// Navigazione CateREG: dalla scheda ragazzo si può andare a
/// [EditStudentPage] (modifica) o eliminare lo studente con conferma.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_service.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/student_model.dart';
import '../students/students_repository.dart';
import '../students/students_add_page.dart' hide classesRepoProvider;
import '../students/edit_student_page.dart' hide classesRepoProvider;
import 'classes_provider.dart';
//import 'classes_repository.dart';

class GroupManagementPage extends ConsumerWidget {
  const GroupManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(classesStreamProvider);
    final studentsRepo = ref.watch(Provider((r) => StudentsRepository()));
    const uid = AuthService.localUserId;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return classesAsync.when(
      loading: () => const AppScaffold(
        title: 'Gestione Gruppo',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => AppScaffold(
        title: 'Gestione Gruppo',
        child: Center(child: Text('Errore: $e')),
      ),
      data: (classes) {
        final myClass = classes.firstWhere(
          (c) => c.catechistIds.contains(uid),
          orElse: () =>
              SchoolClass(id: '', name: '', studentIds: [], catechistIds: []),
        );

        if (myClass.id.isEmpty) {
          return const AppScaffold(
            title: 'Gestione Gruppo',
            child: Center(child: Text('Nessun gruppo assegnato')),
          );
        }

        return AppScaffold(
          title: 'Gestione Gruppo',
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: isDark ? colorScheme.primary : const Color(0xFF174A7E),
            foregroundColor: isDark ? colorScheme.onPrimary : Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Nuovo ragazzo'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AddStudentPage(),
                ),
              ).then((_) {
                // ignore: unused_result
                ref.refresh(classesStreamProvider);
              });
            },
          ),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _GroupHeader(
                schoolClass: myClass,
                onNameChanged: () {
                  // ignore: unused_result
                  ref.refresh(classesStreamProvider);
                },
              ),
              const SizedBox(height: 20),
              _StudentsList(
                classId: myClass.id,
                studentIds: myClass.studentIds,
                studentsRepo: studentsRepo,
                isDark: isDark,
                colorScheme: colorScheme,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// =========================
/// GROUP HEADER
/// =========================
class _GroupHeader extends ConsumerWidget {
  final SchoolClass schoolClass;
  final VoidCallback onNameChanged;

  const _GroupHeader({
    required this.schoolClass,
    required this.onNameChanged,
  });

  void _showEditNameDialog(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: schoolClass.name);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? colorScheme.surface : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Modifica nome gruppo',
          style: TextStyle(color: isDark ? colorScheme.onSurface : Colors.black87),
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nome gruppo',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? colorScheme.primary : const Color(0xFF174A7E),
              foregroundColor: isDark ? colorScheme.onPrimary : Colors.white,
            ),
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final repo = ref.read(classesRepoProvider);
                try {
                  await repo.updateClass(
                    schoolClass.id,
                    schoolClass.copyWith(name: controller.text),
                  );
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                    onNameChanged();
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Errore: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  colorScheme.surfaceContainer,
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                ]
              : [
                  Colors.white,
                  Colors.blue.shade50.withValues(alpha: 0.3),
                ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.blue.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.groups_rounded,
              color: isDark ? colorScheme.onPrimary : Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schoolClass.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? colorScheme.onSurface : const Color(0xFF174A7E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap per modificare il nome',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit, color: isDark ? colorScheme.primary : const Color(0xFF174A7E)),
            onPressed: () => _showEditNameDialog(context, ref),
          ),
        ],
      ),
    );
  }
}

/// =========================
/// STUDENTS LIST
/// =========================
class _StudentsList extends StatelessWidget {
  final String classId;
  final List<String> studentIds;
  final StudentsRepository studentsRepo;
  final bool isDark;
  final ColorScheme colorScheme;

  const _StudentsList({
    required this.classId,
    required this.studentIds,
    required this.studentsRepo,
    required this.isDark,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Student>>(
      stream: studentsRepo.getAllStudents(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _EmptyState(isDark: isDark, colorScheme: colorScheme);
        }

        final allStudents = snapshot.data!;
        final classStudents = Student.sortedBySurname(
          allStudents.where((s) => studentIds.contains(s.id)),
        );

        if (classStudents.isEmpty) {
          return _EmptyState(isDark: isDark, colorScheme: colorScheme);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                'RAGAZZI (${classStudents.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: classStudents.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, index) {
                final student = classStudents[index];

                return _StudentCard(
                  student: student,
                  isDark: isDark,
                  colorScheme: colorScheme,
                  onEdit: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditStudentPage(student: student),
                      ),
                    );
                  },
                  onDelete: () {
                    _showDeleteConfirmation(context, student, classId);
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    Student student,
    String classId,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? colorScheme.surface : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Eliminare ragazzo?',
          style: TextStyle(color: isDark ? colorScheme.onSurface : Colors.black87),
        ),
        content: Text(
          'Sei sicuro di voler eliminare ${student.name} ${student.surname}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              studentsRepo.deleteStudent(student.id);
              Navigator.pop(context);
            },
            child: const Text('Elimina'),
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
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool isDark;
  final ColorScheme colorScheme;

  const _StudentCard({
    required this.student,
    required this.onEdit,
    required this.onDelete,
    required this.isDark,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final name = '${student.name} ${student.surname}';

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    colorScheme.surfaceContainer,
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  ]
                : [
                    Colors.white,
                    Colors.blue.shade50.withValues(alpha: 0.35),
                  ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.blue.shade100,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: isDark ? colorScheme.primary : const Color(0xFF174A7E),
              child: Text(
                student.name.isNotEmpty ? student.name[0] : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? colorScheme.onSurface : const Color(0xFF174A7E),
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit),
                      SizedBox(width: 10),
                      Text('Modifica'),
                    ],
                  ),
                ),
                PopupMenuItem(
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

/// =========================
/// EMPTY STATE
/// =========================
class _EmptyState extends StatelessWidget {
  final bool isDark;
  final ColorScheme colorScheme;

  const _EmptyState({
    required this.isDark,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline,
            size: 70,
            color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'Nessun ragazzo presente',
            style: TextStyle(
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
