import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/attachment_parent_type.dart';
import '../../shared/models/catechesi_model.dart';
import '../attachments/widgets/attachments_section.dart';
import 'catechesi_repository.dart';

/// Pagina di creazione / modifica di una scheda catechesi.
///
/// Se riceve un oggetto `Catechesi.existing` popola i campi per la modifica;
/// altrimenti avvia una nuova scheda generando un identificativo univoco
/// tramite `LocalDatabase.newId`. Il salvataggio delega al repository
/// (`CatechesiRepository`) la scrittura nel box Hive `catechesi`.
///
/// I campi comprendono: titolo (obbligatorio), descrizione, tag separati da
/// virgola, riferimenti biblici (uno per riga), riferimenti sitografici (uno
/// per riga) e una sezione allegati per le foto.
class CatechesiEditPage extends ConsumerStatefulWidget {
  final Catechesi? existing;

  const CatechesiEditPage({super.key, this.existing});

  @override
  ConsumerState<CatechesiEditPage> createState() => _CatechesiEditPageState();
}

/// Stato mutabile del form di creazione / modifica catechesi.
///
/// Inizializza i controller di testo a partire dalla catechesi esistente (se
/// presente) oppure vuoti per una nuova scheda. Fornisce i metodi di utilità
/// `_splitLines` e `_splitTags` per parsare i campi multi-riga e i tag. Al
/// salvataggio convalida il titolo, costruisce il modello `Catechesi` e
/// invoca l'operazione add/update sul repository.
class _CatechesiEditPageState extends ConsumerState<CatechesiEditPage> {
  late final String catechesiId;
  late final DateTime createdAt;

  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final biblicalController = TextEditingController();
  final websiteController = TextEditingController();
  final tagsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    catechesiId = widget.existing?.id ?? LocalDatabase.newId('catechesi');
    createdAt = widget.existing?.createdAt ?? DateTime.now();

    final existing = widget.existing;
    if (existing != null) {
      titleController.text = existing.title;
      descriptionController.text = existing.description;
      biblicalController.text = existing.biblicalReferences.join('\n');
      websiteController.text = existing.websiteReferences.join('\n');
      tagsController.text = existing.tags.join(', ');
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    biblicalController.dispose();
    websiteController.dispose();
    tagsController.dispose();
    super.dispose();
  }

  List<String> _splitLines(String text) {
    return text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  List<String> _splitTags(String text) {
    return text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(catechesiRepositoryProvider);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF174A7E),
        foregroundColor: Colors.white,
        title: Text(
          widget.existing == null ? 'Nuova catechesi' : 'Modifica catechesi',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _ModernInputCard(
              icon: Icons.title_rounded,
              color: const Color(0xFF174A7E),
              child: TextField(
                controller: titleController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'Titolo catechesi',
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ModernInputCard(
              icon: Icons.description_rounded,
              color: Colors.blue,
              child: TextField(
                controller: descriptionController,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: 'Descrivi la catechesi...',
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ModernInputCard(
              icon: Icons.label_rounded,
              color: Colors.deepPurple,
              child: TextField(
                controller: tagsController,
                decoration: const InputDecoration(
                  hintText: 'Tag (separati da virgola)',
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ModernInputCard(
              icon: Icons.menu_book_rounded,
              color: Colors.orange,
              child: TextField(
                controller: biblicalController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Riferimenti biblici (uno per riga)',
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ModernInputCard(
              icon: Icons.link_rounded,
              color: Colors.teal,
              child: TextField(
                controller: websiteController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Riferimenti sitografici (uno per riga)',
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            AttachmentsSection(
              parentId: catechesiId,
              parentType: AttachmentParentType.catechesi,
              title: 'Foto e Documenti',
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF174A7E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: const Icon(Icons.save_rounded),
                label: Text(
                  widget.existing == null ? 'Salva catechesi' : 'Aggiorna',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  if (titleController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Inserisci un titolo')),
                    );
                    return;
                  }

                  final now = DateTime.now();
                  final catechesi = Catechesi(
                    id: catechesiId,
                    title: titleController.text.trim(),
                    tags: _splitTags(tagsController.text),
                    biblicalReferences: _splitLines(biblicalController.text),
                    websiteReferences: _splitLines(websiteController.text),
                    photoIds: widget.existing?.photoIds ?? [],
                    description: descriptionController.text.trim(),
                    createdAt: createdAt,
                    updatedAt: now,
                  );

                  try {
                    if (widget.existing == null) {
                      await repo.addCatechesi(catechesi);
                    } else {
                      await repo.updateCatechesi(catechesi.id, catechesi);
                    }
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Errore: $e')),
                      );
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget di contenitore stile "card" per ciascun campo del form.
///
/// Mostra un'icona colorata in testa e il widget figlio (tipicamente un
/// `TextField`) all'interno di un contenitore arrotondato con bordo e ombra
/// coerenti con il linguaggio visivo dell'app CateREG.
class _ModernInputCard extends StatelessWidget {
  final Widget child;
  final IconData icon;
  final Color color;

  const _ModernInputCard({
    required this.child,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
