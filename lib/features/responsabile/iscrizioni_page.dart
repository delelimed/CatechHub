// ══════════════════════════════════════════════════════════════════════════════
// iscrizioni_page.dart — CatechHub (iscrizioni, censimento e passaggio d'anno)
//
// Tab "Iscrizioni" del Responsabile Catechistico. Copre:
//   1. Censimento completo dei nuovi ragazzi (anagrafica reale [Student] nel
//      registro studenti, con validazione e consenso GDPR) e assegnazione
//      automatica/manuale alla classe di ingresso.
//   2. Spostamento dei ragazzi tra classi (passaggio singolo).
//   3. Passaggio di anno massivo (promozione in blocco) tramite
//      [PassaggioAnnoService].
//   4. "Concludi Anno Catechistico" (riservato al Responsabile): trasforma
//      le classi attive in record [HistoricalRecord] immutabili dell'archivio
//      storico e prepara il database per le nuove iscrizioni dell'anno
//      successivo (chiusura massiva, vedi [ConcludiAnnoService]).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/class_model.dart';
import '../../shared/models/parish_config.dart';
import '../../shared/models/student_model.dart';
import '../classes/classes_provider.dart';
import '../classes/classes_repository.dart';
import '../students/students_add_page.dart';
import '../students/students_repository.dart';
import '../archive/concludi_anno_service.dart';
import 'passaggio_anno_service.dart';
import 'responsabile_providers.dart';

/// Gestione iscrizioni: censimento ragazzi e passaggio di anno massivo.
class IscrizioniPage extends ConsumerStatefulWidget {
  const IscrizioniPage({super.key});

  @override
  ConsumerState<IscrizioniPage> createState() => _IscrizioniPageState();
}

class _IscrizioniPageState extends ConsumerState<IscrizioniPage> {
  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ═══════════════════════════════════════════════════════════════════════
  // CENSIMENTO COMPLETO (nuova anagrafica Student con validazione)
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> _addStudentDialog(SchoolClass c) async {
    // Riusa lo stesso identico form di inserimento usato in modalità
    // normale/associata (AddStudentPage), iscrivendo il ragazzo alla classe
    // target selezionata.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddStudentPage(
          classId: c.id,
          classUniqueCode: c.uniqueCode,
          classLabel: c.name,
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SPOSTAMENTO TRA CLASSI
  // ═════════════════════════════════════════════════════════════════════════
  Future<void> _moveStudentDialog(
    SchoolClass from,
    Student student,
    List<SchoolClass> classes,
  ) async {
    final targets = classes
        .where((c) => c.id != from.id && !c.archived)
        .toList();
    if (targets.isEmpty) {
      _snack('Nessuna altra classe disponibile.');
      return;
    }
    String targetId = targets.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Passa "${student.name} ${student.surname}"'),
          content: DropdownButtonFormField<String>(
            initialValue: targetId,
            decoration: const InputDecoration(
              labelText: 'Classe di destinazione',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final t in targets)
                DropdownMenuItem(value: t.id, child: Text(t.name)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => targetId = v);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Sposta'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final to = targets.firstWhere((t) => t.id == targetId);
    await ClassesRepository().removeStudentFromClass(from.id, student.id);
    await StudentsRepository().updateStudent(
      student.id,
      student.copyWith(classId: to.id, classUniqueCode: to.uniqueCode),
    );
    await ClassesRepository().addStudentToClass(to.id, student.id);
    _snack('${student.name} ${student.surname} spostato in "${to.name}".');
  }

  // ═════════════════════════════════════════════════════════════════════════
  // PASSAGGIO DI ANNO MASSIVO
  // ═════════════════════════════════════════════════════════════════════════
  Future<void> _startPassaggioAnno(List<SchoolClass> classes) async {
    final config = ref.read(parishConfigRepositoryProvider).getConfig();
    final currentAnno = config.annoCatechisticoCorrente.trim();
    if (currentAnno.isEmpty) {
      _snack('Configura prima l\'anno catechistico corrente nella parrocchia.');
      return;
    }
    final targetAnno = PassaggioAnnoService.annoSuccessivo(currentAnno);
    final percorsi =
        classes
            .map((c) => c.percorso)
            .where((p) => p.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final selected = <String>{};
    var archiviaRitirati = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Passaggio di anno'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Da "$currentAnno" a "$targetAnno". Le classi attive '
                  'promuoveranno al livello successivo.',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                if (percorsi.isEmpty)
                  const Text(
                    'Nessun percorso con una classe attiva.',
                    style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                  )
                else ...[
                  const Text(
                    'Percorsi da promuovere:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  for (final p in percorsi)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(p, style: const TextStyle(fontSize: 13)),
                      value: selected.contains(p),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          selected.add(p);
                        } else {
                          selected.remove(p);
                        }
                      }),
                    ),
                ],
                CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'Escludi ragazzi FERMI/RITIRATI',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Gli studenti con percorso FERMO o RITIRATO non '
                    'vengono promossi.',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: archiviaRitirati,
                  onChanged: (v) =>
                      setState(() => archiviaRitirati = v ?? true),
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Esegui promozione'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    try {
      final results = await PassaggioAnnoService().passaAnno(
        soloPercorsi: selected.isEmpty ? null : selected.toList(),
        archiviaRitirati: archiviaRitirati,
        nuovoAnno: targetAnno,
      );
      final totPromossi = results.fold<int>(0, (s, r) => s + r.promossi);
      final totRitirati = results.fold<int>(0, (s, r) => s + r.ritirati);
      _snack(
        'Anno promosso: ${results.length} classi, $totPromossi ragazzi '
        'promossi, $totRitirati ferma/ritirati. Nuovo anno: $targetAnno.',
      );
    } catch (e) {
      _snack('Errore nel passaggio di anno: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(classesStreamProvider);
    final config = ref.watch(parishConfigRepositoryProvider).getConfig();

    return classesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Errore: $e'),
      data: (classes) {
        final active = classes.where((c) => !c.archived).toList();
        return RefreshIndicator(
          onRefresh: () => ref.refresh(classesStreamProvider.future),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: ListView(
                padding: const EdgeInsets.all(4),
                children: [
                  _summaryCard(active),
                  const SizedBox(height: 12),
                  _promotionCard(classes, config),
                  const SizedBox(height: 12),
                  for (final c in active) _classCard(c, classes),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _summaryCard(List<SchoolClass> active) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? Theme.of(context).colorScheme.surfaceContainer
        : Colors.white;
    final totRagazzi = active.fold<int>(0, (s, c) => s + c.studentIds.length);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          _statTile(
            Icons.school_rounded,
            '${active.length}',
            'Classi attive',
            isDark,
          ),
          _verticalDivider(isDark),
          _statTile(
            Icons.groups_rounded,
            '$totRagazzi',
            'Ragazzi iscritti',
            isDark,
          ),
          _verticalDivider(isDark),
          _statTile(
            Icons.person_add_alt_1_rounded,
            '${active.length}',
            'Iscrivi nuovo',
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _statTile(IconData icon, String value, String label, bool isDark) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: isDark ? Colors.grey.shade400 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider(bool isDark) {
    return Container(
      width: 1,
      height: 34,
      color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
    );
  }

  Widget _promotionCard(List<SchoolClass> classes, ParishConfig config) {
    final currentAnno = config.annoCatechisticoCorrente.trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF174A7E), Color(0xFF2368B1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.trending_up_rounded,
                color: Colors.white,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Anno ${currentAnno.isEmpty ? '?' : currentAnno}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Promuovi le classi al prossimo anno catechistico o '
                      'concludi l\'anno e archivia nello storico.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: currentAnno.isEmpty
                    ? null
                    : () => _startPassaggioAnno(classes),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Passaggio di anno'),
              ),
              FilledButton.tonalIcon(
                onPressed: currentAnno.isEmpty
                    ? null
                    : () => _startConcludiAnno(classes),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Concludi anno'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CONCLUDI ANNO CATECHISTICO (archivio storico + preparazione nuove iscrizioni)
  // ═════════════════════════════════════════════════════════════════════════
  Future<void> _startConcludiAnno(List<SchoolClass> classes) async {
    final config = ref.read(parishConfigRepositoryProvider).getConfig();
    final currentAnno = config.annoCatechisticoCorrente.trim();
    if (currentAnno.isEmpty) {
      _snack('Configura prima l\'anno catechistico corrente nella parrocchia.');
      return;
    }
    final targetAnno = PassaggioAnnoService.annoSuccessivo(currentAnno);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Concludi Anno Catechistico'),
        content: Text(
          'Trasformo le classi attive dell\'anno "$currentAnno" in record '
          'storici immutabili (archivio storico e progresso dei ragazzi) e '
          'preparo il database per le nuove iscrizioni dell\'anno '
          '"$targetAnno". Le classi saranno promosse al livello successivo '
          'del percorso.\n\nL\'operazione non è reversibile.',
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

    try {
      final result = await ConcludiAnnoService().concludiAnno(
        soloPercorsi: null,
        archiviaRitirati: true,
        nuovoAnno: targetAnno,
      );
      _snack(
        'Anno concluso: ${result.records.length} record archiviati, '
        '${result.promozioni.length} classi promosse. '
        'Nuovo anno: ${result.nuovoAnno}.',
      );
    } catch (e) {
      _snack('Errore nella conclusione dell\'anno: $e');
    }
  }

  Widget _classCard(SchoolClass c, List<SchoolClass> classes) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final studentsAsync = ref.watch(studentsOfClassProvider(c.id));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainer
            : Colors.white,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${c.studentIds.length} ragazzi iscritti',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _addStudentDialog(c),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Iscrivi'),
              ),
            ],
          ),
          const Divider(height: 16),
          studentsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Errore: $e'),
            data: (students) => students.isEmpty
                ? const Text(
                    'Nessun ragazzo iscritto. Usa "Iscrivi" per il censimento.',
                    style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                  )
                : Column(
                    children: [
                      for (final s in students)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.person_rounded, size: 20),
                          title: Text(
                            '${s.name} ${s.surname}'.trim(),
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            s.annoIscrizione.isNotEmpty
                                ? 'Iscr. ${s.annoIscrizione} · ${s.statoPercorso}'
                                : s.statoPercorso,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: 'Passa a un\'altra classe',
                            icon: const Icon(
                              Icons.swap_horiz_rounded,
                              size: 18,
                            ),
                            onPressed: () => _moveStudentDialog(c, s, classes),
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
