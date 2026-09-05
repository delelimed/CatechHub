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

  // M3: idle-lock anche in foreground. Se l'app resta aperta e inattiva
  // (nessun tocco/scroll) per [idleLockDuration], la sessione viene bloccata.
  // Un telefono incustodito sul tavolo con l'app aperta non deve lasciare i
  // dati dei minori visibili a chi passa.
  static const _lockDuration = Duration(seconds: 120);
  static const _idleLockDuration = Duration(minutes: 5);
  Timer? _idleTimer;
  var _isForeground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
    _idleTimer?.cancel();
    super.dispose();
  }

  /// Riavvia il timer di inattività in foreground a ogni attività dell'utente.
  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (!_isForeground || !mounted) return;
    final privacy = ref.read(privacySettingsProvider);
    if (!privacy.lockOnBackground) return;
    _idleTimer = Timer(_idleLockDuration, () {
      if (!mounted || !_isForeground) return;
      // Blocca solo se la sessione è ancora aperta (evita lock ripetuti).
      final authState = ref.read(authStateProvider);
      if (authState.value != null) {
        ref.read(authStateProvider.notifier).lock();
      }
    });
  }

  void _onUserPointer() => _resetIdleTimer();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _isForeground = false;
      _idleTimer?.cancel();
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
      _isForeground = true;

      if (_hasBeenPaused) {
        _hasBeenPaused = false;

        final elapsed = _backgroundTimestamp != null
            ? DateTime.now().difference(_backgroundTimestamp!)
            : _lockDuration;

        _backgroundTimestamp = null;

        if (elapsed >= _lockDuration) {
          ref.read(authStateProvider.notifier).lock();
        }
      }

      _resetIdleTimer();

      final privacy = ref.read(privacySettingsProvider);
      if (privacy.checkUpdatesOnStart) {
        UpdateService.checkForUpdates();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listener passivo (non interferisce con la gesture arena) che rileva
    // qualsiasi tocco sull'app per riavviare il timer di inattività.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onUserPointer(),
      onPointerMove: (_) => _onUserPointer(),
      onPointerUp: (_) => _onUserPointer(),
      child: widget.child,
    );
  }
}
