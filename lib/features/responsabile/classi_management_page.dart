// ══════════════════════════════════════════════════════════════════════════════
// classi_management_page.dart — CatechHub (gestione classi e catechisti)
//
// Tab "Classi": creazione/rinomina/archiviazione/eliminazione delle classi.
// La creazione avviene tramite una finestra (dialog) con percorso limitato
// ai tre percorsi catechistici (Battesimo, Comunione, Confermazione).
// Il click su una classe apre la schermata di dettaglio [ClasseDetailPage]
// con catechisti associati (per nome), ragazzi inseriti e le azioni di
// modifica (rinomina, archivia, elimina, gestione catechisti).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/class_model.dart';
import '../../shared/utils/auth_utils.dart';
import '../../shared/utils/anno_catechistico.dart';
import '../classes/classes_provider.dart';
import '../classes/classes_repository.dart';

/// Percorsi catechistici ammessi per la creazione di una classe.
const List<String> kPercorsiClassi = [
  'Battesimo',
  'Comunione',
  'Confermazione',
];

/// Gestione classi e assegnazione catechisti.
class ClassiManagementPage extends ConsumerStatefulWidget {
  const ClassiManagementPage({super.key});

  @override
  ConsumerState<ClassiManagementPage> createState() =>
      _ClassiManagementPageState();
}

class _ClassiManagementPageState extends ConsumerState<ClassiManagementPage> {
  /// Apre la finestra di creazione di una nuova classe: nome obbligatorio e
  /// percorso selezionabile solo tra i percorsi ammessi.
  Future<void> _openCreateClassDialog() async {
    final nomeCtrl = TextEditingController();
    String? percorso;

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: const Text('Nuova classe'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nomeCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome classe *',
                    hintText: 'Es. Comunione A',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: percorso,
                  decoration: const InputDecoration(
                    labelText: 'Percorso',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  hint: const Text('Seleziona il percorso'),
                  items: [
                    for (final p in kPercorsiClassi)
                      DropdownMenuItem(value: p, child: Text(p)),
                  ],
                  onChanged: (v) => setState(() => percorso = v),
                ),
                const SizedBox(height: 6),
                Text(
                  'Percorsi disponibili: ${kPercorsiClassi.join(', ')}.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                if (nomeCtrl.text.trim().isEmpty) {
                  _snack('Inserisci il nome della classe.');
                  return;
                }
                Navigator.pop(d, true);
              },
              child: const Text('Crea classe'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      await _createClass(nomeCtrl.text.trim(), percorso);
    }
    nomeCtrl.dispose();
  }

  Future<void> _createClass(String nome, String? percorso) async {
    final repo = ClassesRepository();
    await repo.addClass(SchoolClass(
      id: LocalDatabase.newId('class'),
      name: nome,
      studentIds: [],
      catechistIds: [],
      uniqueCode: generateClassUniqueCode(),
      percorso: percorso ?? '',
      annoCatechistico: currentCatechisticYear(),
      lastModifiedBy: getCurrentCatechistName(),
    ));
    _snack('Classe "$nome" creata.');
  }

  Future<void> _archive(SchoolClass c) async {
    final confirm = await _confirm(
      'Archivia classe',
      'Archiviare "${c.name}"? I dati restano conservati nello storico.',
    );
    if (confirm == true) {
      await ClassesRepository().archiveClass(c.id);
      _snack('Classe archiviata.');
    }
  }

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

  Future<void> _delete(SchoolClass c) async {
    final confirm = await _confirm(
      'Elimina classe',
      'Eliminare definitivamente "${c.name}" e tutti i suoi dati?',
    );
    if (confirm == true) {
      await ClassesRepository().deleteClass(c.id);
      _snack('Classe eliminata.');
    }
  }

  Future<bool?> _confirm(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sectionColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _openCreateClassDialog,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nuova classe'),
              ),
            ),
            const SizedBox(height: 16),
            classesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Errore: $e'),
              data: (classes) {
                final active = classes.where((c) => !c.archived).toList();
                final archived = classes.where((c) => c.archived).toList();
                final percorsi = active.map((c) => c.percorso).toSet().toList()
                  ..sort((a, b) => a.compareTo(b));

                if (active.isEmpty && archived.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Nessuna classe presente. Crea la prima classe con il '
                      'pulsante "Nuova classe".',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (active.isNotEmpty)
                      Text(
                        'Classi attive',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 1,
                          color: sectionColor,
                        ),
                      ),
                    if (active.isNotEmpty) const SizedBox(height: 10),
                    for (final percorso in percorsi) ...[
                      if (percorso.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 6),
                          child: Row(
                            children: [
                              Icon(Icons.route_outlined,
                                  size: 16, color: sectionColor),
                              const SizedBox(width: 6),
                              Text(
                                percorso,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: sectionColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      for (final c
                          in active.where((c) => c.percorso == percorso))
                        _manageClassCard(c),
                    ],
                    if (archived.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Archiviate',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 1,
                          color: sectionColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final c in archived) _manageClassCard(c, archived: true),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _manageClassCard(SchoolClass c, {bool archived = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? Theme.of(context).colorScheme.surfaceContainer
        : Colors.white;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/parrocchia/classi/${c.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${c.studentIds.length} ragazzi · ${c.catechistIds.length} catechisti'
                            '${c.percorso.isNotEmpty ? " · ${c.percorso}" : ""}',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  isDark ? Colors.grey.shade400 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!archived) ...[
                      IconButton(
                        tooltip: 'Rinomina',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _rename(c),
                      ),
                      IconButton(
                        tooltip: 'Archivia',
                        icon: const Icon(Icons.archive_outlined),
                        onPressed: () => _archive(c),
                      ),
                      IconButton(
                        tooltip: 'Elimina',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(c),
                      ),
                    ],
                    Icon(
                      Icons.chevron_right_rounded,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                    ),
                  ],
                ),
                if (c.catechistRoles.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: c.catechistRoles.entries.map((e) {
                      final isTitolo = e.value == ClassesRepository.roleTitolare;
                      return Chip(
                        label: Text(
                          '${_catechistLabel(e.key)} · ${isTitolo ? "Titolare" : "Aiuto"}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: isTitolo
                            ? Colors.orange.shade50
                            : Colors.purple.shade50,
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _catechistLabel(String id) {
    if (id == 'local_catechist_id') return 'Catechista locale';
    return id.length > 8
        ? 'Catechista ${id.substring(id.length - 8)}'
        : id;
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
