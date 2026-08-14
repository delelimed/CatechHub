// ══════════════════════════════════════════════════════════════════════════════
// classe_detail_page.dart — CatechHub (dettaglio classe del Responsabile)
//
// Schermata di dettaglio di una classe: catechisti associati (mostrati per
// NOME dalla rubrica), ragazzi iscritti e azioni di modifica (rinomina,
// archivia/ripristina, elimina, gestione catechisti).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/catechist_profile.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/student_model.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../classes/classes_provider.dart';
import '../classes/classes_repository.dart';
import 'catechist_manager_dialog.dart';
import 'catechists_repository.dart';
import 'responsabile_providers.dart';

/// Dettaglio di una classe: catechisti, ragazzi e azioni di gestione.
class ClasseDetailPage extends ConsumerStatefulWidget {
  final String classId;

  const ClasseDetailPage({super.key, required this.classId});

  @override
  ConsumerState<ClasseDetailPage> createState() => _ClasseDetailPageState();
}

class _ClasseDetailPageState extends ConsumerState<ClasseDetailPage> {
  Future<void> _rename(SchoolClass c) async {
    final nomeCtrl = TextEditingController(text: c.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rinomina classe'),
        content: TextField(
          controller: nomeCtrl,
          decoration: const InputDecoration(
            labelText: 'Nuovo nome',
            hintText: 'Es. Comunione A',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rinomina'),
          ),
        ],
      ),
    );
    if (ok == true && nomeCtrl.text.trim().isNotEmpty) {
      await ClassesRepository().renameClass(c.id, nomeCtrl.text.trim());
      _snack('Classe rinominata in "${nomeCtrl.text.trim()}".');
    }
  }

  Future<void> _archive(SchoolClass c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c.archived ? 'Ripristina classe' : 'Archivia classe'),
        content: Text(c.archived
            ? 'Ripristinare "${c.name}" tra le classi attive?'
            : 'Archiviare "${c.name}"? I dati restano conservati nello storico.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(c.archived ? 'Ripristina' : 'Archivia'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final repo = ClassesRepository();
      if (c.archived) {
        await repo.unarchiveClass(c.id);
        _snack('Classe ripristinata.');
      } else {
        await repo.archiveClass(c.id);
        _snack('Classe archiviata.');
      }
    }
  }

  Future<void> _delete(SchoolClass c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina classe'),
        content: Text(
            'Eliminare definitivamente "${c.name}" e tutti i suoi dati?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ClassesRepository().deleteClass(c.id);
      _snack('Classe eliminata.');
      if (mounted) context.pop();
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesStreamProvider);
    final studentsAsync = ref.watch(studentsOfClassProvider(widget.classId));
    final catechistsAsync = ref.watch(catechistsStreamProvider);

    return classesAsync.when(
      loading: () => const AppScaffold(
        title: 'Classe',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) =>
          AppScaffold(title: 'Classe', child: Center(child: Text('Errore: $e'))),
      data: (classes) {
        SchoolClass? found;
        for (final c in classes) {
          if (c.id == widget.classId) {
            found = c;
            break;
          }
        }
        if (found == null) {
          return const AppScaffold(
            title: 'Classe',
            child: Center(child: Text('Classe non trovata.')),
          );
        }
        final c = found;
        return AppScaffold(
          title: c.name,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _headerCard(c),
                  const SizedBox(height: 12),
                  _actionRow(c),
                  const SizedBox(height: 16),
                  _catechistiSection(c, catechistsAsync),
                  const SizedBox(height: 16),
                  _studentiSection(c, studentsAsync),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _headerCard(SchoolClass c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF174A7E), Color(0xFF2368B1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.class_rounded, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (c.percorso.isNotEmpty) c.percorso,
                    if (c.annoCatechistico.isNotEmpty) c.annoCatechistico,
                    if (c.archived) 'Archiviata',
                  ].join(' · '),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  '${c.studentIds.length} ragazzi · ${c.catechistIds.length} catechisti',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(SchoolClass c) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          onPressed: () async {
            await showCatechistManagerDialog(context, c);
          },
          icon: const Icon(Icons.group_add_outlined, size: 18),
          label: const Text('Gestisci catechisti'),
        ),
        OutlinedButton.icon(
          onPressed: () => _rename(c),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Rinomina'),
        ),
        OutlinedButton.icon(
          onPressed: () => _archive(c),
          icon: Icon(
            c.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
            size: 18,
          ),
          label: Text(c.archived ? 'Ripristina' : 'Archivia'),
        ),
        OutlinedButton.icon(
          onPressed: () => _delete(c),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Elimina'),
        ),
      ],
    );
  }

  Widget _catechistiSection(
    SchoolClass c,
    AsyncValue<List<CatechistProfile>> catechistsAsync,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sectionBg = isDark
        ? Theme.of(context).colorScheme.surfaceContainer
        : Colors.white;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sectionBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Catechisti',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          if (c.catechistIds.isEmpty)
            Text(
              'Nessun catechista assegnato.',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 12,
                color: isDark ? Colors.grey.shade400 : Colors.black54,
              ),
            )
          else
            catechistsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Errore: $e'),
              data: (profiles) {
                final byId = {for (final p in profiles) p.id: p};
                return Column(
                  children: [
                    for (final id in c.catechistIds)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFF174A7E)
                              .withValues(alpha: 0.12),
                          child: Text(
                            _initialsOf(id, byId),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF174A7E),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          _nameOf(id, byId),
                          style: const TextStyle(fontSize: 14),
                        ),
                        trailing: Chip(
                          label: Text(
                            c.catechistRoles[id] == ClassesRepository.roleTitolare
                                ? 'Titolare'
                                : 'Aiuto',
                            style: const TextStyle(fontSize: 11),
                          ),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: c.catechistRoles[id] ==
                                  ClassesRepository.roleTitolare
                              ? Colors.orange.shade50
                              : Colors.purple.shade50,
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _studentiSection(
    SchoolClass c,
    AsyncValue<List<Student>> studentsAsync,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sectionBg = isDark
        ? Theme.of(context).colorScheme.surfaceContainer
        : Colors.white;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sectionBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ragazzi inseriti (${c.studentIds.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 10),
          studentsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Errore: $e'),
            data: (students) => students.isEmpty
                ? Text(
                    'Nessun ragazzo inserito.',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                      color: isDark ? Colors.grey.shade400 : Colors.black54,
                    ),
                  )
                : Column(
                    children: [
                      for (final s in students)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.person_rounded, size: 20),
                          title: Text(
                            '${s.name} ${s.surname}'.trim(),
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            [
                              if (s.annoIscrizione.isNotEmpty)
                                'Iscr. ${s.annoIscrizione}',
                              s.statoPercorso,
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _nameOf(String id, Map<String, CatechistProfile> byId) {
    final p = byId[id];
    if (p != null) return p.fullName;
    if (id == 'local_catechist_id') return 'Catechista locale';
    return id.length > 8
        ? 'Catechista ${id.substring(id.length - 8)}'
        : id;
  }

  String _initialsOf(String id, Map<String, CatechistProfile> byId) {
    final p = byId[id];
    if (p != null) return p.initials;
    return _nameOf(id, byId).substring(0, 1).toUpperCase();
  }
}