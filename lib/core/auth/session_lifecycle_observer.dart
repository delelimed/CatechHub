import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../security/privacy_settings.dart';
import '../services/update_service.dart';
import 'auth_provider.dart';

/// Blocca la sessione dopo 120 secondi in background, se richiesto dalle privacy settings.
class SessionLifecycleObserver extends ConsumerStatefulWidget {
  const SessionLifecycleObserver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SessionLifecycleObserver> createState() =>
      _SessionLifecycleObserverState();
}

class _SessionLifecycleObserverState
    extends ConsumerState<SessionLifecycleObserver>
    with WidgetsBindingObserver {
  Timer? _lockTimer;
  var _hasBeenPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _hasBeenPaused = true;
      _lockTimer?.cancel();

      final privacy = ref.read(privacySettingsProvider);
      if (privacy.lockOnBackground) {
        _lockTimer = Timer(const Duration(seconds: 120), () {
          ref.read(authStateProvider.notifier).lock();
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _lockTimer?.cancel();

      if (_hasBeenPaused) {
        final privacy = ref.read(privacySettingsProvider);
        if (privacy.checkUpdatesOnStart) {
          UpdateService.checkForUpdates();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
