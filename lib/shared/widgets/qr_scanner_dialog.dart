import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/qr_data_service.dart';

/// Dialog di scansione per QR segmentati in chunk (modulo Supplenze).
///
/// Raccoglie i chunk finché il gruppo non è completo, poi pop() con la
/// stringa assemblata ([QRDataService.assembleChunks]). Usa [MobileScanner].
class QrScannerDialog extends StatefulWidget {
  final String title;
  final String hint;

  const QrScannerDialog({
    super.key,
    this.title = 'Scansiona QR',
    this.hint = 'Inquadra i QR mostrati dall\'altro dispositivo.',
  });

  /// Mostra il dialog e restituisce la stringa assemblata (o null se annullato).
  static Future<String?> show(
    BuildContext context, {
    String title = 'Scansiona QR',
    String hint = 'Inquadra i QR mostrati dall\'altro dispositivo.',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => QrScannerDialog(title: title, hint: hint),
    );
  }

  @override
  State<QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<QrScannerDialog> {
  final List<QRChunk> _chunks = [];
  final Set<int> _seenIndexes = {};
  MobileScannerController? _controller;
  String? _status;
  bool _completing = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_completing) return;
    final barcode = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (barcode == null || barcode.isEmpty) return;
    QRChunk chunk;
    try {
      chunk = QRChunk.fromJson(barcode);
    } catch (_) {
      // QR non riconosciuto come chunk: ignora.
      return;
    }
    if (_seenIndexes.contains(chunk.chunkIndex)) return;

    setState(() {
      _seenIndexes.add(chunk.chunkIndex);
      _chunks.add(chunk);
      if (_chunks.length == chunk.totalChunks) {
        _status = 'QR completi, verifica in corso…';
      } else {
        _status = 'QR scansionati: ${_chunks.length}/${chunk.totalChunks}';
      }
    });

    if (_chunks.length == chunk.totalChunks) {
      _complete();
    }
  }

  Future<void> _complete() async {
    if (_completing) return;
    _completing = true;
    await _controller?.stop();
    String assembled;
    try {
      assembled = QRDataService.assembleChunks(_chunks);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore QR: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      Navigator.pop(context);
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, assembled);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        height: 360,
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MobileScanner(
                  onDetect: _onDetect,
                  controller: _controller,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _status ?? widget.hint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
      ],
    );
  }
}