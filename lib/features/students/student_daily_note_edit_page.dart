import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../shared/models/planning_meeting.dart';
import '../../shared/models/student_daily_note_model.dart';
import '../../shared/models/student_model.dart';
import '../planning/planning_repository.dart';
import 'student_daily_notes_repository.dart';

class StudentDailyNoteEditPage extends ConsumerStatefulWidget {
  final Student student;
  final StudentDailyNote? existing;

  const StudentDailyNoteEditPage({
    super.key,
    required this.student,
    this.existing,
  });

  @override
  ConsumerState<StudentDailyNoteEditPage> createState() =>
      _StudentDailyNoteEditPageState();
}

class _StudentDailyNoteEditPageState
    extends ConsumerState<StudentDailyNoteEditPage> {
  late final TextEditingController _textController;
  late final List<PlanningMeeting> _meetings;
  String? _meetingId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.existing?.text ?? '');
    _meetings =
        PlanningRepository()
            .getMeetingsSync()
            .where(
              (meeting) =>
                  !meeting.isReunion &&
                  ((widget.student.classId != null &&
                          widget.student.classId!.isNotEmpty &&
                          meeting.classId == widget.student.classId) ||
                      (widget.student.classUniqueCode != null &&
                          widget.student.classUniqueCode!.isNotEmpty &&
                          meeting.classUniqueCode ==
                              widget.student.classUniqueCode)),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    _meetingId = _meetings.any((m) => m.id == widget.existing?.meetingId)
        ? widget.existing?.meetingId
        : null;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _textController.text.trim();
    if (_meetingId == null || text.isEmpty) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final note = StudentDailyNote(
      id: widget.existing?.id ?? '',
      studentId: widget.student.id,
      meetingId: _meetingId!,
      classUniqueCode: widget.student.classUniqueCode,
      text: text,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );
    final repository = ref.read(studentDailyNotesRepoProvider);
    if (widget.existing == null) {
      await repository.addNote(note);
    } else {
      await repository.updateNote(widget.existing!.id, note);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? 'Nuova annotazione'
              : 'Modifica annotazione',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${widget.student.surname} ${widget.student.name}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            initialValue: _meetingId,
            decoration: const InputDecoration(
              labelText: 'Incontro del gruppo',
              border: OutlineInputBorder(),
            ),
            items: _meetings
                .map(
                  (meeting) => DropdownMenuItem(
                    value: meeting.id,
                    child: Text(
                      '${DateFormat('dd/MM/yyyy').format(meeting.date)} - ${meeting.title}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() => _meetingId = value),
          ),
          if (_meetings.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Non ci sono incontri del gruppo disponibili per questo ragazzo.',
              ),
            ),
          const SizedBox(height: 20),
          TextField(
            controller: _textController,
            maxLines: 10,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Annotazione',
              hintText: 'Scrivi cosa osservare o ricordare...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving || _meetingId == null ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('Salva annotazione'),
          ),
        ],
      ),
    );
  }
}
