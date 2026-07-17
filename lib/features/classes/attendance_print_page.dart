/// Pagina per la stampa degli appelli (fogli presenza) in CateREG.
///
/// Consente al catechista di scegliere tra:
/// - "Tutti gli incontri": stampa l'intero storico presenze della classe.
/// - "Incontri personalizzati": filtro per intervallo di date (Dal/Al).
///
/// Alla pressione del pulsante "Stampa", recupera i dati di studenti,
/// presenze e incontri dai rispettivi repository, calcola i conteggi e
/// delega a [PrintService.printDetailedAttendanceReport] per la generazione
/// del PDF.
///
/// Integrazione CateREG: lo [SchoolClass] viene passato dal chiamante
/// (es. [MyGroupPage]); la pagina usa [AttendanceRepository],
/// [PlanningRepository] e [StudentsRepository] tramite i rispettivi
/// provider per l'accesso offline ai dati Hive.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

//import '../../core/auth/auth_service.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/student_model.dart';
import '../meetings/attendance_repository.dart';
import '../planning/planning_repository.dart';
import '../students/students_repository.dart';
import 'print_service.dart';

class AttendancePrintPage extends ConsumerStatefulWidget {
  final SchoolClass schoolClass;

  const AttendancePrintPage({super.key, required this.schoolClass});

  @override
  ConsumerState<AttendancePrintPage> createState() =>
      _AttendancePrintPageState();
}

class _AttendancePrintPageState extends ConsumerState<AttendancePrintPage> {
  bool _isCustomDate = false;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF174A7E),
        foregroundColor: Colors.white,
        title: const Text('Stampa appelli'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Scegli cosa stampare',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF174A7E),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _RadioOption(
                    title: 'Tutti gli incontri',
                    subtitle: 'Stampa tutti gli appelli registrati',
                    value: false,
                    groupValue: _isCustomDate,
                    onChanged: (value) {
                      setState(() => _isCustomDate = value ?? false);
                    },
                  ),
                  const SizedBox(height: 16),
                  _RadioOption(
                    title: 'Incontri personalizzati',
                    subtitle: 'Scegli un intervallo di date',
                    value: true,
                    groupValue: _isCustomDate,
                    onChanged: (value) {
                      setState(() => _isCustomDate = value ?? false);
                    },
                  ),
                  if (_isCustomDate) ...[
                    const SizedBox(height: 28),
                    _DatePickerField(
                      label: 'Dal',
                      date: _dateFrom,
                      onPick: (date) {
                        setState(() => _dateFrom = date);
                      },
                    ),
                    const SizedBox(height: 12),
                    _DatePickerField(
                      label: 'Al',
                      date: _dateTo,
                      onPick: (date) {
                        setState(() => _dateTo = date);
                      },
                    ),
                  ],
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF174A7E),
                        foregroundColor: Colors.white,
                      ),
                      onPressed:
                          _isCustomDate &&
                              (_dateFrom == null || _dateTo == null)
                          ? null
                          : () => _handlePrint(context),
                      child: const Text(
                        'Stampa',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handlePrint(BuildContext context) async {
    try {
      final studentsRaw =
          ref
              .read(studentsRepositoryProvider)
              .getAllStudentsSync()
              .where((s) => widget.schoolClass.studentIds.contains(s.id))
              .toList()
            ..sort(Student.compareBySurname);

      final allAttendance = ref
          .read(attendanceRepositoryProvider)
          .getAttendanceSync();

      final classMeetings =
          ref
              .read(planningRepositoryProvider)
              .getMeetingsSync()
              .where((m) => m.classId == widget.schoolClass.id && !m.isReunion)
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));

      var meetings = classMeetings;
      List<Map<String, dynamic>> filteredAttendance = allAttendance
          .where((a) => a['classId'] == widget.schoolClass.id)
          .toList();

      if (_isCustomDate && _dateFrom != null && _dateTo != null) {
        filteredAttendance = filteredAttendance.where((a) {
          final date =
              DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime.now();
          return !date.isBefore(_dateFrom!) && !date.isAfter(_dateTo!);
        }).toList();

        meetings = classMeetings.where((meeting) {
          return !meeting.date.isBefore(_dateFrom!) &&
              !meeting.date.isAfter(_dateTo!);
        }).toList();
      }

      final attendanceCounts = {
        for (final student in studentsRaw)
          student.id: {'present': 0, 'absent': 0},
      };

      for (final record in filteredAttendance) {
        final presence = Map<String, dynamic>.from(
          record['presence'] as Map? ?? {},
        );
        for (final entry in presence.entries) {
          if (!attendanceCounts.containsKey(entry.key)) continue;
          if (entry.value == 'Presente') {
            attendanceCounts[entry.key]!['present'] =
                attendanceCounts[entry.key]!['present']! + 1;
          } else if (entry.value == 'Assente') {
            attendanceCounts[entry.key]!['absent'] =
                attendanceCounts[entry.key]!['absent']! + 1;
          }
        }
      }

      final students = studentsRaw.map((s) {
        final counts = attendanceCounts[s.id]!;
        return PrintStudentData(
          id: s.id,
          fullName: '${s.surname} ${s.name}',
          present: counts['present']!,
          absent: counts['absent']!,
          consecutiveAbsences: 0,
        );
      }).toList();

      if (context.mounted) {
        await PrintService.printDetailedAttendanceReport(
          className: widget.schoolClass.name,
          students: students,
          meetings: meetings,
          attendance: filteredAttendance,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Errore: $e')));
      }
    }
  }
}

class _RadioOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final bool groupValue;
  final void Function(bool?)? onChanged;

  const _RadioOption({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged?.call(value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: groupValue == value
                ? const Color(0xFF174A7E)
                : Colors.grey.shade300,
            width: groupValue == value ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: groupValue == value
              ? const Color(0xFF174A7E).withValues(alpha: 0.05)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              value == groupValue
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: const Color(0xFF174A7E),
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF174A7E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final void Function(DateTime) onPick;

  const _DatePickerField({
    required this.label,
    required this.date,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey.shade50,
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month, color: Color(0xFF174A7E)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    date == null
                        ? 'Seleziona data'
                        : '${date!.day}/${date!.month}/${date!.year}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF174A7E),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
