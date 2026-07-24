import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter/widgets.dart';

import '../../features/sync/p2p/p2p_sync_service.dart';

final nearbySyncServiceProvider = Provider<P2PSyncService>((ref) {
  return P2PSyncService();
});

final nearbySyncStateProvider = StreamProvider<P2PSyncState>((ref) {
  final service = ref.watch(nearbySyncServiceProvider);
  return service.onStateChanged;
});

class NearbySyncDaemonController extends StateNotifier<bool> {
  final P2PSyncService _service;
  bool _isAppInForeground = false;

  NearbySyncDaemonController(this._service) : super(false);

  void setAppForeground(bool isForeground) {
    if (_isAppInForeground == isForeground) return;
    _isAppInForeground = isForeground;
    if (isForeground) {
      _service.startBackgroundSync();
      state = true;
    } else {
      _service.stopBackgroundSync();
      state = false;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}