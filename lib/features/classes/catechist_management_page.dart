import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_service.dart';
import '../../core/storage/local_database.dart';
import '../../features/sync/p2p/p2p_security_service.dart';
import '../../shared/models/catechist_profile.dart';
import '../../shared/models/class_model.dart';
import '../../shared/utils/auth_utils.dart';
import 'classes_provider.dart';

class ManageCatechistsPage extends ConsumerStatefulWidget {
  final SchoolClass schoolClass;

  const ManageCatechistsPage({super.key, required this.schoolClass});

  @override
  ConsumerState<ManageCatechistsPage> createState() =>
      _ManageCatechistsPageState();
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

  CatechistProfile? _getProfileSync(String catechistId) {
    try {
      final box = LocalDatabase.catechists();
      final raw = box.get(catechistId);
      if (raw == null) return null;
      return CatechistProfile.fromMap(
          catechistId, LocalDatabase.toStringDynamicMap(raw));
    } catch (_) {
      return null;
    }
  }

  Future<P2PDeviceAssociation?> _findAssociationByCatechistId(
      String catechistId) async {
    try {
      final all = await _security.getAllAssociations();
      for (final a in all) {
        if (a.catechistId == catechistId) return a;
      }
    } catch (_) {}
    return null;
  }

  String _prettyFromCatId(String catId) {
    // cat_gbyhug_9450322d -> "Gby Hug" approx, or fallback
    try {
      final without = catId.replaceFirst('cat_', '');
      final parts = without.split('_');
      if (parts.isNotEmpty && parts.first.length > 2) {
        final p = parts.first;
        return p[0].toUpperCase() + p.substring(1);
      }
    } catch (_) {}
    return catId;
  }

  Future<_DeviceInfo> _resolveDeviceInfo(String id) async {
    // 1) Legacy constant local_catechist_id -> risolvi con Auth locale
    if (id == AuthService.localUserId) {
      final localCat = AuthService.getCatechistId();
      final profile = _getProfileSync(localCat);
      final name = profile?.fullName.isNotEmpty == true
          ? profile!.fullName
          : (getCurrentCatechistName().trim().isNotEmpty
              ? getCurrentCatechistName()
              : AuthService.localUserName);
      return _DeviceInfo(
        id: id,
        logicalId: localCat,
        displayName: name,
        isLocalUser: true,
        isMioDispositivo: false,
      );
    }

    // 2) CatechistId stabile (cat_...) -> prova rubrica
    if (id.startsWith('cat_')) {
      final profile = _getProfileSync(id);
      if (profile != null && profile.fullName.trim().isNotEmpty) {
        final isLocal = id == AuthService.getCatechistId();
        return _DeviceInfo(
          id: id,
          logicalId: id,
          displayName: profile.fullName,
          isLocalUser: isLocal,
          isMioDispositivo: false,
        );
      }
      // Fallback: cerca associazione per catechistId
      try {
        final assoc = await _findAssociationByCatechistId(id)
            .timeout(const Duration(seconds: 2));
        if (assoc != null && assoc.deviceName.trim().isNotEmpty) {
          final isLocal = id == AuthService.getCatechistId();
          return _DeviceInfo(
            id: id,
            logicalId: id,
            displayName: assoc.deviceName,
            isLocalUser: isLocal,
            isMioDispositivo: assoc.remoteRole == 'mioDispositivo',
          );
        }
      } catch (_) {}
      // Prettify cat id
      final isLocal = id == AuthService.getCatechistId();
      return _DeviceInfo(
        id: id,
        logicalId: id,
        displayName: _prettyFromCatId(id),
        isLocalUser: isLocal,
        isMioDispositivo: false,
      );
    }

    // 3) DeviceId (CH_...) -> associazione diretta
    try {
      final assoc = await _security
          .getAssociation(id)
          .timeout(const Duration(seconds: 2));
      if (assoc != null) {
        final logical = (assoc.catechistId != null &&
                assoc.catechistId!.isNotEmpty)
            ? assoc.catechistId!
            : id;
        // Se l'associazione ha un catechistId con profilo, preferisci il profilo
        if (assoc.catechistId != null && assoc.catechistId!.isNotEmpty) {
          final p = _getProfileSync(assoc.catechistId!);
          if (p != null && p.fullName.trim().isNotEmpty) {
            return _DeviceInfo(
              id: id,
              logicalId: logical,
              displayName: p.fullName,
              isLocalUser: false,
              isMioDispositivo: assoc.remoteRole == 'mioDispositivo',
            );
          }
        }
        if (assoc.deviceName.trim().isNotEmpty) {
          return _DeviceInfo(
            id: id,
            logicalId: logical,
            displayName: assoc.deviceName,
            isLocalUser: false,
            isMioDispositivo: assoc.remoteRole == 'mioDispositivo',
          );
        }
      }
    } catch (_) {}

    // Fallback finale: mostra ID ma mai vuoto
    return _DeviceInfo(
      id: id,
      logicalId: id,
      displayName: id,
      isLocalUser: false,
      isMioDispositivo: false,
    );
  }

  List<_CatechistGroup> _buildGroups(List<_DeviceInfo> devices) {
    final mioDispositivo = <_DeviceInfo>[];
    final altri = <_DeviceInfo>[];

    for (final d in devices) {
      if (d.isMioDispositivo) {
        mioDispositivo.add(d);
      } else {
        altri.add(d);
      }
    }

    final groups = <_CatechistGroup>[];
    // Raggruppa per logicalId (catechistId stabile), non per displayName,
    // per evitare collisioni su omonimi.
    final grouped = <String, List<_DeviceInfo>>{};

    for (final d in altri) {
      grouped.putIfAbsent(d.logicalId, () => []).add(d);
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

      // Usa il displayName già risolto (nome cognome), non l'ID.
      final baseName = devs.first.displayName;
      final displayName = isLocal ? '$baseName (tu)' : baseName;

      groups.add(
        _CatechistGroup(
          displayName: displayName,
          deviceCount: devs.length + extraDeviceCount,
          isLocalUser: isLocal,
          deviceIds: allIds,
        ),
      );
    }

    if (!hasLocalUser && mioDispositivo.isNotEmpty) {
      // Caso locale solo come mioDispositivo senza entry in altri
      for (final d in mioDispositivo) {
        groups.add(
          _CatechistGroup(
            displayName: '${d.displayName} (tu)',
            deviceCount: 1,
            isLocalUser: true,
            deviceIds: [d.id],
          ),
        );
      }
    } else if (!hasLocalUser) {
      for (final d in mioDispositivo) {
        groups.add(
          _CatechistGroup(
            displayName: d.displayName,
            deviceCount: 1,
            isLocalUser: false,
            deviceIds: [d.id],
          ),
        );
      }
    }

    // Ordina: tu per primo, poi alfabetico
    groups.sort((a, b) {
      if (a.isLocalUser && !b.isLocalUser) return -1;
      if (!a.isLocalUser && b.isLocalUser) return 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

    return groups;
  }

  Future<void> _removeGroup(_CatechistGroup group) async {
    final repo = ref.read(classesRepoProvider);
    // Rimuove da tutte le strutture roster (non solo catechistIds)
    var updatedIds = List<String>.from(_currentClass.catechistIds);
    var updatedAssociated =
        List<String>.from(_currentClass.associatedCatechistIds);
    var updatedRoles = Map<String, String>.from(_currentClass.catechistRoles);
    var updatedCounts =
        Map<String, int>.from(_currentClass.catechistDeviceCounts);

    for (final id in group.deviceIds) {
      updatedIds.remove(id);
      updatedAssociated.remove(id);
      updatedRoles.remove(id);
      updatedCounts.remove(id);
      // Gestisce anche il caso legacy local_catechist_id -> rimuove il cat locale
      if (id == AuthService.localUserId) {
        final localCat = AuthService.getCatechistId();
        updatedIds.remove(localCat);
        updatedAssociated.remove(localCat);
        updatedRoles.remove(localCat);
        updatedCounts.remove(localCat);
      }
    }
    // Se l'id rimosso è un cat, rimuovi anche eventuali deviceIds legacy associati
    // e viceversa, per pulizia completa.

    try {
      await repo.updateClass(
        _currentClass.id,
        _currentClass.copyWith(
          catechistIds: updatedIds,
          associatedCatechistIds: updatedAssociated,
          catechistRoles: updatedRoles,
          catechistDeviceCounts: updatedCounts,
        ),
      );
      if (mounted) {
        setState(() {
          _currentClass = _currentClass.copyWith(
            catechistIds: updatedIds,
            associatedCatechistIds: updatedAssociated,
            catechistRoles: updatedRoles,
            catechistDeviceCounts: updatedCounts,
          );
          _groups = _groups.where((g) => g != group).toList();
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Errore durante la rimozione del catechista'),
          ),
        );
      }
    }
  }

  Future<void> _showAddOfflineCatechistDialog() async {
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: isDark ? cs.surface : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Aggiungi catechista senza app'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Inserisci nome e cognome del catechista che collabora ma non usa l\'app. Verrà incluso correttamente nel report PDF.',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                        height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: firstCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Nome *',
                      prefixIcon: const Icon(Icons.person_rounded),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: lastCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Cognome *',
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Telefono (facoltativo)',
                      prefixIcon: const Icon(Icons.phone_rounded),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Aggiungi'),
            ),
          ],
        );
      },
    );

    if (result != true) return;
    final first = firstCtrl.text.trim();
    final last = lastCtrl.text.trim();
    final phone = phoneCtrl.text.trim();

    // Genera catechistId stabile deterministico
    final catId = AuthService.generateCatechistId(first, last, phone);

    // Verifica duplicato
    if (_currentClass.catechistIds.contains(catId) ||
        _currentClass.associatedCatechistIds.contains(catId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$first $last è già nel gruppo.')),
      );
      return;
    }

    // Crea profilo offline (bypass canManage, scrittura diretta Hive)
    final profile = CatechistProfile(
      id: catId,
      firstName: first,
      lastName: last,
      phone: phone,
    );
    try {
      final box = LocalDatabase.catechists();
      await box.put(catId, profile.toMap());
      await box.flush();
    } catch (_) {
      // Se il box non è disponibile, procedi comunque con l'aggiunta alla classe
    }

    // Aggiunge al roster classe
    final repo = ref.read(classesRepoProvider);
    final updatedIds = List<String>.from(_currentClass.catechistIds)..add(catId);
    final updatedAssociated =
        List<String>.from(_currentClass.associatedCatechistIds)..add(catId);
    final updatedRoles = Map<String, String>.from(_currentClass.catechistRoles)
      ..[catId] = 'TITOLARE';
    final updatedCounts =
        Map<String, int>.from(_currentClass.catechistDeviceCounts)
          ..[catId] = 1;

    try {
      await repo.updateClass(
        _currentClass.id,
        _currentClass.copyWith(
          catechistIds: updatedIds,
          associatedCatechistIds: updatedAssociated,
          catechistRoles: updatedRoles,
          catechistDeviceCounts: updatedCounts,
        ),
      );
      if (!mounted) return;
      setState(() {
        _currentClass = _currentClass.copyWith(
          catechistIds: updatedIds,
          associatedCatechistIds: updatedAssociated,
          catechistRoles: updatedRoles,
          catechistDeviceCounts: updatedCounts,
        );
      });
      await _resolveGroups();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$first $last aggiunto al gruppo.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore aggiunta: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final hasKnownCreator =
        _currentClass.creatorCatechistId.isNotEmpty ||
        _currentClass.creatorId.isNotEmpty ||
        _currentClass.creatorName.isNotEmpty;
    final canManage =
        _currentClass.isCreator(
          AuthService.localUserId,
          getCurrentCatechistName(),
          catechistId: AuthService.getCatechistId(),
        ) &&
        (!hasKnownCreator ||
            _currentClass.creatorCatechistId.isNotEmpty ||
            !_currentClass.nameLocked);

    return Scaffold(
      backgroundColor: isDark ? colorScheme.surface : Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: isDark
            ? colorScheme.primaryContainer
            : const Color(0xFF174A7E),
        foregroundColor: isDark ? colorScheme.onPrimaryContainer : Colors.white,
        title: Text('Catechisti — ${_currentClass.name}'),
      ),
      body: _loadingNames
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
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
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
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                ),
                if (canManage) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _showAddOfflineCatechistDialog,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? colorScheme.primaryContainer
                                .withValues(alpha: 0.3)
                            : const Color(0xFF174A7E).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? colorScheme.primary.withValues(alpha: 0.3)
                              : const Color(0xFF174A7E).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF174A7E),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.person_add_rounded,
                                color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Aggiungi catechista senza app',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Color(0xFF174A7E)),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Nome e cognome per report corretto',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey,
                                      height: 1.2),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.add_circle_outline_rounded,
                              color: Color(0xFF174A7E)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                ..._groups.map(
                  (group) => _CatechistCard(
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
                                backgroundColor: isDark
                                    ? colorScheme.surface
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                title: const Text('Rimuovere catechista?'),
                                content: Text(
                                  'Rimuovere $label da questo gruppo?',
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
                              await _removeGroup(group);
                            }
                          }
                        : null,
                  ),
                ),
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
  final String logicalId;

  const _DeviceInfo({
    required this.id,
    required this.displayName,
    required this.isLocalUser,
    required this.isMioDispositivo,
    String? logicalId,
  }) : logicalId = logicalId ?? id;
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
              : [Colors.white, Colors.blue.shade50.withValues(alpha: 0.35)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? colorScheme.outline.withValues(alpha: 0.2)
              : Colors.blue.shade100,
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
                    color: isDark
                        ? colorScheme.onSurface
                        : const Color(0xFF174A7E),
                  ),
                ),
                if (isLocalUser)
                  Text(
                    deviceCount > 1
                        ? 'Sei tu — $deviceCount dispositivi'
                        : 'Sei tu',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade500,
                    ),
                  )
                else if (deviceCount > 1)
                  Text(
                    '$deviceCount dispositivi',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade500,
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
