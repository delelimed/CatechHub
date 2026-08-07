import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/class_scoped_providers.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/models/catechesi_model.dart';
import '../../shared/widgets/last_modified_info.dart';
import 'catechesi_repository.dart';

/// Pagina principale dell'applicazione CateREG per la gestione dell'archivio
/// delle catechesi.
///
/// Mostra un elenco navigabile di tutte le schede catechesi salvate nel
/// database Hive cifrato offline. Ogni elemento (`_CatechesiCard`) espone
/// titolo, descrizione, tag e data di ultima modifica. Dalla barra superiore
/// è possibile avviare la creazione di una nuova catechesi o filtrarle tramite
/// ricerca testuale su titolo, tag, riferimenti biblici e sitografici.
///
/// Le azioni disponibili su ogni scheda (modifica / eliminazione con conferma)
/// sono accessibili tramite il menu contestuale (`PopupMenuButton`).
class CatechesiPage extends ConsumerStatefulWidget {
  const CatechesiPage({super.key});

  @override
  ConsumerState<CatechesiPage> createState() => _CatechesiPageState();
}

/// Stato mutevole della pagina [CatechesiPage].
///
/// Gestisce la logica di ricerca locale (`_query`) e si abbina allo
/// stream del repository per aggiornare la UI in tempo reale quando il
/// database Hive subisce modifiche.
class _CatechesiPageState extends ConsumerState<CatechesiPage> {
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catechesiAsync = ref.watch(currentClassCatechesiProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return AppScaffold(
      title: 'Catechesi',
      floatingActionButton: FloatingActionButton.extended(
        elevation: 4,
        backgroundColor: isDark ? colorScheme.primary : const Color(0xFF174A7E),
        foregroundColor: isDark ? colorScheme.onPrimary : Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Nuova catechesi',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        onPressed: () {
          context.push('/catechesi/edit');
        },
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (q) => setState(() => _query = q),
              decoration: InputDecoration(
                hintText: 'Cerca per titolo o tag...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? colorScheme.surfaceContainer : Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: catechesiAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Errore: $e')),
              data: (all) {
                final items = _query.isEmpty
                    ? all
                    : all.where((c) {
                        final q = _query.toLowerCase();
                        if (c.title.toLowerCase().contains(q)) return true;
                        if (c.tags.any((t) => t.toLowerCase().contains(q))) return true;
                        if (c.biblicalReferences.any((b) => b.toLowerCase().contains(q))) return true;
                        if (c.websiteReferences.any((w) => w.toLowerCase().contains(q))) return true;
                        return false;
                      }).toList();

                items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.menu_book_rounded,
                              size: 56, color: isDark ? Colors.grey.shade600 : Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text(
                            _query.isEmpty
                                ? 'Nessuna catechesi salvata'
                                : 'Nessun risultato',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? colorScheme.onSurface : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final c = items[i];
                    return _CatechesiCard(
                      catechesi: c,
                      isDark: isDark,
                      colorScheme: colorScheme,
                      onDeleted: () => setState(() {}),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget privato che visualizza una singola scheda catechesi nell'elenco.
///
/// Mostra titolo (con colore primario CateREG), descrizione (troncata a 3
/// righe), tag sotto forma di `Chip` e data di aggiornamento. Alla pressione
/// naviga verso `CatechesiDetailPage`; dal menu `PopupMenuButton` si accede
/// alle azioni di modifica ed eliminazione (con dialogo di conferma).
class _CatechesiCard extends StatelessWidget {
  final Catechesi catechesi;
  final VoidCallback onDeleted;
  final bool isDark;
  final ColorScheme colorScheme;

  const _CatechesiCard({
    required this.catechesi,
    required this.onDeleted,
    required this.isDark,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        context.push('/catechesi/detail', extra: {'catechesi': catechesi});
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? colorScheme.surfaceContainer : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.03),
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
                Expanded(
                  child: Text(
                    catechesi.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, size: 20, color: isDark ? colorScheme.onSurface : null),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (v) async {
                    if (v == 'edit') {
                      context.push('/catechesi/edit', extra: {'catechesi': catechesi});
                    } else if (v == 'delete') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Elimina catechesi'),
                          content: const Text(
                              'Sei sicuro di voler eliminare questa catechesi?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Annulla'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.red),
                              child: const Text('Elimina'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && context.mounted) {
                        final repo = CatechesiRepository();
                        await repo.deleteCatechesi(catechesi.id);
                        onDeleted();
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Modifica'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_rounded,
                              size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Elimina', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (catechesi.description.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                catechesi.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: isDark ? Colors.grey.shade300 : Colors.grey.shade700, height: 1.35),
              ),
            ],
            if (catechesi.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: catechesi.tags
                    .map(
                      (t) => Chip(
                        label: Text(t),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: isDark ? colorScheme.primary.withValues(alpha: 0.3) : Colors.blue.shade100),
                        backgroundColor: isDark ? colorScheme.primaryContainer.withValues(alpha: 0.2) : Colors.blue.shade50,
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 8),
            LastModifiedInfo(
              updatedAt: catechesi.updatedAt,
              lastModifiedBy: catechesi.lastModifiedBy,
              compact: true,
            ),
          ],
        ),
      ),
    );
  }
}
