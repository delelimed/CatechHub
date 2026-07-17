import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_service.dart';
import '../../core/security/privacy_settings.dart';
import '../../shared/models/planning_meeting.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../auth/bible_quote.dart';
import '../classes/classes_provider.dart';
import '../documents/documents_repository.dart';
import '../meetings/attendance_repository.dart';
import '../planning/planning_provider.dart';
import '../students/students_repository.dart';

/// Pagina principale della dashboard di CateREG.
///
/// Mostra una panoramica completa delle attività del catechista:
/// - Versetto biblico casuale come spunto di riflessione
/// - Carta del prossimo incontro programmato
/// - Percentuale media di presenze del gruppo
/// - Studenti con molte assenze (soglia configurabile)
/// - Documenti consegnati ma non ancora riconsegnati
/// - Griglia di azioni rapide (verifica numero, allergie, uscite autonome, registro contatto)
///
/// Funge da punto di ingresso principale dell'app: tutti i dati vengono aggregati
/// dai vari repository (pianificazione, presenze, studenti, documenti) e presentati
/// in schede interattive che permettono al catechista di monitorare lo stato del gruppo.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  List<Map<String, dynamic>> _attendanceForClass(
    List<Map<String, dynamic>> attendance,
    String classId,
  ) {
    return attendance.where((record) => record['classId'] == classId).toList();
  }

  BibleQuote _randomQuote() {
    final index = Random().nextInt(bibleQuotes.length);
    return bibleQuotes[index];
  }

  double _calculatePresenceRate(List<Map<String, dynamic>> attendanceRecords) {
    var totalPresences = 0;
    var totalAbsences = 0;

    for (final record in attendanceRecords) {
      final presence = Map<String, dynamic>.from(
        record['presence'] as Map? ?? {},
      );
      for (final value in presence.values) {
        if (value == 'Presente') totalPresences++;
        if (value == 'Assente') totalAbsences++;
      }
    }

    final total = totalPresences + totalAbsences;
    if (total == 0) return 0;
    return totalPresences / total * 100;
  }

  List<_HighAbsenceStudent> _fetchHighAbsenceStudents(
    List<Map<String, dynamic>> attendanceRecords,
    Map<String, String> studentNames, {
    int threshold = 6,
  }) {
    final absenceCounts = <String, int>{};

    for (final record in attendanceRecords) {
      final presence = Map<String, dynamic>.from(
        record['presence'] as Map? ?? {},
      );
      presence.forEach((studentId, status) {
        if (status == 'Assente') {
          absenceCounts[studentId] = (absenceCounts[studentId] ?? 0) + 1;
        }
      });
    }

    final result =
        absenceCounts.entries
            .where((entry) => entry.value >= threshold)
            .map((entry) {
              final name = studentNames[entry.key];
              if (name == null || name.isEmpty) return null;
              return _HighAbsenceStudent(name: name, absences: entry.value);
            })
            .whereType<_HighAbsenceStudent>()
            .toList()
          ..sort((a, b) => b.absences.compareTo(a.absences));

    return result;
  }

  List<_PendingDocument> _fetchPendingDocuments(
    List<String> groupStudentIds,
    List<Map<String, dynamic>> documents,
    DocumentsRepository documentsRepo,
    Map<String, String> studentsById,
  ) {
    final result = <_PendingDocument>[];

    for (final document in documents) {
      final deliveries = documentsRepo.getDeliveriesSync(
        document['id'].toString(),
      );
      final pendingStudents =
          groupStudentIds
              .where((studentId) {
                final delivery = Map<String, dynamic>.from(
                  deliveries[studentId] as Map? ?? {},
                );
                return delivery['givenOutAt'] != null &&
                    delivery['receivedAt'] == null;
              })
              .map((studentId) => studentsById[studentId] ?? '')
              .where((name) => name.isNotEmpty)
              .toList()
            ..sort();

      if (pendingStudents.isNotEmpty) {
        result.add(
          _PendingDocument(
            title: document['title']?.toString() ?? 'Documento',
            students: pendingStudents,
          ),
        );
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(classesStreamProvider);
    final planningRepo = ref.watch(planningRepoProvider);
    final attendanceRepo = AttendanceRepository();
    final studentsRepo = StudentsRepository();
    final documentsRepo = DocumentsRepository();
    final privacySettings = ref.watch(privacySettingsProvider);

    return AppScaffold(
      title: 'Dashboard',
      child: classesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore caricamento dati: $e')),
        data: (classes) {
          final myClassList = classes.where(
            (c) => c.catechistIds.contains(AuthService.localUserId),
          );

          if (myClassList.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nessun gruppo assegnato. Aggiungi il catechista locale al gruppo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            );
          }

          final currentClass = myClassList.first;
          final allAttendance = attendanceRepo.getAttendanceSync();
          final classAttendance = _attendanceForClass(
            allAttendance,
            currentClass.id,
          );
          final allStudents = studentsRepo.getAllStudentsSync();
          final studentNames = {
            for (final student in allStudents)
              student.id: '${student.name} ${student.surname}'.trim(),
          };
          final presenceRate = _calculatePresenceRate(classAttendance);
          final highAbsences = _fetchHighAbsenceStudents(
            classAttendance,
            studentNames,
            threshold: privacySettings.absenceThreshold,
          );
          final pendingDocuments = _fetchPendingDocuments(
            currentClass.studentIds,
            documentsRepo.getDocumentsSync(),
            documentsRepo,
            studentNames,
          );

          return StreamBuilder<List<PlanningMeeting>>(
            stream: planningRepo.getMeetings(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final nextMeeting = _nextMeeting(
                snapshot.data!
                    .where((m) => m.classId == currentClass.id)
                    .toList(),
              );

              return LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final isWide = width >= 760;
                  final padding = width < 420 ? 12.0 : 16.0;

                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1040),
                      child: ListView(
                        padding: EdgeInsets.all(padding),
                        children: [
                          _QuoteSnippet(quote: _randomQuote()),
                          const SizedBox(height: 10),
                          _SectionTitle('Il tuo prossimo impegno'),
                          const SizedBox(height: 10),
                          _NextMeetingCard(
                            meeting: nextMeeting,
                            compact: !isWide,
                          ),
                          const SizedBox(height: 24),
                          _SectionTitle('Andamento del gruppo'),
                          const SizedBox(height: 10),
                          _OverviewCard(
                            presenceRate: presenceRate,
                            highAbsences: highAbsences,
                            compact: !isWide,
                            absenceThreshold: privacySettings.absenceThreshold,
                          ),
                          const SizedBox(height: 24),
                          _SectionTitle('Documenti in attesa'),
                          const SizedBox(height: 10),
                          _PendingDocumentsCard(documents: pendingDocuments),
                          const SizedBox(height: 24),
                          _SectionTitle('Azioni rapide'),
                          const SizedBox(height: 12),
                          _QuickActionsGrid(),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  PlanningMeeting? _nextMeeting(List<PlanningMeeting> meetings) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final futureMeetings =
        meetings
            .where(
              (m) => !DateTime(
                m.date.year,
                m.date.month,
                m.date.day,
              ).isBefore(today),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    return futureMeetings.isEmpty ? null : futureMeetings.first;
  }
}

class _HighAbsenceStudent {
  final String name;
  final int absences;

  const _HighAbsenceStudent({required this.name, required this.absences});
}

class _PendingDocument {
  final String title;
  final List<String> students;

  const _PendingDocument({required this.title, required this.students});
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: const Color(0xFF174A7E),
      ),
    );
  }
}

class _NextMeetingCard extends StatelessWidget {
  final PlanningMeeting? meeting;
  final bool compact;

  const _NextMeetingCard({required this.meeting, required this.compact});

  @override
  Widget build(BuildContext context) {
    if (meeting == null) {
      return const _Panel(
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, color: Colors.grey),
            SizedBox(width: 12),
            Expanded(child: Text('Nessun incontro futuro programmato.')),
          ],
        ),
      );
    }

    final dateBox = Container(
      width: compact ? 62 : 74,
      padding: EdgeInsets.symmetric(vertical: compact ? 10 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFF174A7E),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            DateFormat('dd').format(meeting!.date),
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 20 : 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            DateFormat('MMM', 'it_IT').format(meeting!.date).toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dateBox,
          SizedBox(width: compact ? 12 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  meeting!.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                if (meeting!.activity.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    meeting!.activity,
                    style: TextStyle(color: Colors.grey.shade700, height: 1.3),
                  ),
                ],
                if (meeting!.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    meeting!.notes,
                    style: TextStyle(color: Colors.grey.shade700, height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteSnippet extends StatelessWidget {
  final BibleQuote quote;

  const _QuoteSnippet({required this.quote});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '“${quote.text}”',
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: Colors.grey.shade800,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            quote.reference,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final double presenceRate;
  final List<_HighAbsenceStudent> highAbsences;
  final bool compact;
  final int absenceThreshold;

  const _OverviewCard({
    required this.presenceRate,
    required this.highAbsences,
    required this.compact,
    required this.absenceThreshold,
  });

  @override
  Widget build(BuildContext context) {
    final presencePanel = _MetricPanel(
      icon: Icons.trending_up_rounded,
      label: 'Presenze medie',
      value: '${presenceRate.toStringAsFixed(0)}%',
      color: Colors.green,
    );

    final absencesPanel = _HighAbsencePanel(
      students: highAbsences,
      threshold: absenceThreshold,
    );

    return compact
        ? Column(
            children: [
              presencePanel,
              const SizedBox(height: 12),
              absencesPanel,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: presencePanel),
              const SizedBox(width: 12),
              Expanded(child: absencesPanel),
            ],
          );
  }
}

class _MetricPanel extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricPanel({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(label, style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HighAbsencePanel extends StatelessWidget {
  final List<_HighAbsenceStudent> students;
  final int threshold;

  const _HighAbsencePanel({
    required this.students,
    required this.threshold,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Assenze elevate',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (students.isEmpty)
            Text(
              'Nessun ragazzo con $threshold o pi\u00f9 assenze.',
              style: const TextStyle(color: Colors.black54),
            )
          else
            ...students.map(
              (student) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        student.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    _CountBadge(text: '${student.absences}', color: Colors.red),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PendingDocumentsCard extends StatelessWidget {
  final List<_PendingDocument> documents;

  const _PendingDocumentsCard({required this.documents});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.description_outlined,
                  color: Colors.orange.shade800,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Da riconsegnare',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (documents.isEmpty)
            const Text(
              'Nessun documento consegnato risulta ancora da riconsegnare.',
              style: TextStyle(color: Colors.black54),
            )
          else
            ...documents.map(
              (document) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            document.title,
                            style: const TextStyle(
                              color: Color(0xFF174A7E),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _CountBadge(
                          text: '${document.students.length}',
                          color: Colors.orange,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: document.students
                          .map(
                            (student) => Chip(
                              label: Text(student),
                              visualDensity: VisualDensity.compact,
                              side: BorderSide(color: Colors.orange.shade100),
                              backgroundColor: Colors.orange.shade50,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actions = [
      _ActionItem(
        title: 'Verifica Numero',
        icon: Icons.phone_rounded,
        path: '/verify-number',
      ),
      _ActionItem(
        title: 'Allergie',
        icon: Icons.warning_rounded,
        path: '/allergies',
      ),
      _ActionItem(
        title: 'Uscite Autonome',
        icon: Icons.person_outline,
        path: '/autonomous-exits',
      ),
      _ActionItem(
        title: 'Registro Contatto',
        icon: Icons.contact_phone_rounded,
        path: '/contact-notes',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: constraints.maxWidth < 420 ? 220 : 260,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 68,
          ),
          itemCount: actions.length,
          itemBuilder: (context, index) {
            final item = actions[index];
            return InkWell(
              onTap: () => context.push(item.path),
              borderRadius: BorderRadius.circular(16),
              child: _Panel(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(item.icon, color: const Color(0xFF174A7E)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF174A7E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CountBadge extends StatelessWidget {
  final String text;
  final MaterialColor color;

  const _CountBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color.shade800,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Panel({required this.child, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ActionItem {
  final String title;
  final IconData icon;
  final String path;

  _ActionItem({required this.title, required this.icon, required this.path});
}
