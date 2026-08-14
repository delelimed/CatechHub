// ══════════════════════════════════════════════════════════════════════════════
// parish_network_page.dart — CatechHub (Rete Catechistica Parrocchiale)
//
// Pagina della rete parrocchiale: riunioni ed avvisi globali (Canale
// Parrocchiale, in chiaro per la rete) e gestione dei titoli per-classe
// (Canale Classe, cifrato). Il Responsabile o il Catechista Titolare può
// estendere il titolo di trattamento a un altro dispositivo tramite QR.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/auth/auth_service.dart';
import '../../core/services/qr_data_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/avviso_template_model.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/parish_event.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../sync/class_channel_service.dart';
import '../sync/p2p/p2p_sync_service.dart';
import '../sync/parish_channel_service.dart';

/// Pagina della Rete Catechistica Parrocchiale.
class ParishNetworkPage extends StatefulWidget {
  const ParishNetworkPage({super.key});

  @override
  State<ParishNetworkPage> createState() => _ParishNetworkPageState();
}

class _ParishNetworkPageState extends State<ParishNetworkPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Widget? get _fab {
    switch (_tabController.index) {
      case 0:
        return FloatingActionButton.extended(
          tooltip: 'Nuova riunione',
          icon: const Icon(Icons.add),
          label: const Text('Nuova riunione'),
          onPressed: () => _newEventDialog(context),
        );
      case 1:
        return FloatingActionButton.extended(
          tooltip: 'Nuovo avviso',
          icon: const Icon(Icons.add),
          label: const Text('Nuovo avviso'),
          onPressed: () => _newAvvisoDialog(context),
        );
      case 2:
        return FloatingActionButton.extended(
          tooltip: 'Concedi titolo di classe',
          icon: const Icon(Icons.qr_code_rounded),
          label: const Text('Concedi titolo'),
          onPressed: () => _grantTitlePicker(context),
        );
      default:
        return null;
    }
  }

  Future<void> _syncParishChannel(BuildContext context) async {
    final service = P2PSyncService();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await service.sendParishChannelToAll();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Canale parrocchiale sincronizzato.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Sincronizzazione fallita: $e')),
      );
    }
  }

  /// Apre un selettore di classe e concede il titolo di trattamento alla
  /// classe scelta (flusso di creazione dei titoli, tab dedicato).
  Future<void> _grantTitlePicker(BuildContext context) async {
    final classes = LocalDatabase.values(
      LocalDatabase.classes(),
      (id, data) => SchoolClass.fromMap(id, data),
    );
    if (classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nessuna classe presente su questo dispositivo.',
          ),
        ),
      );
      return;
    }
    String selectedId = classes.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: const Text('Concedi titolo'),
          content: DropdownButtonFormField<String>(
            initialValue: selectedId,
            decoration: const InputDecoration(
              labelText: 'Classe',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final c in classes)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => selectedId = v);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Continua'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      if (!context.mounted) return;
      final c = classes.firstWhere((x) => x.id == selectedId);
      await _grantTitleForClass(context, c);
    }
  }

  Future<void> _newEventDialog(BuildContext context) async {
    final title = TextEditingController();
    final location = TextEditingController();
    final notes = TextEditingController();
    var date = DateTime.now();
    var time = '';

    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Nuova riunione parrocchiale'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(
                    labelText: 'Titolo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: d,
                            initialDate: date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => date = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_month_rounded),
                        label: Text(_formatDate(date)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: d,
                            initialTime: const TimeOfDay(hour: 15, minute: 0),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              time =
                                  '${picked.hour.toString().padLeft(2, '0')}:'
                                  '${picked.minute.toString().padLeft(2, '0')}';
                            });
                          }
                        },
                        icon: const Icon(Icons.access_time_rounded),
                        label: Text(time.isEmpty ? 'Orario' : time),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: location,
                  decoration: const InputDecoration(
                    labelText: 'Luogo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note / ordine del giorno',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                await ParishChannelService.saveEvent(
                  ParishEvent(
                    id: '',
                    title: title.text.trim(),
                    date: date,
                    time: time.isEmpty ? null : time,
                    location: location.text.trim().isEmpty
                        ? null
                        : location.text.trim(),
                    notes: notes.text.trim(),
                    createdBy: AuthService.getCatechistId(),
                  ),
                );
                if (d.mounted) Navigator.pop(d);
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _newAvvisoDialog(BuildContext context) async {
    final title = TextEditingController();
    final text = TextEditingController();

    await showDialog(
      context: context,
      builder: (d) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Nuovo avviso parrocchiale'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(
                  labelText: 'Titolo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: text,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Testo',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty || text.text.trim().isEmpty) {
                return;
              }
              await ParishChannelService.saveParishAvviso(
                AvvisoTemplate(
                  id: '',
                  classUniqueCode: null,
                  title: title.text.trim(),
                  text: text.text.trim(),
                ),
              );
              if (d.mounted) Navigator.pop(d);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Rete Catechistica',
      floatingActionButton: _fab,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'Riunioni'),
                Tab(text: 'Avvisi parrocchia'),
                Tab(text: 'Titoli di classe'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _RiunioniTab(onSync: () => _syncParishChannel(context)),
                const _AvvisiTab(),
                const _TitoliTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 1 — RIUNIONI PARROCCHIALI
// ═══════════════════════════════════════════════════════════════════════════

class _RiunioniTab extends ConsumerWidget {
  final Future<void> Function()? onSync;
  const _RiunioniTab({this.onSync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(_parishEventsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onSync,
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Sincronizza rete'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: events.when(
            data: (list) => list.isEmpty
                ? const _EmptyTabState(
                    icon: Icons.event_rounded,
                    message: 'Nessuna riunione parrocchiale.\nCreane una con '
                        'il pulsante +.',
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _EventTile(event: list[index]),
                  ),
            loading: () => const Center(
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => Center(child: Text('Errore: $e')),
          ),
        ),
      ],
    );
  }
}

class _EventTile extends ConsumerWidget {
  final ParishEvent event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.event_rounded,
          color: theme.colorScheme.primary,
        ),
      ),
      title: Text(
        event.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          _formatDate(event.date),
          if (event.time != null && event.time!.isNotEmpty) event.time!,
          if (event.location != null && event.location!.isNotEmpty)
            '· ${event.location}',
        ].join(' '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        color: Colors.red.shade400,
        onPressed: () => _deleteEvent(context, ref, event),
      ),
    );
  }

  Future<void> _deleteEvent(
    BuildContext context,
    WidgetRef ref,
    ParishEvent event,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Elimina riunione'),
        content: Text('Eliminare "${event.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ParishChannelService.deleteEvent(event.id);
    }
  }
}

String _formatDate(DateTime date) {
  final d = date.toLocal();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$day/$m/${d.year}';
}

final _parishEventsProvider = StreamProvider<List<ParishEvent>>((ref) {
  return ParishChannelService.watchAllEvents();
});

// ═══════════════════════════════════════════════════════════════════════════
// TAB 2 — AVVISI PARROCCHIALI (globali, senza classe)
// ═══════════════════════════════════════════════════════════════════════════

class _AvvisiTab extends ConsumerWidget {
  const _AvvisiTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avvisi = ref.watch(_parishAvvisiProvider);
    return Column(
      children: [
        Expanded(
          child: avvisi.when(
            data: (list) => list.isEmpty
                ? const _EmptyTabState(
                    icon: Icons.campaign_rounded,
                    message: 'Nessun avviso parrocchiale.\nCreane uno con il '
                        'pulsante +.',
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _AvvisoTile(avviso: list[index]),
                  ),
            loading: () => const Center(
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => Center(child: Text('Errore: $e')),
          ),
        ),
      ],
    );
  }
}

class _AvvisoTile extends ConsumerWidget {
  final AvvisoTemplate avviso;
  const _AvvisoTile({required this.avviso});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        child: Icon(
          Icons.campaign_rounded,
          color: theme.colorScheme.secondary,
        ),
      ),
      title: Text(
        avviso.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        avviso.text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        color: Colors.red.shade400,
        onPressed: () => _deleteAvviso(context, ref),
      ),
    );
  }

  Future<void> _deleteAvviso(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Elimina avviso'),
        content: Text('Eliminare "${avviso.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ParishChannelService.deleteParishAvviso(avviso.id);
    }
  }
}

final _parishAvvisiProvider = StreamProvider<List<AvvisoTemplate>>((ref) {
  return LocalDatabase.watchList(
    LocalDatabase.avvisi(),
    (id, data) => AvvisoTemplate.fromMap(id, data),
  ).map((list) => list.where((a) => a.classUniqueCode == null).toList());
});

// ═══════════════════════════════════════════════════════════════════════════
// TAB 3 — TITOLI DI CLASSE (Class Channel)
// ═══════════════════════════════════════════════════════════════════════════

class _TitoliTab extends ConsumerWidget {
  const _TitoliTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(_allClassesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _scanTitleFlow(context),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scansiona QR titolo'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: classes.when(
            data: (list) => list.isEmpty
                ? const _EmptyTabState(
                    icon: Icons.class_rounded,
                    message: 'Nessuna classe presente su questo dispositivo.',
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _ClassTitleTile(classModel: list[index]),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Errore: $e')),
          ),
        ),
      ],
    );
  }
}

final _allClassesProvider = StreamProvider<List<SchoolClass>>((ref) {
  return LocalDatabase.watchList(
    LocalDatabase.classes(),
    (id, data) => SchoolClass.fromMap(id, data),
  );
});

class _ClassTitleTile extends ConsumerWidget {
  final SchoolClass classModel;
  const _ClassTitleTile({required this.classModel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key = ClassChannelService.getKeyByClassId(classModel.id);
    final hasTitle = key != null;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: hasTitle
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.orange.withValues(alpha: 0.15),
        child: Icon(
          hasTitle ? Icons.lock_open_rounded : Icons.lock_rounded,
          color: hasTitle ? Colors.green.shade700 : Colors.orange.shade700,
        ),
      ),
      title: Text(
        classModel.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        hasTitle
            ? 'Titolo di trattamento attivo'
            : 'Senza titolo (dati cifrati non leggibili)',
        style: TextStyle(
          color: hasTitle ? Colors.green.shade700 : Colors.orange.shade700,
          fontSize: 12,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Concedi titolo via QR',
            icon: const Icon(Icons.qr_code_rounded),
            color: theme.colorScheme.primary,
            onPressed: () => _grantTitleFlow(context),
          ),
        ],
      ),
    );
  }

  /// Genera un QR grant del titolo della classe (PIN protetto).
  Future<void> _grantTitleFlow(BuildContext context) async {
    await _grantTitleForClass(context, classModel);
  }
}

/// Genera un QR grant del titolo della classe [classModel] (PIN protetto).
/// Condiviso tra il pulsante della riga classe e il FAB "Concedi titolo".
Future<void> _grantTitleForClass(BuildContext context, SchoolClass classModel) async {
  final key = ClassChannelService.getKeyByClassId(classModel.id);
  if (key == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Nessuna chiave disponibile: solo il Responsabile o il Titolare '
          'della classe può concedere il titolo.',
        ),
      ),
    );
    return;
  }

  final pin = QRDataService.generatePin();
  final grantMap = ClassChannelService.buildGrantMap(
    key: key,
    grantorName: _localDisplayName(),
  );
  final chunks = ClassChannelService.createKeyGrantChunks(grantMap, pin);

  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (d) => _GrantQrDialog(
      className: classModel.name,
      pin: pin,
      chunks: chunks,
    ),
  );
}

String _localDisplayName() {
  try {
    final box = LocalDatabase.auth();
    final name = box.get('local_user_name');
    if (name != null && name.toString().trim().isNotEmpty) {
      return name.toString().trim();
    }
  } catch (_) {}
  return AuthService.getCatechistId();
}

/// Dialog con il PIN e i QR chunk del grant.
class _GrantQrDialog extends StatefulWidget {
  final String className;
  final String pin;
  final List<Map<String, dynamic>> chunks;
  const _GrantQrDialog({
    required this.className,
    required this.pin,
    required this.chunks,
  });

  @override
  State<_GrantQrDialog> createState() => _GrantQrDialogState();
}

class _GrantQrDialogState extends State<_GrantQrDialog> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final chunk = widget.chunks[_index];
    final qrData = jsonEncode(chunk);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Concedi titolo — ${widget.className}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Comunica questo PIN al catechista che riceverà il titolo:',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.pin,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            if (widget.chunks.length > 1) ...[
              const SizedBox(height: 8),
              Text(
                'QR ${_index + 1} di ${widget.chunks.length}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'L\'altro catechista deve inquadrare il QR con '
              '“Scansiona QR titolo”.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.chunks.length > 1) ...[
          TextButton(
            onPressed: _index > 0
                ? () => setState(() => _index--)
                : null,
            child: const Text('Precedente'),
          ),
          TextButton(
            onPressed: _index < widget.chunks.length - 1
                ? () => setState(() => _index++)
                : null,
            child: const Text('Successivo'),
          ),
        ],
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
      ],
    );
  }
}

/// Flusso di scansione del QR del titolo (con riassemblaggio dei chunk).
Future<void> _scanTitleFlow(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (_) => const _ScanTitleDialog(),
  );
}

class _ScanTitleDialog extends StatefulWidget {
  const _ScanTitleDialog();

  @override
  State<_ScanTitleDialog> createState() => _ScanTitleDialogState();
}

class _ScanTitleDialogState extends State<_ScanTitleDialog> {
  final List<QRChunk> _chunks = [];
  final Set<int> _seenIndexes = {};
  MobileScannerController? _controller;
  String? _status;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    try {
      final chunk = QRChunk.fromJson(raw);
      if (_seenIndexes.contains(chunk.chunkIndex)) return;
      setState(() {
        _seenIndexes.add(chunk.chunkIndex);
        _chunks.add(chunk);
        if (_chunks.length == chunk.totalChunks) {
          _status = 'QR completi, verifica in corso…';
        } else {
          _status = 'QR scansionati: ${_chunks.length}/${chunk.totalChunks}';
        }
      });
      if (_chunks.length == chunk.totalChunks) {
        _completeImport();
      }
    } catch (_) {
      // QR non riconosciuto (es. altro contenuto): ignora.
    }
  }

  Future<void> _completeImport() async {
    await _controller?.stop();
    String assembled;
    try {
      assembled = QRDataService.assembleChunks(_chunks);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore QR: $e')),
      );
      Navigator.pop(context);
      return;
    }

    if (!mounted) return;
    final pinController = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Inserisci il PIN'),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'PIN comunicato dal Responsabile/Titolare',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, pinController.text.trim()),
            child: const Text('Verifica'),
          ),
        ],
      ),
    );
    if (pin == null || pin.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      final key = ClassChannelService.importKeyGrant(assembled, pin);
      if (key == null) {
        throw Exception('Grant non valido o PIN errato.');
      }
      // Applica eventuali dati cifrati ricevuti in relay prima del titolo.
      await P2PSyncService().tryApplyRelayedCiphertext(
        key.classUniqueCode,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Titolo acquisito per la classe "${key.className}".',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Titolo non acquisito: $e')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Scansiona QR del titolo'),
      content: SizedBox(
        width: 320,
        height: 360,
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MobileScanner(
                  onDetect: _onDetect,
                  controller: _controller,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _status ?? 'Inquadra il QR mostrato dall\'altro dispositivo.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
      ],
    );
  }
}

/// Stato vuoto con icona per i tab della rete parrocchiale.
class _EmptyTabState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyTabState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
