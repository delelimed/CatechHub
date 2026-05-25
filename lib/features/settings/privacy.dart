import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/app_scaffold.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/analytics/event_tracking_service.dart';

class PrivacySecurityPage extends ConsumerWidget {
  const PrivacySecurityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsConsent = ref.watch(analyticsConsentProvider);

    return AppScaffold(
      title: 'Privacy e Sicurezza',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _HeaderCard(),
          const SizedBox(height: 16),
          const _InfoCard(
            title: 'A cosa serve questa app',
            content:
                'Questa applicazione e progettata per supportare i catechisti '
                'nella gestione dei gruppi, delle presenze e delle attivita pastorali. '
                'L\'obiettivo e rendere piu semplice, ordinata e sicura l\'organizzazione delle comunita.',
            icon: Icons.church_rounded,
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            title: 'Protezione dei dati',
            content:
                'Tutti i dati personali degli utenti vengono trattati con il massimo rispetto della privacy. '
                'Le informazioni sono salvate localmente sul dispositivo in un archivio Hive cifrato. '
                'Nessun dato viene mai inviato a server remoti senza il tuo consenso esplicito.',
            icon: Icons.lock_rounded,
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            title: 'Crittografia',
            content:
                'I dati sensibili sono cifrati a riposo con Hive AES e la chiave viene custodita nel portachiavi sicuro del dispositivo. '
                'Questo riduce il rischio che le informazioni siano leggibili da terze parti non autorizzate.',
            icon: Icons.security_rounded,
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            title: 'Standard di sicurezza',
            content:
                'L\'app funziona offline e usa un PIN locale per sbloccare il registro. '
                'La protezione principale e legata al dispositivo e alla cifratura dell\'archivio locale.',
            icon: Icons.verified_user_rounded,
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            title: 'Accesso ai dati',
            content:
                'Solo utenti autorizzati possono accedere alle informazioni. '
                'I permessi vengono gestiti tramite ruoli (admin, catechista) e regole del database.',
            icon: Icons.admin_panel_settings_rounded,
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            title: 'Conformita GDPR',
            content:
                'L\'app rispetta il Regolamento Generale sulla Protezione dei Dati (GDPR). '
                'Tutti i dati personali, in particolare i dati dei ragazzi, non lasciano mai il dispositivo e rimangono completamente locali. '
                'I dati non vengono condivisi con server remoti, cloud o terze parti. '
                'Tutti i dati sono trattati secondo i principi di liceita, correttezza e trasparenza.',
            icon: Icons.gavel_rounded,
          ),
          const SizedBox(height: 24),
          _AnalyticsCard(
            analyticsEnabled: analyticsConsent,
            onChanged: (value) {
              ref.read(analyticsConsentProvider.notifier).setConsent(value);
              EventTrackingService.setEnabled(value);
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'La sicurezza dei dati e una priorita assoluta del sistema.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  final bool analyticsEnabled;
  final Function(bool) onChanged;

  const _AnalyticsCard({
    required this.analyticsEnabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: analyticsEnabled
            ? const Color(0xFF174A7E).withOpacity(0.05)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: analyticsEnabled
              ? const Color(0xFF174A7E).withOpacity(0.2)
              : Colors.grey.shade300,
        ),
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: analyticsEnabled
                  ? const Color(0xFF174A7E)
                  : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.analytics_rounded,
              color: analyticsEnabled ? Colors.white : Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Analisi e Feedback',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  analyticsEnabled
                      ? 'Raccolta dati attivata. Solo i feedback e gli screenshot inviati volontariamente vengono catturati.'
                      : 'Raccolta dati disattivata.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: analyticsEnabled,
            onChanged: onChanged,
            activeColor: const Color(0xFF174A7E),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            Colors.blue.shade50.withOpacity(0.4),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_rounded, color: Color(0xFF174A7E), size: 34),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Privacy e Sicurezza',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF174A7E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String content;
  final IconData icon;

  const _InfoCard({
    required this.title,
    required this.content,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF174A7E).withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF174A7E)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.4,
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
