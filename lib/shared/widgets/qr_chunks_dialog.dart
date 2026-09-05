import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/qr_data_service.dart';

/// Dialog che mostra uno o più QR (chunk) con navigazione avanti/indietro.
/// Riusato dal modulo Supplenze per: delega, consegna dati e revoca.
class QrChunksDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> chunks;
  final String? footer;

  const QrChunksDialog({
    super.key,
    required this.title,
    required this.chunks,
    this.subtitle = '',
    this.footer,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<Map<String, dynamic>> chunks,
    String subtitle = '',
    String? footer,
  }) {
    return showDialog(
      context: context,
      builder: (_) => QrChunksDialog(
        title: title,
        subtitle: subtitle,
        chunks: chunks,
        footer: footer,
      ),
    );
  }

  @override
  State<QrChunksDialog> createState() => _QrChunksDialogState();
}

class _QrChunksDialogState extends State<QrChunksDialog> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final chunks = widget.chunks;
    final chunk = chunks[_index];
    final qrData = QRChunk.fromMap(Map<String, dynamic>.from(chunk)).toJson();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.subtitle.isNotEmpty) ...[
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 14),
            ],
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
            if (chunks.length > 1) ...[
              const SizedBox(height: 10),
              Text(
                'QR ${_index + 1} di ${chunks.length}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              widget.footer ??
                  'Inquadrare i QR nell\'ordine mostrato, uno alla volta.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        if (chunks.length > 1) ...[
          TextButton(
            onPressed: _index > 0 ? () => setState(() => _index--) : null,
            child: const Text('Precedente'),
          ),
          TextButton(
            onPressed: _index < chunks.length - 1
                ? () => setState(() => _index++)
                : null,
            child: const Text('Successivo'),
          ),
        ],
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
      ],
    );
  }
}
