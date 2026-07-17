/// Schermata a tutto schermo per la visualizzazione di allegati (immagini e PDF).
///
/// Nel contesto di CateREG, questa pagina viene aperta da [AttachmentsSection]
/// quando l'utente tocca un allegato. Supporta:
/// - **Immagini** (JPEG/PNG/WEBP/GIF) visualizzate con [InteractiveViewer] per zoom
/// - **PDF** renderizzati con [PdfPreview] (libreria `printing`)
/// - **Stampa PDF** tramite il pulsante nell'AppBar (visibile solo per PDF)
///
/// I byte vengono letti al volo da [AttachmentsRepository.readBytes], che recupera
/// i dati crittografati dal vault locale (vedi [EncryptedFileStorage]).
///
/// In caso di errore di lettura, mostra un messaggio in italiano
/// ("Impossibile aprire il file") con il dettaglio dell'errore.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../shared/models/attachment_model.dart';
import 'attachments_repository.dart';

class AttachmentViewerPage extends ConsumerStatefulWidget {
  const AttachmentViewerPage({super.key, required this.attachment});

  final Attachment attachment;

  @override
  ConsumerState<AttachmentViewerPage> createState() =>
      _AttachmentViewerPageState();
}

class _AttachmentViewerPageState extends ConsumerState<AttachmentViewerPage> {
  @override
  Widget build(BuildContext context) {
    final att = widget.attachment;
    final bytesFuture =
        ref.read(attachmentsRepositoryProvider).readBytes(att.id);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF174A7E),
        foregroundColor: Colors.white,
        title: Text(
          att.name,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (att.isPdf)
            IconButton(
              icon: const Icon(Icons.print_rounded),
              onPressed: () async {
                final bytes = await bytesFuture;
                if (!context.mounted) return;
                await Printing.layoutPdf(
                  name: att.name,
                  onLayout: (_) async => bytes,
                );
              },
            ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: bytesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Impossibile aprire il file.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            );
          }

          final bytes = snapshot.data!;
          if (att.isImage) {
            return InteractiveViewer(
              child: Center(
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            );
          }

          if (att.isPdf) {
            return PdfPreview(
              build: (_) async => bytes,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              allowPrinting: false,
              allowSharing: false,
            );
          }

          return const Center(
            child: Text(
              'Tipo file non supportato in anteprima',
              style: TextStyle(color: Colors.white70),
            ),
          );
        },
      ),
    );
  }
}
