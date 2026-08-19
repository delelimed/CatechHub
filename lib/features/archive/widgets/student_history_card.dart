// ══════════════════════════════════════════════════════════════════════════════
// student_history_card.dart — CatechHub (storico anni precedenti di un ragazzo)
//
// Card mostrata nella scheda del ragazzo (vista Catechista): elenca lo storico
// degli anni catechistici PRECEDENTI del ragazzo, attingendo dall'archivio
// storico con ACL applicata. Se il ragazzo NON è più in una classe del
// catechista, la policy filtra i suoi record: la card non viene renderizzata
// (i dati locali "scadono" e spariscono dalla vista).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/historical_record.dart';
import '../../../shared/models/student_model.dart';
import '../historical_providers.dart';

/// Card dello storico anni precedenti per [student].
class StudentHistoryCard extends ConsumerWidget {
  final Student student;

  const StudentHistoryCard({super.key, required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(historicalAccessPolicyProvider);

    // Il catechista vede lo storico solo dei ragazzi attualmente nelle sue
    // classi. Se il ragazzo non è più assegnato, la card sparisce del tutto.
    if (!policy.isFullAccess &&
        !policy.visibleStudentIdsForCatechist().contains(student.id)) {
      return const SizedBox.shrink();
    }

    final historyAsync = ref.watch(studentHistoryStreamProvider(student.id));

    return historyAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (records) {
        if (records.isEmpty) return const SizedBox.shrink();
        return _InfoCard(
          title: 'Storico anni precedenti',
          icon: Icons.history_rounded,
          color: const Color(0xFF174A7E),
          children: [
            for (final record in records) _HistoryTile(record: record),
          ],
        );
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final HistoricalRecord record;
  const _HistoryTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.blueGrey.withValues(alpha: 0.15)
            : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.blueGrey.withValues(alpha: 0.3)
              : Colors.blue.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded, size: 16, color: primary),
              const SizedBox(width: 6),
              Text(
                record.academicYear,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? primary : const Color(0xFF174A7E),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: isDark ? 0.25 : 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Presenze ${record.attendancePercentage.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? primary : const Color(0xFF174A7E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            record.className.isEmpty
                ? 'Classe non specificata'
                : record.className,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.black54,
            ),
          ),
          if (record.sacramentsReceived.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in record.sacramentsReceived)
                  Chip(
                    label: Text(s.label, style: const TextStyle(fontSize: 10)),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.green.shade50,
                    side: BorderSide(color: Colors.green.shade200),
                  ),
              ],
            ),
          ],
          if (record.evaluationsSummary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              record.evaluationsSummary,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Card informativa riutilizzabile (stile coerente con la scheda ragazzo).
class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? theme.colorScheme.primary : color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
