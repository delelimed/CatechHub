// ══════════════════════════════════════════════════════════════════════════════
// aula_management_page.dart — CatechHub (gestione logistica: aule e slot)
//
// Permette al Responsabile di gestire le aule/stanza parrocchiali e di
// assegnare slot orari settimanali alle classi, con rilevamento conflitti.
// I dispositivi "Associato" (modalità Responsabile attiva nella parrocchia)
// vedono invece una vista in SOLA LETTURA: aule, stanze e tabella orario,
// senza alcuna azione di modifica.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/aula.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/user_role.dart';
import '../../shared/utils/app_mode.dart';
import '../../shared/utils/auth_utils.dart';
import '../classes/classes_provider.dart';
import '../classes/classes_repository.dart';
import 'aula_repository.dart';
import 'responsabile_providers.dart';
import 'slot_conflict_service.dart';

/// Tab di gestione aule.
class AulaManagementSection extends ConsumerStatefulWidget {
  const AulaManagementSection({super.key});

  @override
  ConsumerState<AulaManagementSection> createState() =>
      _AulaManagementSectionState();
}

class _AulaManagementSectionState extends ConsumerState<AulaManagementSection> {
  final _nomeCtrl = TextEditingController();
  final _capienzaCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _capienzaCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _createAula() async {
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) {
      _snack('Inserisci il nome della stanza.');
      return;
    }
    final capienza = int.tryParse(_capienzaCtrl.text.trim()) ?? 0;
    try {
      final repo = AulaRepository();
      await repo.saveAula(Aula(
        stanzaId: LocalDatabase.newId('stanza'),
        nomeStanza: nome,
        capienzaMassima: capienza,
        noteAccessibilita: _noteCtrl.text.trim(),
        lastModifiedBy: getCurrentCatechistName(),
      ));
      _nomeCtrl.clear();
      _capienzaCtrl.clear();
      _noteCtrl.clear();
      _snack('Aula "$nome" creata.');
    } catch (e) {
      _snack('Errore: $e');
    }
  }

  Future<void> _deleteAula(Aula aula) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina aula'),
        content: Text(
            'Eliminare definitivamente l\'aula "${aula.nomeStanza}"? '
            'Verranno rimossi anche gli orari ad essa assegnati.'),
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
    if (confirm == true) {
      await AulaRepository().deleteAula(aula.stanzaId);
      _snack('Aula eliminata.');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = !UserRole.isResponsabile;

    if (readOnly && !AppModeUtils.canViewLogistica()) {
      return _readOnlyDenied();
    }

    final aulasAsync = ref.watch(aulasStreamProvider);
    final classesAsync = ref.watch(classesStreamProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (readOnly)
          _readOnlyBanner()
        else ...[
          _createForm(),
          const SizedBox(height: 16),
        ],
        classesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Errore: $e'),
          data: (classes) => aulasAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Errore: $e'),
            data: (aulas) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!readOnly) ...[
                  _slotAssignmentSection(classes, aulas),
                  const SizedBox(height: 16),
                ],
                _occupazioneTabellare(classes, aulas),
                const SizedBox(height: 16),
                _aulaGrid(classes, aulas, readOnly: readOnly),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Banner informativo mostrato ai dispositivi in sola lettura.
  Widget _readOnlyBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isDark ? Colors.blueGrey.shade900 : Colors.blue.shade50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.blueGrey.shade700 : Colors.blue.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_rounded,
            size: 20,
            color: isDark ? Colors.blueGrey.shade300 : Colors.blue.shade700,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Consultazione in sola lettura: la gestione delle aule e degli '
              'orari è riservata al Responsabile Catechistico.',
              style: TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  /// Schermata di accesso negato (modalità normale, parrocchia non gestita).
  Widget _readOnlyDenied() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 44,
            color: isDark ? Colors.grey.shade500 : Colors.grey,
          ),
          const SizedBox(height: 12),
          Text(
            'Logistica non disponibile',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Aule e orari settimanali sono visibili solo ai dispositivi '
            'collegati a una parrocchia con modalità Responsabile attiva.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _slotAssignmentSection(List<SchoolClass> classes, List<Aula> aulas) {
    final activeClasses = classes.where((c) => !c.archived).toList();
    if (activeClasses.isEmpty || aulas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Text(
          'Crea almeno una classe e un\'aula per assegnare gli orari settimanali.',
          style: TextStyle(fontSize: 13),
        ),
      );
    }
    return _SlotAssignment(
      classes: activeClasses,
      aulas: aulas,
      onAssigned: (msg) =>
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          ),
    );
  }

  /// Visualizzazione tabellare dell'occupazione: una riga per stanza e una
  /// colonna per giorno della settimana, con gli slot (classe + orario)
  /// assegnati a ogni cella. Su schermi stretti la tabella scorre in
  /// orizzontale.
  Widget _occupazioneTabellare(List<SchoolClass> classes, List<Aula> aulas) {
    const giorni = [
      'Lunedì',
      'Martedì',
      'Mercoledì',
      'Giovedì',
      'Venerdì',
      'Sabato',
      'Domenica',
    ];
    final activeClasses = classes.where((c) => !c.archived).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surfaceContainer
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey.shade800
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Occupazione delle stanze',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Griglia settimanale: stanze per giorno e orario di occupazione.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey.shade400
                  : Colors.black54,
            ),
          ),
          const SizedBox(height: 12),
          if (aulas.isEmpty || activeClasses.isEmpty)
            const Text(
              'Crea almeno una classe e un\'aula per visualizzare gli orari.',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 44,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 64,
                columns: [
                  const DataColumn(
                    label: Text('Stanza',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (final g in giorni)
                    DataColumn(
                      label: Text(g,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                ],
                rows: [
                  for (final aula in aulas)
                    DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 120,
                            child: Text(
                              aula.nomeStanza,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        for (var g = 1; g <= 7; g++)
                          DataCell(
                            _cellaOccupazione(aula, activeClasses, g),
                          ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Contenuto di una cella della griglia: gli slot della [aula] nel giorno [g].
  Widget _cellaOccupazione(Aula aula, List<SchoolClass> classes, int g) {
    final slots = <(String, String)>[];
    for (final c in classes) {
      for (final s in c.roomSlots) {
        if (s.stanzaId == aula.stanzaId && s.giornoSettimana == g) {
          slots.add((c.name, '${s.oraInizio}-${s.oraFine}'));
        }
      }
    }
    slots.sort((a, b) => a.$2.compareTo(b.$2));

    if (slots.isEmpty) {
      return const SizedBox(
        width: 90,
        child: Text('-', style: TextStyle(color: Colors.grey)),
      );
    }
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (nome, orario) in slots)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$orario ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey.shade300
                          : Colors.black87,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey.shade400
                            : Colors.black54,
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

  Widget _createForm() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
      ),
    );
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nuova stanza',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isDark ? Colors.white : const Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nomeCtrl,
            decoration: InputDecoration(
              labelText: 'Nome stanza *',
              border: border,
              hintText: "Es. Aula San Giuseppe, Sala parrocchiale",
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _capienzaCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Capienza massima',
              border: border,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(
              labelText: 'Note accessibilità (piano, barriere...)',
              border: border,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _createAula,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Crea aula'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aulaGrid(List<SchoolClass> classes, List<Aula> aulas,
      {bool readOnly = false}) {
    if (aulas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Text('Nessuna aula. Creane una per assegnare gli orari.'),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 700 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: cols == 2 ? 2.4 : 1.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: aulas.length,
          itemBuilder: (context, index) => _AulaCard(
            aula: aulas[index],
            classes: classes,
            readOnly: readOnly,
            onDelete: () => _deleteAula(aulas[index]),
          ),
        );
      },
    );
  }

  Widget _panel({required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainer
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: child,
    );
  }
}

class _AulaCard extends StatelessWidget {
  final Aula aula;
  final List<SchoolClass> classes;
  final bool readOnly;
  final VoidCallback onDelete;

  const _AulaCard({
    required this.aula,
    required this.classes,
    this.readOnly = false,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final occupied = classes
        .expand((c) => c.roomSlots.map((s) => (slot: s, cls: c)))
        .where((item) => item.slot.stanzaId == aula.stanzaId)
        .toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainer
            : Colors.white,
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.meeting_room_rounded, color: Color(0xFF174A7E)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  aula.nomeStanza,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              if (!readOnly)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDelete,
                ),
            ],
          ),
          if (aula.capienzaMassima > 0)
            Text(
              'Capienza: ${aula.capienzaMassima}',
              style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.black54),
            ),
          if (aula.noteAccessibilita.isNotEmpty)
            Text(
              aula.noteAccessibilita,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : Colors.black54,
                fontSize: 12,
              ),
            ),
          const Divider(height: 16),
          if (occupied.isEmpty)
            Text(
              'Nessuno slot assegnato',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: isDark ? Colors.grey.shade500 : Colors.grey,
              ),
            )
          else
            ...occupied.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${item.cls.name} — giorno ${item.slot.giornoSettimana} '
                  '${item.slot.oraInizio}-${item.slot.oraFine}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade300 : Colors.black87,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pannello di assegnazione slot orari settimanali a una classe con
/// rilevamento dei conflitti locale (SlotConflictService).
class _SlotAssignment extends StatefulWidget {
  final List<SchoolClass> classes;
  final List<Aula> aulas;
  final ValueChanged<String> onAssigned;

  const _SlotAssignment({
    required this.classes,
    required this.aulas,
    required this.onAssigned,
  });

  @override
  State<_SlotAssignment> createState() => _SlotAssignmentState();
}

class _SlotAssignmentState extends State<_SlotAssignment> {
  late SchoolClass _class;
  late Aula _aula;
  int _giorno = 6; // default Sabato
  TimeOfDay _inizio = const TimeOfDay(hour: 15, minute: 0);
  TimeOfDay _fine = const TimeOfDay(hour: 16, minute: 30);
  String _error = '';

  static const _giorni = [
    'Lunedì',
    'Martedì',
    'Mercoledì',
    'Giovedì',
    'Venerdì',
    'Sabato',
    'Domenica',
  ];

  @override
  void initState() {
    super.initState();
    _class = widget.classes.first;
    _aula = widget.aulas.first;
  }

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _assign() async {
    setState(() => _error = '');
    if (_inizio.hour * 60 + _inizio.minute >= _fine.hour * 60 + _fine.minute) {
      setState(() => _error = 'L\'ora di inizio deve precedere l\'ora di fine.');
      return;
    }
    final slot = RoomSlot(
      slotId: LocalDatabase.newId('slot'),
      stanzaId: _aula.stanzaId,
      nomeStanza: _aula.nomeStanza,
      giornoSettimana: _giorno,
      oraInizio: _hhmm(_inizio),
      oraFine: _hhmm(_fine),
    );
    try {
      await ClassesRepository().assignRoomSlot(
        classId: _class.id,
        slot: slot,
      );
      if (mounted) {
        widget.onAssigned(
          'Slot assegnato a "${_class.name}" (${_aula.nomeStanza}, '
          '${_giorni[_giorno - 1]}, ${slot.oraInizio}-${slot.oraFine}).',
        );
      }
    } on SlotConflictException catch (e) {
      setState(() => _error = e.conflicts.map((c) => c.message).join('\n'));
    } catch (e) {
      setState(() => _error = 'Errore: $e');
    }
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
          Text(
            'Assegna orario a una classe',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isDark ? Colors.white : const Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _class.id,
            decoration: InputDecoration(
                labelText: 'Classe', border: border, isDense: true),
            items: [
              for (final c in widget.classes)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _class = widget.classes.firstWhere((c) => c.id == v);
                _error = '';
              });
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _aula.stanzaId,
            decoration: InputDecoration(
                labelText: 'Aula', border: border, isDense: true),
            items: [
              for (final a in widget.aulas)
                DropdownMenuItem(value: a.stanzaId, child: Text(a.nomeStanza)),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _aula = widget.aulas.firstWhere((a) => a.stanzaId == v);
                _error = '';
              });
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _giorno,
            decoration: InputDecoration(
                labelText: 'Giorno della settimana',
                border: border,
                isDense: true),
            items: [
              for (var i = 1; i <= 7; i++)
                DropdownMenuItem(value: i, child: Text(_giorni[i - 1])),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _giorno = v);
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text('Inizio ${_hhmm(_inizio)}'),
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: _inizio,
                    );
                    if (t != null) setState(() => _inizio = t);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text('Fine ${_hhmm(_fine)}'),
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: _fine,
                    );
                    if (t != null) setState(() => _fine = t);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                _error,
                style: TextStyle(
                  color: isDark ? Colors.red.shade200 : Colors.red.shade800,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _assign,
              icon: const Icon(Icons.event_available_rounded),
              label: const Text('Assegna'),
            ),
          ),
        ],
      ),
    );
  }
}