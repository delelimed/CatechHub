import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../core/services/qr_data_service.dart';
import '../../core/providers/data_share_provider.dart';

enum _SendPhase { scanIndex, preparingDiff, sendingDiff, completed }

List<Map<String, dynamic>> _buildDiffQrChunks(Map<String, dynamic> args) {
  final data = Map<String, dynamic>.from(args['data'] as Map);
  final pin = args['pin'] as String;

  final package = QRDataService.createPackage(data, pin);
  final compressedPackage = QRDataService.compressData(package.toMap());
  final chunkStrings = QRDataService.segmentData(compressedPackage);

  return chunkStrings
      .asMap()
      .entries
      .map((entry) => QRDataService.createQRChunk(entry.value, entry.key, chunkStrings.length).toMap())
      .toList();
}

/// Pagina di invio differenziale via QR code animati.
///
/// FLUSSO:
/// 1. Scansiona l'indice del database del ricevente
/// 2. Calcola la differenza (solo dati nuovi/modificati)
/// 3. Mostra i QR code cifrati dei soli dati differenziali
class DataShareSendPage extends ConsumerStatefulWidget {
  const DataShareSendPage({super.key});

  @override
  ConsumerState<DataShareSendPage> createState() => _DataShareSendPageState();
}

class _DataShareSendPageState extends ConsumerState<DataShareSendPage> {
  _SendPhase _phase = _SendPhase.scanIndex;

  // Stato per scansione indice
  final List<QRChunk> _receivedIndexChunks = [];
  final Set<int> _receivedIndexIndices = {};
  int _totalIndexChunks = 0;
  bool _isIndexScanning = true;
  Map<String, dynamic>? _remoteIndex;

  // Stato per preparazione diff
  bool _isPreparingDiff = false;
  String? _preparationMessage;

  // Stato per invio diff
  List<QRChunk> _diffChunks = [];
  int _currentDiffChunk = 0;
  Timer? _diffTimer;
  bool _isDiffPlaying = false;
  String? _pin;
  int? _filterStartChunk;
  // Comune
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final options = ref.read(dataShareOptionsProvider);
      if (options == null && mounted) context.pop();
    });
  }

  @override
  void dispose() {
    _diffTimer?.cancel();
    ref.read(dataShareDataProvider.notifier).state = null;
    ref.read(dataSharePinProvider.notifier).state = null;
    super.dispose();
  }

  // ─── SCANSIONE INDICE ─────────────────────────────────────────────────

  void _onIndexQRDetected(BarcodeCapture capture) {
    if (_phase != _SendPhase.scanIndex || !_isIndexScanning) return;
    final barcode = capture.barcodes.first;
    final code = barcode.rawValue;
    if (code != null && code.isNotEmpty) _processIndexChunk(code);
  }

  void _processIndexChunk(String qrData) {
    try {
      final chunk = QRChunk.fromJson(qrData);
      if (!QRDataService.verifyChunkChecksum(chunk)) {
        setState(() => _errorMessage = 'Checksum non valido');
        return;
      }
      if (_totalIndexChunks == 0) setState(() => _totalIndexChunks = chunk.totalChunks);

      if (!_receivedIndexIndices.contains(chunk.chunkIndex)) {
        setState(() {
          _receivedIndexChunks.add(chunk);
          _receivedIndexIndices.add(chunk.chunkIndex);
          _errorMessage = null;
        });
        if (_receivedIndexIndices.length == chunk.totalChunks) _allIndexChunksReceived();
      }
    } catch (e) {
      setState(() => _errorMessage = 'Errore QR: $e');
    }
  }

  void _allIndexChunksReceived() {
    setState(() => _isIndexScanning = false);
    try {
      final assembled = QRDataService.assembleChunks(_receivedIndexChunks);
      final remoteIndex = QRDataService.decompressData(assembled);
      setState(() {
        _remoteIndex = remoteIndex;
      });
      _computeAndShowDiff();
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore assemblaggio indice: $e';
        _isIndexScanning = true;
      });
    }
  }

  // ─── CALCOLO DIFF ─────────────────────────────────────────────────────

  Future<void> _computeAndShowDiff() async {
    if (_remoteIndex == null) return;

    final options = ref.read(dataShareOptionsProvider) ?? const DataShareOptions();
    final pin = QRDataService.generatePin();
    _pin = pin;

    setState(() {
      _phase = _SendPhase.preparingDiff;
      _isPreparingDiff = true;
      _preparationMessage = 'Calcolo dati differenziali…';
    });

    try {
      final diffData = await QRDataService.computeDiffExport(_remoteIndex!, options);

      if (diffData.isEmpty) {
        if (mounted) setState(() {
          _isPreparingDiff = false;
          _preparationMessage = 'Nessun dato da aggiornare — i database sono già sincronizzati.';
        });
        return;
      }

      setState(() => _preparationMessage = 'Preparazione pacchetto cifrato…');

      ref.read(dataShareDataProvider.notifier).state = diffData;
      ref.read(dataSharePinProvider.notifier).state = pin;

      final preparedChunkMaps = await compute(_buildDiffQrChunks, {
        'data': diffData,
        'pin': pin,
      });

      if (!mounted) return;

      final preparedChunks =
          preparedChunkMaps.map((map) => QRChunk.fromMap(Map<String, dynamic>.from(map))).toList();

      setState(() {
        _diffChunks = preparedChunks;
        _currentDiffChunk = 0;
        _filterStartChunk = null;
        _isPreparingDiff = false;
        _phase = _SendPhase.sendingDiff;
        _startDiffAnimation();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPreparingDiff = false;
        _errorMessage = 'Errore preparazione diff: $e';
      });
    }
  }

  // ─── ANIMAZIONE QR DIFF ───────────────────────────────────────────────

  void _startDiffAnimation() {
    if (_diffChunks.isEmpty) return;
    _diffTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        _currentDiffChunk = (_currentDiffChunk + 1) % _diffChunks.length;
        _isDiffPlaying = true;
      });
    });
    setState(() => _isDiffPlaying = true);
  }

  void _pauseDiff() {
    _diffTimer?.cancel();
    setState(() => _isDiffPlaying = false);
  }

  void _resumeDiff() {
    if (!_isDiffPlaying) _startDiffAnimation();
  }

  void _completeSharing() {
    _pauseDiff();
    ref.read(dataShareDataProvider.notifier).state = null;
    ref.read(dataSharePinProvider.notifier).state = null;
    setState(() {
      _phase = _SendPhase.completed;
    });
  }

  void _setChunkFilter(int start, int end) {
    setState(() {
      _filterStartChunk = start;
      _currentDiffChunk = start.clamp(0, _diffChunks.length - 1);
    });
  }

  // ─── BUILD ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = switch (_phase) {
      _SendPhase.scanIndex => 'Scansiona Indice Ricevente',
      _SendPhase.preparingDiff => 'Preparazione Dati Differenziali',
      _SendPhase.sendingDiff => 'Invio Dati Differenziali',
      _SendPhase.completed => 'Invio Completato',
    };

    return AppScaffold(
      title: title,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_phase == _SendPhase.scanIndex) _buildScanIndexPhase(),
            if (_phase == _SendPhase.preparingDiff) _buildPreparingPhase(),
            if (_phase == _SendPhase.sendingDiff) _buildSendingPhase(),
            if (_phase == _SendPhase.completed) _buildCompletedPhase(),
          ],
        ),
      ),
    );
  }

  // ─── FASE 1: SCANSIONE INDICE ─────────────────────────────────────────

  Widget _buildScanIndexPhase() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        _InfoBanner(
          icon: Icons.camera_alt_rounded,
          message: 'Inquadra il QR code dell\'indice mostrato dal ricevente',
          color: const Color(0xFF174A7E),
        ),
        const SizedBox(height: 16),
        Container(
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isIndexScanning
                  ? (isDark ? colorScheme.primary : const Color(0xFF174A7E))
                  : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
              width: 2,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: _isIndexScanning
                ? MobileScanner(onDetect: _onIndexQRDetected)
                : Container(
                    color: isDark ? colorScheme.surfaceContainer : Colors.grey.shade200,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.qr_code_scanner_rounded, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('Scansione completata', style: TextStyle(fontSize: 16, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        _ProgressInfo(
          receivedCount: _receivedIndexChunks.length,
          totalChunks: _totalIndexChunks,
          missingChunkIndices: _getMissingIndexIndices(),
          label: 'Chunk indice ricevuti',
        ),
        if (_errorMessage != null) _ErrorMessage(message: _errorMessage!),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => setState(() { _isIndexScanning = !_isIndexScanning; _errorMessage = null; }),
                icon: Icon(_isIndexScanning ? Icons.pause_rounded : Icons.play_arrow_rounded),
                label: Text(_isIndexScanning ? 'Pausa' : 'Riprendi'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isIndexScanning ? Colors.orange : Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _receivedIndexChunks.clear();
                    _receivedIndexIndices.clear();
                    _totalIndexChunks = 0;
                    _errorMessage = null;
                    _isIndexScanning = true;
                  });
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Ricomincia'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () { ref.read(dataShareOptionsProvider.notifier).state = null; context.pop(); },
          icon: const Icon(Icons.cancel_rounded),
          label: const Text('Annulla'),
        ),
      ],
    );
  }

  List<int> _getMissingIndexIndices() {
    if (_totalIndexChunks == 0) return [];
    final missing = <int>[];
    for (int i = 0; i < _totalIndexChunks; i++) {
      if (!_receivedIndexIndices.contains(i)) missing.add(i);
    }
    return missing;
  }

  // ─── FASE 2: PREPARAZIONE ─────────────────────────────────────────────

  Widget _buildPreparingPhase() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isPreparingDiff) ...[
              const CircularProgressIndicator(color: Color(0xFF174A7E)),
              const SizedBox(height: 24),
              Text(
                _preparationMessage ?? 'Preparazione…',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
            ] else ...[
              const Icon(Icons.check_circle, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              Text(
                _preparationMessage ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () { ref.read(dataShareOptionsProvider.notifier).state = null; context.pop(); },
                icon: const Icon(Icons.home_rounded),
                label: const Text('Torna alla home'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── FASE 3: INVIO DIFF ───────────────────────────────────────────────

  Widget _buildSendingPhase() {
    if (_diffChunks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentChunk = _diffChunks[_currentDiffChunk];

    return Column(
      children: [
        _ProgressCard(
          current: _currentDiffChunk + 1,
          total: _diffChunks.length,
          hasFilter: _filterStartChunk != null,
          label: 'Dati differenziali',
        ),
        const SizedBox(height: 16),
        _InfoBanner(
          icon: Icons.compare_arrows_rounded,
          message: 'Invio solo i dati nuovi/modificati (${_diffChunks.length} chunk)',
          color: Colors.green,
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
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black, width: 3),
                ),
                child: QrImageView(
                  data: currentChunk.toJson(),
                  version: QrVersions.auto,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  size: 380,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(color: Colors.black),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Inquadra il QR code dal dispositivo ricevente',
                style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MiniButton(
              icon: Icons.pause_rounded,
              label: 'Pausa',
              color: Colors.orange,
              onTap: _isDiffPlaying ? _pauseDiff : null,
            ),
            const SizedBox(width: 12),
            _MiniButton(
              icon: Icons.play_arrow_rounded,
              label: 'Riprendi',
              color: Colors.green,
              onTap: !_isDiffPlaying ? _resumeDiff : null,
            ),
            const SizedBox(width: 12),
            _MiniButton(
              icon: Icons.check_rounded,
              label: 'Completa',
              color: const Color(0xFF174A7E),
              onTap: _completeSharing,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => _showFilterDialog(context),
          icon: const Icon(Icons.filter_alt_rounded, size: 18),
          label: const Text('Filtra Chunk'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple.shade600,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 44),
          ),
        ),
        const SizedBox(height: 24),
        _InstructionsCard(steps: [
          'I QR mostrano solo i dati nuovi o modificati rispetto al ricevente',
          'Il ricevente deve inquadrare questi QR con la fotocamera',
          'Al termine, comunica il PIN di sicurezza al ricevente',
        ]),
      ],
    );
  }

  void _showFilterDialog(BuildContext context) {
    int? startChunk = 0;
    int? endChunk = _diffChunks.length - 1;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Filtra Chunk'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Seleziona l\'intervallo di chunk da mostrare:', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Da chunk', border: OutlineInputBorder()),
                onChanged: (val) => startChunk = int.tryParse(val) ?? 0,
              ),
              const SizedBox(height: 12),
              TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'A chunk', border: OutlineInputBorder()),
                onChanged: (val) => endChunk = int.tryParse(val) ?? _diffChunks.length - 1,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          ElevatedButton(
            onPressed: () {
              if (startChunk != null && endChunk != null) {
                _setChunkFilter(startChunk!, endChunk!);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Applica'),
          ),
        ],
      ),
    );
  }

  // ─── FASE 4: COMPLETATO ───────────────────────────────────────────────

  Widget _buildCompletedPhase() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 48),
              ),
              const SizedBox(height: 24),
              const Text(
                'Trasmissione Differenziale Completata',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF174A7E)),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    const Text('PIN di Sicurezza', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
                    const SizedBox(height: 8),
                    Text(
                      _pin ?? '---',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.amber, letterSpacing: 4),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Comunica questo PIN ${_diffChunks.length > 0 ? "e ${_diffChunks.length} chunk inviati" : ""}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () {
            ref.read(dataShareOptionsProvider.notifier).state = null;
            context.pop();
          },
          icon: const Icon(Icons.home_rounded),
          label: const Text('Torna alla selezione'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF174A7E),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
      ],
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
  final VoidCallback? onTap;

  const _MiniButton({required this.icon, required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: onTap != null ? color : Colors.grey,
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

class _ProgressCard extends StatelessWidget {
  final int current;
  final int total;
  final bool hasFilter;
  final String label;

  const _ProgressCard({
    required this.current,
    required this.total,
    required this.hasFilter,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final progress = current / total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF174A7E), Color(0xFF2E5A8F)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text('$current/$total', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 8,
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
