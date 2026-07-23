/// Pagina per la cancellazione selettiva dei dati del registro catechistico.
///
/// L'utente può scegliere una o più categorie da eliminare tra:
/// - Anagrafica ragazzi (nome, genitori, allergie, consegne documenti)
/// - Presenze / appelli registrati
/// - Giornate e riunioni (programmazione)
/// - Allegati (foto e PDF cifrati)
///
/// Mostra il conteggio attuale per ogni categoria tramite [DataDeletionService].
/// La cancellazione è definitiva e irreversibile sul dispositivo, previa
/// conferma tramite dialog.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/data_deletion_service.dart';
import '../../shared/widgets/app_scaffold.dart';

final dataDeletionServiceProvider = Provider((_) => DataDeletionService());

class DeleteDataPage extends ConsumerStatefulWidget {
  const DeleteDataPage({super.key});

  @override
  ConsumerState<DeleteDataPage> createState() => _DeleteDataPageState();
}

class _DeleteDataPageState extends ConsumerState<DeleteDataPage> {
  final _selected = <DataDeletionCategory>{};
  bool _isDeleting = false;
  late DataDeletionCounts _counts;

  @override
  void initState() {
    super.initState();
    _counts = DataDeletionService().getCounts();
  }

  void _refreshCounts() {
    setState(() {
      _counts = ref.read(dataDeletionServiceProvider).getCounts();
    });
  }

  Future<void> _confirmAndDelete() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona almeno una voce')),
      );
      return;
    }

    final labels = _selected.map(_labelFor).join(', ');
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? colorScheme.surface : Colors.white,
        title: const Text('Conferma cancellazione'),
        content: Text(
          'Eliminare definitivamente:\n\n$labels\n\n'
          'L\'operazione non può essere annullata.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Elimina',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      await ref.read(dataDeletionServiceProvider).deleteSelected(_selected);
      if (!mounted) return;

      setState(() {
        _selected.clear();
        _isDeleting = false;
      });
      _refreshCounts();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dati eliminati')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e')),
      );
    }
  }

  String _labelFor(DataDeletionCategory c) {
    switch (c) {
      case DataDeletionCategory.anagrafica:
        return 'Anagrafica ragazzi';
      case DataDeletionCategory.presenze:
        return 'Presenze / appelli';
      case DataDeletionCategory.giornate:
        return 'Giornate e riunioni';
      case DataDeletionCategory.catechesi:
        return 'Catechesi';
      case DataDeletionCategory.noteContatto:
        return 'Note di contatto';
      case DataDeletionCategory.allegati:
        return 'Foto e PDF allegati';
      case DataDeletionCategory.documenti:
        return 'Documenti e consegne';
    }
  }

  String _subtitleFor(DataDeletionCategory c) {
    switch (c) {
      case DataDeletionCategory.anagrafica:
        return 'Ragazzi, genitori, allergie, note e consegne documenti';
      case DataDeletionCategory.presenze:
        return 'Tutti gli appelli registrati';
      case DataDeletionCategory.giornate:
        return 'Programmazione incontri, giornate e riunioni';
      case DataDeletionCategory.catechesi:
        return 'Argomenti e contenuti delle catechesi';
      case DataDeletionCategory.noteContatto:
        return 'Comunicazioni con le famiglie';
      case DataDeletionCategory.allegati:
        return 'Tutti i file cifrati (foto e PDF)';
      case DataDeletionCategory.documenti:
        return 'Certificati, autorizzazioni e consegne';
    }
  }

  int _countFor(DataDeletionCategory c) {
    switch (c) {
      case DataDeletionCategory.anagrafica:
        return _counts.students;
      case DataDeletionCategory.presenze:
        return _counts.attendance;
      case DataDeletionCategory.giornate:
        return _counts.planning;
      case DataDeletionCategory.catechesi:
        return _counts.catechesi;
      case DataDeletionCategory.noteContatto:
        return _counts.contactNotes;
      case DataDeletionCategory.allegati:
        return _counts.attachments;
      case DataDeletionCategory.documenti:
        return _counts.documents;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return AppScaffold(
      title: 'Cancella dati',
      child: _isDeleting
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? colorScheme.errorContainer.withValues(alpha: 0.3) : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? colorScheme.error.withValues(alpha: 0.3) : Colors.red.shade100),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: isDark ? colorScheme.error : Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Scegli cosa eliminare. I dati non vengono inviati online: '
                          'la cancellazione è definitiva sul dispositivo.',
                          style: TextStyle(
                            color: isDark ? colorScheme.onErrorContainer : Colors.red.shade900,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ...DataDeletionCategory.values.map((c) => _buildOption(c, isDark, colorScheme)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.delete_forever_rounded),
                    label: Text(
                      _selected.isEmpty
                          ? 'Elimina selezionati'
                          : 'Elimina ${_selected.length} ${_selected.length == 1 ? 'voce' : 'voci'}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _confirmAndDelete,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildOption(DataDeletionCategory category, bool isDark, ColorScheme colorScheme) {
    final count = _countFor(category);
    final isSelected = _selected.contains(category);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isDark ? colorScheme.surfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            setState(() {
              if (isSelected) {
                _selected.remove(category);
              } else {
                _selected.add(category);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected ? Colors.red : (isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.grey.shade200),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: CheckboxListTile(
              value: isSelected,
              activeColor: Colors.red,
              onChanged: count == 0
                  ? null
                  : (_) {
                      setState(() {
                        if (isSelected) {
                          _selected.remove(category);
                        } else {
                          _selected.add(category);
                        }
                      });
                    },
              title: Text(
                _labelFor(category),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? colorScheme.onSurface : Colors.black87,
                ),
              ),
              subtitle: Text(
                count == 0
                    ? '${_subtitleFor(category)} — nessun dato'
                    : '${_subtitleFor(category)} — $count elementi',
                style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
              secondary: Icon(
                _iconFor(category),
                color: count == 0 ? Colors.grey : (isDark ? colorScheme.primary : const Color(0xFF174A7E)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(DataDeletionCategory c) {
    switch (c) {
      case DataDeletionCategory.anagrafica:
        return Icons.people_rounded;
      case DataDeletionCategory.presenze:
        return Icons.fact_check_rounded;
      case DataDeletionCategory.giornate:
        return Icons.event_note_rounded;
      case DataDeletionCategory.catechesi:
        return Icons.menu_book_rounded;
      case DataDeletionCategory.noteContatto:
        return Icons.contact_mail_rounded;
      case DataDeletionCategory.allegati:
        return Icons.attach_file_rounded;
      case DataDeletionCategory.documenti:
        return Icons.description_rounded;
    }
  }
}
