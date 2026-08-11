import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/providers/current_class_provider.dart';
import '../../../core/providers/nearby_sync_provider.dart';
import '../../../core/storage/local_database.dart';
import '../p2p/p2p_sync_service.dart';
import '../p2p/p2p_security_service.dart';

class P2PIdentityWithConnection extends P2PIdentity {
  const P2PIdentityWithConnection({
    required super.deviceId,
    required super.deviceName,
    required super.username,
    required super.publicKeyBase64,
    required super.fingerprint,
    required super.connectionEndpoint,
  });

  factory P2PIdentityWithConnection.fromIdentity(P2PIdentity id) =>
      P2PIdentityWithConnection(
        deviceId: id.deviceId,
        deviceName: id.deviceName,
        username: id.username,
        publicKeyBase64: id.publicKeyBase64,
        fingerprint: id.fingerprint,
        connectionEndpoint: id.connectionEndpoint,
      );
}

enum _AssociationStep {
  roleChoice,
  showQrAndWait,
  scanFirstQr,
  showSecondQr,
  scanSecondQr,
  pairingCodeVerification,
  onboardingSync,
  complete,
}

class AssociateDeviceScreen extends ConsumerStatefulWidget {
  const AssociateDeviceScreen({super.key});

  @override
  ConsumerState<AssociateDeviceScreen> createState() =>
      _AssociateDeviceScreenState();
}

class _AssociateDeviceScreenState
    extends ConsumerState<AssociateDeviceScreen> {
  final P2PSecurityService _security = P2PSecurityService();

  bool get _isClassCreator {
    try {
      final box = LocalDatabase.classes();
      const uid = AuthService.localUserId;
      final localCatechistId = AuthService.getCatechistId();
      for (final key in box.keys) {
        final data = Map<String, dynamic>.from(box.get(key) as Map);
        final ids = (data['catechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        if (ids.contains(uid)) {
          final creatorCatechistId = data['creatorCatechistId'] as String? ?? '';
          if (creatorCatechistId.isEmpty) return true;
          return creatorCatechistId == localCatechistId;
        }
      }
    } catch (_) {}
    return true;
  }

  _AssociationStep _currentStep = _AssociationStep.roleChoice;

  bool _isFirstToShowQr = false;

  P2PSyncRole _selectedRole = P2PSyncRole.mioDispositivo;
  final bool _isOnboarding = false;

  /// Classi scelte quando il ruolo è "Altro Catechista": solo queste classi
  /// vengono condivise/sincronizzate con il dispositivo remoto.
  Set<String> _selectedSharedClassIds = {};

  String? _qrData;
  String? _errorMessage;
  String? _successMessage;

  MobileScannerController? _scannerController;

  P2PIdentityWithConnection? _remoteIdentity;
  P2PIdentityWithConnection? _localIdentity;

  bool _isPairing = false;
  bool _pairingComplete = false;
  Timer? _pairingTimeoutTimer;
  StreamSubscription<P2PSyncState>? _p2pStateSub;
  bool _pairingDialogShown = false;
  bool _isConfirmingPairing = false;

  String? _pairingCode;

  bool _awaitingVerification = false;

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
    _stopP2pPairing();
    super.dispose();
  }

  Future<void> _initData() async {
    try {
      final identity = await _security.getLocalIdentity();
      final qrData = await _generateQrData();
      if (mounted) {
        setState(() {
          _localIdentity = P2PIdentityWithConnection.fromIdentity(identity);
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

    if (role == P2PSyncRole.altroCatechista) {
      final current = ref.read(currentClassProvider);
      final classes = ref.read(myClassesProvider);
      final valid =
          current != null && current.isNotEmpty && classes.any((c) => c.id == current);
      final initial = valid ? current : (classes.isNotEmpty ? classes.first.id : null);
      setState(() => _selectedSharedClassIds = initial != null ? {initial} : {});
      ref
          .read(nearbySyncServiceProvider)
          .setAssociationSharedClasses(_selectedSharedClassIds);
    } else {
      setState(() => _selectedSharedClassIds = {});
      ref.read(nearbySyncServiceProvider).setAssociationSharedClasses({});
    }
  }

  void _toggleSharedClass(String classId) {
    setState(() {
      if (!_selectedSharedClassIds.remove(classId)) {
        _selectedSharedClassIds.add(classId);
      }
    });
    ref.read(nearbySyncServiceProvider).setAssociationSharedClasses(_selectedSharedClassIds);
  }

  void _chooseShowQrFirst() {
    _isFirstToShowQr = true;
    setState(() {
      _errorMessage = null;
      _successMessage = null;
      _currentStep = _AssociationStep.showQrAndWait;
    });
    _startAdvertiseOnly();
  }

  void _chooseScanFirst() {
    _isFirstToShowQr = false;
    setState(() {
      _errorMessage = null;
      _successMessage = null;
      _currentStep = _AssociationStep.scanFirstQr;
    });
    _openScanner();
  }

  void _openScanner() {
    setState(() {
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
  }

  void _resetWizard() {
    _stopScanner();
    _pairingTimeoutTimer?.cancel();
    _p2pStateSub?.cancel();
    _stopP2pPairing();
    ref.read(nearbySyncServiceProvider).setAssociationSharedClasses({});
    setState(() {
      _currentStep = _AssociationStep.roleChoice;
      _errorMessage = null;
      _successMessage = null;
      _remoteIdentity = null;
      _isPairing = false;
      _pairingComplete = false;
      _pairingCode = null;
      _awaitingVerification = false;
      _pairingDialogShown = false;
      _isConfirmingPairing = false;
    });
  }

  void _stopP2pPairing() {
    try {
      ref.read(nearbySyncServiceProvider).stopPairingMode();
    } catch (_) {}
  }

  void _startAdvertiseOnly() {
    _pairingComplete = false;
    _isPairing = false;
    _watchP2pState();
    _startP2pAdvertiseOnly();
  }

  void _startDiscoverOnly(String targetEndpoint) {
    _pairingComplete = false;
    _isPairing = false;
    _watchP2pState();
    ref.read(nearbySyncServiceProvider).startPairingDiscoverOnly(targetEndpoint);
  }

  void _startP2pAdvertiseOnly() {
    if (_isPairing) return;
    _isPairing = true;
    ref.read(nearbySyncServiceProvider).startPairingAdvertiseOnly();
    _pairingTimeoutTimer = Timer(const Duration(seconds: 120), () {
      if (mounted && !_pairingComplete) {
        setState(() {
          _errorMessage = 'Tempo scaduto. Nessun dispositivo si è connesso.';
          _isPairing = false;
        });
        _stopP2pPairing();
      }
    });
  }

  void _watchP2pState() {
    _p2pStateSub?.cancel();
    _pairingDialogShown = false;
    final service = ref.read(nearbySyncServiceProvider);
    _p2pStateSub = service.onStateChanged.listen((state) {
      if (!mounted) return;

      if (state.status == P2PSyncStatus.sessionEstablished) {
        _pairingTimeoutTimer?.cancel();

        if (_isFirstToShowQr &&
            _currentStep == _AssociationStep.showQrAndWait) {
          _onConnectionReceivedByQrHost();
        } else if (!_isFirstToShowQr &&
            _currentStep == _AssociationStep.scanFirstQr) {
          _onConnectedByScanner();
        }

        if (_isFirstToShowQr &&
            _currentStep == _AssociationStep.scanSecondQr &&
            _awaitingVerification) {
          _onSecondQrScannedComplete();
        }
      } else if (state.status == P2PSyncStatus.pairingVerification) {
        if (!_pairingDialogShown && !_pairingComplete) {
          _pairingTimeoutTimer?.cancel();
          if (state.pairingCode != null) {
            setState(() {
              _pairingCode = state.pairingCode;
              _currentStep = _AssociationStep.pairingCodeVerification;
            });
          }
        }
      } else if (state.status == P2PSyncStatus.onboardingSync) {
        if (_pairingComplete) return;
        setState(() {
          _currentStep = _AssociationStep.onboardingSync;
          _successMessage = 'Sincronizzazione dati in corso...';
        });
      } else if (state.status == P2PSyncStatus.completed) {
        if (_pairingComplete || _isConfirmingPairing) return;
        _pairingComplete = true;
        setState(() {
          _currentStep = _AssociationStep.complete;
          _successMessage = _remoteIdentity != null
              ? 'Associazione completata con ${_remoteIdentity!.username}'
              : 'Associazione completata!';
          _errorMessage = null;
          _isPairing = false;
        });
      } else if (state.status == P2PSyncStatus.error) {
        if (!_pairingComplete && _isPairing && !_isConfirmingPairing) {
          setState(() {
            _errorMessage = state.errorMessage ?? 'Errore di connessione.';
            _isPairing = false;
          });
        }
      }
    });
  }

  void _onConnectionReceivedByQrHost() {
    addLog('INFO', 'Connessione ricevuta! Passo alla scansione del QR partner.');
    setState(() {
      _successMessage = 'Dispositivo connesso! Ora inquadra il QR del partner.';
      _currentStep = _AssociationStep.scanSecondQr;
    });
    _openScanner();
  }

  void _onConnectedByScanner() {
    addLog('INFO', 'Connessione stabilita! Mostro il mio QR per lo scambio chiavi.');
    setState(() {
      _successMessage = 'Connesso! Mostra questo QR al partner.';
      _currentStep = _AssociationStep.showSecondQr;
    });
  }

  Future<void> _onQrScanned(BarcodeCapture capture) async {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      final remoteIdentity = P2PSecurityService.parseQrPayload(raw);
      if (remoteIdentity == null) {
        setState(() => _errorMessage = 'QR code non valido.');
        return;
      }

      if (_remoteIdentity != null &&
          _remoteIdentity!.deviceId == remoteIdentity.deviceId) {
        return;
      }

      final remoteWithConn =
          P2PIdentityWithConnection.fromIdentity(remoteIdentity);

      if (mounted) {
        setState(() {
          _remoteIdentity = remoteWithConn;
          _errorMessage = null;
        });
      }

      if (_isFirstToShowQr) {
        await _onSecondQrScanned(remoteWithConn);
      } else {
        await _onFirstQrScanned(remoteWithConn);
      }
      return;
    }
  }

  Future<void> _onFirstQrScanned(
      P2PIdentityWithConnection remote) async {
    addLog('INFO', 'Primo QR scansionato: ${remote.username} (${remote.deviceId})');

    _stopScanner();

    final existing = await _security.getAssociation(remote.deviceId);
    if (existing != null && existing.isValid) {
      if (mounted) {
        setState(() => _errorMessage = 'Dispositivo già associato.');
      }
      return;
    }

    final remotePublicKey = remote.publicKeyBase64;
    final sharedSecret =
        await _security.computeStaticSharedSecret(remotePublicKey);

    final service = ref.read(nearbySyncServiceProvider);
    await service.storePendingAssociation(
      deviceId: remote.deviceId,
      deviceName: remote.deviceName,
      publicKeyBase64: remotePublicKey,
      fingerprint: remote.fingerprint,
      sharedSecretBase64: sharedSecret,
    );

    if (mounted) {
      setState(() {
        _successMessage =
            'QR scansionato! Mi connetto a ${remote.username}...';
      });
    }

    _startDiscoverOnly(remote.connectionEndpoint);
  }

  Future<void> _onSecondQrScanned(
      P2PIdentityWithConnection remote) async {
    addLog('INFO',
        'Secondo QR scansionato: ${remote.username} (${remote.deviceId})');

    _stopScanner();

    final existing = await _security.getAssociation(remote.deviceId);
    if (existing != null && existing.isValid) {
      if (mounted) {
        setState(() => _errorMessage = 'Dispositivo già associato.');
      }
      return;
    }

    final remotePublicKey = remote.publicKeyBase64;
    final sharedSecret =
        await _security.computeStaticSharedSecret(remotePublicKey);

    final service = ref.read(nearbySyncServiceProvider);
    await service.storePendingAssociation(
      deviceId: remote.deviceId,
      deviceName: remote.deviceName,
      publicKeyBase64: remotePublicKey,
      fingerprint: remote.fingerprint,
      sharedSecretBase64: sharedSecret,
    );

    if (mounted) {
      setState(() {
        _successMessage = 'QR scansionato! Codice di verifica in arrivo...';
      });
    }

    _awaitingVerification = true;

    await service.completePairingAfterQrScan(remote.deviceId);
  }

  void _onSecondQrScannedComplete() {
    addLog('INFO', 'Secondo QR scan completato, attesa verifica pairing');
  }

  void _showPairingCodeDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Verifica codice sicurezza'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Conferma che su entrambi i dispositivi\n'
                'sia visualizzato lo STESSO codice:',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _pairingCode ?? '',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Se i codici NON corrispondono, annulla:\n'
                'potrebbe esserci un tentativo di intrusione.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _rejectPairing();
              },
              child: const Text('Codici DIVERSI, Annulla',
                  style: TextStyle(color: Colors.red)),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _confirmPairingCodeAndSync();
              },
              child: const Text('Codici corrispondono'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmPairingCodeAndSync() async {
    final service = ref.read(nearbySyncServiceProvider);

    if (service.currentState.status != P2PSyncStatus.pairingVerification) {
      addLog('WARN', 'confirmPairingCodeAndSync chiamato fuori da pairingVerification');
      return;
    }

    _isConfirmingPairing = true;
    await service.confirmPairingCode();
    final awaitingChoice = service.currentState.awaitingCatechistIdChoice;
    _isConfirmingPairing = false;

    // Discordanza tra due catechistId su dispositivi della stessa persona
    // ("Mio Dispositivo"): chiedi quale identità conservare (default: la
    // classe che invia).
    if (awaitingChoice) {
      addLog('INFO', 'Rilevata discordanza catechistId, richiesco scelta');
      await _showCatechistIdChoiceDialog();
    }
    if (!mounted) return;

    setState(() {
      _currentStep = _AssociationStep.onboardingSync;
      _successMessage = 'Sincronizzazione dati classe in corso...';
    });

    addLog('INFO', 'Codice verificato, avvio onboarding sync');

    if (_isOnboarding) {
      await _performOnboardingSync();
    } else {
      await _registerCatechistInClass();
    }

    if (mounted) {
      setState(() {
        _currentStep = _AssociationStep.complete;
        _pairingComplete = true;
        _successMessage = _remoteIdentity != null
            ? 'Associazione completata con ${_remoteIdentity!.username}'
            : 'Associazione completata!';
        _errorMessage = null;
        _isPairing = false;
      });
    }
  }

  Future<void> _rejectPairing() async {
    final service = ref.read(nearbySyncServiceProvider);
    await service.rejectPairingCode();
    _resetWizard();
  }

  /// Dialogo mostrato quando due dispositivi della stessa persona ("Mio
  /// Dispositivo") hanno già classi con due catechistId diversi. L'utente
  /// sceglie quale identità conservare (default: quella della classe che invia).
  Future<void> _showCatechistIdChoiceDialog() async {
    final service = ref.read(nearbySyncServiceProvider);
    final st = service.currentState;
    final localId = st.pendingCatechistChoiceLocalId ?? '';
    final remoteId = st.pendingCatechistChoiceRemoteId ?? '';
    final remoteName =
        st.pendingCatechistChoiceRemoteName ?? 'dispositivo remoto';
    final defaultId = st.pendingCatechistChoiceDefault ?? localId;

    String chosenValue = defaultId;
    final chosen = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Due identità rilevate'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Entrambi i dispositivi contengono classi associate a due '
                'identità diverse. Conservando una sola identità, tutti i '
                'dispositivi della stessa persona la condivideranno.',
                textAlign: TextAlign.justify,
              ),
              const SizedBox(height: 16),
              StatefulBuilder(
                builder: (ctx, setState) {
                  String selected = chosenValue;
                  return RadioGroup<String>(
                    groupValue: selected,
                    onChanged: (value) {
                      if (value != null) {
                        chosenValue = value;
                        setState(() => selected = value);
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RadioListTile<String>(
                          value: localId,
                          title: const Text('Questo dispositivo'),
                          subtitle: Text('Identità: $localId',
                              style: const TextStyle(fontSize: 11)),
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<String>(
                          value: remoteId,
                          title: Text(remoteName),
                          subtitle: Text('Identità: $remoteId',
                              style: const TextStyle(fontSize: 11)),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(chosenValue),
            child: const Text('Conservare consigliata'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(chosenValue),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    final resolved = chosen ?? defaultId;
    addLog('INFO', 'Identità scelta: $resolved (default: $defaultId)');
    await service.chooseCatechistId(resolved);
  }

  Future<void> _performOnboardingSync() async {
    addLog('INFO', 'Avvio download dati classe (onboarding)');

    final service = ref.read(nearbySyncServiceProvider);

    try {
      final endpointId = service.currentState.connectedDeviceId;
      if (endpointId == null) {
        addLog('ERROR', 'Nessun endpoint connesso per onboarding sync');
        return;
      }

      await service.triggerManualSync();

      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final state = service.currentState;
        if (state.status == P2PSyncStatus.completed) break;
      }

      _ensureLocalCatechistInClass(sharedClassIds: _selectedSharedClassIds);

      addLog('INFO', 'Onboarding sync completato');
    } catch (e) {
      addLog('ERROR', 'Errore durante onboarding sync: $e');
    }
  }

  Future<void> _registerCatechistInClass() async {
    addLog('INFO', 'Registro nuovo catechista nella classe');
    _ensureLocalCatechistInClass(sharedClassIds: _selectedSharedClassIds);
  }

  /// Aggiunge il dispositivo remoto (e il catechista locale) alle classi.
  /// Se [sharedClassIds] è valorizzato (associazione di un ALTRO catechista),
  /// tocca solo quelle classi; altrimenti tutte le classi locali.
  void _ensureLocalCatechistInClass({Set<String>? sharedClassIds}) {
    try {
      final box = LocalDatabase.classes();
      const localId = AuthService.localUserId;
      bool isShared(String key) =>
          sharedClassIds == null ||
          sharedClassIds.isEmpty ||
          sharedClassIds.contains(key);

      if (_remoteIdentity != null) {
        final remoteDeviceId = _remoteIdentity!.deviceId;
        for (final key in box.keys) {
          if (!isShared(key.toString())) continue;
          final data = LocalDatabase.toStringDynamicMap(box.get(key));
          final ids = (data['catechistIds'] as List? ?? [])
              .map((e) => e.toString())
              .toList();
          if (!ids.contains(remoteDeviceId)) {
            ids.add(remoteDeviceId);
            data['catechistIds'] = ids;
            box.put(key, data);
            addLog('INFO',
                'Aggiunto catechista remoto ${_remoteIdentity!.username} alla classe ${data['name']}');
          }
        }
      }
      for (final key in box.keys) {
        if (!isShared(key.toString())) continue;
        final data = LocalDatabase.toStringDynamicMap(box.get(key));
        final ids = (data['catechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        if (!ids.contains(localId)) {
          ids.add(localId);
          data['catechistIds'] = ids;
          box.put(key, data);
          addLog('INFO',
              'Aggiunto catechista locale alla classe ${data['name']}');
        }
      }
    } catch (e) {
      addLog('ERROR', 'Errore _ensureLocalCatechistInClass: $e');
    }
  }

  void addLog(String level, String message) {
    try {
      ref.read(nearbySyncServiceProvider).addLog(level, message);
    } catch (_) {}
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _currentStep == _AssociationStep.roleChoice
              ? () => Navigator.of(context).pop()
              : _resetWizard,
        ),
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
    final steps = _isFirstToShowQr
        ? [
            _AssociationStep.showQrAndWait,
            _AssociationStep.scanSecondQr,
            _AssociationStep.pairingCodeVerification,
            _AssociationStep.onboardingSync,
            _AssociationStep.complete,
          ]
        : [
            _AssociationStep.scanFirstQr,
            _AssociationStep.showSecondQr,
            _AssociationStep.pairingCodeVerification,
            _AssociationStep.onboardingSync,
            _AssociationStep.complete,
          ];

    final labels = _isFirstToShowQr
        ? ['Mostra QR', 'Scansiona', 'Verifica Codice', 'Sincronizza', 'Fatto']
        : ['Scansiona', 'Mostra QR', 'Verifica Codice', 'Sincronizza', 'Fatto'];

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
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[400],
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
      case _AssociationStep.showQrAndWait:
        return _buildShowQrAndWaitStep(theme, colorScheme);
      case _AssociationStep.scanFirstQr:
        return _buildScanFirstQrStep(theme, colorScheme);
      case _AssociationStep.showSecondQr:
        return _buildShowSecondQrStep(theme, colorScheme);
      case _AssociationStep.scanSecondQr:
        return _buildScanSecondQrStep(theme, colorScheme);
      case _AssociationStep.pairingCodeVerification:
        return _buildPairingVerificationStep(theme, colorScheme);
      case _AssociationStep.onboardingSync:
        return _buildOnboardingSyncStep(theme, colorScheme);
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
                  'Associazione dispositivo',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Scegli il ruolo e se sei in fase di onboarding.',
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
                    subtitle: const Text('Sincronizzazione automatica'),
                    secondary: const Icon(Icons.sync),
                    value: P2PSyncRole.mioDispositivo,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_isClassCreator)
                    RadioListTile<P2PSyncRole>(
                      title: const Text('Altro Catechista'),
                      subtitle: const Text(
                          'Richiede conferma prima di sincronizzare'),
                      secondary: const Icon(Icons.how_to_reg),
                      value: P2PSyncRole.altroCatechista,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            if (_selectedRole == P2PSyncRole.altroCatechista)
              _buildSharedClassSelector(theme, colorScheme),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _currentStep = _AssociationStep.showQrAndWait;
                    _errorMessage = null;
                  });
                  _chooseShowQrFirst();
                },
                icon: const Icon(Icons.qr_code),
                label: const Text('Mostra QR (attendere connessione)'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _currentStep = _AssociationStep.scanFirstQr;
                    _errorMessage = null;
                  });
                  _chooseScanFirst();
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scansiona QR partner'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Selettore delle classi da condividere con l'altro catechista.
  /// Solo le classi selezionate verranno sincronizzate con il dispositivo remoto.
  Widget _buildSharedClassSelector(
      ThemeData theme, ColorScheme colorScheme) {
    final myClasses = ref.watch(myClassesProvider);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt_rounded,
                  size: 18, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Classi da sincronizzare',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Con questo dispositivo condividerai SOLO le classi selezionate.\n'
            'Se non selezioni nulla, verranno sincronizzate le classi in comune.',
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          if (myClasses.isEmpty)
            Text(
              'Non fai parte di nessun gruppo.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            )
          else
            Column(
              children: myClasses.map((c) => CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _selectedSharedClassIds.contains(c.id),
                    onChanged: (_) => _toggleSharedClass(c.id),
                    title: Text(
                      c.name,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildShowQrAndWaitStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        _buildInfoCard(
          icon: Icons.qr_code,
          title: 'Mostra questo QR all\'altro dispositivo',
          subtitle:
              'Il tuo dispositivo è in attesa. Non invia richieste.\n'
              'Quando l\'altro dispositivo scansionerà questo QR\ne si connetterà, potrai scansionare il suo QR.',
          color: colorScheme.primary,
        ),
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
        if (_localIdentity != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text('Utente: ${_localIdentity!.username}',
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                Text('Dispositivo: ${_localIdentity!.deviceName}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        if (_isPairing && !_pairingComplete) ...[
          const SizedBox(height: 16),
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
                'In attesa connessione in entrata...',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _resetWizard,
            child: const Text('Annulla e ricomincia'),
          ),
        ),
      ],
    );
  }

  Widget _buildScanFirstQrStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        _buildInfoCard(
          icon: Icons.qr_code_scanner,
          title: 'Scansiona il QR dell\'altro dispositivo',
          subtitle:
              'Inquadra il QR code mostrato dall\'altro catechista.\n'
              'Il QR contiene il nome utente, la chiave pubblica\ne le coordinate per la connessione.',
          color: colorScheme.primary,
        ),
        const SizedBox(height: 16),
        if (_scannerController != null)
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
        else
          const SizedBox(
            height: 280,
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_remoteIdentity != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Column(
                children: [
                  Text('QR scansionato!',
                      style: TextStyle(
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Utente: ${_remoteIdentity!.username}',
                      style: const TextStyle(fontSize: 13)),
                  Text('Dispositivo: ${_remoteIdentity!.deviceName}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildShowSecondQrStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        _buildInfoCard(
          icon: Icons.qr_code,
          title: 'Connesso! Mostra ora questo QR',
          subtitle:
              'L\'altro dispositivo deve inquadrare questo QR\n'
              'per completare lo scambio delle chiavi pubbliche.',
          color: Colors.green,
        ),
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
        if (_isPairing && !_pairingComplete)
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
                'In attesa che il partner scansioni il QR...',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildScanSecondQrStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        _buildInfoCard(
          icon: Icons.qr_code_scanner,
          title: 'Ora scansiona il QR del partner',
          subtitle:
              'Il dispositivo si è connesso. Ora inquadra il QR\n'
              'dell\'altro dispositivo per ricevere la sua chiave pubblica.',
          color: Colors.orange,
        ),
        const SizedBox(height: 16),
        if (_scannerController != null)
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
        else
          const SizedBox(
            height: 280,
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_remoteIdentity != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Text('QR ricevuto: ${_remoteIdentity!.username}',
                  style: TextStyle(color: Colors.green[700])),
            ),
          ),
      ],
    );
  }

  Widget _buildPairingVerificationStep(
      ThemeData theme, ColorScheme colorScheme) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pairingCode != null && !_pairingDialogShown) {
        _pairingDialogShown = true;
        _showPairingCodeDialog();
      }
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.verified_user, size: 64, color: Colors.orange[400]),
            const SizedBox(height: 16),
            const Text(
              'Verifica codice di sicurezza',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Confronta il codice con l\'altro dispositivo...',
              style: TextStyle(color: Colors.grey[600]),
            ),
            if (_pairingCode != null) ...[
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _pairingCode!,
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOnboardingSyncStep(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 20),
            Text(
              _isOnboarding
                  ? 'Download dati classe in corso...'
                  : 'Registrazione in corso...',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isOnboarding
                  ? 'Sto scaricando i dati della classe dal dispositivo\n'
                      'e li decodifico con la chiave pubblica.'
                  : 'Sto registrando il nuovo catechista nella classe.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      ),
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
            if (_remoteIdentity != null) ...[
              Text(
                _remoteIdentity!.username,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800]),
              ),
              const SizedBox(height: 4),
              Text(
                _remoteIdentity!.deviceName,
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              _isOnboarding
                  ? 'Dati della classe scaricati e decodificati.\n'
                      'Ora puoi accedere a tutti i dati.'
                  : 'Nuovo catechista registrato nella classe.\n'
                      'La sincronizzazione continua è attiva.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
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
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/');
                      }
                    },
                    child: const Text('Continua'),
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
