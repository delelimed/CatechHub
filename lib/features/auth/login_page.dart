import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bible_quote.dart';
import '../../core/auth/auth_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  late final BibleQuote randomQuote;

  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _groupController = TextEditingController();

  bool _isConfirmingStage = false;
  bool _isFirstSetup = false;
  bool _biometricAvailable = false;
  bool _showPin = false;

  String _firstPin = '';
  String? _errorMessage;

  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    randomQuote = bibleQuotes[Random().nextInt(bibleQuotes.length)];

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authService = ref.read(authServiceProvider);
      final isConfigured = authService.isPinConfigured;
      debugPrint('Login initState - PIN configurato: $isConfigured');

      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      debugPrint('Login initState - Device supportato: $isDeviceSupported, Can check: $canCheckBiometrics');

      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      debugPrint('Login initState - Biometriche disponibili: $availableBiometrics');

      final canBiometric = isDeviceSupported && canCheckBiometrics && availableBiometrics.isNotEmpty;

      if (mounted) {
        setState(() {
          _isFirstSetup = !isConfigured;
          _biometricAvailable = canBiometric && isConfigured;
          debugPrint('Login initState - Biometrica disponibile: $_biometricAvailable');
          if (_biometricAvailable) {
            debugPrint('Login initState - Avvio autenticazione biometrica automatica');
            _authenticateWithBiometrics();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _groupController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    HapticFeedback.mediumImpact();
    setState(() => _errorMessage = null);

    final controller = _isConfirmingStage
        ? _confirmPinController
        : _pinController;
    final pin = controller.text.trim();

    if (pin.length < 4) {
      setState(() => _errorMessage = "Il PIN deve essere di almeno 4 cifre");
      return;
    }

    final auth = ref.read(authStateProvider.notifier);

    if (_isFirstSetup) {
      if (!_isConfirmingStage) {
        final firstName = _firstNameController.text.trim();
        final lastName = _lastNameController.text.trim();
        final groupName = _groupController.text.trim();

        if (firstName.isEmpty || lastName.isEmpty || groupName.isEmpty) {
          setState(
            () => _errorMessage = "Nome, cognome e gruppo sono obbligatori.",
          );
          return;
        }

        _firstPin = pin;
        _pinController.clear();

        setState(() => _isConfirmingStage = true);
        return;
      }

      if (_firstPin != pin) {
        _pinController.clear();
        _confirmPinController.clear();

        setState(() {
          _isConfirmingStage = false;
          _errorMessage = "I PIN non corrispondono.";
        });
        return;
      }

      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final groupName = _groupController.text.trim();

      try {
        final ok = await auth.setupAndUnlock(
          pin,
          firstName: firstName,
          lastName: lastName,
          groupName: groupName,
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () async {
            if (mounted) {
              setState(() => _errorMessage = "Timeout: controlla la connessione");
            }
            return false;
          },
        );

        if (!ok && mounted) {
          setState(
            () => _errorMessage = "Errore durante la creazione del profilo.",
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _errorMessage = "Errore: riprova");
          debugPrint('Setup error: $e');
        }
      }

      return;
    }

    try {
      final ok = await auth.unlock(pin).timeout(
        const Duration(seconds: 15),
        onTimeout: () async {
          if (mounted) {
            setState(() => _errorMessage = "Timeout: controlla la connessione");
          }
          return false;
        },
      );

      if (!ok && mounted) {
        setState(() {
          _errorMessage = "PIN errato";
          _pinController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = "Errore: riprova");
        debugPrint('Login error: $e');
      }
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    HapticFeedback.mediumImpact();
    setState(() => _errorMessage = null);

    final auth = ref.read(authStateProvider.notifier);
    final ok = await auth.unlockWithBiometrics();

    if (!ok && mounted) {
      setState(
        () => _errorMessage =
            "Autenticazione biometrica non riuscita. Usa il PIN.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEAF4FF), Color(0xFFD5E8FF), Color(0xFFB9D7FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
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
                          "assets/images/logo.png",
                          height: 120,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.menu_book, size: 80),
                        ),

                        const SizedBox(height: 16),

                        const Text(
                          "Registro del Catechista",
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

                        if (isLoading)
                          const Column(
                            children: [
                              SizedBox(height: 8),
                              CircularProgressIndicator(
                                strokeWidth: 3,
                              ),
                              SizedBox(height: 16),
                              Text(
                                "Verifica in corso...",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 24),
                            ],
                          )
                        else if (_isFirstSetup) ...[
                          if (!_isConfirmingStage)
                            _buildFirstSetupForm()
                          else
                            _buildPinConfirmationForm(),
                        ]
                        else ...[
                          _buildLoginForm(),
                        ],

                        const SizedBox(height: 20),

                        OutlinedButton.icon(
                          onPressed: () async {
                            final uri = Uri.parse(
                              "https://www.diocesisabina.it/sussidiocatechesi/",
                            );
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text("Sussidio Catechesi"),
                        ),

                        const SizedBox(height: 16),

                        const Text(
                          "Realizzato con ❤️ da DELELI",
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

  Widget _buildLoginForm() {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Sblocca Registro",
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF174A7E),
          ),
        ),
        const SizedBox(height: 24),
        if (_biometricAvailable) ...[
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
              ),
              onPressed: isLoading ? null : _authenticateWithBiometrics,
              icon: const Icon(Icons.fingerprint, size: 28),
              label: const Text(
                'Usa impronta digitale',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Container(height: 1, color: Colors.grey.shade300)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'oppure',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
              Expanded(child: Container(height: 1, color: Colors.grey.shade300)),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Text(
          _biometricAvailable ? 'Inserisci PIN' : 'Sblocca con PIN',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),
        if (!isLoading) _buildPinInputField(_pinController),
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
          Container(
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
                    _errorMessage!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: isLoading ? null : _handleSubmit,
            child: const Text('Sblocca'),
          ),
        ),
      ],
    );
  }

  Widget _buildFirstSetupForm() {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Crea il tuo account",
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF174A7E),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Passo 1 di 3 - Informazioni personali",
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        if (!isLoading) ...[
          _buildTextField(_firstNameController, 'Nome', Icons.person),
          const SizedBox(height: 12),
          _buildTextField(_lastNameController, 'Cognome', Icons.person_outline),
          const SizedBox(height: 12),
          _buildTextField(_groupController, 'Gruppo', Icons.groups),
          const SizedBox(height: 20),
          Text(
            "Scegli un PIN",
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 12),
          _buildPinInputField(_pinController),
        ] else
          const SizedBox(
            height: 150,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Creazione account in corso...'),
                ],
              ),
            ),
          ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
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
                    _errorMessage!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: isLoading ? null : _handleSubmit,
            child: const Text('Continua'),
          ),
        ),
      ],
    );
  }

  Widget _buildPinConfirmationForm() {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Conferma PIN",
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF174A7E),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Passo 2 di 3 - Conferma il PIN",
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        Text(
          "Reinserisci il PIN per confermare",
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),
        if (!isLoading)
          _buildPinInputField(_confirmPinController)
        else
          const SizedBox(
            height: 60,
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
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
                    _errorMessage!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: isLoading ? null : _handleSubmit,
            child: const Text('Crea account'),
          ),
        ),
      ],
    );
  }

  Widget _buildPinInputField(TextEditingController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _errorMessage != null ? Colors.red.shade300 : Colors.grey.shade300,
          width: _errorMessage != null ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              obscureText: !_showPin,
              textAlign: TextAlign.center,
              maxLength: 12,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 4,
                fontWeight: FontWeight.bold,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                counterText: "",
                border: InputBorder.none,
                hintText: "••••",
                hintStyle: TextStyle(letterSpacing: 4),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _handleSubmit(),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _showPin = !_showPin),
            child: Icon(
              _showPin ? Icons.visibility : Icons.visibility_off,
              color: Colors.grey,
            ),
          ),
        ],
      ),
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
}
