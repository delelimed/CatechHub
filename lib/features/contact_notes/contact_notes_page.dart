import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../shared/models/student_model.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../students/students_repository.dart';
import 'contact_notes_repository.dart';
import 'student_contact_notes_page.dart';

/// Pagina principale "Registro di Contatto" di CateREG.
///
/// Mostra l'elenco completo di tutti i ragazzi (ordinati per cognome) con
/// un'anteprima dell'ultima nota di contatto registrata per ciascuno.
/// Da ogni tile è possibile navigare alla pagina dei dettagli contatto
/// del singolo studente ([StudentContactNotesPage]).
class ContactNotesPage extends ConsumerWidget {
  const ContactNotesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsRepo = StudentsRepository();
    final contactNotesRepo = ref.watch(contactNotesRepoProvider);
    final students = Student.sortedBySurname(studentsRepo.getAllStudentsSync());

    return AppScaffold(
      title: 'Registro di Contatto',
      child: students.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline,
                        size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Nessun ragazzo registrato',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: students.length,
              itemBuilder: (context, index) {
                final student = students[index];
                final latestNotes =
                    contactNotesRepo.getNotesForStudentSync(student.id);
                final lastNote =
                    latestNotes.isNotEmpty ? latestNotes.first : null;

                return _StudentContactTile(
                  student: student,
                  lastNote: lastNote,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentContactNotesPage(
                          student: student,
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

/// Tile per singolo studente nella lista principale.
///
/// Mostra iniziale del cognome, nome completo e anteprima dell'ultimo
/// contatto (data + testo troncato a 40 caratteri). Se non ci sono
/// contatti, mostra un messaggio "Nessun contatto registrato".
class _StudentContactTile extends StatelessWidget {
  final Student student;
  final dynamic lastNote;
  final VoidCallback onTap;

  const _StudentContactTile({
    required this.student,
    required this.lastNote,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF174A7E).withValues(alpha: 0.1),
                child: Text(
                  student.surname.isNotEmpty
                      ? student.surname[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Color(0xFF174A7E),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${student.surname} ${student.name}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (lastNote != null)
                      Text(
                        '${DateFormat('dd/MM/yy').format(lastNote.dateTime)} — ${lastNote.notes.length > 40 ? '${lastNote.notes.substring(0, 40)}...' : lastNote.notes}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        'Nessun contatto registrato',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
