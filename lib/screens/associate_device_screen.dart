import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/providers/nearby_sync_provider.dart';
import '../features/sync/p2p/p2p_sync_service.dart';
import '../features/sync/p2p/p2p_security_service.dart';

enum _AssociationStep { roleChoice, actionChoice, scanQr, showQr, complete }

class AssociateDeviceScreen extends ConsumerStatefulWidget {
  const AssociateDeviceScreen({super.key});

  @override
  ConsumerState<AssociateDeviceScreen> createState() =>
      _AssociateDeviceScreenState();
}

class _AssociateDeviceScreenState
    extends ConsumerState<AssociateDeviceScreen> {
  final P2PSecurityService _security = P2PSecurityService();

  _AssociationStep _currentStep = _AssociationStep.roleChoice;

  P2PSyncRole _selectedRole = P2PSyncRole.mioDispositivo;

  bool _choseScanFirst = false;

  String? _qrData;
  String? _errorMessage;
  String? _successMessage;

  MobileScannerController? _scannerController;
  bool _showScanner = false;
  String? _lastScannedDeviceName;
  String? _scannedDeviceId;

  Timer? _reciprocalCheckTimer;
  bool _waitingForReciprocal = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _stopScanner();
    _reciprocalCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    try {
      final qrData = await _generateQrData();
      if (mounted) {
        setState(() {
          _qrData = qrData;
        });
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

  void _proceedToActionChoice() {
    setState(() {
      _currentStep = _AssociationStep.actionChoice;
      _errorMessage = null;
    });
  }

  void _chooseScanFirst() {
    setState(() {
      _choseScanFirst = true;
      _currentStep = _AssociationStep.scanQr;
      _errorMessage = null;
      _successMessage = null;
    });
    _openScanner();
  }

  void _chooseShowQrFirst() {
    setState(() {
      _choseScanFirst = false;
      _currentStep = _AssociationStep.showQr;
      _errorMessage = null;
      _successMessage = null;
    });
  }

  void _proceedToShowQrAfterScan() {
    setState(() {
      _currentStep = _AssociationStep.showQr;
      _showScanner = false;
      _waitingForReciprocal = true;
    });
    _startReciprocalCheck(_scannedDeviceId);
  }

  void _proceedToScanAfterShow() {
    setState(() {
      _currentStep = _AssociationStep.scanQr;
      _errorMessage = null;
    });
    _openScanner();
  }

  void _openScanner() {
    setState(() {
      _showScanner = true;
      _errorMessage = null;
    });
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
    _showScanner = false;
  }

  void _resetWizard() {
    _stopScanner();
    _reciprocalCheckTimer?.cancel();
    setState(() {
      _currentStep = _AssociationStep.roleChoice;
      _errorMessage = null;
      _successMessage = null;
      _lastScannedDeviceName = null;
      _scannedDeviceId = null;
      _waitingForReciprocal = false;
    });
  }

  Future<void> _onQrScanned(BarcodeCapture capture) async {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      _stopScanner();

      final remoteIdentity = P2PSecurityService.parseQrPayload(raw);
      if (remoteIdentity == null) {
        setState(() => _errorMessage = 'QR code non valido.');
        return;
      }

      final existing = await _security.getAssociation(remoteIdentity.deviceId);
      if (existing != null) {
        setState(() => _errorMessage = 'Dispositivo già associato.');
        return;
      }

      try {
        final syncService = ref.read(nearbySyncServiceProvider);
        final localRole = syncService.currentState.role.name;

        final sharedSecret = await _security.computeStaticSharedSecret(
            remoteIdentity.publicKeyBase64,
            forDeviceId: remoteIdentity.deviceId);

        await _security.registerAndSaveAssociation(
          deviceId: remoteIdentity.deviceId,
          deviceName: remoteIdentity.deviceName,
          publicKeyBase64: remoteIdentity.publicKeyBase64,
          fingerprint: remoteIdentity.fingerprint,
          sharedSecretBase64: sharedSecret,
          localRole: localRole,
        );

        if (mounted) {
          setState(() {
            _lastScannedDeviceName = remoteIdentity.deviceName;
            _scannedDeviceId = remoteIdentity.deviceId;
            _errorMessage = null;
            _successMessage =
                'Associazione salvata: ${remoteIdentity.deviceName}';
          });

          if (_choseScanFirst) {
            _proceedToShowQrAfterScan();
          } else {
            setState(() {
              _currentStep = _AssociationStep.complete;
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _errorMessage = 'Errore associazione: $e');
        }
      }

      return;
    }
  }

  void _startReciprocalCheck(String? scannedDeviceId) {
    if (scannedDeviceId == null) return;
    _reciprocalCheckTimer?.cancel();
    _reciprocalCheckTimer =
        Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final reciprocalAssoc = await _security.getAssociation(scannedDeviceId);
      if (reciprocalAssoc != null && reciprocalAssoc.remoteRole != null) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _waitingForReciprocal = false;
            _currentStep = _AssociationStep.complete;
            _successMessage = 'Associazione reciproca completata!';
          });
        }
      }
    });

    Future.delayed(const Duration(seconds: 30), () {
      _reciprocalCheckTimer?.cancel();
      if (mounted && _waitingForReciprocal) {
        setState(() {
          _waitingForReciprocal = false;
          _errorMessage =
              'Tempo scaduto. Assicurati che l\'altro dispositivo '
              'abbia scansionato il tuo QR.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Associa Dispositivo',
            style: TextStyle(color: Colors.white)),
        backgroundColor: colorScheme.primary,
        actions: [
          if (_currentStep != _AssociationStep.roleChoice)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _resetWizard,
              tooltip: 'Ricomincia',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStepIndicator(theme),
            const SizedBox(height: 20),
            _buildCurrentStep(theme, colorScheme),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _buildMessageBanner(theme, _errorMessage!, isError: true),
            ],
            if (_successMessage != null && _errorMessage == null) ...[
              const SizedBox(height: 12),
              _buildMessageBanner(theme, _successMessage!, isError: false),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(ThemeData theme) {
    final steps = [
      _AssociationStep.roleChoice,
      _AssociationStep.actionChoice,
      _choseScanFirst
          ? _AssociationStep.scanQr
          : _AssociationStep.showQr,
      _choseScanFirst
          ? _AssociationStep.showQr
          : _AssociationStep.scanQr,
      _AssociationStep.complete,
    ];

    final labels = [
      'Ruolo',
      'Azione',
      _choseScanFirst ? 'Scansiona' : 'Mostra QR',
      _choseScanFirst ? 'Mostra QR' : 'Scansiona',
      'Completato',
    ];

    final currentIndex = steps.indexOf(_currentStep);

    return Row(
      children: List.generate(steps.length, (i) {
        final isActive = i <= currentIndex;
        final isCurrent = i == currentIndex;
        return Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (i > 0)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[300],
                      ),
                    ),
                  Container(
                    width: isCurrent ? 32 : 24,
                    height: isCurrent ? 32 : 24,
                    decoration: BoxDecoration(
                      color: isActive
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[300],
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: isActive
                          ? Icon(Icons.check, color: Colors.white, size: 16)
                          : Text('${i + 1}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              )),
                    ),
                  ),
                  if (i < steps.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: steps[i + 1] == _currentStep || isActive
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[300],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 9,
                  color: isActive ? Theme.of(context).colorScheme.primary : Colors.grey[400],
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildCurrentStep(ThemeData theme, ColorScheme colorScheme) {
    switch (_currentStep) {
      case _AssociationStep.roleChoice:
        return _buildRoleStep(theme, colorScheme);
      case _AssociationStep.actionChoice:
        return _buildActionStep(theme, colorScheme);
      case _AssociationStep.scanQr:
        return _buildScanStep(theme, colorScheme);
      case _AssociationStep.showQr:
        return _buildShowQrStep(theme, colorScheme);
      case _AssociationStep.complete:
        return _buildCompleteStep(theme, colorScheme);
    }
  }

  Widget _buildRoleStep(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_outline, color: colorScheme.primary, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Scegli il ruolo del dispositivo',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Il ruolo determina come si comporterà la sincronizzazione.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 16),
            RadioGroup<P2PSyncRole>(
              groupValue: _selectedRole,
              onChanged: (role) {
                if (role != null) _setRole(role);
              },
              child: Column(
                children: [
                  RadioListTile<P2PSyncRole>(
                    title: const Text('Mio Dispositivo'),
                    subtitle: const Text('Sincronizzazione automatica con gli altri catechisti'),
                    secondary: const Icon(Icons.sync),
                    value: P2PSyncRole.mioDispositivo,
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<P2PSyncRole>(
                    title: const Text('Altro Catechista'),
                    subtitle: const Text('Richiede conferma prima di sincronizzare'),
                    secondary: const Icon(Icons.how_to_reg),
                    value: P2PSyncRole.altroCatechista,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _proceedToActionChoice,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continua'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.sync_problem, size: 48, color: colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  'Scegli come procedere',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Coordinati con l\'altro catechista:\n'
                  'un dispositivo deve scegliere "Scansiona" e l\'altro "Mostra QR".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _chooseScanFirst,
            icon: const Icon(Icons.qr_code_scanner, size: 22),
            label: const Text('Scansiona QR partner'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _chooseShowQrFirst,
            icon: const Icon(Icons.qr_code, size: 22),
            label: const Text('Mostra il mio QR'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              foregroundColor: colorScheme.primary,
              side: BorderSide(color: colorScheme.primary, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScanStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        if (_choseScanFirst) ...[
          _buildInfoCard(
            icon: Icons.qr_code_scanner,
            title: 'Scansiona il QR dell\'altro dispositivo',
            subtitle: 'Inquadra il QR code mostrato dall\'altro catechista',
            color: colorScheme.primary,
          ),
          const SizedBox(height: 16),
        ] else ...[
          _buildInfoCard(
            icon: Icons.qr_code_scanner,
            title: 'Ora scansiona il QR partner',
            subtitle:
                'L\'altro dispositivo dovrebbe mostrare il suo QR. Inquadralo con la fotocamera.',
            color: Colors.orange,
          ),
          const SizedBox(height: 16),
        ],
        if (_showScanner && _scannerController != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 280,
              child: MobileScanner(
                controller: _scannerController!,
                onDetect: _onQrScanned,
              ),
            ),
          )
        else if (_showScanner)
          const SizedBox(
            height: 280,
            child: Center(child: CircularProgressIndicator()),
          ),
        const SizedBox(height: 12),
        if (_showScanner)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                _stopScanner();
                setState(() {
                  _showScanner = false;
                });
              },
              icon: const Icon(Icons.close),
              label: const Text('Chiudi scanner'),
            ),
          ),
      ],
    );
  }

  Widget _buildShowQrStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        if (_choseScanFirst) ...[
          _buildInfoCard(
            icon: Icons.info_outline,
            title: 'Mostra questo QR all\'altro dispositivo',
            subtitle:
                'Hai già scansionato $_lastScannedDeviceName.\n'
                'Ora l\'altro catechista deve scansionare il tuo QR.',
            color: Colors.green,
          ),
        ] else ...[
          _buildInfoCard(
            icon: Icons.qr_code,
            title: 'Mostra il tuo QR',
            subtitle:
                'Mostra questo QR all\'altro catechista per farlo scansionare.',
            color: colorScheme.primary,
          ),
        ],
        const SizedBox(height: 16),
        if (_qrData != null)
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(
                data: _qrData!,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (_waitingForReciprocal) ...[
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text(
                'In attesa che l\'altro completi l\'associazione...',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ],
        if (!_choseScanFirst && !_waitingForReciprocal) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _proceedToScanAfterShow,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Ora scansiona il QR partner'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Dopo che l\'altro ha scansionato il tuo QR,\npremi qui per scansionare il suo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ],
    );
  }

  Widget _buildCompleteStep(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.check_circle_outline,
                size: 72, color: Colors.green[400]),
            const SizedBox(height: 16),
            Text(
              'Associazione completata!',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _lastScannedDeviceName != null
                  ? 'Dispositivo associato: $_lastScannedDeviceName'
                  : 'I dispositivi sono stati associati con successo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Ora puoi tornare alla pagina di sincronizzazione '
              'per avviare la sincronizzazione dei dati.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _resetWizard,
                    child: const Text('Associa altro dispositivo'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => context.pop(),
                    child: const Text('Torna alla sync'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBanner(
      ThemeData theme, String message, {required bool isError}) {
    final color = isError ? theme.colorScheme.error : Colors.green[700]!;
    final bgColor = isError
        ? theme.colorScheme.errorContainer
        : Colors.green.withValues(alpha: 0.1);
    final borderColor = isError
        ? theme.colorScheme.error.withValues(alpha: 0.3)
        : Colors.green.withValues(alpha: 0.3);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.info_outline : Icons.check_circle,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() {
              if (isError) {
                _errorMessage = null;
              } else {
                _successMessage = null;
              }
            }),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}


