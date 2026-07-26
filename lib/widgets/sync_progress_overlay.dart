import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/nearby_sync_provider.dart';
import '../features/sync/p2p/p2p_sync_service.dart';

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

  bool _showingSessionPermission = false;

  void _onStateChanged(P2PSyncState state) {
    if (!mounted) return;
    if (state.awaitingConfirmation && !_showingConfirmation) {
      _showingConfirmation = true;
      _showSyncConfirmation(state);
    }
    if (state.awaitingSessionPermission && !_showingSessionPermission) {
      _showingSessionPermission = true;
      _showSessionPermission(state);
    }
    if (state.largeSyncInProgress &&
        state.totalRecordsToExchange > 0 &&
        !_showingSheet) {
      _showingSheet = true;
      _showProgressSheet(state);
    }
  }

  void _showSyncConfirmation(P2PSyncState state) {
    final service = ref.read(nearbySyncServiceProvider);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Richiesta di sincronizzazione'),
          content: Text(
            '${state.pendingConfirmationDeviceName ?? "Dispositivo sconosciuto"} '
            'vuole sincronizzare i dati.\n\n'
            'Vuoi autorizzare la sincronizzazione?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _showingConfirmation = false;
                service.rejectSync();
              },
              child: const Text('Rifiuta',
                  style: TextStyle(color: Colors.red)),
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

  void _showSessionPermission(P2PSyncState state) {
    final service = ref.read(nearbySyncServiceProvider);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Permesso sincronizzazione'),
          content: Text(
            '${state.pendingSessionDeviceName ?? "Un dispositivo"} è nelle vicinanze.\n\n'
            'Autorizzi la sincronizzazione automatica per questa sessione?\n\n'
            'Il permesso sarà valido fino alla chiusura dell\'app.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _showingSessionPermission = false;
                service.denySessionPermission();
              },
              child: const Text('Rifiuta',
                  style: TextStyle(color: Colors.red)),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _showingSessionPermission = false;
                service.grantSessionPermission();
                service.startBackgroundSync();
              },
              child: const Text('Autorizza'),
            ),
          ],
        );
      },
    ).then((_) => _showingSessionPermission = false);
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
        if (mounted) {
          Navigator.of(context).pop();
          widget.onDismiss();
        }
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
          Icon(Icons.sync, size: 40, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            'Sincronizzazione in corso',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
