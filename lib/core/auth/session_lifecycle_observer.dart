// ══════════════════════════════════════════════════════════════════════════════
// session_lifecycle_observer.dart — CatechHub (blocco sessione in background)
//
// Widget che osserva il ciclo di vita dell'app tramite WidgetsBindingObserver
// e blocca la sessione dopo 120 secondi di inattività in background.
//
// CONTESTO PROGETTO:
//   Requisito di sicurezza: se l'utente mette l'app in background e non
//   torna entro 120s, la sessione viene automaticamente bloccata e alla
//   riapertura serve reinserire il PIN o la biometria. Questo previene
//   accessi non autorizzati se il telefono viene lasciato incustodito.
//
//   Al resume, se è stata rilevata una pausa, controlla anche eventuali
//   aggiornamenti disponibili (se abilitato nelle impostazioni privacy).
//
// COMPORTAMENTO:
//   paused/detached → avvia timer 120s → lock()
//   resumed → cancella timer + check updates
//   Se lockOnBackground è false, nessun timer viene avviato.
//   Se checkUpdatesOnStart è false, nessun update check al resume.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../security/privacy_settings.dart';
import '../services/update_service.dart';
import 'auth_provider.dart';

/// Blocca la sessione dopo 120 secondi in background, se richiesto
/// dalle privacy settings. Avvolge l'intera app in main.dart.
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
  DateTime? _backgroundTimestamp;

  static const _lockDuration = Duration(seconds: 120);

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
      _backgroundTimestamp = DateTime.now();
      _lockTimer?.cancel();

      final privacy = ref.read(privacySettingsProvider);
      if (privacy.lockOnBackground) {
        _lockTimer = Timer(_lockDuration, () {
          if (!mounted) return;
          ref.read(authStateProvider.notifier).lock();
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _lockTimer?.cancel();

      if (_hasBeenPaused) {
        _hasBeenPaused = false;

        final elapsed = _backgroundTimestamp != null
            ? DateTime.now().difference(_backgroundTimestamp!)
            : _lockDuration;

        _backgroundTimestamp = null;

        if (elapsed >= _lockDuration) {
          ref.read(authStateProvider.notifier).lock();
          return;
        }
      }

      final privacy = ref.read(privacySettingsProvider);
      if (privacy.checkUpdatesOnStart) {
        UpdateService.checkForUpdates();
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
