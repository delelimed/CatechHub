import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../core/auth/auth_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/student_model.dart';
import 'students_repository.dart';
import '../classes/classes_provider.dart';
import '../classes/classes_repository.dart';

final studentsRepoProvider = Provider((ref) => StudentsRepository());
final classesRepoProvider = Provider((ref) => ClassesRepository());

class AddStudentPage extends ConsumerStatefulWidget {
  const AddStudentPage({super.key});

  @override
  ConsumerState<AddStudentPage> createState() =>
      _AddStudentPageState();
}

class _AddStudentPageState extends ConsumerState<AddStudentPage> {
  final name = TextEditingController();
  final surname = TextEditingController();

  final motherName = TextEditingController();
  final motherSurname = TextEditingController();
  final fatherName = TextEditingController();
  final fatherSurname = TextEditingController();

  final motherPhone = TextEditingController();
  final fatherPhone = TextEditingController();
  final studentPhone = TextEditingController();

  final allergies = TextEditingController();
  final notes = TextEditingController();

  DateTime? birthDate;
  Set<String> selectedExits = {};
  String? customExitName;

  bool get isDesktop =>
      MediaQuery.of(context).size.width > 900;

  @override
  void dispose() {
    name.dispose();
    surname.dispose();
    motherName.dispose();
    motherSurname.dispose();
    fatherName.dispose();
    fatherSurname.dispose();
    motherPhone.dispose();
    fatherPhone.dispose();
    studentPhone.dispose();
    allergies.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(studentsRepoProvider);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,

      appBar: AppBar(
        backgroundColor: const Color(0xFF174A7E),
        foregroundColor: Colors.white,
        title: const Text('Nuovo ragazzo'),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _HeaderCard(),

            const SizedBox(height: 16),

            /// =========================
            /// DATI BASE
            /// =========================
            _Section(
              title: 'Dati ragazzo',
              children: [
                _Field(name, 'Nome'),
                _Field(surname, 'Cognome'),

                const SizedBox(height: 10),

                _DatePicker(
                  date: birthDate,
                  onPick: (date) {
                    setState(() => birthDate = date);
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            /// =========================
            /// GENITORI (RESPONSIVE)
            /// =========================
            _Section(
              title: 'Genitori',
              children: isDesktop
                  ? [
                      Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _ParentCard(
                              title: 'Madre',
                              name: motherName,
                              surname: motherSurname,
                              phone: motherPhone,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ParentCard(
                              title: 'Padre',
                              name: fatherName,
                              surname: fatherSurname,
                              phone: fatherPhone,
                            ),
                          ),
                        ],
                      )
                    ]
                  : [
                      _ParentCard(
                        title: 'Madre',
                        name: motherName,
                        surname: motherSurname,
                        phone: motherPhone,
                      ),
                      const SizedBox(height: 12),
                      _ParentCard(
                        title: 'Padre',
                        name: fatherName,
                        surname: fatherSurname,
                        phone: fatherPhone,
                      ),
                    ],
            ),

            const SizedBox(height: 16),

            /// =========================
            /// CONTATTI
            /// =========================
            _Section(
              title: 'Contatti ragazzo',
              children: [
                _Field(studentPhone, 'Cellulare ragazzo'),
              ],
            ),

            const SizedBox(height: 16),

            /// =========================
            /// ALLERGIE E USCITE
            /// =========================
            _Section(
              title: 'Allergie e Uscite',
              children: [
                _Field(allergies, 'Allergie', maxLines: 2),
                const SizedBox(height: 16),
                _ExitsSelector(
                  selectedExits: selectedExits,
                  onSelectionChanged: (exits, custom) {
                    setState(() {
                      selectedExits = exits;
                      customExitName = custom;
                    });
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            /// =========================
            /// NOTE
            /// =========================
            _Section(
              title: 'Note',
              children: [
                _NotesField(notes),
              ],
            ),

            const SizedBox(height: 30),

            /// =========================
            /// SAVE
            /// =========================
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF174A7E),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  if (birthDate == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Seleziona la data di nascita'),
                      ),
                    );
                    return;
                  }

                  final studentId = LocalDatabase.newId('student');

                  String? autonomousExits;
                  if (selectedExits.isNotEmpty) {
                    if (selectedExits.contains('altro') && customExitName != null && customExitName!.isNotEmpty) {
                      autonomousExits = 'altro:$customExitName';
                    } else if (selectedExits.length == 1) {
                      autonomousExits = selectedExits.first;
                    } else {
                      autonomousExits = selectedExits.join(',');
                    }
                  }

                  final student = Student(
                    id: studentId,
                    name: name.text,
                    surname: surname.text,
                    birthDate: birthDate!,
                    motherName: motherName.text,
                    motherSurname: motherSurname.text,
                    motherPhone: motherPhone.text,
                    fatherName: fatherName.text,
                    fatherSurname: fatherSurname.text,
                    fatherPhone: fatherPhone.text,
                    studentPhone: studentPhone.text,
                    allergies: allergies.text.isNotEmpty ? allergies.text : null,
                    autonomousExits: autonomousExits,
                    notes: notes.text,
                  );

                  try {
                    final repo = ref.read(studentsRepoProvider);
                    await repo.addStudent(student);

                    final classesAsync = ref.read(classesStreamProvider);
                    final classesRepo = ref.read(classesRepoProvider);

                    classesAsync.whenData((classes) async {
                      final myClass = classes.firstWhereOrNull(
                        (c) => c.catechistIds.contains(AuthService.localUserId),
                      );

                      if (myClass != null) {
                        await classesRepo.addStudentToClass(myClass.id, studentId);
                      }
                    });

                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Errore: $e')),
                    );
                  }
                },
                child: const Text('Salva ragazzo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================
/// HEADER
/// =========================
class _HeaderCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            Colors.blue.shade50.withOpacity(0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.person_add_alt_1,
              color: Color(0xFF174A7E), size: 30),
          SizedBox(width: 12),
          Text(
            'Nuovo profilo ragazzo',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF174A7E),
            ),
          ),
        ],
      ),
    );
  }
}

/// =========================
/// SECTION
/// =========================
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// =========================
/// PARENT CARD
/// =========================
class _ParentCard extends StatelessWidget {
  final String title;
  final TextEditingController name;
  final TextEditingController surname;
  final TextEditingController phone;

  const _ParentCard({
    required this.title,
    required this.name,
    required this.surname,
    required this.phone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 8),
          _Field(name, 'Nome'),
          _Field(surname, 'Cognome'),
          _Field(phone, 'Telefono'),
        ],
      ),
    );
  }
}

/// =========================
/// FIELD
/// =========================
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;

  const _Field(this.controller, this.label, {this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// =========================
/// NOTES FIELD
/// =========================
class _NotesField extends StatelessWidget {
  final TextEditingController controller;

  const _NotesField(this.controller);

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: 5,
      decoration: InputDecoration(
        labelText: 'Note',
        alignLabelWithHint: true,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// =========================
/// EXITS SELECTOR
/// =========================
class _ExitsSelector extends StatefulWidget {
  final Set<String> selectedExits;
  final Function(Set<String>, String?) onSelectionChanged;

  const _ExitsSelector({
    required this.selectedExits,
    required this.onSelectionChanged,
  });

  @override
  State<_ExitsSelector> createState() =>
      _ExitsSelectorState();
}

class _ExitsSelectorState extends State<_ExitsSelector> {
  late Set<String> selected;
  late TextEditingController customController;

  @override
  void initState() {
    super.initState();
    selected = Set.from(widget.selectedExits);
    customController = TextEditingController();
  }

  @override
  void dispose() {
    customController.dispose();
    super.dispose();
  }

  void _updateSelection() {
    widget.onSelectionChanged(selected, customController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Chi accompagna l\'uscita?',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ExitChip(
              label: 'Autonomo',
              selected: selected.contains('autonomo'),
              onChanged: (isSelected) {
                setState(() {
                  if (isSelected) {
                    selected.add('autonomo');
                  } else {
                    selected.remove('autonomo');
                  }
                  _updateSelection();
                });
              },
            ),
            _ExitChip(
              label: 'Genitori',
              selected: selected.contains('genitori'),
              onChanged: (isSelected) {
                setState(() {
                  if (isSelected) {
                    selected.add('genitori');
                  } else {
                    selected.remove('genitori');
                  }
                  _updateSelection();
                });
              },
            ),
            _ExitChip(
              label: 'Altro',
              selected: selected.contains('altro'),
              onChanged: (isSelected) {
                setState(() {
                  if (isSelected) {
                    selected.add('altro');
                  } else {
                    selected.remove('altro');
                    customController.clear();
                  }
                  _updateSelection();
                });
              },
            ),
          ],
        ),
        if (selected.contains('altro')) ...[
          const SizedBox(height: 12),
          TextField(
            controller: customController,
            decoration: InputDecoration(
              labelText: 'Specifica chi accompagna',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) => _updateSelection(),
          ),
        ],
      ],
    );
  }
}

/// =========================
/// EXIT CHIP
/// =========================
class _ExitChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Function(bool) onChanged;

  const _ExitChip({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onChanged,
      backgroundColor: Colors.grey.shade100,
      selectedColor: const Color(0xFF174A7E),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// =========================
/// DATE PICKER
/// =========================
class _DatePicker extends StatelessWidget {
  final DateTime? date;
  final Function(DateTime) onPick;

  const _DatePicker({
    required this.date,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          firstDate: DateTime(1990),
          lastDate: DateTime.now(),
        );

        if (picked != null) onPick(picked);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month,
                color: Color(0xFF174A7E)),
            const SizedBox(width: 10),
            Text(
              date == null
                  ? 'Seleziona data nascita'
                  : '${date!.day}/${date!.month}/${date!.year}',
              style:
                  const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}