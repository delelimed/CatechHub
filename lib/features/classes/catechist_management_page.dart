import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_service.dart';
import '../../features/sync/p2p/p2p_security_service.dart';
import '../../shared/models/class_model.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'classes_provider.dart';

class ManageCatechistsPage extends ConsumerStatefulWidget {
  final SchoolClass schoolClass;

  const ManageCatechistsPage({super.key, required this.schoolClass});

  @override
  ConsumerState<ManageCatechistsPage> createState() => _ManageCatechistsPageState();
}

class _ManageCatechistsPageState extends ConsumerState<ManageCatechistsPage> {
  late SchoolClass _currentClass;
  final _security = P2PSecurityService();
  final Map<String, String> _resolvedNames = {};
  bool _loadingNames = true;

  @override
  void initState() {
    super.initState();
    _currentClass = widget.schoolClass;
    _resolveNames().catchError((_) {
      if (mounted) {
        setState(() => _loadingNames = false);
      }
    });
  }

  Future<void> _resolveNames() async {
    try {
      final ids = _currentClass.catechistIds;
      final names = <String, String>{};
      for (final id in ids) {
        if (id == AuthService.localUserId) {
          try {
            names[id] = '${AuthService.localUserName} (tu)';
          } catch (_) {
            names[id] = '${id} (tu)';
          }
        } else {
          try {
            final assoc = await _security.getAssociation(id);
            if (assoc != null && assoc.deviceName.isNotEmpty) {
              names[id] = assoc.deviceName;
            } else {
              names[id] = id;
            }
          } catch (_) {
            names[id] = id;
          }
        }
      }
      if (mounted) {
        setState(() {
          _resolvedNames.addAll(names);
          _loadingNames = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingNames = false);
      }
    }
  }

  Future<void> _removeCatechist(String catechistId) async {
    try {
      final repo = ref.read(classesRepoProvider);
      await repo.removeCatechistFromClass(_currentClass.id, catechistId);
      if (mounted) {
        setState(() {
          _currentClass = _currentClass.copyWith(
            catechistIds: _currentClass.catechistIds.where((id) => id != catechistId).toList(),
          );
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Errore durante la rimozione del catechista')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final canManage = !_currentClass.nameLocked;

    final ids = _currentClass.catechistIds;

    return AppScaffold(
      title: 'Catechisti — ${_currentClass.name}',
      child: _loadingNames
          ? const Center(child: CircularProgressIndicator())
          : ids.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_off_outlined,
                        size: 70,
                        color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Nessun catechista associato',
                        style: TextStyle(
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 12),
                      child: Text(
                        canManage
                            ? 'CATECHISTI (${ids.length})'
                            : 'CATECHISTI (${ids.length}) — SOLA LETTURA',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                    ),
                    ...ids.map((id) => _CatechistCard(
                          catechistId: id,
                          displayName: _resolvedNames[id] ?? id,
                          isLocalUser: id == AuthService.localUserId,
                          isDark: isDark,
                          colorScheme: colorScheme,
                          onRemove: canManage && id != AuthService.localUserId
                              ? () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: isDark ? colorScheme.surface : Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      title: Text(
                                        'Rimuovere catechista?',
                                        style: TextStyle(
                                          color: isDark ? colorScheme.onSurface : Colors.black87,
                                        ),
                                      ),
                                      content: Text(
                                        'Rimuovere "${_resolvedNames[id] ?? id}" da questo gruppo?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('Annulla'),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                          ),
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text('Rimuovi'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    await _removeCatechist(id);
                                  }
                                }
                              : null,
                        )),
                  ],
                ),
    );
  }
}

class _CatechistCard extends StatelessWidget {
  final String catechistId;
  final String displayName;
  final bool isLocalUser;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback? onRemove;

  const _CatechistCard({
    required this.catechistId,
    required this.displayName,
    required this.isLocalUser,
    required this.isDark,
    required this.colorScheme,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
            backgroundColor: isLocalUser
                ? Colors.green
                : (isDark ? colorScheme.primary : const Color(0xFF174A7E)),
            child: Icon(
              isLocalUser ? Icons.person : Icons.devices,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? colorScheme.onSurface : const Color(0xFF174A7E),
                  ),
                ),
                if (isLocalUser)
                  Text(
                    'Sei tu',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
              tooltip: 'Rimuovi catechista',
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}
