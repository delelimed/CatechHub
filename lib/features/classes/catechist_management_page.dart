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

class _CatechistGroup {
  final String displayName;
  final int deviceCount;
  final bool isLocalUser;
  final List<String> deviceIds;

  const _CatechistGroup({
    required this.displayName,
    required this.deviceCount,
    required this.isLocalUser,
    required this.deviceIds,
  });
}

class _ManageCatechistsPageState extends ConsumerState<ManageCatechistsPage> {
  late SchoolClass _currentClass;
  final _security = P2PSecurityService();
  List<_CatechistGroup> _groups = [];
  bool _loadingNames = true;

  @override
  void initState() {
    super.initState();
    _currentClass = widget.schoolClass;
    _resolveGroups().catchError((_) {
      if (mounted) {
        setState(() => _loadingNames = false);
      }
    });
  }

  Future<void> _resolveGroups() async {
    try {
      final ids = _currentClass.catechistIds;
      if (ids.isEmpty) {
        if (mounted) setState(() => _loadingNames = false);
        return;
      }

      final results = await Future.wait(
        ids.map((id) => _resolveDeviceInfo(id)),
        cleanUp: (_) {},
      );

      if (mounted) {
        setState(() {
          _groups = _buildGroups(results);
          _loadingNames = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingNames = false);
      }
    }
  }

  Future<_DeviceInfo> _resolveDeviceInfo(String id) async {
    try {
      if (id == AuthService.localUserId) {
        return _DeviceInfo(
          id: id,
          displayName: AuthService.localUserName,
          isLocalUser: true,
          isMioDispositivo: false,
        );
      }
    } catch (_) {
      // fall through
    }
    try {
      final assoc = await _security.getAssociation(id).timeout(
        const Duration(seconds: 5),
      );
      if (assoc != null && assoc.remoteRole == 'mioDispositivo') {
        return _DeviceInfo(
          id: id,
          displayName: assoc.deviceName.isNotEmpty ? assoc.deviceName : id,
          isLocalUser: false,
          isMioDispositivo: true,
        );
      }
      if (assoc != null && assoc.deviceName.isNotEmpty) {
        return _DeviceInfo(
          id: id,
          displayName: assoc.deviceName,
          isLocalUser: false,
          isMioDispositivo: false,
        );
      }
    } catch (_) {
      // fall through
    }
    return _DeviceInfo(
      id: id,
      displayName: id,
      isLocalUser: false,
      isMioDispositivo: false,
    );
  }

  List<_CatechistGroup> _buildGroups(List<_DeviceInfo> devices) {
    final mioDispositivo = <_DeviceInfo>[];
    final altri = <_DeviceInfo>[];

    for (final d in devices) {
      if (d.isLocalUser) {
        altri.add(d);
      } else if (d.isMioDispositivo) {
        mioDispositivo.add(d);
      } else {
        altri.add(d);
      }
    }

    final groups = <_CatechistGroup>[];
    final grouped = <String, List<_DeviceInfo>>{};

    for (final d in altri) {
      grouped.putIfAbsent(d.displayName, () => []).add(d);
    }

    var hasLocalUser = false;

    for (final entry in grouped.entries) {
      final devs = entry.value;
      final isLocal = devs.any((d) => d.isLocalUser);
      final allIds = devs.map((d) => d.id).toList();

      if (isLocal) hasLocalUser = true;

      int extraDeviceCount = 0;
      if (isLocal) {
        extraDeviceCount = mioDispositivo.length;
      }

      final displayName = isLocal
          ? '${AuthService.localUserName} (tu)'
          : entry.key;

      groups.add(_CatechistGroup(
        displayName: displayName,
        deviceCount: devs.length + extraDeviceCount,
        isLocalUser: isLocal,
        deviceIds: allIds,
      ));
    }

    if (!hasLocalUser) {
      for (final d in mioDispositivo) {
        groups.add(_CatechistGroup(
          displayName: d.displayName,
          deviceCount: 1,
          isLocalUser: false,
          deviceIds: [d.id],
        ));
      }
    }

    return groups;
  }

  Future<void> _removeGroup(_CatechistGroup group) async {
    final repo = ref.read(classesRepoProvider);
    var updatedIds = List<String>.from(_currentClass.catechistIds);
    for (final id in group.deviceIds) {
      updatedIds.remove(id);
    }
    try {
      await repo.updateClass(
        _currentClass.id,
        _currentClass.copyWith(catechistIds: updatedIds),
      );
      if (mounted) {
        setState(() {
          _currentClass = _currentClass.copyWith(catechistIds: updatedIds);
          _groups = _groups.where((g) => g != group).toList();
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

    return AppScaffold(
      title: 'Catechisti — ${_currentClass.name}',
      child: _loadingNames
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
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
                            ? 'CATECHISTI (${_groups.length})'
                            : 'CATECHISTI (${_groups.length}) — SOLA LETTURA',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                    ),
                    ..._groups.map((group) => _CatechistCard(
                          displayName: group.displayName,
                          deviceCount: group.deviceCount,
                          isLocalUser: group.isLocalUser,
                          isDark: isDark,
                          colorScheme: colorScheme,
                          onRemove: canManage && !group.isLocalUser
                              ? () async {
                                  final label = group.deviceCount > 1
                                      ? '${group.displayName} (${group.deviceCount} dispositivi)'
                                      : group.displayName;
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: isDark ? colorScheme.surface : Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      title: const Text('Rimuovere catechista?'),
                                      content: Text('Rimuovere $label da questo gruppo?'),
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
                                    await _removeGroup(group);
                                  }
                                }
                              : null,
                        )),
                  ],
                ),
    );
  }
}

class _DeviceInfo {
  final String id;
  final String displayName;
  final bool isLocalUser;
  final bool isMioDispositivo;

  const _DeviceInfo({
    required this.id,
    required this.displayName,
    required this.isLocalUser,
    required this.isMioDispositivo,
  });
}

class _CatechistCard extends StatelessWidget {
  final String displayName;
  final int deviceCount;
  final bool isLocalUser;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback? onRemove;

  const _CatechistCard({
    required this.displayName,
    required this.deviceCount,
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
                    deviceCount > 1
                        ? 'Sei tu — $deviceCount dispositivi'
                        : 'Sei tu',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                    ),
                  )
                else if (deviceCount > 1)
                  Text(
                    '$deviceCount dispositivi',
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
