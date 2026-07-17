import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/student_model.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../meetings/attendance_repository.dart';
import '../planning/planning_repository.dart';
import 'documents_provider.dart';
import 'documents_repository.dart';

class DocumentDetailPage extends ConsumerWidget {
  final Map<String, dynamic> document;
  final List<Student> students;

  const DocumentDetailPage({
    super.key,
    required this.document,
    required this.students,
  });

  String _formatTimestamp(dynamic timestamp) {
    final DateTime? date = DateTime.tryParse(timestamp?.toString() ?? '');
    if (date == null) return '';

    final List<String> mesi = [
      'Gen', 'Feb', 'Mar', 'Apr', 'Mag', 'Giu',
      'Lug', 'Ago', 'Set', 'Ott', 'Nov', 'Dic'
    ];

    return '${date.day} ${mesi[date.month - 1]}';
  }

  Future<int> _setDeliveredForToday() async {
    final planningRepo = PlanningRepository();
    final attendanceRepo = AttendanceRepository();
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);

    final meetings = planningRepo.getMeetingsSync().where((m) {
      final mDate = DateTime(m.date.year, m.date.month, m.date.day);
      return mDate == todayStart && !m.isReunion;
    }).toList();

    if (meetings.isEmpty) return 0;

    Map<String, dynamic>? todayAttendance;
    for (final meeting in meetings) {
      todayAttendance = attendanceRepo.getAttendanceForMeeting(meeting.id);
      if (todayAttendance != null) break;
    }

    if (todayAttendance == null) return 0;

    final presenceMap = Map<String, String>.from(
      (todayAttendance['presence'] as Map?)?.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ) ?? {},
    );

    final presentIds = presenceMap.entries
        .where((e) => e.value == 'Presente')
        .map((e) => e.key)
        .toSet();

    if (presentIds.isEmpty) return 0;

    final repo = DocumentsRepository();
    final docId = document['id']?.toString() ?? '';
    final deliveries = repo.getDeliveriesSync(docId);
    int updated = 0;

    for (final studentId in presentIds) {
      if (!students.any((s) => s.id == studentId)) continue;
      final delivery = deliveries[studentId];
      if (delivery != null && delivery['givenOutAt'] != null) continue;

      await repo.setGivenOut(
        docId: docId,
        studentId: studentId,
        isCurrentlyGiven: false,
      );
      updated++;
    }

    return updated;
  }

  Future<void> _toggleGivenOut({
    required String docId,
    required String studentId,
    required bool isCurrentlyGiven,
  }) async {
    await DocumentsRepository().setGivenOut(
      docId: docId,
      studentId: studentId,
      isCurrentlyGiven: isCurrentlyGiven,
    );
  }

  Future<void> _toggleReceived({
    required String docId,
    required String studentId,
    required bool isCurrentlyReceived,
  }) async {
    await DocumentsRepository().setReceived(
      docId: docId,
      studentId: studentId,
      isCurrentlyReceived: isCurrentlyReceived,
    );
  }

  Future<void> _toggleExonerated({
    required String docId,
    required String studentId,
    required bool isCurrentlyExonerated,
  }) async {
    await DocumentsRepository().setExonerated(
      docId: docId,
      studentId: studentId,
      isCurrentlyExonerated: isCurrentlyExonerated,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docId = document['id']?.toString() ?? '';
    final deliveriesAsync = ref.watch(documentDeliveriesProvider(docId));

    return AppScaffold(
      title: document['title']?.toString() ?? 'Dettaglio Documento',
      child: deliveriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore nel caricamento: $e')),
        data: (deliveries) {
          if (students.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Nessun ragazzo presente in questo gruppo.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final exoneratedCount = students.where(
            (s) => deliveries[s.id]?['exoneratedAt'] != null,
          ).length;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: students.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  children: [
                    _TodayDeliverButton(
                      onTap: () async {
                        final updated = await _setDeliveredForToday();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                updated > 0
                                    ? 'Consegnato a $updated ragazzi presenti oggi'
                                    : 'Nessun presente da aggiornare',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                    if (exoneratedCount > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Text(
                            '$exoneratedCount ${exoneratedCount == 1 ? 'ragazzo esonerato' : 'ragazzi esonerati'}',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              }
              final student = students[index - 1];
              final studentId = student.id;

              final deliveryData = deliveries[studentId];
              final bool isExonerated = deliveryData?['exoneratedAt'] != null;

              final dynamic givenOutTimestamp = deliveryData?['givenOutAt'];
              final dynamic receivedTimestamp = deliveryData?['receivedAt'];

              final bool isGivenOut = givenOutTimestamp != null;
              final bool isReceived = receivedTimestamp != null;

              final String dateGivenStr = _formatTimestamp(givenOutTimestamp);
              final String dateReceivedStr = _formatTimestamp(receivedTimestamp);

              String statusText = 'Da consegnare';
              Color statusColor = Colors.grey.shade600;
              if (isExonerated) {
                statusText = 'Esonerato';
                statusColor = Colors.grey;
              } else if (isGivenOut && !isReceived) {
                statusText = 'Consegnato (In attesa di riconsegna)';
                statusColor = Colors.orange.shade800;
              } else if (isReceived) {
                statusText = 'Ritirato e Completato';
                statusColor = Colors.green;
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: isExonerated ? Colors.grey.shade100 : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: isExonerated
                                  ? Colors.grey.shade300
                                  : const Color(0xFF174A7E).withValues(alpha: 0.1),
                              child: Text(
                                student.name.isNotEmpty ? student.name[0].toUpperCase() : 'R',
                                style: TextStyle(
                                  color: isExonerated ? Colors.grey.shade500 : const Color(0xFF174A7E),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${student.name} ${student.surname}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: isExonerated ? Colors.grey.shade500 : const Color(0xFF174A7E),
                                    ),
                                  ),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_vert_rounded,
                                color: isExonerated ? Colors.grey.shade400 : Colors.grey.shade600,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              onSelected: (v) async {
                                if (v == 'exonerate') {
                                  await _toggleExonerated(
                                    docId: docId,
                                    studentId: studentId,
                                    isCurrentlyExonerated: isExonerated,
                                  );
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'exonerate',
                                  child: Row(
                                    children: [
                                      Icon(
                                        isExonerated ? Icons.replay_rounded : Icons.block_rounded,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(isExonerated ? 'Revoca esonero' : 'Esonera'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (isExonerated)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.block_rounded, size: 16, color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Text(
                                  'Esonerato',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          const Divider(height: 20, thickness: 0.5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _ActionButton(
                                    label: 'Consegnato',
                                    icon: Icons.outbox,
                                    isActive: isGivenOut,
                                    activeColor: Colors.orange.shade700,
                                    onTap: () => _toggleGivenOut(
                                      docId: docId,
                                      studentId: studentId,
                                      isCurrentlyGiven: isGivenOut,
                                    ),
                                  ),
                                  if (isGivenOut && dateGivenStr.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      dateGivenStr,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ]
                                ],
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _ActionButton(
                                    label: 'Ritirato',
                                    icon: Icons.assignment_turned_in,
                                    isActive: isReceived,
                                    activeColor: Colors.green,
                                    onTap: !isGivenOut
                                        ? null
                                        : () => _toggleReceived(
                                            docId: docId,
                                            studentId: studentId,
                                            isCurrentlyReceived: isReceived,
                                          ),
                                  ),
                                  if (isReceived && dateReceivedStr.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      dateReceivedStr,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ]
                                ],
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isButtonDisabled = onTap == null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isButtonDisabled
              ? Colors.grey.shade100
              : isActive
                  ? activeColor.withValues(alpha: 0.12)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isButtonDisabled
                ? Colors.grey.shade300
                : isActive
                    ? activeColor
                    : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isButtonDisabled
                  ? Colors.grey.shade400
                  : isActive
                      ? activeColor
                      : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isButtonDisabled
                    ? Colors.grey.shade400
                    : isActive
                        ? activeColor
                        : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayDeliverButton extends StatelessWidget {
  final VoidCallback onTap;

  const _TodayDeliverButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.green.shade700,
                Colors.green.shade500,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.checklist_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Consegna di oggi',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Imposta consegnato per i presenti all\'incontro di oggi',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Applica',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
