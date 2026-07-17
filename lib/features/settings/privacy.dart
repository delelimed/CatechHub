/// Pagina "Privacy e Sicurezza" che illustra all'utente come i dati del
/// registro catechistico vengono gestiti localmente sul dispositivo.
///
/// Rassicura l'utente spiegando in modo semplice:
/// - I dati restano solo sul dispositivo
/// - Le foto e i PDF sono protetti
/// - Il PIN è custodito in modo sicuro
/// - Non c'è invio automatico a server esterni
/// - L'utente ha il pieno controllo dei propri dati
/// - **PROTEZIONE RUNTIME freeRASP: anti-root, anti-emulatore, anti-tamper, anti-hooking**
///
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/security_service.dart';
import '../../shared/widgets/app_scaffold.dart';

class PrivacySecurityPage extends ConsumerWidget {
  const PrivacySecurityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final securityService = ref.watch(securityStatusProvider);

    return AppScaffold(
      title: 'Privacy e Sicurezza',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _HeaderCard(),
          const SizedBox(height: 16),
          const _SectionLabel('I tuoi dati sono al sicuro'),
          const SizedBox(height: 8),
          const _InfoCard(
            title: 'Rimanere sul dispositivo',
            content:
                'Tutti i dati che inserisci — ragazzi, presenze, programmazione, '
                'documenti, note — restano solo sul tuo telefono. Non vengono caricati '
                'su server esterni né condivisi automaticamente con nessuno.',
            icon: Icons.phone_android_rounded,
          ),
          const SizedBox(height: 10),
          const _InfoCard(
            title: 'Foto e documenti protetti',
            content:
                'Le foto e i PDF che alleghi non finiscono nella Galleria del telefono: '
                'restano in un\'area privata dell\'app, accessibile solo dopo aver '
                'inserito il PIN o l\'impronta digitale.',
            icon: Icons.lock_rounded,
          ),
          const SizedBox(height: 10),
          const _InfoCard(
            title: 'Niente cloud, niente sorprese',
            content:
                'CatechHub non invia i tuoi dati a nessun servizio online. '
                'Puoi fare backup manuali cifrati su file o scambiare dati '
                'in modo sicuro con altri catechisti via QR code o Bluetooth.',
            icon: Icons.cloud_off_rounded,
          ),
          const SizedBox(height: 10),
          const _InfoCard(
            title: 'Pieno controllo dei tuoi dati',
            content:
                'Puoi vedere, modificare o eliminare i tuoi dati in qualsiasi '
                'momento dalle impostazioni. La cancellazione è definitiva e '
                'limitata al tuo dispositivo, come deve essere.',
            icon: Icons.admin_panel_settings_rounded,
          ),

          // ─── NUOVA SEZIONE: PROTEZIONE RUNTIME FREE_RASP ───
          const SizedBox(height: 24),
          _SectionLabel(
            'Protezione Runtime (freeRASP v8+)',
            icon: Icons.security_rounded,
          ),
          const SizedBox(height: 8),
          _FreeRASPStatusCard(securityStatus: securityService),


          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Provider per lo stato di sicurezza freeRASP (reactive)
final securityStatusProvider = NotifierProvider<_SecurityStatusNotifier, SecurityStatus>(_SecurityStatusNotifier.new);

/// Notifier che espone reattivamente i ValueNotifier di SecurityService
class _SecurityStatusNotifier extends Notifier<SecurityStatus> {
  StreamSubscription? _blockSub;
  StreamSubscription? _warningSub;

  @override
  SecurityStatus build() {
    _blockSub = _valueNotifierToStream(SecurityService.blockMessage)
        .listen((value) => state = state.copyWith(blockMessage: value));
    _warningSub = _valueNotifierToStream(SecurityService.developerOptionsWarningMessage)
        .listen((value) => state = state.copyWith(warningMessage: value));
    ref.onDispose(() {
      _blockSub?.cancel();
      _warningSub?.cancel();
    });
    return SecurityStatus(
      blockMessage: SecurityService.blockMessage.value,
      warningMessage: SecurityService.developerOptionsWarningMessage.value,
    );
  }

  /// Converte un ValueNotifier in una Stream per ascolto reattivo
  Stream<T> _valueNotifierToStream<T>(ValueNotifier<T> notifier) async* {
    yield notifier.value;
    final controller = StreamController<T>.broadcast();
    void listener() => controller.add(notifier.value);
    notifier.addListener(listener);
    await for (final value in controller.stream) {
      yield value;
    }
    notifier.removeListener(listener);
    await controller.close();
  }
}

/// Stato combinato per la UI
class SecurityStatus {
  final String? blockMessage;
  final String? warningMessage;

  SecurityStatus({this.blockMessage, this.warningMessage});

  bool get hasActiveBlock => blockMessage != null;
  bool get hasActiveWarning => warningMessage != null;
  bool get isSecure => !hasActiveBlock && !hasActiveWarning;

  SecurityStatus copyWith({String? blockMessage, String? warningMessage}) {
    return SecurityStatus(
      blockMessage: blockMessage ?? this.blockMessage,
      warningMessage: warningMessage ?? this.warningMessage,
    );
  }
}

/// Etichetta di sezione in maiuscolo usata nella pagina privacy.
class _SectionLabel extends StatelessWidget {
  final String text;
  final IconData? icon;

  const _SectionLabel(this.text, {this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 6),
        ],
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

/// Card di intestazione della pagina privacy con il messaggio rassicurante
/// "I tuoi dati restano sul dispositivo".
class _HeaderCard extends StatelessWidget {
  const _HeaderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.blue.shade50.withValues(alpha: 0.4)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
              'I tuoi dati restano sul dispositivo',
              style: TextStyle(
                fontSize: 17,
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

/// Card informativa riutilizzabile nella pagina privacy: mostra un'icona,
/// un titolo e un testo descrittivo su come vengono gestiti i dati.
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
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF174A7E).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF174A7E), size: 22),
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
                    height: 1.45,
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

/// Card che mostra lo stato attuale della protezione freeRASP
/// con indicatori visivi animati.
class _FreeRASPStatusCard extends ConsumerStatefulWidget {
  final SecurityStatus securityStatus;

  const _FreeRASPStatusCard({required this.securityStatus});

  @override
  ConsumerState<_FreeRASPStatusCard> createState() => _FreeRASPStatusCardState();
}

class _FreeRASPStatusCardState extends ConsumerState<_FreeRASPStatusCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.securityStatus;
    Color statusColor;
    IconData statusIcon;
    String statusTitle;
    String statusSubtitle;
    bool showPulse = false;

    if (status.hasActiveBlock) {
      statusColor = Colors.red.shade700;
      statusIcon = Icons.lock_outline_rounded;
      statusTitle = 'BLOCCO SICUREZZA ATTIVO';
      statusSubtitle = status.blockMessage!;
      showPulse = true;
    } else if (status.hasActiveWarning) {
      statusColor = Colors.orange.shade700;
      statusIcon = Icons.warning_amber_rounded;
      statusTitle = 'AVVISO DI SICUREZZA';
      statusSubtitle = status.warningMessage!;
      showPulse = true;
    } else {
      statusColor = Colors.green.shade700;
      statusIcon = Icons.verified_rounded;
      statusTitle = 'AMBIENTE SICURO';
      statusSubtitle = 'Tutti i controlli freeRASP superati. Protezione attiva.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            statusColor.withValues(alpha: 0.08),
            statusColor.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header con icona e titolo
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) => Transform.scale(
                  scale: showPulse ? _pulseAnimation.value : 1.0,
                  child: child,
                ),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        statusColor.withValues(alpha: 0.2),
                        statusColor.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: showPulse
                        ? [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 28),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'freeRASP v8+ Runtime Protection',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: statusColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              // Badge versione
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'v8+',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Messaggio dettagliato
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  status.hasActiveBlock
                      ? Icons.error_outline_rounded
                      : status.hasActiveWarning
                          ? Icons.info_outline_rounded
                          : Icons.check_circle_outline_rounded,
                  color: statusColor,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    statusSubtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: statusColor.withValues(alpha: 0.9),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Indicatori controlli
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniIndicator(
                label: 'Root',
                icon: Icons.admin_panel_settings_rounded,
                passed: !status.hasActiveBlock || !status.blockMessage!.contains('Root'),
                color: Colors.green,
              ),
              _MiniIndicator(
                label: 'Emulatore',
                icon: Icons.computer_rounded,
                passed: !status.hasActiveBlock || !status.blockMessage!.contains('Emulatore'),
                color: Colors.green,
              ),
              _MiniIndicator(
                label: 'Integrità',
                icon: Icons.verified_rounded,
                passed: !status.hasActiveBlock || !status.blockMessage!.contains('Firma'),
                color: Colors.green,
              ),
              _MiniIndicator(
                label: 'Hooking',
                icon: Icons.bug_report_rounded,
                passed: !status.hasActiveBlock || !status.blockMessage!.contains('Hooking'),
                color: Colors.green,
              ),
              _MiniIndicator(
                label: 'Device Bind',
                icon: Icons.devices_rounded,
                passed: !status.hasActiveBlock || !status.blockMessage!.contains('Binding'),
                color: Colors.green,
              ),
              _MiniIndicator(
                label: 'ADB/Debug',
                icon: Icons.usb_rounded,
                passed: !status.hasActiveWarning,
                color: status.hasActiveWarning ? Colors.orange : Colors.green,
                isWarning: status.hasActiveWarning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Indicatore compatto per singolo controllo
class _MiniIndicator extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool passed;
  final Color color;
  final bool isWarning;

  const _MiniIndicator({
    required this.label,
    required this.icon,
    required this.passed,
    required this.color,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayColor = passed ? color : (isWarning ? Colors.orange : Colors.red);
    final bgColor = passed
        ? displayColor.withValues(alpha: 0.12)
        : displayColor.withValues(alpha: 0.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: displayColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: displayColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: displayColor,
            ),
          ),
        ],
      ),
    );
  }
}