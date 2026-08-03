import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                  _buildCreateButton(context, isDark, colorScheme),
                ],
              ),
            );
          }

          final activeGroupId = ref.watch(currentClassProvider) ?? '';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...myClasses.map((c) => _GroupCard(
                schoolClass: c,
                isActive: c.id == activeGroupId,
                onDelete: () async {
                  try {
                    await ref.read(classesRepoProvider).deleteClass(c.id);
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
              )),
              const SizedBox(height: 24),
              _buildCreateButton(context, isDark, colorScheme),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCreateButton(BuildContext context, bool isDark, ColorScheme colorScheme) {
    return Center(
      child: ElevatedButton.icon(
        onPressed: () => _showComingSoonDialog(context, isDark, colorScheme),
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

  void _showComingSoonDialog(BuildContext context, bool isDark, ColorScheme colorScheme) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? colorScheme.surface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction_rounded, size: 56, color: Colors.orange.shade400),
            const SizedBox(height: 20),
            Text(
              'Prossimamente in CatechHub 2.0',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? colorScheme.onSurface : const Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Il supporto multi-classe sarà disponibile\n'
              'a partire dall\'anno catechistico 2027/2028.\n\n'
              'Questa funzionalità ti permetterà di gestire\n'
              'più gruppi contemporaneamente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? colorScheme.primary : const Color(0xFF174A7E),
              foregroundColor: isDark ? colorScheme.onPrimary : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Ho capito'),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final SchoolClass schoolClass;
  final bool isActive;
  final VoidCallback? onDelete;

  const _GroupCard({required this.schoolClass, this.isActive = false, this.onDelete});

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
    final borderColor = isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.blue.shade100;

    return Container(
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
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Elimina'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
