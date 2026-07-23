import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/attachment_parent_type.dart';
import '../../shared/models/student_model.dart';
import '../attachments/widgets/attachments_section.dart';
import '../classes/classes_repository.dart';
import 'students_repository.dart';

final studentsRepoProvider = Provider((ref) => StudentsRepository());
final classesRepoProvider = Provider((ref) => ClassesRepository());

/// Pagina di modifica di uno studente esistente: campi editabili per nome,
/// cognome, genitori (con pulsanti azione telefono/WhatsApp), uscite
/// autorizzate, allergie, note e sezione allegati.
/// Usa il modello [Student] e persiste tramite [StudentsRepository] (Box `students`).
/// La modifica è protetta da un lucchetto (toggle editMode) per evitare
/// cambi accidentali. Flusso: accessibile dal menu contestuale di [StudentsPage].
class EditStudentPage extends ConsumerStatefulWidget {
  final Student student;

  const EditStudentPage({super.key, required this.student});

  @override
  ConsumerState<EditStudentPage> createState() =>
      _EditStudentPageState();
}

class _EditStudentPageState extends ConsumerState<EditStudentPage> {
  late TextEditingController name;
  late TextEditingController surname;

  late TextEditingController motherName;
  late TextEditingController motherSurname;
  late TextEditingController motherPhone;

  late TextEditingController fatherName;
  late TextEditingController fatherSurname;
  late TextEditingController fatherPhone;

  late TextEditingController studentPhone;
  late TextEditingController allergies;
  late TextEditingController notes;

  bool editMode = false;
  Set<String> selectedExits = {};
  String? customExitName;
  String? tempStudentId;

  @override
  void initState() {
    super.initState();

    final s = widget.student;
    tempStudentId = s.id;

    name = TextEditingController(text: s.name);
    surname = TextEditingController(text: s.surname);

    motherName = TextEditingController(text: s.motherName);
    motherSurname = TextEditingController(text: s.motherSurname);
    motherPhone = TextEditingController(text: s.motherPhone);

    fatherName = TextEditingController(text: s.fatherName);
    fatherSurname = TextEditingController(text: s.fatherSurname);
    fatherPhone = TextEditingController(text: s.fatherPhone);

    studentPhone = TextEditingController(text: s.studentPhone);
    allergies = TextEditingController(text: s.allergies ?? '');
    notes = TextEditingController(text: s.notes ?? '');

    // Parse autonomousExits
    if (s.autonomousExits != null && s.autonomousExits!.isNotEmpty) {
      if (s.autonomousExits!.startsWith('altro:')) {
        selectedExits.add('altro');
        customExitName = s.autonomousExits!.replaceFirst('altro:', '');
      } else {
        selectedExits.addAll(s.autonomousExits!.split(','));
      }
    }
  }

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

  // =========================
  // NORMALIZZAZIONE NUMERI
  // =========================
  String _normalizePhone(String input) {
    String phone = input.replaceAll(RegExp(r'[^0-9]'), '');

    if (phone.startsWith('0039')) {
      phone = phone.replaceFirst('0039', '39');
    }

    if (!phone.startsWith('39')) {
      phone = '39$phone';
    }

    return phone;
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _whatsapp(String phone) async {
    final normalized = _normalizePhone(phone);
    final uri = Uri.parse('https://wa.me/$normalized');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(studentsRepoProvider);
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? colorScheme.surface : Colors.grey.shade50,

      appBar: AppBar(
        backgroundColor: isDark ? colorScheme.primaryContainer : const Color(0xFF174A7E),
        foregroundColor: isDark ? colorScheme.onPrimaryContainer : Colors.white,
        title: const Text('Modifica ragazzo'),
        actions: [
          IconButton(
            icon: Icon(editMode ? Icons.lock_open : Icons.lock),
            onPressed: () => setState(() => editMode = !editMode),
            tooltip: editMode ? 'Blocca modifiche' : 'Abilita modifiche',
          )
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _HeaderCard(
              name: '${widget.student.name} ${widget.student.surname}',
              isDark: isDark,
              colorScheme: colorScheme,
            ),

            const SizedBox(height: 16),

            _Section(
              title: 'Dati ragazzo',
              isDark: isDark,
              colorScheme: colorScheme,
              children: [
                _Field(name, 'Nome', enabled: editMode, capitalizeWords: true, isDark: isDark, colorScheme: colorScheme),
                _Field(surname, 'Cognome', enabled: editMode, capitalizeWords: true, isDark: isDark, colorScheme: colorScheme),
              ],
            ),

            const SizedBox(height: 16),

            _Section(
              title: 'Genitori',
              isDark: isDark,
              colorScheme: colorScheme,
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
                              editMode: editMode,
                              isDark: isDark,
                              colorScheme: colorScheme,
                              onCall: _call,
                              onWhatsapp: _whatsapp,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ParentCard(
                              title: 'Padre',
                              name: fatherName,
                              surname: fatherSurname,
                              phone: fatherPhone,
                              editMode: editMode,
                              isDark: isDark,
                              colorScheme: colorScheme,
                              onCall: _call,
                              onWhatsapp: _whatsapp,
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
                        editMode: editMode,
                        isDark: isDark,
                        colorScheme: colorScheme,
                        onCall: _call,
                        onWhatsapp: _whatsapp,
                      ),
                      const SizedBox(height: 12),
                      _ParentCard(
                        title: 'Padre',
                        name: fatherName,
                        surname: fatherSurname,
                        phone: fatherPhone,
                        editMode: editMode,
                        isDark: isDark,
                        colorScheme: colorScheme,
                        onCall: _call,
                        onWhatsapp: _whatsapp,
                      ),
                    ],
            ),

            const SizedBox(height: 16),

            _Section(
              title: 'Contatti ragazzo',
              isDark: isDark,
              colorScheme: colorScheme,
              children: [
                _PhoneRow(
                  controller: studentPhone,
                  enabled: editMode,
                  isDark: isDark,
                  colorScheme: colorScheme,
                  onCall: _call,
                  onWhatsapp: _whatsapp,
                ),
              ],
            ),

            const SizedBox(height: 16),

            _Section(
              title: 'Allergie e Uscite',
              isDark: isDark,
              colorScheme: colorScheme,
              children: [
                _Field(allergies, 'Allergie', maxLines: 2, enabled: editMode, isDark: isDark, colorScheme: colorScheme),
                const SizedBox(height: 16),
                _EditExitsSelector(
                  selectedExits: selectedExits,
                  customExitName: customExitName,
                  editMode: editMode,
                  isDark: isDark,
                  colorScheme: colorScheme,
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

            _Section(
              title: 'Note',
              isDark: isDark,
              colorScheme: colorScheme,
              children: [
                _NotesField(notes, enabled: editMode, isDark: isDark, colorScheme: colorScheme),
              ],
            ),

            const SizedBox(height: 16),

            /// =========================
            /// ALLEGATI
            /// =========================
            AttachmentsSection(
              parentId: widget.student.id,
              parentType: AttachmentParentType.student,
            ),

            const SizedBox(height: 30),

            /// =========================
            /// SAVE
            /// =========================
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? colorScheme.primary : const Color(0xFF174A7E),
                  foregroundColor: isDark ? colorScheme.onPrimary : Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: editMode
                    ? () async {
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

                        final updated = Student(
                          id: widget.student.id,
                          name: name.text,
                          surname: surname.text,
                          birthDate: widget.student.birthDate,
                          motherName: motherName.text,
                          motherSurname: motherSurname.text,
                          motherPhone: motherPhone.text,
                          fatherName: fatherName.text,
                          fatherSurname: fatherSurname.text,
                          fatherPhone: fatherPhone.text,
                          studentPhone: studentPhone.text,
                          allergies: allergies.text.isNotEmpty ? allergies.text : null,
                          autonomousExits: autonomousExits,
                          notes: notes.text.isNotEmpty ? notes.text : null,
                        );

                        await repo.updateStudent(
                          widget.student.id,
                          updated,
                        );

                        setState(() => editMode = false);
                      }
                    : null,
                child: const Text('Salva modifiche'),
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
  final String name;
  final bool isDark;
  final ColorScheme colorScheme;

  const _HeaderCard({
    required this.name,
    required this.isDark,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  colorScheme.surfaceContainer,
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                ]
              : [
                  Colors.white,
                  Colors.blue.shade50.withValues(alpha: 0.5),
                ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.edit,
              color: isDark ? colorScheme.primary : const Color(0xFF174A7E), size: 30),
          const SizedBox(width: 12),
          Text(
            'Modifica profilo ragazzo',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
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
  final bool isDark;
  final ColorScheme colorScheme;

  const _Section({
    required this.title,
    required this.children,
    required this.isDark,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.03),
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
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
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
  final bool editMode;
  final bool isDark;
  final ColorScheme colorScheme;
  final Function(String) onCall;
  final Function(String) onWhatsapp;

  const _ParentCard({
    required this.title,
    required this.name,
    required this.surname,
    required this.phone,
    required this.editMode,
    required this.isDark,
    required this.colorScheme,
    required this.onCall,
    required this.onWhatsapp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 8),
          _Field(name, 'Nome', enabled: editMode, capitalizeWords: true, isDark: isDark, colorScheme: colorScheme),
          _Field(surname, 'Cognome', enabled: editMode, capitalizeWords: true, isDark: isDark, colorScheme: colorScheme),
          Row(
            children: [
              Expanded(
                child: _Field(phone, 'Telefono', enabled: editMode, keyboardType: TextInputType.phone, isDark: isDark, colorScheme: colorScheme),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.call, color: Colors.green),
                onPressed: () => onCall(phone.text),
              ),
              IconButton(
                icon: const Icon(Icons.chat, color: Colors.green),
                onPressed: () => onWhatsapp(phone.text),
              ),
            ],
          ),
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
  final bool capitalizeWords;
  final TextInputType? keyboardType;
  final bool enabled;
  final bool isDark;
  final ColorScheme colorScheme;

  const _Field(
    this.controller,
    this.label, {
    this.maxLines = 1,
    this.capitalizeWords = false,
    this.keyboardType,
    this.enabled = true,
    required this.isDark,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        enabled: enabled,
        maxLines: maxLines,
        textCapitalization: capitalizeWords
            ? TextCapitalization.words
            : TextCapitalization.none,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: isDark ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.2) : Colors.grey.shade50,
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
  final bool enabled;
  final bool isDark;
  final ColorScheme colorScheme;

  const _NotesField(this.controller, {this.enabled = true, required this.isDark, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: 5,
      decoration: InputDecoration(
        labelText: 'Note',
        alignLabelWithHint: true,
        filled: true,
        fillColor: isDark ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.2) : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// =========================
/// PHONE ROW (STUDENTE)
/// =========================
class _PhoneRow extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool isDark;
  final ColorScheme colorScheme;
  final Function(String) onCall;
  final Function(String) onWhatsapp;

  const _PhoneRow({
    required this.controller,
    required this.enabled,
    required this.isDark,
    required this.colorScheme,
    required this.onCall,
    required this.onWhatsapp,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Field(
            controller,
            'Cellulare ragazzo',
            enabled: enabled,
            keyboardType: TextInputType.phone,
            isDark: isDark,
            colorScheme: colorScheme,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.call, color: Colors.green),
          onPressed: () => onCall(controller.text),
        ),
        IconButton(
          icon: const Icon(Icons.chat, color: Colors.green),
          onPressed: () => onWhatsapp(controller.text),
        ),
      ],
    );
  }
}

/// =========================
/// EDIT EXITS SELECTOR
/// =========================
class _EditExitsSelector extends StatefulWidget {
  final Set<String> selectedExits;
  final String? customExitName;
  final bool editMode;
  final bool isDark;
  final ColorScheme colorScheme;
  final Function(Set<String>, String?) onSelectionChanged;

  const _EditExitsSelector({
    required this.selectedExits,
    required this.customExitName,
    required this.editMode,
    required this.isDark,
    required this.colorScheme,
    required this.onSelectionChanged,
  });

  @override
  State<_EditExitsSelector> createState() =>
      _EditExitsSelectorState();
}

class _EditExitsSelectorState extends State<_EditExitsSelector> {
  late Set<String> selected;
  late TextEditingController customController;

  @override
  void initState() {
    super.initState();
    selected = Set.from(widget.selectedExits);
    customController = TextEditingController(text: widget.customExitName ?? '');
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
        if (widget.editMode)
          Text(
            'Chi accompagna l\'uscita?',
            style: TextStyle(fontWeight: FontWeight.w600, color: widget.isDark ? widget.colorScheme.onSurface : null),
          )
        else
          Text(
            'Chi accompagna l\'uscita: ${selected.isEmpty ? 'Non specificato' : selected.join(', ')}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: widget.isDark ? widget.colorScheme.onSurface : Colors.grey.shade700,
            ),
          ),
        const SizedBox(height: 12),
        if (widget.editMode)
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
                isDark: widget.isDark,
                colorScheme: widget.colorScheme,
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
                isDark: widget.isDark,
                colorScheme: widget.colorScheme,
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
                isDark: widget.isDark,
                colorScheme: widget.colorScheme,
              ),
            ],
          ),
        if (widget.editMode && selected.contains('altro')) ...[
          const SizedBox(height: 12),
          TextField(
            controller: customController,
            decoration: InputDecoration(
              labelText: 'Specifica chi accompagna',
              filled: true,
              fillColor: widget.isDark ? widget.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2) : Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) => _updateSelection(),
          ),
        ],
        if (!widget.editMode && selected.contains('altro'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Altro: ${customController.text}',
              style: TextStyle(color: widget.isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
          ),
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
  final bool isDark;
  final ColorScheme colorScheme;
  final Function(bool) onChanged;

  const _ExitChip({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.colorScheme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onChanged,
      backgroundColor: isDark ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3) : Colors.grey.shade100,
      selectedColor: isDark ? colorScheme.primary : const Color(0xFF174A7E),
      labelStyle: TextStyle(
        color: selected ? Colors.white : (isDark ? colorScheme.onSurface : Colors.black),
        fontWeight: FontWeight.w500,
      ),
    );
  }
}