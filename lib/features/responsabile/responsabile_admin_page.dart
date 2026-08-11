// ══════════════════════════════════════════════════════════════════════════════
// responsabile_admin_page.dart - CatechHub (hub amministrativo del Responsabile)
//
// Hub a schede con tutte le funzioni amministrative del Responsabile
// Catechistico. Ogni voce apre una schermata autonoma (niente tab affollati):
// la navigazione e semplice sia su tablet (10-12") sia su smartphone (5-8").
// La griglia si adatta alla larghezza dello schermo (1, 2 o 3 colonne).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/user_role.dart';
import '../../shared/widgets/app_scaffold.dart';

/// Hub amministrativo del Responsabile.
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

    final items = [
      _AdminItem(
        icon: Icons.groups_rounded,
        title: 'Classi',
        subtitle: 'Crea classi e assegna i catechisti',
        color: const Color(0xFF174A7E),
        route: '/parrocchia/classi',
      ),
      _AdminItem(
        icon: Icons.person_add_alt_1_rounded,
        title: 'Catechisti',
        subtitle: 'Rubrica, telefono, classi e dispositivi',
        color: const Color(0xFF2E7D32),
        route: '/parrocchia/catechisti',
      ),
      _AdminItem(
        icon: Icons.assignment_ind_rounded,
        title: 'Iscrizioni',
        subtitle: 'Censimento ragazzi e passaggio anno',
        color: const Color(0xFFB34700),
        route: '/parrocchia/iscrizioni',
      ),
      _AdminItem(
        icon: Icons.meeting_room_rounded,
        title: 'Logistica',
        subtitle: 'Aule e orari settimanali',
        color: const Color(0xFF6A4FA3),
        route: '/parrocchia/logistica',
      ),
      _AdminItem(
        icon: Icons.notification_important_rounded,
        title: 'Allarme assenze',
        subtitle: 'Ragazzi con assenze prolungate',
        color: const Color(0xFFC62828),
        route: '/parrocchia/allarmi',
      ),
      _AdminItem(
        icon: Icons.network_check_rounded,
        title: 'Rete parrocchiale',
        subtitle: 'Riunioni, avvisi e titoli',
        color: const Color(0xFF00838F),
        route: '/parrocchia/rete',
      ),
      _AdminItem(
        icon: Icons.task_alt_rounded,
        title: 'Consensi',
        subtitle: 'Schede iscrizione firmate',
        color: const Color(0xFFAD7F00),
        route: '/parrocchia/consensi',
      ),
      _AdminItem(
        icon: Icons.gavel_rounded,
        title: 'Registro trattamenti',
        subtitle: 'Log GDPR (Art. 30)',
        color: const Color(0xFF7B1FA2),
        route: '/parrocchia/audit',
      ),
      _AdminItem(
        icon: Icons.history_rounded,
        title: 'Archivio storico',
        subtitle: 'Progresso e chiusura anno',
        color: const Color(0xFF455A64),
        route: '/parrocchia/archivio',
      ),
      _AdminItem(
        icon: Icons.upload_file_rounded,
        title: 'Importa ragazzi',
        subtitle: 'Da Excel o CSV',
        color: const Color(0xFF00695C),
        route: '/parrocchia/import-ragazzi',
      ),
    ];

    return AppScaffold(
      title: 'Gestione parrocchia',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth >= 900
              ? 3
              : constraints.maxWidth >= 560
                  ? 2
                  : 1;
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisExtent: 132,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => _AdminCard(item: items[index]),
          );
        },
      ),
    );
  }
}

class _AdminItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String route;

  const _AdminItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.route,
  });
}

class _AdminCard extends StatelessWidget {
  final _AdminItem item;

  const _AdminCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push(item.route),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark
              ? Theme.of(context).colorScheme.surfaceContainer
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark
                ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)
                : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: isDark ? 0.25 : 0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(item.icon, color: item.color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}
