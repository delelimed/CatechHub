import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/sync/p2p/p2p_sync_service.dart';
import '../services/bluetooth_permission_service.dart';

final nearbySyncServiceProvider = Provider<P2PSyncService>((ref) {
  return P2PSyncService();
});

final nearbySyncStateProvider = StreamProvider<P2PSyncState>((ref) {
  final service = ref.watch(nearbySyncServiceProvider);
  return service.onStateChanged;
});

final syncLogsProvider = Provider<List<SyncLogEntry>>((ref) {
  final service = ref.watch(nearbySyncServiceProvider);
  return service.syncLogs;
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