// ══════════════════════════════════════════════════════════════════════════════
// nearby_sync_provider.dart — CatechHub (provider NearbySyncService)
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter/widgets.dart';

import '../../services/nearby_sync_service.dart';

// Provider per il servizio NearbySync (singleton)
final nearbySyncServiceProvider = Provider<NearbySyncService>((ref) {
  return NearbySyncService();
});

// Provider per lo stato del sync (stream)
final nearbySyncStateProvider = StreamProvider<NearbySyncState>((ref) {
  final service = ref.watch(nearbySyncServiceProvider);
  return service.onStateChanged;
});

// Provider per controllare il daemon (avvia/ferma in base al lifecycle dell'app)
class NearbySyncDaemonController extends StateNotifier<bool> {
  final NearbySyncService _service;
  bool _isAppInForeground = false;

  NearbySyncDaemonController(this._service) : super(false);

  void setAppForeground(bool isForeground) {
    _isAppInForeground = isForeground;
    if (isForeground) {
      _service.startDaemon();
      state = true;
    } else {
      _service.stopDaemon();
      state = false;
    }
  }

  Future<void> triggerManualSync() async {
    await _service.triggerManualSync();
  }

  @override
  void dispose() {
    if (_isAppInForeground) {
      _service.stopDaemon();
    }
    super.dispose();
  }
}

final nearbySyncDaemonProvider =
    StateNotifierProvider<NearbySyncDaemonController, bool>((ref) {
  final service = ref.watch(nearbySyncServiceProvider);
  return NearbySyncDaemonController(service);
});

// Widget per gestire il lifecycle del daemon (da inserire nell'albero widget principale)
class NearbySyncLifecycleManager extends ConsumerStatefulWidget {
  final Widget child;

  const NearbySyncLifecycleManager({super.key, required this.child});

  @override
  ConsumerState<NearbySyncLifecycleManager> createState() =>
      _NearbySyncLifecycleManagerState();
}

class _NearbySyncLifecycleManagerState
    extends ConsumerState<NearbySyncLifecycleManager> with WidgetsBindingObserver {
  bool _daemonStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Avvia il daemon immediatamente se l'app è già in foreground
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_daemonStarted) {
        _daemonStarted = true;
        final daemonController = ref.read(nearbySyncDaemonProvider.notifier);
        daemonController.setAppForeground(true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final daemonController = ref.read(nearbySyncDaemonProvider.notifier);
    switch (state) {
      case AppLifecycleState.resumed:
        daemonController.setAppForeground(true);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        daemonController.setAppForeground(false);
        break;
      case AppLifecycleState.inactive:
        // Non fermiamo il daemon qui, solo su paused/detached
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}