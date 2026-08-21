import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import '../../../core/providers/nearby_sync_provider.dart';
import '../../../core/storage/local_database.dart';
import '../p2p/p2p_sync_service.dart';

class SyncProgressOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const SyncProgressOverlay({super.key, required this.child});

  @override
  ConsumerState<SyncProgressOverlay> createState() =>
      _SyncProgressOverlayState();
}

class _SyncProgressOverlayState extends ConsumerState<SyncProgressOverlay> {
  StreamSubscription<P2PSyncState>? _sub;
  bool _showingSheet = false;
  bool _showingConfirmation = false;

  @override
  void initState() {
    super.initState();
    final service = ref.read(nearbySyncServiceProvider);
    _sub = service.onStateChanged.listen(_onStateChanged);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onStateChanged(P2PSyncState state) {
    if (!mounted) return;
    if (state.awaitingConfirmation && !_showingConfirmation) {
      _showingConfirmation = true;
      _showSyncConfirmation(state);
    }
    if (state.largeSyncInProgress &&
        state.totalRecordsToExchange > 0 &&
        !_showingSheet) {
      _showingSheet = true;
      _showProgressSheet(state);
    }
    if (state.status == P2PSyncStatus.completed && !_showingConfirmation) {
      _checkConflicts();
    }
    if (state.status == P2PSyncStatus.syncing) {
      _conflictsChecked = false;
    }
  }

  bool _conflictsChecked = false;

  void _checkConflicts() {
    if (_conflictsChecked) return;
    _conflictsChecked = true;
    try {
      final box = LocalDatabase.syncConflicts();
      final unresolved = box.values.where((v) {
        final data = Map<String, dynamic>.from(v);
        return data['resolved'] != true;
      }).length;
      if (unresolved > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showConflictNotification(unresolved);
        });
      }
    } catch (_) {}
  }

  String _getCurrentClassName() {
    try {
      final box = Hive.box<Map>('classes_box');
      const uid = 'local_catechist_id';
      for (final key in box.keys) {
        final data = Map<String, dynamic>.from(box.get(key) as Map);
        final ids = (data['catechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        if (ids.contains(uid)) {
          return data['name']?.toString() ?? 'Classe';
        }
      }
    } catch (_) {}
    return 'Classe corrente';
  }

  void _showSyncConfirmation(P2PSyncState state) {
    final service = ref.read(nearbySyncServiceProvider);
    final className = _getCurrentClassName();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Richiesta di sincronizzazione'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${state.pendingConfirmationDeviceName ?? "Dispositivo sconosciuto"} '
                'vuole sincronizzare i dati.\n\n'
                'Vuoi autorizzare la sincronizzazione?\n\n'
                'Nota: anche l\'altro catechista deve autorizzare la sincronizzazione '
                'prima che lo scambio abbia inizio.',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF174A7E).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.class_,
                      size: 16,
                      color: const Color(0xFF174A7E),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Classe: $className',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF174A7E),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'La sincronizzazione Bluetooth avviene solo tra dispositivi della stessa classe.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _showingConfirmation = false;
                service.rejectSync();
              },
              child: const Text('Rifiuta', style: TextStyle(color: Colors.red)),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _showingConfirmation = false;
                service.confirmSync();
              },
              child: const Text('Autorizza sync'),
            ),
          ],
        );
      },
    ).then((_) => _showingConfirmation = false);
  }

  void _showConflictNotification(int count) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber, size: 48, color: Colors.orange[700]),
        title: const Text('Conflitti di sincronizzazione'),
        content: Text(
          '$count campo${count == 1 ? ' è' : ' sono'} in conflitto.\n\n'
          'Scegli per ogni campo se mantenere la versione locale o '
          'quella ricevuta dall\'altro dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Più tardi'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.push('/settings/sync-conflicts');
            },
            child: const Text('Risolvi ora'),
          ),
        ],
      ),
    );
  }

  void _showProgressSheet(P2PSyncState state) {
    final total = state.totalRecordsToExchange;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _SyncProgressContent(
        totalRecords: total,
        onDismiss: () => _showingSheet = false,
      ),
    ).then((_) => _showingSheet = false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SyncProgressContent extends ConsumerStatefulWidget {
  final int totalRecords;
  final VoidCallback onDismiss;
  const _SyncProgressContent({
    required this.totalRecords,
    required this.onDismiss,
  });

  @override
  _SyncProgressContentState createState() => _SyncProgressContentState();
}

class _SyncProgressContentState extends ConsumerState<_SyncProgressContent> {
  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(nearbySyncStateProvider);
    final state = asyncState.asData?.value;
    if (state == null) return const SizedBox.shrink();

    final total = widget.totalRecords;
    final sent = state.sentRecordsCount;
    final received = state.receivedRecordsCount;
    final processed = sent + received;
    final progress = total > 0 ? processed / total : 0.0;
    final percent = (progress * 100).round();
    final sendPercent = total > 0 ? (sent / total * 100).round() : 0;
    final receivePercent = total > 0 ? (received / total * 100).round() : 0;

    if (state.status == P2PSyncStatus.completed ||
        state.status == P2PSyncStatus.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          Navigator.of(context).pop();
        } catch (_) {
          // Route già rimossa
        }
        widget.onDismiss();
      });
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Icon(
            Icons.sync,
            size: 40,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Sincronizzazione in corso',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Scambio di $total record tra i dispositivi',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.grey[200],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$percent% completato',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: percent == 100 ? Colors.green[700] : null,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.arrow_upward, size: 16, color: Colors.green[600]),
              const SizedBox(width: 4),
              Text(
                'Inviati: $sent record ($sendPercent%)',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.arrow_downward, size: 16, color: Colors.blue[600]),
              const SizedBox(width: 4),
              Text(
                'Ricevuti: $received record ($receivePercent%)',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _getStatusMessage(state),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  String _getStatusMessage(P2PSyncState state) {
    switch (state.status) {
      case P2PSyncStatus.syncing:
        return 'Sincronizzazione in corso…';
      case P2PSyncStatus.sessionEstablished:
        return 'Sessione stabilita, attesa dati…';
      case P2PSyncStatus.handshakeSent:
      case P2PSyncStatus.handshakeReceived:
        return 'Scambio chiavi in corso…';
      default:
        return 'Elaborazione…';
    }
  }
}
