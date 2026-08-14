// ══════════════════════════════════════════════════════════════════════════════
// catechist_manager_dialog.dart — CatechHub (gestione catechisti di una classe)
//
// Dialog per assegnare/rimuovere i catechisti di una classe usando i profili
// della rubrica (per NOME, non per ID). Consente di impostare il ruolo interno
// (TITOLARE/AIUTO) e di rimuovere un catechista dalla classe.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../shared/models/catechist_profile.dart';
import '../../shared/models/class_model.dart';
import '../classes/classes_repository.dart';
import 'catechists_repository.dart';

/// Apre il dialog di gestione dei catechisti della classe [classModel].
Future<bool?> showCatechistManagerDialog(
  BuildContext context,
  SchoolClass classModel,
) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _CatechistManagerDialog(classModel: classModel),
  );
}

class _CatechistManagerDialog extends StatefulWidget {
  final SchoolClass classModel;

  const _CatechistManagerDialog({required this.classModel});

  @override
  State<_CatechistManagerDialog> createState() => _CatechistManagerDialogState();
}

class _CatechistManagerDialogState extends State<_CatechistManagerDialog> {
  /// catechistId → ruolo interno (TITOLARE/AIUTO) in lavorazione.
  late final Map<String, String> _roles;
  late final List<CatechistProfile> _profiles;

  String? _selectedProfileId;
  String _newRole = ClassesRepository.roleTitolare;

  @override
  void initState() {
    super.initState();
    _roles = Map.of(widget.classModel.catechistRoles);
    _profiles = CatechistsRepository().getAllSync();
  }

  List<CatechistProfile> get _available =>
      _profiles.where((p) => !_roles.containsKey(p.id)).toList();

  Future<void> _save() async {
    final repo = ClassesRepository();
    final c = widget.classModel;

    for (final entry in _roles.entries) {
      if (!c.catechistIds.contains(entry.key)) {
        await repo.addCatechistToClass(c.id, entry.key, role: entry.value);
      } else if (c.catechistRoles[entry.key] != entry.value) {
        await repo.setCatechistRole(c.id, entry.key, entry.value);
      }
    }

    final rimossi =
        c.catechistIds.where((id) => !_roles.containsKey(id)).toList();
    for (final id in rimossi) {
      await repo.removeCatechistFromClass(c.id, id);
    }

    if (mounted) Navigator.pop(context, true);
  }

  String _nameOf(String catechistId) {
    for (final p in _profiles) {
      if (p.id == catechistId) return p.fullName;
    }
    if (catechistId == 'local_catechist_id') return 'Catechista locale';
    return catechistId.length > 8
        ? 'Catechista ${catechistId.substring(catechistId.length - 8)}'
        : catechistId;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
      ),
    );

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Catechisti di "${widget.classModel.name}"'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_roles.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Nessun catechista assegnato.',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.grey.shade400 : Colors.black54,
                      fontSize: 13,
                    ),
                  ),
                ),
              for (final entry in _roles.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _nameOf(entry.key),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      SegmentedButton<String>(
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                        segments: const [
                          ButtonSegment(
                            value: ClassesRepository.roleTitolare,
                            label: Text('Titolare'),
                            icon: Icon(Icons.star_rounded, size: 16),
                          ),
                          ButtonSegment(
                            value: ClassesRepository.roleAiuto,
                            label: Text('Aiuto'),
                            icon: Icon(Icons.group_rounded, size: 16),
                          ),
                        ],
                        selected: {entry.value},
                        onSelectionChanged: (sel) => setState(
                          () => _roles[entry.key] = sel.first,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Rimuovi dalla classe',
                        icon: const Icon(Icons.person_remove_outlined),
                        color: Colors.red.shade400,
                        onPressed: () => setState(() => _roles.remove(entry.key)),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 24),
              const Text(
                'Aggiungi un catechista (per nome)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 10),
              if (_profiles.isEmpty)
                Text(
                  'Nessun profilo in rubrica. Crea i catechisti nella sezione '
                  '"Catechisti".',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.grey.shade400 : Colors.black54,
                  ),
                )
              else if (_available.isEmpty)
                Text(
                  'Tutti i catechisti della rubrica sono già assegnati.',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.grey.shade400 : Colors.black54,
                  ),
                )
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedProfileId,
                        decoration: InputDecoration(
                          labelText: 'Catechista',
                          border: border,
                          isDense: true,
                        ),
                        hint: const Text('Seleziona'),
                        items: [
                          for (final p in _available)
                            DropdownMenuItem(
                              value: p.id,
                              child: Text(
                                p.fullName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedProfileId = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SegmentedButton<String>(
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: ClassesRepository.roleTitolare,
                          label: Text('Tit.'),
                          icon: Icon(Icons.star_rounded, size: 14),
                        ),
                        ButtonSegment(
                          value: ClassesRepository.roleAiuto,
                          label: Text('Aiuto'),
                          icon: Icon(Icons.group_rounded, size: 14),
                        ),
                      ],
                      selected: {_newRole},
                      onSelectionChanged: (sel) =>
                          setState(() => _newRole = sel.first),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Aggiungi',
                      icon: const Icon(Icons.add_rounded),
                      onPressed: _selectedProfileId == null
                          ? null
                          : () {
                              setState(() {
                                _roles[_selectedProfileId!] = _newRole;
                                _selectedProfileId = null;
                              });
                            },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Salva'),
        ),
      ],
    );
  }
}
