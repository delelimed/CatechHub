/// Pagina di dettaglio di una singola classe in CateREG.
///
/// Mostra le informazioni principali del gruppo (nome, ragazzi assegnati,
/// catechisti assegnati) e permette di modificare le assegnazioni tramite
/// un pannello modale (bottom sheet) con ricerca testuale dei ragazzi.
///
/// Utilizza [classesStreamProvider] per il stream delle classi e un provider
/// locale [studentsStreamProvider] per i ragazzi. I provider temporanei
/// [catechistsProvider] attendono l'implementazione della repository dedicata.
///
/// Flusso CateREG: l'utente arriva qui da [ClassesPage] cliccando su una
/// scheda classe; le modifiche alle assegnazioni vengono salvate su Hive
/// tramite [classesRepoProvider].
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/class_model.dart';
import '../../shared/models/student_model.dart';
import '../classes/classes_provider.dart';
import '../students/students_provider.dart';

// Definizione dello StreamProvider per i ragazzi
final studentsStreamProvider = StreamProvider<List<Student>>((ref) {
  final repo = ref.watch(studentsRepoProvider);
  return repo.getStudents(); // Se riscontri errore qui, sostituisci con il metodo esatto (es. getAllStudents())
});

// Provider temporaneo per i catechisti (puoi modificarlo quando implementerai la loro repository)
final catechistsProvider = Provider<List<Map<String, dynamic>>>((ref) {
  return []; 
});

class ClassDetailPage extends ConsumerWidget {
  final String classId;

  const ClassDetailPage({super.key, required this.classId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(classesStreamProvider);
    final studentsAsync = ref.watch(studentsStreamProvider); 
    final catechistsList = ref.watch(catechistsProvider);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF174A7E),
        foregroundColor: Colors.white,
        title: const Text('Dettaglio Gruppo'),
      ),
      body: classesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Errore caricamento classi: $err')),
        data: (classes) {
          final currentClass = classes.firstWhere(
            (e) => e.id == classId,
            orElse: () => SchoolClass(id: '', name: 'Gruppo non trovato', studentIds: [], catechistIds: []),
          );

          if (currentClass.id.isEmpty) {
            return const Center(child: Text('Il gruppo richiesto non esiste più.'));
          }

          return studentsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Errore caricamento ragazzi: $err')),
            data: (allStudents) {
              final assignedStudents = allStudents
                  .where((s) => currentClass.studentIds.contains(s.id))
                  .toList();

              final assignedCatechists = catechistsList
                  .where((c) => currentClass.catechistIds.contains(c['id']))
                  .toList();

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  /// Intestazione Gruppo
                  _HeaderCard(name: currentClass.name),
                  const SizedBox(height: 20),

                  /// Sezione Ragazzi
                  _SectionTitle(title: 'Ragazzi', count: assignedStudents.length),
                  const SizedBox(height: 8),
                  if (assignedStudents.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text('Nessun ragazzo assegnato', style: TextStyle(color: Colors.grey)),
                    ),
                  ...assignedStudents.map((s) => _PersonCard(title: '${s.name} ${s.surname}', icon: Icons.person)),
                  const SizedBox(height: 20),

                  /// Sezione Catechisti
                  _SectionTitle(title: 'Catechisti', count: assignedCatechists.length),
                  const SizedBox(height: 8),
                  if (assignedCatechists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text('Nessun catechista assegnato', style: TextStyle(color: Colors.grey)),
                    ),
                  ...assignedCatechists.map((c) => _PersonCard(title: c['name'] ?? '', subtitle: c['email'] ?? '', icon: Icons.badge)),
                  const SizedBox(height: 30),

                  /// Pulsante per aprire il BottomSheet di modifica
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF174A7E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.edit),
                      label: const Text("Modifica assegnazioni"),
                      onPressed: () {
                        _openAssignmentPanel(context, ref, currentClass, allStudents, catechistsList);
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // Modale per la gestione interattiva delle assegnazioni (Ragazzi e Catechisti)
  void _openAssignmentPanel(
    BuildContext context,
    WidgetRef ref,
    SchoolClass currentClass,
    List<Student> allStudents,
    List<Map<String, dynamic>> allCatechists,
  ) {
    final selectedStudents = Set<String>.from(currentClass.studentIds);
    final selectedCatechists = Set<String>.from(currentClass.catechistIds);
    String searchStudents = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            final filteredStudents = allStudents.where((s) {
              final full = '${s.name} ${s.surname}'.toLowerCase();
              return full.contains(searchStudents.toLowerCase());
            }).toList();

            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.9,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(20)),
                  ),
                  const SizedBox(height: 16),
                  const Text("Gestione assegnazioni", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  /// Input di ricerca testuale per i ragazzi
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Cerca ragazzo...',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      onChanged: (value) {
                        setState(() { searchStudents = value; });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _PanelSectionTitle(title: 'Ragazzi', count: filteredStudents.length),
                        ...filteredStudents.map((s) {
                          return _CheckboxPerson(
                            title: '${s.name} ${s.surname}',
                            selected: selectedStudents.contains(s.id),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) { selectedStudents.add(s.id); } 
                                else { selectedStudents.remove(s.id); }
                              });
                            },
                          );
                        }),
                        const SizedBox(height: 24),
                        _PanelSectionTitle(title: 'Catechisti', count: allCatechists.length),
                        ...allCatechists.map((c) {
                          final String cId = c['id'] ?? '';
                          return _CheckboxPerson(
                            title: c['name'] ?? '',
                            subtitle: c['email'] ?? '',
                            selected: selectedCatechists.contains(cId),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) { selectedCatechists.add(cId); } 
                                else { selectedCatechists.remove(cId); }
                              });
                            },
                          );
                        }),
                      ],
                    ),
                  ),

                  /// Pulsante di salvataggio finale locale
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF174A7E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () async {
                          await ref.read(classesRepoProvider).updateClass(
                                currentClass.id,
                                currentClass.copyWith(
                                  studentIds: selectedStudents.toList(),
                                  catechistIds: selectedCatechists.toList(),
                                ),
                              );
                          if (context.mounted) { Navigator.pop(context); }
                        },
                        child: const Text("Salva modifiche", style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// ============================================================
/// UI COMPONENTS COMPATTI
/// ============================================================

class _HeaderCard extends StatelessWidget {
  final String name;
  const _HeaderCard({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF174A7E))),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;
  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFF174A7E).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Text('$count', style: const TextStyle(color: Color(0xFF174A7E), fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }
}

class _PanelSectionTitle extends StatelessWidget {
  final String title;
  final int count;
  const _PanelSectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(width: 6),
          Text('($count)', style: const TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  const _PersonCard({required this.title, this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF174A7E).withValues(alpha: 0.1),
          child: Icon(icon, color: const Color(0xFF174A7E), size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: subtitle != null ? Text(subtitle!) : null,
      ),
    );
  }
}

class _CheckboxPerson extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  const _CheckboxPerson({required this.title, required this.selected, required this.onChanged, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: selected,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      activeColor: const Color(0xFF174A7E),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }
}
