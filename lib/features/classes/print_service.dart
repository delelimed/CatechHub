/// Servizio di stampa PDF per CateREG basato su `pdf` e `printing`.
///
/// Genera documenti PDF per reportistica delle classi:
/// - [printAttendanceReport]: report sintetico con nome classe, elenco
///   studenti (ordinato alfabeticamente), conteggio presenze (P) e assenze (A).
/// - [printDetailedAttendanceReport]: report dettagliato con una colonna per
///   ogni incontro programmato, indicando "a" per assente, più totali P/A.
///
/// I dati vengono renderizzati in tabelle su formato A4 orizzontale e inviati
/// al servizio di stampa nativo tramite [Printing.layoutPdf].
///
/// Integrazione CateREG: utilizzato da [AttendancePrintPage] per esportare
/// gli appelli; [PrintStudentData] è il DTO che veicola i dati di uno
/// studente dal layer dati al layout PDF.
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../shared/models/planning_meeting.dart';

class PrintStudentData {
  final String id;
  final String fullName;
  final int present;
  final int absent;
  final int consecutiveAbsences;

  PrintStudentData({
    required this.id,
    required this.fullName,
    required this.present,
    required this.absent,
    required this.consecutiveAbsences,
  });
}

class PrintService {
  static Future<void> printAttendanceReport({
    required String className,
    required List<PrintStudentData> students,
  }) async {
    final pdf = pw.Document();

    final sortedStudents = [...students]
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                className,
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 12),

              pw.Expanded(
                child: pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(1),
                    2: const pw.FlexColumnWidth(1),
                    3: const pw.FlexColumnWidth(3),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200,
                      ),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            'Nome e Cognome',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            'P',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            'A',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            'Stato incontri',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                      ],
                    ),

                    ...sortedStudents.map((s) {
                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(s.fullName),
                          ),

                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              '${s.present}',
                              textAlign: pw.TextAlign.center,
                            ),
                          ),

                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              '${s.absent}',
                              textAlign: pw.TextAlign.center,
                            ),
                          ),

                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              s.absent > 0 ? 'a' : '',
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                color: s.absent > 0
                                    ? PdfColors.red
                                    : PdfColors.green,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }

  static Future<void> printDetailedAttendanceReport({
    required String className,
    required List<PrintStudentData> students,
    required List<PlanningMeeting> meetings,
    required List<Map<String, dynamic>> attendance,
  }) async {
    final pdf = pw.Document();

    final sortedStudents = [...students]
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    final sortedMeetings = [...meetings]..sort((a, b) => a.date.compareTo(b.date));

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                className,
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 12),

              pw.Expanded(
                child: pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(0.8),
                    2: const pw.FlexColumnWidth(0.8),
                    ...{
                      for (int i = 0; i < sortedMeetings.length; i++)
                        3 + i: const pw.FlexColumnWidth(0.6),
                    }
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200,
                      ),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'Nome e Cognome',
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'P',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'A',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        ...sortedMeetings.map((meeting) {
                          return pw.Padding(
                            padding: const pw.EdgeInsets.all(2),
                            child: pw.Text(
                              '${meeting.date.day}/${meeting.date.month}',
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                            ),
                          );
                        }).toList(),
                      ],
                    ),

                    ...sortedStudents.map((student) {
                      final totalPresent = student.present;
                      final totalAbsent = student.absent;

                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(
                              student.fullName,
                              style: pw.TextStyle(fontSize: 9),
                            ),
                          ),

                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(
                              '$totalPresent',
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(fontSize: 9, color: PdfColors.green),
                            ),
                          ),

                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(
                              '$totalAbsent',
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(fontSize: 9, color: PdfColors.red),
                            ),
                          ),

                          ...sortedMeetings.map((meeting) {
                            final attendanceRecord = attendance.firstWhere(
                              (a) => a['meetingId'].toString() == meeting.id,
                              orElse: () => {},
                            );

                            final presence = Map<String, dynamic>.from(
                              attendanceRecord['presence'] as Map? ?? {},
                            );

                            final status = presence[student.id] ?? '';
                            final isAbsent = status == 'Assente';

                            return pw.Padding(
                              padding: const pw.EdgeInsets.all(2),
                              child: pw.Text(
                                isAbsent ? 'a' : '',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  color: isAbsent ? PdfColors.red : PdfColors.green,
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }
}