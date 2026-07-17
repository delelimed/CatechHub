import 'dart:async';
import 'package:flutter/foundation.dart';

// ══════════════════════════════════════════════════════════════════════════════
// go_router_refresh_stream.dart — CatechHub
//
// Utility per collegare uno Stream Dart a GoRouter tramite il meccanismo
// di ChangeNotifier, abilitando il re-render automatico del router quando
// lo stream emette nuovi valori.
//
// UTILIZZO NEL PROGETTO:
//   Questa classe viene utilizzata (o può essere utilizzata) per notificare
//   a GoRouter i cambiamenti di stato che richiedono un re-eval del redirect,
//   come i cambiamenti di autenticazione o di sessione.
//
//   Nel caso specifico di CatechHub, il redirect di autenticazione è gestito
//   da _AuthStateNotifier (in router.dart) che ascolta authStateProvider
//   tramite Riverpod. Questa classe è un'utility generica disponibile
//   per futuri use case dove uno stream Dart debba triggerare un re-render
//   del router.
//
// MECCANISMO:
//   1. Un costruttore accetta uno Stream<dynamic>
//   2. Il listener sullo stream chiama notifyListeners() ad ogni evento
//   3. GoRouter, configurato con refreshListenable: questo ChangeNotifier,
//      viene notificato e ri-evalua il redirect
//   4. Al dispose, la subscription viene cancellata per evitare memory leak
//
// NOTE DI IMPLEMENTAZIONE:
//   - Estende ChangeNotifier (non StreamSubscription) perché GoRouter
//     richiede un Listenable per refreshListenable
//   - La subscription è late final perché viene inizializzata nel costruttore
//   - Il cancel della subscription nel dispose previene memory leak
// ══════════════════════════════════════════════════════════════════════════════

class GoRouterRefreshStream extends ChangeNotifier {
  /// Costruisce un GoRouterRefreshStream che ascolta lo stream fornito.
  ///
  /// Ad ogni evento emesso dallo stream, viene notificato GoRouter
  /// per un re-render del widget tree e un re-eval del redirect.
  ///
  /// @param stream Lo Stream Dart da ascoltare per i cambiamenti di stato
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen(
      (_) {
        notifyListeners();
      },
      onError: (_) {
        notifyListeners();
      },
      cancelOnError: false,
    );
  }

  /// Subscription allo stream, cancellata al dispose per evitare memory leak.
  late final StreamSubscription<dynamic> _subscription;

  /// Cancella la subscription e libera le risorse.
  /// Chiamato automaticamente quando GoRouter viene distrutto.
  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
