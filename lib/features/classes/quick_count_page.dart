/// Pagina "Conteggio rapido" di CateREG: verifica la completezza di un
/// gruppo rispetto all'appello di oggi.
///
/// Il catechista seleziona una o più classi, inserisce il numero di ragazzi
/// rilevati fisicamente e avvia la verifica:
/// - Se oggi non esiste un appello per le classi selezionate, avvisa e si
///   ferma (non procede).
/// - Se il conteggio coincide con i presenti all'appello, avvisa che il
///   gruppo è completo.
/// - Se non coincide, mostra l'elenco dei SOLI presenti all'appello (in
///   ordine alfabetico) con checkbox per marcare chi è stato realmente
///   visto e individuare così i possibili mancanti.
///
/// IMPORTANTE: questa funzione NON salva nulla e NON modifica l'appello
/// svolto: è solo un supporto di verifica in presenza.
library;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/current_class_provider.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/student_model.dart';
import '../meetings/attendance_repository.dart';
import '../students/students_provider.dart';
import 'quick_count_logic.dart';

/// Dati raccolti nella fase di verifica, mostrati nella fase di confronto.
class _QuickCountData {
  final int detected;
  final int present;
  final List<Student> presentStudents;
  final List<SchoolClass> classes;

  const _QuickCountData({
    required this.detected,
    required this.present,
    required this.presentStudents,
    required this.classes,
  });

  String? _classNameFor(String classId) {
    for (final c in classes) {
      if (c.id == classId) return c.name;
    }
    return null;
  }

  /// Raggruppa i presenti per classe (ordine: lista classi), mantenendo
  /// l'ordinamento alfabetico degli studenti.
  List<MapEntry<String, List<Student>>> get byClass {
    final grouped = <String, List<Student>>{};
    for (final s in presentStudents) {
      final key = _classNameFor(s.classId ?? '') ?? 'Senza gruppo';
      grouped.putIfAbsent(key, () => []).add(s);
    }
    return grouped.entries.toList();
  }
}

enum _QuickCountPhase { form, review }

class QuickCountPage extends ConsumerStatefulWidget {
  const QuickCountPage({super.key});

  @override
  ConsumerState<QuickCountPage> createState() => _QuickCountPageState();
}

class _QuickCountPageState extends ConsumerState<QuickCountPage> {
  final Set<String> _selectedClassIds = {};
  final Set<String> _seenIds = {};
  final TextEditingController _countController = TextEditingController();
  _QuickCountPhase _phase = _QuickCountPhase.form;
  _QuickCountData? _data;

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _verify() async {
    final detected = int.tryParse(_countController.text.trim());
    if (_selectedClassIds.isEmpty) {
      _showSnack('Seleziona almeno una classe');
      return;
    }
    if (detected == null || detected < 0) {
      _showSnack('Inserisci un numero di persone valido');
      return;
    }

    final attendance = ref.read(attendanceRepositoryProvider).getAttendanceSync();
    final todayRecords = QuickCountLogic.recordsOfClasses(
      QuickCountLogic.recordsOnDate(attendance, DateTime.now()),
      _selectedClassIds,
    );
    if (todayRecords.isEmpty) {
      _showSnack('Nessun appello svolto oggi per le classi selezionate');
      return;
    }

    final present = QuickCountLogic.totalPresentCount(todayRecords);

    if (QuickCountLogic.isComplete(detected, present)) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Gruppo completo'),
          content: Text(
            'Il conteggio ($detected) coincide con i presenti all\'appello '
            'di oggi ($present).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final presentIds = QuickCountLogic.presentStudentIds(todayRecords);
    final students = ref.read(studentsRepoProvider).getAllStudentsSync();
    final presentStudents = Student.sortedBySurname(
      students.where((s) => presentIds.contains(s.id)),
    );
    final classes = ref
        .read(myClassesProvider)
        .where((c) => _selectedClassIds.contains(c.id))
        .toList();

    setState(() {
      _seenIds.clear();
      _data = _QuickCountData(
        detected: detected,
        present: present,
        presentStudents: presentStudents,
        classes: classes,
      );
      _phase = _QuickCountPhase.review;
    });
  }

  void _reset() {
    setState(() {
      _phase = _QuickCountPhase.form;
      _data = null;
      _seenIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF174A7E),
        foregroundColor: Colors.white,
        title: const Text('Conteggio rapido'),
      ),
      body: _phase == _QuickCountPhase.form
          ? _buildForm()
          : _buildReview(_data!),
    );
  }

  /// Fase 1: selezione classi + numero rilevato.
  Widget _buildForm() {
    final myClasses = ref.watch(myClassesProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Verifica la completezza del gruppo rispetto all\'appello '
                'di oggi.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.black54,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Classi da controllare',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
                ),
              ),
              const SizedBox(height: 8),
              if (myClasses.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Nessuna classe assegnata',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.grey.shade400 : Colors.black54,
                    ),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark
                          ? colorScheme.outline.withValues(alpha: 0.3)
                          : Colors.grey.shade300,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    color: isDark
                        ? colorScheme.surfaceContainer
                        : Colors.grey.shade50,
                  ),
                  child: Column(
                    children: [
                      for (final c in myClasses)
                        CheckboxListTile(
                          value: _selectedClassIds.contains(c.id),
                          activeColor: const Color(0xFF174A7E),
                          title: Text(c.name),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedClassIds.add(c.id);
                              } else {
                                _selectedClassIds.remove(c.id);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              TextField(
                controller: _countController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Persone rilevate',
                  hintText: 'Es. 12',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.groups_rounded),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF174A7E),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.fact_check_rounded),
                  label: const Text(
                    'Verifica',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _verify,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fase 2: confronto con i presenti all'appello.
  Widget _buildReview(_QuickCountData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final missingCount = data.present - _seenIds.length;
    final unseen = data.presentStudents
        .where((s) => !_seenIds.contains(s.id))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.orange.withValues(alpha: 0.15)
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.orange.withValues(alpha: 0.4)
                            : Colors.orange.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Il conteggio non coincide con l\'appello',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Persone rilevate: ${data.detected}   ·   '
                          'Presenti all\'appello: ${data.present}',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.grey.shade300 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Seleziona i ragazzi che hai realmente visto per '
                          'individuare i mancanti. Nessun dato viene salvato.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey.shade400 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            children: [
              for (final group in data.byClass) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    group.key,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? colorScheme.primary
                          : const Color(0xFF174A7E),
                    ),
                  ),
                ),
                for (final s in group.value)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    child: CheckboxListTile(
                      value: _seenIds.contains(s.id),
                      activeColor: const Color(0xFF174A7E),
                      dense: true,
                      title: Text('${s.surname} ${s.name}'),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _seenIds.add(s.id);
                          } else {
                            _seenIds.remove(s.id);
                          }
                        });
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.withValues(alpha: 0.15)
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? Colors.blue.withValues(alpha: 0.4)
                        : Colors.blue.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selezionati: ${_seenIds.length} / ${data.present}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? colorScheme.primary
                            : const Color(0xFF174A7E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (unseen.isNotEmpty)
                      Text(
                        'Non selezionati (possibili mancanti): '
                        '${unseen.map((s) => '${s.surname} ${s.name}').join(', ')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey.shade300 : Colors.black87,
                        ),
                      )
                    else
                      Text(
                        'Tutti i presenti all\'appello sono stati selezionati.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey.shade300 : Colors.black87,
                        ),
                      ),
                    if (_seenIds.length != data.present) ...[
                      const SizedBox(height: 6),
                      Text(
                        _seenIds.length < data.present
                            ? 'Hai selezionato meno ragazzi dei presenti '
                                  'all\'appello ($missingCount in meno rispetto '
                                  'ai presenti).'
                            : 'Hai selezionato più ragazzi dei presenti '
                                  'all\'appello.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text(
                    'Riprova',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _reset,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
