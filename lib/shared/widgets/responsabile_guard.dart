// ══════════════════════════════════════════════════════════════════════════════
// responsabile_guard.dart — CatechHub (guard di accesso per la gestione
// parrocchiale)
//
// Difesa in profondità a livello di UI: ogni sezione riservata al Responsabile
// Catechistico viene avvolta da questo widget. Se il ruolo corrente non è
// Responsabile, il contenuto viene sostituito da una schermata di blocco.
// La sicurezza reale è garantita dal redirect del router (router.dart), qui
// il guard evita la renderizzazione di contenuti/funzioni non autorizzate.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/user_role.dart';
import 'app_scaffold.dart';

/// Avvolge una sezione riservata al Responsabile Catechistico.
class ResponsabileGuard extends StatelessWidget {
  /// Titolo della sezione (usato nella schermata di blocco).
  final String title;

  /// Contenuto amministrativo mostrato solo al Responsabile.
  final Widget child;

  const ResponsabileGuard({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    if (RolePermissions.currentCan(RolePermission.manageClasses)) {
      return child;
    }
    return AppScaffold(
      title: title,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 52, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(
                'Questa sezione è riservata al Responsabile Catechistico.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Torna alla home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
