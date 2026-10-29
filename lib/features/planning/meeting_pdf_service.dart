import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../shared/models/attachment_model.dart';
import '../../shared/models/attachment_parent_type.dart';
import '../../shared/models/catechesi_model.dart';
import '../../shared/models/planning_meeting.dart';
import '../attachments/attachments_repository.dart';
import '../catechesi/catechesi_repository.dart';

class MeetingPdfService {
  static const _primary = PdfColor.fromInt(0xFF174A7E);
  static const _accent = PdfColor.fromInt(0xFF3E92CC);
  static const _softBackground = PdfColor.fromInt(0xFFF0F5FB);
  static const _line = PdfColor.fromInt(0xFFDCE6F0);
  static const _text = PdfColor.fromInt(0xFF1B2A3A);
  static const _muted = PdfColor.fromInt(0xFF5B6B7B);
  static const _pageMargin = 30.0;

  static Future<Uint8List> generate({
    required PlanningMeeting meeting,
    required List<String> catechesiIds,
  }) async {
    final pdf = pw.Document();
    final attachments = AttachmentsRepository().listForParent(
      parentId: meeting.id,
      parentType: AttachmentParentType.meeting,
    );
    final catechesi = CatechesiRepository()
        .getCatechesiSync()
        .where((item) => catechesiIds.contains(item.id))
        .toList();
    final logo = await _loadLogo();
    final imageAttachments = <_ImageAttachment>[];

    for (final attachment in attachments.where((item) => item.isImage)) {
      try {
        imageAttachments.add(
          _ImageAttachment(
            attachment,
            pw.MemoryImage(
              await AttachmentsRepository().readBytes(attachment.id),
            ),
          ),
        );
      } catch (_) {
        // The attachment remains listed even if its preview cannot be read.
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(_pageMargin, 26, _pageMargin, 38),
        header: (_) => _header(meeting, logo),
        footer: (context) => _footer(context),
        build: (_) => [
          pw.SizedBox(height: 12),
          _sectionTitle('Informazioni dell\'incontro'),
          _infoGrid(meeting),
          if (meeting.activity.trim().isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _sectionTitle('Attività / Argomenti'),
            _textBlock(meeting.activity),
          ],
          if (meeting.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _sectionTitle('Note'),
            _textBlock(meeting.notes),
          ],
          if (attachments.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _sectionTitle('Allegati dell\'incontro'),
            _attachmentsList(attachments),
          ],
          if (imageAttachments.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _sectionTitle('Immagini allegate'),
            _imageGrid(imageAttachments),
          ],
          if (catechesi.isNotEmpty) ...[
            pw.SizedBox(height: 24),
            _sectionTitle('Catechesi associate'),
            ...catechesi.expand(_catechesiWidgets),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  static Future<void> printOrShare({
    required PlanningMeeting meeting,
    required List<String> catechesiIds,
  }) async {
    final bytes = await generate(meeting: meeting, catechesiIds: catechesiIds);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'CatechHub_${_safeName(meeting.title)}.pdf',
      subject: 'Incontro del ${DateFormat('dd/MM/yyyy').format(meeting.date)}',
    );
  }

  static pw.Widget _header(PlanningMeeting meeting, Uint8List? logo) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _line, width: 1)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null)
            pw.Container(
              width: 34,
              height: 34,
              margin: const pw.EdgeInsets.only(right: 10),
              child: pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'CatechHub',
                  style: pw.TextStyle(
                    color: _primary,
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  meeting.isReunion ? 'Scheda riunione' : 'Scheda incontro',
                  style: pw.TextStyle(
                    color: _text,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _line, width: 1)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'CatechHub · Esportazione incontro',
            style: const pw.TextStyle(color: _muted, fontSize: 8),
          ),
          pw.Text(
            'Pagina ${context.pageNumber}',
            style: const pw.TextStyle(color: _muted, fontSize: 8),
          ),
        ],
      ),
    );
  }

  static pw.Widget _sectionTitle(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const pw.BoxDecoration(
        color: _primary,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 7,
            height: 7,
            decoration: const pw.BoxDecoration(
              color: _accent,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            title,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _infoGrid(PlanningMeeting meeting) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.all(14),
      decoration: const pw.BoxDecoration(
        color: _softBackground,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            meeting.title,
            style: pw.TextStyle(
              color: _text,
              fontSize: 17,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              _labelValue(
                'Data',
                DateFormat('dd/MM/yyyy').format(meeting.date),
              ),
              if (meeting.time != null && meeting.time!.isNotEmpty)
                _labelValue('Orario', meeting.time!),
              _labelValue(
                'Tipo',
                meeting.isReunion ? 'Riunione' : 'Giornata di catechismo',
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _labelValue(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: const pw.TextStyle(color: _muted, fontSize: 8),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(
            color: _text,
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static pw.Widget _textBlock(String text) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(color: _text, fontSize: 10, lineSpacing: 1.4),
      ),
    );
  }

  static pw.Widget _attachmentsList(List<Attachment> attachments) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Column(
        children: [
          for (final attachment in attachments)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                vertical: 7,
                horizontal: 10,
              ),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: _line)),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      attachment.name,
                      style: const pw.TextStyle(color: _text, fontSize: 9),
                    ),
                  ),
                  pw.Text(
                    '${attachment.mimeType} · ${attachment.sizeLabel}',
                    style: const pw.TextStyle(color: _muted, fontSize: 8),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _imageGrid(List<_ImageAttachment> images) {
    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final image in images)
          pw.Container(
            width: 245,
            padding: const pw.EdgeInsets.all(5),
            decoration: const pw.BoxDecoration(
              color: _softBackground,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  height: 125,
                  width: double.infinity,
                  child: pw.Image(image.image, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  image.attachment.name,
                  maxLines: 1,
                  style: const pw.TextStyle(color: _muted, fontSize: 8),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static Iterable<pw.Widget> _catechesiWidgets(Catechesi item) sync* {
    yield pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.all(12),
      decoration: const pw.BoxDecoration(
        color: _softBackground,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            item.title,
            style: pw.TextStyle(
              color: _primary,
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (item.description.trim().isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              item.description,
              style: const pw.TextStyle(color: _text, fontSize: 9),
            ),
          ],
          if (item.tags.isNotEmpty) ...[
            pw.SizedBox(height: 7),
            pw.Text(
              'Tag: ${item.tags.join(', ')}',
              style: const pw.TextStyle(color: _muted, fontSize: 8),
            ),
          ],
          if (item.biblicalReferences.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              'Riferimenti biblici: ${item.biblicalReferences.join(', ')}',
              style: const pw.TextStyle(color: _muted, fontSize: 8),
            ),
          ],
          if (item.websiteReferences.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              'Risorse: ${item.websiteReferences.join(', ')}',
              style: const pw.TextStyle(color: _muted, fontSize: 8),
            ),
          ],
        ],
      ),
    );
  }

  static Future<Uint8List?> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/images/logo.png');
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static String _safeName(String value) {
    final name = value.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_').trim();
    return name.isEmpty ? 'incontro' : name;
  }
}

class _ImageAttachment {
  final Attachment attachment;
  final pw.MemoryImage image;

  const _ImageAttachment(this.attachment, this.image);
}
