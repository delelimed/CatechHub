// ══════════════════════════════════════════════════════════════════════════════
// responsabile_dashboard_page.dart — CatechHub (dashboard parrocchiale)
//
// Dashboard principale del Responsabile Catechistico. Mostra il quadro
// sintetico della parrocchia (classi attive, ragazzi iscritti, catechisti)
// e le funzioni rapide di gestione.
//
// Accede solo se la modalità Responsabile è attiva (ParishConfig).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/parish_config.dart';
import '../../shared/models/user_role.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'responsabile_providers.dart';

/// Dashboard parrocchiale del Responsabile Catechistico.
class ResponsabileDashboardPage extends ConsumerWidget {
  const ResponsabileDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configRepo = ref.watch(parishConfigRepositoryProvider);
    final config = configRepo.getConfig();

    if (!UserRole.isResponsabile || !config.isResponsabileModeActive) {
      return const _AccessDenied();
    }

    final classesAsync = ref.watch(parrocchiaClassesProvider);

    return AppScaffold(
      title: 'Parrocchia',
      child: classesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore caricamento classi: $e')),
        data: (classes) {
          final active = classes.where((c) => !c.archived).toList();
          final nClassi = active.length;
          final nRagazzi = active.fold<int>(
            0,
            (sum, c) => sum + c.studentIds.length,
          );
          final nCatechisti = active.fold<int>(
            0,
            (sum, c) => sum + c.catechistIds.length,
          );

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _Header(config: config),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.groups_rounded,
                          label: 'Classi attive',
                          value: nClassi,
                          color: const Color(0xFF174A7E),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.person_rounded,
                          label: 'Ragazzi',
                          value: nRagazzi,
                          color: const Color(0xFF2E7D32),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.school_rounded,
                          label: 'Catechisti',
                          value: nCatechisti,
                          color: const Color(0xFFB34700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.visibility_rounded,
                              color: Color(0xFF174A7E)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Visibilità parrocchiale: puoi vedere il calendario, '
                              'le anagrafiche di ogni ragazzo e il registro assenze '
                              'di tutta la parrocchia. Nella sincronizzazione P2P il '
                              'tuo dispositivo allinea tutte le classi.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Funzioni rapide',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF174A7E),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _QuickActions(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Parrocchia',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.admin_panel_settings_outlined,
                size: 56,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                'Accesso riservato',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'La vista parrocchiale è disponibile solo al Responsabile '
                'Catechistico con modalità attiva.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/settings'),
                icon: const Icon(Icons.settings),
                label: const Text('Vai alle impostazioni'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ParishConfig config;

  const _Header({required this.config});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF174A7E), Color(0xFF2368B1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.church_rounded, color: Colors.white, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.nomeParrocchia.trim().isEmpty
                      ? 'Parrocchia'
                      : config.nomeParrocchia.trim(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                if (config.diocesi.trim().isNotEmpty)
                  Text(
                    config.diocesi.trim(),
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Anno ${config.annoLabel}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Card con un dato statistico riassuntivo della parrocchia.
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
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
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.25 : 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 10),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark
                  ? Theme.of(context).colorScheme.onSurface
                  : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Griglia di accesso rapido alle funzioni amministrative del Responsabile.
class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickActionData(
        icon: Icons.groups_rounded,
        label: 'Classi',
        subtitle: 'Crea classi e assegna i catechisti',
        color: const Color(0xFF174A7E),
        route: '/parrocchia/classi',
      ),
      _QuickActionData(
        icon: Icons.meeting_room_rounded,
        label: 'Logistica',
        subtitle: 'Aule, orari e occupazione',
        color: const Color(0xFF00695C),
        route: '/parrocchia/logistica',
      ),
      _QuickActionData(
        icon: Icons.person_add_alt_1_rounded,
        label: 'Iscrizioni',
        subtitle: 'Censimento e passaggio d\'anno',
        color: const Color(0xFF2E7D32),
        route: '/parrocchia/iscrizioni',
      ),
      _QuickActionData(
        icon: Icons.people_alt_rounded,
        label: 'Catechisti',
        subtitle: 'Rubrica, telefono, classi e dispositivi',
        color: const Color(0xFF7B1FA2),
        route: '/parrocchia/catechisti',
      ),
      _QuickActionData(
        icon: Icons.admin_panel_settings_rounded,
        label: 'Amministrazione',
        subtitle: 'Hub completo della parrocchia',
        color: const Color(0xFFB34700),
        route: '/parrocchia/admin',
      ),
      _QuickActionData(
        icon: Icons.network_check_rounded,
        label: 'Rete parrocchiale',
        subtitle: 'Riunioni, avvisi, titoli',
        color: const Color(0xFF6A4FA3),
        route: '/parrocchia/rete',
      ),
      _QuickActionData(
        icon: Icons.task_alt_rounded,
        label: 'Consensi',
        subtitle: 'Schede iscrizione firmate',
        color: const Color(0xFF00838F),
        route: '/parrocchia/consensi',
      ),
      _QuickActionData(
        icon: Icons.gavel_rounded,
        label: 'Registro trattamenti',
        subtitle: 'Log GDPR (Art. 30)',
        color: const Color(0xFFC62828),
        route: '/parrocchia/audit',
      ),
      _QuickActionData(
        icon: Icons.history_rounded,
        label: 'Archivio storico',
        subtitle: 'Progresso e chiusura anno',
        color: const Color(0xFFAD7F00),
        route: '/parrocchia/archivio',
      ),
      _QuickActionData(
        icon: Icons.upload_file_rounded,
        label: 'Importa ragazzi',
        subtitle: 'Da Excel o CSV',
        color: const Color(0xFF01579B),
        route: '/parrocchia/import-ragazzi',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 600 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 116,
          ),
          itemCount: actions.length,
          itemBuilder: (context, index) {
            final a = actions[index];
            return _QuickActionCard(data: a);
          },
        );
      },
    );
  }
}

class _QuickActionData {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final String route;

  const _QuickActionData({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.route,
  });
}

class _QuickActionCard extends StatelessWidget {
  final _QuickActionData data;

  const _QuickActionCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push(data.route),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: data.color.withValues(alpha: isDark ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(data.icon, color: data.color, size: 22),
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? Theme.of(context).colorScheme.onSurface
                    : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              data.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
