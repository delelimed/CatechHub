// ══════════════════════════════════════════════════════════════════════════════
// responsabile_admin_page.dart — CatechHub (hub amministrativo del Responsabile)
//
// Raccoglie le funzionalità amministrative del Responsabile Catechistico in
// tab: Gestione classi, Logistica (aule/orari), Iscrizioni/Passaggio anno,
// Allarmi assenze. Ogni sezione è autogated dal ruolo.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/user_role.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'aula_management_page.dart';
import 'allarme_assenze_page.dart';
import 'classi_management_page.dart';
import 'iscrizioni_page.dart';

/// Pagina hub amministrativo del Responsabile.
class ResponsabileAdminPage extends ConsumerWidget {
  const ResponsabileAdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!RolePermissions.currentCan(RolePermission.manageClasses)) {
      return AppScaffold(
        title: 'Gestione parrocchia',
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

    return AppScaffold(
      title: 'Gestione parrocchia',
      child: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            const Material(
              color: Colors.transparent,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Classi'),
                  Tab(text: 'Iscrizioni'),
                  Tab(text: 'Logistica'),
                  Tab(text: 'Allarmi assenze'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Expanded(
              child: TabBarView(
                children: [
                  ClassiManagementPage(),
                  IscrizioniPage(),
                  AulaManagementSection(),
                  AllarmeAssenzePage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}