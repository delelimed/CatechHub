import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../shared/widgets/app_scaffold.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(authStateProvider).valueOrNull ?? {};

    final canManageCatechists = data['canManageCatechists'] == true;

    return AppScaffold(
          title: 'Impostazioni',

          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [

              /// =========================
              /// PROFILE
              /// =========================
              _ProfileCard(
                name: data['name'] ?? '',
                role: 'Catechista',
              ),

              const SizedBox(height: 20),

              /// =========================
              /// GESTIONE
              /// =========================
              const _SectionTitle(title: 'Gestione'),

              const SizedBox(height: 12),

              _SettingsItem(
                icon: Icons.groups_rounded,
                title: 'Gestione Gruppo',
                subtitle: 'Gestisci il gruppo e i ragazzi',
                color: const Color(0xFF174A7E),
                onTap: () => context.go('/group-management'),
              ),

              const SizedBox(height: 24),

              /// =========================
              /// SICUREZZA
              /// =========================
              const _SectionTitle(title: 'Sicurezza'),

              const SizedBox(height: 12),

              _SettingsItem(
                icon: Icons.lock_rounded,
                title: 'Privacy e sicurezza',
                subtitle: 'Gestisci i tuoi dati personali',
                color: Colors.green,
                onTap: () {
                   context.go('/privacy-security');
                },
              ),

              const SizedBox(height: 30),

              /// =========================
              /// LOGOUT
              /// =========================
              _SettingsItem(
                icon: Icons.logout_rounded,
                title: 'Logout',
                subtitle: 'Esci dall’app',
                color: Colors.red,
                isDestructive: true,
                onTap: () async {
                  await ref.read(authStateProvider.notifier).lock();
                  if (context.mounted) {
                    context.go('/');
                  }
                },
              ),
            ],
          ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String name;
  final String role;

  const _ProfileCard({
    required this.name,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFF174A7E),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF174A7E),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  role,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF174A7E),
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

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
        color: Colors.grey.shade600,
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isDestructive;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: isDestructive
                    ? Colors.red.withOpacity(0.08)
                    : color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isDestructive
                          ? Colors.red
                          : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
