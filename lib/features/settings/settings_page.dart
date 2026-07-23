/// Pagina principale delle Impostazioni dell'app CateREG (CatechHub).
///
/// Funge da hub di navigazione per tutte le sezioni di configurazione:
/// - **Profilo**: card con nome e ruolo del catechista autenticato
/// - **Gestione**: collegamento alla gestione del gruppo e dei ragazzi
/// - **Supporto**: invio feedback tramite Wiredash (solo se il consenso remoto è attivo)
/// - **Sicurezza**: privacy, cancellazione selettiva dati
/// - **App**: aggiornamenti, condivisione dati, licenze open source
/// - **Consiglia**: condivisione tramite SharePlus del link GitHub del progetto
/// - **Logout**: blocco della sessione e ritorno alla schermata di login
///
/// Dipende da [authStateProvider] per i dati dell'account e da
/// [privacySettingsProvider] per verificare se il feedback remoto è abilitato.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wiredash/wiredash.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/security/privacy_settings.dart';
import '../../shared/widgets/app_scaffold.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  void _showAbsenceThresholdDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(privacySettingsProvider).absenceThreshold;
    final controller = TextEditingController(text: current.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Soglia assenze',
          style: TextStyle(color: Color(0xFF174A7E), fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Mostra nella dashboard i ragazzi con almeno questo numero di assenze.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () {
                    final v = int.tryParse(controller.text) ?? 1;
                    if (v > 1) controller.text = (v - 1).toString();
                  },
                ),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: controller,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    final v = int.tryParse(controller.text) ?? 1;
                    controller.text = (v + 1).toString();
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF174A7E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final v = int.tryParse(controller.text);
              if (v != null && v >= 1) {
                await ref.read(privacySettingsProvider.notifier).setAbsenceThreshold(v);
                if (ctx.mounted) Navigator.of(ctx).pop();
              }
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacy = ref.watch(privacySettingsProvider);
    final authAsync = ref.watch(authStateProvider);

    return authAsync.when(
      data: (map) {
        final data = map ?? <String, dynamic>{};

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
                onTap: () => context.push('/group-management'),
              ),

              const SizedBox(height: 12),

              _SettingsItem(
                icon: Icons.warning_amber_rounded,
                title: 'Soglia assenze',
                subtitle: 'Minimo assenze per la dashboard: ${privacy.absenceThreshold}',
                color: Colors.red,
                onTap: () => _showAbsenceThresholdDialog(context, ref),
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
                        content: Text(
                          'Feedback non configurato in questa build',
                        ),
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
                  context.push('/privacy-security');
                },
              ),

              const SizedBox(height: 12),

              _SettingsItem(
                icon: Icons.delete_forever_rounded,
                title: 'Cancella dati salvati',
                subtitle: 'Elimina anagrafica, presenze, giornate o allegati',
                color: Colors.red,
                isDestructive: true,
                onTap: () => context.push('/delete-data'),
              ),

              const SizedBox(height: 24),

              /// =========================
              /// CONDIVISIONE E BACKUP
              /// =========================
              const _SectionTitle(title: 'Condivisione e backup'),

              const SizedBox(height: 12),

              _SettingsItem(
                icon: Icons.qr_code_rounded,
                title: 'Condivisione e Backup',
                subtitle: 'Condividi dati, sincronizza e gestisci backup',
                color: Colors.orange,
                onTap: () => context.push('/data-share'),
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
                onTap: () => context.push('/updates'),
              ),

              const SizedBox(height: 12),

              const _ThemeSelectorItem(),

              const SizedBox(height: 12),

              _SettingsItem(
                icon: Icons.info_rounded,
                title: 'Informazioni e licenze',
                subtitle:
                    'Vedi le dipendenze usate e le indicazioni open source',
                color: Colors.blue,
                onTap: () => context.push('/settings/licenses'),
              ),

              const SizedBox(height: 30),

              _SettingsItem(
                icon: Icons.recommend_rounded,
                title: 'Consiglia l\'app',
                subtitle: 'Condividi un messaggio per consigliare l\'app',
                color: Colors.indigo,
                onTap: () {
                  final shareText =
                      'Ehi! Prova CatechHub — il registro smart per i catechisti. Scopri di più su GitHub: https://github.com/delelimed/CatechHub';

                  SharePlus.instance.share(
                    ShareParams(
                      text: shareText,
                    ),
                  );
                },
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
      },
      loading: () => const AppScaffold(
        title: 'Impostazioni',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => AppScaffold(
        title: 'Impostazioni',
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Errore nel caricamento dell\'account: $err'),
          ),
        ),
      ),
    );
  }
}

/// Widget per selezionare il tema dell'app (Automatico/Chiaro/Scuro)
class _ThemeSelectorItem extends ConsumerWidget {
  const _ThemeSelectorItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.watch(themeNotifierProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final cardColor = isDark ? colorScheme.surfaceContainer : Colors.white;
    final iconBgColor = isDark
        ? colorScheme.primaryContainer.withValues(alpha: 0.3)
        : const Color(0xFFEAF2FF);
    final iconColor = isDark ? colorScheme.primary : const Color(0xFF174A7E);
    final titleColor = isDark ? colorScheme.onSurface : const Color(0xFF1A1A1A);
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final borderColor = isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.transparent;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.4)
        : Colors.black.withValues(alpha: 0.04);
    final chevronColor = isDark ? Colors.grey.shade500 : Colors.grey.shade400;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => _showThemeDialog(context, ref),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
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
                color: iconBgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.brightness_6_rounded, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tema',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentTheme.displayName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: chevronColor),
          ],
        ),
      ),
    );
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.read(themeNotifierProvider);
    final notifier = ref.read(themeNotifierProvider.notifier);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Scegli il tema',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF174A7E)),
        ),
        content: RadioGroup<AppThemeMode>(
          groupValue: currentTheme,
          onChanged: (value) {
            if (value != null) {
              notifier.setThemeMode(value);
              Navigator.pop(ctx);
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: AppThemeMode.values.map((mode) {
              final isSelected = mode == currentTheme;
              return RadioListTile<AppThemeMode>(
                value: mode,
                title: Text(
                  mode.displayName,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? const Color(0xFF174A7E) : Colors.black87,
                  ),
                ),
                activeColor: const Color(0xFF174A7E),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
        ],
      ),
    );
  }
}

/// Etichetta in fondo alla pagina che mostra il nome dell'app e la versione
/// ottenuta da [PackageInfo.fromPlatform].
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

/// Card del profilo nella pagina impostazioni: mostra l'iniziale del nome
/// in un CircleAvatar, il nome completo e il ruolo (es. "Catechista").
class _ProfileCard extends StatelessWidget {
  final String name;
  final String role;

  const _ProfileCard({required this.name, required this.role});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final cardColor = isDark ? colorScheme.surfaceContainer : Colors.white;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.4)
        : Colors.black.withValues(alpha: 0.04);
    final nameColor = isDark ? colorScheme.onSurface : const Color(0xFF174A7E);
    final roleColor = isDark ? colorScheme.primary : const Color(0xFF174A7E);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
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
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: nameColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  role,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: roleColor,
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

/// Titolo di sezione nella pagina impostazioni, renderizzato in maiuscolo
/// con letter-spacing aumentato.
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

/// Singola riga selezionabile nelle impostazioni, composta da icona,
/// titolo, sottotitolo e freccia di navigazione. Supporta la modalità
/// `isDestructive` per voci pericolose (cancellazione, logout).
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final cardColor = isDark ? colorScheme.surfaceContainer : Colors.white;
    final iconBgColor = isDestructive
        ? Colors.red.withValues(alpha: isDark ? 0.2 : 0.08)
        : color.withValues(alpha: isDark ? 0.2 : 0.10);
    final titleColor = isDark ? colorScheme.onSurface : const Color(0xFF1A1A1A);
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final iconColor = isDestructive ? Colors.red : color;
    final borderColor = isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.transparent;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.4)
        : Colors.black.withValues(alpha: 0.04);

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
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
                color: iconBgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: isDark ? Colors.grey.shade500 : Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
