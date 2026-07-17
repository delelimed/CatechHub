import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../../shared/models/attachment_parent_type.dart';
import '../attachments/widgets/attachments_section.dart';
import '../../shared/models/catechesi_model.dart';
import 'catechesi_repository.dart';

class CatechesiDetailPage extends ConsumerStatefulWidget {
  final Catechesi catechesi;

  const CatechesiDetailPage({super.key, required this.catechesi});

  @override
  ConsumerState<CatechesiDetailPage> createState() => _CatechesiDetailPageState();
}

class _CatechesiDetailPageState extends ConsumerState<CatechesiDetailPage> {
  late Catechesi _catechesi;
  bool _isEditing = false;

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _biblicalController;
  late final TextEditingController _websiteController;
  late final TextEditingController _tagsController;

  @override
  void initState() {
    super.initState();
    _catechesi = widget.catechesi;
    _initControllers();
  }

  void _initControllers() {
    _titleController = TextEditingController(text: _catechesi.title);
    _descriptionController = TextEditingController(text: _catechesi.description);
    _biblicalController = TextEditingController(text: _catechesi.biblicalReferences.join('\n'));
    _websiteController = TextEditingController(text: _catechesi.websiteReferences.join('\n'));
    _tagsController = TextEditingController(text: _catechesi.tags.join(', '));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _biblicalController.dispose();
    _websiteController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _toggleEditing() {
    if (_isEditing) {
      _titleController.text = _catechesi.title;
      _descriptionController.text = _catechesi.description;
      _biblicalController.text = _catechesi.biblicalReferences.join('\n');
      _websiteController.text = _catechesi.websiteReferences.join('\n');
      _tagsController.text = _catechesi.tags.join(', ');
    }
    setState(() => _isEditing = !_isEditing);
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

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci un titolo')),
      );
      return;
    }

    final now = DateTime.now();
    final updated = Catechesi(
      id: _catechesi.id,
      title: _titleController.text.trim(),
      tags: _splitTags(_tagsController.text),
      biblicalReferences: _splitLines(_biblicalController.text),
      websiteReferences: _splitLines(_websiteController.text),
      photoIds: _catechesi.photoIds,
      description: _descriptionController.text.trim(),
      createdAt: _catechesi.createdAt,
      updatedAt: now,
    );

    try {
      final repo = ref.read(catechesiRepositoryProvider);
      await repo.updateCatechesi(updated.id, updated);
      setState(() {
        _catechesi = updated;
        _isEditing = false;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Catechesi aggiornata')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF174A7E),
        foregroundColor: Colors.white,
        title: Text(
          _isEditing ? 'Modifica catechesi' : 'Catechesi',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.lock_open_rounded : Icons.lock_outline_rounded),
            tooltip: _isEditing ? 'Torna a sola lettura' : 'Abilita modifica',
            onPressed: _toggleEditing,
          ),
        ],
      ),
      body: _isEditing ? _buildEditView() : _buildReadOnlyView(),
    );
  }

  Widget _buildReadOnlyView() {
    final formatter = DateFormat('dd MMMM yyyy', 'it_IT');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _catechesi.title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.update_rounded, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                'Modificata ${formatter.format(_catechesi.updatedAt)}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_catechesi.description.trim().isNotEmpty) ...[
            _Section(
              icon: Icons.description_rounded,
              color: Colors.blue,
              title: 'Descrizione',
              child: Text(
                _catechesi.description,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (_catechesi.tags.isNotEmpty) ...[
            _Section(
              icon: Icons.label_rounded,
              color: Colors.deepPurple,
              title: 'Tag',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _catechesi.tags
                    .map(
                      (t) => Chip(
                        label: Text(t),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: Colors.purple.shade100),
                        backgroundColor: Colors.purple.shade50,
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (_catechesi.biblicalReferences.isNotEmpty) ...[
            _Section(
              icon: Icons.menu_book_rounded,
              color: Colors.orange,
              title: 'Riferimenti biblici',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _catechesi.biblicalReferences
                    .map(
                      (b) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '• $b',
                          style: const TextStyle(fontSize: 15, height: 1.4),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (_catechesi.websiteReferences.isNotEmpty) ...[
            _Section(
              icon: Icons.link_rounded,
              color: Colors.teal,
              title: 'Riferimenti sitografici',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _catechesi.websiteReferences
                    .map(
                      (w) => InkWell(
                        onTap: () async {
                          final uri = Uri.tryParse(w);
                          if (uri != null) {
                            final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                            if (!ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Impossibile aprire: $w')),
                              );
                            }
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(Icons.open_in_new_rounded,
                                  size: 16, color: Colors.teal.shade700),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  w,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.teal.shade700,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],
          AttachmentsSection(
            parentId: _catechesi.id,
            parentType: AttachmentParentType.catechesi,
            title: 'Foto e Documenti',
            readOnly: true,
          ),
        ],
      ),
    );
  }

  Widget _buildEditView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _EditField(
            icon: Icons.title_rounded,
            color: const Color(0xFF174A7E),
            child: TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Titolo catechesi',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _EditField(
            icon: Icons.description_rounded,
            color: Colors.blue,
            child: TextField(
              controller: _descriptionController,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: 'Descrivi la catechesi...',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _EditField(
            icon: Icons.label_rounded,
            color: Colors.deepPurple,
            child: TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                hintText: 'Tag (separati da virgola)',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _EditField(
            icon: Icons.menu_book_rounded,
            color: Colors.orange,
            child: TextField(
              controller: _biblicalController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Riferimenti biblici (uno per riga)',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _EditField(
            icon: Icons.link_rounded,
            color: Colors.teal,
            child: TextField(
              controller: _websiteController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Riferimenti sitografici (uno per riga)',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          AttachmentsSection(
            parentId: _catechesi.id,
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
              label: const Text(
                'Salva modifiche',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final Widget child;

  const _Section({
    required this.icon,
    required this.color,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  final Widget child;
  final IconData icon;
  final Color color;

  const _EditField({
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
