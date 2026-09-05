import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../core/services/qr_data_service.dart';
import '../../core/services/data_export_service.dart';
import '../../core/providers/data_share_provider.dart';
import '../../core/providers/current_class_provider.dart';
import '../classes/classes_provider.dart';
import '../documents/documents_provider.dart';
import '../planning/planning_provider.dart';
import '../students/students_provider.dart';

enum _ReceivePhase { showIndex, scanData, pinVerification, importing }

/// Pagina di ricezione con flusso differenziale a due fasi:
/// 1. Mostra l'indice del database locale come QR animati
/// 2. Passa alla scansione dei dati differenziali inviati dal mittente
class DataShareReceivePage extends ConsumerStatefulWidget {
  const DataShareReceivePage({super.key});

  @override
  ConsumerState<DataShareReceivePage> createState() =>
      _DataShareReceivePageState();
}

class _DataShareReceivePageState extends ConsumerState<DataShareReceivePage> {
  _ReceivePhase _phase = _ReceivePhase.showIndex;

  // Stato per la fase "showIndex"
  List<QRChunk> _indexChunks = [];
  int _currentIndexChunk = 0;
  Timer? _indexTimer;
  bool _isIndexPlaying = false;

  // A9: il PIN di sessione (comunicato dal mittente all'inizio del flusso)
  // cifra l'indice prima della trasmissione. L'indice non viaggia più in
  // chiaro: un terzo che fotografasse i QR non leggerebbe nemmeno i metadati
  // (id + timestamp) dei record.
  String? _sessionPin;
  bool _isPreparingIndex = false;
  final TextEditingController _sessionPinController = TextEditingController();

  // Stato per la fase "scanData"
  final List<QRChunk> _receivedChunks = [];
  final Set<int> _receivedChunkIndices = {};
  int _totalChunks = 0;
  String? _assembledPackageData;
  bool _isScanning = true;

  // Stato per pin/import
  final TextEditingController _pinController = TextEditingController();
  String? _errorMessage;
  String? _phaseMessage;

  // A1: rate-limit sulla verifica del PIN. L'app non limita i tentativi di
  // decifratura (la KDF a 350k iterazioni è già costosa), ma un lockout dopo
  // troppi errori consecutivi scoraggia il brute-force interattivo del PIN.
  static const int _maxPinAttempts = 5;
  static const Duration _pinLockoutDuration = Duration(minutes: 1);
  int _pinAttempts = 0;
  DateTime? _pinLockoutUntil;

  @override
  void initState() {
    super.initState();
    // A9: l'indice viene preparato (e cifrato) solo dopo che l'utente inserisce
    // il PIN di sessione comunicato dal mittente, quindi non serve prepararlo
    // qui all'apertura della pagina.
  }

  @override
  void dispose() {
    _indexTimer?.cancel();
    _pinController.dispose();
    _sessionPinController.dispose();
    super.dispose();
  }

  Future<void> _prepareIndex() async {
    final pin = _sessionPinController.text.trim();
    if (pin.length != QRDataService.pinLength) {
      setState(
        () => _errorMessage =
            'Il PIN deve essere di ${QRDataService.pinLength} cifre',
      );
      return;
    }
    final options =
        ref.read(dataShareOptionsProvider) ?? const DataShareOptions();
    setState(() {
      _sessionPin = pin;
      _isPreparingIndex = true;
      _errorMessage = null;
    });
    try {
      final indexMap = QRDataService.buildDatabaseIndex(options);
      if (!mounted) return;
      final chunkMaps = await QRDataService.encryptIndexToChunks(indexMap, pin);
      if (!mounted) return;
      final chunks = chunkMaps
          .map((m) => QRChunk.fromMap(Map<String, dynamic>.from(m)))
          .toList();
      setState(() {
        _indexChunks = chunks;
        _isPreparingIndex = false;
        _startIndexAnimation();
      });
    } catch (e) {
      setState(() {
        _isPreparingIndex = false;
        _errorMessage = 'Errore creazione indice: $e';
      });
    }
  }

  void _startIndexAnimation() {
    if (_indexChunks.isEmpty) return;
    _indexTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _currentIndexChunk = (_currentIndexChunk + 1) % _indexChunks.length;
        _isIndexPlaying = true;
      });
    });
  }

  void _pauseIndex() {
    _indexTimer?.cancel();
    setState(() => _isIndexPlaying = false);
  }

  void _resumeIndex() {
    if (!_isIndexPlaying) _startIndexAnimation();
  }

  void _switchToScanPhase() {
    _indexTimer?.cancel();
    setState(() {
      _phase = _ReceivePhase.scanData;
      _errorMessage = null;
    });
  }

  // A9: torna alla richiesta del PIN di sessione (es. PIN errato lato mittente).
  void _resetIndex() {
    _indexTimer?.cancel();
    setState(() {
      _sessionPin = null;
      _sessionPinController.clear();
      _indexChunks.clear();
      _currentIndexChunk = 0;
      _isIndexPlaying = false;
      _isPreparingIndex = false;
      _errorMessage = null;
    });
  }

  // ─── SCAN FASE ────────────────────────────────────────────────────────

  void _onQRCodeDetected(BarcodeCapture capture) {
    if (_phase != _ReceivePhase.scanData || !_isScanning) return;
    final barcode = capture.barcodes.first;
    final code = barcode.rawValue;
    if (code != null && code.isNotEmpty) _processQRCode(code);
  }

  void _processQRCode(String qrData) {
    try {
      final chunk = QRChunk.fromJson(qrData);
      if (!QRDataService.verifyChunkChecksum(chunk)) {
        setState(() => _errorMessage = 'Checksum non valido per il chunk');
        return;
      }
      if (_totalChunks == 0) setState(() => _totalChunks = chunk.totalChunks);

      if (!_receivedChunkIndices.contains(chunk.chunkIndex)) {
        setState(() {
          _receivedChunks.add(chunk);
          _receivedChunkIndices.add(chunk.chunkIndex);
          _errorMessage = null;
        });
        if (_receivedChunkIndices.length == chunk.totalChunks) {
          _allChunksReceived();
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Errore QR: $e');
    }
  }

  void _allChunksReceived() {
    setState(() => _isScanning = false);
    try {
      final assembledData = QRDataService.assembleChunks(_receivedChunks);
      QRDataService.extractPackage(assembledData);
      setState(() {
        _assembledPackageData = assembledData;
        // A9: il PIN di sessione è già noto (usato per l'indice): lo
        // precompiliamo, l'utente deve solo confermare.
        _pinController.text = _sessionPin ?? '';
        _phase = _ReceivePhase.pinVerification;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore assemblaggio: $e';
        _isScanning = true;
      });
    }
  }

  void _verifyAndImport() {
    if (_assembledPackageData == null) {
      setState(() => _errorMessage = 'Pacchetto dati non disponibile');
      return;
    }
    // A1: lockout dopo troppi tentativi non validi.
    final now = DateTime.now();
    if (_pinLockoutUntil != null && now.isBefore(_pinLockoutUntil!)) {
      final remaining =
          _pinLockoutUntil!.difference(now).inSeconds + 1;
      setState(
        () => _errorMessage =
            'Troppi tentativi non validi. Riprova tra $remaining secondi.',
      );
      return;
    }
    final inputPin = _pinController.text.trim();
    if (inputPin.length != QRDataService.pinLength) {
      setState(
        () => _errorMessage =
            'Il PIN deve essere di ${QRDataService.pinLength} cifre',
      );
      return;
    }
    setState(() {
      _phase = _ReceivePhase.importing;
      _errorMessage = null;
    });
    Future.delayed(Duration.zero, () => _importData(inputPin));
  }

  Future<void> _importData(String pin) async {
    try {
      setState(() => _phaseMessage = 'Decifratura dati…');
      final receivedData = await QRDataService.extractPackageData(
        _assembledPackageData!,
        pin,
      );

      setState(() => _phaseMessage = 'Verifica integrità…');
      if (!DataExportService.verifyDataIntegrity(
        receivedData,
        requireFullPackage: false,
      )) {
        setState(() {
          _errorMessage = 'Integrità dei dati non valida';
          _phase = _ReceivePhase.scanData;
          _isScanning = true;
          _phaseMessage = null;
        });
        return;
      }

      setState(() => _phaseMessage = 'Importazione dati…');

      // I dati ricevuti vengono inseriti nella classe attualmente aperta.
      final currentClass = ref.read(currentClassDetailsProvider);
      if (currentClass != null && currentClass.id.isNotEmpty) {
        await DataExportService.importDataIntoClass(
          receivedData,
          currentClass,
          onPhase: (phase) {
            if (mounted) setState(() => _phaseMessage = phase);
          },
        );
      } else {
        await DataExportService.importData(
          receivedData,
          onPhase: (phase) {
            if (mounted) setState(() => _phaseMessage = phase);
          },
        );
      }

      ref.invalidate(classesStreamProvider);
      ref.invalidate(documentsStreamProvider);
      ref.invalidate(planningRepoProvider);
      ref.invalidate(studentsRepoProvider);

      setState(() {
        _pinAttempts = 0;
        _pinLockoutUntil = null;
        _phaseMessage = null;
      });
      if (mounted) _showSuccessDialog();
    } catch (e) {
      // A1: conta i tentativi non validi e applica il lockout dopo il massimo.
      setState(() {
        _pinAttempts++;
        if (_pinAttempts >= _maxPinAttempts) {
          _pinLockoutUntil = DateTime.now().add(_pinLockoutDuration);
          _pinAttempts = 0;
          _errorMessage =
              'Troppi tentativi non validi. Riprova tra '
              '${_pinLockoutDuration.inMinutes} minuto.';
        } else {
          _errorMessage = 'PIN non corretto o dati non validi';
        }
        _phase = _ReceivePhase.pinVerification;
        _phaseMessage = null;
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Importazione Completata'),
          ],
        ),
        content: const Text(
          'I dati differenziali sono stati importati con successo.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go('/');
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _resetScanning() {
    setState(() {
      _receivedChunks.clear();
      _receivedChunkIndices.clear();
      _assembledPackageData = null;
      _pinController.clear();
      _isScanning = true;
      _totalChunks = 0;
      _errorMessage = null;
      _phase = _ReceivePhase.scanData;
    });
  }

  List<int> _getMissingChunkIndices() {
    if (_totalChunks == 0) return [];
    final missing = <int>[];
    for (int i = 0; i < _totalChunks; i++) {
      if (!_receivedChunkIndices.contains(i)) missing.add(i);
    }
    return missing;
  }

  // ─── BUILD ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _phase == _ReceivePhase.showIndex
          ? 'Mostra Indice Database'
          : 'Ricezione Dati',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_phase == _ReceivePhase.showIndex) _buildIndexPhase(),
            if (_phase == _ReceivePhase.scanData) _buildScanPhase(),
            if (_phase == _ReceivePhase.pinVerification) _buildPinPhase(),
            if (_phase == _ReceivePhase.importing) _buildImportPhase(),
          ],
        ),
      ),
    );
  }

  // ─── FASE 1: MOSTRA INDICE ────────────────────────────────────────────

  Widget _buildIndexPhase() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF174A7E).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF174A7E).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.class_, color: const Color(0xFF174A7E), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'I dati ricevuti verranno inseriti nella classe attualmente aperta.',
                      style: TextStyle(
                        fontSize: 13,
                        color: const Color(0xFF174A7E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_sessionPin == null)
          _buildSessionPinForm()
        else ...[
          _InfoBanner(
            icon: Icons.qr_code_2_rounded,
            message:
                'Mostra questo QR code al mittente\nper consentirgli di confrontare i database',
            color: const Color(0xFF174A7E),
          ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(color: const Color(0xFF174A7E), width: 2),
          ),
          child: Column(
            children: [
              if (_indexChunks.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black, width: 3),
                  ),
                  child: QrImageView(
                    data: _indexChunks[_currentIndexChunk].toJson(),
                    version: QrVersions.auto,
                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                    size: 380,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(color: Colors.black),
                    dataModuleStyle: const QrDataModuleStyle(
                      color: Colors.black,
                    ),
                  ),
                )
              else
                const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),
              const SizedBox(height: 12),
              Text(
                'Chunk ${_currentIndexChunk + 1} di ${_indexChunks.length}',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_indexChunks.isNotEmpty) ...[
              _MiniButton(
                icon: _isIndexPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                label: _isIndexPlaying ? 'Pausa' : 'Riprendi',
                color: _isIndexPlaying ? Colors.orange : Colors.green,
                onTap: _isIndexPlaying ? _pauseIndex : _resumeIndex,
              ),
              const SizedBox(width: 16),
            ],
            _MiniButton(
              icon: Icons.arrow_forward_rounded,
              label: 'Passa alla Ricezione',
              color: const Color(0xFF174A7E),
              onTap: _switchToScanPhase,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _resetIndex,
          icon: const Icon(Icons.replay_rounded, size: 18),
          label: const Text('PIN errato? Reinserisci'),
        ),
        const SizedBox(height: 16),
        _InstructionsCard(
          steps: [
            'Mostra questo QR al mittente per l\'analisi del database',
            'Dopo averlo scansionato, il mittente invierà solo i dati aggiornati',
            'Premi "Passa alla Ricezione" e inquadra i QR del mittente',
            'Il PIN inserito all\'inizio completa l\'importazione',
          ],
        ),
        ],
      ],
    );
  }

  // A9: form di inserimento del PIN di sessione mostrato dal mittente.
  // L'indice viene cifrato SOLO dopo questo inserimento.
  Widget _buildSessionPinForm() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoBanner(
          icon: Icons.pin_rounded,
          message:
              'Il mittente ti mostrerà un PIN di sicurezza.\nInseriscilo qui: l\'indice del database verrà cifrato prima della trasmissione.',
          color: const Color(0xFF174A7E),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? colorScheme.surfaceContainer : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: const Color(0xFF174A7E), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'PIN di sicurezza',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sessionPinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: QRDataService.pinLength,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  labelText: 'PIN',
                  hintText: '••••••••••••',
                  prefixIcon: const Icon(Icons.lock_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  counterText: '',
                ),
              ),
              if (_isPreparingIndex) ...[
                const SizedBox(height: 12),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Preparazione indice cifrato…',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _ErrorMessage(message: _errorMessage!),
        ],
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _isPreparingIndex ? null : _prepareIndex,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: Text(
            _isPreparingIndex ? 'Preparazione…' : 'Cifra e mostra indice',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF174A7E),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () {
            ref.read(dataShareOptionsProvider.notifier).state = null;
            context.pop();
          },
          icon: const Icon(Icons.cancel_rounded),
          label: const Text('Annulla'),
        ),
      ],
    );
  }

  // ─── FASE 2: SCANSIONE DATI ───────────────────────────────────────────

  Widget _buildScanPhase() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        _InfoBanner(
          icon: Icons.camera_alt_rounded,
          message: 'Inquadra i QR code differenziali del mittente',
          color: Colors.green,
        ),
        const SizedBox(height: 16),
        Container(
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isScanning
                  ? (isDark ? colorScheme.primary : const Color(0xFF174A7E))
                  : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
              width: 2,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: _isScanning
                ? MobileScanner(onDetect: _onQRCodeDetected)
                : Container(
                    color: isDark
                        ? colorScheme.surfaceContainer
                        : Colors.grey.shade200,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Scansione in pausa',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        _ProgressInfo(
          receivedCount: _receivedChunks.length,
          totalChunks: _totalChunks,
          missingChunkIndices: _getMissingChunkIndices(),
          label: 'Chunk dati ricevuti',
        ),
        if (_errorMessage != null) _ErrorMessage(message: _errorMessage!),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => setState(() {
                  _isScanning = !_isScanning;
                  _errorMessage = null;
                }),
                icon: Icon(
                  _isScanning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(_isScanning ? 'Pausa' : 'Riprendi'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isScanning ? Colors.orange : Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _resetScanning,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Ricomincia'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () {
            _indexTimer?.cancel();
            ref.read(dataShareOptionsProvider.notifier).state = null;
            context.pop();
          },
          icon: const Icon(Icons.cancel_rounded),
          label: const Text('Annulla'),
        ),
      ],
    );
  }

  // ─── FASE 3: VERIFICA PIN ─────────────────────────────────────────────

  Widget _buildPinPhase() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: const Column(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
              SizedBox(height: 16),
              Text(
                'Tutti i chunk ricevuti!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF174A7E),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Inserisci il PIN di ${QRDataService.pinLength} cifre fornito dal mittente',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          maxLength: QRDataService.pinLength,
          decoration: const InputDecoration(
            labelText: 'PIN di sicurezza',
            hintText: 'Inserisci ${QRDataService.pinLength} cifre',
            prefixIcon: Icon(Icons.security_rounded),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            counterText: '',
          ),
          style: const TextStyle(fontSize: 20, letterSpacing: 8),
          textAlign: TextAlign.center,
        ),
        if (_errorMessage != null) _ErrorMessage(message: _errorMessage!),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _verifyAndImport,
          icon: const Icon(Icons.verified_rounded),
          label: const Text('Verifica e Importa'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF174A7E),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            minimumSize: const Size(double.infinity, 56),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _resetScanning,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Ricomincia scansione'),
        ),
      ],
    );
  }

  // ─── FASE 4: IMPORT ───────────────────────────────────────────────────

  Widget _buildImportPhase() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          CircularProgressIndicator(
            color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
          ),
          const SizedBox(height: 24),
          const Text(
            'Importazione in corso...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (_phaseMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _phaseMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF174A7E),
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'I dati vengono salvati. Non chiudere l\'app.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// ─── WIDGET RIUTILIZZABILI ──────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const _InfoBanner({
    required this.icon,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 13, color: color)),
          ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MiniButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}

class _ProgressInfo extends StatelessWidget {
  final int receivedCount;
  final int totalChunks;
  final List<int> missingChunkIndices;
  final String label;

  const _ProgressInfo({
    required this.receivedCount,
    required this.totalChunks,
    required this.missingChunkIndices,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = totalChunks > 0
        ? (receivedCount / totalChunks * 100).toStringAsFixed(1)
        : '0';
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF174A7E), Color(0xFF2E5A8F)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.qr_code_2_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '$receivedCount${totalChunks > 0 ? '/$totalChunks' : ''}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$percentage%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              if (totalChunks > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: receivedCount / totalChunks,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                    minHeight: 6,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (missingChunkIndices.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Mancanti: #${missingChunkIndices.join(', #')}',
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  final String message;
  const _ErrorMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionsCard extends StatelessWidget {
  final List<String> steps;
  const _InstructionsCard({required this.steps});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainer : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? colorScheme.outline.withValues(alpha: 0.2)
              : Colors.blue.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_rounded,
                color: isDark ? colorScheme.primary : Colors.blue.shade700,
              ),
              const SizedBox(width: 8),
              Text(
                'Istruzioni',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? colorScheme.primary : Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.primary
                          : Colors.blue.shade700,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? colorScheme.onSurface : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
