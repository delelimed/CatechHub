import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../core/services/qr_data_service.dart';
import '../../core/providers/data_share_provider.dart';

List<Map<String, dynamic>> _buildQrChunkMaps(Map<String, dynamic> args) {
  final data = Map<String, dynamic>.from(args['data'] as Map);
  final pin = args['pin'] as String;

  final package = QRDataService.createPackage(data, pin);
  final compressedPackage = QRDataService.compressData(package.toMap());
  final chunkStrings = QRDataService.segmentData(compressedPackage);

  return chunkStrings
      .asMap()
      .entries
      .map(
        (entry) => QRDataService.createQRChunk(
          entry.value,
          entry.key,
          chunkStrings.length,
        ).toMap(),
      )
      .toList();
}

class DataShareSendPage extends ConsumerStatefulWidget {
  const DataShareSendPage({super.key});

  @override
  ConsumerState<DataShareSendPage> createState() => _DataShareSendPageState();
}

class _DataShareSendPageState extends ConsumerState<DataShareSendPage> {
  Map<String, dynamic>? _data;
  String? _pin;
  List<QRChunk> _chunks = [];
  int _currentChunkIndex = 0;
  Timer? _timer;
  bool _isCompleted = false;
  bool _isPlaying = false;
  bool _isPreparing = true;
  String? _errorMessage;
  int? _filterStartChunk;
  int? _filterEndChunk;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Pulisci i provider quando la pagina viene distrutta
    ref.read(dataShareDataProvider.notifier).state = null;
    ref.read(dataSharePinProvider.notifier).state = null;
    super.dispose();
  }

  void _initializeData() {
    // Recupera i dati dai provider
    final data = ref.read(dataShareDataProvider);
    final pin = ref.read(dataSharePinProvider);

    if (data != null && pin != null) {
      setState(() {
        _data = data;
        _pin = pin;
        _isPreparing = true;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _prepareChunks();
      });
    } else {
      // Se non ci sono dati, torna alla selezione
      if (mounted) {
        context.go('/data-share');
      }
    }
  }

  Future<void> _prepareChunks() async {
    if (_data == null || _pin == null) return;

    setState(() {
      _isPreparing = true;
      _errorMessage = null;
    });

    try {
      final preparedChunkMaps = await compute(_buildQrChunkMaps, {
        'data': _data!,
        'pin': _pin!,
      });

      if (!mounted) return;

      final preparedChunks = preparedChunkMaps
          .map((map) => QRChunk.fromMap(Map<String, dynamic>.from(map)))
          .toList();

      if (!mounted) return;

      setState(() {
        _chunks = preparedChunks;
        _currentChunkIndex = 0;
        _filterStartChunk = null;
        _filterEndChunk = null;
        _isPreparing = false;
        _startAnimation();
      });
    } catch (e, stack) {
      debugPrint('Errore durante la preparazione dei chunk QR: $e');
      if (!mounted) return;
      setState(() {
        _isPreparing = false;
        _errorMessage = 'Errore durante la creazione dei QR code: $e';
      });
    }
  }

  List<QRChunk> _getFilteredChunks() {
    if (_filterStartChunk == null || _filterEndChunk == null) {
      return _chunks;
    }

    final start = _filterStartChunk!.clamp(0, _chunks.length - 1);
    final end = (_filterEndChunk! + 1).clamp(0, _chunks.length);
    return _chunks.sublist(start, end);
  }

  void _setChunkFilter(int start, int end) {
    setState(() {
      _filterStartChunk = start;
      _filterEndChunk = end;
      _currentChunkIndex = start.clamp(0, _chunks.length - 1);
    });
  }

  void _clearChunkFilter() {
    setState(() {
      _filterStartChunk = null;
      _filterEndChunk = null;
      _currentChunkIndex = 0;
    });
  }

  void _startAnimation() {
    // Mostra ogni chunk a 4 FPS (circa 250ms per frame)
    _timer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _currentChunkIndex = (_currentChunkIndex + 1) % _chunks.length;
        _isPlaying = true;
      });
    });
    setState(() => _isPlaying = true);
  }

  void _pauseAnimation() {
    _timer?.cancel();
    setState(() => _isPlaying = false);
  }

  void _resumeAnimation() {
    if (!_isPlaying) {
      _startAnimation();
    }
  }

  void _completeSharing() {
    _pauseAnimation();

    // Pulisci i provider
    ref.read(dataShareDataProvider.notifier).state = null;
    ref.read(dataSharePinProvider.notifier).state = null;

    setState(() {
      _isCompleted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null || _pin == null) {
      return AppScaffold(
        title: 'Errore',
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text('Dati non disponibili'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/data-share'),
                child: const Text('Torna indietro'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isPreparing) {
      return AppScaffold(
        title: 'Preparazione QR',
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(color: Color(0xFF174A7E)),
              SizedBox(height: 16),
              Text(
                'Generazione QR in corso… attendi qualche secondo',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.black87),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return AppScaffold(
        title: 'Errore',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: Colors.black87),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.go('/data-share'),
                  child: const Text('Riprova dalla selezione'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_chunks.isEmpty) {
      return AppScaffold(
        title: 'Preparazione...',
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF174A7E)),
        ),
      );
    }

    final currentChunk = _chunks[_currentChunkIndex];
    final filteredChunks = _getFilteredChunks();

    return AppScaffold(
      title: 'Invio Dati',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_isCompleted)
              _CompletionCard(pin: _pin!)
            else
              _QRDisplayCard(
                chunk: currentChunk,
                currentChunkIndex: _currentChunkIndex,
                totalChunks: _chunks.length,
                isPlaying: _isPlaying,
                hasFilter: _filterStartChunk != null,
                onPause: _pauseAnimation,
                onResume: _resumeAnimation,
                onComplete: _completeSharing,
                onSetFilter: _setChunkFilter,
                onClearFilter: _clearChunkFilter,
              ),
          ],
        ),
      ),
    );
  }
}

class _QRDisplayCard extends StatelessWidget {
  final QRChunk chunk;
  final int currentChunkIndex;
  final int totalChunks;
  final bool isPlaying;
  final bool hasFilter;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onComplete;
  final Function(int, int) onSetFilter;
  final VoidCallback onClearFilter;

  const _QRDisplayCard({
    required this.chunk,
    required this.currentChunkIndex,
    required this.totalChunks,
    required this.isPlaying,
    required this.hasFilter,
    required this.onPause,
    required this.onResume,
    required this.onComplete,
    required this.onSetFilter,
    required this.onClearFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProgressCard(
          current: currentChunkIndex + 1,
          total: totalChunks,
          hasFilter: hasFilter,
        ),
        const SizedBox(height: 24),

        _PinCard(pin: '****'), // PIN nascosto durante trasmissione
        const SizedBox(height: 24),

        if (hasFilter)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(
                    Icons.filter_list_rounded,
                    color: Colors.blue,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Filtro Attivo',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: onClearFilter,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Mostra Tutti'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),

        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(color: const Color(0xFF174A7E), width: 2),
          ),
          child: Column(
            children: [
              // QR Code con margine bianco ampio per migliore lettura
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black, width: 3),
                ),
                child: QrImageView(
                  data: chunk.toJson(),
                  version: QrVersions.auto,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  size: 380,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Inquadra il QR code dal dispositivo ricevente',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        _InfoText(
          text: 'Chunk ${currentChunkIndex + 1} di $totalChunks',
          icon: Icons.qr_code_2_rounded,
        ),
        const SizedBox(height: 8),

        _InfoText(
          text: isPlaying ? 'In trasmissione...' : 'In pausa',
          icon: isPlaying
              ? Icons.autorenew_rounded
              : Icons.pause_circle_rounded,
        ),
        const SizedBox(height: 32),

        Row(
          children: [
            Expanded(
              child: _ControlButton(
                icon: Icons.pause_rounded,
                label: 'Pausa',
                color: Colors.orange,
                isActive: isPlaying,
                onTap: isPlaying ? onPause : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ControlButton(
                icon: Icons.play_arrow_rounded,
                label: 'Riprendi',
                color: Colors.green,
                isActive: !isPlaying,
                onTap: !isPlaying ? onResume : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ControlButton(
                icon: Icons.check_rounded,
                label: 'Completa',
                color: const Color(0xFF174A7E),
                isActive: true,
                onTap: onComplete,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        ElevatedButton.icon(
          onPressed: () => _showFilterDialog(context),
          icon: const Icon(Icons.filter_alt_rounded),
          label: const Text('Filtra Chunk'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple.shade600,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ],
    );
  }

  void _showFilterDialog(BuildContext context) {
    int? startChunk = 0;
    int? endChunk = totalChunks - 1;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Filtra Chunk'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Seleziona l\'intervallo di chunk da mostrare:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Da chunk',
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) {
                  startChunk = int.tryParse(val) ?? 0;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'A chunk',
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) {
                  endChunk = int.tryParse(val) ?? totalChunks - 1;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () {
              if (startChunk != null && endChunk != null) {
                onSetFilter(startChunk!, endChunk!);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Applica'),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final int current;
  final int total;
  final bool hasFilter;

  const _ProgressCard({
    required this.current,
    required this.total,
    required this.hasFilter,
  });

  @override
  Widget build(BuildContext context) {
    final progress = current / total;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF174A7E).withOpacity(0.8),
            const Color(0xFF2E5A8F).withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Progresso Trasmissione',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (hasFilter)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                  ),
                  child: const Text(
                    'Filtrato',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Text(
                  '$current/$total',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}

class _PinCard extends StatelessWidget {
  final String pin;

  const _PinCard({required this.pin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.security_rounded, color: Colors.amber, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PIN di Sicurezza',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Comunica questo PIN al ricevente: $pin',
                  style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  final String pin;

  const _CompletionCard({required this.pin});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Trasmissione Completata',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF174A7E),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'PIN: $pin',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Il ricevente deve inserire questo PIN per completare l\'importazione',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        ElevatedButton.icon(
          onPressed: () => context.go('/data-share'),
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

class _InfoText extends StatelessWidget {
  final String text;
  final IconData icon;

  const _InfoText({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isActive;
  final VoidCallback? onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive && onTap != null
              ? color.withOpacity(0.1)
              : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive && onTap != null
                ? color.withOpacity(0.3)
                : Colors.grey.withOpacity(0.2),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isActive && onTap != null ? color : Colors.grey.shade400,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isActive && onTap != null ? color : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
