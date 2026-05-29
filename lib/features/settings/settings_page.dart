import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wiredash/wiredash.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/security/privacy_settings.dart';
import '../../shared/widgets/app_scaffold.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(authStateProvider).valueOrNull ?? {};

    final privacy = ref.watch(privacySettingsProvider);

    return AppScaffold(
      title: 'Impostazioni',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          /// =========================
          /// PROFILE
          /// =========================
          _ProfileCard(name: data['name'] ?? '', role: 'Catechista'),

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
          /// ASSISTENZA & FEEDBACK
          /// =========================
          const _SectionTitle(title: 'Supporto'),

          const SizedBox(height: 12),

          _SettingsItem(
            icon: Icons.feedback_rounded,
            title: 'Invia Feedback',
            subtitle: "Segnala un problema o suggerisci un'idea",
            color: Colors.orange,
            onTap: () {
              if (!privacy.allowRemoteFeedback) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Abilita "Feedback remoto" in Privacy e sicurezza',
                    ),
                  ),
                );
                return;
              }
              try {
                Wiredash.of(context).show(inheritMaterialTheme: true);
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Feedback non configurato in questa build'),
                  ),
                );
              }
            },
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

          const SizedBox(height: 12),

          _SettingsItem(
            icon: Icons.password_rounded,
            title: 'Cambia PIN',
            subtitle: 'Modifica il tuo PIN di accesso',
            color: const Color(0xFF174A7E),
            onTap: () {
              context.go('/change-pin');
            },
          ),

          const SizedBox(height: 12),

          _SettingsItem(
            icon: Icons.delete_forever_rounded,
            title: 'Cancella dati salvati',
            subtitle: 'Elimina anagrafica, presenze, giornate o allegati',
            color: Colors.red,
            isDestructive: true,
            onTap: () => context.go('/delete-data'),
          ),

          const SizedBox(height: 24),

          /// =========================
          /// APP
          /// =========================
          const _SectionTitle(title: 'App'),

          const SizedBox(height: 12),

          _SettingsItem(
            icon: Icons.system_update_rounded,
            title: 'Aggiornamenti',
            subtitle: 'Controlla nuove versioni',
            color: const Color(0xFF174A7E),
            onTap: () => context.go('/updates'),
          ),

          const SizedBox(height: 12),

          _SettingsItem(
            icon: Icons.share_rounded,
            title: 'Condivisione Dati',
            subtitle: 'Condividi dati tra dispositivi via QR',
            color: Colors.purple,
            onTap: () => context.go('/data-share'),
          ),

          const SizedBox(height: 12),

          _SettingsItem(
            icon: Icons.backup_rounded,
            title: 'Backup',
            subtitle: 'Esporta o importa un backup completo',
            color: Colors.teal,
            onTap: () => context.go('/backup'),
          ),

          const SizedBox(height: 12),

          _SettingsItem(
            icon: Icons.info_rounded,
            title: 'Informazioni e licenze',
            subtitle: 'Vedi le dipendenze usate e le indicazioni open source',
            color: Colors.blue,
            onTap: () => context.go('/settings/licenses'),
          ),

          const SizedBox(height: 30),

          /// =========================
          /// LOGOUT
          /// =========================
          _SettingsItem(
            icon: Icons.logout_rounded,
            title: 'Logout',
            subtitle: "Esci dall'app",
            color: Colors.red,
            isDestructive: true,
            onTap: () async {
              await ref.read(authStateProvider.notifier).lock();
              if (context.mounted) {
                context.go('/');
              }
            },
          ),

          const SizedBox(height: 28),

          const _AppVersionLabel(),
        ],
      ),
    );
  }
}

class _AppVersionLabel extends StatelessWidget {
  const _AppVersionLabel();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version;
        final label = version == null ? 'CatechHub' : 'CatechHub v$version';

        return Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
        );
      },
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String name;
  final String role;

  const _ProfileCard({required this.name, required this.role});

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
              child: Icon(icon, color: isDestructive ? Colors.red : color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
