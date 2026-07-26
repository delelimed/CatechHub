import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/avviso_template_model.dart';
import '../../shared/models/contact_note_model.dart';
import '../../shared/models/planning_meeting.dart';
import '../../shared/models/student_model.dart';
import '../../core/storage/local_database.dart';
import '../planning/planning_repository.dart';
import '../students/students_repository.dart';
import 'avvisi_repository.dart';
import 'avvisi_utils.dart';
import 'contact_notes_repository.dart';

class AvvisiPage extends ConsumerWidget {
  const AvvisiPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(avvisiTemplatesProvider);
    final templates = templatesAsync.asData?.value ?? [];
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Condividi avviso'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.white,
        onPressed: () => _editTemplate(context, ref, null),
        child: const Icon(Icons.add_rounded),
      ),
      body: templates.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.send_rounded,
                      size: 64,
                      color: Colors.green.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nessun avviso',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tocca + per creare un nuovo messaggio',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: templates.length,
              itemBuilder: (context, index) {
                final template = templates[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? theme.colorScheme.surfaceContainer : Colors.white,
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
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.description_rounded, color: Colors.green.shade600),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      template.title,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? theme.colorScheme.onSurface : const Color(0xFF1A1A1A),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      template.text,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.3,
                                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _ActionChip(
                                icon: Icons.share_rounded,
                                label: 'Invia',
                                color: Colors.green,
                                onTap: () => _inviaTemplate(context, ref, template),
                              ),
                              const SizedBox(width: 8),
                              _ActionChip(
                                icon: Icons.edit_rounded,
                                label: 'Modifica',
                                color: Colors.blue,
                                onTap: () => _editTemplate(context, ref, template),
                              ),
                              const SizedBox(width: 8),
                              _ActionChip(
                                icon: Icons.delete_outline,
                                label: 'Elimina',
                                color: Colors.red,
                                onTap: () => _deleteTemplate(context, ref, template),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  static const _personSpecificPlaceholders = [
    '{nome_ragazzo}',
    '{cognome_ragazzo}',
    '{nome_genitore}',
    '{assenze_consecutive}',
    '{ultima_presenza}',
  ];

  bool _hasStudentPlaceholders(String text) {
    return _personSpecificPlaceholders.any((p) => text.contains(p));
  }

  Future<void> _inviaTemplate(BuildContext context, WidgetRef ref, AvvisoTemplate template) async {
    if (!_hasStudentPlaceholders(template.text)) {
      final resolved = _resolveDateOnly(context, ref, template.text);
      openWhatsApp(null, resolved);
      return;
    }

    final student = await _selectStudent(context, ref);
    if (student == null) return;

    final parentInfo = await _selectParent(context, student);
    if (parentInfo == null) return;

    _openWhatsAppForTemplate(context, ref, template, student, parentInfo.$1, parentInfo.$2);
  }

  String _resolveDateOnly(BuildContext context, WidgetRef ref, String text) {
    if (!hasPlaceholders(text)) return text;
    try {
      final students = ref.read(studentsRepositoryProvider).getAllStudentsSync();
      if (students.isEmpty) return text;
      final student = students.first;
      if (student.classId == null) return text;

      String result = text;
      final groupName = _getClassName(student.classId!);
      final nextMeeting = _getNextMeeting(student.classId!);
      if (groupName.isNotEmpty) {
        result = result.replaceAll('{nome_gruppo}', groupName);
      }
      if (nextMeeting != null) {
        final meetingDate = '${nextMeeting.date.day.toString().padLeft(2, '0')}/${nextMeeting.date.month.toString().padLeft(2, '0')}/${nextMeeting.date.year}';
        result = result.replaceAll('{data_incontro}', meetingDate);
      }
      return result;
    } catch (_) {
      return text;
    }
  }

  Future<Student?> _selectStudent(BuildContext context, WidgetRef ref) async {
    final students = ref.read(studentsRepositoryProvider).getAllStudentsSync();
    if (students.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nessun ragazzo presente in anagrafica')),
        );
      }
      return null;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    String query = '';

    String? _studentMeetingDate(String classId) {
      final m = _getNextMeeting(classId);
      if (m == null) return null;
      return '${m.date.day.toString().padLeft(2, '0')}/${m.date.month.toString().padLeft(2, '0')}/${m.date.year}';
    }

    String _studentAbsenceInfo(Student s) {
      if (s.classId == null) return '';
      final data = computeAbsenceData(s.id, s.classId!);
      final parts = <String>[];
      if (data.lastPresenceDate != null) {
        parts.add('Ultima: ${data.lastPresenceDate}');
      }
      parts.add('Assenze: ${data.consecutiveAbsences}');
      return parts.join(' · ');
    }

    final result = await showModalBottomSheet<Student>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? Theme.of(context).colorScheme.surfaceContainer : null,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            final filtered = query.isEmpty
                ? students
                : students.where((s) =>
                    s.name.toLowerCase().contains(query.toLowerCase()) ||
                    s.surname.toLowerCase().contains(query.toLowerCase())).toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Seleziona un ragazzo',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Theme.of(context).colorScheme.onSurface : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Cerca ragazzo...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final s = filtered[index];
                        final meetingDate = s.classId != null ? _studentMeetingDate(s.classId!) : null;
                        final absInfo = _studentAbsenceInfo(s);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.withValues(alpha: 0.1),
                            child: Text(
                              '${s.name[0]}${s.surname[0]}',
                              style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600),
                            ),
                          ),
                          title: Text('${s.name} ${s.surname}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (s.classId != null)
                                Text(
                                  _getClassName(s.classId!),
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                ),
                              if (meetingDate != null || absInfo.isNotEmpty)
                                Text(
                                  [
                                    if (meetingDate != null) 'Incontro: $meetingDate',
                                    if (absInfo.isNotEmpty) absInfo,
                                  ].join(' · '),
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                ),
                            ],
                          ),
                          isThreeLine: meetingDate != null || absInfo.isNotEmpty,
                          onTap: () => Navigator.pop(ctx, s),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );

    return result;
  }

  String _getClassName(String classId) {
    if (classId.isEmpty) return '';
    try {
      final data = LocalDatabase.classes().get(classId);
      if (data != null) {
        final map = Map<String, dynamic>.from(data);
        return map['name']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  Future<(String, String)?> _selectParent(BuildContext context, Student student) async {
    final contacts = <(String label, String name, String phone)>[];

    if (student.motherPhone.isNotEmpty) {
      final name = '${student.motherName} ${student.motherSurname}'.trim();
      contacts.add(('Mamma', name.isNotEmpty ? name : student.motherName, student.motherPhone));
    }
    if (student.fatherPhone.isNotEmpty) {
      final name = '${student.fatherName} ${student.fatherSurname}'.trim();
      contacts.add(('Papà', name.isNotEmpty ? name : student.fatherName, student.fatherPhone));
    }
    if (student.studentPhone.isNotEmpty) {
      contacts.add(('Ragazzo', '${student.name} ${student.surname}', student.studentPhone));
    }

    if (contacts.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nessun numero di telefono registrato per questo ragazzo')),
        );
      }
      return null;
    }

    if (contacts.length == 1) {
      final c = contacts.first;
      return (c.$2, c.$3);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showModalBottomSheet<MapEntry<String, String>>(
      context: context,
      backgroundColor: isDark ? Theme.of(context).colorScheme.surfaceContainer : null,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Invia a...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Theme.of(context).colorScheme.onSurface : null,
                ),
              ),
              const SizedBox(height: 12),
              ...contacts.map((c) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.withValues(alpha: 0.1),
                      child: Icon(Icons.phone_android_rounded, color: Colors.green.shade600),
                    ),
                    title: Text(c.$1),
                    subtitle: Text(
                      '${c.$2} — ${c.$3}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                    onTap: () => Navigator.pop(ctx, MapEntry(c.$2, c.$3)),
                  )),
            ],
          ),
        );
      },
    );

    if (result == null) return null;
    return (result.key, result.value);
  }

  void _openWhatsAppForTemplate(
    BuildContext context,
    WidgetRef ref,
    AvvisoTemplate template,
    Student? student,
    String? parentName,
    String? phone,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String finalMessage = template.text;

    if (student != null) {
      String? groupName;
      String? meetingDate;

      if (student.classId != null) {
        groupName = _getClassName(student.classId!);
        final nextMeeting = _getNextMeeting(student.classId!);
        if (nextMeeting != null) {
          meetingDate =
              '${nextMeeting.date.day.toString().padLeft(2, '0')}/${nextMeeting.date.month.toString().padLeft(2, '0')}/${nextMeeting.date.year}';
        }
      }

      AbsenceData? absenceData;
      if (template.text.contains('{assenze_consecutive}') ||
          template.text.contains('{ultima_presenza}')) {
        absenceData = computeAbsenceData(student.id, student.classId ?? '');
      }

      finalMessage = resolvePlaceholders(
        template.text,
        student,
        parentName: parentName,
        groupName: groupName,
        meetingDate: meetingDate,
        consecutiveAbsences: absenceData?.consecutiveAbsences,
        lastPresenceDate: absenceData?.lastPresenceDate,
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Theme.of(context).colorScheme.surfaceContainer : null,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.send_rounded, color: Colors.green.shade600, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Invia messaggio',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Theme.of(context).colorScheme.onSurface : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (phone != null && student != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'A: ${parentName ?? ''} (${student.name} ${student.surname})',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  finalMessage,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Apri WhatsApp'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      openWhatsApp(phone, finalMessage);
                      if (student != null) {
                        _recordContactNote(ref, student, template.title, finalMessage, phone);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  PlanningMeeting? _getNextMeeting(String classId) {
    try {
      final repo = PlanningRepository();
      final meetings = repo.getMeetingsSync();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      PlanningMeeting? closest;

      for (final meeting in meetings) {
        if (meeting.isReunion) continue;
        final meetingDate = DateTime(meeting.date.year, meeting.date.month, meeting.date.day);
        if (!meetingDate.isBefore(today)) {
          if (closest == null || meeting.date.isBefore(closest.date)) {
            closest = meeting;
          }
        }
      }
      return closest;
    } catch (_) {
      return null;
    }
  }

  void _recordContactNote(WidgetRef ref, Student student, String title, String message, String? phone) {
    final note = ContactNote(
      id: '',
      studentId: student.id,
      dateTime: DateTime.now(),
      medium: 'whatsapp',
      notes: 'Inviato "$title"${phone != null ? ' al $phone' : ''}',
    );
    ref.read(contactNotesRepoProvider).addNote(note);
  }

  void _editTemplate(BuildContext context, WidgetRef ref, AvvisoTemplate? existing) {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final textController = TextEditingController(text: existing?.text ?? '');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? Theme.of(context).colorScheme.surfaceContainer : null,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    existing != null ? 'Modifica avviso' : 'Nuovo avviso',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Theme.of(context).colorScheme.onSurface : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: 'Titolo (es. Promemoria incontro)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Segnaposto disponibili (tocca per inserire):',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: AvvisoTemplate.placeholders.map((ph) {
                      return ActionChip(
                        label: Text(ph.code, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          final pos = textController.selection.baseOffset;
                          final text = textController.text;
                          if (pos < 0) {
                            textController.text = text + ph.code;
                          } else {
                            textController.text = text.substring(0, pos) + ph.code + text.substring(pos);
                            textController.selection = TextSelection.collapsed(offset: pos + ph.code.length);
                          }
                          setDialogState(() {});
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: textController,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: 'Testo del messaggio',
                      hintText: 'Inserisci il testo con 😊 emoji e segnaposto...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Annulla'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          if (titleController.text.trim().isEmpty || textController.text.trim().isEmpty) return;
                          final template = AvvisoTemplate(
                            id: existing?.id ?? '',
                            title: titleController.text.trim(),
                            text: textController.text.trim(),
                          );
                          ref.read(avvisiRepoProvider).save(template);
                          Navigator.pop(dialogContext);
                        },
                        child: const Text('Salva'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _deleteTemplate(BuildContext context, WidgetRef ref, AvvisoTemplate template) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Elimina avviso'),
        content: Text('Eliminare "${template.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              ref.read(avvisiRepoProvider).delete(template.id);
              Navigator.pop(dialogContext);
            },
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: color.withValues(alpha: isDark ? 0.15 : 0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
