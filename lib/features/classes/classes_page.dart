/// Schermata principale dell'elenco classi in CateREG.
///
/// Mostra tutte le classi (gruppi) di cui l'utente è catechista sotto forma di
/// schede (`_ClassCard`) con nome, numero di ragazzi e numero di catechisti.
/// Dalla pagina è possibile:
/// - Creare una nuova classe tramite il FAB "Nuova classe".
/// - Navigare al dettaglio classe toccando una scheda.
/// - Eliminare una classe (tramite menu a tre punti).
/// - Modificare il nome della classe (solo per il primo utente in modalità
///   "first user").
///
/// Integrazione CateREG: si aggancia a [classesStreamProvider] per ricevere
/// in tempo reale l'elenco aggiornato delle classi e a [classesRepoProvider]
/// per le operazioni di scrittura (add/delete/update).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_service.dart';
import '../../core/providers/current_class_provider.dart';
import '../../shared/utils/auth_utils.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/models/class_model.dart';
import 'classes_provider.dart';
import 'class_detail_page.dart';

class ClassesPage extends ConsumerWidget {
  const ClassesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(classesStreamProvider);

    return classesAsync.when(
      data: (classes) {
        final activeClassId = ref.watch(currentClassProvider) ?? '';

        return AppScaffold(
          title: 'Gruppi',
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: const Color(0xFF174A7E),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Nuova classe',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onPressed: () => _showAddClass(context, ref),
          ),
          child: classes.isEmpty
              ? const _EmptyState(
                  icon: Icons.groups_rounded,
                  title: 'Nessuna classe',
                  subtitle: 'Crea la prima classe per iniziare.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: classes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, index) {
                    final c = classes[index];
                    final isActive = c.id == activeClassId;

                    return _ClassCard(
                      name: c.name,
                      students: c.studentIds.length,
                      catechists: c.catechistIds.length,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClassDetailPage(classId: c.id),
                          ),
                        );
                      },
                      onDelete: () async {
                        try {
                          await ref.read(classesRepoProvider).deleteClass(c.id);
                          // Se si eliminava la classe aperta, pulisce la selezione
                          await clearCurrentClassIfDeleted(ref, c.id);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Errore durante l\'eliminazione: $e',
                                ),
                                backgroundColor: Colors.red.shade700,
                              ),
                            );
                          }
                        }
                      },
                      classId: c.id,
                      className: c.name,
                      nameLocked: c.nameLocked,
                      isActive: isActive,
                      canEdit:
                          c.isCreator(
                            AuthService.localUserId,
                            getCurrentCatechistName(),
                            catechistId: AuthService.getCatechistId(),
                          ) &&
                          (c.creatorCatechistId.isEmpty &&
                                  c.creatorId.isEmpty &&
                                  c.creatorName.isEmpty ||
                              !c.nameLocked),
                      onEditName:
                          c.isCreator(
                                AuthService.localUserId,
                                getCurrentCatechistName(),
                                catechistId: AuthService.getCatechistId(),
                              ) &&
                              (c.creatorCatechistId.isEmpty &&
                                      c.creatorId.isEmpty &&
                                      c.creatorName.isEmpty ||
                                  !c.nameLocked)
                          ? (newName) {
                              ref
                                  .read(classesRepoProvider)
                                  .updateClass(c.id, c.copyWith(name: newName));
                            }
                          : null,
                    );
                  },
                ),
        );
      },
      loading: () => const AppScaffold(
        title: 'Gruppi',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => AppScaffold(
        title: 'Gruppi',
        child: Center(child: Text('Errore: $e')),
      ),
    );
  }

  void _showAddClass(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Nuova classe'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nome classe'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF174A7E),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await ref
                  .read(classesRepoProvider)
                  .addClass(
                    SchoolClass(
                      id: '',
                      name: controller.text,
                      catechistIds: [],
                      studentIds: [],
                    ),
                  );

              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Crea'),
          ),
        ],
      ),
    );
  }
}

/// =========================
/// CLASS CARD
/// =========================
class _ClassCard extends StatelessWidget {
  final String name;
  final int students;
  final int catechists;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final String classId;
  final String className;
  final bool nameLocked;
  final bool isActive;
  final bool canEdit;
  final Function(String)? onEditName;

  const _ClassCard({
    required this.name,
    required this.students,
    required this.catechists,
    required this.onTap,
    this.onDelete,
    required this.classId,
    required this.className,
    this.nameLocked = false,
    this.isActive = false,
    this.canEdit = true,
    this.onEditName,
  });

  void _showEditNameDialog(BuildContext context) {
    final controller = TextEditingController(text: name);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Modifica nome gruppo'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nome gruppo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF174A7E),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (controller.text.isNotEmpty) {
                onEditName?.call(controller.text);
              }
              Navigator.pop(context);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Elimina gruppo'),
        content: Text(
          'Sei sicuro di voler eliminare "$name"?\n\n'
          'Verranno eliminati anche i piani di incontro e le presenze associati.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              onDelete?.call();
            },
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isActive
                ? [
                    Colors.blue.shade50,
                    Colors.blue.shade100.withValues(alpha: 0.4),
                  ]
                : [Colors.white, Colors.blue.shade50.withValues(alpha: 0.35)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isActive ? const Color(0xFF174A7E) : Colors.blue.shade100,
            width: isActive ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            /// ICON
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF174A7E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isActive ? Icons.star_rounded : Icons.groups_rounded,
                color: Colors.white,
              ),
            ),

            const SizedBox(width: 14),

            /// INFO
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF174A7E),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF174A7E),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Attiva',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      _Pill(icon: Icons.person, text: '$students ragazzi'),
                      const SizedBox(width: 8),
                      _Pill(icon: Icons.school, text: '$catechists catechisti'),
                    ],
                  ),
                ],
              ),
            ),

            /// MENU (solo per classi non attive)
            if (!isActive)
              PopupMenuButton<String>(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (value) {
                  if (value == 'edit') {
                    if (canEdit) {
                      _showEditNameDialog(context);
                    }
                  } else if (value == 'delete') {
                    _showDeleteConfirmation(context);
                  }
                },
                itemBuilder: (_) => [
                  if (canEdit && onEditName != null)
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Modifica nome'),
                    ),
                  if (onDelete != null)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Elimina'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// =========================
/// PILL
/// =========================
class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Pill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

/// =========================
/// EMPTY STATE
/// =========================
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: const Color(0xFF174A7E)),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}
