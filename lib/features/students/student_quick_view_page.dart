import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/attachment_parent_type.dart';
import '../../shared/models/contact_note_model.dart';
import '../../shared/models/planning_meeting.dart';
import '../../shared/models/student_daily_note_model.dart';
import '../../shared/models/student_model.dart';
import '../attachments/widgets/attachments_section.dart';
import '../contact_notes/contact_notes_repository.dart';
import '../contact_notes/student_contact_notes_page.dart';
import '../documents/documents_provider.dart';
import '../meetings/attendance_repository.dart';
import '../planning/planning_repository.dart';
import 'student_daily_notes_repository.dart';
import 'students_repository.dart';

final studentsRepoProvider = Provider((ref) => StudentsRepository());

final _studentDailyNotesStreamProvider = StreamProvider.autoDispose
    .family<List<StudentDailyNote>, String>((ref, studentId) {
  return ref.read(studentDailyNotesRepoProvider).getNotesForStudent(studentId);
});

final _studentAbsencesProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, studentId) {
  final attendanceRepo = AttendanceRepository();
  final planningRepo = PlanningRepository();

  return attendanceRepo.getAttendance().map((attendanceRecords) {
    final meetings = planningRepo.getMeetingsSync();
    final meetingMap = {for (var m in meetings) m.id: m};

    final absences = <Map<String, dynamic>>[];

    for (final record in attendanceRecords) {
      final presenceMap = Map<String, dynamic>.from(record['presence'] as Map? ?? {});
      final studentStatus = presenceMap[studentId]?.toString();

      if (studentStatus == 'Assente') {
        final meeting = meetingMap[record['id']];
        final date = DateTime.tryParse(record['date']?.toString() ?? '') ?? DateTime.now();

        absences.add({
          'date': date,
          'meetingTitle': meeting?.title ?? 'Riunione sconosciuta',
          'meetingActivity': meeting?.activity ?? '',
          'isReunion': meeting?.isReunion ?? false,
        });
      }
    }

    absences.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    return absences;
  });
});

/// Dashboard riassuntiva completa per un singolo studente: mostra in cards
/// verticali i dati personali, i genitori (con azioni telefono/WhatsApp),
/// le allergie e uscite, lo stato dei documenti (consegna/pending), gli
/// allegati, le note generali (modificabili inline), le annotazioni
/// giornaliere (CRUD con dialogo), le note di contatto (ultime 3 con
/// collegamento a tutte) e lo storico assenze.
/// Usa [Student], [StudentDailyNote], [ContactNote] e [PlanningMeeting];
/// attinge da [StudentsRepository], [StudentDailyNotesRepository],
/// [AttendanceRepository], [PlanningRepository] e [DocumentsProvider].
/// Flusso: nucleo della consultazione rapida, raggiunto da [StudentsPage].
class StudentQuickViewPage extends ConsumerStatefulWidget {
  final Student student;

  const StudentQuickViewPage({
    super.key,
    required this.student,
  });

  @override
  ConsumerState<StudentQuickViewPage> createState() =>
      _StudentQuickViewPageState();
}

class _StudentQuickViewPageState extends ConsumerState<StudentQuickViewPage> {
  late Student _student;

  @override
  void initState() {
    super.initState();
    _student = widget.student;
  }

  Future<void> _updateNotes(String? notes) async {
    final updated = _student.copyWith(notes: notes);
    await ref.read(studentsRepoProvider).updateStudent(_student.id, updated);
    setState(() => _student = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF174A7E),
        foregroundColor: Colors.white,
        title: const Text('Scheda Ragazzo'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeaderCard(student: _student),
            const SizedBox(height: 16),
            _PersonalInfoCard(student: _student),
            const SizedBox(height: 16),
            _ParentsCard(student: _student),
            const SizedBox(height: 16),
            _AllergiesCard(student: _student),
            const SizedBox(height: 16),
            _DocumentsCard(studentId: _student.id),
            const SizedBox(height: 16),
            AttachmentsSection(
              parentId: _student.id,
              parentType: AttachmentParentType.student,
            ),
            const SizedBox(height: 16),
            _NotesCard(
              student: _student,
              onEdit: () => _showEditNotesDialog(),
              onDelete: _student.notes != null && _student.notes!.isNotEmpty
                  ? () => _showDeleteNotesConfirm()
                  : null,
            ),
            const SizedBox(height: 16),
            _DailyAnnotationsCard(studentId: _student.id),
            const SizedBox(height: 16),
            _ContactNotesCard(student: _student),
            const SizedBox(height: 16),
            _AbsencesCard(studentId: _student.id),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditNotesDialog() async {
    final controller = TextEditingController(text: _student.notes ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifica note'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Inserisci note generali...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (result != null) {
      await _updateNotes(result.isEmpty ? null : result);
    }
  }

  Future<void> _showDeleteNotesConfirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina note'),
        content: const Text('Vuoi cancellare le note generali?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _updateNotes(null);
    }
  }
}

class _HeaderCard extends StatelessWidget {
  final Student student;

  const _HeaderCard({required this.student});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF174A7E), Color(0xFF2E5A8F)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 35,
            backgroundColor: Colors.white,
            child: Text(
              student.name.isNotEmpty ? student.name[0] : '?',
              style: const TextStyle(
                color: Color(0xFF174A7E),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${student.surname} ${student.name}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('dd/MM/yyyy').format(student.birthDate),
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalInfoCard extends StatelessWidget {
  final Student student;

  const _PersonalInfoCard({required this.student});

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Dati Personali',
      icon: Icons.person_rounded,
      color: const Color(0xFF174A7E),
      children: [
        _InfoRow('Nome', student.name),
        _InfoRow('Cognome', student.surname),
        _InfoRow(
          'Data di nascita',
          DateFormat('dd/MM/yyyy').format(student.birthDate),
        ),
        if (student.studentPhone.isNotEmpty)
          _InfoRow('Cellulare', student.studentPhone, isPhone: true),
      ],
    );
  }
}

class _ParentsCard extends StatelessWidget {
  final Student student;

  const _ParentsCard({required this.student});

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _whatsapp(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$normalized');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Genitori',
      icon: Icons.family_restroom_rounded,
      color: Colors.green,
      children: [
        if (student.motherName.isNotEmpty || student.motherSurname.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Madre',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                  fontSize: 14,
                ),
              ),
              _InfoRow('Nome', '${student.motherName} ${student.motherSurname}'),
              if (student.motherPhone.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: _InfoRow('Telefono', student.motherPhone),
                    ),
                    IconButton(
                      icon: const Icon(Icons.phone, color: Colors.green),
                      onPressed: () => _call(student.motherPhone),
                    ),
                    IconButton(
                      icon: const Icon(Icons.message, color: Colors.green),
                      onPressed: () => _whatsapp(student.motherPhone),
                    ),
                  ],
                ),
            ],
          ),
        if (student.fatherName.isNotEmpty || student.fatherSurname.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text(
                'Padre',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                  fontSize: 14,
                ),
              ),
              _InfoRow('Nome', '${student.fatherName} ${student.fatherSurname}'),
              if (student.fatherPhone.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: _InfoRow('Telefono', student.fatherPhone),
                    ),
                    IconButton(
                      icon: const Icon(Icons.phone, color: Colors.green),
                      onPressed: () => _call(student.fatherPhone),
                    ),
                    IconButton(
                      icon: const Icon(Icons.message, color: Colors.green),
                      onPressed: () => _whatsapp(student.fatherPhone),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}

class _AllergiesCard extends StatelessWidget {
  final Student student;

  const _AllergiesCard({required this.student});

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Allergie e Autorizzazioni',
      icon: Icons.medical_information_rounded,
      color: Colors.orange,
      children: [
        if (student.allergies != null && student.allergies!.isNotEmpty)
          _InfoRow('Allergie', student.allergies!)
        else
          Text(
            'Nessuna allergia registrata',
            style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic),
          ),
        const SizedBox(height: 8),
        if (student.autonomousExits != null && student.autonomousExits!.isNotEmpty)
          _InfoRow('Uscite autonome', _formatExits(student.autonomousExits!))
        else
          Text(
            'Nessuna uscita autonome autorizzata',
            style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic),
          ),
      ],
    );
  }

  String _formatExits(String exits) {
    if (exits.startsWith('altro:')) {
      return exits.replaceFirst('altro:', 'Altro: ');
    }
    return exits;
  }
}

class _DocumentsCard extends ConsumerWidget {
  final String studentId;

  const _DocumentsCard({required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(documentsStreamProvider);

    return _InfoCard(
      title: 'Documenti da consegnare',
      icon: Icons.description_rounded,
      color: Colors.purple,
      children: [
        docsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Text('Errore caricamento documenti'),
          data: (documents) {
            if (documents.isEmpty) {
              return Text(
                'Nessun documento richiesto',
                style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: documents.map((doc) {
                final docId = doc['id'].toString();
                final deliveriesAsync = ref.watch(documentDeliveriesProvider(docId));

                return deliveriesAsync.when(
                  loading: () => const SizedBox(height: 30),
                  error: (_, __) => const SizedBox(height: 30),
                  data: (deliveries) {
                    final delivery = deliveries[studentId];
                    final isReceived = delivery != null && delivery['receivedAt'] != null;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            isReceived ? Icons.check_circle_rounded : Icons.pending_rounded,
                            color: isReceived ? Colors.green : Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              doc['title']?.toString() ?? 'Documento',
                              style: TextStyle(
                                color: isReceived ? Colors.grey.shade700 : Colors.orange.shade800,
                                decoration: isReceived ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                          if (!isReceived)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Da consegnare',
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _NotesCard extends StatelessWidget {
  final Student student;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _NotesCard({
    required this.student,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Note',
      icon: Icons.note_rounded,
      color: Colors.blue,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            onPressed: onEdit,
            tooltip: 'Modifica note',
          ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
              onPressed: onDelete,
              tooltip: 'Elimina note',
            ),
        ],
      ),
      children: [
        if (student.notes != null && student.notes!.isNotEmpty)
          Text(
            student.notes!,
            style: const TextStyle(fontSize: 14),
          )
        else
          Text(
            'Nessuna nota registrata',
            style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic),
          ),
      ],
    );
  }
}

class _DailyAnnotationsCard extends ConsumerWidget {
  final String studentId;

  const _DailyAnnotationsCard({required this.studentId});

  Map<String, PlanningMeeting> _meetingsMap(List<PlanningMeeting> meetings) {
    return {for (var m in meetings) m.id: m};
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(_studentDailyNotesStreamProvider(studentId));
    return _InfoCard(
      title: 'Annotazioni giornaliere',
      icon: Icons.auto_stories_rounded,
      color: Colors.indigo,
      trailing: IconButton(
        icon: const Icon(Icons.add_circle_outline, size: 22, color: Colors.indigo),
        onPressed: () => _showAddEditDialog(context, ref, null, null),
        tooltip: 'Aggiungi annotazione',
      ),
      children: [
        notesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Errore: $e'),
          data: (notes) {
            if (notes.isEmpty) {
              return Text(
                'Nessuna annotazione',
                style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic),
              );
            }
            final meetings = PlanningRepository().getMeetingsSync();
            final meetingMap = _meetingsMap(meetings);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: notes.map((note) {
                final meeting = meetingMap[note.meetingId];
                final meetingTitle = meeting != null
                    ? '${DateFormat('dd/MM/yyyy').format(meeting.date)} - ${meeting.title}'
                    : 'Giornata sconosciuta';
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: Colors.indigo.shade300),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              meetingTitle,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.indigo.shade700,
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showAddEditDialog(context, ref, note, meetingTitle);
                              } else if (value == 'delete') {
                                _showDeleteConfirm(context, ref, note);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 18),
                                    SizedBox(width: 8),
                                    Text('Modifica'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, size: 18, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Elimina', style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                            icon: const Icon(Icons.more_vert, size: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        note.text,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${DateFormat('dd/MM/yy HH:mm').format(note.createdAt)}${note.updatedAt != note.createdAt ? ' (modificato)' : ''}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _showAddEditDialog(
    BuildContext context,
    WidgetRef ref,
    StudentDailyNote? existing,
    String? existingMeetingLabel,
  ) async {
    final textController = TextEditingController(text: existing?.text ?? '');
    final meetings = PlanningRepository().getMeetingsSync()
      ..sort((a, b) => b.date.compareTo(a.date));
    String? selectedMeetingId = existing?.meetingId;
    final themeColor = Colors.indigo;

    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing != null ? 'Modifica annotazione' : 'Nuova annotazione'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Giorno di catechesi:', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedMeetingId,
                    hint: const Text('Seleziona un giorno...'),
                    isExpanded: true,
                    items: meetings.map((m) {
                      return DropdownMenuItem(
                        value: m.id,
                        child: Text(
                          '${DateFormat('dd/MM/yyyy').format(m.date)} - ${m.title}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      setDialogState(() => selectedMeetingId = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Scrivi annotazione...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () {
                final text = textController.text.trim();
                if (text.isEmpty || selectedMeetingId == null) return;
                Navigator.pop(ctx, {
                  'meetingId': selectedMeetingId!,
                  'text': text,
                });
              },
              style: ElevatedButton.styleFrom(backgroundColor: themeColor),
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    final repo = ref.read(studentDailyNotesRepoProvider);
    if (existing != null) {
      final updated = existing.copyWith(
        meetingId: result['meetingId'],
        text: result['text'],
        updatedAt: DateTime.now(),
      );
      await repo.updateNote(existing.id, updated);
    } else {
      final note = StudentDailyNote(
        id: '',
        studentId: studentId,
        meetingId: result['meetingId']!,
        text: result['text']!,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await repo.addNote(note);
    }
  }

  Future<void> _showDeleteConfirm(
    BuildContext context,
    WidgetRef ref,
    StudentDailyNote note,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina annotazione'),
        content: const Text('Vuoi cancellare questa annotazione?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(studentDailyNotesRepoProvider).deleteNote(note.id);
    }
  }
}

class _AbsencesCard extends ConsumerWidget {
  final String studentId;

  const _AbsencesCard({required this.studentId});

  void _showFullHistory(BuildContext context, WidgetRef ref, String studentId) {
    final attendanceRepo = AttendanceRepository();
    final planningRepo = PlanningRepository();
    final allAttendance = attendanceRepo.getAttendanceSync();
    final meetings = planningRepo.getMeetingsSync();
    final meetingMap = {for (var m in meetings) m.id: m};

    final records = <Map<String, dynamic>>[];
    for (final record in allAttendance) {
      final presenceMap = Map<String, dynamic>.from(record['presence'] as Map? ?? {});
      final status = presenceMap[studentId]?.toString();
      if (status == null) continue;

      final meeting = meetingMap[record['id']];
      final date = DateTime.tryParse(record['date']?.toString() ?? '') ?? DateTime.now();

      records.add({
        'date': date,
        'status': status,
        'meetingTitle': meeting?.title ?? 'Sconosciuto',
        'meetingActivity': meeting?.activity ?? '',
        'isReunion': meeting?.isReunion ?? false,
      });
    }
    records.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Storico presenze',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF174A7E),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: records.isEmpty
                    ? Center(
                        child: Text(
                          'Nessuna presenza registrata',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: records.length,
                        itemBuilder: (_, i) {
                          final r = records[i];
                          final date = r['date'] as DateTime;
                          final isPresent = r['status'] == 'Presente';
                          final title = r['meetingTitle'] as String;
                          final activity = r['meetingActivity'] as String;
                          final isReunion = r['isReunion'] as bool;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isPresent
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isPresent
                                    ? Colors.green.shade200
                                    : Colors.red.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: isPresent
                                        ? Colors.green
                                        : Colors.red,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      isPresent ? 'P' : 'A',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            DateFormat('dd/MM/yyyy').format(date),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: isPresent
                                                  ? Colors.green.shade900
                                                  : Colors.red.shade900,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (isReunion)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade100,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Riunione',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color: Colors.orange.shade900,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (activity.isNotEmpty)
                                        Text(
                                          activity,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final absencesAsync = ref.watch(_studentAbsencesProvider(studentId));

    return InkWell(
      onTap: () => _showFullHistory(context, ref, studentId),
      borderRadius: BorderRadius.circular(16),
      child: _InfoCard(
        title: 'Assenze',
        icon: Icons.event_busy_rounded,
        color: Colors.red,
        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
        children: [
          absencesAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => Text(
              'Errore nel caricamento assenze: $e',
              style: TextStyle(color: Colors.red.shade700),
            ),
            data: (absences) {
              if (absences.isEmpty) {
                return Text(
                  'Nessuna assenza registrata',
                  style: TextStyle(color: Colors.grey.shade600),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tocca per vedere lo storico completo',
                    style: TextStyle(
                      color: Colors.red.shade400,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...absences.take(3).map((absence) {
                    final date = absence['date'] as DateTime;
                    final title = absence['meetingTitle'] as String;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200, width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: Colors.red.shade700),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat('dd/MM/yyyy').format(date),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade900,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  title,
                                  style: const TextStyle(fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  if (absences.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '+ ${absences.length - 3} altre assenze',
                        style: TextStyle(
                          color: Colors.red.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
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
}

class _ContactNotesCard extends ConsumerWidget {
  final Student student;

  const _ContactNotesCard({required this.student});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(contactNotesRepoProvider);
    final notes = repo.getNotesForStudentSync(student.id);
    final recentNotes = notes.take(3).toList();

    return _InfoCard(
      title: 'Note di Contatto',
      icon: Icons.contact_phone_rounded,
      color: Colors.teal,
      children: [
        if (recentNotes.isEmpty)
          Text(
            'Nessuna nota di contatto',
            style: TextStyle(
                color: Colors.grey.shade600, fontStyle: FontStyle.italic),
          )
        else
          ...recentNotes.map((note) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _mediumColor(note.medium).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _mediumColor(note.medium).withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_mediumIcon(note.medium),
                            size: 16, color: _mediumColor(note.medium)),
                        const SizedBox(width: 6),
                        Text(
                          ContactNote.mediumLabel(note.medium),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: _mediumColor(note.medium),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('dd/MM/yy HH:mm').format(note.dateTime),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      note.notes,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              )),
        if (notes.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+ ${notes.length - 3} altre note',
              style: TextStyle(
                fontSize: 12,
                color: Colors.teal.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      StudentContactNotesPage(student: student),
                ),
              );
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Vedi tutte'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.teal,
              side: const BorderSide(color: Colors.teal),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;
  final Widget? trailing;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isPhone;

  const _InfoRow(this.label, this.value, {this.isPhone = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 14,
                fontWeight: isPhone ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}