import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_service.dart';
import '../../core/providers/current_class_provider.dart';
import '../../shared/models/class_model.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'classes_provider.dart';

class ClassSwitcherPage extends ConsumerWidget {
  const ClassSwitcherPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myClasses = ref.watch(myClassesProvider);
    final currentClassId = ref.watch(currentClassProvider);
    final currentClassNotifier = ref.read(currentClassProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return AppScaffold(
      title: 'Cambia classe',
      child: Builder(
        builder: (context) {
          if (myClasses.isEmpty) {
            return _EmptyState(
              isDark: isDark,
              colorScheme: colorScheme,
              onCreateClass: () => _showCreateClassDialog(context, ref, isDark, colorScheme),
              onOpenGroups: () => context.push('/view-groups'),
            );
          }

          final currentName = myClasses
              .firstWhere((c) => c.id == currentClassId, orElse: () => SchoolClass(id: '', name: '', studentIds: [], catechistIds: []))
              .name;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Classe attuale: ${currentName.isNotEmpty ? currentName : 'Nessuna'}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ...myClasses.map((c) => _ClassCard(
                schoolClass: c,
                isDark: isDark,
                colorScheme: colorScheme,
                isSelected: c.id == currentClassId,
                onTap: () async {
                  if (c.id != currentClassId) {
                    await currentClassNotifier.setClass(c.id);
                    if (context.mounted) {
                      context.go('/');
                    }
                  }
                },
              )),
              const SizedBox(height: 16),
              _CreateClassButton(
                isDark: isDark,
                colorScheme: colorScheme,
                onTap: () => _showCreateClassDialog(context, ref, isDark, colorScheme),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  void _showCreateClassDialog(
      BuildContext context, WidgetRef ref, bool isDark, ColorScheme colorScheme) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? colorScheme.surface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Nuovo gruppo',
          style: TextStyle(color: Color(0xFF174A7E), fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nome del gruppo',
            hintText: 'Es. Prima elementare',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? colorScheme.primary : const Color(0xFF174A7E),
              foregroundColor: isDark ? colorScheme.onPrimary : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.of(ctx).pop();
              try {
                await ref.read(classesRepoProvider).addClass(
                      SchoolClass(
                        id: '',
                        name: name,
                        studentIds: [],
                        catechistIds: [AuthService.localUserId],
                      ),
                    );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Errore durante la creazione: $e'),
                      backgroundColor: Colors.red.shade700,
                    ),
                  );
                }
              }
            },
            child: const Text('Crea'),
          ),
        ],
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final SchoolClass schoolClass;
  final bool isDark;
  final ColorScheme colorScheme;
  final bool isSelected;
  final VoidCallback onTap;

  const _ClassCard({
    required this.schoolClass,
    required this.isDark,
    required this.colorScheme,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? colorScheme.primaryContainer.withValues(alpha: 0.3) : const Color(0xFF174A7E).withValues(alpha: 0.1))
              : (isDark ? colorScheme.surfaceContainer : Colors.white),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected
                ? (isDark ? colorScheme.primary : const Color(0xFF174A7E))
                : (isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.blue.shade100),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark ? colorScheme.primary : const Color(0xFF174A7E))
                    : (isDark ? colorScheme.primary : const Color(0xFF174A7E)).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.groups_rounded,
                color: isSelected
                    ? (isDark ? colorScheme.onPrimary : Colors.white)
                    : (isDark ? colorScheme.primary : const Color(0xFF174A7E)),
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
                      color: isSelected
                          ? (isDark ? colorScheme.onPrimary : const Color(0xFF174A7E))
                          : (isDark ? colorScheme.onSurface : const Color(0xFF174A7E)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.people, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        '${schoolClass.studentIds.length} ragazzi',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey.shade400 : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.school, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        '${schoolClass.catechistIds.length} catechisti',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey.shade400 : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
                size: 24,
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback onCreateClass;
  final VoidCallback onOpenGroups;

  const _EmptyState({
    required this.isDark,
    required this.colorScheme,
    required this.onCreateClass,
    required this.onOpenGroups,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined, size: 70, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Non fai parte di nessun gruppo',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Puoi creare un nuovo gruppo qui sotto.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 24),
          _CreateClassButton(
            isDark: isDark,
            colorScheme: colorScheme,
            onTap: onCreateClass,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onOpenGroups,
            icon: const Icon(Icons.groups_rounded),
            label: const Text('Vai a "I miei gruppi"'),
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? colorScheme.primary : const Color(0xFF174A7E),
              side: BorderSide(
                color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateClassButton extends StatelessWidget {
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _CreateClassButton({
    required this.isDark,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add),
        label: const Text('Crea nuovo gruppo'),
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? colorScheme.primary : const Color(0xFF174A7E),
          foregroundColor: isDark ? colorScheme.onPrimary : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}