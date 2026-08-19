import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_service.dart';
import '../../core/providers/current_class_provider.dart';
import '../../shared/models/class_model.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'classes_provider.dart';

class ViewGroupsPage extends ConsumerWidget {
  const ViewGroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(classesStreamProvider);
    const uid = AuthService.localUserId;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return AppScaffold(
      title: 'I miei gruppi',
      child: classesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (classes) {
          final myClasses = classes
              .where((c) => c.catechistIds.contains(uid))
              .toList();

          if (myClasses.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.groups_outlined,
                    size: 70,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Non fai parte di nessun gruppo',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 24),
                  _buildCreateButton(context, ref, isDark, colorScheme),
                ],
              ),
            );
          }

          final activeGroupId = ref.watch(currentClassProvider) ?? '';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...myClasses.map(
                (c) => _GroupCard(
                  schoolClass: c,
                  isActive: c.id == activeGroupId,
                  onTap: () async {
                    await ref
                        .read(currentClassProvider.notifier)
                        .setClass(c.id);
                    if (context.mounted) {
                      context.push('/settings/class-switcher');
                    }
                  },
                  onDelete: () async {
                    try {
                      await ref.read(classesRepoProvider).deleteClass(c.id);
                      // Se si eliminava la classe aperta, pulisce la selezione
                      await clearCurrentClassIfDeleted(ref, c.id);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Errore durante l\'eliminazione: $e'),
                            backgroundColor: Colors.red.shade700,
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
              const SizedBox(height: 24),
              _buildCreateButton(context, ref, isDark, colorScheme),
              const SizedBox(height: 12),
              _ActionCard(
                icon: Icons.swap_horiz_rounded,
                title: 'Cambia classe',
                subtitle: 'Seleziona una classe diversa',
                color: Colors.purple,
                isDark: isDark,
                onTap: () => context.push('/settings/class-switcher'),
              ),
              const SizedBox(height: 12),
              _ActionCard(
                icon: Icons.copy_all_rounded,
                title: 'Copia da altra classe',
                subtitle: 'Copia contenuti senza associazioni ai ragazzi',
                color: Colors.teal,
                isDark: isDark,
                onTap: () => context.push('/settings/class-copy'),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCreateButton(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: ElevatedButton.icon(
        onPressed: () =>
            _showCreateClassDialog(context, ref, isDark, colorScheme),
        icon: const Icon(Icons.add),
        label: const Text('Crea nuovo gruppo'),
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark
              ? colorScheme.primary
              : const Color(0xFF174A7E),
          foregroundColor: isDark ? colorScheme.onPrimary : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  void _showCreateClassDialog(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? colorScheme.surface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Nuovo gruppo',
          style: TextStyle(
            color: Color(0xFF174A7E),
            fontWeight: FontWeight.bold,
          ),
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
              backgroundColor: isDark
                  ? colorScheme.primary
                  : const Color(0xFF174A7E),
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
                await ref
                    .read(classesRepoProvider)
                    .addClass(
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

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final cardColor = isDark ? colorScheme.surfaceContainer : Colors.white;
    final iconBgColor = color.withValues(alpha: isDark ? 0.2 : 0.10);
    final titleColor = isDark ? colorScheme.onSurface : const Color(0xFF1A1A1A);
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final borderColor = isDark
        ? colorScheme.outline.withValues(alpha: 0.2)
        : Colors.transparent;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.4)
        : Colors.black.withValues(alpha: 0.04);

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
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

class _GroupCard extends StatelessWidget {
  final SchoolClass schoolClass;
  final bool isActive;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  const _GroupCard({
    required this.schoolClass,
    this.isActive = false,
    this.onDelete,
    this.onTap,
  });

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Elimina gruppo'),
        content: Text(
          'Sei sicuro di voler eliminare "${schoolClass.name}"?\n\n'
          'Verranno eliminati anche i piani di incontro e le presenze associati.',
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
              Navigator.pop(context);
              onDelete?.call();
            },
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final cardColor = isDark ? colorScheme.surfaceContainer : Colors.white;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.4)
        : Colors.black.withValues(alpha: 0.04);
    final borderColor = isDark
        ? colorScheme.outline.withValues(alpha: 0.2)
        : Colors.blue.shade100;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.groups_rounded,
                color: isDark ? colorScheme.onPrimary : Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schoolClass.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? colorScheme.onSurface
                          : const Color(0xFF174A7E),
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
            if (onDelete != null && !isActive)
              PopupMenuButton<String>(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (value) {
                  if (value == 'delete') {
                    _showDeleteConfirmation(context);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'delete', child: Text('Elimina')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
