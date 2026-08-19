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
/// Per il Responsabile Catechistico la cancellazione selettiva agisce invece
/// su TUTTI i dati della parrocchia (tutte le classi, i ragazzi, i catechisti,
/// le presenze, la logistica e gli allegati).
///
/// In fondo alla pagina è presente anche il pulsante "Elimina tutto e
/// ripristina" che cancella OGNI dato, chiave e associazione, riportando
/// l'app allo stato di onboarding. La cancellazione totale è protetta da un
/// flusso a conferma differita (24 ore di attesa, finestra di conferma entro
/// 30 ore): evita eliminazioni accidentali e non cancella mai in automatico.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/storage/data_deletion_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/user_role.dart';
import '../../shared/utils/app_mode.dart';
import '../../shared/utils/auth_utils.dart';
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
  SchoolClass? _currentClass;
  DeletionRequestStatus _deletionStatus = DeletionRequestStatus.none;
  Timer? _countdownTimer;

  bool get _isResponsabile => UserRole.isResponsabile;

  /// La cancellazione totale dei dati è disponibile solo:
  /// - per il Responsabile Catechistico;
  /// - per un catechista in modalità normale che sia il TITOLARE che ha
  ///   creato la classe.
  /// È nascosta se il dispositivo è associato a una parrocchia gestita dal
  /// Responsabile (modalità "Associato") o se l'utente non è il creatore
  /// della classe.
  bool get _canRequestTotalDeletion {
    if (_isResponsabile) return true;
    if (AppModeUtils.isAssociato) return false;
    final c = _currentClass;
    if (c == null) return false;
    return c.isCreator(
      AuthService.localUserId,
      getCurrentCatechistName(),
      catechistId: AuthService.getCatechistId(),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentClass();
    if (_currentClassId != null) {
      _counts = DataDeletionService().getCounts(classId: _currentClassId);
    } else {
      _counts = DataDeletionService().getCounts();
    }
    _refreshDeletionStatus();
    _countdownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _refreshDeletionStatus();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _loadCurrentClass() {
    if (_isResponsabile) return;
    final classes = LocalDatabase.classes();
    const uid = AuthService.localUserId;
    for (final key in classes.keys) {
      final data = Map<String, dynamic>.from(classes.get(key) as Map);
      final ids = (data['catechistIds'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
      if (ids.contains(uid)) {
        _currentClassId = key.toString();
        _currentClassName = data['name']?.toString() ?? 'Classe';
        _currentClass = SchoolClass.fromMap(
          key.toString(),
          LocalDatabase.toStringDynamicMap(classes.get(key)),
        );
        break;
      }
    }
  }

  void _refreshCounts() {
    setState(() {
      _counts = ref
          .read(dataDeletionServiceProvider)
          .getCounts(classId: _currentClassId);
    });
  }

  void _refreshDeletionStatus() {
    setState(() {
      _deletionStatus = ref
          .read(dataDeletionServiceProvider)
          .getDeletionRequestStatus();
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
      await ref
          .read(dataDeletionServiceProvider)
          .deleteSelected(_selected, classId: _currentClassId);
      if (!mounted) return;

      setState(() {
        _selected.clear();
        _isDeleting = false;
      });
      _refreshCounts();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dati eliminati')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore: $e')));
    }
  }

  bool _isResetting = false;

  /// Gestisce il pulsante "Elimina tutto e ripristina" secondo il ciclo
  /// 24/30 ore della richiesta di cancellazione totale.
  Future<void> _handleResetTotal() async {
    final service = ref.read(dataDeletionServiceProvider);
    switch (_deletionStatus) {
      case DeletionRequestStatus.none:
      case DeletionRequestStatus.expired:
        final confirmed = await _confirmStartDeletionRequest();
        if (confirmed != true || !mounted) return;
        await service.requestDeletion();
        _refreshDeletionStatus();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Richiesta di cancellazione registrata. Dopo 24 ore avrai 6 ore '
              'di tempo per confermare; la richiesta scade dopo 30 ore.',
            ),
          ),
        );
        return;
      case DeletionRequestStatus.waiting:
        return;
      case DeletionRequestStatus.available:
        await _confirmAndResetAll();
    }
  }

  Future<bool?> _confirmStartDeletionRequest() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? colorScheme.surface : Colors.white,
        title: const Text(
          'Richiedi la cancellazione totale',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Verrà registrata la richiesta di eliminare IRREVERSIBILMENTE '
          'tutti i dati (classi, ragazzi, presenze, allegati, associazioni, '
          'chiavi crittografiche e account).\n\n'
          'La cancellazione NON avviene subito: dopo 24 ore avrai 6 ore di '
          'tempo per tornare qui e confermare. Se non la confermi entro 30 '
          'ore dalla richiesta, la richiesta scade senza cancellare nulla.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Registra richiesta'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelDeletionRequest() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? colorScheme.surface : Colors.white,
        title: const Text(
          'Annullare la richiesta?',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'La richiesta di cancellazione totale verrà annullata. '
          'Nessun dato verrà eliminato.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Torna indietro'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Annulla richiesta',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await ref.read(dataDeletionServiceProvider).clearDeletionRequest();
    _refreshDeletionStatus();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Richiesta di cancellazione annullata.')),
    );
  }

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
        const SnackBar(
          content: Text(
            'Tutti i dati sono stati eliminati. Reindirizzamento...',
          ),
        ),
      );

      await Future.delayed(const Duration(seconds: 1));
      if (mounted) context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isResetting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore durante il reset: $e')));
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

  /// Testo informativo della sezione "Elimina tutto e ripristina", aggiornato
  /// in base allo stato della richiesta di cancellazione (ciclo 24/30 ore).
  String get _deletionStatusText {
    final service = ref.read(dataDeletionServiceProvider);
    final requestedAt = service.getDeletionRequestTime();
    final now = DateTime.now();
    switch (_deletionStatus) {
      case DeletionRequestStatus.none:
        return 'Cancella OGNI dato, classe, associazione, chiave crittografica '
            'e account. L\'app tornerà allo stato iniziale come appena '
            'installata.\n\nLa cancellazione non è immediata: viene registrata '
            'una richiesta e dopo 24 ore avrai 6 ore di tempo per confermarla. '
            'Se non la confermi entro 30 ore, la richiesta scade senza '
            'cancellare nulla.';
      case DeletionRequestStatus.waiting:
        final remaining = requestedAt == null
            ? DataDeletionService.kDeletionRequestWait
            : requestedAt
                  .add(DataDeletionService.kDeletionRequestWait)
                  .difference(now);
        return 'Richiesta di cancellazione registrata. La cancellazione sarà '
            'disponibile dopo 24 ore dalla richiesta.\n\n'
            'Attesa in corso: ${_formatDuration(remaining)}.\n\n'
            'Dopo le 24 ore avrai 6 ore di tempo per confermare; se non lo '
            'fai, la richiesta scade senza cancellare nulla.';
      case DeletionRequestStatus.available:
        final remaining = requestedAt == null
            ? DataDeletionService.kDeletionRequestWindow
            : requestedAt
                  .add(DataDeletionService.kDeletionRequestExpiry)
                  .difference(now);
        return 'La richiesta è pronta: puoi ora confermare l\'eliminazione '
            'definitiva di tutti i dati.\n\n'
            'Finestra di conferma (6 ore) ancora disponibile: '
            '${_formatDuration(remaining)}.';
      case DeletionRequestStatus.expired:
        return 'La richiesta è scaduta dopo 30 ore senza eseguire alcuna '
            'cancellazione. Nessun dato è stato eliminato.\n\n'
            'Inoltra una nuova richiesta per riavviare il ciclo di 24 ore.';
    }
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return '${h}h ${m.toString().padLeft(2, '0')}m';
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
                    _isResetting
                        ? 'Eliminazione totale in corso...'
                        : 'Eliminazione in corso...',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_isResponsabile)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF174A7E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF174A7E).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.church_rounded,
                          color: Color(0xFF174A7E),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _isResponsabile
                                ? 'Ambito: tutta la parrocchia'
                                : 'Classe attiva: $className',
                            style: const TextStyle(
                              color: Color(0xFF174A7E),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF174A7E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF174A7E).withValues(alpha: 0.3),
                      ),
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
                    color: isDark
                        ? colorScheme.errorContainer.withValues(alpha: 0.3)
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? colorScheme.error.withValues(alpha: 0.3)
                          : Colors.red.shade100,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: isDark ? colorScheme.error : Colors.red.shade700,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isResponsabile
                              ? 'La cancellazione agisce su TUTTI i dati della '
                                    'parrocchia: tutte le classi, i ragazzi, i '
                                    'catechisti, le presenze, la logistica e gli '
                                    'allegati presenti sul dispositivo.'
                              : 'La cancellazione agisce SOLO sulla classe "$className". '
                                    'I dati di altre classi sul dispositivo non vengono toccati.',
                          style: TextStyle(
                            color: isDark
                                ? colorScheme.onErrorContainer
                                : Colors.red.shade900,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ...DataDeletionCategory.values.map(
                  (c) => _buildOption(c, isDark, colorScheme),
                ),
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

                // ─── RESET TOTALE (richiesta con ciclo 24/30 ore) ─────────
                if (!_canRequestTotalDeletion)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.grey.shade800.withValues(alpha: 0.3)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'La cancellazione totale dei dati non è disponibile '
                            'su questo dispositivo: il dispositivo è associato '
                            'a una parrocchia gestita dal Responsabile oppure '
                            'non sei il titolare che ha creato la classe.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade700,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.red.shade900.withValues(alpha: 0.2)
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_rounded,
                              color: Colors.red.shade700,
                              size: 24,
                            ),
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
                          _deletionStatusText,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Colors.red.shade200
                                : Colors.red.shade900,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child:
                              _deletionStatus == DeletionRequestStatus.available
                              ? FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: const Icon(Icons.delete_sweep_rounded),
                                  label: const Text(
                                    'Conferma ed elimina tutto',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: _handleResetTotal,
                                )
                              : OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: const Icon(Icons.delete_sweep_rounded),
                                  label: Text(
                                    _deletionStatus ==
                                            DeletionRequestStatus.waiting
                                        ? 'Attendi 24 ore dalla richiesta...'
                                        : 'Richiedi la cancellazione totale',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed:
                                      _deletionStatus ==
                                          DeletionRequestStatus.waiting
                                      ? null
                                      : _handleResetTotal,
                                ),
                        ),
                        if (_deletionStatus != DeletionRequestStatus.none) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                              ),
                              icon: const Icon(Icons.cancel_outlined, size: 20),
                              label: const Text('Annulla richiesta'),
                              onPressed: _cancelDeletionRequest,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildOption(
    DataDeletionCategory category,
    bool isDark,
    ColorScheme colorScheme,
  ) {
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
                color: isSelected
                    ? Colors.red
                    : (isDark
                          ? colorScheme.outline.withValues(alpha: 0.2)
                          : Colors.grey.shade200),
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
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              secondary: Icon(
                _iconFor(category),
                color: count == 0
                    ? Colors.grey
                    : (isDark ? colorScheme.primary : const Color(0xFF174A7E)),
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
