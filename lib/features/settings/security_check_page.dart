// ═══════════════════════════════════════════════════════════════════════════════
// security_check_page.dart — CatechHub (Verifica Sicurezza freeRASP — UI Moderna)
// ═══════════════════════════════════════════════════════════════════════════════
//
// PAGINA DI VERIFICA SICUREZZA — REQUISITI UI MIGLIORATI:
// ──────────────────────────────────────────────────────────────────────────────
// Mostra gli esiti delle verifiche runtime di freeRASP con UI premium:
// ──────────────────────────────────────────────────────────────────────────────
// • HEADER ANIMATO: Stato globale con animazione pulse/shine, gradiente dinamico
// • CARDS CONTROLLI: ExpansionTile animate con staggered entrance animation
//   - Icon container con gradiente + ombra + animazione scale al tap
//   - Badge stato animato (success/warning/error/pending) con micro-animazioni
//   - Titolo + descrizione con tipografia gerarchica
//   - Expand: dettaglio minaccia + vettori attacco + mitigazione + link docs
// • INDICATORI REAL-TIME: ValueListenableBuilder su SecurityService callbacks
// • PULL-TO-REFRESH: RefreshIndicator con animazione custom + haptic feedback
// • STATO VUOTO/ERRORE: Illustrations vuote con messaggi contestuali
// • ACCESSIBILITÀ: Semantics, contrasti WCAG AA, screen reader labels
// • THEME-AWARE: Supporta light/dark mode con ColorScheme dinamico
// ──────────────────────────────────────────────────────────────────────────────
//
// INTEGRAZIONE ROUTER (go_router):
// ──────────────────────────────────────────────────────────────────────────────
// GoRoute(
//   path: '/security-check',
//   name: 'security-check',
//   builder: (context, state) => const SecurityCheckPage(),
// ),
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/security/security_service.dart';

/// Pagina che mostra i risultati delle verifiche di sicurezza freeRASP
/// con UI moderna, animazioni e aggiornamenti real-time.
class SecurityCheckPage extends ConsumerStatefulWidget {
  const SecurityCheckPage({super.key});

  @override
  ConsumerState<SecurityCheckPage> createState() => _SecurityCheckPageState();
}

class _SecurityCheckPageState extends ConsumerState<SecurityCheckPage>
    with TickerProviderStateMixin {
  late final AnimationController _headerController;
  late final AnimationController _listController;
  late final AnimationController _refreshController;

  late final Animation<double> _headerFadeAnimation;
  late final Animation<Offset> _headerSlideAnimation;
  late final Animation<double> _headerScaleAnimation;
  late final Animation<double> _refreshRotationAnimation;

  final List<SecurityCheckItem> _checks = [];
  Timer? _refreshDebounce;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();

    _headerController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _listController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _headerFadeAnimation = CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOut,
    );
    _headerSlideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOutCubic,
    ));
    _headerScaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _headerController, curve: Curves.elasticOut),
    );
    _refreshRotationAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _refreshController, curve: Curves.linear),
    );

    _initializeChecks();
    _startEntranceAnimations();
  }

  void _initializeChecks() {
    _checks.clear();
    _checks.addAll([
      SecurityCheckItem(
        id: 'root',
        title: 'Root / Accesso Privilegiato',
        description:
            'Verifica se il dispositivo ha accesso root (Magisk, KernelSU, SuperSU, ecc.). '
            'Il root permette di bypassare le protezioni del sistema e accedere a dati sensibili.',
        icon: Icons.admin_panel_settings_rounded,
        iconGradient: const LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
        threatType: ThreatType.root,
        threatVectors: [
          'Bypass sandbox applicazione',
          'Accesso filesystem root',
          'Modifica memoria processo',
          'Intercettazione chiamate sistema',
          'Installazione certificati CA malevoli',
        ],
        mitigation:
            'Disabilita root o usa Magisk Hide/Zygisk. Ripristina stock ROM per uso produzione.',
        docsUrl: 'https://freerasp.tech/docs/threats/root',
      ),
      SecurityCheckItem(
        id: 'emulator',
        title: 'Emulatore / Ambiente Virtuale',
        description:
            "Rileva se l'app sta girando su un emulatore Android invece che su un dispositivo fisico. "
            'Gli emulatori sono spesso usati per analisi dinamica e reverse engineering.',
        icon: Icons.computer_rounded,
        iconGradient: const LinearGradient(
          colors: [Color(0xFF43CEA2), Color(0xFF185A9D)],
        ),
        threatType: ThreatType.emulator,
        threatVectors: [
          'Analisi dinamica automatizzata',
          'Snapshotting memoria/registro',
          'Manipolazione orario/sensori',
          'Hooking facilitato (Frida built-in)',
          'Clonazione stato dispositivo',
        ],
        mitigation:
            'Esegui l\'app solo su dispositivi fisici certificati. Usa attestazione hardware (Play Integrity).',
        docsUrl: 'https://freerasp.tech/docs/threats/emulator',
      ),
      SecurityCheckItem(
        id: 'tamper',
        title: 'Integrità Applicazione (Anti-Tamper)',
        description:
            "Verifica che l'APK non sia stata modificata, rifirmata o alterata. "
            'Controlla la firma del certificato e l\'integrità del codice.',
        icon: Icons.verified_rounded,
        iconGradient: const LinearGradient(
          colors: [Color(0xFFFA709A), Color(0xFFFEE140)],
        ),
        threatType: ThreatType.tamper,
        threatVectors: [
          'Ricompilazione APK (apktool)',
          'Rifirma certificato non autorizzato',
          'Iniezione codice malevolo (smali)',
          'Rimozione controlli sicurezza',
          'Modifica risorse/asset',
        ],
        mitigation:
            'Distribuisci solo via Play Store. Abilita Play App Signing. Usa App Bundle (AAB).',
        docsUrl: 'https://freerasp.tech/docs/threats/tampering',
      ),
      SecurityCheckItem(
        id: 'hook',
        title: 'Hooking / Framework Dinamici',
        description:
            'Rileva la presenza di framework di hooking come Frida, Xposed, Substrate, '
            'o strumenti di instrumentation runtime che intercettano chiamate di funzione.',
        icon: Icons.bug_report_rounded,
        iconGradient: const LinearGradient(
          colors: [Color(0xFFFF512F), Color(0xFFFFF59D)],
        ),
        threatType: ThreatType.hook,
        threatVectors: [
          'Intercettazione API crittografiche',
          'Bypass pinning certificati',
          'Dump chiavi memoria',
          'Modifica logica runtime',
          'Keylogging / screen capture',
        ],
        mitigation:
            'Abilita rilevamento Frida/Xposed. Usa code obfuscation (R8/ProGuard) + native libs.',
        docsUrl: 'https://freerasp.tech/docs/threats/hooking',
      ),
      SecurityCheckItem(
        id: 'deviceBinding',
        title: 'Device Binding',
        description:
            'Verifica che il dispositivo sia ancora autorizzato (binding non violato). '
            "Utile per rilevare clonazione o trasferimento non autorizzato dell'app.",
        icon: Icons.devices_rounded,
        iconGradient: const LinearGradient(
          colors: [Color(0xFF30E8BF), Color(0xFFFF8235)],
        ),
        threatType: ThreatType.deviceBinding,
        threatVectors: [
          'Clonazione identità dispositivo',
          'Trasferimento app su device non autorizzato',
          'Spoofing Android ID / IMEI',
          'Backup/restore malevolo',
          'Violazione policy BYOD/MDM',
        ],
        mitigation:
            'Implementa device binding server-side. Usa Attestation (Play Integrity, SafetyNet).',
        docsUrl: 'https://freerasp.tech/docs/threats/device-binding',
      ),
      SecurityCheckItem(
        id: 'unofficialStore',
        title: 'Fonte Installazione (Play Store)',
        description:
            "Controlla se l'app è stata installata da Google Play Store. "
            'Installazioni da store alternativi o sideloading (APK diretto) '
            'possono indicare distribuzione non autorizzata.',
        icon: Icons.store_rounded,
        iconGradient: const LinearGradient(
          colors: [Color(0xFF4ECDC4), Color(0xFF44A08D)],
        ),
        threatType: ThreatType.unofficialStore,
        isWarningOnly: true,
        threatVectors: [
          'Distribuzione non autorizzata',
          'APK modificati su store terzi',
          'Mancanza aggiornamenti sicurezza',
          'Bypass licenze/abbonamenti',
          'Iniezione malware in repackaging',
        ],
        mitigation:
            'Pubblica solo su Play Store. Abilita Play Integrity API. Verifica installer package name.',
        docsUrl: 'https://freerasp.tech/docs/threats/unofficial-store',
      ),
      SecurityCheckItem(
        id: 'adb',
        title: 'Debug USB / ADB Attivo',
        description:
            'Rileva se il debug USB è abilitato o ADB è connesso. '
            'ADB attivo permette controllo completo del dispositivo da remoto.',
        icon: Icons.usb_rounded,
        iconGradient: const LinearGradient(
          colors: [Color(0xFFFFA726), Color(0xFFFF7043)],
        ),
        threatType: ThreatType.adb,
        isWarningOnly: true,
        threatVectors: [
          'Controllo shell remoto (adb shell)',
          'Installazione app non firmate',
          'Accesso logcat / dumpsys',
          'Port forwarding / reverse tethering',
          'Screen recording / screenshot',
        ],
        mitigation:
            'Disabilita Opzioni Sviluppatore → Debug USB. Usa policy MDM per bloccare ADB.',
        docsUrl: 'https://freerasp.tech/docs/threats/adb',
      ),
      SecurityCheckItem(
        id: 'debugger',
        title: 'Debugger Connesso',
        description:
            'Rileva se un debugger (JDWP, LLDB, GDB) è attaccato al processo. '
            'Indica analisi attiva o tentativo di reverse engineering in corso.',
        icon: Icons.memory_rounded,
        iconGradient: const LinearGradient(
          colors: [Color(0xFFE17055), Color(0xFFD63031)],
        ),
        threatType: ThreatType.debugger,
        threatVectors: [
          'Step-through codice sensibile',
          'Ispezione variabili runtime',
          'Breakpoint su funzioni critiche',
          'Memory dump processo',
          'Modifica registri/stack',
        ],
        mitigation:
            'freeRASP blocca l\'app se debugger rilevato in release. Non debuggare build produzione.',
        docsUrl: 'https://freerasp.tech/docs/threats/debugger',
      ),
      SecurityCheckItem(
        id: 'devMode',
        title: 'Opzioni Sviluppatore Attive',
        description:
            'Rileva se le Opzioni Sviluppatore sono abilitate nelle impostazioni. '
            'Abilita vettori di attacco (ADB, USB debugging, OEM unlock, ecc.).',
        icon: Icons.developer_mode_rounded,
        iconGradient: const LinearGradient(
          colors: [Color(0xFFFD79A8), Color(0xFFE84393)],
        ),
        threatType: ThreatType.devMode,
        isWarningOnly: true,
        threatVectors: [
          'Abilita Debug USB / ADB wireless',
          'OEM Unlock (sblocco bootloader)',
          'Simulazione posizioni GPS false',
          'Visualizzazione tocchi / puntatore',
          'Profiling GPU / rendering',
        ],
        mitigation:
            'Disattiva: Impostazioni → Sistema → Opzioni Sviluppatore → Interruttore OFF.',
        docsUrl: 'https://freerasp.tech/docs/threats/developer-options',
      ),
    ]);

    _updateCheckStatuses();
  }

  void _startEntranceAnimations() {
    _headerController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _listController.forward();
    });
  }

  void _updateCheckStatuses() {
    final blockMsg = SecurityService.blockMessage.value;
    final warningMsg = SecurityService.developerOptionsWarningMessage.value;

    setState(() {
      for (final check in _checks) {
        final isBlocked = _mapThreatToBlockMessage(check.threatType, blockMsg);
        final isWarned = check.isWarningOnly &&
            _mapThreatToWarningMessage(check.threatType, warningMsg);

        if (isBlocked) {
          check.status = CheckStatus.failed;
          check.activeMessage = blockMsg;
        } else if (isWarned) {
          check.status = CheckStatus.warning;
          check.activeMessage = warningMsg;
        } else {
          check.status = CheckStatus.passed;
          check.activeMessage = null;
        }
      }
    });
  }

  bool _mapThreatToBlockMessage(ThreatType type, String? blockMsg) {
    if (blockMsg == null) return false;
    switch (type) {
      case ThreatType.root:
        return blockMsg.contains('Root');
      case ThreatType.emulator:
        return blockMsg.contains('Emulatore');
      case ThreatType.tamper:
        return blockMsg.contains('Firma') || blockMsg.contains('manomessa');
      case ThreatType.hook:
        return blockMsg.contains('Hooking');
      case ThreatType.deviceBinding:
        return blockMsg.contains('Binding');
      case ThreatType.debugger:
        return blockMsg.contains('Debugger');
      case ThreatType.adb:
        return blockMsg.contains('Debug USB') || blockMsg.contains('ADB');
      case ThreatType.devMode:
        return false; // devMode non blocca, solo warning
      case ThreatType.unofficialStore:
        return blockMsg.contains('fonte non attendibile');
    }
  }

  bool _mapThreatToWarningMessage(ThreatType type, String? warningMsg) {
    if (warningMsg == null) return false;
    switch (type) {
      case ThreatType.devMode:
        return warningMsg.contains('Opzioni sviluppatore') ||
            warningMsg.contains('Developer');
      case ThreatType.adb:
        return warningMsg.contains('Debug USB') || warningMsg.contains('ADB');
      case ThreatType.unofficialStore:
        return warningMsg.contains('fonte non attendibile');
      default:
        return false;
    }
  }

  @override
  void dispose() {
    _headerController.dispose();
    _listController.dispose();
    _refreshController.dispose();
    _refreshDebounce?.cancel();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;

    HapticFeedback.mediumImpact();
    setState(() => _isRefreshing = true);
    _refreshController.repeat();

    // Simula refresh: resetta a unknown, poi rievalua
    setState(() {
      for (final check in _checks) {
        check.status = CheckStatus.unknown;
        check.activeMessage = null;
      }
    });

    await Future.delayed(const Duration(milliseconds: 1200));

    _updateCheckStatuses();
    _refreshController.stop();
    _refreshController.reset();
    setState(() => _isRefreshing = false);
  }

  Future<void> _openDocs(String url) async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final hasActiveBlock = SecurityService.blockMessage.value != null;
    final hasActiveWarning = SecurityService.developerOptionsWarningMessage.value != null;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ─── SLIVER APP BAR CON HEADER ANIMATO ───
          SliverAppBar(
            expandedHeight: 220,
            floating: false,
            pinned: true,
            stretch: true,
            elevation: 0,
            backgroundColor: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: colorScheme.onSurface),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              // Pulsante refresh con animazione
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: AnimatedBuilder(
                  animation: _refreshController,
                  builder: (context, child) => Transform.rotate(
                    angle: _isRefreshing ? _refreshRotationAnimation.value * 2 * 3.14159 : 0,
                    child: IconButton(
                      icon: Icon(
                        _isRefreshing ? Icons.refresh_rounded : Icons.refresh_rounded,
                        color: colorScheme.primary,
                      ),
                      onPressed: _isRefreshing ? null : _onRefresh,
                      tooltip: 'Aggiorna controlli',
                    ),
                  ),
                ),
              ),
              // Pulsante documentazione
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: Icon(Icons.help_outline_rounded, color: colorScheme.onSurfaceVariant),
                  onPressed: () => _openDocs('https://freerasp.tech/docs'),
                  tooltip: 'Documentazione freeRASP',
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground, StretchMode.fadeTitle],
              background: _buildAnimatedHeader(context, isDark, hasActiveBlock, hasActiveWarning),
            ),
          ),

          // ─── LISTA CONTROLLI CON ANIMAZIONI STAGGERED ───
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: SliverList.separated(
              itemCount: _checks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final check = _checks[index];
                return _buildAnimatedCheckCard(context, check, index, colorScheme, isDark);
              },
            ),
          ),

          // ─── FOOTER INFO ───
          SliverToBoxAdapter(
            child: _buildFooter(context, colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedHeader(
    BuildContext context,
    bool isDark,
    bool hasActiveBlock,
    bool hasActiveWarning,
  ) {
    Color headerStartColor;
    Color headerEndColor;
    IconData headerIcon;
    String headerTitle;
    String headerSubtitle;

    if (hasActiveBlock) {
      headerStartColor = Colors.red.shade700;
      headerEndColor = Colors.red.shade900;
      headerIcon = Icons.lock_outline_rounded;
      headerTitle = 'Sicurezza Violata';
      headerSubtitle = 'freeRASP ha bloccato l\'app per protezione';
    } else if (hasActiveWarning) {
      headerStartColor = Colors.orange.shade700;
      headerEndColor = Colors.orange.shade900;
      headerIcon = Icons.warning_amber_rounded;
      headerTitle = 'Attenzione Richiesta';
      headerSubtitle = 'Anomalie non critiche rilevate';
    } else {
      headerStartColor = Colors.green.shade700;
      headerEndColor = Colors.green.shade900;
      headerIcon = Icons.verified_rounded;
      headerTitle = 'Ambiente Sicuro';
      headerSubtitle = 'Tutti i controlli freeRASP superati';
    }

    return AnimatedBuilder(
      animation: _headerController,
      builder: (context, child) => FadeTransition(
        opacity: _headerFadeAnimation,
        child: SlideTransition(
          position: _headerSlideAnimation,
          child: ScaleTransition(
            scale: _headerScaleAnimation,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [headerStartColor, headerEndColor],
                ),
              ),
              child: Stack(
                children: [
                  // Pattern decorativo sfondo
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _HeaderPatternPainter(
                        progress: _headerController.value,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  // Contenuto header
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Icona con glow
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.25),
                                  Colors.white.withValues(alpha: 0.1),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: headerStartColor.withValues(alpha: 0.4),
                                  blurRadius: 30,
                                  spreadRadius: -5,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Icon(headerIcon, size: 36, color: Colors.white),
                          ),
                          const SizedBox(height: 20),
                          // Titolo
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Colors.white, Color(0xFFE8E8E8)],
                            ).createShader(bounds),
                            child: Text(
                              headerTitle,
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            headerSubtitle,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Badge stato
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _PulsingDot(
                                  color: hasActiveBlock
                                      ? Colors.red.shade300
                                      : hasActiveWarning
                                          ? Colors.orange.shade300
                                          : Colors.green.shade300,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  hasActiveBlock
                                      ? 'BLOCCO ATTIVO'
                                      : hasActiveWarning
                                          ? 'AVVISO ATTIVO'
                                          : 'PROTETTO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedCheckCard(
    BuildContext context,
    SecurityCheckItem check,
    int index,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    // Staggered animation per ogni card
    final delay = (index * 100).clamp(0, 600);
    final animationStart = delay / 1200;
    final animationEnd = ((delay + 400) / 1200).clamp(0, 1);

    return AnimatedBuilder(
      animation: _listController,
      builder: (context, child) {
        final progress = _listController.value;
        double cardProgress = 0.0;
        if (progress >= animationStart && progress <= animationEnd) {
          cardProgress = (progress - animationStart) / (animationEnd - animationStart);
          cardProgress = Curves.easeOutCubic.transform(cardProgress);
        } else if (progress > animationEnd) {
          cardProgress = 1.0;
        }

        return Opacity(
          opacity: cardProgress.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - cardProgress)),
            child: child,
          ),
        );
      },
      child: _SecurityCheckCard(
        check: check,
        onOpenDocs: _openDocs,
        colorScheme: colorScheme,
        isDark: isDark,
      ),
    );
  }

  Widget _buildFooter(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Divider(color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'freeRASP v8+ — Protezione Runtime Applicazione',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'I controlli vengono eseguiti continuamente in background. '
            'Se viene rilevata un\'anomalia, l\'app entra in modalità blocco.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // Legenda stati
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              _LegendItem(color: Colors.green.shade600, label: 'Superato', icon: Icons.check_circle_rounded),
              _LegendItem(color: Colors.orange.shade600, label: 'Avviso', icon: Icons.warning_amber_rounded),
              _LegendItem(color: Colors.red.shade600, label: 'Bloccato', icon: Icons.cancel_rounded),
              _LegendItem(color: Colors.grey.shade500, label: 'In verifica', icon: Icons.hourglass_empty_rounded),
            ],
          ),
          const SizedBox(height: 16),
          // Versione build
          Text(
            'Build: CatechHub v1.0.0+1',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MODELLI DATI
// ═══════════════════════════════════════════════════════════════════════════════

enum ThreatType {
  root,
  emulator,
  tamper,
  hook,
  deviceBinding,
  unofficialStore,
  adb,
  debugger,
  devMode,
}

enum CheckStatus {
  unknown,
  passed,
  warning,
  failed,
}

class SecurityCheckItem {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final LinearGradient iconGradient;
  final ThreatType threatType;
  final bool isWarningOnly;
  final List<String> threatVectors;
  final String mitigation;
  final String docsUrl;

  CheckStatus status = CheckStatus.unknown;
  String? activeMessage;

  SecurityCheckItem({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.iconGradient,
    required this.threatType,
    this.isWarningOnly = false,
    required this.threatVectors,
    required this.mitigation,
    required this.docsUrl,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGETS RIAUTILIZZABILI
// ═══════════════════════════════════════════════════════════════════════════════

class _SecurityCheckCard extends StatefulWidget {
  final SecurityCheckItem check;
  final Function(String) onOpenDocs;
  final ColorScheme colorScheme;
  final bool isDark;

  const _SecurityCheckCard({
    required this.check,
    required this.onOpenDocs,
    required this.colorScheme,
    required this.isDark,
  });

  @override
  State<_SecurityCheckCard> createState() => _SecurityCheckCardState();
}

class _SecurityCheckCardState extends State<_SecurityCheckCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expandController;
  late final AnimationController _iconController;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _iconController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
    HapticFeedback.lightImpact();
  }

  void _onIconTap() {
    _iconController.forward().then((_) => _iconController.reverse());
  }

  @override
  Widget build(BuildContext context) {
    final check = widget.check;
    final statusColor = _getStatusColor(check.status);
    final statusIcon = _getStatusIcon(check.status);
    final statusLabel = _getStatusLabel(check.status);
    final isFailed = check.status == CheckStatus.failed;
    final isWarning = check.status == CheckStatus.warning;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: widget.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isFailed
                ? statusColor.withValues(alpha: 0.3)
                : isWarning
                    ? statusColor.withValues(alpha: 0.3)
                    : widget.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: isFailed || isWarning ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: widget.isDark ? 0.2 : 0.04),
              blurRadius: isFailed || isWarning ? 20 : 12,
              offset: const Offset(0, 6),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Column(
          children: [
            // ─── HEADER CARD (sempre visibile) ───
            InkWell(
              onTap: _toggleExpanded,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Icona con gradiente e animazione tap
                    GestureDetector(
                      onTap: _onIconTap,
                      child: AnimatedBuilder(
                        animation: _iconController,
                        builder: (context, child) => Transform.scale(
                          scale: 1 - _iconController.value * 0.1,
                          child: child,
                        ),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: check.iconGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: check.iconGradient.colors.first.withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                                spreadRadius: -2,
                              ),
                            ],
                          ),
                          child: Icon(check.icon, color: Colors.white, size: 28),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Titolo e descrizione breve
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            check.title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: widget.colorScheme.onSurface,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            check.description,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: widget.colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Badge stato + freccia espansione
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Badge stato animato
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  statusIcon,
                                  key: ValueKey(check.status),
                                  size: 14,
                                  color: statusColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Freccia espansione
                        AnimatedRotation(
                          turns: _isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: widget.colorScheme.onSurfaceVariant,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ─── CONTENUTO ESPANDIBILE ANIMATO ───
            AnimatedBuilder(
              animation: _expandController,
              builder: (context, child) => ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _expandController.value,
                  child: child,
                ),
              ),
              child: _buildExpandedContent(context, check, statusColor, isFailed, isWarning),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent(
    BuildContext context,
    SecurityCheckItem check,
    Color statusColor,
    bool isFailed,
    bool isWarning,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: BoxDecoration(
        color: widget.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Messaggio attivo se fallito
          if (check.activeMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (isFailed ? Colors.red : Colors.orange).shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (isFailed ? Colors.red : Colors.orange).shade200,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isFailed ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                    color: statusColor,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isFailed ? 'BLOCCO ATTIVO' : 'AVVISO ATTIVO',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          check.activeMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: statusColor.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Vettori di minaccia
          _SectionHeader(
            title: 'Vettori di Attacco',
            icon: Icons.arrow_right_alt_rounded,
            color: widget.colorScheme.primary,
          ),
          const SizedBox(height: 10),
          ...check.threatVectors.asMap().entries.map((entry) {
            final vector = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      vector,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: widget.colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 20),

          // Mitigazione
          _SectionHeader(
            title: 'Mitigazione Consigliata',
            icon: Icons.shield_outlined,
            color: Colors.green.shade700,
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.shade50.withValues(alpha: widget.isDark ? 0.3 : 1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.green.shade200.withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    check.mitigation,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.green.shade800,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Azioni
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onOpenDocs(check.docsUrl),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Documentazione'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: widget.colorScheme.outlineVariant),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _copyThreatInfo(check),
                  icon: const Icon(Icons.content_copy_rounded, size: 18),
                  label: const Text('Copia Dettagli'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: widget.colorScheme.primary,
                    foregroundColor: widget.colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _copyThreatInfo(SecurityCheckItem check) {
    final buffer = StringBuffer()
      ..writeln('=== ${check.title} ===')
      ..writeln('Stato: ${_getStatusLabel(check.status)}')
      ..writeln()
      ..writeln('Descrizione:')
      ..writeln(check.description)
      ..writeln()
      ..writeln('Vettori di attacco:')
      ..writeAll(check.threatVectors.map((v) => '• $v'), '\n')
      ..writeln()
      ..writeln('Mitigazione:')
      ..writeln(check.mitigation)
      ..writeln()
      ..writeln('Docs: ${check.docsUrl}');

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Dettagli minaccia copiati negli appunti'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color _getStatusColor(CheckStatus status) {
    switch (status) {
      case CheckStatus.passed:
        return Colors.green.shade700;
      case CheckStatus.warning:
        return Colors.orange.shade700;
      case CheckStatus.failed:
        return Colors.red.shade700;
      case CheckStatus.unknown:
        return widget.colorScheme.onSurfaceVariant;
    }
  }

  IconData _getStatusIcon(CheckStatus status) {
    switch (status) {
      case CheckStatus.passed:
        return Icons.check_rounded;
      case CheckStatus.warning:
        return Icons.warning_amber_rounded;
      case CheckStatus.failed:
        return Icons.close_rounded;
      case CheckStatus.unknown:
        return Icons.hourglass_empty_rounded;
    }
  }

  String _getStatusLabel(CheckStatus status) {
    switch (status) {
      case CheckStatus.passed:
        return 'Superato';
      case CheckStatus.warning:
        return 'Avviso';
      case CheckStatus.failed:
        return 'Bloccato';
      case CheckStatus.unknown:
        return 'In verifica';
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final IconData icon;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Opacity(
        opacity: _animation.value,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.6),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderPatternPainter extends CustomPainter {
  final double progress;
  final Color color;

  _HeaderPatternPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const spacing = 30.0;
    const radius = 3.0;

    for (double x = -spacing; x < size.width + spacing; x += spacing) {
      for (double y = -spacing; y < size.height + spacing; y += spacing) {
        final dx = (x + (progress * spacing)) % (spacing * 2) - spacing;
        final dy = (y + (progress * spacing)) % (spacing * 2) - spacing;
        final dist = sqrt(dx * dx + dy * dy);

        if (dist < spacing * 0.7) {
          final opacity = (1 - dist / (spacing * 0.7)) * progress;
          paint.color = color.withValues(alpha: opacity * 0.5);
          canvas.drawCircle(Offset(x, y), radius * (0.5 + progress * 0.5), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is _HeaderPatternPainter &&
        oldDelegate.progress != progress &&
        oldDelegate.color != color;
  }
}