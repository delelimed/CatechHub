import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/contact_note_model.dart';
import '../../shared/models/student_model.dart';
import 'contact_notes_repository.dart';

/// Provider che espone in tempo reale le [ContactNote] di uno specifico
/// studente, identificate dal suo [studentId]. Viene usato da
/// [StudentContactNotesPage] per aggiornare la UI a ogni modifica.
final _studentNotesProvider =
    StreamProvider.autoDispose.family<List<ContactNote>, String>(
  (ref, studentId) {
    final repo = ref.watch(contactNotesRepoProvider);
    return repo.getNotesForStudent(studentId);
  },
);

/// Pagina dettaglio contatti per un singolo studente di CateREG.
///
/// Mostra l'elenco cronologico (dal più recente) delle note di contatto
/// dello studente sotto forma di card. Ogni card mostra il mezzo usato
/// (de visu/WhatsApp/cellulare), data/ora e il testo della nota.
/// Permette di aggiungere una nuova nota o modificare/eliminare una
/// esistente tramite bottom sheet modali.
class StudentContactNotesPage extends ConsumerWidget {
  final Student student;

  const StudentContactNotesPage({super.key, required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(_studentNotesProvider(student.id));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? colorScheme.surface : Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: isDark ? colorScheme.primaryContainer : const Color(0xFF174A7E),
        foregroundColor: isDark ? colorScheme.onPrimaryContainer : Colors.white,
        title: Text('${student.surname} ${student.name}'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: isDark ? colorScheme.primary : const Color(0xFF174A7E),
        onPressed: () => _showAddNoteDialog(context, ref),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (notes) {
          if (notes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.contact_phone_outlined,
                        size: 64, color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Nessuna nota di contatto',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Premi + per aggiungere una nota',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return _ContactNoteCard(
                note: note,
                isDark: isDark,
                colorScheme: colorScheme,
                onDelete: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: isDark ? colorScheme.surfaceContainer : null,
                      title: Text('Elimina nota', style: TextStyle(color: isDark ? colorScheme.onSurface : null)),
                      content: Text(
                          'Vuoi eliminare questa nota di contatto?',
                          style: TextStyle(color: isDark ? colorScheme.onSurface : null)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Annulla'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style:
                              TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Elimina'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final repo = ref.read(contactNotesRepoProvider);
                    await repo.deleteNote(note.id);
                  }
                },
                onEdit: () => _showEditNoteDialog(context, ref, note),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddNoteDialog(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? colorScheme.surface : null,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddContactNoteSheet(
        studentId: student.id,
        isDark: isDark,
        colorScheme: colorScheme,
        onSave: (note) async {
          final repo = ref.read(contactNotesRepoProvider);
          await repo.addNote(note);
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
  }

  void _showEditNoteDialog(
      BuildContext context, WidgetRef ref, ContactNote note) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? colorScheme.surface : null,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _EditContactNoteSheet(
        note: note,
        isDark: isDark,
        colorScheme: colorScheme,
        onSave: (updatedNote) async {
          final repo = ref.read(contactNotesRepoProvider);
          await repo.addNote(updatedNote);
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
  }
}

/// Card che visualizza una singola nota di contatto.
///
/// Mostra il mezzo di comunicazione con icona e colore dedicati,
/// la data/ora formattata e il testo integrale della nota. Fornisce
/// pulsanti per modificare o eliminare la nota.
class _ContactNoteCard extends StatelessWidget {
  final ContactNote note;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _ContactNoteCard({
    required this.note,
    required this.isDark,
    required this.colorScheme,
    required this.onDelete,
    required this.onEdit,
  });

  IconData _mediumIcon(String medium) {
    switch (medium) {
      case 'whatsapp':
        return Icons.message_rounded;
      case 'cellulare':
        return Icons.phone_rounded;
      case 'de_visu':
      default:
        return Icons.person_rounded;
    }
  }

  Color _mediumColor(String medium) {
    switch (medium) {
      case 'whatsapp':
        return Colors.green;
      case 'cellulare':
        return Colors.blue;
      case 'de_visu':
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediumColor = _mediumColor(note.medium);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: mediumColor.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(_mediumIcon(note.medium), color: mediumColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  ContactNote.mediumLabel(note.medium),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: mediumColor,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Icon(Icons.calendar_today, size: 14, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd/MM/yyyy  HH:mm').format(note.dateTime),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(8),
                  child: Icon(Icons.edit,
                      size: 18, color: isDark ? Colors.blue.shade300 : Colors.blue.shade300),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(8),
                  child: Icon(Icons.delete_outline,
                      size: 18, color: Colors.red.shade300),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              note.notes,
              style: TextStyle(fontSize: 14, height: 1.4, color: isDark ? colorScheme.onSurface : null),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet per la creazione di una nuova nota di contatto.
///
/// Permette di selezionare data/ora, mezzo di comunicazione
/// (de visu, WhatsApp, cellulare) e inserire il testo della nota.
class _AddContactNoteSheet extends StatefulWidget {
  final String studentId;
  final bool isDark;
  final ColorScheme colorScheme;
  final Future<void> Function(ContactNote) onSave;

  const _AddContactNoteSheet({
    required this.studentId,
    required this.isDark,
    required this.colorScheme,
    required this.onSave,
  });

  @override
  State<_AddContactNoteSheet> createState() => _AddContactNoteSheetState();
}

class _AddContactNoteSheetState extends State<_AddContactNoteSheet> {
  final _notesController = TextEditingController();
  String _selectedMedium = 'de_visu';
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _selectedTime = TimeOfDay.now();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

  Future<void> _save() async {
    if (_notesController.text.trim().isEmpty) return;
    HapticFeedback.mediumImpact();

    setState(() => _isSaving = true);

    final dateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final note = ContactNote(
      id: LocalDatabase.newId('contact_note'),
      studentId: widget.studentId,
      dateTime: dateTime,
      medium: _selectedMedium,
      notes: _notesController.text.trim(),
    );

    await widget.onSave(note);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final colorScheme = widget.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Nuova Nota di Contatto',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 18, color: isDark ? colorScheme.primary : const Color(0xFF174A7E)),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('dd/MM/yyyy').format(_selectedDate),
                            style: TextStyle(fontSize: 14, color: isDark ? colorScheme.onSurface : null),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _pickTime,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time,
                              size: 18, color: isDark ? colorScheme.primary : const Color(0xFF174A7E)),
                          const SizedBox(width: 8),
                          Text(
                            _selectedTime.format(context),
                            style: TextStyle(fontSize: 14, color: isDark ? colorScheme.onSurface : null),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Text(
              'Mezzo di comunicazione',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MediumChip(
                  label: 'De visu',
                  icon: Icons.person_rounded,
                  value: 'de_visu',
                  selected: _selectedMedium == 'de_visu',
                  onTap: () => setState(() => _selectedMedium = 'de_visu'),
                  isDark: isDark,
                  colorScheme: colorScheme,
                ),
                const SizedBox(width: 8),
                _MediumChip(
                  label: 'WhatsApp',
                  icon: Icons.message_rounded,
                  value: 'whatsapp',
                  selected: _selectedMedium == 'whatsapp',
                  onTap: () => setState(() => _selectedMedium = 'whatsapp'),
                  isDark: isDark,
                  colorScheme: colorScheme,
                ),
                const SizedBox(width: 8),
                _MediumChip(
                  label: 'Cellulare',
                  icon: Icons.phone_rounded,
                  value: 'cellulare',
                  selected: _selectedMedium == 'cellulare',
                  onTap: () => setState(() => _selectedMedium = 'cellulare'),
                  isDark: isDark,
                  colorScheme: colorScheme,
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Note sulla conversazione',
                hintText: 'Descrivi il contenuto del contatto...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? colorScheme.primary : const Color(0xFF174A7E),
                foregroundColor: isDark ? colorScheme.onPrimary : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Salva',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet per la modifica di una nota di contatto esistente.
///
/// Pre-carica i valori correnti (data, ora, mezzo, testo) e consente
/// di aggiornarli. La nota mantiene lo stesso ID in modo che venga
/// sovrascritta nel database.
class _EditContactNoteSheet extends StatefulWidget {
  final ContactNote note;
  final bool isDark;
  final ColorScheme colorScheme;
  final Future<void> Function(ContactNote) onSave;

  const _EditContactNoteSheet({
    required this.note,
    required this.isDark,
    required this.colorScheme,
    required this.onSave,
  });

  @override
  State<_EditContactNoteSheet> createState() => _EditContactNoteSheetState();
}

class _EditContactNoteSheetState extends State<_EditContactNoteSheet> {
  late TextEditingController _notesController;
  late String _selectedMedium;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.note.notes);
    _selectedMedium = widget.note.medium;
    _selectedDate = widget.note.dateTime;
    _selectedTime = TimeOfDay.fromDateTime(widget.note.dateTime);
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

  Future<void> _save() async {
    if (_notesController.text.trim().isEmpty) return;
    HapticFeedback.mediumImpact();

    setState(() => _isSaving = true);

    final dateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final updatedNote = ContactNote(
      id: widget.note.id,
      studentId: widget.note.studentId,
      dateTime: dateTime,
      medium: _selectedMedium,
      notes: _notesController.text.trim(),
    );

    await widget.onSave(updatedNote);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final colorScheme = widget.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Modifica Nota di Contatto',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 18, color: isDark ? colorScheme.primary : const Color(0xFF174A7E)),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('dd/MM/yyyy').format(_selectedDate),
                            style: TextStyle(fontSize: 14, color: isDark ? colorScheme.onSurface : null),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _pickTime,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time,
                              size: 18, color: isDark ? colorScheme.primary : const Color(0xFF174A7E)),
                          const SizedBox(width: 8),
                          Text(
                            _selectedTime.format(context),
                            style: TextStyle(fontSize: 14, color: isDark ? colorScheme.onSurface : null),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Text(
              'Mezzo di comunicazione',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MediumChip(
                  label: 'De visu',
                  icon: Icons.person_rounded,
                  value: 'de_visu',
                  selected: _selectedMedium == 'de_visu',
                  onTap: () => setState(() => _selectedMedium = 'de_visu'),
                  isDark: isDark,
                  colorScheme: colorScheme,
                ),
                const SizedBox(width: 8),
                _MediumChip(
                  label: 'WhatsApp',
                  icon: Icons.message_rounded,
                  value: 'whatsapp',
                  selected: _selectedMedium == 'whatsapp',
                  onTap: () => setState(() => _selectedMedium = 'whatsapp'),
                  isDark: isDark,
                  colorScheme: colorScheme,
                ),
                const SizedBox(width: 8),
                _MediumChip(
                  label: 'Cellulare',
                  icon: Icons.phone_rounded,
                  value: 'cellulare',
                  selected: _selectedMedium == 'cellulare',
                  onTap: () => setState(() => _selectedMedium = 'cellulare'),
                  isDark: isDark,
                  colorScheme: colorScheme,
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Note sulla conversazione',
                hintText: 'Descrivi il contenuto del contatto...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? colorScheme.primary : const Color(0xFF174A7E),
                foregroundColor: isDark ? colorScheme.onPrimary : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Salva Modifiche',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip selezionabile per il mezzo di comunicazione.
///
/// Usato sia in [_AddContactNoteSheet] che in [_EditContactNoteSheet]
/// per scegliere tra "De visu", "WhatsApp" e "Cellulare".
/// Quando selezionato, si illumina con il colore primario di CateREG.
class _MediumChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final bool selected;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _MediumChip({
    required this.label,
    required this.icon,
    required this.value,
    required this.selected,
    required this.isDark,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? colorScheme.primary.withValues(alpha: 0.2) : const Color(0xFF174A7E).withValues(alpha: 0.1))
                : (isDark ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3) : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? (isDark ? colorScheme.primary : const Color(0xFF174A7E)) : (isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.grey.shade300),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? (isDark ? colorScheme.primary : const Color(0xFF174A7E))
                    : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected
                      ? (isDark ? colorScheme.primary : const Color(0xFF174A7E))
                      : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
