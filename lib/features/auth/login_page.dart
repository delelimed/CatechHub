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
  State<_AnimatedGradientBackground> createState() =>
      _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState
    extends State<_AnimatedGradientBackground>
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

  int _setupStep = 0; // 0: nome/cognome, 1: crea/unisciti, 2: nome gruppo (solo se crea)

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

  void _nextStep() {
    if (_setupStep == 0) {
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      if (firstName.isEmpty || lastName.isEmpty) {
        setState(() => _errorMessage = 'Nome e cognome sono obbligatori.');
        return;
      }
      setState(() {
        _errorMessage = null;
        _setupStep = 1;
      });
    }
  }

  void _previousStep() {
    setState(() {
      _errorMessage = null;
      _setupStep = _setupStep - 1;
      if (_setupStep == 1) _groupController.clear();
    });
  }

  Future<void> _handleJoinClass() async {
    HapticFeedback.mediumImpact();
    setState(() => _errorMessage = null);

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();

    final auth = ref.read(authStateProvider.notifier);
    final ok = await auth.setupInitialProfile(
      firstName: firstName,
      lastName: lastName,
      createClass: false,
    );

    if (!ok && mounted) {
      setState(
        () => _errorMessage = 'Errore durante la configurazione. Riprova.',
      );
    }
  }

  Future<void> _handleCreateClass() async {
    HapticFeedback.mediumImpact();
    setState(() => _errorMessage = null);

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final groupName = _groupController.text.trim();

    if (groupName.isEmpty) {
      setState(() => _errorMessage = 'Il nome del gruppo è obbligatorio.');
      return;
    }

    final auth = ref.read(authStateProvider.notifier);
    final ok = await auth.setupInitialProfile(
      firstName: firstName,
      lastName: lastName,
      groupName: groupName,
      createClass: true,
    );

    if (!ok && mounted) {
      setState(
        () => _errorMessage = 'Errore durante la configurazione. Riprova.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

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
                constraints: BoxConstraints(maxWidth: isLandscape ? 760 : 430),
                child: Card(
                  elevation: 12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isLandscape ? 40 : 28),
                    child: isLandscape
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Image.asset(
                                      'assets/images/logo.png',
                                      height: isLandscape ? 140 : 100,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.menu_book, size: 80),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'CatechHub',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: isLandscape ? 28 : 22,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF174A7E),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      '"${randomQuote.text}"',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        fontSize: isLandscape ? 15 : 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 4,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isFirstSetup) ...[
                                      _buildFirstSetupForm(isLoading, isLandscape),
                                    ] else if (!_checkedLockScreen) ...[
                                      _buildCheckingLockScreen(),
                                    ] else if (!_hasSecureLockScreen) ...[
                                      const HardLockScreen(),
                                    ] else ...[
                                      _buildUnlockForm(isLoading, isLandscape),
                                    ],
                                    const SizedBox(height: 20),
                                    const Text(
                                      'Realizzato con ❤️\n da un catechista per i catechisti',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Column(
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
                                _buildFirstSetupForm(isLoading, isLandscape),
                              ] else if (!_checkedLockScreen) ...[
                                _buildCheckingLockScreen(),
                              ] else if (!_hasSecureLockScreen) ...[
                                // HARD LOCK SCREEN - Non chiudibile, non bypassabile
                                const HardLockScreen(),
                              ] else ...[
                                _buildUnlockForm(isLoading, isLandscape),
                              ],

                              const SizedBox(height: 20),
                              const Text(
                                'Realizzato con ❤️\n da un catechista per i catechisti',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
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

  Widget _buildFirstSetupForm(bool isLoading, bool isLandscape) {
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
        Text(
          'L\'app usa il blocco schermo del tuo telefono (impronta, volto, PIN) '
          'per proteggere i dati. Non serve creare un PIN separato.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: isLandscape ? 13 : 12, color: Colors.grey),
        ),
        const SizedBox(height: 24),
        if (isLoading) ...[
          const SizedBox(height: 8),
          const CircularProgressIndicator(strokeWidth: 3),
        ] else ...[
          if (_errorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700, fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_setupStep == 0) ...[
            _buildTextField(_firstNameController, 'Nome', Icons.person, isLandscape),
            const SizedBox(height: 12),
            _buildTextField(_lastNameController, 'Cognome', Icons.person_outline, isLandscape),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
                minimumSize: Size(double.infinity, isLandscape ? 56 : 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Avanti',
                style: TextStyle(
                  fontSize: isLandscape ? 17 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ] else if (_setupStep == 1) ...[
            Text(
              'Scegli come iniziare',
              style: TextStyle(
                fontSize: isLandscape ? 16 : 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _setupStep = 2;
                    _errorMessage = null;
                  });
                },
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Crea una nuova classe'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF174A7E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _handleJoinClass,
                icon: const Icon(Icons.people_outline),
                label: const Text('Unisciti a una classe esistente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF174A7E),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Color(0xFF174A7E)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: _previousStep,
              child: Text(
                'Indietro',
                style: TextStyle(
                  fontSize: isLandscape ? 14 : 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ] else if (_setupStep == 2) ...[
            _buildTextField(
              _groupController,
              'Nome della classe',
              Icons.groups,
              isLandscape,
            ),
            const SizedBox(height: 12),
            Text(
              'Inserisci il nome del tuo gruppo di catechismo '
              '(es. "Prima elementare", "Cresima 2026")',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: isLandscape ? 12 : 11, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _handleCreateClass,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
                minimumSize: Size(double.infinity, isLandscape ? 56 : 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Crea profilo e accedi',
                style: TextStyle(
                  fontSize: isLandscape ? 17 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _previousStep,
              child: Text(
                'Indietro',
                style: TextStyle(
                  fontSize: isLandscape ? 14 : 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildUnlockForm(bool isLoading, bool isLandscape) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_errorMessage != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red.shade700, fontSize: 14),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          'Sblocca il registro',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF174A7E),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Usa l\'impronta digitale, il riconoscimento facciale o il PIN del telefono.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: isLandscape ? 14 : 13, color: Colors.grey),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF174A7E),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 24 : 20,
              vertical: isLandscape ? 20 : 18,
            ),
            minimumSize: Size(double.infinity, isLandscape ? 0 : 0),
          ),
          onPressed: isLoading ? null : _handleBiometricUnlock,
          icon: Icon(Icons.fingerprint, size: isLandscape ? 28 : 28),
          label: Text(
            'Accedi con impronta / volto / PIN telefono',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isLandscape ? 14 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (isLoading) ...[
          const SizedBox(height: 16),
          const CircularProgressIndicator(strokeWidth: 3),
        ],
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, [
    bool isLandscape = false,
  ]) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF174A7E)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: const Color(0xFF174A7E).withValues(alpha: 0.05),
        contentPadding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 24 : 20,
          vertical: isLandscape ? 20 : 16,
        ),
      ),
    );
  }
}

/// Schermata di blocco totale - NON chiudibile, NON bypassabile
/// Appare se il dispositivo NON ha un lockscreen sicuro attivo.
class HardLockScreen extends StatelessWidget {
  const HardLockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
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
              Icon(Icons.security, size: 48, color: Colors.red.shade700),
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
                'Per usare CatechHub devi attivare un blocco schermo sicuro '
                '(PIN, impronta, volto) nelle impostazioni del telefono.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.red.shade700),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.settings, color: Colors.white),
                label: const Text(
                  'Apri Impostazioni Sicurezza',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'L\'app non può funzionare senza blocco schermo attivo.\n'
                'Questa misura protegge i dati dei catechisti e dei ragazzi.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.red.shade500),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
