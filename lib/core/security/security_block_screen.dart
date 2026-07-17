// ═══════════════════════════════════════════════════════════════════════════════
// security_block_screen.dart — CatechHub (Schermata Blocco Sicurezza freeRASP)
// ═══════════════════════════════════════════════════════════════════════════════
//
// SCHERMATA DI BLOCCO SICUREZZA — REQUISITI UI MIGLIORATI:
// ──────────────────────────────────────────────────────────────────────────────
// Quando freeRASP rileva un'anomalia (root, emulator, tamper, hook, device binding),
// l'app NON chiude con SystemNavigator.pop ma mostra QUESTA schermata fissa:
// ──────────────────────────────────────────────────────────────────────────────
// • SFONDO: Gradient rosso intenso (Colors.red.shade900 → shade800 → shade700)
// • ANIMAZIONE ENTRATA: Fade-in + Scale + Shake per il lucchetto (AnimationController)
// • ICONA CENTRALE: Lucchetto bianco (Icons.lock_outline) con animazione shake
//   + alone pulse sottile + ombra profonda per profondità
// • TITOLO: "Sicurezza Violata" - Bianco, 24sp, bold, ombra per leggibilità
// • MESSAGGIO SPECIFICO: Nero chiaro leggibile (Colors.black87), 17sp, centrato,
//   padding 32, max 3 righe, textAlign.center (es. "Root rilevato", "Emulatore non consentito",
//   "Firma dell'applicazione manomessa", "Tentativo di Hooking", "Binding dispositivo violato")
// • CARD DETTAGLI ROSSA: Card rossa scura semitrasparente con border radius 16,
//   contenente spiegazione del rischio specifico per tipo di minaccia
// • LAYOUT: Center + Column(mainAxisAlignment: center) + SingleChildScrollView
// • SAFE AREA: SafeArea per evitare notch/gesture bar
// • IMMERSIVE: SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)
//   per nascondere status/nav bar e impedire swipe accidentali
// • BLOCCO NAVIGAZIONE: PopScope con canPop: false + callback onPopInvoked
// • NO SYSTEM NAVIGATOR POP: L'app NON chiude, rimane bloccata su questa schermata
// • INDICATORE STATO: Pulsante animato "Contatta Supporto" (mailto: security@...)
// • ACCESSIBILITÀ: SemanticLabel, screen reader, contrasti WCAG AA
// ──────────────────────────────────────────────────────────────────────────────
//
// INTEGRAZIONE IN main.dart:
// ──────────────────────────────────────────────────────────────────────────────
// class MyApp extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return ValueListenableBuilder<String?>(
//       valueListenable: SecurityService.blockMessage,
//       builder: (_, blockMsg, __) {
//         if (blockMsg != null) {
//           return MaterialApp(
//             home: SecurityBlockScreen(message: blockMsg),
//           );
//         }
//         return MaterialApp(home: MyHomePage());
//       },
//     );
//   }
// }
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Schermata di blocco sicurezza mostrata quando freeRASP rileva un'anomalia.
///
/// Caratteristiche UI migliorate:
/// - Sfondo gradient rosso con pattern decorativo
/// - Animazioni di entrata fluide (fade, scale, shake)
/// - Icona lucchetto animata con shake + pulse
/// - Titolo "Sicurezza Violata" prominente
/// - Messaggio specifico della minaccia
/// - Card esplicativa rossa con dettagli per tipo di minaccia
/// - Pulsante "Contatta Supporto" con mailto
/// - Immersive mode, blocco navigazione, accessibilità completa
class SecurityBlockScreen extends StatefulWidget {
  /// Messaggio specifico del problema rilevato da freeRASP.
  /// Esempi: "Root rilevato", "Emulatore non consentito",
  /// "Firma dell'applicazione manomessa", "Tentativo di Hooking",
  /// "Binding dispositivo violato"
  final String message;

  /// Costruttore costante per rebuild efficienti.
  const SecurityBlockScreen({
    super.key,
    required this.message,
  });

  @override
  State<SecurityBlockScreen> createState() => _SecurityBlockScreenState();
}

class _SecurityBlockScreenState extends State<SecurityBlockScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _scaleController;
  late final AnimationController _shakeController;
  late final AnimationController _pulseController;

  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _shakeAnimation;
  late final Animation<double> _pulseAnimation;

  Timer? _shakeTimer;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _scaleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );
    _shakeAnimation = Tween<double>(begin: -1.0, end: 1.0).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Avvia animazioni in sequenza
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 100), () => _scaleController.forward());
    Future.delayed(const Duration(milliseconds: 500), () => _startShakeLoop());

    // Attiva immersive sticky mode per nascondere system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  void _startShakeLoop() {
    _shakeTimer?.cancel();
    _shakeTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _shakeController.forward(from: 0);
      }
    });
    // Primo shake dopo 500ms
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _shakeController.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _shakeController.dispose();
    _pulseController.dispose();
    _shakeTimer?.cancel();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
    super.dispose();
  }

  Future<void> _contactSupport() async {
    HapticFeedback.heavyImpact();

    final threatDetail = _getThreatDetail(widget.message);

    final buffer = StringBuffer()
      ..writeln('--- SEGNALAZIONE SICUREZZA CatechHub ---')
      ..writeln()
      ..writeln('PROBLEMA RILEVATO:')
      ..writeln('  ${threatDetail.title}')
      ..writeln('  Messaggio: ${widget.message}')
      ..writeln()
      ..writeln('DESCRIZIONE:')
      ..writeln('  ${threatDetail.description}')
      ..writeln()
      ..writeln('IMPATTO:')
      ..writeln('  ${threatDetail.impact}')
      ..writeln()
      ..writeln('SOLUZIONE CONSIGLIATA:')
      ..writeln('  ${threatDetail.solution}')
      ..writeln()
      ..writeln('--- DESCRIZIONE UTENTE ---')
      ..writeln()
      ..writeln('(descrivi qui cosa stavi facendo quando hai ricevuto l\'avviso)')
      ..writeln();

    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'catechhub.app@proton.me',
      queryParameters: {
        'subject': 'Segnalazione Sicurezza CatechHub - ${widget.message}',
        'body': buffer.toString(),
      },
    );
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final threatDetail = _getThreatDetail(widget.message);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Feedback aptico per indicare che il back è bloccato
        HapticFeedback.heavyImpact();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFB71C1C), // red.shade900
                Color(0xFFC62828), // red.shade800
                Color(0xFFD32F2F), // red.shade700
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: MediaQuery.of(context).padding.top + 20,
                  bottom: MediaQuery.of(context).padding.bottom + 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const SizedBox(height: 16),

                        // ─── ICONA LUCCHETTO ANIMATA (SCALE + SHAKE + PULSE) ───
                        AnimatedBuilder(
                          animation: Listenable.merge([_scaleController, _shakeController, _pulseController]),
                          builder: (context, child) => Transform.scale(
                            scale: _scaleAnimation.value * _pulseAnimation.value,
                            child: Transform.translate(
                              offset: Offset(_shakeAnimation.value * 8, 0),
                              child: Container(
                                width: 110,
                                height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8),
                                    spreadRadius: -4,
                                  ),
                                  BoxShadow(
                                    color: Colors.red.shade900.withValues(alpha: 0.5),
                                    blurRadius: 40,
                                    offset: const Offset(0, 16),
                                    spreadRadius: -8,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.lock_outline_rounded,
                                size: 96,
                                color: Colors.white,
                                semanticLabel: 'Blocco sicurezza attivo',
                              ),
                            ),
                          ),
                        ),
                        ),
                        
                        const SizedBox(height: 28),

                        // ─── TITOLO "SICUREZZA VIOLATA" ───
                        Text(
                          'Sicurezza Violata',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            letterSpacing: 0.5,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                offset: const Offset(0, 2),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ─── MESSAGGIO SPECIFICO MINACCIA ───
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            widget.message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                              letterSpacing: 0.2,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        const SizedBox(height: 32),

                        // ─── CARD DETTAGLIO MINACCIA (ROSSA SCURA SEMITRASPARENTE) ───
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                                spreadRadius: -2,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      threatDetail.icon,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      threatDetail.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                threatDetail.description,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  height: 1.6,
                                  letterSpacing: 0.1,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                threatDetail.impact,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ─── CARD SOLUZIONE (VERDE SCURO SEMITRASPARENTE) ───
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Color(0xFF1B5E20).withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.3),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                                spreadRadius: -2,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.lightbulb_outline_rounded,
                                      color: Colors.greenAccent,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'Potenziale Soluzione',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                threatDetail.solution,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  height: 1.6,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // ─── PULSANTE CONTATTA SUPPORTO ───
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _contactSupport,
                            icon: const Icon(Icons.email_outlined, size: 20),
                            label: const Text(
                              'Contatta Supporto Sicurezza',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.6),
                                width: 1.5,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ─── ETICHETTA APP ───
                        Text(
                          'CatechHub — Sicurezza Attiva',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  _ThreatDetail _getThreatDetail(String message) {
    final lower = message.toLowerCase();

    if (lower.contains('root')) {
      return _ThreatDetail(
        icon: Icons.warning_amber_rounded,
        title: 'Accesso Root Rilevato',
        description:
            'Il dispositivo ha permessi di root (Magisk, KernelSU, SuperSU). '
            'Questo permette a app malintenzionate di leggere la memoria dell\'app, '
            'estrarre chiavi crittografiche, e bypassare i controlli di sicurezza.',
        impact: 'IMPATTO: Accesso completo a dati sensibili minori',
        solution:
            'Rimuovi il root dal dispositivo (es. tramite app Magisk -> Disinstalla completo, '
            'o ripristina il firmware originale con un flash ufficiale). '
            'Se il root è necessario, utilizza l\'elenco di esclusione (DenyList) di Magisk '
            'per CatechHub nelle impostazioni Magisk.',
      );
    }
    if (lower.contains('emulatore') || lower.contains('emulator')) {
      return _ThreatDetail(
        icon: Icons.phone_android_outlined,
        title: 'Esecuzione su Emulatore',
        description:
            'L\'app sta girando su un emulatore Android (non dispositivo fisico). '
            'Gli emulatori permettono ispezione memoria completa, snapshot, '
            'e manipolazione runtime non rilevabile su device reali.',
        impact: 'IMPATTO: Ambiente non attendibile per dati sensibili',
        solution:
            'Avvia l\'app esclusivamente su un dispositivo fisico Android. '
            'Se stai usando l\'app in un ambiente di sviluppo, utilizza un '
            'dispositivo fisico collegato via USB per il debug.',
      );
    }
    if (lower.contains('firma') || lower.contains('manomess') || lower.contains('tamper') || lower.contains('integrit')) {
      return _ThreatDetail(
        icon: Icons.broken_image_outlined,
        title: 'Integrità Applicazione Compromessa',
        description:
            'La firma dell\'APK è stata modificata o il codice è stato alterato. '
            'Questo indica che l\'app è stata ricompilata, decompilata/ricompilata, '
            'o iniettata con codice malevolo (es. spyware, keylogger).',
        impact: 'IMPATTO: Codice non verificabile, possibile data exfiltration',
        solution:
            'Disinstalla immediatamente l\'app e reinstalla dal Google Play Store ufficiale. '
            'Non scaricare APK da fonti non ufficiali. '
            'Se il problema persiste, contatta il supporto per verificare la firma.',
      );
    }
    if (lower.contains('hook') || lower.contains('frida') || lower.contains('xposed')) {
      return _ThreatDetail(
        icon: Icons.bug_report_outlined,
        title: 'Framework Hooking Rilevato',
        description:
            'È stato rilevato un framework di hooking (Frida, Xposed, Substrate, '
            'Dobby). Questi permettono l\'intercettazione di chiamate di funzione, '
            'modifica valori in memoria, e bypass controlli di sicurezza runtime.',
        impact: 'IMPATTO: Controllo completo dell\'esecuzione app',
        solution:
            'Disinstalla completamente il framework di hooking (Xposed, Frida, etc.) '
            'dal dispositivo. Se utilizzi un modding personalizzato, ripristina '
            'il firmware originale senza modifiche ai framework runtime.',
      );
    }
    if (lower.contains('binding') || lower.contains('device binding')) {
      return _ThreatDetail(
        icon: Icons.link_off_outlined,
        title: 'Device Binding Violato',
        description:
            'Il binding crittografico del dispositivo è stato violato. '
            'Questo significa che i dati dell\'app sono stati copiati su un altro '
            'dispositivo o l\'identità hardware è stata falsificata (spoofing).',
        impact: 'IMPATTO: Clonazione identità dispositivo, accesso non autorizzato',
        solution:
            'Contatta il supporto per ri-autenticare il dispositivo. '
            'Potrebbe essere necessario riaccedere all\'account e registrare '
            'nuovamente il dispositivo. Non tentare di clonare o trasferire '
            'i dati dell\'app tra dispositivi.',
      );
    }
    if (lower.contains('debug') || lower.contains('adb')) {
      return _ThreatDetail(
        icon: Icons.usb_outlined,
        title: 'Debug USB / ADB Attivo',
        description:
            'Il debug USB è abilitato e/o un debugger è connesso (ADB). '
            'Questo permette ispezione memoria, installazione app non firmate, '
            'estrazione database, e bypass controlli runtime.',
        impact: 'IMPATTO: Superficie d\'attacco ampliata, rischio data leak',
        solution:
            'Disattiva il Debug USB dalle Impostazioni Sviluppatore: '
            'Impostazioni -> Opzioni Sviluppatore -> Debug USB -> Disattiva. '
            'Se non hai bisogno di sviluppo, disattiva completamente le '
            'Opzioni Sviluppatore dal menu Impostazioni.',
      );
    }

    // Default generico
    return _ThreatDetail(
      icon: Icons.security_outlined,
      title: 'Anomalia Sicurezza Rilevata',
      description:
          'freeRASP ha rilevato un\'anomalia che compromette l\'integrità '
          'dell\'ambiente di esecuzione. L\'app non può garantire la sicurezza '
          'dei dati sensibili in queste condizioni.',
      impact: 'IMPATTO: Protezione dati non garantita',
      solution:
          'Contatta il supporto tecnico per assistenza. '
          'Fornisci i dettagli del dispositivo e il messaggio di errore.',
    );
  }
}

/// Dettaglio specifico per tipo di minaccia.
class _ThreatDetail {
  final IconData icon;
  final String title;
  final String description;
  final String impact;
  final String solution;

  const _ThreatDetail({
    required this.icon,
    required this.title,
    required this.description,
    required this.impact,
    required this.solution,
  });
}