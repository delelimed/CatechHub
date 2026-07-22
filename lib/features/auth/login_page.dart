// ══════════════════════════════════════════════════════════════════════════════
// login_page.dart — CatechHub (Login SOLO biometrico nativo / profilo iniziale)
// 
// FLUSSO:
// 1. App avviata → controlla isProfileConfigured
// 2. Se NON configurato → Form profilo (nome, cognome, gruppo) → setupInitialProfile → sblocca
// 3. Se configurato → Verifica hasSecureLockScreen()
//    - Se FALSE → HardLockScreen (bloccante, non chiudibile)
//    - Se TRUE → Mostra pulsante "Accedi con Impronta/Faccia/PIN Telefono"
// 4. Tap pulsante → unlockWithBiometrics() (biometricOnly: false = fallback PIN telefono)
// 5. Successo → Home
//
// NESSUN PIN app. NESSUN campo PIN. Solo biometria nativa Android.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bible_quote.dart';
import '../../core/auth/auth_provider.dart';

/// Animated gradient background with flowing colors
class _AnimatedGradientBackground extends StatefulWidget {
  final Widget child;

  const _AnimatedGradientBackground({required this.child});

  @override
  State<_AnimatedGradientBackground> createState() => _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<_AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final angle = lerpDouble(-0.3, 0.3, t)!;
        final begin = Alignment(sin(angle * pi), -cos(angle * pi));
        final end = Alignment(-sin(angle * pi), cos(angle * pi));

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: const [
                Color(0xFF174A7E), // Dark blue
                Color(0xFF2A6BB0), // Medium blue
                Color(0xFF4A90D9), // Light blue
                Color(0xFF7AB8F0), // Lighter blue
                Color(0xFFA8D0E6), // Soft cyan
              ],
              stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              begin: begin,
              end: end,
              transform: GradientRotation(angle * pi / 2),
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

/// Schermata di accesso principale - SOLO autenticazione nativa dispositivo.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  late final BibleQuote randomQuote;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _groupController = TextEditingController();

  bool _isFirstSetup = false;
  bool _hasSecureLockScreen = false;
  bool _checkedLockScreen = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    randomQuote = bibleQuotes[Random().nextInt(bibleQuotes.length)];

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authService = ref.read(authServiceProvider);
      final isConfigured = authService.isProfileConfigured;
      debugPrint('Login initState - Profilo configurato: $isConfigured');

      if (!isConfigured) {
        if (mounted) setState(() => _isFirstSetup = true);
        return;
      }

      // Profilo esiste: verifica se il dispositivo ha lockscreen attivo
      final hasLock = await authService.hasSecureLockScreen();
      debugPrint('Login initState - Lockscreen attivo: $hasLock');

      if (mounted) {
        setState(() {
          _hasSecureLockScreen = hasLock;
          _checkedLockScreen = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _groupController.dispose();
    super.dispose();
  }

  Future<void> _handleBiometricUnlock() async {
    HapticFeedback.mediumImpact();
    setState(() => _errorMessage = null);

    final auth = ref.read(authStateProvider.notifier);
    final ok = await auth.unlockWithBiometrics();

    if (!ok && mounted) {
      setState(() {
        _errorMessage = 'Autenticazione non riuscita. Riprova.';
      });
    }
  }

  Future<void> _handleSetupProfile() async {
    HapticFeedback.mediumImpact();
    setState(() => _errorMessage = null);

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final groupName = _groupController.text.trim();

    if (firstName.isEmpty || lastName.isEmpty || groupName.isEmpty) {
      setState(() => _errorMessage = 'Nome, cognome e gruppo sono obbligatori.');
      return;
    }

    final auth = ref.read(authStateProvider.notifier);
    final ok = await auth.setupInitialProfile(
      firstName: firstName,
      lastName: lastName,
      groupName: groupName,
    );

    if (!ok && mounted) {
      setState(() => _errorMessage = 'Errore durante la configurazione. Riprova.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading;

    // Se già sbloccato, non dovremmo essere qui (router gestisce redirect)
    // Ma per sicurezza mostriamo loading
    if (isLoading) {
      return _buildLoadingScreen();
    }

    return Scaffold(
      body: _AnimatedGradientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Card(
                  elevation: 12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/logo.png',
                          height: 120,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.menu_book, size: 80),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'CatechHub',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF174A7E),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '"${randomQuote.text}"',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontStyle: FontStyle.italic,
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Contenuto dinamico in base allo stato
                        if (_isFirstSetup) ...[
                          _buildFirstSetupForm(isLoading),
                        ] else if (!_checkedLockScreen) ...[
                          _buildCheckingLockScreen(),
                        ] else if (!_hasSecureLockScreen) ...[
                          // HARD LOCK SCREEN - Non chiudibile, non bypassabile
                          const HardLockScreen(),
                        ] else ...[
                          _buildUnlockForm(isLoading),
                        ],

                        const SizedBox(height: 20),
                        const Text(
                          'Realizzato con ❤️\n da un catechista per i catechisti',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey),
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

  Widget _buildLoadingScreen() {
    return Scaffold(
      body: _AnimatedGradientBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(strokeWidth: 3),
                SizedBox(height: 18),
                Text(
                  'Sto caricando il profilo...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckingLockScreen() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        const CircularProgressIndicator(strokeWidth: 3),
        const SizedBox(height: 16),
        const Text(
          'Verifica sicurezza dispositivo...',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF174A7E),
          ),
        ),
      ],
    );
  }

  Widget _buildFirstSetupForm(bool isLoading) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Crea il tuo profilo',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF174A7E),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'L\'app usa il blocco schermo del tuo telefono (impronta, volto, PIN) '
          'per proteggere i dati. Non serve creare un PIN separato.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 24),
        if (!isLoading) ...[
          _buildTextField(_firstNameController, 'Nome', Icons.person),
          const SizedBox(height: 12),
          _buildTextField(_lastNameController, 'Cognome', Icons.person_outline),
          const SizedBox(height: 12),
          _buildTextField(_groupController, 'Gruppo / Parrocchia', Icons.groups),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _handleSetupProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Crea profilo e accedi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ] else ...[
          const SizedBox(
            height: 150,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Creazione profilo in corso...'),
                ],
              ),
            ),
          ),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _buildErrorMessage(_errorMessage!),
        ],
      ],
    );
  }

  Widget _buildUnlockForm(bool isLoading) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Sblocca Registro',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF174A7E),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Usa l\'impronta digitale, il riconoscimento facciale '
          'o il PIN/Pattern del tuo telefono.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF174A7E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: isLoading ? null : _handleBiometricUnlock,
            icon: const Icon(Icons.fingerprint, size: 28),
            label: const Text(
              'Accedi con impronta / volto / PIN telefono',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (isLoading)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SizedBox(
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _buildErrorMessage(_errorMessage!),
        ],
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: const Color(0xFF174A7E)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildErrorMessage(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// ══════════════════════════════════════════════════════════════════════════════
/// HARD LOCK SCREEN - Schermata BLOCCANTE non chiudibile
///
/// Mostrata quando il dispositivo NON ha alcun blocco schermo configurato
/// (niente PIN, niente pattern, niente password, niente biometria).
///
/// L'app NON può funzionare senza sicurezza del dispositivo attiva perché:
/// - I dati degli studenti (minori) sono sensibili
/// - La biometria nativa richiede un lockscreen di base (KeyguardManager)
/// - Senza lockscreen, chiunque prenda il telefono accede a tutto
///
/// L'utente DEVE andare in Impostazioni → Sicurezza e attivare un blocco.
/// Non c'è pulsante "Indietro", "Annulla", "Salta". Solo "Apri Impostazioni".
/// ══════════════════════════════════════════════════════════════════════════════

class HardLockScreen extends StatelessWidget {
  const HardLockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // IMPOSSIBILE chiudere con back button
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          // Ignora il back button - non fa nulla
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.red.shade200, width: 2),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.security_rounded,
                  size: 64,
                  color: Colors.red.shade700,
                ),
                const SizedBox(height: 16),
                Text(
                  'Sicurezza Dispositivo Richiesta',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'CatechHub gestisce dati sensibili di minori (anagrafica, allergie, '
                  'contatti genitori, presenze). Per proteggerli, l\'app richiede che '
                  'il tuo telefono abbia un blocco schermo attivo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.red.shade700),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Il tuo telefono NON ha attualmente:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildMissingItem('PIN numerico'),
                      _buildMissingItem('Pattern (disegno)'),
                      _buildMissingItem('Password'),
                      _buildMissingItem('Impronta digitale / Riconoscimento facciale'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Attiva uno di questi metodi in:\n'
                  'Impostazioni → Sicurezza e privacy → Blocco schermo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
              ),
              onPressed: () {
                // Apre le impostazioni di sicurezza del sistema
                // Nota: su Android serve intent specifico, qui usiamo url_launcher generico
                _openSecuritySettings();
              },
              icon: const Icon(Icons.settings_rounded, size: 28),
              label: const Text(
                'Apri Impostazioni Sicurezza',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Dopo aver attivato il blocco schermo, torna qui e riprova.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildMissingItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.close_rounded, size: 16, color: Colors.red.shade400),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 13, color: Colors.red.shade700)),
        ],
      ),
    );
  }

  void _openSecuritySettings() {
    // Su Android, l'intent per aprire le impostazioni di sicurezza è:
    // Intent(Settings.ACTION_SECURITY_SETTINGS)
    // Per ora mostriamo un messaggio; l'integrazione nativa richiede
    // un MethodChannel o url_launcher con intent Android specifico.
    // Implementazione completa richiederebbe platform channel.
    debugPrint('TODO: Aprire Impostazioni Sicurezza Android via MethodChannel');
  }
}