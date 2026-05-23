import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/models/class_model.dart';
import 'classes_provider.dart';
import 'class_detail_page.dart';

class ClassesPage extends ConsumerWidget {
  const ClassesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(classesStreamProvider);

    return classesAsync.when(
      data: (classes) {
        final isFirstUser = classes.length == 1 &&
            classes[0].catechistIds.contains(AuthService.localUserId) &&
            classes[0].catechistIds.length == 1;

        return AppScaffold(
          title: 'Gruppi',
          floatingActionButton: isFirstUser
              ? null
              : FloatingActionButton.extended(
                  backgroundColor: const Color(0xFF174A7E),
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'Nuova classe',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => _showAddClass(context, ref),
                ),
          child: classes.isEmpty
              ? const _EmptyState(
                  icon: Icons.groups_rounded,
                  title: 'Nessuna classe',
                  subtitle: 'Crea la prima classe per iniziare.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: classes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, index) {
                    final c = classes[index];
                    final canEditOnly = isFirstUser && index == 0;

                    return _ClassCard(
                      name: c.name,
                      students: c.studentIds.length,
                      catechists: c.catechistIds.length,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ClassDetailPage(classId: c.id),
                          ),
                        );
                      },
                      onDelete: canEditOnly
                          ? null
                          : () {
                              ref.read(classesRepoProvider).deleteClass(c.id);
                            },
                      canEditOnly: canEditOnly,
                      classId: c.id,
                      className: c.name,
                      onEditName: canEditOnly
                          ? (newName) {
                              ref.read(classesRepoProvider).updateClass(
                                    c.id,
                                    c.copyWith(name: newName),
                                  );
                            }
                          : null,
                    );
                  },
                ),
        );
      },
      loading: () => const AppScaffold(
        title: 'Gruppi',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => AppScaffold(
        title: 'Gruppi',
        child: Center(child: Text('Errore: $e')),
      ),
    );
  }

  void _showAddClass(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Nuova classe'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nome classe',
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
              await ref.read(classesRepoProvider).addClass(
                    SchoolClass(
                      id: '',
                      name: controller.text,
                      catechistIds: [],
                      studentIds: [],
                    ),
                  );

              Navigator.pop(context);
            },
            child: const Text('Crea'),
          ),
        ],
      ),
    );
  }
}

/// =========================
/// CLASS CARD
/// =========================
class _ClassCard extends StatelessWidget {
  final String name;
  final int students;
  final int catechists;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool canEditOnly;
  final String classId;
  final String className;
  final Function(String)? onEditName;

  const _ClassCard({
    required this.name,
    required this.students,
    required this.catechists,
    required this.onTap,
    this.onDelete,
    this.canEditOnly = false,
    required this.classId,
    required this.className,
    this.onEditName,
  });

  void _showEditNameDialog(BuildContext context) {
    final controller = TextEditingController(text: name);

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
            onPressed: () {
              if (controller.text.isNotEmpty) {
                onEditName?.call(controller.text);
              }
              Navigator.pop(context);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white,
              Colors.blue.shade50.withOpacity(0.35),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
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
            /// ICON
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

            const SizedBox(width: 14),

            /// INFO
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

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      _Pill(
                        icon: Icons.person,
                        text: '$students ragazzi',
                      ),
                      const SizedBox(width: 8),
                      _Pill(
                        icon: Icons.school,
                        text: '$catechists catechisti',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            /// MENU
            if (canEditOnly)
              PopupMenuButton<String>(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (value) {
                  if (value == 'edit') {
                    _showEditNameDialog(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text('Modifica nome'),
                  ),
                ],
              )
            else
              PopupMenuButton<String>(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (value) {
                  if (value == 'delete') {
                    onDelete?.call();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Elimina'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// =========================
/// PILL
/// =========================
class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Pill({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
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
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 44,
                color: const Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}