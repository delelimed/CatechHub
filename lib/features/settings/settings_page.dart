/// Pagina principale delle Impostazioni dell'app CateREG (CatechHub).
///
/// Funge da hub di navigazione per tutte le sezioni di configurazione:
/// - **Profilo**: card con nome e ruolo del catechista autenticato
/// - **Gestione**: collegamento alla gestione del gruppo e dei ragazzi, soglia assenze, cancellazione dati
/// - **Supporto**: invio feedback tramite Wiredash (solo se il consenso remoto è attivo)
/// - **Sicurezza**: privacy, cancellazione selettiva dati
/// - **App**: aggiornamenti, condivisione dati, licenze open source
/// - **Consiglia**: condivisione tramite SharePlus del link GitHub del progetto
/// - **Logout**: blocco della sessione e ritorno alla schermata di login
///
/// Dipende da [authStateProvider] per i dati dell'account e da
/// [privacySettingsProvider] per verificare se il feedback remoto è abilitato.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wiredash/wiredash.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/security/privacy_settings.dart';
import '../../core/services/meeting_notification_service.dart';
import '../../shared/models/user_role.dart';
import '../../shared/utils/anno_catechistico.dart';
import '../../shared/utils/app_mode.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../responsabile/parish_config_repository.dart';

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
          style: TextStyle(
            color: Color(0xFF174A7E),
            fontWeight: FontWeight.bold,
          ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              final v = int.tryParse(controller.text);
              if (v != null && v >= 1) {
                await ref
                    .read(privacySettingsProvider.notifier)
                    .setAbsenceThreshold(v);
                if (ctx.mounted) Navigator.of(ctx).pop();
              }
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  void _showParishConfigDialog(BuildContext context, WidgetRef ref) {
    final repo = ref.read(parishConfigRepositoryProvider);
    final config = repo.getConfig();

    final nomeCtrl = TextEditingController(text: config.nomeParrocchia);
    final diocesiCtrl = TextEditingController(text: config.diocesi);
    final annoCtrl = TextEditingController(
      text: config.annoCatechisticoCorrente.trim().isNotEmpty
          ? config.annoCatechisticoCorrente
          : currentCatechisticYear(),
    );
    final sogliaCtrl = TextEditingController(
      text: config.sogliaAssenzeConsecutive.toString(),
    );
    final durataCtrl = TextEditingController(
      text: config.durataValiditaConsensoMesi.toString(),
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Configura parrocchia',
            style: TextStyle(
              color: Color(0xFF174A7E),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ConfigSectionLabel('Parrocchia'),
                TextField(
                  controller: nomeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome parrocchia',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: diocesiCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Diocesi',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const Divider(height: 24),
                const _ConfigSectionLabel('Anno e presenze'),
                TextField(
                  controller: annoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Anno catechistico corrente',
                    hintText: 'Es. 2026-2027',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: sogliaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Soglia assenze consecutive (allerta)',
                    helperText: 'Almeno 2. Usata per le segnalazioni.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const Divider(height: 24),
                const _ConfigSectionLabel('Privacy'),
                TextField(
                  controller: durataCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Validità consenso GDPR (mesi)',
                    helperText: 'Durata del consenso al trattamento dei dati.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () async {
                final soglia = int.tryParse(sogliaCtrl.text.trim());
                final durata = int.tryParse(durataCtrl.text.trim());
                await repo.save(
                  config.copyWith(
                    nomeParrocchia: nomeCtrl.text.trim(),
                    diocesi: diocesiCtrl.text.trim(),
                    annoCatechisticoCorrente: annoCtrl.text.trim(),
                    durataValiditaConsensoMesi: (durata != null && durata > 0)
                        ? durata
                        : config.durataValiditaConsensoMesi,
                    sogliaAssenzeConsecutive: (soglia != null && soglia >= 2)
                        ? soglia
                        : config.sogliaAssenzeConsecutive,
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Configurazione parrocchia salvata.'),
                  ),
                );
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNotificationSettingsDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final isEnabled = MeetingNotificationService.areNotificationsEnabled;
          final currentTime = MeetingNotificationService.notificationTime;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text(
              'Notifiche incontri',
              style: TextStyle(
                color: Color(0xFF174A7E),
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Ricevi un promemoria il giorno prima di ogni incontro di catechismo o riunione, all\'orario che preferisci.',
                  style: TextStyle(fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  title: const Text('Attiva notifiche'),
                  subtitle: const Text(
                    'Ricevi promemoria per incontri e riunioni',
                  ),
                  value: isEnabled,
                  activeThumbColor: const Color(0xFF174A7E),
                  onChanged: (value) async {
                    await MeetingNotificationService.setEnabled(value);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 12),
                if (isEnabled) ...[
                  ListTile(
                    title: const Text('Orario notifica'),
                    subtitle: Text(
                      currentTime,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF174A7E),
                      ),
                    ),
                    trailing: const Icon(
                      Icons.access_time_rounded,
                      color: Color(0xFF174A7E),
                    ),
                    onTap: () async {
                      final TimeOfDay? picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: int.parse(currentTime.split(':')[0]),
                          minute: int.parse(currentTime.split(':')[1]),
                        ),
                      );
                      if (picked != null && ctx.mounted) {
                        final formattedTime =
                            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                        await MeetingNotificationService.setNotificationTime(
                          formattedTime,
                        );
                        setState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'La notifica verrà inviata il giorno prima dell\'incontro a quest\'ora.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Chiudi'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacy = ref.watch(privacySettingsProvider);
    final authAsync = ref.watch(authStateProvider);
    final isResponsabile = UserRole.isResponsabile;

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
              _ProfileCard(
                name: data['name'] ?? '',
                role: UserRole.current().label,
              ),

              const SizedBox(height: 20),

              /// =========================
              /// GESTIONE
              /// =========================
              const _SectionTitle(title: 'Gestione'),

              const SizedBox(height: 12),

              if (!isResponsabile) ...[
                _SettingsItem(
                  icon: Icons.list_alt_rounded,
                  title: 'Visualizza Gruppi',
                  subtitle: 'Vedi tutti i gruppi di cui fai parte',
                  color: const Color(0xFF174A7E),
                  onTap: () => context.push('/view-groups'),
                ),

                const SizedBox(height: 12),

                _SettingsItem(
                  icon: Icons.groups_rounded,
                  title: 'Gestione Gruppo',
                  subtitle: 'Gestisci il gruppo e i ragazzi',
                  color: const Color(0xFF174A7E),
                  onTap: () => context.push('/group-management'),
                ),

                const SizedBox(height: 12),

                if (AppModeUtils.supplenzeEnabled()) ...[
                  _SettingsItem(
                    icon: Icons.swap_horiz_rounded,
                    title: 'Supplenze',
                    subtitle:
                        'Delega temporanea del registro a un altro catechista',
                    color: const Color(0xFF174A7E),
                    onTap: () => context.push('/substitutes'),
                  ),

                  const SizedBox(height: 12),
                ],

                _SettingsItem(
                  icon: Icons.warning_amber_rounded,
                  title: 'Soglia assenze',
                  subtitle:
                      'Minimo assenze per la dashboard: ${privacy.absenceThreshold}',
                  color: Colors.red,
                  onTap: () => _showAbsenceThresholdDialog(context, ref),
                ),

                const SizedBox(height: 12),
              ],

              if (!isResponsabile) ...[
                const SizedBox(height: 12),

                _SettingsItem(
                  icon: Icons.notifications_active_rounded,
                  title: 'Notifiche incontri',
                  subtitle:
                      'Ricevi un promemoria il giorno prima di incontri e riunioni',
                  color: Colors.blue,
                  onTap: () => _showNotificationSettingsDialog(context, ref),
                ),
              ],

              const SizedBox(height: 24),

              /// =========================
              /// GESTIONE PARROCCHIA (Responsabile Catechistico)
              /// =========================
              if (isResponsabile) ...[
                const _SectionTitle(title: 'Gestione parrocchia'),

                const SizedBox(height: 12),

                _SettingsItem(
                  icon: Icons.church_rounded,
                  title: 'Amministrazione parrocchia',
                  subtitle: 'Classi, iscrizioni, logistica e allarmi assenze',
                  color: const Color(0xFF174A7E),
                  onTap: () => context.push('/parrocchia/admin'),
                ),

                const SizedBox(height: 12),

                _SettingsItem(
                  icon: Icons.verified_user_rounded,
                  title: 'Catena di fiducia',
                  subtitle:
                      'Approva i dispositivi abilitati alla sync e gestisci il QR di fiducia',
                  color: Colors.teal,
                  onTap: () => context.push('/settings/approval-center'),
                ),

                const SizedBox(height: 12),

                _SettingsItem(
                  icon: Icons.gavel_rounded,
                  title: 'Registro Trattamenti',
                  subtitle:
                      'Registro GDPR (Art. 30) con verifica integrità firme',
                  color: Colors.teal,
                  onTap: () => context.push('/parrocchia/audit'),
                ),

                const SizedBox(height: 12),

                _SettingsItem(
                  icon: Icons.history_rounded,
                  title: 'Archivio storico',
                  subtitle:
                      'Progresso dei ragazzi negli anni e chiusura anno catechistico',
                  color: const Color(0xFF174A7E),
                  onTap: () => context.push('/parrocchia/archivio'),
                ),

                const SizedBox(height: 12),

                _SettingsItem(
                  icon: Icons.upload_file_rounded,
                  title: 'Importa Dati Ragazzi',
                  subtitle: 'Importazione massiva anagrafica da Excel o CSV',
                  color: const Color(0xFF174A7E),
                  onTap: () => context.push('/parrocchia/import-ragazzi'),
                ),

                const SizedBox(height: 12),

                _SettingsItem(
                  icon: Icons.tune_rounded,
                  title: 'Configura parrocchia',
                  subtitle:
                      'Nome parrocchia, diocesi, anno catechistico, soglia assenze',
                  color: const Color(0xFF174A7E),
                  onTap: () => _showParishConfigDialog(context, ref),
                ),

                const SizedBox(height: 24),
              ],

              /// =========================
              /// ASSISTENZA & FEEDBACK
              /// =========================
              const _SectionTitle(title: 'Supporto'),

              const SizedBox(height: 12),

              _SettingsItem(
                icon: Icons.tour_rounded,
                title: 'Guida alle funzioni',
                subtitle:
                    'Rivedi la guida all\'uso dell\'app in qualsiasi momento',
                color: Colors.blue,
                onTap: () => context.push('/guide?mode=review'),
              ),

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

              const SizedBox(height: 12),

              _SettingsItem(
                icon: Icons.delete_forever_rounded,
                title: 'Cancella dati salvati',
                subtitle:
                    'Elimina selettivamente anagrafiche, presenze, documenti, calendario, catechesi o allegati. La cancellazione totale avviene con conferma dopo 24 ore',
                color: Colors.red,
                isDestructive: true,
                onTap: () => context.push('/delete-data'),
              ),

              const SizedBox(height: 24),

              /// =========================
              /// PARROCCHIA (Associati)
              /// =========================
              if (!isResponsabile && AppModeUtils.canViewLogistica()) ...[
                const _SectionTitle(title: 'Parrocchia'),

                const SizedBox(height: 12),

                _SettingsItem(
                  icon: Icons.meeting_room_rounded,
                  title: 'Aule e orari',
                  subtitle:
                      'Consultazione in sola lettura della logistica parrocchiale',
                  color: const Color(0xFF00695C),
                  onTap: () => context.push('/parrocchia/logistica'),
                ),

                const SizedBox(height: 24),
              ],

              /// =========================
              /// CONDIVISIONE E BACKUP
              /// =========================
              if (!isResponsabile) ...[
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
              ],

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

                  SharePlus.instance.share(ShareParams(text: shareText));
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
    final borderColor = isDark
        ? colorScheme.outline.withValues(alpha: 0.2)
        : Colors.transparent;
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Scegli il tema',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
          ),
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
                    color: isSelected
                        ? (isDark
                              ? colorScheme.primary
                              : const Color(0xFF174A7E))
                        : colorScheme.onSurface,
                  ),
                ),
                activeColor: isDark
                    ? colorScheme.primary
                    : const Color(0xFF174A7E),
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

/// Etichetta di sezione usata dentro i dialog di configurazione.
class _ConfigSectionLabel extends StatelessWidget {
  final String text;

  const _ConfigSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
          color: Theme.of(context).colorScheme.primary,
        ),
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
    final borderColor = isDark
        ? colorScheme.outline.withValues(alpha: 0.2)
        : Colors.transparent;
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
