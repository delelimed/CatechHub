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
///
/// La cancellazione agisce SOLO sulla classe attualmente aperta. I dati
/// di altre classi presenti sul dispositivo non vengono toccati.
/// Le associazioni dispositivi non appartengono a nessuna classe e vengono
/// gestite globalmente.
///
/// In fondo alla pagina è presente anche il pulsante "Elimina tutto e
/// ripristina" che cancella OGNI dato, chiave e associazione, riportando
/// l'app allo stato di onboarding.
library;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/storage/data_deletion_service.dart';
import '../../core/storage/local_database.dart';
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
  String? _currentClassId;
  String? _currentClassName;

  @override
  void initState() {
    super.initState();
    _loadCurrentClass();
    if (_currentClassId != null) {
      _counts = DataDeletionService().getCounts(classId: _currentClassId);
    } else {
      _counts = DataDeletionService().getCounts();
    }
  }

  void _loadCurrentClass() {
    final classes = LocalDatabase.classes();
    const uid = AuthService.localUserId;
    for (final key in classes.keys) {
      final data = Map<String, dynamic>.from(classes.get(key) as Map);
      final ids = (data['catechistIds'] as List? ?? []).map((e) => e.toString()).toList();
      if (ids.contains(uid)) {
        _currentClassId = key.toString();
        _currentClassName = data['name']?.toString() ?? 'Classe';
        break;
      }
    }
  }

  void _refreshCounts() {
    setState(() {
      _counts = ref.read(dataDeletionServiceProvider).getCounts(classId: _currentClassId);
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
    final className = _currentClassName ?? 'Classe corrente';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? colorScheme.surface : Colors.white,
        title: const Text('Conferma cancellazione'),
        content: Text(
          'Classe: $className\n\n'
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
      await ref.read(dataDeletionServiceProvider).deleteSelected(_selected, classId: _currentClassId);
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

  bool _isResetting = false;

  Future<void> _confirmAndResetAll() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? colorScheme.surface : Colors.white,
        title: const Text(
          'Eliminare TUTTO?',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Questa operazione cancellerà IRREVERSIBILMENTE:\n\n'
          '• Tutte le classi e i gruppi\n'
          '• Tutti i ragazzi (anagrafica, presenze, note)\n'
          '• Tutti gli allegati (foto, PDF)\n'
          '• Tutte le catechesi e programmazioni\n'
          '• Tutti i documenti e consegne\n'
          '• Tutte le associazioni con altri dispositivi\n'
          '• Tutte le chiavi crittografiche nello StrongBox/TEE\n'
          '• I dati del profilo e dell\'account\n\n'
          'L\'app tornerà alla configurazione iniziale (onboarding).\n\n'
          'Questa azione NON può essere annullata.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Elimina tutto',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isResetting = true);

    try {
      await ref.read(dataDeletionServiceProvider).deleteAllAndReset();

      await ref.read(authStateProvider.notifier).lock();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tutti i dati sono stati eliminati. Reindirizzamento...')),
      );

      await Future.delayed(const Duration(seconds: 1));
      if (mounted) context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isResetting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore durante il reset: $e')),
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
      case DataDeletionCategory.associazioni:
        return 'Associazioni dispositivi';
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
      case DataDeletionCategory.associazioni:
        return 'Dispositivi associati e chiavi di sincronizzazione';
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
      case DataDeletionCategory.associazioni:
        return _counts.associations;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final className = _currentClassName ?? 'Classe corrente';

    return AppScaffold(
      title: 'Cancella dati',
      child: _isDeleting || _isResetting
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    _isResetting ? 'Eliminazione totale in corso...' : 'Eliminazione in corso...',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF174A7E).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF174A7E).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.class_, color: const Color(0xFF174A7E)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Classe attiva: $className',
                          style: const TextStyle(
                            color: Color(0xFF174A7E),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
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
                          'La cancellazione agisce SOLO sulla classe "$className". '
                          'I dati di altre classi sul dispositivo non vengono toccati.',
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

                const SizedBox(height: 40),

                // ─── RESET TOTALE ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.red.shade900.withValues(alpha: 0.2) : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_rounded, color: Colors.red.shade700, size: 24),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Elimina tutto e ripristina',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Cancella OGNI dato, classe, associazione, chiave crittografica '
                        'e account. L\'app tornerà allo stato iniziale come appena installata.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.red.shade200 : Colors.red.shade900,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.delete_sweep_rounded),
                          label: const Text(
                            'Elimina tutto e ripristina',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: _confirmAndResetAll,
                        ),
                      ),
                    ],
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
      case DataDeletionCategory.associazioni:
        return Icons.sync_alt_rounded;
    }
  }
}
