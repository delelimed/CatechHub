// ══════════════════════════════════════════════════════════════════════════════
// pdf_export_service.dart — CatechHub (esportazione report PDF del gruppo)
//
// Genera un documento PDF in formato A4, professionale ma dal carattere
// giovane, con:
//   - Prima pagina (copertina): nome del gruppo in grande, descrizione
//     "Riassunto dell'anno catechistico", elenco delle parti esportate,
//     in fondo logo, nome dell'app e versione.
//   - Sezioni successive nell'ordine:
//       1. Anagrafica           5. Statistiche        8. Catechesi
//       2. Note di contatto     6. Documenti
//       3. Composizione gruppo  7. Programmazione incontri
//       4. Presenze (contenuto ruotato di 90° su foglio portrait)
//
// Ogni sezione viene inclusa solo se selezionata dall'utente tramite
// [PdfExportOptions].
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/storage/local_database.dart';
import '../../shared/models/catechesi_model.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/contact_note_model.dart';
import '../../shared/models/planning_meeting.dart';
import '../../shared/models/student_model.dart';
import '../../shared/utils/auth_utils.dart';

/// Opzioni di esportazione del report PDF.
class PdfExportOptions {
  final String classId;
  final bool includeAnagrafica;
  final bool includeNoteContatto;
  final bool includeComposizione;
  final bool includePresenze;
  final bool includeStatistiche;
  final bool includeDocumenti;
  final bool includeProgrammazione;
  final bool includeCatechesi;

  const PdfExportOptions({
    required this.classId,
    this.includeAnagrafica = false,
    this.includeNoteContatto = false,
    this.includeComposizione = false,
    this.includePresenze = false,
    this.includeStatistiche = false,
    this.includeDocumenti = false,
    this.includeProgrammazione = false,
    this.includeCatechesi = false,
  });

  /// Nome leggibile della sezione, usato nell'elenco della copertina.
  String get anagraficaLabel => 'Anagrafica';
  String get noteContattoLabel => 'Note di contatto';
  String get composizioneLabel => 'Composizione del gruppo';
  String get presenzeLabel => 'Presenze';
  String get statisticheLabel => 'Statistiche';
  String get documentiLabel => 'Documenti';
  String get programmazioneLabel => 'Programmazione degli incontri';
  String get catechesiLabel => 'Catechesi';

  List<String> selectedParts() {
    final parts = <String>[];
    if (includeAnagrafica) parts.add(anagraficaLabel);
    if (includeNoteContatto) parts.add(noteContattoLabel);
    if (includeComposizione) parts.add(composizioneLabel);
    if (includePresenze) parts.add(presenzeLabel);
    if (includeStatistiche) parts.add(statisticheLabel);
    if (includeDocumenti) parts.add(documentiLabel);
    if (includeProgrammazione) parts.add(programmazioneLabel);
    if (includeCatechesi) parts.add(catechesiLabel);
    return parts;
  }
}

/// Servizio di generazione del report PDF.
class PdfExportService {
  // ─── Palette (blu istituzionale + accenti giovanili) ─────────────────────
  static final PdfColor _primary = PdfColor.fromInt(0xFF174A7E);
  static final PdfColor _primaryLight = PdfColor.fromInt(0xFF4A90D9);
  static final PdfColor _accent = PdfColor.fromInt(0xFF3E92CC);
  static final PdfColor _teal = PdfColor.fromInt(0xFF2A9D8F);
  static final PdfColor _orange = PdfColor.fromInt(0xFFE76F51);
  static final PdfColor _green = PdfColor.fromInt(0xFF27AE60);
  static final PdfColor _red = PdfColor.fromInt(0xFFE74C3C);
  static final PdfColor _amber = PdfColor.fromInt(0xFFF4A62A);
  static final PdfColor _bgSoft = PdfColor.fromInt(0xFFF0F5FB);
  static final PdfColor _bgZebra = PdfColor.fromInt(0xFFF7FAFD);
  static final PdfColor _line = PdfColor.fromInt(0xFFDCE6F0);
  static final PdfColor _textDark = PdfColor.fromInt(0xFF1B2A3A);
  static final PdfColor _textGrey = PdfColor.fromInt(0xFF5B6B7B);
  static final PdfColor _white = PdfColor.fromInt(0xFFFFFFFF);

  static const double _pageMargin = 28;

  // ─── API pubblica ─────────────────────────────────────────────────────────

  /// Genera il report PDF per la classe [options.classId].
  static Future<Uint8List> generateReport(PdfExportOptions options) async {
    final pdf = pw.Document();
    final classId = options.classId;
    final rawClass = LocalDatabase.classes().get(classId);
    final classData = LocalDatabase.toStringDynamicMap(rawClass);
    final schoolClass = SchoolClass.fromMap(classId, classData);
    final className = schoolClass.name.isNotEmpty
        ? schoolClass.name
        : 'Gruppo';

    final students = _loadStudents(schoolClass);
    final attendance = _loadAttendance(schoolClass);
    final meetings = _loadMeetings(schoolClass);
    final documents = _loadDocuments(schoolClass);
    final catechesi = _loadCatechesi();
    final contactNotes = _loadContactNotes(schoolClass, students);

    final parts = options.selectedParts();
    final logoBytes = await _loadLogo();
    final appVersion = await _readVersion();
    final catechists = _loadCatechists(schoolClass);
    final createdAt = DateTime.now();

    // ── Copertina ───────────────────────────────────────────────────────────
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(_pageMargin),
        build: (ctx) => _buildCover(
          className,
          catechists,
          parts,
          logoBytes,
          appVersion,
          createdAt,
        ),
      ),
    );

    // ── Contenuto ───────────────────────────────────────────────────────────
    // Il report usa sempre fogli A4 portrait (verticale). Ogni modulo
    // (anagrafiche, presenze, statistiche, documenti, ...) inizia su una
    // pagina nuova. La tabella delle presenze è molto larga (una colonna per
    // incontro) e viene ruotata di 90° sul suo foglio: il registro sfrutta
    // l'asse lungo della pagina e si legge ruotando il foglio in senso orario,
    // senza creare pagine in landscape.
    var index = 0;

    void add(List<pw.Widget> target, pw.Widget widget) {
      target.add(widget);
      target.add(pw.SizedBox(height: 18));
    }

    // Ogni modulo selezionato viene stampato in una pagina nuova (e in più
    // pagine successive se il contenuto va a capo), con piè di pagina.
    void addModule(List<pw.Widget> widgets) {
      if (widgets.isEmpty) return;
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(_pageMargin, 24, _pageMargin, 36),
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          footer: (ctx) => _footer(ctx, className),
          // I singoli widget del modulo vengono emessi come figli di primo
          // livello del foglio MultiPage: cosi l'impostazione a capo del
          // contenuto avviene tra i widget reali (intestazione inclusa) e
          // l'intestazione blu di sezione non resta isolata sulla pagina,
          // separata dal contenuto che le segue.
          build: (ctx) => widgets,
        ),
      );
    }

    final anagrafica = <pw.Widget>[];
    final noteContatto = <pw.Widget>[];
    final composizione = <pw.Widget>[];
    final presenze = <pw.Widget>[];
    final statistiche = <pw.Widget>[];
    final documenti = <pw.Widget>[];
    final programmazione = <pw.Widget>[];
    final catechesiModule = <pw.Widget>[];

    if (options.includeAnagrafica) {
      add(anagrafica, _sectionHeader(++index, 'Anagrafica',
          'Dati anagrafici e contatti dei ragazzi del gruppo'));
      add(anagrafica, _anagraficaSection(students));
    }

    if (options.includeNoteContatto) {
      add(noteContatto, _sectionHeader(++index, 'Note di contatto',
          'Registro delle comunicazioni con i genitori'));
      add(noteContatto, _noteContattoSection(students, contactNotes));
    }

    if (options.includeComposizione) {
      add(composizione, _sectionHeader(++index, 'Composizione del gruppo',
          'Elenco dei ragazzi iscritti'));
      add(composizione, _composizioneSection(schoolClass, students));
    }

    if (options.includePresenze) {
      add(presenze, _sectionHeader(++index, 'Presenze',
          'Registro delle presenze per ogni incontro'));
      add(presenze, _rotatedPresenze(_presenzeSection(students, attendance)));
    }

    if (options.includeStatistiche) {
      add(statistiche, _sectionHeader(++index, 'Statistiche',
          'Sintesi dei dati di frequenza del gruppo'));
      add(statistiche, _statisticheSection(students, attendance, className));
    }

    if (options.includeDocumenti) {
      add(documenti, _sectionHeader(++index, 'Documenti',
          'Certificati, autorizzazioni e consegne'));
      add(documenti, _documentiSection(students, documents));
    }

    if (options.includeProgrammazione) {
      add(programmazione, _sectionHeader(++index, 'Programmazione degli incontri',
          'Incontri e riunioni programmate nel corso dell\'anno'));
      add(programmazione, _programmazioneSection(meetings));
    }

    if (options.includeCatechesi) {
      add(catechesiModule, _sectionHeader(++index, 'Catechesi',
          'Contenuti e schede catechetiche'));
      add(catechesiModule, _catechesiSection(catechesi));
    }

    addModule(anagrafica);
    addModule(noteContatto);
    addModule(composizione);
    addModule(presenze);
    addModule(statistiche);
    addModule(documenti);
    addModule(programmazione);
    addModule(catechesiModule);

    return pdf.save();
  }

  // ─── Caricamento dati ─────────────────────────────────────────────────────

  static List<Student> _loadStudents(SchoolClass schoolClass) {
    final students = LocalDatabase.values(
      LocalDatabase.students(),
      (id, data) => Student.fromMap(id, data),
    );
    final ids = schoolClass.studentIds.toSet();
    return Student.sortedBySurname(students.where((s) => ids.contains(s.id)));
  }

  static List<Map<String, dynamic>> _loadAttendance(SchoolClass schoolClass) {
    final records = LocalDatabase.values(
      LocalDatabase.attendance(),
      (id, data) => {'id': id, ...data},
    );
    return records
        .where((r) =>
            r['classId']?.toString() == schoolClass.id ||
            r['classUniqueCode']?.toString() == schoolClass.uniqueCode)
        .toList()
      ..sort((a, b) {
        final ad = DateTime.tryParse(a['date']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bd = DateTime.tryParse(b['date']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return ad.compareTo(bd);
      });
  }

  static List<PlanningMeeting> _loadMeetings(SchoolClass schoolClass) {
    final meetings = LocalDatabase.values(
      LocalDatabase.planning(),
      (id, data) => PlanningMeeting.fromMap(id, data),
    );
    return meetings
        .where((m) =>
            m.classId == schoolClass.id ||
            m.classUniqueCode == schoolClass.uniqueCode)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  static List<Map<String, dynamic>> _loadDocuments(SchoolClass schoolClass) {
    final docs = LocalDatabase.values(
      LocalDatabase.documents(),
      (id, data) => {'id': id, ...data},
    );
    if (schoolClass.uniqueCode.isEmpty) return [];
    return docs
        .where((d) => d['classUniqueCode']?.toString() == schoolClass.uniqueCode)
        .toList();
  }

  static List<Catechesi> _loadCatechesi() {
    final list = LocalDatabase.values(
      LocalDatabase.catechesi(),
      (id, data) => Catechesi.fromMap(id, data),
    );
    list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return list;
  }

  /// Nomi dei catechisti del gruppo: creatore, catechista corrente e ultimo
  /// autore di una modifica, in ordine alfabetico e senza duplicati.
  static List<String> _loadCatechists(SchoolClass schoolClass) {
    final names = <String>{};
    void add(String name) {
      final clean = name.trim();
      if (clean.isNotEmpty) names.add(clean);
    }

    add(schoolClass.creatorName);
    add(getCurrentCatechistName());
    add(schoolClass.lastModifiedBy);
    final result = names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  /// Note di contatto relative alla classe: quelle che referenziano il
  /// codice univoco della classe o uno degli studenti del gruppo.
  static List<ContactNote> _loadContactNotes(
      SchoolClass schoolClass, List<Student> students) {
    final notes = LocalDatabase.values(
      LocalDatabase.contactNotes(),
      (id, data) => ContactNote.fromMap(id, data),
    );
    final studentIds = {for (final s in students) s.id};
    final classUniqueCode = schoolClass.uniqueCode;
    return notes
        .where((n) =>
            (classUniqueCode.isNotEmpty && n.classUniqueCode == classUniqueCode) ||
            studentIds.contains(n.studentId))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  static Map<String, Student> _studentsById(List<Student> students) =>
      {for (final s in students) s.id: s};

  // ─── Copertina ────────────────────────────────────────────────────────────

  static pw.Widget _buildCover(
    String className,
    List<String> catechists,
    List<String> parts,
    Uint8List? logoBytes,
    String appVersion,
    DateTime createdAt,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 4),
        // Data e ora di creazione del report
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Creato il ${_formatDate(createdAt)} alle ${_formatTime(createdAt)}',
              style: pw.TextStyle(fontSize: 9, color: _textGrey),
            ),
            pw.Text(
              'CatechHub',
              style: pw.TextStyle(fontSize: 9, color: _textGrey),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        // Fascia decorativa superiore
        pw.Container(
          height: 6,
          decoration: pw.BoxDecoration(
            color: _primary,
            borderRadius: pw.BorderRadius.circular(6),
          ),
        ),
        pw.SizedBox(height: 40),

        // Nome del gruppo
        pw.Center(
          child: pw.Text(
            className,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: pw.Font.helveticaBold(),
              fontSize: 30,
              color: _primary,
            ),
          ),
        ),
        pw.SizedBox(height: 12),

        // Catechisti del gruppo (elenco alfabetico)
        if (catechists.isNotEmpty) ...[
          pw.Center(
            child: pw.Text(
              'CATECHISTI',
              style: pw.TextStyle(
                fontSize: 10,
                letterSpacing: 1.4,
                color: _textGrey,
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          for (final name in catechists) _coverPartRow(name),
          pw.SizedBox(height: 12),
        ],

        // Descrizione documento
        pw.Center(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: pw.BoxDecoration(
              color: _bgSoft,
              borderRadius: pw.BorderRadius.circular(30),
            ),
            child: pw.Text(
              'Riassunto dell\'anno catechistico',
              style: pw.TextStyle(
                font: pw.Font.helveticaBold(),
                fontSize: 13,
                color: _primaryLight,
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 42),

        // Parti esportate
        pw.Text(
          'CONTENUTI DEL DOCUMENTO',
          style: pw.TextStyle(
            fontSize: 10,
            letterSpacing: 1.4,
            color: _textGrey,
          ),
        ),
        pw.SizedBox(height: 12),
        for (final part in parts) _coverPartRow(part),
        pw.SizedBox(height: 10),

        pw.Spacer(),

        // Blocco inferiore: logo, nome app, versione
        if (logoBytes != null) ...[
          pw.Center(
            child: pw.Image(
              pw.MemoryImage(logoBytes),
              width: 64,
              height: 64,
              fit: pw.BoxFit.contain,
            ),
          ),
          pw.SizedBox(height: 6),
        ],
        pw.Center(
          child: pw.Text(
            'CatechHub',
            style: pw.TextStyle(
              font: pw.Font.helveticaBold(),
              fontSize: 15,
              color: _primary,
            ),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            appVersion.isEmpty
                ? 'CatechHub'
                : 'Versione $appVersion',
            style: pw.TextStyle(fontSize: 10, color: _textGrey),
          ),
        ),
        pw.SizedBox(height: 10),
      ],
    );
  }

  static pw.Widget _coverPartRow(String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        children: [
          pw.Container(
            width: 8,
            height: 8,
            decoration: pw.BoxDecoration(
              color: _teal,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 13, color: _textDark),
            ),
          ),
        ],
      ),
    );
  }

  static Future<Uint8List> _loadLogo() async {
    final data = await rootBundle.load('assets/images/logo.png');
    return data.buffer.asUint8List();
  }

  static Future<String> _readVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '';
    }
  }

  // ─── Sezioni ──────────────────────────────────────────────────────────────

  static pw.Widget _sectionHeader(int number, String title, String subtitle) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: pw.BoxDecoration(
        color: _primary,
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 30,
            height: 30,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: PdfColors.white.withAlpha(0.16),
              shape: pw.BoxShape.circle,
            ),
            child: pw.Text(
              '$number',
              style: pw.TextStyle(
                font: pw.Font.helveticaBold(),
                fontSize: 13,
                color: _white,
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    font: pw.Font.helveticaBold(),
                    fontSize: 15,
                    color: _white,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    subtitle,
                    style: pw.TextStyle(fontSize: 9.5, color: _white.withAlpha(0.82)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Anagrafica ───────────────────────────────────────────────────────────

  static pw.Widget _anagraficaSection(List<Student> students) {
    if (students.isEmpty) return _emptyState('Nessun ragazzo nel gruppo');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < students.length; i++) ...[
          _studentCard(students[i]),
          if (i != students.length - 1) pw.SizedBox(height: 10),
        ],
      ],
    );
  }

  // ─── Note di contatto ─────────────────────────────────────────────────────

  static pw.Widget _noteContattoSection(
      List<Student> students, List<ContactNote> notes) {
    if (notes.isEmpty) {
      return _emptyState('Nessuna nota di contatto registrata');
    }

    final byId = _studentsById(students);
    final grouped = <String, List<ContactNote>>{};
    for (final note in notes) {
      if (byId.containsKey(note.studentId)) {
        grouped.putIfAbsent(note.studentId, () => []).add(note);
      }
    }

    final studentKeys = grouped.keys.toList()
      ..sort((a, b) {
        final sa = byId[a]!;
        final sb = byId[b]!;
        return '${sa.surname} ${sa.name}'
            .toLowerCase()
            .compareTo('${sb.surname} ${sb.name}'.toLowerCase());
      });

    if (studentKeys.isEmpty) {
      return _emptyState('Nessuna nota di contatto registrata');
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < studentKeys.length; i++) ...[
          _contactNoteCard(byId[studentKeys[i]]!, grouped[studentKeys[i]]!),
          if (i != studentKeys.length - 1) pw.SizedBox(height: 10),
        ],
      ],
    );
  }

  static pw.Widget _contactNoteCard(Student s, List<ContactNote> notes) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: pw.BoxDecoration(
        color: _bgZebra,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _line, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 4,
                height: 16,
                decoration: pw.BoxDecoration(
                  color: _accent,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Text(
                  '${s.surname} ${s.name}'.trim(),
                  style: pw.TextStyle(
                    font: pw.Font.helveticaBold(),
                    fontSize: 12,
                    color: _primary,
                  ),
                ),
              ),
              pw.Text(
                '${notes.length} nota${notes.length == 1 ? '' : 'e'}',
                style: pw.TextStyle(fontSize: 9, color: _textGrey),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          for (var i = 0; i < notes.length; i++) ...[
            _contactNoteRow(notes[i]),
            if (i != notes.length - 1) pw.SizedBox(height: 5),
          ],
        ],
      ),
    );
  }

  static pw.Widget _contactNoteRow(ContactNote note) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 120,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${_formatDate(note.dateTime)} ${_formatTime(note.dateTime)}',
                style: pw.TextStyle(
                  font: pw.Font.helveticaBold(),
                  fontSize: 9,
                  color: _teal,
                ),
              ),
              pw.Text(
                ContactNote.mediumLabel(note.medium),
                style: pw.TextStyle(fontSize: 8.5, color: _textGrey),
              ),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            note.notes.trim().isEmpty ? '—' : note.notes.trim(),
            style: pw.TextStyle(
              fontSize: 9.5,
              color: _textDark,
              lineSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _studentCard(Student s) {
    final rows = <pw.Widget>[];

    void row(String label, String? value, {PdfColor? color}) {
      if (value == null || value.trim().isEmpty) return;
      rows.add(pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 92,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 9.5, color: _textGrey),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(fontSize: 10, color: color ?? _textDark),
            ),
          ),
        ],
      ));
      rows.add(pw.SizedBox(height: 3));
    }

    final mother = _fullName(s.motherName, s.motherSurname);
    final father = _fullName(s.fatherName, s.fatherSurname);

    row('Data di nascita', '${_formatDate(s.birthDate)}  (${_age(s.birthDate)} anni)');
    row('Madre', mother);
    row('Tel. madre', s.motherPhone);
    row('Padre', father);
    row('Tel. padre', s.fatherPhone);
    if (s.studentPhone.trim().isNotEmpty) row('Telefono ragazzo', s.studentPhone);
    if (s.allergies != null && s.allergies!.trim().isNotEmpty) {
      row('Allergie', s.allergies!.trim(), color: _red);
    }
    if (s.autonomousExits != null &&
        s.autonomousExits!.trim().isNotEmpty) {
      row('Uscite autonome', s.autonomousExits!.trim());
    }
    if (s.notes != null && s.notes!.trim().isNotEmpty) {
      row('Note', s.notes!.trim());
    }

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: pw.BoxDecoration(
        color: _bgZebra,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _line, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 4,
                height: 16,
                decoration: pw.BoxDecoration(
                  color: _accent,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Text(
                  '${s.surname} ${s.name}'.trim(),
                  style: pw.TextStyle(
                    font: pw.Font.helveticaBold(),
                    fontSize: 12,
                    color: _primary,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          ...rows,
        ],
      ),
    );
  }

  // ─── Composizione del gruppo ──────────────────────────────────────────────

  static pw.Widget _composizioneSection(
      SchoolClass schoolClass, List<Student> students) {
    final summary = [
      _summaryTile('${students.length}', 'Ragazzi iscritti', _accent),
      _summaryTile('${schoolClass.catechistIds.length}',
          'Catechisti assegnati', _teal),
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          children: [
            for (var i = 0; i < summary.length; i++) ...[
              pw.Expanded(child: summary[i]),
              if (i != summary.length - 1) pw.SizedBox(width: 10),
            ],
          ],
        ),
        pw.SizedBox(height: 12),
        if (students.isEmpty)
          _emptyState('Nessun ragazzo nel gruppo')
        else
          pw.Table(
            border: pw.TableBorder.all(color: _line, width: 0.8),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(1),
            },
            children: [
              _tableHeaderRow(['Nome e cognome', 'Data di nascita', 'Età']),
              for (final s in students)
                _tableDataRow([
                  '${s.surname} ${s.name}'.trim(),
                  _formatDate(s.birthDate),
                  '${_age(s.birthDate)} anni',
                ]),
            ],
          ),
      ],
    );
  }

  static pw.Widget _summaryTile(String value, String label, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _bgSoft,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _line, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              font: pw.Font.helveticaBold(),
              fontSize: 22,
              color: color,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 9.5, color: _textGrey),
          ),
        ],
      ),
    );
  }

  // ─── Presenze ─────────────────────────────────────────────────────────────

  /// Presenta la tabella presenze ruotata di 90° sul foglio A4 portrait:
  /// il registro, molto largo (una colonna per incontro), sfrutta l'asse
  /// lungo della pagina e si legge ruotando il foglio di 90° in senso orario.
  static pw.Widget _rotatedPresenze(pw.Widget table) {
    return pw.Transform.rotateBox(
      angle: -math.pi / 2,
      unconstrained: true,
      child: pw.SizedBox(
        width: 670,
        child: table,
      ),
    );
  }

  static pw.Widget _presenzeSection(
      List<Student> students, List<Map<String, dynamic>> attendance) {
    if (attendance.isEmpty) {
      return _emptyState('Nessuna presenza registrata');
    }

    final byId = _studentsById(students);
    final columns = <pw.TableColumnWidth>[
      const pw.FlexColumnWidth(2.4),
    ];
    for (var i = 0; i < attendance.length; i++) {
      columns.add(const pw.FlexColumnWidth(0.7));
    }
    columns.add(const pw.FlexColumnWidth(0.7));
    columns.add(const pw.FlexColumnWidth(0.7));

    final headerCells = <pw.Widget>[
      _cell('Studente', bold: true, color: _white),
      for (final record in attendance)
        _cell(
          _formatShortDate(record['date']?.toString() ?? ''),
          bold: true,
          color: _white,
        ),
      _cell('P', bold: true, color: _white),
      _cell('A', bold: true, color: _white),
    ];

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: _primary),
        children: headerCells,
      ),
      for (final s in students)
        _presenceRow(s, byId, attendance),
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.6),
      columnWidths: {for (var i = 0; i < columns.length; i++) i: columns[i]},
      children: rows,
    );
  }

  static pw.TableRow _presenceRow(
      Student s, Map<String, Student> byId, List<Map<String, dynamic>> attendance) {
    var present = 0, absent = 0;
    final cells = <pw.Widget>[
      _cell('${s.surname} ${s.name}'.trim()),
    ];
    for (final record in attendance) {
      final presence = Map<String, dynamic>.from(record['presence'] as Map? ?? {});
      final status = presence[s.id]?.toString() ?? '';
      if (status == 'Presente') present++;
      if (status == 'Assente') absent++;
      PdfColor? color;
      var text = '';
      switch (status) {
        case 'Presente':
          text = 'P';
          color = _green;
          break;
        case 'Assente':
          text = 'A';
          color = _red;
          break;
        case 'Giustificato':
          text = 'G';
          color = _amber;
          break;
        default:
          text = '';
      }
      cells.add(_cell(text, color: color, align: pw.TextAlign.center));
    }
    cells.add(_cell('$present', color: _green, align: pw.TextAlign.center, bold: true));
    cells.add(_cell('$absent', color: _red, align: pw.TextAlign.center, bold: true));
    return pw.TableRow(children: cells);
  }

  // ─── Statistiche ──────────────────────────────────────────────────────────

  static pw.Widget _statisticheSection(
      List<Student> students, List<Map<String, dynamic>> attendance, String className) {
    if (attendance.isEmpty) {
      return _emptyState('Nessuna presenza registrata');
    }

    var totalPresent = 0, totalAbsent = 0;
    final perStudent = <String, Map<String, int>>{};
    final perMeeting = <Map<String, dynamic>>[];

    for (final record in attendance) {
      final presence = Map<String, dynamic>.from(record['presence'] as Map? ?? {});
      var p = 0, a = 0;
      presence.forEach((id, status) {
        final st = status?.toString() ?? '';
        if (st == 'Presente') {
          p++;
          totalPresent++;
          perStudent.putIfAbsent(id, () => {'p': 0, 'a': 0})['p'] =
              (perStudent[id]?['p'] ?? 0) + 1;
        } else if (st == 'Assente') {
          a++;
          totalAbsent++;
          perStudent.putIfAbsent(id, () => {'p': 0, 'a': 0})['a'] =
              (perStudent[id]?['a'] ?? 0) + 1;
        }
      });
      final total = p + a;
      if (total > 0) {
        final meetingId = record['id']?.toString() ?? '';
        final dateStr = record['date']?.toString() ?? '';
        perMeeting.add({
          'id': meetingId,
          'title': _meetingTitle(meetingId, dateStr),
          'date': dateStr,
          'present': p,
          'absent': a,
          'total': total,
          'percent': p / total * 100,
        });
      }
    }

    final overall = totalPresent + totalAbsent;
    final presentRate = overall > 0 ? totalPresent / overall * 100 : 0.0;
    final absentRate = overall > 0 ? totalAbsent / overall * 100 : 0.0;
    final avgPerMeeting = perMeeting.isNotEmpty
        ? perMeeting.map((m) => (m['percent'] as double)).reduce((a, b) => a + b) /
            perMeeting.length
        : 0.0;
    final avgStudents = perMeeting.isNotEmpty
        ? (perMeeting.map((m) => (m['present'] as int)).reduce((a, b) => a + b) /
                perMeeting.length)
            .round()
        : 0;
    final totalStudents = perMeeting.isNotEmpty
        ? perMeeting.map((m) => (m['total'] as int)).reduce((a, b) => a > b ? a : b)
        : 0;

    var best = perMeeting.isEmpty ? null : perMeeting.first;
    var worst = perMeeting.isEmpty ? null : perMeeting.first;
    for (final m in perMeeting) {
      if ((m['percent'] as double) > (best!['percent'] as double)) best = m;
      if ((m['percent'] as double) < (worst!['percent'] as double)) worst = m;
    }

    final cards = [
      _metricCard('Presenze medie', '${presentRate.toStringAsFixed(1)}%', _green),
      _metricCard('Assenze medie', '${absentRate.toStringAsFixed(1)}%', _red),
      _metricCard('Media presenze per incontro',
          '${avgPerMeeting.toStringAsFixed(1)}%', _accent),
      _metricCard('Totale incontri', '${perMeeting.length}', _teal),
      _metricCard('Ragazzi nel gruppo', '$totalStudents', _orange),
      _metricCard('Media ragazzi per incontro', '$avgStudents',
          PdfColor.fromInt(0xFF8E44AD)),
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: cards,
        ),
        pw.SizedBox(height: 14),
        if (best != null)
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.green.withAlpha(0.08),
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(color: _green.withAlpha(0.4), width: 1),
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 6,
                  height: 6,
                  decoration: pw.BoxDecoration(
                    color: _green,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Text(
                    'Migliore presenza: ${best['title']} '
                    '(${(best['percent'] as double).toStringAsFixed(0)}%)',
                    style: pw.TextStyle(fontSize: 10, color: _textDark),
                  ),
                ),
              ],
            ),
          ),
        if (worst != null) ...[
          pw.SizedBox(height: 6),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.red.withAlpha(0.08),
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(color: _red.withAlpha(0.4), width: 1),
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 6,
                  height: 6,
                  decoration: pw.BoxDecoration(
                    color: _red,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Text(
                    'Peggiore presenza: ${worst['title']} '
                    '(${(worst['percent'] as double).toStringAsFixed(0)}%)',
                    style: pw.TextStyle(fontSize: 10, color: _textDark),
                  ),
                ),
              ],
            ),
          ),
        ],
        pw.SizedBox(height: 14),
        pw.Text(
          'ANDAMENTO PRESENZE NEL TEMPO',
          style: pw.TextStyle(fontSize: 9.5, letterSpacing: 1.1, color: _textGrey),
        ),
        pw.SizedBox(height: 8),
        _trendChart(perMeeting),
        pw.SizedBox(height: 18),
        pw.Text(
          'DETTAGLIO PER RAGAZZO',
          style: pw.TextStyle(fontSize: 9.5, letterSpacing: 1.1, color: _textGrey),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.8),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1.4),
          },
          children: [
            _tableHeaderRow(['Nome e cognome', 'Presenti', 'Assenti', 'Percentuale']),
            for (final s in students)
              _tableDataRow([
                '${s.surname} ${s.name}'.trim(),
                '${perStudent[s.id]?['p'] ?? 0}',
                '${perStudent[s.id]?['a'] ?? 0}',
                _percentOf(perStudent[s.id]?['p'] ?? 0, perStudent[s.id]?['a'] ?? 0),
              ]),
          ],
        ),
      ],
    );
  }

  static String _percentOf(int present, int absent) {
    final total = present + absent;
    if (total == 0) return '—';
    return '${(present / total * 100).toStringAsFixed(1)}%';
  }

  /// Titolo leggibile di un incontro: preferisce il titolo programmato,
  /// altrimenti la data breve del record presenze.
  static String _meetingTitle(String meetingId, String dateStr) {
    if (meetingId.isEmpty) return _formatShortDate(dateStr);
    final data =
        LocalDatabase.toStringDynamicMap(LocalDatabase.planning().get(meetingId));
    final title = data['title']?.toString().trim() ?? '';
    if (title.isNotEmpty) return title;
    return _formatShortDate(dateStr);
  }

  /// Grafico a linee dell'andamento dei presenti nel tempo.
  static pw.Widget _trendChart(List<Map<String, dynamic>> perMeeting) {
    if (perMeeting.length < 2) {
      return _emptyState('Dati non sufficienti per il grafico');
    }
    final maxPresent =
        perMeeting.map((m) => (m['total'] as int)).reduce((a, b) => a > b ? a : b);
    final maxTick = maxPresent <= 0 ? 1 : maxPresent;
    final dates = [
      for (final m in perMeeting) _formatShortDate(m['date'] as String),
    ];
    final yTicks =
        <int>{for (var i = 0; i <= 4; i++) (maxTick * i / 4).round()}.toList()
          ..sort();

    return pw.SizedBox(
      height: 190,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis.fromStrings(
            dates,
            divisions: true,
            color: _line,
            textStyle: pw.TextStyle(fontSize: 7, color: _textGrey),
          ),
          yAxis: pw.FixedAxis<int>(
            yTicks,
            divisions: true,
            divisionsDashed: true,
            color: _line,
            textStyle: pw.TextStyle(fontSize: 7, color: _textGrey),
          ),
        ),
        datasets: [
          pw.LineDataSet(
            data: [
              for (var i = 0; i < perMeeting.length; i++)
                pw.PointChartValue(
                  i.toDouble(),
                  (perMeeting[i]['present'] as int).toDouble(),
                ),
            ],
            color: _green,
            pointSize: 2.5,
            lineWidth: 2,
            drawSurface: true,
            surfaceOpacity: 0.2,
          ),
        ],
      ),
    );
  }

  static pw.Widget _metricCard(String label, String value, PdfColor color) {
    return pw.Container(
      width: 120,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _bgSoft,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _line, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              font: pw.Font.helveticaBold(),
              fontSize: 17,
              color: color,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 8.5, color: _textGrey),
          ),
        ],
      ),
    );
  }

  // ─── Documenti ────────────────────────────────────────────────────────────

  static pw.Widget _documentiSection(
      List<Student> students, List<Map<String, dynamic>> documents) {
    if (documents.isEmpty) {
      return _emptyState('Nessun documento registrato');
    }
    final studentsById = _studentsById(students);

    final rows = <pw.TableRow>[];
    for (final doc in documents) {
      final deliveries = LocalDatabase.toStringDynamicMap(
        LocalDatabase.documentDeliveries().get(doc['id'].toString()),
      );
      var givenOut = 0, received = 0, exonerated = 0;
      final pending = <String>[];
      deliveries.forEach((studentId, value) {
        final d = Map<String, dynamic>.from(value as Map? ?? {});
        if (d['exoneratedAt'] != null) exonerated++;
        if (d['givenOutAt'] != null) givenOut++;
        if (d['receivedAt'] != null) received++;
        if (d['givenOutAt'] != null && d['receivedAt'] == null) {
          final s = studentsById[studentId.toString()];
          if (s != null) pending.add('${s.surname} ${s.name}'.trim());
        }
      });

      final cells = [
        _cell(
          '${doc['title']?.toString() ?? 'Documento'}\n'
          'Consegna: ${doc['createdAt']?.toString() ?? ''}',
        ),
        _cell('$givenOut', align: pw.TextAlign.center),
        _cell('$received', align: pw.TextAlign.center),
        _cell('${givenOut - received}', align: pw.TextAlign.center,
            color: (givenOut - received) > 0 ? _orange : _textDark),
        _cell('$exonerated', align: pw.TextAlign.center),
      ];

      final rowCells = <pw.Widget>[
        for (var i = 0; i < cells.length; i++)
          pw.Padding(padding: const pw.EdgeInsets.all(5), child: cells[i]),
      ];

      rows.add(pw.TableRow(children: rowCells));

      if (pending.isNotEmpty) {
        rows.add(pw.TableRow(
          decoration: pw.BoxDecoration(color: _bgZebra),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(5, 2, 5, 6),
              child: pw.Text(
                'In attesa di riconsegna: ${pending.join(', ')}',
                style: pw.TextStyle(fontSize: 8, color: _orange, font: pw.Font.helveticaOblique()),
              ),
            ),
            for (var i = 1; i < 5; i++) pw.Padding(padding: pw.EdgeInsets.all(2), child: pw.Text('')),
          ],
        ));
      }
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.8),
      columnWidths: {
        0: const pw.FlexColumnWidth(3.2),
        1: const pw.FlexColumnWidth(0.9),
        2: const pw.FlexColumnWidth(0.9),
        3: const pw.FlexColumnWidth(0.9),
        4: const pw.FlexColumnWidth(0.9),
      },
      children: [
        _tableHeaderRow([
          'Documento',
          'Consegnati',
          'Riconsegnati',
          'In attesa',
          'Esonerati',
        ]),
        ...rows,
      ],
    );
  }

  // ─── Programmazione incontri ──────────────────────────────────────────────

  static pw.Widget _programmazioneSection(List<PlanningMeeting> meetings) {
    if (meetings.isEmpty) {
      return _emptyState('Nessun incontro programmato');
    }
    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.8),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(2.4),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(2.6),
      },
      children: [
        _tableHeaderRow(['Data', 'Titolo', 'Tipo', 'Attività / Note']),
        for (final m in meetings)
          _tableDataRow([
            _formatDate(m.date),
            m.title,
            m.isReunion ? 'Riunione' : 'Incontro',
            _joinNonEmpty([m.activity, m.notes]),
          ]),
      ],
    );
  }

  // ─── Catechesi ────────────────────────────────────────────────────────────

  static pw.Widget _catechesiSection(List<Catechesi> catechesi) {
    if (catechesi.isEmpty) {
      return _emptyState('Nessuna catechesi registrata');
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < catechesi.length; i++) ...[
          _catechesiCard(catechesi[i]),
          if (i != catechesi.length - 1) pw.SizedBox(height: 10),
        ],
      ],
    );
  }

  static pw.Widget _catechesiCard(Catechesi c) {
    final chips = <pw.Widget>[];
    for (final tag in c.tags) {
      chips.add(pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: pw.BoxDecoration(
          color: _bgSoft,
          borderRadius: pw.BorderRadius.circular(20),
          border: pw.Border.all(color: _accent.withAlpha(0.5), width: 0.8),
        ),
        child: pw.Text(
          tag,
          style: pw.TextStyle(fontSize: 8, color: _primaryLight),
        ),
      ));
    }

    final refs = c.biblicalReferences.isNotEmpty
        ? 'Riferimenti biblici: ${c.biblicalReferences.join(' · ')}'
        : '';

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _bgZebra,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _line, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            c.title,
            style: pw.TextStyle(
              font: pw.Font.helveticaBold(),
              fontSize: 12,
              color: _primary,
            ),
          ),
          if (chips.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Wrap(spacing: 4, runSpacing: 4, children: chips),
          ],
          if (refs.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              refs,
              style: pw.TextStyle(fontSize: 9, color: _teal),
            ),
          ],
          if (c.description.trim().isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              c.description,
              style: pw.TextStyle(fontSize: 9.5, color: _textDark, lineSpacing: 1.3),
            ),
          ],
          if (c.websiteReferences.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Link: ${c.websiteReferences.join('\n')}',
              style: pw.TextStyle(fontSize: 8.5, color: _primaryLight),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Widget e helper comuni ───────────────────────────────────────────────

  static pw.Widget _emptyState(String message) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: _bgZebra,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _line, width: 1),
      ),
      child: pw.Text(
        message,
        style: pw.TextStyle(fontSize: 11, color: _textGrey, font: pw.Font.helveticaOblique()),
      ),
    );
  }

  static pw.TableRow _tableHeaderRow(List<String> headers) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: _primary),
      children: [
        for (final h in headers)
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(
              h,
              style: pw.TextStyle(
                font: pw.Font.helveticaBold(),
                fontSize: 9,
                color: _white,
              ),
            ),
          ),
      ],
    );
  }

  static pw.TableRow _tableDataRow(List<String> cells) {
    return pw.TableRow(
      children: [
        for (final c in cells)
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(c, style: pw.TextStyle(fontSize: 9, color: _textDark)),
          ),
      ],
    );
  }

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    PdfColor? color,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          font: bold ? pw.Font.helveticaBold() : pw.Font.helvetica(),
          fontSize: 7.5,
          color: color ?? _textDark,
        ),
      ),
    );
  }

  static pw.Widget _footer(pw.Context context, String className) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'CatechHub · $className',
            style: pw.TextStyle(fontSize: 8, color: _textGrey),
          ),
          pw.Text(
            'Pagina ${context.pageNumber}',
            style: pw.TextStyle(fontSize: 8, color: _textGrey),
          ),
        ],
      ),
    );
  }

  // ─── Formattazione ────────────────────────────────────────────────────────

  static String _fullName(String name, String surname) {
    final full = '$name $surname'.trim();
    return full.isNotEmpty ? full : '';
  }

  static String _formatDate(DateTime date) {
    return '${_two(date.day)}/${_two(date.month)}/${date.year}';
  }

  static String _formatTime(DateTime date) {
    return '${_two(date.hour)}:${_two(date.minute)}';
  }

  static String _formatShortDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return '${_two(dt.day)}/${_two(dt.month)}';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static int _age(DateTime birthDate) {
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age < 0 ? 0 : age;
  }

  static String _joinNonEmpty(List<String?> values) {
    final clean = values.where((v) => v != null && v.trim().isNotEmpty).toList();
    return clean.join(' · ');
  }
}
