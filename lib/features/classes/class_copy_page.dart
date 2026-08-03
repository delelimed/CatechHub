import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/current_class_provider.dart';
import '../../shared/models/class_model.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'class_copy_service.dart';

/// Pagina per copiare contenuti (documenti, catechesi, messaggi programmati,
/// calendario) da un'altra classe alla classe corrente.
///
/// NON copia le associazioni ai ragazzi (consegne documenti, registro
/// presenze): i contenuti vengono ricreati per la classe corrente.
class ClassCopyPage extends ConsumerStatefulWidget {
  const ClassCopyPage({super.key});

  @override
  ConsumerState<ClassCopyPage> createState() => _ClassCopyPageState();
}

class _ClassCopyPageState extends ConsumerState<ClassCopyPage> {
  bool _includeDocuments = true;
  bool _includeCatechesi = true;
  bool _includeAvvisi = true;
  bool _includeCalendar = true;
  bool _isCopying = false;

  Future<void> _performCopy({
    required SchoolClass source,
    required SchoolClass target,
  }) async {
    final anySelected =
        _includeDocuments || _includeCatechesi || _includeAvvisi || _includeCalendar;
    if (!anySelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleziona almeno un tipo di contenuto da copiare.'),
        ),
      );
      return;
    }

    setState(() => _isCopying = true);
    try {
      final result = await ClassCopyService.copyContent(
        sourceClass: source,
        targetClass: target,
        includeDocuments: _includeDocuments,
        includeCatechesi: _includeCatechesi,
        includeAvvisi: _includeAvvisi,
        includeCalendar: _includeCalendar,
      );
      if (!mounted) return;
      final items = <String>[
        if (_includeDocuments) '${result.documents} documenti',
        if (_includeCatechesi) '${result.catechesi} catechesi',
        if (_includeAvvisi) '${result.avvisi} messaggi programmati',
        if (_includeCalendar) '${result.meetings} incontri',
      ].where((s) => !s.startsWith('0 ')).toList();

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Copia completata'),
          content: items.isEmpty
              ? const Text('Nessun contenuto è stato copiato.')
              : Text(
                  'I seguenti contenuti di "${source.name}" sono stati aggiunti a "${target.name}":\n\n• ${items.join('\n• ')}',
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante la copia: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCopying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myClasses = ref.watch(myClassesProvider);
    final currentClassId = ref.watch(currentClassProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    SchoolClass? currentClass;
    for (final c in myClasses) {
      if (c.id == currentClassId) currentClass = c;
    }
    final sourceClasses =
        myClasses.where((c) => c.id != currentClassId).toList();

    return AppScaffold(
      title: 'Copia da altra classe',
      child: Builder(
        builder: (context) {
          if (currentClass == null) {
            return const Center(
              child: Text('Seleziona prima una classe dalle impostazioni.'),
            );
          }

          if (sourceClasses.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Non ci sono altre classi da cui copiare.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InfoCard(
                icon: Icons.copy_all_rounded,
                title: 'Copia contenuti nella classe corrente',
                subtitle:
                    'Copia documenti, catechesi, messaggi programmati e calendario da un\'altra classe. Le associazioni ai ragazzi (consegne, presenze) NON vengono copiate.',
                isDark: isDark,
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 16),
              Text(
                'Classe corrente: ${currentClass.name}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
                ),
              ),
              const SizedBox(height: 16),
              _SourceSelector(
                sourceClasses: sourceClasses,
                isCopying: _isCopying,
                onCopy: (source) => _performCopy(
                  source: source,
                  target: currentClass!,
                ),
              ),
              const SizedBox(height: 20),
              _SectionTitle(
                title: 'Contenuti da copiare',
                isDark: isDark,
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 8),
              _ModuleToggle(
                label: 'Documenti',
                subtitle: 'Certificati, autorizzazioni, consegne',
                icon: Icons.description_rounded,
                value: _includeDocuments,
                isDark: isDark,
                onChanged: (v) => setState(() => _includeDocuments = v),
              ),
              _ModuleToggle(
                label: 'Catechesi',
                subtitle: 'Argomenti e contenuti delle catechesi',
                icon: Icons.menu_book_rounded,
                value: _includeCatechesi,
                isDark: isDark,
                onChanged: (v) => setState(() => _includeCatechesi = v),
              ),
              _ModuleToggle(
                label: 'Messaggi programmati',
                subtitle: 'Avvisi e comunicazioni ai genitori',
                icon: Icons.mail_outline_rounded,
                value: _includeAvvisi,
                isDark: isDark,
                onChanged: (v) => setState(() => _includeAvvisi = v),
              ),
              _ModuleToggle(
                label: 'Calendario',
                subtitle: 'Incontri e programmazione',
                icon: Icons.calendar_month_rounded,
                value: _includeCalendar,
                isDark: isDark,
                onChanged: (v) => setState(() => _includeCalendar = v),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// ─── WIDGET SUPPORT ─────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final ColorScheme colorScheme;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.primary.withValues(alpha: 0.12)
            : const Color(0xFF174A7E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? colorScheme.primary.withValues(alpha: 0.4)
              : const Color(0xFF174A7E).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              color: isDark ? colorScheme.primary : const Color(0xFF174A7E)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? colorScheme.onSurface : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: isDark
                        ? Colors.grey.shade400
                        : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceSelector extends StatelessWidget {
  final List<SchoolClass> sourceClasses;
  final bool isCopying;
  final void Function(SchoolClass) onCopy;

  const _SourceSelector({
    required this.sourceClasses,
    required this.isCopying,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Scegli la classe da cui copiare',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        ...sourceClasses.map((c) => _SourceCard(
          schoolClass: c,
          isCopying: isCopying,
          onTap: () => onCopy(c),
        )),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  final SchoolClass schoolClass;
  final bool isCopying;
  final VoidCallback onTap;

  const _SourceCard({
    required this.schoolClass,
    required this.isCopying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: isCopying ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blue.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF174A7E).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.content_copy_rounded,
                  color: Color(0xFF174A7E)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schoolClass.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF174A7E),
                    ),
                  ),
                  Text(
                    '${schoolClass.studentIds.length} ragazzi',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (isCopying)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFF174A7E)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;
  final ColorScheme colorScheme;

  const _SectionTitle({
    required this.title,
    required this.isDark,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: isDark ? colorScheme.onSurface : Colors.grey.shade800,
          ),
        ),
      ],
    );
  }
}

class _ModuleToggle extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool value;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const _ModuleToggle({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        ),
      ),
      value: value,
      onChanged: (v) => onChanged(v),
    );
  }
}