import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/current_class_provider.dart';
import '../../shared/models/class_model.dart';
import '../../shared/widgets/app_scaffold.dart';

class ClassSelectionPage extends ConsumerWidget {
  const ClassSelectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myClasses = ref.watch(myClassesProvider);
    final currentClassNotifier = ref.read(currentClassProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return AppScaffold(
      title: 'Scegli una classe',
      child: Builder(
        builder: (context) {
          if (myClasses.isEmpty) {
            return _EmptyState(
              isDark: isDark,
              colorScheme: colorScheme,
              onCreateClass: () => context.push('/group-management'),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Tocca una classe per accedere',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ...myClasses.map((c) => _ClassCard(
                schoolClass: c,
                isDark: isDark,
                colorScheme: colorScheme,
                onTap: () async {
                  await currentClassNotifier.setClass(c.id);
                  if (context.mounted) context.go('/');
                },
              )),
              const SizedBox(height: 24),
              _CreateClassButton(
                isDark: isDark,
                colorScheme: colorScheme,
                onTap: () => context.push('/group-management'),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final SchoolClass schoolClass;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _ClassCard({
    required this.schoolClass,
    required this.isDark,
    required this.colorScheme,
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
          color: isDark ? colorScheme.surfaceContainer : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.blue.shade100,
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

  const _EmptyState({
    required this.isDark,
    required this.colorScheme,
    required this.onCreateClass,
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
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onCreateClass,
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
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add),
        label: const Text('Crea nuovo gruppo'),
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
    );
  }
}