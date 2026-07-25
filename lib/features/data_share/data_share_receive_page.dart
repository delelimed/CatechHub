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
  ConsumerState<DataShareReceivePage> createState() => _DataShareReceivePageState();
}

class _DataShareReceivePageState extends ConsumerState<DataShareReceivePage> {
  _ReceivePhase _phase = _ReceivePhase.showIndex;

  // Stato per la fase "showIndex"
  List<QRChunk> _indexChunks = [];
  int _currentIndexChunk = 0;
  Timer? _indexTimer;
  bool _isIndexPlaying = false;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareIndex());
  }

  @override
  void dispose() {
    _indexTimer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _prepareIndex() async {
    final options = ref.read(dataShareOptionsProvider) ?? const DataShareOptions();
    try {
      final indexMap = QRDataService.buildDatabaseIndex(options);
      if (!mounted) return;
      final chunkMaps = QRDataService.serializeIndexToChunks(indexMap);
      if (!mounted) return;
      final chunks = chunkMaps.map((m) => QRChunk.fromMap(Map<String, dynamic>.from(m))).toList();
      setState(() {
        _indexChunks = chunks;
        _startIndexAnimation();
      });
    } catch (e) {
      setState(() => _errorMessage = 'Errore creazione indice: $e');
    }
  }

  void _startIndexAnimation() {
    if (_indexChunks.isEmpty) return;
    _indexTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) { timer.cancel(); return; }
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
        if (_receivedChunkIndices.length == chunk.totalChunks) _allChunksReceived();
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
    final inputPin = _pinController.text.trim();
    if (inputPin.length != 8) {
      setState(() => _errorMessage = 'Il PIN deve essere di 8 cifre');
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
      final receivedData = QRDataService.extractPackageData(_assembledPackageData!, pin);

      setState(() => _phaseMessage = 'Verifica integrità…');
      if (!DataExportService.verifyDataIntegrity(receivedData, requireFullPackage: false)) {
        setState(() {
          _errorMessage = 'Integrità dei dati non valida';
          _phase = _ReceivePhase.scanData;
          _isScanning = true;
          _phaseMessage = null;
        });
        return;
      }

      setState(() => _phaseMessage = 'Importazione dati…');
      await DataExportService.importData(receivedData, onPhase: (phase) {
        if (mounted) setState(() => _phaseMessage = phase);
      });

      ref.invalidate(classesStreamProvider);
      ref.invalidate(documentsStreamProvider);
      ref.invalidate(planningRepoProvider);
      ref.invalidate(studentsRepoProvider);

      setState(() { _phaseMessage = null; });
      if (mounted) _showSuccessDialog();
    } catch (e) {
      setState(() {
        _errorMessage = 'PIN non corretto o dati non validi';
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
        content: const Text('I dati differenziali sono stati importati con successo.'),
        actions: [
          TextButton(
            onPressed: () { Navigator.of(ctx).pop(); context.go('/'); },
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
      title: _phase == _ReceivePhase.showIndex ? 'Mostra Indice Database' : 'Ricezione Dati',
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
        _InfoBanner(
          icon: Icons.qr_code_2_rounded,
          message: 'Mostra questo QR code al mittente\nper consentirgli di confrontare i database',
          color: const Color(0xFF174A7E),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 10))],
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
                    dataModuleStyle: const QrDataModuleStyle(color: Colors.black),
                  ),
                )
              else
                const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
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
                icon: _isIndexPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
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
        const SizedBox(height: 24),
        _InstructionsCard(
          steps: [
            'Mostra questo QR al mittente per l\'analisi del database',
            'Dopo averlo scansionato, il mittente invierà solo i dati aggiornati',
            'Premi "Passa alla Ricezione" e inquadra i QR del mittente',
            'Inserisci il PIN per completare l\'importazione',
          ],
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
                    color: isDark ? colorScheme.surfaceContainer : Colors.grey.shade200,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.qr_code_scanner_rounded, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('Scansione in pausa', style: TextStyle(fontSize: 16, color: Colors.grey)),
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
                onPressed: () => setState(() { _isScanning = !_isScanning; _errorMessage = null; }),
                icon: Icon(_isScanning ? Icons.pause_rounded : Icons.play_arrow_rounded),
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
            color: isDark ? Colors.green.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: const Column(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
              SizedBox(height: 16),
              Text(
                'Tutti i chunk ricevuti!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF174A7E)),
              ),
              SizedBox(height: 8),
              Text(
                'Inserisci il PIN di 8 cifre fornito dal mittente',
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
          maxLength: 8,
          decoration: const InputDecoration(
            labelText: 'PIN di sicurezza',
            hintText: 'Inserisci 8 cifre',
            prefixIcon: Icon(Icons.security_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
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
          CircularProgressIndicator(color: isDark ? colorScheme.primary : const Color(0xFF174A7E)),
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
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF174A7E)),
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

  const _InfoBanner({required this.icon, required this.message, required this.color});

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
          Expanded(child: Text(message, style: TextStyle(fontSize: 13, color: color))),
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

  const _MiniButton({required this.icon, required this.label, required this.color, required this.onTap});

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
    final percentage = totalChunks > 0 ? (receivedCount / totalChunks * 100).toStringAsFixed(1) : '0';
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF174A7E), Color(0xFF2E5A8F)]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          Text('$receivedCount${totalChunks > 0 ? '/$totalChunks' : ''}',
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                    child: Text('$percentage%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
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
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Text('Mancanti: #${missingChunkIndices.join(', #')}',
                    style: const TextStyle(fontSize: 12, color: Colors.orange)),
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
          Expanded(child: Text(message, style: const TextStyle(color: Colors.red, fontSize: 13))),
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
        border: Border.all(color: isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_rounded, color: isDark ? colorScheme.primary : Colors.blue.shade700),
              const SizedBox(width: 8),
              Text('Istruzioni',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? colorScheme.primary : Colors.blue.shade700)),
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
                      color: isDark ? colorScheme.primary : Colors.blue.shade700,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text('${i + 1}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(steps[i], style: TextStyle(fontSize: 13, color: isDark ? colorScheme.onSurface : null))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
