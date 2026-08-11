// ══════════════════════════════════════════════════════════════════════════════
// onboarding_classes_page.dart — CatechHub (gestione multiclasse nell'onboarding)
//
// Schermata dedicata della fase di onboarding per la gestione multiclasse.
// Viene mostrata al termine della prima configurazione (profilo + classe
// iniziale) oppure dopo essersi uniti a una classe esistente via P2P.
//
// Integra le funzioni già presenti nell'app per la gestione delle classi:
// - elenco di tutte le classi a cui appartiene il catechista (multiclasse);
// - selezione della classe corrente (funzione class selection/switcher);
// - creazione di nuove classi (funzione gruppo di group management);
// - unione a una classe esistente via QR/P2P (funzione onboarding-sync);
// - copia di contenuti da un'altra classe (funzione class-copy);
// - completamento dell'onboarding e accesso alla home.
//
// Quando l'utente preme "Vai alla home" il flag `onboarding_classes_completed`
// viene salvato, così il router smette di reindirizzare verso questa schermata.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/providers/current_class_provider.dart';
import '../../../../core/storage/local_database.dart';
import '../../../../features/classes/classes_provider.dart';
import '../../../../features/guide/demo_guide_service.dart';
import '../../../../shared/models/class_model.dart';
import '../../../../shared/utils/auth_utils.dart';

class OnboardingClassesPage extends ConsumerStatefulWidget {
  const OnboardingClassesPage({super.key});

  @override
  ConsumerState<OnboardingClassesPage> createState() =>
      _OnboardingClassesPageState();
}

class _OnboardingClassesPageState extends ConsumerState<OnboardingClassesPage> {
  bool _creating = false;
  bool _autoSelected = false;

  Future<void> _createClass() async {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? colorScheme.surface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Crea nuova classe'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nome della classe',
            hintText: 'Es. Prima elementare, Cresima 2026...',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isDark ? colorScheme.primary : const Color(0xFF174A7E),
              foregroundColor: isDark ? colorScheme.onPrimary : Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Crea'),
          ),
        ],
      ),
    );

    final trimmed = result?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;

    HapticFeedback.lightImpact();
    setState(() => _creating = true);
    try {
      final repo = ref.read(classesRepoProvider);
      final classId = LocalDatabase.newId('class');
      final fullName = getCurrentCatechistName();
      final newClass = SchoolClass(
        id: classId,
        name: trimmed,
        studentIds: const [],
        catechistIds: [AuthService.localUserId],
        lastModifiedBy: fullName,
        uniqueCode: generateClassUniqueCode(),
        nameLocked: false,
        creatorId: AuthService.localUserId,
        creatorName: fullName,
        creatorCatechistId: AuthService.getCatechistId(),
        catechistDeviceCounts: {AuthService.getCatechistId(): 1},
      );
      await repo.addClass(newClass);

      if (ref.read(currentClassProvider) == null) {
        await ref.read(currentClassProvider.notifier).setClass(classId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Classe "$trimmed" creata.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante la creazione: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _selectClass(String classId) async {
    HapticFeedback.lightImpact();
    await ref.read(currentClassProvider.notifier).setClass(classId);
  }

  Future<void> _completeOnboarding() async {
    if (ref.read(currentClassProvider) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleziona o crea una classe per continuare.'),
        ),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    await LocalDatabase.auth().put('onboarding_classes_completed', true);
    await DemoGuideService.scheduleGuide();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final myClasses = ref.watch(myClassesProvider);
    final currentClassId = ref.watch(currentClassProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final hasSelection = currentClassId != null;

    // Robustezza: se l'utente non ha ancora una classe selezionata (es. si è
    // unito a una classe via P2P senza selezione esplicita), seleziona
    // automaticamente la prima disponibile. In questo modo l'utente non resta
    // mai bloccato senza una classe corrente.
    ref.listen(myClassesProvider, (previous, next) {
      if (_autoSelected) return;
      if (next.isEmpty || ref.read(currentClassProvider) != null) return;
      _autoSelected = true;
      final first = next.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(currentClassProvider.notifier).setClass(first.id);
        }
      });
    });

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(isDark),
                    const SizedBox(height: 28),
                    _buildClassesSection(
                      myClasses,
                      currentClassId,
                      isDark,
                      colorScheme,
                    ),
                    const SizedBox(height: 24),
                    _buildActions(isDark, colorScheme),
                    const SizedBox(height: 28),
                    _buildFinishButton(isDark, colorScheme, hasSelection),
                    const SizedBox(height: 12),
                    if (myClasses.isNotEmpty && !hasSelection)
                      Center(
                        child: Text(
                          'Tocca una classe per selezionarla come predefinita.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── HEADER ─────────────────────────────────────────────────────────

  Widget _buildHeader(bool isDark) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF174A7E).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(
            Icons.groups_rounded,
            size: 40,
            color: Color(0xFF174A7E),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Le tue classi',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Color(0xFF174A7E),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Gestisci più classi di catechismo: crea nuovi gruppi, unisciti '
          'a quelli esistenti o copia i contenuti da un\'altra classe.\n'
          'Potrai sempre gestirli in seguito dalle Impostazioni.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // ─── ELENCO CLASSI ──────────────────────────────────────────────────

  Widget _buildClassesSection(
    List<SchoolClass> classes,
    String? currentClassId,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    if (classes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? colorScheme.surfaceContainer : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? colorScheme.outline.withValues(alpha: 0.2)
                : Colors.blue.shade100,
          ),
        ),
        child: Column(
          children: [
            Icon(Icons.groups_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Non fai ancora parte di nessuna classe.\n'
              'Crea un nuovo gruppo o unisciti a uno esistente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LE TUE CLASSI (${classes.length})',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 12),
        ...classes.map(
          (c) => _ClassCard(
            schoolClass: c,
            isSelected: c.id == currentClassId,
            isDark: isDark,
            colorScheme: colorScheme,
            onTap: () => _selectClass(c.id),
          ),
        ),
      ],
    );
  }

  // ─── AZIONI ─────────────────────────────────────────────────────────

  Widget _buildActions(bool isDark, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActionButton(
          icon: Icons.add_circle_outline_rounded,
          label: 'Crea nuova classe',
          description: 'Aggiungi un altro gruppo di catechismo',
          filled: true,
          isDark: isDark,
          colorScheme: colorScheme,
          loading: _creating,
          onTap: _createClass,
        ),
        const SizedBox(height: 10),
        _ActionButton(
          icon: Icons.qr_code_scanner_rounded,
          label: 'Unisciti a una classe esistente',
          description: 'Sincronizzati con un altro catechista (QR / Bluetooth)',
          filled: false,
          isDark: isDark,
          colorScheme: colorScheme,
          onTap: () => context.push('/onboarding-sync'),
        ),
        const SizedBox(height: 10),
        _ActionButton(
          icon: Icons.content_copy_rounded,
          label: 'Copia contenuti da un\'altra classe',
          description: 'Documenti, calendario, incontri e catechesi',
          filled: false,
          isDark: isDark,
          colorScheme: colorScheme,
          onTap: () => context.push('/settings/class-copy'),
        ),
      ],
    );
  }

  // ─── BOTTONI FINALI ─────────────────────────────────────────────────

  Widget _buildFinishButton(
    bool isDark,
    ColorScheme colorScheme,
    bool hasSelection,
  ) {
    final primaryColor = isDark ? colorScheme.primary : const Color(0xFF174A7E);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: hasSelection ? _completeOnboarding : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: isDark ? colorScheme.onPrimary : Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.grey.shade500,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
            ),
            child: const Text(
              'Vai alla home',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── CARD CLASSE ─────────────────────────────────────────────────────────────

class _ClassCard extends StatelessWidget {
  final SchoolClass schoolClass;
  final bool isSelected;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _ClassCard({
    required this.schoolClass,
    required this.isSelected,
    required this.isDark,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = isDark ? colorScheme.primary : const Color(0xFF174A7E);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.08)
              : (isDark ? colorScheme.surfaceContainer : Colors.white),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? primaryColor
                : (isDark
                    ? colorScheme.outline.withValues(alpha: 0.2)
                    : Colors.blue.shade100),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected ? primaryColor : primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.groups_rounded,
                color: isSelected ? Colors.white : primaryColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schoolClass.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? colorScheme.onSurface : const Color(0xFF174A7E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${schoolClass.studentIds.length} ragazzi · '
                    '${schoolClass.catechistIds.length} catechist${schoolClass.catechistIds.length == 1 ? 'a' : 'i'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: primaryColor, size: 24)
            else
              Icon(
                Icons.radio_button_unchecked_rounded,
                color: Colors.grey.shade400,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}

// ─── BOTTONE AZIONE ──────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool filled;
  final bool isDark;
  final ColorScheme colorScheme;
  final bool loading;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.filled,
    required this.isDark,
    required this.colorScheme,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = isDark ? colorScheme.primary : const Color(0xFF174A7E);

    final content = Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: filled
                ? Colors.white.withValues(alpha: 0.2)
                : primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: filled ? Colors.white : primaryColor,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: filled ? Colors.white : (isDark ? colorScheme.onSurface : const Color(0xFF174A7E)),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11,
                  color: filled
                      ? Colors.white.withValues(alpha: 0.85)
                      : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
        if (loading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: filled ? Colors.white : primaryColor,
            ),
          )
        else
          Icon(
            Icons.chevron_right_rounded,
            color: filled ? Colors.white.withValues(alpha: 0.85) : Colors.grey.shade400,
          ),
      ],
    );

    if (filled) {
      return SizedBox(
        height: 64,
        child: ElevatedButton(
          onPressed: loading ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: content,
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: loading ? null : onTap,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? colorScheme.surfaceContainer : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? colorScheme.outline.withValues(alpha: 0.2)
                  : Colors.blue.shade100,
            ),
          ),
          child: content,
        ),
    );
  }
}
