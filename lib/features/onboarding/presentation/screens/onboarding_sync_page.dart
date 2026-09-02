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
import '../../../../shared/widgets/loading_overlay.dart';

enum _OnboardingStep {
  roleChoice,
  actionChoice,
  showQr,
  scanQr,
  pairingVerification,
  syncing,
  complete,
  error,
}

class OnboardingSyncPage extends ConsumerStatefulWidget {
  const OnboardingSyncPage({super.key});

  @override
  ConsumerState<OnboardingSyncPage> createState() => _OnboardingSyncPageState();
}

class _OnboardingSyncPageState extends ConsumerState<OnboardingSyncPage> {
  final P2PSecurityService _security = P2PSecurityService();

  _OnboardingStep _currentStep = _OnboardingStep.roleChoice;

  P2PSyncRole _selectedRole = P2PSyncRole.mioDispositivo;
  bool _choseScanFirst = false;

  String? _qrData;
  String? _errorMessage;
  String? _successMessage;
  String? _syncedDeviceName;
  String? _pairingCode;

  MobileScannerController? _scannerController;

  bool _isPairing = false;
  bool _syncCompleted = false;
  bool _syncStarted = false;
  bool _manualRetryStarted = false;
  bool _isLoading = false;
  String? _scannedDeviceId;
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

  void _proceedToActionChoice() {
    setState(() {
      _currentStep = _OnboardingStep.actionChoice;
      _errorMessage = null;
    });
  }

  void _chooseScanFirst() {
    setState(() {
      _choseScanFirst = true;
      _currentStep = _OnboardingStep.scanQr;
      _errorMessage = null;
      _isLoading = true;
    });
    _openScanner();
  }

  void _chooseShowFirst() {
    setState(() {
      _choseScanFirst = false;
      _currentStep = _OnboardingStep.showQr;
      _errorMessage = null;
      _isLoading = true;
    });
    _startShowQrWithP2p();
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

  void _startShowQrWithP2p() {
    _resetState();
    _watchP2pState();
    _startP2pAdvertiseOnly();
  }

  void _startDiscoverOnly(String targetEndpoint) {
    _resetState();
    _watchP2pState();
    _startP2pDiscoverOnly(targetEndpoint);
  }

  void _resetState() {
    _syncCompleted = false;
    _syncStarted = false;
    _manualRetryStarted = false;
    _isPairing = false;
    _scannedDeviceId = null;
  }

  void _startP2pAdvertiseOnly() {
    if (_isPairing) return;
    _isPairing = true;
    ref.read(nearbySyncServiceProvider).startPairingAdvertiseOnly();
    _pairingTimeoutTimer = Timer(const Duration(seconds: 120), () {
      if (mounted && !_syncCompleted) {
        setState(() {
          _errorMessage =
              'Tempo scaduto. Assicurati che l\'altro dispositivo '
              'sia in modalità associazione.';
          _isPairing = false;
          _currentStep = _OnboardingStep.error;
        });
        _stopP2p();
      }
    });
  }

  void _startP2pDiscoverOnly(String targetEndpoint) {
    if (_isPairing) return;
    _isPairing = true;
    ref
        .read(nearbySyncServiceProvider)
        .startPairingDiscoverOnly(targetEndpoint);
    _pairingTimeoutTimer = Timer(const Duration(seconds: 120), () {
      if (mounted && !_syncCompleted) {
        setState(() {
          _errorMessage =
              'Tempo scaduto. Assicurati che l\'altro dispositivo '
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

      if (state.status == P2PSyncStatus.pairingVerification) {
        _pairingTimeoutTimer?.cancel();
        if (state.pairingCode != null &&
            _currentStep != _OnboardingStep.pairingVerification) {
          setState(() {
            _currentStep = _OnboardingStep.pairingVerification;
            _pairingCode = state.pairingCode;
            _syncedDeviceName = state.connectedDeviceName;
            _errorMessage = null;
          });
        }
      } else if (state.status == P2PSyncStatus.syncing && !_syncCompleted) {
        _pairingTimeoutTimer?.cancel();
        _syncStarted = true;
        setState(() {
          _currentStep = _OnboardingStep.syncing;
          _syncProgressTotal = state.totalRecordsToExchange;
          _syncProgressCurrent =
              state.sentRecordsCount + state.receivedRecordsCount;
          _syncedDeviceName = state.connectedDeviceName;
        });
      } else if (state.status == P2PSyncStatus.completed) {
        _pairingTimeoutTimer?.cancel();
        if (_syncStarted || _syncCompleted) {
          _onSyncCompleted(state);
        }
      } else if (state.status == P2PSyncStatus.sessionEstablished) {
        if (!_choseScanFirst && _currentStep == _OnboardingStep.showQr) {
          _pairingTimeoutTimer?.cancel();
          _autoSwitchToScanner();
        }
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

  void _autoSwitchToScanner() {
    if (mounted && _currentStep != _OnboardingStep.scanQr) {
      setState(() {
        _currentStep = _OnboardingStep.scanQr;
        _errorMessage = null;
      });
      _openScanner();
    }
  }

  /// True se il catechista locale risulta in almeno una classe ricevuta.
  /// Controlla sia il constant `local_catechist_id` (legacy/onboarding)
  /// sia lo stabile `catechistId` (cat_...) via creator/associated per
  /// gestire tutte le classi selezionate (anche multiple).
  bool _isLocalUserInAnyClass() {
    try {
      final classesBox = LocalDatabase.classes();
      const localId = AuthService.localUserId;
      final localCat = AuthService.getCatechistId();
      for (final key in classesBox.keys) {
        final data = LocalDatabase.toStringDynamicMap(classesBox.get(key));
        final ids = (data['catechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        if (ids.contains(localId) || ids.contains(localCat)) return true;
        final creator = data['creatorCatechistId']?.toString() ?? '';
        if (creator == localCat) return true;
        final associated = (data['associatedCatechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        if (associated.contains(localCat)) return true;
        // Se la classe selezionata è stata ricevuta con tutte le sue
        // proprietà, anche una sola corrispondenza basta per considerare
        // il sync riuscito per "tutte le classi selezionate" dal mittente.
      }
    } catch (_) {}
    return false;
  }

  // Verifica tutte le classi condivise se necessario in futuro
  // ignore: unused_element
  bool _hasAllSharedClasses(List<String> expectedIds) {
    if (expectedIds.isEmpty) return _isLocalUserInAnyClass();
    try {
      final box = LocalDatabase.classes();
      for (final id in expectedIds) {
        if (!box.containsKey(id)) return false;
        final data = LocalDatabase.toStringDynamicMap(box.get(id));
        final ids = (data['catechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        final cat = AuthService.getCatechistId();
        final creator = data['creatorCatechistId']?.toString() ?? '';
        final associated = (data['associatedCatechistIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        final inClass = ids.contains('local_catechist_id') ||
            ids.contains(cat) ||
            creator == cat ||
            associated.contains(cat);
        if (!inClass) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _onSyncCompleted(P2PSyncState state) async {
    if (_syncCompleted) return;

    // Il servizio emette `completed` anche appena dopo la conferma del codice
    // pairing, PRIMA che i dati della classe siano effettivamente arrivati.
    // In quel caso non fallire subito: forza una sincronizzazione manuale e
    // attendi (finestra limitata) che l'associazione alla classe arrivi.
    var found = _isLocalUserInAnyClass();
    if (!found && !_manualRetryStarted) {
      _manualRetryStarted = true;
      addLog(
        'INFO',
        'Sync completata ma classe non ancora presente: avvio sync manuale di recupero',
      );
      final service = ref.read(nearbySyncServiceProvider);
      unawaited(service.triggerManualSync());
      for (int i = 0; i < 60 && !found; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        found = _isLocalUserInAnyClass();
      }
    }

    if (!found || !AuthService.hasLocalAnagrafica()) {
      setState(() {
        _errorMessage = !found
            ? 'Sincronizzazione completata ma non risulti in '
                  'nessuna classe. Assicurati che l\'altro catechista ti abbia '
                  'aggiunto al gruppo.'
            : 'Sincronizzazione completata ma l\'account non è stato '
                  'configurato con i dati condivisi. Riprova l\'associazione.';
        _currentStep = _OnboardingStep.error;
        _isPairing = false;
      });
      return;
    }

    LocalDatabase.auth().put('onboarding_completed', true);

    _syncCompleted = true;
    setState(() {
      _currentStep = _OnboardingStep.complete;
      _successMessage =
          'Sei stato aggiunto alla classe '
                  '${state.connectedDeviceName != null ? "di ${state.connectedDeviceName}" : ""}!'
              .trim();
      _isPairing = false;
      _isLoading = false;
    });
  }

  Future<void> _onQrScanned(BarcodeCapture capture) async {
    if (_scannedDeviceId != null) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      // QR della Catena di Fiducia (trust/approvazione del Responsabile):
      // non è un QR di associazione. Guida l'utente verso la schermata
      // corretta invece di mostrare il generico "QR code non valido".
      final qrType = P2PSecurityService.classifyQrPayload(raw);
      if (qrType == P2PQrType.trust) {
        if (mounted) {
          setState(
            () => _errorMessage =
                'Questo è il QR di fiducia del Responsabile: si importa da '
                '"Catena di fiducia" → "Scansiona QR di fiducia", non qui. '
                'Per associare il dispositivo usa il QR mostrato dall\'altro '
                'dispositivo.',
          );
        }
        return;
      }
      if (qrType == P2PQrType.approval) {
        if (mounted) {
          setState(
            () => _errorMessage =
                'Questo è un QR di approvazione del Responsabile: si riceve da '
                '"Catena di fiducia" → "Ricevi approvazione", non qui. Per '
                'associare il dispositivo usa il QR mostrato dall\'altro '
                'dispositivo.',
          );
        }
        return;
      }

      final remoteIdentity = P2PSecurityService.parseQrPayload(raw);
      if (remoteIdentity == null) {
        if (mounted) setState(() => _errorMessage = 'QR code non valido.');
        return;
      }

      final existing = await _security.getAssociation(remoteIdentity.deviceId);
      if (existing != null && existing.isValid) {
        if (mounted) {
          setState(() => _errorMessage = 'Dispositivo già associato.');
        }
        return;
      }

      final sharedSecret = await _security.computeStaticSharedSecret(
        remoteIdentity.publicKeyBase64,
      );
      final service = ref.read(nearbySyncServiceProvider);
      await service.storePendingAssociation(
        deviceId: remoteIdentity.deviceId,
        deviceName: remoteIdentity.deviceName,
        publicKeyBase64: remoteIdentity.publicKeyBase64,
        fingerprint: remoteIdentity.fingerprint,
        sharedSecretBase64: sharedSecret,
      );

      _stopScanner();
      _scannedDeviceId = remoteIdentity.deviceId;
      _syncedDeviceName = remoteIdentity.deviceName;

      if (mounted) {
        setState(() {
          _currentStep = _OnboardingStep.showQr;
          _errorMessage = null;
        });
        if (_choseScanFirst) {
          _startDiscoverOnly(remoteIdentity.connectionEndpoint);
        } else {
          // Secondo QR scansionato (show-first path): completa pairing
          await service.completePairingAfterQrScan(remoteIdentity.deviceId);
        }
      }
      return;
    }
  }

  void _onConfirmPairingCode() async {
    final service = ref.read(nearbySyncServiceProvider);
    await service.confirmPairingCode();

    final state = service.currentState;
    if (state.awaitingCatechistIdChoice) {
      final resolved = await _showCatechistIdChoiceDialog(state);
      if (resolved != null) {
        await service.chooseCatechistId(resolved);
      }
    }

    addLog('INFO', 'Codice pairing confermato, attesa sincronizzazione dati');
    if (!mounted) return;

    // Dalla conferma in poi siamo nella fase di sincronizzazione: senza
    // questo flag l'evento `completed` emesso dal servizio veniva ignorato
    // (il ricevente non osserva mai lo stato `syncing`, impostato solo da chi
    // avvia la sync) e la UI restava bloccata su "Sincronizzazione in corso".
    _syncStarted = true;
    setState(() {
      _currentStep = _OnboardingStep.syncing;
      _successMessage = 'Sincronizzazione dati classe in corso...';
    });

    // Se il remoto ha già confermato prima di noi, il servizio è già passato
    // a `completed` e l'evento nello stream è stato perso: completa subito.
    final latest = ref.read(nearbySyncServiceProvider).currentState;
    if (latest.status == P2PSyncStatus.completed && !_syncCompleted) {
      await _onSyncCompleted(latest);
    }
  }

  Future<String?> _showCatechistIdChoiceDialog(P2PSyncState state) async {
    final localId = state.pendingCatechistChoiceLocalId ?? '';
    final remoteId = state.pendingCatechistChoiceRemoteId ?? '';
    final remoteName =
        state.pendingCatechistChoiceRemoteName ?? 'dispositivo remoto';
    final defaultId = state.pendingCatechistChoiceDefault ?? localId;
    String chosenValue = defaultId;

    final chosen = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          String selected = chosenValue;
          return AlertDialog(
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
                  RadioGroup<String>(
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
                          subtitle: Text(
                            'Identità: $localId',
                            style: const TextStyle(fontSize: 11),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<String>(
                          value: remoteId,
                          title: Text(remoteName),
                          subtitle: Text(
                            'Identità: $remoteId',
                            style: const TextStyle(fontSize: 11),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
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
          );
        },
      ),
    );

    return chosen ?? defaultId;
  }

  void _onRejectPairingCode() {
    final service = ref.read(nearbySyncServiceProvider);
    service.rejectPairingCode();
    setState(() {
      _errorMessage =
          'Codice di verifica non corrispondente. Associazione annullata.';
      _currentStep = _OnboardingStep.error;
      _isPairing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Mostra banner di caricamento durante operazioni pesanti
    final showLoadingBanner = _isLoading &&
        (_currentStep == _OnboardingStep.showQr ||
            _currentStep == _OnboardingStep.scanQr ||
            _currentStep == _OnboardingStep.pairingVerification ||
            _currentStep == _OnboardingStep.syncing);

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Unisciti a una classe'),
          automaticallyImplyLeading: false,
        ),
        body: Column(
          children: [
            if (showLoadingBanner)
              LoadingBanner(
                message: _getLoadingMessage(),
              ),
            Expanded(
              child: SafeArea(child: _buildBody()),
            ),
          ],
        ),
      ),
    );
  }

  String _getLoadingMessage() {
    switch (_currentStep) {
      case _OnboardingStep.showQr:
        return _choseScanFirst
            ? 'In attesa di connessione...'
            : 'Connessione in corso...';
      case _OnboardingStep.scanQr:
        return 'Scansione QR in corso...';
      case _OnboardingStep.pairingVerification:
        return 'Verifica codice sicurezza...';
      case _OnboardingStep.syncing:
        return 'Sincronizzazione in corso...';
      default:
        return 'Operazione in corso...';
    }
  }

  Widget _buildBody() {
    switch (_currentStep) {
      case _OnboardingStep.roleChoice:
        return _buildRoleChoice();
      case _OnboardingStep.actionChoice:
        return _buildActionChoice();
      case _OnboardingStep.showQr:
        return _buildShowQrStep();
      case _OnboardingStep.scanQr:
        return _buildScanQrStep();
      case _OnboardingStep.pairingVerification:
        return _buildPairingVerification();
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
            child: const Icon(
              Icons.people_rounded,
              size: 36,
              color: Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Scegli il tipo di associazione',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Entrambi i dispositivi devono selezionare lo STESSO ruolo '
            'per poter sincronizzare. Accordati con l\'altro catechista.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text(
                'Continua',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              onPressed: _proceedToActionChoice,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildRoleOption(
    P2PSyncRole role,
    IconData icon,
    String title,
    String description,
  ) {
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
              color: isSelected
                  ? const Color(0xFF174A7E)
                  : Colors.grey.shade200,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF174A7E)
                      : const Color(0xFF174A7E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? Colors.white : const Color(0xFF174A7E),
                  size: 26,
                ),
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
                        color: isSelected
                            ? const Color(0xFF174A7E)
                            : Colors.black87,
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
                Icon(
                  Icons.check_circle_rounded,
                  color: const Color(0xFF174A7E),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionChoice() {
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
            child: const Icon(
              Icons.bluetooth_rounded,
              size: 36,
              color: Color(0xFF174A7E),
            ),
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
          const SizedBox(height: 12),
          Text(
            'Per unirti a una classe esistente, deve esserci uno scambio '
            'di QR code tra i due dispositivi.\n\n'
            'Uno dei due deve iniziare scansionando il QR dell\'altro.\n'
            'Dopo la scansione, il passaggio sarà automatico.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text(
                'Inquadra QR del partner',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              onPressed: _chooseScanFirst,
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.qr_code_rounded),
              label: const Text(
                'Mostra QR al partner',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              onPressed: _chooseShowFirst,
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
            child: Icon(
              _choseScanFirst || _scannedDeviceId == null
                  ? Icons.qr_code_rounded
                  : Icons.check_circle_rounded,
              size: 36,
              color: _choseScanFirst || _scannedDeviceId == null
                  ? const Color(0xFF174A7E)
                  : Colors.green,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _choseScanFirst
                ? 'Mostra questo QR al partner'
                : _scannedDeviceId != null
                ? 'QR acquisito!'
                : 'Mostra il tuo QR',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _choseScanFirst
                ? 'Hai già scansionato il QR del partner.\n'
                      'Ora l\'altro catechista deve scansionare il tuo QR.'
                : _scannedDeviceId != null
                ? 'In attesa della verifica del codice di sicurezza...'
                : 'Quando l\'altro dispositivo lo scansionerà,\n'
                      'passerai automaticamente alla fotocamera.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          if (_choseScanFirst || _scannedDeviceId == null) ...[
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
          ] else
            const Column(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 48,
                  color: Colors.green,
                ),
                SizedBox(height: 8),
                Text(
                  'Scambio completato, attesa verifica...',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          if (_isPairing && (_choseScanFirst || _scannedDeviceId == null)) ...[
            const SizedBox(height: 20),
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
                  'In attesa connessione...',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
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
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              if (_scannerController != null)
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
              Text(
                _choseScanFirst
                    ? 'Inquadra il QR dell\'altro catechista'
                    : 'Ora scansiona il QR del partner',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _choseScanFirst
                    ? 'Dopo la scansione passerai automaticamente\n'
                          'alla schermata "Mostra QR".'
                    : 'Il QR si trova nella schermata "Mostra QR"\n'
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

  Widget _buildPairingVerification() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF174A7E).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.lock_rounded,
              size: 36,
              color: Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Verifica sicurezza',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Conferma che su entrambi i dispositivi\nsia visualizzato lo STESSO codice:',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          if (_pairingCode != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF174A7E).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF174A7E).withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                _pairingCode!,
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                  color: Color(0xFF174A7E),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Se i codici NON corrispondono, annulla:\n'
            'potrebbe esserci un tentativo di intrusione.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.check_rounded),
              label: const Text(
                'Codici corrispondono, conferma',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              onPressed: _onConfirmPairingCode,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.close_rounded),
              label: const Text(
                'Codici DIVERSI, Annulla',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              onPressed: _onRejectPairingCode,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
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
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF174A7E),
              ),
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
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          if (_successMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _successMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black87,
                height: 1.4,
              ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.groups_rounded),
              label: const Text(
                'Gestisci le tue classi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              onPressed: () {
                context.go('/onboarding-classes');
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
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(
                'Riprova',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              onPressed: _retry,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void addLog(String level, String message) {
    try {
      ref.read(nearbySyncServiceProvider).addLog(level, message);
    } catch (_) {}
  }

  void _retry() {
    _pairingTimeoutTimer?.cancel();
    _p2pStateSub?.cancel();
    _stopP2p();
    _stopScanner();
    _syncCompleted = false;
    _syncStarted = false;
    _manualRetryStarted = false;
    _isPairing = false;
    _scannedDeviceId = null;
    _errorMessage = null;
    _successMessage = null;
    _pairingCode = null;
    setState(() {
      _currentStep = _OnboardingStep.roleChoice;
    });
  }
}
