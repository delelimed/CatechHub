// ══════════════════════════════════════════════════════════════════════════════
// historical_archive_page.dart — CatechHub (archivio storico — vista Responsabile)
//
// Vista "Archivio Storico e Progresso dei Ragazzi" riservata al Responsabile
// Catechistico (Full Access):
//   - Elenca TUTTI i record storici della parrocchia, raggruppati per anno
//     catechistico (dal più recente).
//   - Ogni record è uno snapshot immutabile: anno, classe, catechista,
//     sacramenti ricevuti, percentuale di presenza e riepilogo valutazioni.
//   - Espone il pulsante "Concludi Anno Catechistico" (chiusura massiva) e le
//     azioni singole di fine anno (Promuovi / Archivia) per ogni studente.
//
// La vista Catechista NON usa questa pagina: il catechista vede lo storico
// degli anni precedenti dentro la scheda del singolo ragazzo (card
// [StudentHistoryCard]), filtrata dalla policy [HistoricalAccessPolicy].
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_database.dart';
import '../../../shared/models/class_model.dart';
import '../../../shared/models/historical_record.dart';
import '../../../shared/models/parish_config.dart';
import '../../../shared/models/student_model.dart';
import '../../../shared/models/user_role.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../classes/classes_repository.dart';
import '../../students/students_repository.dart';
import '../concludi_anno_service.dart';
import '../historical_providers.dart';

/// Pagina archivio storico (solo Responsabile Catechistico).
class HistoricalArchivePage extends ConsumerStatefulWidget {
  const HistoricalArchivePage({super.key});

  @override
  ConsumerState<HistoricalArchivePage> createState() =>
      _HistoricalArchivePageState();
}

class _HistoricalArchivePageState extends ConsumerState<HistoricalArchivePage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    if (!RolePermissions.currentCan(RolePermission.manageParishConfig)) {
      return AppScaffold(
        title: 'Archivio storico',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.lock_outline, size: 52, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'Questa sezione è riservata al Responsabile Catechistico.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final config = _currentConfig();
    final year = config.annoCatechisticoCorrente.trim();

    return AppScaffold(
      title: 'Archivio storico',
      floatingActionButton: year.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : () => _confirmConcludiAnno(year),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_busy ? 'Concludo…' : 'Concludi Anno'),
            ),
      child: const _ArchiveBody(),
    );
  }

  ParishConfig _currentConfig() {
    try {
      final raw = LocalDatabase.parishConfig().get(ParishConfig.storageKey);
      if (raw == null) return ParishConfig.empty;
      return ParishConfig.fromMap(LocalDatabase.toStringDynamicMap(raw));
    } catch (_) {
      return ParishConfig.empty;
    }
  }

  /// Conferma e avvia la chiusura massiva dell'anno catechistico.
  Future<void> _confirmConcludiAnno(String currentYear) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Concludi Anno Catechistico'),
        content: Text(
          'Trasformo le classi attive dell\'anno "$currentYear" in record '
          'storici immutabili e preparo il database per le nuove iscrizioni '
          'dell\'anno successivo. Le classi saranno promosse al livello '
          'seguente del percorso.\n\nL\'operazione non è reversibile.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Concludi anno'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final result = await ConcludiAnnoService().concludiAnno();
      setState(() => _busy = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Anno concluso: ${result.records.length} record archiviati, '
            '${result.promozioni.length} classi promosse. '
            'Nuovo anno: ${result.nuovoAnno}.',
          ),
        ),
      );
    } catch (e) {
      setState(() => _busy = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore: $e')));
    }
  }
}

/// Corpo della pagina: elenco dei record raggruppati per anno.
class _ArchiveBody extends ConsumerWidget {
  const _ArchiveBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(historicalRecordsStreamProvider);

    return recordsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Errore: $e')),
      data: (records) {
        if (records.isEmpty) {
          return const _EmptyState();
        }
        final byYear = <String, List<HistoricalRecord>>{};
        for (final r in records) {
          byYear.putIfAbsent(r.academicYear, () => []).add(r);
        }
        final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
        return RefreshIndicator(
          onRefresh: () => ref.refresh(historicalRecordsStreamProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final year in years) ...[
                _YearHeader(year: year, count: byYear[year]!.length),
                const SizedBox(height: 8),
                for (final record in byYear[year]!)
                  _ArchiveRecordCard(record: record),
                const SizedBox(height: 16),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Nessun record storico archiviato.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Usa "Concludi Anno Catechistico" al termine dell\'anno '
              'per archiviare le classi e preparare le nuove iscrizioni.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _YearHeader extends StatelessWidget {
  final String year;
  final int count;

  const _YearHeader({required this.year, required this.count});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(
          Icons.calendar_month_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          'Anno $year',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isDark ? Colors.blueGrey.shade700 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count record',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _ArchiveRecordCard extends ConsumerWidget {
  final HistoricalRecord record;

  const _ArchiveRecordCard({required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return FutureBuilder<Student?>(
      future: _studentById(record.studentId),
      builder: (context, snapshot) {
        final student = snapshot.data;
        final name = student == null
            ? 'Ragazzo eliminato'
            : '${student.name} ${student.surname}'.trim();

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? theme.colorScheme.surfaceContainer : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.primary.withValues(
                      alpha: 0.12,
                    ),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          record.className.isEmpty
                              ? 'Classe non specificata'
                              : record.className,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Presenze ${record.attendancePercentage.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              if (record.sacramentsReceived.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in record.sacramentsReceived)
                      Chip(
                        label: Text(
                          s.label,
                          style: const TextStyle(fontSize: 10),
                        ),
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
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
              const Divider(height: 16),
              _StudentEndOfYearActions(record: record),
            ],
          ),
        );
      },
    );
  }

  Future<Student?> _studentById(String id) async {
    for (final s in await StudentsRepository().getAllStudentsSync()) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// Azioni singole di fine anno: Promuovi / Archivia.
class _StudentEndOfYearActions extends ConsumerStatefulWidget {
  final HistoricalRecord record;

  const _StudentEndOfYearActions({required this.record});

  @override
  ConsumerState<_StudentEndOfYearActions> createState() =>
      _StudentEndOfYearActionsState();
}

class _StudentEndOfYearActionsState
    extends ConsumerState<_StudentEndOfYearActions> {
  bool _busy = false;

  HistoricalRecord get record => widget.record;

  @override
  Widget build(BuildContext context) {
    final cls = _classById(record.classId);
    return FutureBuilder<Student?>(
      future: _studentById(record.studentId),
      builder: (context, snapshot) {
        final student = snapshot.data;

        if (student == null || cls == null) {
          return Text(
            'Ragazzo non più presente nelle classi attive.',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: Colors.grey.shade600,
            ),
          );
        }

        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _promuovi(student, cls),
                icon: const Icon(Icons.trending_up_rounded, size: 16),
                label: const Text('Promuovi'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _archivia(student, cls),
                icon: const Icon(Icons.archive_outlined, size: 16),
                label: const Text('Archivia'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<Student?> _studentById(String id) async {
    for (final s in await StudentsRepository().getAllStudentsSync()) {
      if (s.id == id) return s;
    }
    return null;
  }

  SchoolClass? _classById(String id) {
    if (id.isEmpty) return null;
    for (final c in ClassesRepository().getClassesSync()) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _promuovi(Student student, SchoolClass cls) async {
    setState(() => _busy = true);
    try {
      await ConcludiAnnoService().promuoviStudente(
        student,
        cls,
        testNow: DateTime.now(),
      );
      _snack(
        '${student.name} ${student.surname} promosso all\'anno successivo.',
      );
    } catch (e) {
      _snack('Errore: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archivia(Student student, SchoolClass cls) async {
    setState(() => _busy = true);
    try {
      await ConcludiAnnoService().archiviaStudente(
        student,
        cls,
        testNow: DateTime.now(),
      );
      _snack('${student.name} ${student.surname} archiviato ad anno concluso.');
    } catch (e) {
      _snack('Errore: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
