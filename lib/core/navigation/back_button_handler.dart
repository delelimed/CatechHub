// ══════════════════════════════════════════════════════════════════════════════
// back_button_handler.dart — CatechHub (gestione tasto indietro Android)
//
// Widget che intercetta il tasto indietro Android e implementa:
//   - Navigazione alla dashboard se non si è sulla home
//   - Doppio tap "Premi ancora per uscire" per chiudere l'app
//
// CONTESTO PROGETTO:
//   Poiché CatechHub usa GoRouter con navigazione dichiarativa (non uno
//   stack di route), il comportamento predefinito di PopScope (pop della
//   route) non è desiderato. Al suo posto, il back button:
//   1. Se non siamo su '/' → naviga a '/' (dashboard)
//   2. Se siamo su '/' → mostra snackbar "Premi ancora per uscire"
//   3. Secondo tap entro 2s → SystemNavigator.pop() (esce dall'app)
//
//   Questo evita che l'utente si "impalli" in route annidiate senza un
//   modo chiaro per tornare alla home, e previene chiusure accidentali.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Widget che gestisce il comportamento del tasto indietro Android.
/// - Prima pressione fuori dalla dashboard: naviga alla dashboard
/// - Prima pressione sulla dashboard: mostra messaggio "Premi ancora per uscire"
/// - Seconda pressione entro 2 secondi sulla dashboard: chiude l'app
class BackButtonHandler extends StatefulWidget {
  final Widget child;
  final GoRouter router;

  const BackButtonHandler({
    super.key,
    required this.child,
    required this.router,
  });

  @override
  State<BackButtonHandler> createState() => _BackButtonHandlerState();
}

class _BackButtonHandlerState extends State<BackButtonHandler> {
  DateTime? _lastBackPressed;
  static const int _backPressInterval = 2; // secondi

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop(context),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        
        _handleBackPressed(context);
      },
      child: widget.child,
    );
  }

  /// Non permettere il pop automatico in nessun caso.
  /// Gestiamo tutto manualmente in _handleBackPressed.
  bool _canPop(BuildContext context) {
    return false;
  }

  void _handleBackPressed(BuildContext context) {
    // Prova prima a fare pop (funziona per route arrivate via context.push)
    if (widget.router.canPop()) {
      widget.router.pop();
      return;
    }

    final location = widget.router.routeInformationProvider.value.uri.path;

    // Se non siamo sulla dashboard, torna alla dashboard
    if (location != '/') {
      widget.router.go('/');
      return;
    }

    // Sulla dashboard: doppio tap per uscire (intervallo 2 secondi)
    final now = DateTime.now();

    if (_lastBackPressed == null ||
        now.difference(_lastBackPressed!) > const Duration(seconds: _backPressInterval)) {
      _lastBackPressed = now;
      _showExitSnackBar(context);
    } else {
      _exitApp();
    }
  }

  void _showExitSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Premi ancora per uscire'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 100,
          left: 20,
          right: 20,
        ),
      ),
    );
  }

  void _exitApp() {
    SystemNavigator.pop();
  }
}
