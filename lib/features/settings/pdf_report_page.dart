// ══════════════════════════════════════════════════════════════════════════════
// pdf_report_page.dart — CatechHub (esportazione report PDF del gruppo)
//
// Permette al catechista di scegliere quali informazioni della classe
// attualmente aperta esportare in un documento PDF A4:
//   - Anagrafica
//   - Note di contatto
//   - Composizione del gruppo
//   - Presenze
//   - Statistiche
//   - Documenti
//   - Programmazione degli incontri
//   - Catechesi
//
// Il PDF viene generato da [PdfExportService] e poi condiviso tramite il
// foglio di condivisione nativo (salva su file, stampa, invia, ecc.).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/providers/current_class_provider.dart';
import '../../shared/models/class_model.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'pdf_export_service.dart';

/// Modello di una voce selezionabile.
class _ModuleOption {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool Function() selected;
  final void Function(bool) onChanged;

  const _ModuleOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onChanged,
  });
}

class PdfReportPage extends ConsumerStatefulWidget {
  const PdfReportPage({super.key});

  @override
  ConsumerState<PdfReportPage> createState() => _PdfReportPageState();
}

class _PdfReportPageState extends ConsumerState<PdfReportPage> {
  bool _includeAnagrafica = true;
  bool _includeNoteContatto = false;
  bool _includeComposizione = true;
  bool _includePresenze = true;
  bool _includeStatistiche = true;
  bool _includeDocumenti = true;
  bool _includeProgrammazione = true;
  bool _includeCatechesi = false;

  bool _generating = false;

  List<_ModuleOption> get _options => [
        _ModuleOption(
          label: 'Anagrafica',
          subtitle: 'Dati anagrafici, contatti e note dei ragazzi',
          icon: Icons.people_rounded,
          color: const Color(0xFF3E92CC),
          selected: () => _includeAnagrafica,
          onChanged: (v) => setState(() => _includeAnagrafica = v),
        ),
        _ModuleOption(
          label: 'Note di contatto',
          subtitle: 'Registro delle comunicazioni con i genitori',
          icon: Icons.contact_phone_rounded,
          color: const Color(0xFF6A4FA3),
          selected: () => _includeNoteContatto,
          onChanged: (v) => setState(() => _includeNoteContatto = v),
        ),
        _ModuleOption(
          label: 'Composizione del gruppo',
          subtitle: 'Elenco dei ragazzi iscritti al gruppo',
          icon: Icons.groups_rounded,
          color: const Color(0xFF2A9D8F),
          selected: () => _includeComposizione,
          onChanged: (v) => setState(() => _includeComposizione = v),
        ),
        _ModuleOption(
          label: 'Presenze',
          subtitle: 'Registro completo delle presenze per incontro',
          icon: Icons.fact_check_rounded,
          color: const Color(0xFF27AE60),
          selected: () => _includePresenze,
          onChanged: (v) => setState(() => _includePresenze = v),
        ),
        _ModuleOption(
          label: 'Statistiche',
          subtitle: 'Percentuali di frequenza e dati di sintesi',
          icon: Icons.bar_chart_rounded,
          color: const Color(0xFFE76F51),
          selected: () => _includeStatistiche,
          onChanged: (v) => setState(() => _includeStatistiche = v),
        ),
        _ModuleOption(
          label: 'Documenti',
          subtitle: 'Certificati, autorizzazioni e stato consegne',
          icon: Icons.description_rounded,
          color: const Color(0xFFF4A62A),
          selected: () => _includeDocumenti,
          onChanged: (v) => setState(() => _includeDocumenti = v),
        ),
        _ModuleOption(
          label: 'Programmazione degli incontri',
          subtitle: 'Incontri e riunioni programmate nel corso dell\'anno',
          icon: Icons.calendar_month_rounded,
          color: const Color(0xFF9B59B6),
          selected: () => _includeProgrammazione,
          onChanged: (v) => setState(() => _includeProgrammazione = v),
        ),
        _ModuleOption(
          label: 'Catechesi',
          subtitle: 'Schede e contenuti catechetici',
          icon: Icons.menu_book_rounded,
          color: const Color(0xFF174A7E),
          selected: () => _includeCatechesi,
          onChanged: (v) => setState(() => _includeCatechesi = v),
        ),
      ];

  bool get _anySelected =>
      _includeAnagrafica ||
      _includeNoteContatto ||
      _includeComposizione ||
      _includePresenze ||
      _includeStatistiche ||
      _includeDocumenti ||
      _includeProgrammazione ||
      _includeCatechesi;

  void _setAll(bool value) {
    setState(() {
      _includeAnagrafica = value;
      _includeNoteContatto = value;
      _includeComposizione = value;
      _includePresenze = value;
      _includeStatistiche = value;
      _includeDocumenti = value;
      _includeProgrammazione = value;
      _includeCatechesi = value;
    });
  }

  Future<void> _generate(SchoolClass schoolClass) async {
    if (!_anySelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleziona almeno una parte da esportare.'),
        ),
      );
      return;
    }

    setState(() => _generating = true);
    try {
      final options = PdfExportOptions(
        classId: schoolClass.id,
        includeAnagrafica: _includeAnagrafica,
        includeNoteContatto: _includeNoteContatto,
        includeComposizione: _includeComposizione,
        includePresenze: _includePresenze,
        includeStatistiche: _includeStatistiche,
        includeDocumenti: _includeDocumenti,
        includeProgrammazione: _includeProgrammazione,
        includeCatechesi: _includeCatechesi,
      );

      final bytes = await PdfExportService.generateReport(options);

      if (!mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'CatechHub_${_safeFileName(schoolClass.name)}.pdf',
        subject: 'Report del gruppo ${schoolClass.name}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante la generazione del PDF: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  String _safeFileName(String name) {
    return name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  }

  @override
  Widget build(BuildContext context) {
    final currentClass = ref.watch(currentClassDetailsProvider);

    return AppScaffold(
      title: 'Esporta Report PDF',
      child: currentClass == null || currentClass.id.isEmpty
          ? _NoClassSelected()
          : _buildSelection(context, currentClass),
    );
  }

  Widget _buildSelection(BuildContext context, SchoolClass schoolClass) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(4),
      children: [
        // Intestazione con la classe corrente
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF174A7E), Color(0xFF2368B1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.picture_as_pdf_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gruppo da esportare',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      schoolClass.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.check_circle_rounded, color: Colors.white),
            ],
          ),
        ),
        const SizedBox(height: 18),

        Text(
          'Cosa vuoi esportare?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? colorScheme.onSurface : const Color(0xFF174A7E),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Il report verrà generato in formato A4 con la copertina '
          'e le sezioni selezionate.',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.grey.shade400 : Colors.black54,
          ),
        ),
        const SizedBox(height: 12),

        ..._options.map(
          (option) => _ModuleTile(option: option, isDark: isDark, colorScheme: colorScheme),
        ),

        const SizedBox(height: 12),
        Row(
          children: [
            TextButton.icon(
              onPressed: _anySelected ? () => _setAll(false) : null,
              icon: const Icon(Icons.deselect_rounded, size: 18),
              label: const Text('Deseleziona tutto'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _anySelected ? null : () => _setAll(true),
              icon: const Icon(Icons.select_all_rounded, size: 18),
              label: const Text('Seleziona tutto'),
            ),
          ],
        ),

        const SizedBox(height: 16),

        SizedBox(
          height: 52,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE76F51),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _generating ? null : () => _generate(schoolClass),
            icon: _generating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.share_rounded),
            label: Text(
              _generating
                  ? 'Generazione in corso…'
                  : 'Genera e condividi PDF',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),
        Center(
          child: Text(
            'Il documento verrà generato e aperto nel foglio di '
            'condivisione: potrai salvarlo, stamparlo o inviarlo.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Riga selezionabile di un modulo da esportare.
class _ModuleTile extends StatelessWidget {
  final _ModuleOption option;
  final bool isDark;
  final ColorScheme colorScheme;

  const _ModuleTile({
    required this.option,
    required this.isDark,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => option.onChanged(!option.selected()),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? colorScheme.surfaceContainer : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: option.selected()
                ? option.color.withValues(alpha: 0.6)
                : (isDark
                    ? colorScheme.outline.withValues(alpha: 0.2)
                    : Colors.grey.shade200),
            width: option.selected() ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: option.selected(),
              activeColor: option.color,
              onChanged: (v) => option.onChanged(v ?? false),
            ),
            const SizedBox(width: 6),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: option.color.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(option.icon, color: option.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? colorScheme.onSurface : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    option.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
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

/// Stato quando non è presente alcuna classe aperta.
class _NoClassSelected extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.groups_rounded,
              size: 56,
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Nessun gruppo aperto',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Apri un gruppo dalla dashboard o dalle impostazioni '
              'per esportare il report PDF.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
