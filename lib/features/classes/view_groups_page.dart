import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_service.dart';
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...myClasses.map((c) => _GroupCard(schoolClass: c)),
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

  const _GroupCard({required this.schoolClass});

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
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.person, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Creato da: ${schoolClass.lastModifiedBy.isNotEmpty ? schoolClass.lastModifiedBy : 'Sconosciuto'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey.shade400 : Colors.grey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
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
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: isDark ? Colors.grey.shade500 : Colors.grey.shade400),
        ],
      ),
    );
  }
}
