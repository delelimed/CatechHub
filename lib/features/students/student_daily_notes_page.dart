import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/class_scoped_providers.dart';
import '../../shared/models/planning_meeting.dart';
import '../../shared/models/student_daily_note_model.dart';
import '../../shared/models/student_model.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../planning/planning_repository.dart';
import 'student_daily_notes_repository.dart';

class StudentDailyNotesPage extends ConsumerWidget {
  const StudentDailyNotesPage({super.key});

  Future<void> _editNote(
    BuildContext context,
    WidgetRef ref,
    Student student,
    List<PlanningMeeting> meetings,
    StudentDailyNote? existing,
  ) async {
    final controller = TextEditingController(text: existing?.text ?? '');
    var meetingId =
        existing?.meetingId ?? (meetings.isNotEmpty ? meetings.first.id : null);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            existing == null ? 'Nuova annotazione' : 'Modifica annotazione',
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: meetingId,
                  decoration: const InputDecoration(labelText: 'Incontro'),
                  items: meetings
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
                  onChanged: (value) => setState(() => meetingId = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 5,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Annotazione',
                    hintText: 'Scrivi cosa osservare o ricordare...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: meetingId == null || controller.text.trim().isEmpty
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final note = StudentDailyNote(
                        id: existing?.id ?? '',
                        studentId: student.id,
                        meetingId: meetingId!,
                        classUniqueCode: student.classUniqueCode,
                        text: controller.text.trim(),
                        createdAt: existing?.createdAt ?? now,
                        updatedAt: now,
                      );
                      final repo = ref.read(studentDailyNotesRepoProvider);
                      if (existing == null) {
                        await repo.addNote(note);
                      } else {
                        await repo.updateNote(existing.id, note);
                      }
                      if (context.mounted) Navigator.pop(context, true);
                    },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (saved == true) ref.invalidate(studentDailyNotesRepositoryProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(currentClassStudentsSyncProvider);
    final meetings =
        ref
            .read(planningRepositoryProvider)
            .getMeetingsSync()
            .where((meeting) => !meeting.isReunion)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final repo = ref.read(studentDailyNotesRepoProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AppScaffold(
      title: 'Annotazioni giornaliere',
      child: studentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Errore: $error')),
        data: (students) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Annotazioni del gruppo',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Raccogli osservazioni per incontro e ritrovale rapidamente nella scheda di ogni ragazzo.',
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 18),
            ...students.map((student) {
              final notes = repo.getNotesForStudentSync(student.id);
              final latest = notes.isEmpty ? null : notes.first;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      student.surname.isEmpty
                          ? '?'
                          : student.surname[0].toUpperCase(),
                    ),
                  ),
                  title: Text('${student.surname} ${student.name}'),
                  subtitle: latest == null
                      ? const Text('Nessuna annotazione')
                      : Text(
                          latest.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Aggiungi annotazione',
                    onPressed: () =>
                        _editNote(context, ref, student, meetings, null),
                  ),
                  onTap: () =>
                      _showStudentNotes(context, ref, student, meetings, notes),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _showStudentNotes(
    BuildContext context,
    WidgetRef ref,
    Student student,
    List<PlanningMeeting> meetings,
    List<StudentDailyNote> notes,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${student.surname} ${student.name}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (notes.isEmpty)
              const Text('Nessuna annotazione')
            else
              ...notes.map(
                (note) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(note.text),
                  subtitle: Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(note.createdAt),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        await _editNote(context, ref, student, meetings, note);
                        if (context.mounted) Navigator.pop(context);
                      } else {
                        await ref
                            .read(studentDailyNotesRepoProvider)
                            .deleteNote(note.id);
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Modifica')),
                      PopupMenuItem(value: 'delete', child: Text('Elimina')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
