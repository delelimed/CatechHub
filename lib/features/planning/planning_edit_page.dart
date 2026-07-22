import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/attachment_parent_type.dart';
import '../../shared/models/planning_meeting.dart';
import '../attachments/widgets/attachments_section.dart';
import '../catechesi/catechesi_repository.dart';
import '../../shared/models/catechesi_model.dart';
import '../classes/classes_provider.dart';
import 'planning_provider.dart';

/// Schermata di creazione/modifica di un incontro o riunione in CateREG.
///
/// Se [existing] è fornito, la pagina si comporta in modalità modifica
/// caricando i dati esistenti (titolo, attività, note, data, associazioni).
/// Se [isReunion] è `true`, l'incontro viene contrassegnato come riunione
/// (nessun appello presenze) — il flag è ignorato se [existing] è presente
/// (in quel caso viene usato il valore salvato).
class PlanningEditPage extends ConsumerStatefulWidget {
  final PlanningMeeting? existing;

  /// Nuovo incontro: `false` = giornata con appello, `true` = riunione senza appello.
  final bool isReunion;

  const PlanningEditPage({
    super.key,
    this.existing,
    this.isReunion = false,
  });

  @override
  ConsumerState<PlanningEditPage> createState() => _PlanningEditPageState();
}

class _PlanningEditPageState extends ConsumerState<PlanningEditPage> {
  late final String meetingId;
  late final bool isReunion;

  DateTime? selectedDate;
  TimeOfDay? selectedTime;

  final title = TextEditingController();
  final activity = TextEditingController();
  final notes = TextEditingController();

  List<String> associatedCatechesiIds = [];
  bool _readOnly = true;

  @override
  void initState() {
    super.initState();
    meetingId = widget.existing?.id ?? LocalDatabase.newId('meeting');
    isReunion = widget.existing?.isReunion ?? widget.isReunion;
    _readOnly = widget.existing != null;

    final meeting = widget.existing;
    if (meeting != null) {
      selectedDate = meeting.date;
      if (meeting.time != null && meeting.time!.isNotEmpty) {
        final parts = meeting.time!.split(':');
        if (parts.length == 2) {
          selectedTime = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 0,
            minute: int.tryParse(parts[1]) ?? 0,
          );
        }
      }
      title.text = meeting.title;
      activity.text = meeting.activity;
      notes.text = meeting.notes;
    }

    associatedCatechesiIds = _loadAssociatedCatechesi();
  }

  /// Recupera dal box di associazione meeting↔catechesi gli ID delle
  /// catechesi già collegate a questo meeting (se in modifica).
  List<String> _loadAssociatedCatechesi() {
    final box = LocalDatabase.meetingCatechesi();
    final data = box.get(meetingId);
    if (data == null) return [];
    final list = (data as List<dynamic>?)?.cast<String>() ?? [];
    return list;
  }

  /// Salva in Hive le associazioni tra questo meeting e le catechesi selezionate.
  Future<void> _saveAssociatedCatechesi() async {
    final box = LocalDatabase.meetingCatechesi();
    await box.put(meetingId, associatedCatechesiIds);
  }

  @override
  void dispose() {
    title.dispose();
    activity.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(planningRepoProvider);
    final classesAsync = ref.watch(classesStreamProvider);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF174A7E),
        foregroundColor: Colors.white,
        title: Text(
          _pageTitle(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: Icon(_readOnly ? Icons.lock_outline_rounded : Icons.lock_open_rounded),
              tooltip: _readOnly ? 'Abilita modifica' : 'Blocca',
              onPressed: () => setState(() => _readOnly = !_readOnly),
            ),
        ],
      ),
      body: classesAsync.when(
        data: (classes) {
          final myClass = classes.where(
            (c) => c.catechistIds.contains(AuthService.localUserId),
          );

          if (myClass.isEmpty) {
            return const Center(
              child: Text('Non sei assegnato a nessuna classe'),
            );
          }

          final classId = myClass.first.id;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (isReunion)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.deepPurple.shade100),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.groups_rounded,
                          color: Colors.deepPurple.shade700,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Riunione: non compare nell\'appello presenze.',
                            style: TextStyle(
                              color: Colors.deepPurple.shade900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                _DatePickerCard(
                  selectedDate: selectedDate,
                  onTap: () {
                    if (_readOnly) return;
                    showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: Color(0xFF174A7E),
                            ),
                          ),
                          child: child!,
                        );
                      },
                    ).then((date) {
                      if (date != null) {
                        setState(() => selectedDate = date);
                      }
                    });
                  },
                ),
                if (isReunion) ...[
                  const SizedBox(height: 14),
                  _TimePickerCard(
                    selectedTime: selectedTime,
                    onTap: () {
                      if (_readOnly) return;
                      showTimePicker(
                        context: context,
                        initialTime: selectedTime ?? TimeOfDay.now(),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: const ColorScheme.light(
                                primary: Color(0xFF174A7E),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      ).then((time) {
                        if (time != null) {
                          setState(() => selectedTime = time);
                        }
                      });
                    },
                  ),
                ],
                if (!isReunion) ...[
                  const SizedBox(height: 14),
                  _MeetingNumberBadge(
                    meetingId: meetingId,
                    classId: classId,
                  ),
                ],
                const SizedBox(height: 18),
                _ModernInputCard(
                  icon: Icons.title_rounded,
                  color: const Color(0xFF174A7E),
                  child: TextField(
                    controller: title,
                    textInputAction: TextInputAction.next,
                    readOnly: _readOnly,
                    decoration: InputDecoration(
                      hintText: isReunion ? 'Titolo riunione' : 'Titolo giornata',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _ModernInputCard(
                  icon: Icons.menu_book_rounded,
                  color: Colors.orange,
                  child: TextField(
                    controller: activity,
                    maxLines: 6,
                    readOnly: _readOnly,
                    decoration: const InputDecoration(
                      hintText: 'Attività / Argomenti',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _ModernInputCard(
                  icon: Icons.notes_rounded,
                  color: Colors.blue,
                  child: TextField(
                    controller: notes,
                    maxLines: 3,
                    readOnly: _readOnly,
                    decoration: const InputDecoration(
                      hintText: 'Note',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AttachmentsSection(
                  parentId: meetingId,
                  parentType: AttachmentParentType.meeting,
                  title: 'Foto e PDF dell\'incontro',
                  readOnly: _readOnly,
                ),
                const SizedBox(height: 20),
                _CatechesiAssociationSection(
                  associatedIds: associatedCatechesiIds,
                  onChanged: (ids) {
                    setState(() => associatedCatechesiIds = ids);
                  },
                  readOnly: _readOnly,
                ),
                const SizedBox(height: 24),
                if (!_readOnly)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF174A7E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: const Icon(Icons.save_rounded),
                    label: Text(
                      isReunion ? 'Salva riunione' : 'Salva giornata',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      if (selectedDate == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Seleziona una data')),
                        );
                        return;
                      }

                      if (title.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isReunion
                                  ? 'Inserisci un titolo per la riunione'
                                  : 'Inserisci un titolo per la giornata',
                            ),
                          ),
                        );
                        return;
                      }

                      final meeting = PlanningMeeting(
                        id: meetingId,
                        classId: classId,
                        createdBy: AuthService.localUserId,
                        date: selectedDate!,
                        time: (isReunion && selectedTime != null)
                            ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                            : null,
                        title: title.text.trim(),
                        activity: activity.text.trim(),
                        notes: notes.text.trim(),
                        isReunion: isReunion,
                      );

                      try {
                        if (widget.existing == null) {
                          await repo.addMeeting(meeting);
                        } else {
                          await repo.updateMeeting(meeting.id, meeting);
                        }
                        await _saveAssociatedCatechesi();

                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Errore: $e')),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
      ),
    );
  }

  /// Restituisce il titolo della AppBar in base al contesto:
  /// "Nuova giornata/riunione" in creazione, "Modifica giornata/riunione" in modifica.
  String _pageTitle() {
    if (widget.existing != null) {
      return isReunion ? 'Modifica riunione' : 'Modifica giornata';
    }
    return isReunion ? 'Nuova riunione' : 'Nuova giornata';
  }
}

/// Card interattiva per la selezione della data di un incontro.
///
/// Mostra la data correntemente selezionata (o un invito a selezionarne una)
/// e cambia stile (gradiente blu scuro) quando una data è stata scelta,
/// coerente con il design delle schede di input del modulo.
class _DatePickerCard extends StatelessWidget {
  final DateTime? selectedDate;
  final VoidCallback onTap;

  const _DatePickerCard({
    required this.selectedDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedDate != null;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isSelected
                ? [
                    const Color(0xFF174A7E),
                    const Color(0xFF2A6BB0),
                  ]
                : [
                    Colors.white,
                    Colors.blue.shade50.withValues(alpha: 0.4),
                  ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? Colors.transparent : Colors.blue.shade100,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.15) : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.calendar_month_rounded,
                color: isSelected ? Colors.white : const Color(0xFF174A7E),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Data incontro',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white70 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSelected
                        ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                        : 'Seleziona una data',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : const Color(0xFF174A7E),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: isSelected ? Colors.white70 : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

/// Card interattiva per la selezione dell'orario di una riunione.
///
/// Mostra l'orario correntemente selezionato (o un invito a selezionarne uno)
/// e cambia stile (gradiente viola) quando un orario è stato scelto.
class _TimePickerCard extends StatelessWidget {
  final TimeOfDay? selectedTime;
  final VoidCallback onTap;

  const _TimePickerCard({
    required this.selectedTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedTime != null;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isSelected
                ? [
                    Colors.deepPurple.shade400,
                    Colors.deepPurple.shade600,
                  ]
                : [
                    Colors.white,
                    Colors.deepPurple.shade50.withValues(alpha: 0.4),
                  ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? Colors.transparent : Colors.deepPurple.shade100,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.15) : Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.access_time_rounded,
                color: isSelected ? Colors.white : Colors.deepPurple.shade700,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Orario riunione',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white70 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSelected
                        ? selectedTime!.format(context)
                        : 'Seleziona un orario',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.deepPurple.shade700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: isSelected ? Colors.white70 : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

/// Card contenitore stilosa per i campi di input del modulo.
///
/// Ogni card mostra un'icona colorata in alto e il widget figlio (TextField)
/// in basso, con bordi arrotondati e ombra leggera. Usata per titolo,
/// attività e note nel form di creazione/modifica incontro.
class _ModernInputCard extends StatelessWidget {
  final Widget child;
  final IconData icon;
  final Color color;

  const _ModernInputCard({
    required this.child,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Sezione per associare una o più catechesi all'incontro corrente.
///
/// Mostra le catechesi già collegate con possibilità di rimuoverle,
/// e un pulsante per aprirne il selettore modale e aggiungerne altre.
class _CatechesiAssociationSection extends StatefulWidget {
  final List<String> associatedIds;
  final ValueChanged<List<String>> onChanged;
  final bool readOnly;

  const _CatechesiAssociationSection({
    required this.associatedIds,
    required this.onChanged,
    this.readOnly = false,
  });

  @override
  State<_CatechesiAssociationSection> createState() => _CatechesiAssociationSectionState();
}

class _CatechesiAssociationSectionState extends State<_CatechesiAssociationSection> {
  late List<String> _selectedIds;

  /// Recupera tutte le catechesi disponibili dal repository.
  List<Catechesi> _allCatechesi() => CatechesiRepository().getCatechesiSync();

  @override
  void initState() {
    super.initState();
    _selectedIds = List.from(widget.associatedIds);
  }

  @override
  Widget build(BuildContext context) {
    final all = _allCatechesi();
    final selected = all.where((c) => _selectedIds.contains(c.id)).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_rounded, color: Colors.deepPurple.shade700),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Catechesi associate',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF174A7E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (selected.isEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Nessuna catechesi associata',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
                if (!widget.readOnly)
                  TextButton.icon(
                    onPressed: () => _showPicker(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Aggiungi'),
                  ),
              ],
            )
          else
            Column(
              children: [
                ...selected.map((c) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      final repo = CatechesiRepository();
                      final fullCatechesi = repo.getCatechesiSync().firstWhere(
                        (x) => x.id == c.id,
                        orElse: () => c,
                      );
                      context.push('/catechesi/detail', extra: {'catechesi': fullCatechesi});
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.deepPurple.shade100),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.title,
                              style: TextStyle(color: Colors.deepPurple.shade900),
                            ),
                          ),
                          if (!widget.readOnly)
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              color: Colors.deepPurple.shade700,
                              onPressed: () {
                                setState(() {
                                  _selectedIds.remove(c.id);
                                });
                                widget.onChanged(_selectedIds);
                              },
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 8),
                if (!widget.readOnly)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _showPicker(context),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Aggiungi altra catechesi'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final repo = CatechesiRepository();
    final all = repo.getCatechesiSync();
    final candidates = all.where((c) => !_selectedIds.contains(c.id)).toList();

    await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const Text(
                'Seleziona catechesi',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: candidates.length,
                  itemBuilder: (context, i) {
                    final c = candidates[i];
                    return ListTile(
                      title: Text(c.title),
                      subtitle: c.tags.isEmpty
                          ? null
                          : Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: c.tags
                                  .take(3)
                                  .map((t) => Chip(
                                        label: Text(t, style: const TextStyle(fontSize: 11)),
                                        visualDensity: VisualDensity.compact,
                                        backgroundColor: Colors.blue.shade50,
                                        side: BorderSide(color: Colors.blue.shade100),
                                      ))
                                  .toList(),
                            ),
                      onTap: () {
                        setState(() {
                          _selectedIds.add(c.id);
                        });
                        widget.onChanged(_selectedIds);
                        Navigator.pop(ctx, _selectedIds);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mostra il numero progressivo dell'incontro tra quelli della stessa classe,
/// ordinati dal più vicino al più lontano. Visibile solo per gli incontri
/// (non riunioni).
class _MeetingNumberBadge extends ConsumerWidget {
  final String meetingId;
  final String classId;

  const _MeetingNumberBadge({
    required this.meetingId,
    required this.classId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.read(planningRepoProvider).getMeetingsSync();
    final filtered = meetings
        .where((m) => m.classId == classId && !m.isReunion)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final index = filtered.indexWhere((m) => m.id == meetingId);
    if (index == -1) return const SizedBox.shrink();

    final numero = index + 1;
    final totale = filtered.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF174A7E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF174A7E).withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.tag_rounded, size: 18, color: const Color(0xFF174A7E)),
          const SizedBox(width: 8),
          Text(
            'Incontro $numero di $totale',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF174A7E),
            ),
          ),
        ],
      ),
    );
  }
}
