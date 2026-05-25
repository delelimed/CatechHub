import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_service.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/student_model.dart';
import '../students/students_repository.dart';
import '../students/students_add_page.dart' hide classesRepoProvider;
import '../students/edit_student_page.dart';
import 'classes_provider.dart';
import 'classes_repository.dart';

class GroupManagementPage extends ConsumerWidget {
  const GroupManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(classesStreamProvider);
    final studentsRepo = ref.watch(Provider((r) => StudentsRepository()));
    const uid = AuthService.localUserId;

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
              ).then((_) {
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
                  ref.refresh(classesStreamProvider);
                },
              ),
              const SizedBox(height: 20),
              _StudentsList(
                classId: myClass.id,
                studentIds: myClass.studentIds,
                studentsRepo: studentsRepo,
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
    final controller = TextEditingController(text: schoolClass.name);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Modifica nome gruppo'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nome gruppo',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF174A7E),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final repo = ref.read(classesRepoProvider);
                try {
                  await repo.updateClass(
                    schoolClass.id,
                    schoolClass.copyWith(name: controller.text),
                  );
                  if (context.mounted) {
                    onNameChanged();
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context);
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            Colors.blue.shade50.withOpacity(0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.blue.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
              color: const Color(0xFF174A7E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.groups_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schoolClass.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF174A7E),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tap per modificare il nome',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: Color(0xFF174A7E)),
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

  const _StudentsList({
    required this.classId,
    required this.studentIds,
    required this.studentsRepo,
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
          return _EmptyState();
        }

        final allStudents = snapshot.data!;
        final classStudents = allStudents
            .where((s) => studentIds.contains(s.id))
            .toList();

        if (classStudents.isEmpty) {
          return _EmptyState();
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
                  color: Colors.grey.shade600,
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
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Eliminare ragazzo?'),
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

  const _StudentCard({
    required this.student,
    required this.onEdit,
    required this.onDelete,
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
            colors: [
              Colors.white,
              Colors.blue.shade50.withOpacity(0.35),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.blue.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: const Color(0xFF174A7E),
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF174A7E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Madre: ${student.motherName} ${student.motherSurname}',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Padre: ${student.fatherName} ${student.fatherSurname}',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 13,
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
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline,
            size: 70,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'Nessun ragazzo presente',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
