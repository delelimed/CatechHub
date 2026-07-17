/// Widget che mostra la sezione "Foto e documenti" all'interno delle schede
/// di dettaglio di CateREG (pratiche, clienti, fatture, ecc.).
///
/// Funzionalità principali:
///
/// - **Elenco reattivo**: usa uno [StreamBuilder] con [AttachmentsRepository.watchForParent]
///   per aggiornarsi automaticamente quando gli allegati del padre cambiano.
///
/// - **Aggiunta file**: tramite [ImagePicker] (camera/galleria) o [FilePicker] (PDF).
///   Le foto vengono scattate/selezionate con qualità 70% e max 2048px, poi passate
///   al repository che le ottimizzerà ulteriormente.
///
/// - **Rinomina**: dialogo modale che preserva automaticamente l'estensione originale.
///
/// - **Eliminazione**: conferma con dialogo prima di rimuovere l'allegato sia
///   dal vault crittografato che dal database.
///
/// - **Visualizzazione**: apre [AttachmentViewerPage] per la preview full-screen.
///
/// Il parametro [readOnly] disabilita tutte le azioni modificative (aggiungi,
/// rinomina, elimina), utile in contesti di sola consultazione.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../shared/models/attachment_model.dart';
import '../attachment_viewer_page.dart';
import '../attachments_repository.dart';

class AttachmentsSection extends ConsumerWidget {
  const AttachmentsSection({
    super.key,
    required this.parentId,
    required this.parentType,
    this.title = 'Foto e documenti',
    this.readOnly = false,
  });

  final String parentId;
  final String parentType;
  final String title;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(attachmentsRepositoryProvider);

    return StreamBuilder<List<Attachment>>(
      stream: repo.watchForParent(parentId: parentId, parentType: parentType),
      builder: (context, snapshot) {
        final attachments = snapshot.data ?? [];

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.lock_rounded,
                    color: Color(0xFF174A7E),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF174A7E),
                      ),
                    ),
                  ),
                  if (!readOnly)
                    IconButton(
                      tooltip: 'Aggiungi',
                      onPressed: () => _showAddMenu(context, ref),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      color: const Color(0xFF174A7E),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Salvati cifrati e compressi (foto max 1600px, JPEG).',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData)
                const Center(child: CircularProgressIndicator())
              else if (attachments.isEmpty)
                Text(
                  'Nessun allegato',
                  style: TextStyle(color: Colors.grey.shade500),
                )
              else
                ...attachments.map(
                  (att) => _AttachmentTile(
                    attachment: att,
                    readOnly: readOnly,
                    onOpen: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AttachmentViewerPage(attachment: att),
                        ),
                      );
                    },
                    onDelete: readOnly
                        ? null
                        : () => _confirmDelete(context, ref, att),
                    onRename: readOnly
                        ? null
                        : () => _renameAttachment(context, ref, att),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddMenu(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Scatta foto'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Scegli dalla galleria'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded),
              title: const Text('Importa PDF'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
          ],
        ),
      ),
    );

    if (choice == null || !context.mounted) return;

    try {
      switch (choice) {
        case 'camera':
          await _pickImage(context, ref, ImageSource.camera);
          break;
        case 'gallery':
          await _pickImage(context, ref, ImageSource.gallery);
          break;
        case 'pdf':
          await _pickPdf(context, ref);
          break;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Errore: $e')));
      }
    }
  }

  Future<void> _pickImage(
    BuildContext context,
    WidgetRef ref,
    ImageSource source,
  ) async {
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        throw Exception('Permesso fotocamera negato');
      }
    } else if (source == ImageSource.gallery) {
      // Su Android 13+ serve READ_MEDIA_IMAGES, su Android <13 READ_EXTERNAL_STORAGE
      // Il permission_handler gestisce automaticamente la differenza
      final status = await Permission.photos.request();
      if (!status.isGranted) {
        throw Exception('Permesso galleria negato');
      }
    }
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (file == null) return;

    // Genera un nome appropriato per il file
    String fileName = file.name.isNotEmpty
        ? file.name
        : 'file_${DateTime.now().millisecondsSinceEpoch}';

    // Chiedi all'utente di confermare o modificare il nome
    final finalName = await _askForFileName(context, fileName);

    final repo = ref.read(attachmentsRepositoryProvider);
    final saved = await repo.addFromPath(
      parentId: parentId,
      parentType: parentType,
      filePath: file.path,
      name: finalName,
      mimeType: _mimeFromPath(file.path, fallback: 'image/jpeg'),
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_savedMessage(saved.size, 'Foto'))),
      );
    }
  }

  Future<void> _pickPdf(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final path = file.path;

    // Chiedi all'utente di confermare o modificare il nome
    final finalName = await _askForFileName(context, file.name);

    final repo = ref.read(attachmentsRepositoryProvider);
    final saved;
    if (path != null) {
      saved = await repo.addFromPath(
        parentId: parentId,
        parentType: parentType,
        filePath: path,
        name: finalName,
        mimeType: 'application/pdf',
      );
    } else {
      final bytes = await file.readAsBytes();
      saved = await repo.addFromBytes(
        parentId: parentId,
        parentType: parentType,
        name: finalName,
        mimeType: 'application/pdf',
        bytes: bytes,
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_savedMessage(saved.size, 'PDF'))));
    }
  }

  Future<String> _askForFileName(
    BuildContext context,
    String defaultName,
  ) async {
    final controller = TextEditingController(text: defaultName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nome allegato'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Inserisci il nome del file',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result?.trim().isNotEmpty == true ? result! : defaultName;
  }

  Future<void> _renameAttachment(
    BuildContext context,
    WidgetRef ref,
    Attachment att,
  ) async {
    final originalExtension = _extensionOf(att.name);
    final controller = TextEditingController(text: _stripExtension(att.name));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rinomina allegato'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Nuovo nome del file',
            suffixText: originalExtension,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    controller.dispose();

    final typedName = result?.trim();
    if (typedName != null && typedName.isNotEmpty) {
      final preservedName = _preserveExtension(
        att.name,
        _stripExtension(typedName),
      );
      if (preservedName != att.name) {
        await ref
            .read(attachmentsRepositoryProvider)
            .updateAttachmentName(attachmentId: att.id, name: preservedName);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Nome aggiornato in "$preservedName"')),
          );
        }
      }
    }
  }

  String _preserveExtension(String originalName, String newName) {
    final originalExtension = _extensionOf(originalName);
    if (originalExtension.isEmpty) return newName.trim();
    return '${newName.trim()}$originalExtension';
  }

  String _stripExtension(String name) {
    final index = name.lastIndexOf('.');
    if (index < 0) return name.trim();
    return name.substring(0, index).trim();
  }

  String _extensionOf(String name) {
    final index = name.lastIndexOf('.');
    if (index < 0 || index == name.length - 1) return '';
    return name.substring(index);
  }

  String _savedMessage(int bytes, String type) {
    final kb = (bytes / 1024).ceil();
    if (kb < 1024) {
      return '$type salvato in modo sicuro (~$kb KB)';
    }
    return '$type salvato in modo sicuro (~${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB)';
  }

  String _mimeFromPath(String path, {required String fallback}) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return fallback;
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Attachment att,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina allegato'),
        content: Text('Eliminare "${att.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(attachmentsRepositoryProvider).deleteAttachment(att.id);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Allegato eliminato')));
    }
  }
}

/// Singola riga di allegato nella lista di [AttachmentsSection].
///
/// Mostra l'icona (immagine/PDF/file generico), il nome, la dimensione
/// formattata, la data e i pulsanti di rinomina/eliminazione in base al
/// parametro [readOnly]. Al tap apre [AttachmentViewerPage].
class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.readOnly,
    required this.onOpen,
    this.onDelete,
    this.onRename,
  });

  final Attachment attachment;
  final bool readOnly;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    final icon = attachment.isImage
        ? Icons.image_rounded
        : attachment.isPdf
        ? Icons.picture_as_pdf_rounded
        : Icons.insert_drive_file_rounded;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.grey.shade50,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF174A7E)),
        title: Text(
          attachment.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${attachment.sizeLabel} · ${_formatDate(attachment.createdAt)}',
        ),
        trailing: readOnly
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onRename != null)
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, color: Colors.blue),
                      onPressed: onRename,
                      tooltip: 'Rinomina',
                    ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red,
                      ),
                      onPressed: onDelete,
                      tooltip: 'Elimina',
                    ),
                ],
              ),
        onTap: onOpen,
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}
