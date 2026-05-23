import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bible_quote.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_service.dart';

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
      final canBiometric =
          await _localAuth.isDeviceSupported() ||
          await _localAuth.canCheckBiometrics;

      if (mounted) {
        setState(() {
          _isFirstSetup = !isConfigured;
          _biometricAvailable = canBiometric && isConfigured;
        });
      }
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
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

      final ok = await auth.setupAndUnlock(
        pin,
        firstName: firstName,
        lastName: lastName,
        groupName: groupName,
      );

      if (!ok && mounted) {
        setState(
          () => _errorMessage = "Errore durante la creazione del profilo.",
        );
      }

      return;
    }

    final ok = await auth.unlock(pin);

    if (!ok && mounted) {
      setState(() {
        _errorMessage = "PIN errato";
        _pinController.clear();
      });
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
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),

                        const SizedBox(height: 28),

                        if (isLoading)
                          const CircularProgressIndicator()
                        else ...[
                          Text(
                            _isFirstSetup
                                ? (_isConfirmingStage
                                      ? "Conferma PIN"
                                      : "Crea il tuo account")
                                : "Inserisci PIN",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),

                          const SizedBox(height: 12),

                          if (_isFirstSetup && !_isConfirmingStage) ...[
                            TextField(
                              controller: _firstNameController,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Nome',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _lastNameController,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Cognome',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _groupController,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Gruppo',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          TextField(
                            controller: _isConfirmingStage
                                ? _confirmPinController
                                : _pinController,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            textAlign: TextAlign.center,
                            maxLength: 12,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              counterText: "",
                              hintText: "••••",
                            ),
                            onSubmitted: (_) => _handleSubmit(),
                          ),

                          if (_errorMessage != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],

                          const SizedBox(height: 20),

                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _handleSubmit,
                              child: Text(
                                _isFirstSetup
                                    ? (_isConfirmingStage
                                          ? "Conferma"
                                          : "Continua")
                                    : "Sblocca",
                              ),
                            ),
                          ),

                          if (!_isFirstSetup && _biometricAvailable) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.fingerprint),
                                label: const Text('Usa impronta digitale'),
                                onPressed: _authenticateWithBiometrics,
                              ),
                            ),
                          ],
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
                          style: TextStyle(fontSize: 12),
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
}
