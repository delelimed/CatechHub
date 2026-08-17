// ══════════════════════════════════════════════════════════════════════════════
// import_ragazzi_page.dart — CatechHub (wizard "Importa Dati Ragazzi")
//
// Riservato al profilo Responsabile. Flusso a 4 passi:
//   1. Selezione file (.csv / .xls / .xlsx) + template di esempio.
//   2. Mappatura colonne (auto + correzione manuale con dropdown).
//   3. Anteprima, validazione e risoluzione duplicati.
//   4. Report finale dell'importazione.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/user_role.dart';
import '../../../shared/widgets/app_scaffold.dart';
import 'import_ragazzi_models.dart';
import 'import_ragazzi_service.dart';
import 'import_ragazzi_template.dart';

class ImportRagazziPage extends ConsumerStatefulWidget {
  const ImportRagazziPage({super.key});

  @override
  ConsumerState<ImportRagazziPage> createState() => _ImportRagazziPageState();
}

enum _Step { start, mapping, review, report }

class _ImportRagazziPageState extends ConsumerState<ImportRagazziPage> {
  final _service = ImportRagazziService();

  _Step _step = _Step.start;
  String? _fileName;
  List<String> _headers = [];
  List<List<String>> _rows = [];
  Map<int, ImportField> _mapping = {};
  List<String> _warnings = [];
  List<ImportRow> _rowsStatus = [];
  ImportReport? _report;
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    if (!UserRole.isResponsabile) {
      return AppScaffold(
        title: 'Importa Dati Ragazzi',
        child: const Center(
          child: Text(
            'Funzione riservata al Responsabile Catechistico.',
          ),
        ),
      );
    }

    return AppScaffold(
      title: 'Importa Dati Ragazzi',
      child: switch (_step) {
        _Step.start => _buildStart(),
        _Step.mapping => _buildMapping(),
        _Step.review => _buildReview(),
        _Step.report => _buildReport(),
      },
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // PASSO 1 — SELEZIONE FILE
  // ═════════════════════════════════════════════════════════════════════

  Widget _buildStart() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.grey.shade700 : Colors.blue.shade100,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Importazione massiva anagrafica ragazzi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Carica un file .csv o .xlsx con l\'elenco dei ragazzi. '
                'Campi obbligatori: Nome, Cognome e Data di nascita. '
                'Le colonne verranno associate automaticamente e potranno '
                'essere corrette nel passo successivo.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_warnings.isNotEmpty) ...[
          for (final w in _warnings) _warningTile(w),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.upload_file_rounded),
          label: Text(_fileName == null ? 'Seleziona file' : 'Cambia file'),
        ),
        if (_fileName != null) ...[
          const SizedBox(height: 8),
          Text(
            'File selezionato: $_fileName',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _downloadTemplate,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Scarica template'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showTemplatePreview,
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: const Text('Vedi campi'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_fileName != null)
          FilledButton.icon(
            onPressed: () => _goToMapping(),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Continua'),
          ),
      ],
    );
  }

  Widget _warningTile(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    // file_picker 12: pickFiles restituisce List<PlatformFile> (vuota su annulla).
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xls', 'xlsx'],
    );
    if (files.isEmpty) return;
    final file = files.single;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      _setWarning('Impossibile leggere il file selezionato.');
      return;
    }

    setState(() {
      _fileName = file.name;
      _warnings = [];
    });

    final parsed = _service.parseFile(file.name, bytes);
    if (parsed == null) {
      _setWarning('Formato file non supportato.');
      return;
    }
    setState(() {
      _headers = parsed.headers;
      _rows = parsed.rows;
      _warnings = List.of(parsed.warnings);
      _mapping = _service.autoMapHeaders(parsed.headers);
    });
  }

  void _setWarning(String message) {
    if (mounted) setState(() => _warnings = [message]);
  }

  // ═════════════════════════════════════════════════════════════════════
  // TEMPLATE
  // ═════════════════════════════════════════════════════════════════════

  Future<void> _downloadTemplate() async {
    final csv = buildTemplateCsv();
    try {
      await FilePicker.saveFile(
        dialogTitle: 'Salva template importazione',
        fileName: 'template_importazione_ragazzi.csv',
        bytes: Uint8List.fromList(csv.codeUnits),
      );
      _snack('Template salvato.');
    } catch (_) {
      _snack('Salvataggio template non riuscito.');
    }
  }

  void _showTemplatePreview() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Campi del template'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Obbligatori: Nome, Cognome, Data di nascita.\n'
                'Opzionali: dati dei genitori, email, note mediche.\n',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const Divider(),
              for (final field in ImportField.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        field.required
                            ? Icons.star_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 16,
                        color: field.required
                            ? Colors.orange
                            : Colors.green.shade600,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          field.label,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        field.required ? 'Obbligatorio' : 'Opzionale',
                        style: TextStyle(
                          fontSize: 11,
                          color: field.required
                              ? Colors.orange.shade800
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ═════════════════════════════════════════════════════════════════════
  // PASSO 2 — MAPPATURA COLONNE
  // ═════════════════════════════════════════════════════════════════════

  void _goToMapping() {
    if (_headers.isEmpty) {
      _snack('Il file non contiene intestazioni: impossibile mappare le '
          'colonne.');
      return;
    }
    setState(() {
      _mapping = _service.autoMapHeaders(_headers);
      _step = _Step.mapping;
    });
  }

  Widget _buildMapping() {
    final missing = _service.missingRequired(_mapping);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900 : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? Colors.grey.shade700
                        : Colors.blue.shade100,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mappa le colonne',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Associa ogni colonna del file al campo del database. '
                      'Le colonne riconosciute sono già selezionate.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                    if (missing.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Campi obbligatori da mappare: '
                          '${missing.map((f) => f.label).join(', ')}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < _headers.length; i++) _mappingTile(i, isDark),
              const SizedBox(height: 16),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _step = _Step.start),
                child: const Text('Indietro'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: missing.isEmpty ? _proceedToReview : null,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Anteprima e validazione'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mappingTile(int columnIndex, bool isDark) {
    final header = _headers[columnIndex];
    final current = _mapping[columnIndex];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: current != null
              ? Colors.green.shade300
              : isDark
                  ? Colors.grey.shade700
                  : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Colonna ${columnIndex + 1}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF174A7E)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              header.isEmpty ? '(senza intestazione)' : header,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          DropdownButton<ImportField?>(
            value: current,
            hint: const Text('— non mappato —', style: TextStyle(fontSize: 13)),
            isExpanded: false,
            items: [
              const DropdownMenuItem<ImportField?>(
                value: null,
                child: Text('Non mappato', style: TextStyle(fontSize: 13)),
              ),
              for (final field in ImportField.values)
                DropdownMenuItem<ImportField?>(
                  value: field,
                  child: Text(
                    field.label,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) {
                setState(() => _mapping.remove(columnIndex));
                return;
              }
              // Evita duplicati: un campo non può essere mappato due volte.
              setState(() {
                final previousOwner = _mapping.entries
                    .where((e) => e.value == value)
                    .map((e) => e.key)
                    .toList();
                for (final owner in previousOwner) {
                  _mapping.remove(owner);
                }
                _mapping[columnIndex] = value;
              });
            },
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // PASSO 3 — ANTEPRIMA, VALIDAZIONE E DEDUPLICA
  // ═════════════════════════════════════════════════════════════════════

  void _proceedToReview() {
    final rowsStatus = _service.buildRows(_rows, _mapping);
    final withDuplicates = _service.detectDuplicates(rowsStatus);
    setState(() {
      _rowsStatus = withDuplicates;
      _step = _Step.review;
    });
  }

  Widget _buildReview() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final valid = _rowsStatus
        .where((r) => r.status == ImportRowStatus.valid)
        .toList();
    final errors = _rowsStatus
        .where((r) => r.status == ImportRowStatus.error)
        .toList();
    final duplicates = _rowsStatus
        .where((r) => r.status == ImportRowStatus.duplicate)
        .toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _summaryChip(
                isDark,
                Icons.check_circle_rounded,
                Colors.green,
                '${valid.length} nuovi',
              ),
              const SizedBox(height: 8),
              _summaryChip(
                isDark,
                Icons.error_rounded,
                Colors.red,
                '${errors.length} con errori',
              ),
              const SizedBox(height: 8),
              _summaryChip(
                isDark,
                Icons.content_copy_rounded,
                Colors.orange,
                '${duplicates.length} possibili duplicati',
              ),
              const SizedBox(height: 20),
              if (duplicates.isNotEmpty) ...[
                Text(
                  'Duplicati rilevati',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                for (final d in duplicates) _duplicateCard(d, isDark),
                const SizedBox(height: 20),
              ],
              if (errors.isNotEmpty) ...[
                Text(
                  'Righe con errori (verranno saltate)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                for (final e in errors) _errorCard(e, isDark),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _step = _Step.mapping),
                child: const Text('Indietro'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _importing ? null : _runImport,
                  icon: _importing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_importing
                      ? 'Importazione…'
                      : 'Importa ${valid.length} ragazzi'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryChip(bool isDark, IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _duplicateCard(ImportRow row, bool isDark) {
    final existing = row.existing;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_search_rounded,
                  color: Colors.orange.shade700, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Riga ${row.rowNumber}: ${row.displayName}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (existing != null) ...[
            const SizedBox(height: 6),
            Text(
              'Già presente: ${existing.name} ${existing.surname} '
              '(${_formatDate(existing.birthDate)})',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButton<DuplicateAction>(
                  value: row.action,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: DuplicateAction.ignore,
                      child: Text('Ignora duplicato',
                          style: TextStyle(fontSize: 13)),
                    ),
                    DropdownMenuItem(
                      value: DuplicateAction.update,
                      child: Text('Aggiorna dati esistenti',
                          style: TextStyle(fontSize: 13)),
                    ),
                    DropdownMenuItem(
                      value: DuplicateAction.createNew,
                      child: Text('Crea come nuovo',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ],
                  onChanged: (action) {
                    if (action == null) return;
                    setState(() {
                      final index = _rowsStatus.indexOf(row);
                      _rowsStatus[index] = row.copyWith(action: action);
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorCard(ImportRow row, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Riga ${row.rowNumber}: ${row.displayName}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          for (final error in row.errors)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '• $error',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // PASSO 4 — REPORT FINALE
  // ═════════════════════════════════════════════════════════════════════

  Future<void> _runImport() async {
    setState(() => _importing = true);
    try {
      final report = await _service.importRows(_rowsStatus);
      if (mounted) {
        setState(() {
          _report = report;
          _step = _Step.report;
          _importing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        _snack('Importazione non riuscita: $e');
      }
    }
  }

  Widget _buildReport() {
    final report = _report;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.shade300),
          ),
          child: Column(
            children: [
              const Icon(Icons.task_alt_rounded, size: 48, color: Colors.green),
              const SizedBox(height: 12),
              Text(
                report?.summary ?? 'Importazione completata.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _reportRow(Icons.check_circle_rounded, Colors.green,
            'Ragazzi importati', report?.imported ?? 0),
        _reportRow(Icons.update_rounded, Colors.blue,
            'Duplicati aggiornati', report?.updated ?? 0),
        _reportRow(Icons.skip_next_rounded, Colors.orange,
            'Duplicati ignorati', report?.duplicatesIgnored ?? 0),
        _reportRow(Icons.error_rounded, Colors.red,
            'Errori saltati', report?.errors ?? 0),
        if (report != null && report.errorMessages.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final msg in report.errorMessages) _errorCard(
            ImportRow(
              rowNumber: 0,
              values: const {},
              errors: [msg],
              status: ImportRowStatus.error,
            ),
            isDark,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => setState(() {
            _step = _Step.start;
            _report = null;
            _rowsStatus = [];
            _rows = [];
            _headers = [];
            _fileName = null;
            _warnings = [];
          }),
          icon: const Icon(Icons.home_rounded),
          label: const Text('Torna all\'inizio'),
        ),
      ],
    );
  }

  Widget _reportRow(IconData icon, Color color, String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Text(
            '$count',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

