import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../shared/widgets/app_scaffold.dart';

class ChangePinPage extends ConsumerStatefulWidget {
  const ChangePinPage({super.key});

  @override
  ConsumerState<ChangePinPage> createState() => _ChangePinPageState();
}

class _ChangePinPageState extends ConsumerState<ChangePinPage> {
  final _oldPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool _showOldPin = false;
  bool _showNewPin = false;
  bool _showConfirmPin = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _oldPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _handleChangePin() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    final oldPin = _oldPinController.text.trim();
    final newPin = _newPinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (oldPin.length < 4) {
      setState(() {
        _errorMessage = 'Il PIN deve essere di almeno 4 cifre';
        _isLoading = false;
      });
      return;
    }

    if (newPin.length < 4) {
      setState(() {
        _errorMessage = 'Il nuovo PIN deve essere di almeno 4 cifre';
        _isLoading = false;
      });
      return;
    }

    if (newPin != confirmPin) {
      setState(() {
        _errorMessage = 'I nuovi PIN non corrispondono';
        _isLoading = false;
      });
      return;
    }

    if (oldPin == newPin) {
      setState(() {
        _errorMessage = 'Il nuovo PIN deve essere diverso da quello vecchio';
        _isLoading = false;
      });
      return;
    }

    final authNotifier = ref.read(authStateProvider.notifier);
    final success = await authNotifier.changePin(oldPin, newPin);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN modificato con successo'),
          backgroundColor: Colors.green,
        ),
      );
      context.pop();
    } else {
      setState(() => _errorMessage = 'PIN vecchio non corretto');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Cambia PIN',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Inserisci il PIN attuale e poi il nuovo PIN due volte per confermare',
                      style: TextStyle(
                        color: Colors.blue.shade900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Old PIN
            Text(
              'PIN attuale',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            _buildPinInputField(
              _oldPinController,
              _showOldPin,
              () => setState(() => _showOldPin = !_showOldPin),
            ),

            const SizedBox(height: 24),

            // New PIN
            Text(
              'Nuovo PIN',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            _buildPinInputField(
              _newPinController,
              _showNewPin,
              () => setState(() => _showNewPin = !_showNewPin),
            ),

            const SizedBox(height: 24),

            // Confirm New PIN
            Text(
              'Conferma nuovo PIN',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            _buildPinInputField(
              _confirmPinController,
              _showConfirmPin,
              () => setState(() => _showConfirmPin = !_showConfirmPin),
            ),

            const SizedBox(height: 24),

            if (_errorMessage != null) ...[
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
              const SizedBox(height: 20),
            ],

            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleChangePin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF174A7E),
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Salva nuovo PIN',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinInputField(
    TextEditingController controller,
    bool showPin,
    VoidCallback onToggleVisibility,
  ) {
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
              obscureText: !showPin,
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
            ),
          ),
          GestureDetector(
            onTap: onToggleVisibility,
            child: Icon(
              showPin ? Icons.visibility : Icons.visibility_off,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
