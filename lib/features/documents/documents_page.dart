import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'package:go_router/go_router.dart';
import 'documents_provider.dart';
import 'documents_repository.dart';

/// Pagina principale della sezione Documenti in CateREG.
///
/// Mostra l'elenco di tutti i documenti (certificati, autorizzazioni, moduli,
/// fogli informativi, etc.) creati dal catechista per la propria classe.
/// Per ogni documento viene mostrato il numero di ragazzi che devono ancora
/// consegnarlo, permettendo di monitorare rapidamente le mancate consegne.
/// Dalla pagina è possibile creare nuovi documenti (tramite FAB "+") ed
/// eliminare quelli esistenti. La navigazione al dettaglio avviene tramite tap.
class DocumentsPage extends ConsumerWidget {
  const DocumentsPage({super.key});

  /// Mostra un dialog per la creazione di un nuovo documento.
  ///
  /// Richiede all'utente di inserire un titolo descrittivo (es. "Autorizzazione
  /// Campo Estivo", "Certificato di Battesimo", "Modulo di Iscrizione").
  /// Al salvataggio, il documento viene persistito su Hive tramite il
  /// [DocumentsRepository].
  void _showCreateDocumentDialog(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Nuovo Documento',
          style: TextStyle(color: Color(0xFF174A7E), fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Titolo del documento',
            hintText: 'es. Autorizzazione Campi Estivi',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF174A7E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final text = titleController.text.trim();
              if (text.isNotEmpty) {
                // Catturiamo il Navigator prima del blocco asincrono per evitare GoRouterState Error
                final navigator = Navigator.of(dialogContext);

                await ref.read(documentsRepoProvider).addDocument(text);
                
                navigator.pop();
              }
            },
            child: const Text('Crea'),
          ),
        ],
      ),
    );
  }

  /// Mostra un dialog per modificare il nome di un documento esistente.
  void _showEditDocumentDialog(
    BuildContext context,
    WidgetRef ref,
    String docId,
    String currentTitle,
  ) {
    final titleController = TextEditingController(text: currentTitle);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Modifica Documento',
          style: TextStyle(color: Color(0xFF174A7E), fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Titolo del documento',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF174A7E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final text = titleController.text.trim();
              if (text.isNotEmpty) {
                final navigator = Navigator.of(dialogContext);
                await ref.read(documentsRepoProvider).updateDocument(docId, text);
                navigator.pop();
              }
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  /// Costruisce l'interfaccia della lista documenti.
  ///
  /// Mostra ogni documento come card con titolo, conteggio dei mancanti
  /// (calcolato solo sugli studenti della classe del catechista) e menu
  /// contestuale per l'eliminazione. Lo stato "Completato" appare verde quando
  /// tutti i ragazzi hanno riconsegnato il documento.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(documentsStreamProvider);
    final studentsAsync = ref.watch(myGroupStudentsProvider);

    return AppScaffold(
      title: 'Documenti',
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF174A7E),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () => _showCreateDocumentDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      child: docsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (documents) {
          if (documents.isEmpty) {
            return const Center(
              child: Text('Nessun documento. Premi + per aggiungerne uno.'),
            );
          }

          return studentsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Errore ragazzi: $e')),
            data: (myStudents) {
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: documents.length,
                itemBuilder: (context, index) {
                  final theme = Theme.of(context);
                  final isDark = theme.brightness == Brightness.dark;
                  final colorScheme = theme.colorScheme;
                  final doc = documents[index];
                  final docId = doc['id'].toString();
                  final deliveriesAsync = ref.watch(documentDeliveriesProvider(docId));

                  return deliveriesAsync.when(
                    loading: () => const SizedBox(height: 70),
                    error: (_, __) => const Text('Errore dati'),
                    data: (deliveries) {
                      // Calcolo dei mancanti focalizzato unicamente sulla classe del catechista
                      int mancanti = 0;
                      int esonerati = 0;
                      for (final student in myStudents) {
                        final d = deliveries[student.id];
                        if (d?['exoneratedAt'] != null) {
                          esonerati++;
                          continue;
                        }
                        if (d == null || d['receivedAt'] == null) {
                          mancanti++;
                        }
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark ? colorScheme.surfaceContainer : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: isDark
                                    ? Colors.black.withValues(alpha: 0.4)
                                    : Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF174A7E).withValues(alpha: 0.1),
                              child: const Icon(Icons.description, color: Color(0xFF174A7E)),
                            ),
                            title: Text(
                              doc['title']?.toString() ?? 'Documento',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              mancanti == 0
                                  ? (esonerati > 0 ? 'Completato ($esonerati esonerati)' : 'Completato')
                                  : '$mancanti mancanti${esonerati > 0 ? ', $esonerati esonerati' : ''}',
                              style: TextStyle(
                                color: mancanti == 0 ? Colors.green : Colors.orange.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                              trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded),
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  _showEditDocumentDialog(
                                    context,
                                    ref,
                                    docId,
                                    doc['title']?.toString() ?? '',
                                  );
                                } else if (value == 'delete') {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                      title: const Text(
                                        'Elimina Documento',
                                        style: TextStyle(color: Color(0xFF174A7E), fontWeight: FontWeight.bold),
                                      ),
                                      content: Text(
                                        'Eliminare "${doc['title']?.toString() ?? 'Documento'}"?\n'
                                        'Tutte le consegne associate verranno rimosse.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(false),
                                          child: const Text('Annulla'),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          onPressed: () => Navigator.of(ctx).pop(true),
                                          child: const Text('Elimina'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    await ref
                                        .read(documentsRepoProvider)
                                        .deleteDocument(docId);
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_rounded),
                                      SizedBox(width: 10),
                                      Text('Modifica nome'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_rounded),
                                      SizedBox(width: 10),
                                      Text('Elimina'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              context.push(
                                '/document-detail',
                                extra: {
                                  'document': doc,
                                  'students': myStudents,
                                },
                              );
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}


