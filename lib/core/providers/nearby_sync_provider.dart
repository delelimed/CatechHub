import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/sync/widgets/sync_progress_overlay.dart';

import '../../features/sync/p2p/p2p_security_service.dart';
import '../../features/sync/p2p/p2p_sync_service.dart';
import '../services/bluetooth_permission_service.dart';

final nearbySyncServiceProvider = Provider<P2PSyncService>((ref) {
  return P2PSyncService();
});

final nearbySyncStateProvider = StreamProvider<P2PSyncState>((ref) {
  final service = ref.watch(nearbySyncServiceProvider);
  return service.onStateChanged;
});

final syncLogsProvider = StreamProvider<List<SyncLogEntry>>((ref) async* {
  final service = ref.watch(nearbySyncServiceProvider);
  yield service.syncLogs;
  await for (final _ in service.onLogChanged) {
    yield service.syncLogs;
  }
});

class NearbySyncDaemonController extends StateNotifier<bool> {
  final P2PSyncService _service;
  bool _isAppInForeground = false;
  bool _initialized = false;
  static const _prefsKey = 'sync_permanently_enabled';

  NearbySyncDaemonController(this._service) : super(false);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefsKey) ?? false;
    if (enabled) {
      state = true;
      return;
    }
    // Auto-enable se il dispositivo risulta già associato (persistenza Hive):
    // soddisfa il requisito "se associo un dispositivo (oppure configuro il
    // dispositivo come associato) la sincronizzazione automatica deve essere
    // attiva di default" anche dopo reinstallazione del flag o primo avvio
    // post-associazione senza intervento utente.
    try {
      final hasAssoc = await P2PSecurityService().hasValidAssociation();
      if (hasAssoc) {
        await prefs.setBool(_prefsKey, true);
        state = true;
      }
    } catch (_) {}
  }

  /// Abilita in modo persistente la sincronizzazione automatica senza
  /// richiedere interazione utente. Usato dopo una nuova associazione riuscita.
  Future<void> enableAutoSync() async {
    if (state) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
    state = true;
    final permResult =
        await BluetoothPermissionService.checkAndRequestPermissions();
    if (permResult.allGranted) {
      _service.startBackgroundSync();
    }
  }

  void setAppForeground(bool isForeground) {
    if (_isAppInForeground == isForeground) return;
    _isAppInForeground = isForeground;
    if (isForeground && state) {
      _service.startBackgroundSync();
    } else if (!isForeground) {
      _service.stopBackgroundSync();
    }
  }

  Future<void> setSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
    state = enabled;
    if (enabled) {
      final permResult =
          await BluetoothPermissionService.checkAndRequestPermissions();
      if (permResult.allGranted) {
        _service.startBackgroundSync();
      }
    } else {
      _service.stopBackgroundSync();
    }
  }

  Future<void> triggerManualSync() async {
    await _service.triggerManualSync();
  }

  @override
  void dispose() {
    if (_isAppInForeground) {
      _service.stopBackgroundSync();
    }
    super.dispose();
  }
}

final nearbySyncDaemonProvider =
    StateNotifierProvider<NearbySyncDaemonController, bool>((ref) {
      final service = ref.watch(nearbySyncServiceProvider);
      return NearbySyncDaemonController(service);
    });

class NearbySyncLifecycleManager extends ConsumerStatefulWidget {
  final Widget child;

  const NearbySyncLifecycleManager({super.key, required this.child});

  @override
  ConsumerState<NearbySyncLifecycleManager> createState() =>
      _NearbySyncLifecycleManagerState();
}

class _NearbySyncLifecycleManagerState
    extends ConsumerState<NearbySyncLifecycleManager>
    with WidgetsBindingObserver {
  bool _daemonStarted = false;
  bool _expirationWarningShown = false;
  StreamSubscription<P2PSyncState>? _stateSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_daemonStarted) {
        _daemonStarted = true;
        final daemonController = ref.read(nearbySyncDaemonProvider.notifier);
        daemonController.init().then((_) {
          daemonController.setAppForeground(true);
        });
      }
    });
    final service = ref.read(nearbySyncServiceProvider);
    _stateSub = service.onStateChanged.listen(_onSyncStateChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateSub?.cancel();
    super.dispose();
  }

  void _onSyncStateChanged(P2PSyncState state) {
    if (!mounted) return;

    // Se il servizio ha avviato la modalità continua (es. dopo associazione)
    // ma il flag persistente è ancora spento, allineiamo il daemon: la sync
    // automatica deve essere attiva di default appena si associa un dispositivo.
    if (state.isBackgroundSyncActive && !ref.read(nearbySyncDaemonProvider)) {
      // fire-and-forget: persiste e aggiorna lo switch senza bloccare UI
      ref.read(nearbySyncDaemonProvider.notifier).enableAutoSync();
    }

    if (state.expirationWarning != null && !_expirationWarningShown) {
      _expirationWarningShown = true;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
              const SizedBox(width: 8),
              const Text('Connessione in scadenza'),
            ],
          ),
          content: Text(
            '${state.expirationWarning}.\n\n'
            'Le connessioni hanno validità 30 giorni. '
            'Per continuare a sincronizzare, associa nuovamente '
            'i dispositivi prima della scadenza.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Ho capito'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final daemonController = ref.read(nearbySyncDaemonProvider.notifier);
    switch (state) {
      case AppLifecycleState.resumed:
        _expirationWarningShown = false;
        daemonController.init().then((_) {
          daemonController.setAppForeground(true);
        });
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        daemonController.setAppForeground(false);
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) =>
      SyncProgressOverlay(child: widget.child);
}
