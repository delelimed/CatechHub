import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../core/services/qr_data_service.dart';
import '../../core/services/data_export_service.dart';

class DataShareReceivePage extends StatefulWidget {
  const DataShareReceivePage({super.key});

  @override
  State<DataShareReceivePage> createState() => _DataShareReceivePageState();
}

class _DataShareReceivePageState extends State<DataShareReceivePage> {
  final List<QRChunk> _receivedChunks = [];
  final Set<int> _receivedChunkIndices = {};
  String? _assembledPackageData;
  final TextEditingController _pinController = TextEditingController();
  bool _isScanning = true;
  bool _isVerifyingPin = false;
  bool _isImporting = false;
  String? _errorMessage;
  int _totalChunks = 0;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _onQRCodeDetected(BarcodeCapture capture) {
    if (!_isScanning || _isVerifyingPin || _isImporting) return;

    final barcode = capture.barcodes.first;
    final code = barcode.rawValue;

    if (code != null && code.isNotEmpty) {
      _processQRCode(code);
    }
  }

  void _processQRCode(String qrData) {
    try {
      final chunk = QRChunk.fromJson(qrData);

      // Verifica checksum del chunk
      if (!QRDataService.verifyChunkChecksum(chunk)) {
        setState(() {
          _errorMessage = 'Checksum non valido per il chunk';
        });
        return;
      }

      // Traccia il totale dei chunks
      if (_totalChunks == 0) {
        setState(() {
          _totalChunks = chunk.totalChunks;
        });
      }

      // Aggiungi chunk se non già ricevuto
      if (!_receivedChunkIndices.contains(chunk.chunkIndex)) {
        setState(() {
          _receivedChunks.add(chunk);
          _receivedChunkIndices.add(chunk.chunkIndex);
          _errorMessage = null;
        });

        // Controlla se tutti i chunk sono stati ricevuti
        if (_receivedChunkIndices.length == chunk.totalChunks) {
          _allChunksReceived();
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore nell\'elaborazione del QR code: $e';
      });
    }
  }

  void _allChunksReceived() {
    // Ferma scansione
    setState(() {
      _isScanning = false;
    });

    // Assembla i chunk
    try {
      final assembledData = QRDataService.assembleChunks(_receivedChunks);
      QRDataService.extractPackage(assembledData);

      setState(() {
        _assembledPackageData = assembledData;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore nell\'assemblaggio dei dati: $e';
        _isScanning = true;
      });
    }
  }

  void _verifyAndImport() {
    if (_assembledPackageData == null) {
      setState(() {
        _errorMessage = 'Pacchetto dati non disponibile';
      });
      return;
    }

    final inputPin = _pinController.text.trim();
    if (inputPin.length != 8) {
      setState(() {
        _errorMessage = 'Il PIN deve essere di 8 cifre';
      });
      return;
    }

    setState(() {
      _isVerifyingPin = true;
      _isImporting = true;
      _errorMessage = null;
    });

    _importData(inputPin);
  }

  Future<void> _importData(String pin) async {
    try {
      final receivedData = QRDataService.extractPackageData(
        _assembledPackageData!,
        pin,
      );

      // Verifica integrità dati per pacchetti selettivi
      if (!DataExportService.verifyDataIntegrity(
        receivedData,
        requireFullPackage: false,
      )) {
        setState(() {
          _errorMessage = 'Integrità dei dati non valida';
          _isImporting = false;
          _isScanning = true;
        });
        return;
      }

      // Importa i dati
      await DataExportService.importData(receivedData);

      // Importazione completata
      setState(() {
        _isImporting = false;
        _isVerifyingPin = false;
      });
      if (mounted) {
        setState(() {
          _isImporting = false;
          _isVerifyingPin = false;
        });
        _showSuccessDialog();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'PIN non corretto o dati non validi';
        _isImporting = false;
        _isVerifyingPin = false;
        _isScanning = true;
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Importazione Completata'),
          ],
        ),
        content: const Text('I dati sono stati importati con successo.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/'); // Torna alla home
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
      _isVerifyingPin = false;
      _isImporting = false;
      _errorMessage = null;
      _totalChunks = 0;
    });
  }

  List<int> _getMissingChunkIndices() {
    if (_totalChunks == 0) return [];
    final missing = <int>[];
    for (int i = 0; i < _totalChunks; i++) {
      if (!_receivedChunkIndices.contains(i)) {
        missing.add(i);
      }
    }
    return missing;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Ricezione Dati',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_isImporting)
              _ImportingCard()
            else if (_assembledPackageData != null)
              _PinVerificationCard(
                controller: _pinController,
                onVerify: _verifyAndImport,
                onReset: _resetScanning,
                errorMessage: _errorMessage,
              )
            else
              _ScanningCard(
                isScanning: _isScanning,
                receivedCount: _receivedChunks.length,
                totalChunks: _totalChunks,
                missingChunkIndices: _getMissingChunkIndices(),
                onQRCodeDetected: _onQRCodeDetected,
                errorMessage: _errorMessage,
                onToggleScanning: () {
                  setState(() {
                    _isScanning = !_isScanning;
                    _errorMessage = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ScanningCard extends StatefulWidget {
  final bool isScanning;
  final int receivedCount;
  final int totalChunks;
  final List<int> missingChunkIndices;
  final Function(BarcodeCapture) onQRCodeDetected;
  final String? errorMessage;
  final VoidCallback onToggleScanning;

  const _ScanningCard({
    required this.isScanning,
    required this.receivedCount,
    required this.totalChunks,
    required this.missingChunkIndices,
    required this.onQRCodeDetected,
    required this.errorMessage,
    required this.onToggleScanning,
  });

  @override
  State<_ScanningCard> createState() => _ScanningCardState();
}

class _ScanningCardState extends State<_ScanningCard> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.isScanning
                  ? const Color(0xFF174A7E)
                  : Colors.grey.shade400,
              width: 2,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: widget.isScanning
                ? MobileScanner(onDetect: widget.onQRCodeDetected)
                : Container(
                    color: Colors.grey.shade200,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Scansione in pausa',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 24),

        _ProgressInfo(
          receivedCount: widget.receivedCount,
          totalChunks: widget.totalChunks,
          missingChunkIndices: widget.missingChunkIndices,
        ),
        const SizedBox(height: 16),

        if (widget.errorMessage != null)
          _ErrorMessage(message: widget.errorMessage!),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: widget.onToggleScanning,
                icon: Icon(
                  widget.isScanning
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(widget.isScanning ? 'Pausa' : 'Riprendi'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.isScanning
                      ? Colors.orange
                      : Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.go('/data-share'),
                icon: const Icon(Icons.cancel_rounded),
                label: const Text('Annulla'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _InstructionsCard(),
      ],
    );
  }
}

class _PinVerificationCard extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onVerify;
  final VoidCallback onReset;
  final String? errorMessage;

  const _PinVerificationCard({
    required this.controller,
    required this.onVerify,
    required this.onReset,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.green,
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                'Tutti i chunk ricevuti!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF174A7E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Inserisci il PIN di 8 cifre fornito dal mittente per completare l\'importazione',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: InputDecoration(
            labelText: 'PIN di sicurezza',
            hintText: 'Inserisci 8 cifre',
            prefixIcon: const Icon(Icons.security_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            counterText: '',
          ),
          style: const TextStyle(fontSize: 20, letterSpacing: 8),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        if (errorMessage != null) _ErrorMessage(message: errorMessage!),
        const SizedBox(height: 16),

        ElevatedButton.icon(
          onPressed: onVerify,
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
          onPressed: onReset,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Ricomincia scansione'),
        ),
      ],
    );
  }
}

class _ImportingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const CircularProgressIndicator(color: Color(0xFF174A7E)),
          const SizedBox(height: 24),
          const Text(
            'Importazione in corso...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'I dati vengono salvati. Non chiudere l\'app.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _ProgressInfo extends StatelessWidget {
  final int receivedCount;
  final int totalChunks;
  final List<int> missingChunkIndices;

  const _ProgressInfo({
    required this.receivedCount,
    required this.totalChunks,
    required this.missingChunkIndices,
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
            gradient: LinearGradient(
              colors: [
                const Color(0xFF174A7E).withOpacity(0.8),
                const Color(0xFF2E5A8F).withOpacity(0.8),
              ],
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
                          const Text(
                            'Chunk ricevuti',
                            style: TextStyle(
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
                      color: Colors.white.withOpacity(0.2),
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
                    backgroundColor: Colors.white.withOpacity(0.3),
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
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mancanti: ${missingChunkIndices.length} chunk',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      Text(
                        '#${missingChunkIndices.join(', #')}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
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
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
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
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_rounded, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                'Istruzioni',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InstructionStep(
            number: 1,
            text: 'Inquadra i QR code mostrati dal dispositivo mittente',
          ),
          _InstructionStep(
            number: 2,
            text:
                'I QR code vengono mostrati ciclicamente, puoi riprovare se ne perdi uno',
          ),
          _InstructionStep(
            number: 3,
            text:
                'Quando tutti i chunk sono ricevuti, inserisci il PIN fornito',
          ),
          _InstructionStep(
            number: 4,
            text: 'I dati verranno importati sostituendo quelli esistenti',
          ),
        ],
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  final int number;
  final String text;

  const _InstructionStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue.shade700,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
