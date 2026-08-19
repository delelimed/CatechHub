// ─────────────────────────────────────────────────────────────────────────
// substitute_register_page.dart — registro supplenza (presenze + note)
// ─────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/substitute_delegation.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/qr_chunks_dialog.dart';
import '../meetings/attendance_repository.dart';
import 'substitute_providers.dart';

class SubstituteRegisterPage extends ConsumerStatefulWidget {
  final String? delegationId;

  const SubstituteRegisterPage({super.key, this.delegationId});

  @override
  ConsumerState<SubstituteRegisterPage> createState() =>
      _SubstituteRegisterPageState();
}

class _SubstituteRegisterPageState
    extends ConsumerState<SubstituteRegisterPage> {
  late Future<SubstituteDelegation?> _delegationFuture;
  final _noteController = TextEditingController();
  DateTime _attendanceDate = DateTime.now();
  final Map<String, String> _presence = {};
  bool _savingAttendance = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _delegationFuture = _load();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<SubstituteDelegation?> _load() async {
    final repo = ref.read(substituteDelegationRepoProvider);
    final id = widget.delegationId;
    if (id == null || id.isEmpty) return null;
    return repo.getById(id);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Registro supplenza',
      child: FutureBuilder<SubstituteDelegation?>(
        future: _delegationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final delegation = snapshot.data;
          if (delegation == null) {
            return const Center(child: Text('Delega non trovata.'));
          }
          return _buildBody(delegation);
        },
      ),
    );
  }

  Widget _buildBody(SubstituteDelegation delegation) {
    final students = _loadStudents(delegation.classId);
    final notes = ref
        .watch(substituteDelegationRepoProvider)
        .getNotesForDelegationSync(delegation.delegationId);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _delegationHeader(delegation),
        const SizedBox(height: 20),
        _attendanceCard(delegation, students),
        const SizedBox(height: 16),
        _notesCard(delegation, notes),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _sending ? null : () => _sendData(delegation),
          icon: const Icon(Icons.qr_code_2_rounded),
          label: const Text('Consegna dati al Titolare (QR)'),
        ),
      ],
    );
  }

  // ─── Intestazione ─────────────────────────────────────────────────────
  Widget _delegationHeader(SubstituteDelegation d) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.blue.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.className,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Titolare: ${d.ownerName}\n'
            'Validità: ${_fmt(d.validFrom)} → ${_fmt(d.validUntil)}',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Presenze ─────────────────────────────────────────────────────────
  Widget _attendanceCard(
    SubstituteDelegation d,
    List<Map<String, String>> students,
  ) {
    if (students.isEmpty) {
      return _card(
        title: 'Presenze',
        child: const Text('Nessuno studente nello snapshot della classe.'),
      );
    }
    return _card(
      title: 'Presenze del giorno',
      trailing: TextButton.icon(
        onPressed: _pickDate,
        icon: const Icon(Icons.event_rounded, size: 18),
        label: Text(_fmt(_attendanceDate)),
      ),
      child: Column(
        children: [
          for (final s in students) _studentRow(s),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _savingAttendance
                ? null
                : () => _saveAttendance(d, students),
            icon: const Icon(Icons.save_rounded),
            label: Text(_savingAttendance ? 'Salvataggio…' : 'Salva presenze'),
          ),
        ],
      ),
    );
  }

  Widget _studentRow(Map<String, String> s) {
    final id = s['id'] ?? '';
    final name = '${s['surname'] ?? ''} ${s['name'] ?? ''}'.trim();
    final status = _presence[id];
    final isPresent = status == 'Presente';
    final isAbsent = status == 'Assente';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isPresent
            ? Colors.green.withValues(alpha: 0.1)
            : isAbsent
            ? Colors.red.withValues(alpha: 0.08)
            : Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: Text(name, style: const TextStyle(fontSize: 14))),
          _toggleChip('Presente', isPresent, () {
            setState(() => _presence[id] = isPresent ? 'Assente' : 'Presente');
          }),
          const SizedBox(width: 6),
          _toggleChip('Assente', isAbsent, () {
            setState(() => _presence[id] = isAbsent ? 'Presente' : 'Assente');
          }),
        ],
      ),
    );
  }

  Widget _toggleChip(String label, bool active, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      selectedColor: label == 'Presente'
          ? Colors.green.shade200
          : Colors.red.shade200,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _attendanceDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _attendanceDate = picked);
  }

  Future<void> _saveAttendance(
    SubstituteDelegation d,
    List<Map<String, String>> students,
  ) async {
    final presentIds = _presence.entries
        .where((e) => e.value == 'Presente')
        .map((e) => e.key);
    final absentIds = _presence.entries
        .where((e) => e.value == 'Assente')
        .map((e) => e.key);

    final presence = <String, String>{};
    for (final s in students) {
      final id = s['id'] ?? '';
      if (presentIds.contains(id)) {
        presence[id] = 'Presente';
      } else if (absentIds.contains(id)) {
        presence[id] = 'Assente';
      }
    }
    if (presence.isEmpty) {
      _snack('Seleziona almeno una presenza prima di salvare.');
      return;
    }

    setState(() => _savingAttendance = true);
    try {
      await AttendanceRepository().saveAttendance(
        meetingId: LocalDatabase.newId('sub_att'),
        date: _attendanceDate,
        classId: d.classId,
        presence: presence,
        classUniqueCode: d.classUniqueCode,
        viaDelegationId: d.delegationId,
      );
      _snack('Presenze salvate.');
    } catch (e) {
      _snack('Errore salvataggio presenze: $e');
    } finally {
      if (mounted) setState(() => _savingAttendance = false);
    }
  }

  // ─── Note di lezione ──────────────────────────────────────────────────
  Widget _notesCard(SubstituteDelegation d, List<SubstituteLessonNote> notes) {
    return _card(
      title: 'Note di lezione (${notes.length})',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _noteController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Scrivi una nota della lezione…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: () => _addNote(d),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Aggiungi nota'),
            ),
          ),
          const SizedBox(height: 8),
          for (final n in notes) _noteTile(n),
        ],
      ),
    );
  }

  Widget _noteTile(SubstituteLessonNote n) {
    final repo = ref.read(substituteDelegationRepoProvider);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: Text(n.note, style: const TextStyle(fontSize: 13))),
          IconButton(
            tooltip: 'Elimina',
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            onPressed: () async {
              await repo.deleteLessonNote(n.noteId);
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Future<void> _addNote(SubstituteDelegation d) async {
    final text = _noteController.text.trim();
    if (text.isEmpty) {
      _snack('Scrivi prima una nota.');
      return;
    }
    final repo = ref.read(substituteDelegationRepoProvider);
    await repo.addLessonNote(
      delegationId: d.delegationId,
      classId: d.classId,
      classUniqueCode: d.classUniqueCode,
      date: DateTime.now(),
      note: text,
    );
    _noteController.clear();
    if (mounted) setState(() {});
    _snack('Nota aggiunta.');
  }

  // ─── Consegna dati ────────────────────────────────────────────────────
  Future<void> _sendData(SubstituteDelegation d) async {
    final repo = ref.read(substituteDelegationRepoProvider);
    final service = ref.read(substituteDelegationServiceProvider);

    final attendance = _collectAttendance(d);
    final notes = repo
        .getNotesForDelegationSync(d.delegationId)
        .map((n) => n.toMap())
        .toList();
    if (attendance.isEmpty && notes.isEmpty) {
      _snack('Non ci sono presenze o note da consegnare.');
      return;
    }

    setState(() => _sending = true);
    try {
      final chunks = await service.buildHandoverQrChunks(
        delegation: d,
        attendance: attendance,
        notes: notes,
      );
      if (!mounted) return;
      await QrChunksDialog.show(
        context,
        title: 'Consegna dati',
        subtitle:
            'Inquadra questi QR con il dispositivo del Titolare'
            ' (pulsante "Acquisisci dati").',
        chunks: chunks,
      );
    } catch (e) {
      _snack('Errore generazione QR: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  List<Map<String, dynamic>> _collectAttendance(SubstituteDelegation d) {
    final box = LocalDatabase.attendance();
    final records = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final map = LocalDatabase.toStringDynamicMap(raw);
      if (map['classId']?.toString() != d.classId) continue;
      records.add({
        'meetingId': map['meetingId']?.toString() ?? key,
        'date': map['date']?.toString(),
        'classId': map['classId']?.toString(),
        'presence': map['presence'],
        'viaDelegationId': ?map['viaDelegationId']?.toString(),
      });
    }
    return records;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────
  List<Map<String, String>> _loadStudents(String classId) {
    final box = LocalDatabase.students();
    final result = <Map<String, String>>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final map = LocalDatabase.toStringDynamicMap(raw);
      if (map['classId']?.toString() != classId) continue;
      result.add({
        'id': key,
        'name': map['name']?.toString() ?? '',
        'surname': map['surname']?.toString() ?? '',
      });
    }
    return result;
  }

  Widget _card({
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _fmt(DateTime d) => DateFormat('dd/MM/yyyy', 'it_IT').format(d);
}
