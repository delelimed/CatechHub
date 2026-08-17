// ══════════════════════════════════════════════════════════════════════════════
// catechisti_page.dart — CatechHub (rubrica catechisti della parrocchia)
//
// Pagina dedicata alla gestione dei catechisti della parrocchia:
//   - Rubrica con anagrafica (nome, cognome, telefono);
//   - Assegnazione dei catechisti alle classi con ruolo (TITOLARE/AIUTO);
//   - Stato dei dispositivi associati (P2P) e rinvio alla Catena di Fiducia.
//
// La pagina si adatta a tablet e smartphone: su schermi larghi le card sono
// disposte su più colonne, su telefoni restano un elenco scorrevole.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/catechist_profile.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/user_role.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../classes/classes_provider.dart';
import '../classes/classes_repository.dart';
import '../sync/p2p/p2p_security_service.dart';
import 'catechists_repository.dart';

/// Pagina della rubrica catechisti.
class CatechistiPage extends ConsumerWidget {
  const CatechistiPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!UserRole.isResponsabile) {
      return AppScaffold(
        title: 'Catechisti',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 52, color: Colors.grey),
                const SizedBox(height: 12),
                const Text(
                  'Questa sezione è riservata al Responsabile Catechistico.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Torna alla home'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return AppScaffold(
      title: 'Catechisti',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCatechistForm(context, ref),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nuovo catechista'),
      ),
      child: Consumer(
        builder: (context, ref, _) {
          final catechistsAsync = ref.watch(catechistsStreamProvider);
          return catechistsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Errore: $e')),
            data: (catechists) {
              if (catechists.isEmpty) {
                return _EmptyState(
                  onCreate: () => _showCatechistForm(context, ref),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth >= 900
                      ? 3
                      : constraints.maxWidth >= 560
                          ? 2
                          : 1;
                  return GridView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisExtent: 178,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    itemCount: catechists.length,
                    itemBuilder: (context, index) => _CatechistCard(
                      profile: catechists[index],
                      onTap: () =>
                          _showCatechistDetail(context, ref, catechists[index]),
                      onEdit: () =>
                          _showCatechistForm(context, ref, catechists[index]),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // CREAZIONE / MODIFICA
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _showCatechistForm(
    BuildContext context,
    WidgetRef ref, [
    CatechistProfile? existing,
  ]) async {
    final nomeCtrl = TextEditingController(text: existing?.firstName ?? '');
    final cognomeCtrl = TextEditingController(text: existing?.lastName ?? '');
    final telefonoCtrl = TextEditingController(text: existing?.phone ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          existing == null ? 'Nuovo catechista' : 'Modifica catechista',
          style: const TextStyle(
            color: Color(0xFF174A7E),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nome *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cognomeCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Cognome *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: telefonoCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefono',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () async {
              final nome = nomeCtrl.text.trim();
              final cognome = cognomeCtrl.text.trim();
              if (nome.isEmpty || cognome.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Inserisci nome e cognome.')),
                );
                return;
              }
              final repo = ref.read(catechistsRepositoryProvider);
              final profile = CatechistProfile(
                id: existing?.id ?? LocalDatabase.newId('cat'),
                firstName: nome,
                lastName: cognome,
                phone: telefonoCtrl.text.trim(),
              );
              await repo.save(profile);
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existing == null ? 'Catechista aggiunto.' : 'Catechista aggiornato.'),
        ),
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // DETTAGLIO: classi + dispositivi
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _showCatechistDetail(
    BuildContext context,
    WidgetRef ref,
    CatechistProfile profile,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.surfaceContainer
          : Colors.white,
      builder: (sheetContext) => _CatechistDetailSheet(
        profile: profile,
        ref: ref,
      ),
    );
  }
}

class _CatechistDetailSheet extends ConsumerStatefulWidget {
  final CatechistProfile profile;
  final WidgetRef ref;

  const _CatechistDetailSheet({
    required this.profile,
    required this.ref,
  });

  @override
  ConsumerState<_CatechistDetailSheet> createState() =>
      _CatechistDetailSheetState();
}

class _CatechistDetailSheetState extends ConsumerState<_CatechistDetailSheet> {
  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final classesAsync = ref.watch(classesStreamProvider);
    final deviceAsync = FutureBuilder<List<P2PDeviceAssociation>>(
      future: P2PSecurityService().getAllAssociations(),
      builder: (context, snapshot) {
        final assocs = snapshot.data ?? const <P2PDeviceAssociation>[];
        return _deviceSection(profile, assocs);
      },
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFF174A7E),
                  child: Text(
                    profile.initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
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
                        profile.fullName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF174A7E),
                        ),
                      ),
                      if (profile.phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          profile.phone,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Modifica',
                  icon: const Icon(Icons.edit_rounded),
                  onPressed: () async {
                    await _editProfile();
                  },
                ),
                IconButton(
                  tooltip: 'Elimina',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red.shade400,
                  ),
                  onPressed: _deleteProfile,
                ),
              ],
            ),
            const SizedBox(height: 20),
            const _SectionLabel('Classi assegnate'),
            const SizedBox(height: 8),
            classesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Errore: $e'),
              data: (classes) => _classAssignment(classes),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('Dispositivi associati'),
            const SizedBox(height: 8),
            deviceAsync,
          ],
        ),
      ),
    );
  }

  Widget _classAssignment(List<SchoolClass> classes) {
    final active = classes.where((c) => !c.archived).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final myClasses = active
        .where((c) => c.catechistIds.contains(widget.profile.id))
        .toList();

    if (myClasses.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Nessuna classe assegnata. Tocca sotto per assegnarne una.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _assignToClass(active, myClasses),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Assegna a una classe'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in myClasses)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.groups_rounded,
                color: Color(0xFF174A7E)),
            title: Text(c.name),
            subtitle: Text(
              ClassesRepository().roleOf(c, widget.profile.id) ==
                      ClassesRepository.roleTitolare
                  ? 'Titolare'
                  : 'Aiuto',
            ),
            trailing: PopupMenuButton<String>(
              tooltip: 'Ruolo o rimozione',
              onSelected: (value) async {
                if (value == 'remove') {
                  await ClassesRepository()
                      .removeCatechistFromClass(c.id, widget.profile.id);
                } else {
                  await ClassesRepository().setCatechistRole(
                    c.id,
                    widget.profile.id,
                    value,
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: ClassesRepository.roleTitolare,
                  child: Text('Rendi Titolare'),
                ),
                const PopupMenuItem(
                  value: ClassesRepository.roleAiuto,
                  child: Text('Rendi Aiuto'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Rimuovi dalla classe',
                      style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => _assignToClass(active, myClasses),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Assegna a un\'altra classe'),
        ),
      ],
    );
  }

  Future<void> _assignToClass(
    List<SchoolClass> active,
    List<SchoolClass> myClasses,
  ) async {
    final candidates =
        active.where((c) => !myClasses.contains(c)).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Il catechista è già in tutte le classi.')),
      );
      return;
    }
    var selectedId = candidates.first.id;
    var role = ClassesRepository.roleTitolare;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text(
            'Assegna a una classe',
            style: TextStyle(
              color: Color(0xFF174A7E),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedId,
                decoration: const InputDecoration(
                  labelText: 'Classe',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final c in candidates)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => selectedId = v);
                },
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: ClassesRepository.roleTitolare,
                    label: Text('Titolare'),
                    icon: Icon(Icons.star_rounded),
                  ),
                  ButtonSegment(
                    value: ClassesRepository.roleAiuto,
                    label: Text('Aiuto'),
                    icon: Icon(Icons.group_rounded),
                  ),
                ],
                selected: {role},
                onSelectionChanged: (sel) => setState(() => role = sel.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () async {
                await ClassesRepository().addCatechistToClass(
                  selectedId,
                  widget.profile.id,
                  role: role,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Assegna'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceSection(
    CatechistProfile profile,
    List<P2PDeviceAssociation> associations,
  ) {
    final mine =
        associations.where((a) => a.catechistId == profile.id).toList();

    if (mine.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: const Text(
              'Nessun dispositivo collegato a questo catechista. '
              'Associa il suo telefono tramite la Catena di Fiducia.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.pop(context);
              context.push('/settings/approval-center');
            },
            icon: const Icon(Icons.qr_code_2_rounded, size: 18),
            label: const Text('Associa il cellulare'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in mine)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: a.authorizedByResponsabile
                  ? Colors.green.withValues(alpha: 0.06)
                  : Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: a.authorizedByResponsabile
                    ? Colors.green.withValues(alpha: 0.3)
                    : Colors.grey.shade300,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  a.authorizedByResponsabile
                      ? Icons.verified_rounded
                      : Icons.phone_android_rounded,
                  color: a.authorizedByResponsabile
                      ? Colors.green.shade700
                      : Colors.grey.shade600,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.deviceName.isEmpty ? 'Dispositivo' : a.deviceName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        a.authorizedByResponsabile
                            ? 'Approvato'
                            : 'Non ancora approvato',
                        style: TextStyle(
                          fontSize: 12,
                          color: a.authorizedByResponsabile
                              ? Colors.green.shade700
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () {
            Navigator.pop(context);
            context.push('/settings/approval-center');
          },
          icon: const Icon(Icons.qr_code_2_rounded, size: 18),
          label: const Text('Gestisci dispositivi'),
        ),
      ],
    );
  }

  Future<void> _editProfile() async {
    Navigator.pop(context);
    // La modifica passa dal form condiviso della pagina madre.
    await _CatechistiPageBuilder.showEdit(
      context,
      widget.ref,
      widget.profile,
    );
  }

  Future<void> _deleteProfile() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Elimina catechista'),
        content: Text(
          'Eliminare "${widget.profile.fullName}" dalla rubrica? '
          'Verranno rimosse anche le assegnazioni alle classi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final classesRepo = ClassesRepository();
    final classes = classesRepo.getClassesSync();
    for (final c in classes) {
      if (c.catechistIds.contains(widget.profile.id)) {
        await classesRepo.removeCatechistFromClass(c.id, widget.profile.id);
      }
    }
    await widget.ref
        .read(catechistsRepositoryProvider)
        .delete(widget.profile.id);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.profile.fullName} eliminato.')),
      );
    }
  }
}

/// Builder statico per aprire il form di creazione/modifica dalla pagina.
class _CatechistiPageBuilder {
  static Future<void> showEdit(
    BuildContext context,
    WidgetRef ref,
    CatechistProfile? profile,
  ) async {
    final nomeCtrl = TextEditingController(text: profile?.firstName ?? '');
    final cognomeCtrl = TextEditingController(text: profile?.lastName ?? '');
    final telefonoCtrl = TextEditingController(text: profile?.phone ?? '');

    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          profile == null ? 'Nuovo catechista' : 'Modifica catechista',
          style: const TextStyle(
            color: Color(0xFF174A7E),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cognomeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Cognome *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: telefonoCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefono',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () async {
              final nome = nomeCtrl.text.trim();
              final cognome = cognomeCtrl.text.trim();
              if (nome.isEmpty || cognome.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Inserisci nome e cognome.')),
                );
                return;
              }
              final repo = ref.read(catechistsRepositoryProvider);
              final updated = CatechistProfile(
                id: profile?.id ?? LocalDatabase.newId('cat'),
                firstName: nome,
                lastName: cognome,
                phone: telefonoCtrl.text.trim(),
              );
              await repo.save(updated);
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }
}

/// Card di un catechista nell'elenco.
class _CatechistCard extends StatelessWidget {
  final CatechistProfile profile;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _CatechistCard({
    required this.profile,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? Theme.of(context).colorScheme.surfaceContainer
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark
                ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)
                : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF174A7E).withValues(alpha: 0.12),
                  child: Text(
                    profile.initials,
                    style: const TextStyle(
                      color: Color(0xFF174A7E),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      if (profile.phone.isNotEmpty)
                        Text(
                          profile.phone,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                isDark ? Colors.grey.shade400 : Colors.black54,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Modifica',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: onEdit,
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Icon(
                  Icons.groups_rounded,
                  size: 16,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Tocca per assegnare alle classi',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_add_alt_1_rounded,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              'Nessun catechista in rubrica',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Aggiungi i catechisti della parrocchia per assegnarli alle '
              'classi e collegarli ai loro dispositivi.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Nuovo catechista'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.3,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
