import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:qr_flutter/qr_flutter.dart';

import '../../../shared/widgets/app_scaffold.dart';
import '../../../core/services/encryption_service.dart';
import '../data/classic_sync_models.dart';
import '../domain/classic_connection_manager.dart';
import '../domain/classic_sync_provider.dart';

/// Pagina di accoppiamento bidirezionale tra dispositivi CatechREG.
///
/// CONTESTO PROGETTO:
/// L'accoppiamento (pairing) è il primo passo per abilitare la
/// sincronizzazione tra due dispositivi di catechisti. Il protocollo
/// è bidirezionale e simmetrico:
///
/// 1. Device A genera QR con chiave pubblica ECDH e lo mostra
/// 2. Device B scannerizza il QR, genera la propria chiave ECDH,
///    salva TrustedDevice di A, mostra QR di risposta
/// 3. Device A scannerizza QR risposta, deriva chiave di sessione
///    con ECDH + HKDF, salva TrustedDevice di B
///
/// Entrambi i dispositivi usano Bluetooth Classico RFCOMM per la
/// verifica hardware (prossimità fisica). La chiave ECDH è effimera
/// (generata per ogni sessione di pairing) e la chiave di sessione
/// derivata è persistita nel Box trusted_devices_box.
///
/// Dopo il pairing, viene avviato il server di sincronizzazione
/// persistente per permettere sync automatiche future.
class ClassicPairingPage extends ConsumerStatefulWidget {
  const ClassicPairingPage({super.key});

  @override
  ConsumerState<ClassicPairingPage> createState() =>
      _ClassicPairingPageState();
}

class _ClassicPairingPageState extends ConsumerState<ClassicPairingPage> {
  ClassicPairingFlowState _flowState = const ClassicPairingFlowState();
  MobileScannerController? _scannerController;
  bool _isScanning = false;
  final ClassicConnectionManager _connectionManager =
      ClassicConnectionManager();
  StreamSubscription? _errorSubscription;
  final TextEditingController _deviceNameController = TextEditingController();
  String _savedDeviceName = '';
  String _fallbackDeviceName = 'CatechHub Device';

  // ECDH key pair per questa sessione di pairing (in memoria, non persistito)
  pc.ECPrivateKey? _localEcdhPrivateKey;
  String? _localEcdhPublicKeyBase64;
  String? _sessionNonce;

  @override
  void initState() {
    super.initState();
    _initDeviceName();
    _errorSubscription = _connectionManager.onMessage.listen((msg) {
      if (msg.contains('Errore') || msg.contains('Timeout')) {
        if (mounted) {
          setState(() {
            _flowState = _flowState.copyWith(
              pairingState: ClassicPairingState.errore,
              errorMessage: msg,
              isProcessing: false,
            );
          });
          _stopCamera();
        }
      }
    });
  }

  @override
  void dispose() {
    _stopCamera();
    _errorSubscription?.cancel();
    _deviceNameController.dispose();
    _connectionManager.resetPairingEngine();
    _localEcdhPrivateKey = null;
    _localEcdhPublicKeyBase64 = null;
    _sessionNonce = null;
    super.dispose();
  }

  Future<void> _initDeviceName() async {
    final customName = await _connectionManager.getCustomDeviceName();
    final fallback = await ClassicConnectionManager.resolveDeviceName();
    if (mounted) {
      setState(() {
        _savedDeviceName = customName ?? '';
        _fallbackDeviceName =
            ClassicConnectionManager.stripDeviceNamePrefix(fallback);
        _deviceNameController.text = _savedDeviceName;
      });
    }
  }

  Future<void> _saveDeviceName() async {
    final name = _deviceNameController.text.trim();
    await _connectionManager.saveCustomDeviceName(name);
    if (mounted) {
      setState(() {
        _savedDeviceName = name;
      });
    }
  }

  Future<void> _startPhase1AsDeviceA() async {
    setState(() {
      _flowState = _flowState.copyWith(
        pairingState: ClassicPairingState.fase1_A_mostraQR,
        isProcessing: true,
        errorMessage: null,
      );
    });
    try {
      // Genera coppia di chiavi ECDH effimera per questa sessione
      final (ecdhPublicKey, ecdhPrivateKey) =
          EncryptionService.generateEcdhKeyPair();
      _localEcdhPrivateKey = ecdhPrivateKey;
      _localEcdhPublicKeyBase64 = base64Encode(ecdhPublicKey);

      // Genera nonce casuale per la sessione (16 byte)
      _sessionNonce = base64Encode(EncryptionService.secureRandomBytes(16));

      final pairingData = await ClassicPairingService.createPairingData(
        deviceName: _deviceNameController.text.trim().isNotEmpty
            ? '${ClassicUuids.deviceNamePrefix}${_deviceNameController.text.trim()}'
            : null,
        role: ref.read(classicSyncProvider).role,
        ecdhPublicKey: _localEcdhPublicKeyBase64,
        sessionNonce: _sessionNonce,
      );
      setState(() {
        _flowState = _flowState.copyWith(
          localPairingData: pairingData,
          myRole: ClassicPairingRole.dispositivoA,
        );
      });

      // Imposta il nome Bluetooth per renderlo trovabile via discovery
      final btName = '${ClassicUuids.deviceNamePrefix}${pairingData.deviceId.length > 20 ? pairingData.deviceId.substring(0, 20) : pairingData.deviceId}';
      await BluetoothClassicService.setLocalBluetoothName(btName);

      // Richiedi discoverability PRIMA di avviare il server
      await BluetoothClassicService.requestDiscoverability(timeoutSec: 120);

      // Avvia il server pairing e ATTENDI che sia pronto
      final serverStarted = await _connectionManager.startPairingServer();
      if (!serverStarted) {
        setState(() {
          _flowState = _flowState.copyWith(
            pairingState: ClassicPairingState.errore,
            errorMessage:
                'Impossibile avviare il server pairing. Verifica che il Bluetooth sia attivo.',
            isProcessing: false,
          );
        });
        return;
      }

      setState(() {
        _flowState = _flowState.copyWith(isProcessing: false);
      });
    } catch (e) {
      setState(() {
        _flowState = _flowState.copyWith(
          pairingState: ClassicPairingState.errore,
          errorMessage: 'Errore creazione QR: $e',
          isProcessing: false,
        );
      });
    }
  }

  void _handleQrScannedPhase1(String rawData) {
    if (_flowState.pairingState != ClassicPairingState.fase1_B_scansionaQR) {
      return;
    }
    if (_flowState.isProcessing) return;
    print('[FLUTTER_BT_SYNC] QR scansionato. Payload: $rawData');
    final scannedData = ClassicPairingService.decodeScannedQr(rawData);
    if (scannedData == null) {
      setState(() {
        _flowState = _flowState.copyWith(
          errorMessage: 'QR code non valido.',
        );
      });
      return;
    }
    setState(() {
      _flowState = _flowState.copyWith(
        scannedPairingData: scannedData,
        remoteDeviceId: scannedData.deviceId,
        pairingState: ClassicPairingState.verifyingHardware,
        isProcessing: true,
        errorMessage: null,
      );
    });
    _verifyHardware(scannedData);
  }

  Future<void> _verifyHardware(ClassicPairingData remoteData) async {
    _stopCamera();
    try {
      final expectedName = remoteData.deviceName.isNotEmpty
          ? '${ClassicUuids.deviceNamePrefix}${remoteData.deviceId.length > 20 ? remoteData.deviceId.substring(0, 20) : remoteData.deviceId}'
          : null;
      final (discoveredMac, success) =
          await _connectionManager.discoverAndConnectForPairing(
        timeoutSec: 20,
        expectedDeviceName: expectedName,
      );

      if (!success) {
        setState(() {
          _flowState = _flowState.copyWith(
            pairingState: ClassicPairingState.errore,
            errorMessage: discoveredMac == null
                ? 'Nessun catechista in modalita ricezione trovato nelle vicinanze.'
                : 'Verifica hardware fallita. I dispositivi non sono vicini.',
            isProcessing: false,
          );
        });
        return;
      }

      setState(() {
        _flowState = _flowState.copyWith(
          remoteMacAddress: discoveredMac,
        );
      });

      // Device B: genera la propria coppia di chiavi ECDH
      final (bEcdhPublicKey, bEcdhPrivateKey) =
          EncryptionService.generateEcdhKeyPair();
      _localEcdhPrivateKey = bEcdhPrivateKey;
      _localEcdhPublicKeyBase64 = base64Encode(bEcdhPublicKey);

      // Usa il nonce dal QR di Device A (se disponibile), altrimenti genera uno nuovo
      final sessionNonce = remoteData.sessionNonce ??
          base64Encode(EncryptionService.secureRandomBytes(16));
      _sessionNonce = sessionNonce;

      // Device B: salva il TrustedDevice di Device A con session key ECDH
      await ClassicPairingService.saveDeviceBTrustedDevice(
        remoteData,
        localPrivateKey: bEcdhPrivateKey,
        sessionNonce: sessionNonce,
        remoteMacAddress: discoveredMac,
      );

      // Crea i dati di pairing di Device B per il QR di risposta
      final localKeyData = await ClassicPairingService.createPairingData(
        deviceName: _deviceNameController.text.trim().isNotEmpty
            ? '${ClassicUuids.deviceNamePrefix}${_deviceNameController.text.trim()}'
            : null,
        role: ref.read(classicSyncProvider).role,
        ecdhPublicKey: _localEcdhPublicKeyBase64,
        sessionNonce: _sessionNonce,
      );

      setState(() {
        _flowState = _flowState.copyWith(
          pairingState: ClassicPairingState.fase2_B_mostraQR,
          localPairingData: localKeyData,
          isProcessing: false,
          errorMessage: null,
        );
      });
      await _connectionManager.resetPairingHandshake();
      await _showDeviceBQR(localKeyData);
    } catch (e) {
      setState(() {
        _flowState = _flowState.copyWith(
          pairingState: ClassicPairingState.errore,
          errorMessage: 'Errore verifica hardware: $e',
          isProcessing: false,
        );
      });
    }
  }

  Future<void> _showDeviceBQR(ClassicPairingData pairingData) async {
    setState(() {
      _flowState = _flowState.copyWith(isProcessing: true);
    });
    try {
      // Imposta il nome Bluetooth per renderlo trovabile via discovery
      final btName = '${ClassicUuids.deviceNamePrefix}${pairingData.deviceId.length > 20 ? pairingData.deviceId.substring(0, 20) : pairingData.deviceId}';
      await BluetoothClassicService.setLocalBluetoothName(btName);

      // Richiedi discoverability PRIMA di avviare il server
      await BluetoothClassicService.requestDiscoverability(timeoutSec: 120);

      // Avvia il server pairing e ATTENDI che sia pronto
      final serverStarted = await _connectionManager.startPairingServer();
      if (!serverStarted) {
        setState(() {
          _flowState = _flowState.copyWith(
            pairingState: ClassicPairingState.errore,
            errorMessage:
                'Impossibile avviare il server pairing per la risposta.',
            isProcessing: false,
          );
        });
        return;
      }

      setState(() {
        _flowState = _flowState.copyWith(isProcessing: false);
      });
    } catch (e) {
      setState(() {
        _flowState = _flowState.copyWith(
          pairingState: ClassicPairingState.errore,
          errorMessage: 'Errore creazione QR risposta: $e',
          isProcessing: false,
        );
      });
    }
  }

  void _handleQrScannedPhase2(String rawData) {
    if (_flowState.pairingState != ClassicPairingState.fase2_A_scansionaQR) {
      return;
    }
    if (_flowState.isProcessing) return;
    print('[FLUTTER_BT_SYNC] QR scansionato. Payload: $rawData');
    final scannedData = ClassicPairingService.decodeScannedQr(rawData);
    if (scannedData == null) {
      setState(() {
        _flowState = _flowState.copyWith(errorMessage: 'QR code non valido.');
      });
      return;
    }
    setState(() {
      _flowState = _flowState.copyWith(
        scannedPairingData: scannedData,
        remoteDeviceId: scannedData.deviceId,
        isProcessing: true,
        errorMessage: null,
      );
    });
    _completePairingAsDeviceA(scannedData);
  }

  Future<void> _completePairingAsDeviceA(ClassicPairingData remoteData) async {
    _stopCamera();
    try {
      final expectedName = remoteData.deviceName.isNotEmpty
          ? '${ClassicUuids.deviceNamePrefix}${remoteData.deviceId.length > 20 ? remoteData.deviceId.substring(0, 20) : remoteData.deviceId}'
          : null;
      final (discoveredMac, success) =
          await _connectionManager.discoverAndConnectForPairing(
        timeoutSec: 20,
        expectedDeviceName: expectedName,
      );

      if (!success) {
        setState(() {
          _flowState = _flowState.copyWith(
            pairingState: ClassicPairingState.errore,
            errorMessage: discoveredMac == null
                ? 'Nessun catechista in modalita ricezione trovato nelle vicinanze.'
                : 'Verifica finale fallita.',
            isProcessing: false,
          );
        });
        return;
      }

      final localRole = ref.read(classicSyncProvider).role;
      final rolesCoherent = ClassicPairingService.controllareCoerenzaRuoli(
        localRole,
        remoteData.syncRole,
      );
      if (!rolesCoherent) {
        setState(() {
          _flowState = _flowState.copyWith(
            pairingState: ClassicPairingState.errore,
            errorMessage: ClassicPairingService.roleCoherenceError,
            isProcessing: false,
          );
        });
        await _connectionManager.resetPairingHandshake();
        return;
      }

      // Device A: completa il pairing con ECDH
      // Usa la chiave privata ECDH locale + chiave pubblica ECDH di Device B + nonce
      if (_localEcdhPrivateKey == null || _sessionNonce == null) {
        setState(() {
          _flowState = _flowState.copyWith(
            pairingState: ClassicPairingState.errore,
            errorMessage: 'Chiavi ECDH locali mancanti. Riprova il pairing.',
            isProcessing: false,
          );
        });
        return;
      }

      await ClassicPairingService.completeBidirectionalPairing(
        remoteData,
        localPrivateKey: _localEcdhPrivateKey!,
        localPublicKey: _localEcdhPublicKeyBase64!,
        sessionNonce: _sessionNonce!,
        remoteMacAddress: discoveredMac,
      );
      await _connectionManager.resetPairingEngine();

      // Avvia il server di sincronizzazione persistente
      await _connectionManager.startPersistentSyncServer();

      ref.read(classicSyncProvider.notifier).loadPairingState();
      setState(() {
        _flowState = _flowState.copyWith(
          pairingState: ClassicPairingState.completato,
          isProcessing: false,
          errorMessage: null,
        );
      });
    } catch (e) {
      setState(() {
        _flowState = _flowState.copyWith(
          pairingState: ClassicPairingState.errore,
          errorMessage: 'Errore completamento pairing: $e',
          isProcessing: false,
        );
      });
    }
  }

  void _startCamera() {
    if (_isScanning) return;
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
    _isScanning = true;
    _scannerController!.start();
  }

  void _stopCamera() {
    if (!_isScanning) return;
    _isScanning = false;
    try {
      _scannerController?.stop();
      _scannerController?.dispose();
    } catch (_) {}
    _scannerController = null;
  }

  void _onQRDetected(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      if (_flowState.pairingState == ClassicPairingState.fase1_B_scansionaQR) {
        _handleQrScannedPhase1(raw);
        return;
      }
      if (_flowState.pairingState == ClassicPairingState.fase2_A_scansionaQR) {
        _handleQrScannedPhase2(raw);
        return;
      }
    }
  }

  Future<void> _resetPairing() async {
    _stopCamera();
    await _connectionManager.resetPairingEngine();
    _localEcdhPrivateKey = null;
    _localEcdhPublicKeyBase64 = null;
    _sessionNonce = null;
    if (mounted) {
      setState(() {
        _flowState = const ClassicPairingFlowState();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Associazione Dispositivi',
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_flowState.pairingState) {
      case ClassicPairingState.idle:
        return _buildIdleState();
      case ClassicPairingState.fase1_A_mostraQR:
        return _buildShowQRState(isPhase2: false);
      case ClassicPairingState.fase1_B_scansionaQR:
        return _buildScanQRState();
      case ClassicPairingState.verifyingHardware:
        return _buildVerifyingHardwareState();
      case ClassicPairingState.fase2_B_mostraQR:
        return _buildShowQRState(isPhase2: true);
      case ClassicPairingState.fase2_A_scansionaQR:
        return _buildScanQRState();
      case ClassicPairingState.completato:
        return _buildCompletedState();
      case ClassicPairingState.errore:
        return _buildErrorState();
    }
  }

  Widget _buildIdleState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.bluetooth_searching,
              size: 72, color: Color(0xFF174A7E)),
          const SizedBox(height: 16),
          const Text(
            'Associazione Dispositivi',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scegli il ruolo del tuo dispositivo per iniziare l\'associazione.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _deviceNameController,
            decoration: InputDecoration(
              labelText: 'Nome dispositivo (opzionale)',
              hintText: _fallbackDeviceName,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check),
                onPressed: _saveDeviceName,
              ),
            ),
            onChanged: (_) => _saveDeviceName(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _startPhase1AsDeviceA(),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Mostra il mio codice QR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _flowState = _flowState.copyWith(
                    pairingState: ClassicPairingState.fase1_B_scansionaQR,
                    myRole: ClassicPairingRole.dispositivoB,
                    errorMessage: null,
                  );
                });
                _startCamera();
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scansiona il codice QR del partner'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (_flowState.errorMessage != null) ...[
            const SizedBox(height: 16),
            _buildErrorBanner(_flowState.errorMessage!),
          ],
        ],
      ),
    );
  }

  Widget _buildShowQRState({required bool isPhase2}) {
    final pairingData = _flowState.localPairingData;
    if (pairingData == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            isPhase2
                ? 'Scansiona questo codice con l\'altro dispositivo'
                : 'Mostra questo codice all\'altro dispositivo',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'L\'altro dispositivo deve scansionare questo QR code.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: QrImageView(
              data: pairingData.toJson(),
              version: QrVersions.auto,
              size: 250,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            pairingData.cleanDisplayName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          if (_flowState.isProcessing) ...[
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            const SizedBox(height: 8),
            const Text('In attesa della connessione...'),
          ],
          // FIX: Se è il dispositivo A in Fase 1, mostra il bottone per procedere allo scan del QR di risposta di B
          if (!isPhase2 && _flowState.myRole == ClassicPairingRole.dispositivoA) ...[
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  _stopCamera(); // Sicurezza
                  setState(() {
                    _flowState = _flowState.copyWith(
                      pairingState: ClassicPairingState.fase2_A_scansionaQR,
                      errorMessage: null,
                    );
                  });
                  _startCamera();
                },
                icon: const Icon(Icons.camera_alt),
                label: const Text('Ora scansiona il QR di Device B'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF174A7E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScanQRState() {
    if (!_isScanning || _scannerController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: _scannerController!,
            onDetect: _onQRDetected,
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          child: const Text(
            'Inquadra il codice QR dell\'altro dispositivo.',
            style: TextStyle(fontSize: 16),
          ),
        ),
        TextButton(
          onPressed: _resetPairing,
          child: const Text('Annulla'),
        ),
      ],
    );
  }

  Widget _buildVerifyingHardwareState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF174A7E)),
          SizedBox(height: 24),
          Text(
            'Ricerca dispositivo CatechHub...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Scansione Bluetooth in corso. Verifica che i due dispositivi siano vicini.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 72, color: Colors.green),
          const SizedBox(height: 16),
          const Text(
            'Associazione completata!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'I dispositivi sono stati associati con successo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              if (context.mounted) {
                context.pop();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF174A7E),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            child: const Text('Vai alla Dashboard'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 72, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Errore di associazione',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _flowState.errorMessage ?? 'Errore sconosciuto.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _resetPairing,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
              ),
              child: const Text('Riprova'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.red),
        textAlign: TextAlign.center,
      ),
    );
  }
}
