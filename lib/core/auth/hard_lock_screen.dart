// ══════════════════════════════════════════════════════════════════════════════
// hard_lock_screen.dart — CatechHub (Schermata blocco obbligatoria: niente lockscreen telefono = niente app)
// 
// Widget NON CHIUDIBILE (barrierDismissible: false) che blocca completamente l'app
// se il dispositivo NON ha un blocco schermo attivo (PIN, pattern, password, biometria).
//
// LOGICA:
// - Viene mostrato PRIMA di qualsiasi autenticazione (all'avvio app, in main.dart)
// - Verifica: AuthService.hasSecureLockScreen() → false = dispositivo insicuro
// - L'utente DEVE andare in Impostazioni > Sicurezza e impostare un blocco schermo
// - Pulsante "Apri Impostazioni Sicurezza" lancia intent nativo Android
// - Nessun bypass, nessun "continua comunque", nessun pulsante indietro
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';

/// Schermata di blocco totale (hard lock) per dispositivi senza sicurezza.
/// Non è chiudibile, non ha pulsante indietro, non ha drawer.
/// L'unico modo per procedere è impostare un blocco schermo sul telefono.
class HardLockScreen extends StatefulWidget {
  /// Callback opzionale per notificare quando l'utente ha configurato il lockscreen
  /// e l'app può riprovare la verifica.
  final VoidCallback? onRetry;

  const HardLockScreen({super.key, this.onRetry});

  @override
  State<HardLockScreen> createState() => _HardLockScreenState();
}

class _HardLockScreenState extends State<HardLockScreen> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  bool _isChecking = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Controllo iniziale e periodico
    _checkLockScreen();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkLockScreen() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);

    try {
      final authService = AuthService();
      final hasLock = await authService.hasSecureLockScreen();

      if (hasLock && mounted) {
        widget.onRetry?.call();
        return;
      }

      if (mounted) {
        setState(() => _isChecking = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _lastError = 'Errore verifica sicurezza: $e';
        });
      }
    }
  }

  /// Apre le impostazioni di sicurezza per configurare il blocco schermo.
  Future<void> _openSecuritySettings() async {
    if (Platform.isAndroid) {
      try {
        const MethodChannel channel = MethodChannel('catechhub/security_settings');
        await channel.invokeMethod('openSecuritySettings');
      } catch (e) {
        _showSettingsError(e);
      }
    } else {
      try {
        final uri = Uri.parse('app-settings:');
        final launched = await launchUrl(uri);
        if (!launched && mounted) {
          _showSettingsError('Impossibile aprire le impostazioni iOS');
        }
      } catch (e) {
        _showSettingsError(e);
      }
    }
  }

  void _showSettingsError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Impossibile aprire le impostazioni: $error'),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // WillPopScope / PopScope per impedire il tasto indietro sistema
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          // Ignora il back button - l'app non si chiude
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icona animata pulsante
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) => Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.red.shade200, width: 3),
                      ),
                      child: Icon(
                        Icons.security_rounded,
                        size: 60,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Titolo
                Text(
                  'Sicurezza Dispositivo Richiesta',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: 16),

                // Messaggio principale
                Text(
                  'CatechHub protegge dati sensibili di minori '
                  '(anagrafica, allergie, contatti genitori, presenze).\n\n'
                  'Per funzionare, l\'app richiede che il tuo telefono abbia '
                  'un BLOCCO SCHERMO ATTIVO:\n'
                  '• PIN numerico\n'
                  '• Pattern (sequenza punti)\n'
                  '• Password alfanumerica\n'
                  '• Impronta digitale / Riconoscimento facciale\n\n'
                  'Attualmente il tuo dispositivo NON HA nessun blocco schermo configurato.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF333333),
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 24),

                // Box informativo
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber.shade200, width: 1.5),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: Colors.amber.shade800, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Perché è obbligatorio?',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Senza blocco schermo, CHIUNQUE prenda in mano il tuo telefono '
                        'può aprire CatechHub e vedere TUTTI i dati dei bambini. '
                        'Android non permette l\'autenticazione biometrica/PIN nativa '
                        'se non hai prima impostato un blocco schermo.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.amber.shade800,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Pulsante principale: Apri Impostazioni Sicurezza
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _isChecking ? null : _openSecuritySettings,
                    icon: _isChecking
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.settings_rounded, size: 26),
                    label: Text(
                      _isChecking ? 'Verifica in corso...' : 'Apri Impostazioni Sicurezza',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF174A7E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Pulsante secondario: Riprova (dopo aver impostato il lockscreen)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _isChecking ? null : _checkLockScreen,
                    icon: const Icon(Icons.refresh_rounded, size: 22),
                    label: const Text(
                      'Ho impostato il blocco schermo → Verifica',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF174A7E),
                      side: const BorderSide(color: Color(0xFF174A7E), width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),

                if (_lastError != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _lastError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],

                const SizedBox(height: 40),

                // Footer
                Text(
                  'CatechHub · Registro Catechistico Sicuro\n'
                  'I dati non lasciano mai questo dispositivo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget wrapper che mostra HardLockScreen se il dispositivo non è sicuro,
/// altrimenti mostra il child (login page o app principale).
/// Da usare in main.dart come root del MaterialApp o nel router.
class HardLockGuard extends StatefulWidget {
  final Widget child;
  final Duration checkInterval;

  const HardLockGuard({
    super.key,
    required this.child,
    this.checkInterval = const Duration(seconds: 5),
  });

  @override
  State<HardLockGuard> createState() => _HardLockGuardState();
}

class _HardLockGuardState extends State<HardLockGuard> {
  bool _showHardLock = false;
  bool _initialCheckDone = false;

  @override
  void initState() {
    super.initState();
    _performInitialCheck();
  }

  Future<void> _performInitialCheck() async {
    final authService = AuthService();
    final hasLock = await authService.hasSecureLockScreen();

    if (mounted) {
      setState(() {
        _showHardLock = !hasLock;
        _initialCheckDone = true;
      });
    }
  }

  void _onRetry() {
    _performInitialCheck();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialCheckDone) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 3),
              SizedBox(height: 16),
              Text(
                'Verifica sicurezza dispositivo...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    if (_showHardLock) {
      return HardLockScreen(onRetry: _onRetry);
    }

    return widget.child;
  }
}