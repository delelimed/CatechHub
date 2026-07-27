import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/providers/nearby_sync_provider.dart';
import '../../../../core/storage/local_database.dart';
import '../../../../features/sync/p2p/p2p_sync_service.dart';
import '../../../../features/sync/p2p/p2p_security_service.dart';

enum _OnboardingStep { roleChoice, instructions, showQr, scanQr, syncing, complete, error }

class OnboardingSyncPage extends ConsumerStatefulWidget {
  const OnboardingSyncPage({super.key});

  @override
  ConsumerState<OnboardingSyncPage> createState() => _OnboardingSyncPageState();
}

class _OnboardingSyncPageState extends ConsumerState<OnboardingSyncPage> {
  final P2PSecurityService _security = P2PSecurityService();

  _OnboardingStep _currentStep = _OnboardingStep.roleChoice;

  P2PSyncRole _selectedRole = P2PSyncRole.mioDispositivo;

  String? _qrData;
  String? _errorMessage;
  String? _successMessage;
  String? _syncedDeviceName;

  MobileScannerController? _scannerController;

  bool _isPairing = false;
  bool _syncCompleted = false;
  Timer? _pairingTimeoutTimer;
  StreamSubscription<P2PSyncState>? _p2pStateSub;

  int _syncProgressTotal = 0;
  int _syncProgressCurrent = 0;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _stopScanner();
    _pairingTimeoutTimer?.cancel();
    _p2pStateSub?.cancel();
    _stopP2p();
    super.dispose();
  }

  Future<void> _initData() async {
    try {
      final qrData = await _generateQrData();
      if (mounted) {
        setState(() => _qrData = qrData);
      }
    } catch (_) {}
  }

  Future<String> _generateQrData() async {
    return _security.generateQrPayload();
  }

  void _setRole(P2PSyncRole role) {
    setState(() {
      _selectedRole = role;
      _errorMessage = null;
    });
    ref.read(nearbySyncServiceProvider).setRole(role);
  }

  void _proceedFromRoleChoice() {
    setState(() {
      _currentStep = _OnboardingStep.instructions;
      _errorMessage = null;
    });
  }

  void _startShowQr() {
    setState(() {
      _currentStep = _OnboardingStep.showQr;
      _errorMessage = null;
    });
    _startP2p();
  }

  void _startScanQr() {
    setState(() {
      _currentStep = _OnboardingStep.scanQr;
      _errorMessage = null;
    });
    _openScanner();
    _startP2p();
  }

  void _openScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
    _scannerController!.start();
  }

  void _stopScanner() {
    try {
      _scannerController?.stop();
      _scannerController?.dispose();
    } catch (_) {}
    _scannerController = null;
  }

  void _stopP2p() {
    try {
      ref.read(nearbySyncServiceProvider).stopPairingMode();
    } catch (_) {}
  }

  void _startP2p() {
    if (_isPairing) return;
    _isPairing = true;
    _watchP2pState();
    ref.read(nearbySyncServiceProvider).startPairingMode();
    _pairingTimeoutTimer = Timer(const Duration(seconds: 120), () {
      if (mounted && !_syncCompleted) {
        setState(() {
          _errorMessage = 'Tempo scaduto. Assicurati che l\'altro dispositivo '
              'sia in modalità associazione.';
          _isPairing = false;
          _currentStep = _OnboardingStep.error;
        });
        _stopP2p();
      }
    });
  }

  void _watchP2pState() {
    _p2pStateSub?.cancel();
    final service = ref.read(nearbySyncServiceProvider);
    _p2pStateSub = service.onStateChanged.listen((state) {
      if (!mounted) return;

      if (state.status == P2PSyncStatus.sessionEstablished ||
          state.status == P2PSyncStatus.completed ||
          state.status == P2PSyncStatus.syncing) {
        _pairingTimeoutTimer?.cancel();

        if (state.status == P2PSyncStatus.syncing) {
          setState(() {
            _currentStep = _OnboardingStep.syncing;
            _syncProgressTotal = state.totalRecordsToExchange;
            _syncProgressCurrent = state.sentRecordsCount + state.receivedRecordsCount;
            _syncedDeviceName = state.connectedDeviceName;
          });
        }

        if (state.status == P2PSyncStatus.completed) {
          _onSyncCompleted(state);
        }
      } else if (state.status == P2PSyncStatus.pairingVerification) {
        _pairingTimeoutTimer?.cancel();
      } else if (state.status == P2PSyncStatus.error) {
        if (!_syncCompleted) {
          setState(() {
            _errorMessage = state.errorMessage ?? 'Errore di connessione.';
            _isPairing = false;
            _currentStep = _OnboardingStep.error;
          });
        }
      }
    });
  }

  void _onSyncCompleted(P2PSyncState state) {
    _syncCompleted = true;

    try {
      final classesBox = LocalDatabase.classes();
      const localId = AuthService.localUserId;
      bool found = false;
      for (final key in classesBox.keys) {
        final data = LocalDatabase.toStringDynamicMap(classesBox.get(key));
        final ids = (data['catechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        if (ids.contains(localId)) {
          found = true;
          break;
        }
      }

      if (!found) {
        setState(() {
          _errorMessage = 'Sincronizzazione completata ma non risulti in '
              'nessuna classe. Assicurati che l\'altro catechista ti abbia '
              'aggiunto al gruppo.';
          _currentStep = _OnboardingStep.error;
          _isPairing = false;
        });
        return;
      }
    } catch (_) {
      setState(() {
        _errorMessage = 'Errore durante la verifica della classe.';
        _currentStep = _OnboardingStep.error;
        _isPairing = false;
      });
      return;
    }

    setState(() {
      _currentStep = _OnboardingStep.complete;
      _successMessage = 'Sei stato aggiunto alla classe '
          '${state.connectedDeviceName != null ? "di ${state.connectedDeviceName}" : ""}!'
          .trim();
      _isPairing = false;
    });
  }

  Future<void> _onQrScanned(BarcodeCapture capture) async {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      final remoteIdentity = P2PSecurityService.parseQrPayload(raw);
      if (remoteIdentity == null) {
        if (mounted) setState(() => _errorMessage = 'QR code non valido.');
        return;
      }

      final existing = await _security.getAssociation(remoteIdentity.deviceId);

      if (existing == null) {
        try {
          final syncService = ref.read(nearbySyncServiceProvider);
          final localRole = syncService.currentState.role.name;
          final sharedSecret = await _security.computeStaticSharedSecret(
              remoteIdentity.publicKeyBase64);
          await _security.registerAndSaveAssociation(
            deviceId: remoteIdentity.deviceId,
            deviceName: remoteIdentity.deviceName,
            publicKeyBase64: remoteIdentity.publicKeyBase64,
            fingerprint: remoteIdentity.fingerprint,
            sharedSecretBase64: sharedSecret,
            localRole: localRole,
          );
        } catch (e) {
          if (mounted) {
            setState(() => _errorMessage = 'Errore salvataggio associazione: $e');
          }
          return;
        }
      }

      _stopScanner();

      if (mounted) {
        final service = ref.read(nearbySyncServiceProvider);
        final currentState = service.currentState;
        if (currentState.status == P2PSyncStatus.pairingVerification) {
          await service.confirmPairingCode();
        } else if (currentState.connectedDeviceId != null) {
          await service.finalizeAssociation(
            currentState.connectedDeviceId!,
            remoteIdentity.deviceId,
          );
        }
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unisciti a una classe'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _stopP2p();
            _stopScanner();
            context.go('/login');
          },
        ),
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_currentStep) {
      case _OnboardingStep.roleChoice:
        return _buildRoleChoice();
      case _OnboardingStep.instructions:
        return _buildInstructions();
      case _OnboardingStep.showQr:
        return _buildShowQrStep();
      case _OnboardingStep.scanQr:
        return _buildScanQrStep();
      case _OnboardingStep.syncing:
        return _buildSyncingStep();
      case _OnboardingStep.complete:
        return _buildCompleteStep();
      case _OnboardingStep.error:
        return _buildErrorStep();
    }
  }

  Widget _buildRoleChoice() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF174A7E).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.people_rounded, size: 36, color: Color(0xFF174A7E)),
          ),
          const SizedBox(height: 24),
          const Text(
            'Scegli il tipo di associazione',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF174A7E)),
          ),
          const SizedBox(height: 12),
          Text(
            'Entrambi i dispositivi devono selezionare lo STESSO ruolo '
            'per poter sincronizzare. Accordati con l\'altro catechista.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 24),
          _buildRoleOption(
            P2PSyncRole.mioDispositivo,
            Icons.phone_android_rounded,
            'Mio dispositivo',
            'Sei il catechista principale che ha già i dati della classe '
            'sul proprio dispositivo oppure sei un nuovo catechista '
            'che si unisce a una classe esistente.',
          ),
          const SizedBox(height: 12),
          _buildRoleOption(
            P2PSyncRole.altroCatechista,
            Icons.person_add_rounded,
            'Altro catechista',
            'Sei un catechista che si associa per la sincronizzazione '
            'dei dati con il collega.',
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Continua',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              onPressed: _proceedFromRoleChoice,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildRoleOption(P2PSyncRole role, IconData icon, String title, String description) {
    final isSelected = _selectedRole == role;
    return Material(
      color: isSelected
          ? const Color(0xFF174A7E).withValues(alpha: 0.08)
          : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _setRole(role),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? const Color(0xFF174A7E) : Colors.grey.shade200,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF174A7E) : const Color(0xFF174A7E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: isSelected ? Colors.white : const Color(0xFF174A7E), size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isSelected ? const Color(0xFF174A7E) : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: const Color(0xFF174A7E)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF174A7E).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.bluetooth_rounded, size: 36, color: Color(0xFF174A7E)),
          ),
          const SizedBox(height: 24),
          const Text(
            'Sincronizzazione con un catechista',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Per unirti a una classe esistente, devi sincronizzarti '
            'con il catechista che ha già creato il gruppo.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 24),
          _buildStepCard(
            '1',
            'Scegli come procedere',
            'Puoi mostrare il tuo QR all\'altro catechista oppure '
            'inquadrare il suo QR, a seconda di cosa è più comodo.',
          ),
          const SizedBox(height: 12),
          _buildStepCard(
            '2',
            'Abbina i codici',
            'Confronta il codice di sicurezza che appare su entrambi '
            'i dispositivi per verificare che la connessione sia sicura.',
          ),
          const SizedBox(height: 12),
          _buildStepCard(
            '3',
            'Sincronizzazione',
            'I dati della classe verranno trasferiti automaticamente '
            'sul tuo dispositivo in modo sicuro e cifrato.',
          ),
          const SizedBox(height: 12),
          _buildStepCard(
            '4',
            'Pronto!',
            'Una volta completata la sincronizzazione, potrai '
            'accedere alla dashboard con i dati della classe.',
          ),
          const SizedBox(height: 32),
          const Text(
            'Entrambi i dispositivi devono avere lo STESSO ruolo: '
            'entrambi "mioDispositivo" o entrambi "altroCatechista".',
            style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Inquadra QR del partner',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              onPressed: _startScanQr,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF174A7E),
                side: const BorderSide(color: Color(0xFF174A7E)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.qr_code_rounded),
              label: const Text('Mostra QR al partner',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              onPressed: _startShowQr,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildShowQrStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.qr_code_rounded, size: 36, color: Color(0xFF174A7E)),
          ),
          const SizedBox(height: 20),
          const Text(
            'Mostra questo QR al partner',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF174A7E)),
          ),
          const SizedBox(height: 8),
          Text(
            'L\'altro catechista deve inquadrare questo codice '
            'con la fotocamera di CatechHub.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
          ),
          const SizedBox(height: 24),
          if (_qrData != null)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: QrImageView(
                data: _qrData!,
                size: 220,
                backgroundColor: Colors.white,
              ),
            )
          else
            const CircularProgressIndicator(),
          const SizedBox(height: 24),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ),
          Text(
            'In attesa che il partner inquadri il QR...',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildScanQrStep() {
    return Column(
      children: [
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: Stack(
            children: [
              MobileScanner(
                controller: _scannerController,
                onDetect: _onQrScanned,
              ),
              Container(
                alignment: Alignment.center,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                'Inquadra il QR dell\'altro catechista',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Il QR si trova nella schermata "Mostra QR" '
                'dell\'altra app.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSyncingStep() {
    final progress = _syncProgressTotal > 0
        ? (_syncProgressCurrent / _syncProgressTotal).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.sync_rounded, size: 64, color: Color(0xFF174A7E)),
          const SizedBox(height: 24),
          const Text(
            'Sincronizzazione in corso...',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF174A7E)),
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF174A7E)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _syncProgressTotal > 0
                ? '$_syncProgressCurrent / $_syncProgressTotal record'
                : 'Trasferimento dati in corso...',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          if (_syncedDeviceName != null) ...[
            const SizedBox(height: 8),
            Text(
              'Connesso a: $_syncedDeviceName',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompleteStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.check_circle_rounded, size: 80, color: Colors.green),
          const SizedBox(height: 24),
          const Text(
            'Sincronizzazione completata!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          if (_successMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _successMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.4),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.home_rounded),
              label: const Text('Vai alla home',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              onPressed: () {
                context.go('/');
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildErrorStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.error_outline_rounded, size: 64, color: Colors.red),
          const SizedBox(height: 24),
          const Text(
            'Sincronizzazione non riuscita',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Riprova',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              onPressed: _retry,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/'),
            child: const Text('Salta e vai alla home'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _retry() {
    _stopP2p();
    _stopScanner();
    _syncCompleted = false;
    _isPairing = false;
    _errorMessage = null;
    _successMessage = null;
    setState(() {
      _currentStep = _OnboardingStep.roleChoice;
    });
  }

  Widget _buildStepCard(String number, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFF174A7E),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF174A7E))),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}