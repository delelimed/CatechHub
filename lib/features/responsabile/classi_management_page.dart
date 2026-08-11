// ══════════════════════════════════════════════════════════════════════════════
// classi_management_page.dart — CatechHub (gestione classi e catechisti)
//
// Tab "Classi": creazione/rinomina/archiviazione/eliminazione delle classi e
// assegnazione catechisti con ruoli interni (TITOLARE/AIUTO).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/class_model.dart';
import '../../shared/utils/auth_utils.dart';
import '../classes/classes_provider.dart';
import '../classes/classes_repository.dart';

/// Gestione classi e assegnazione catechisti.
class ClassiManagementPage extends ConsumerStatefulWidget {
  const ClassiManagementPage({super.key});

  @override
  ConsumerState<ClassiManagementPage> createState() =>
      _ClassiManagementPageState();
}

class _ClassiManagementPageState extends ConsumerState<ClassiManagementPage> {
  final _nomeCtrl = TextEditingController();
  final _percorsoCtrl = TextEditingController();

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _percorsoCtrl.dispose();
    super.dispose();
  }

  Future<void> _createClass() async {
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) {
      _snack('Inserisci il nome della classe.');
      return;
    }
    final repo = ClassesRepository();
    await repo.addClass(SchoolClass(
      id: LocalDatabase.newId('class'),
      name: nome,
      studentIds: [],
      catechistIds: [],
      uniqueCode: generateClassUniqueCode(),
      percorso: _percorsoCtrl.text.trim(),
      lastModifiedBy: getCurrentCatechistName(),
    ));
    _nomeCtrl.clear();
    _percorsoCtrl.clear();
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
    return ListView(
      children: [
        _createForm(),
        const SizedBox(height: 12),
        classesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Errore: $e'),
          data: (classes) => Column(
            children: [
              for (final c in classes.where((c) => !c.archived))
                _manageClassCard(c),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Archiviate',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade400
                : Colors.black54,
          ),
        ),
        classesAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
          data: (classes) {
            final archived = classes.where((c) => c.archived).toList();
            if (archived.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Nessuna classe archiviata.',
                    style: TextStyle(fontStyle: FontStyle.italic)),
              );
            }
            return Column(
              children: [
                for (final c in archived)
                  _manageClassCard(c, archived: true),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _createForm() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
      ),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainer
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nuova classe',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _nomeCtrl,
            decoration: InputDecoration(
                labelText: 'Nome classe *', border: border),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _percorsoCtrl,
            decoration: InputDecoration(
              labelText: 'Percorso/Gruppo',
              hintText: 'Es. Prima Comunione, Cresima',
              border: border,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _createClass,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Crea classe'),
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
      ),
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
                        color: isDark ? Colors.grey.shade400 : Colors.black54,
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
                  tooltip: 'Assegna catechisti',
                  icon: const Icon(Icons.group_add_outlined),
                  onPressed: () => _showCatechist(c),
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
            ],
          ),
          if (c.catechistRoles.isNotEmpty)
            Wrap(
              spacing: 6,
              children: c.catechistRoles.entries.map((e) {
                final isTitolo = e.value == ClassesRepository.roleTitolare;
                return Chip(
                  label: Text(
                    '${_catechistLabel(e.key)} · ${isTitolo ? "Titolare" : "Aiuto"}',
                    style: TextStyle(fontSize: 11),
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
    );
  }

  Future<void> _showCatechist(SchoolClass c) async {
    // Aggiunge un catechista (ID interno) con ruolo TITOLARE o AIUTO.
    final idCtrl = TextEditingController();
    var role = ClassesRepository.roleTitolare;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Assegna catechista a "${c.name}"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idCtrl,
                decoration: const InputDecoration(
                  labelText: 'ID catechista',
                  hintText: 'cat_... o codice associazione',
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'TITOLARE',
                    label: Text('Titolare'),
                    icon: Icon(Icons.star_rounded),
                  ),
                  ButtonSegment(
                    value: 'AIUTO',
                    label: Text('Aiuto'),
                    icon: Icon(Icons.group_rounded),
                  ),
                ],
                selected: {role},
                onSelectionChanged: (sel) =>
                    setState(() => role = sel.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Assegna'),
            ),
          ],
        ),
      ),
    );
    if (result == true && idCtrl.text.trim().isNotEmpty) {
      await ClassesRepository().addCatechistToClass(c.id, idCtrl.text.trim(),
          role: role);
      _snack('Catechista assegnato.');
    }
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

/// Alias brevissimo a LocalDatabase.newId (chiamato nel form).
class LocalDb {
  static String newId(String prefix) => LocalDatabase.newId(prefix);
}