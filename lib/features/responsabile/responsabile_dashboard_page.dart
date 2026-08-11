// ══════════════════════════════════════════════════════════════════════════════
// responsabile_dashboard_page.dart — CatechHub (vista albero parrocchiale)
//
// Dashboard principale del Responsabile Catechistico. Mostra la gerarchia
// parrocchiale a 4 livelli espandibili:
//   L1 Anno catechistico → Percorsi/Gruppi (es. Prima Comunione, Cresima)
//   L2 Classi/Sezioni      (es. Comunione A, Comunione B)
//   L3 Catechisti assegnati (Titolare / Co-titolo/Aiuto)
//   L4 Ragazzi iscritti     (indicatore visivo stato presenze)
//
// Accede solo se la modalità Responsabile è attiva (ParishConfig).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_service.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/aula.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/parish_config.dart';
import '../../shared/models/student_model.dart';
import '../../shared/models/user_role.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../classes/classes_repository.dart';
import 'responsabile_providers.dart';

/// Pagina della vista gerarchica parrocchiale.
class ResponsabileDashboardPage extends ConsumerWidget {
  const ResponsabileDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configRepo = ref.watch(parishConfigRepositoryProvider);
    final config = configRepo.getConfig();

    if (!UserRole.isResponsabile || !config.isResponsabileModeActive) {
      return const _AccessDenied();
    }

    final classesAsync = ref.watch(parrocchiaClassesProvider);
    final studentsAsync = ref.watch(parrocchiaStudentsProvider);
    final presenzeAsync = ref.watch(presenzePerClasseProvider);
    final aulasAsync = ref.watch(aulasStreamProvider);

    return AppScaffold(
      title: 'Parrocchia',
      child: aulasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore caricamento aule: $e')),
        data: (aulas) => classesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Errore caricamento classi: $e')),
          data: (classes) => studentsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Errore caricamento studenti: $e')),
            data: (students) => presenzeAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Errore caricamento presenze: $e')),
              data: (presenze) {
                final studentsById = {for (final s in students) s.id: s};
                return _ParishTree(
                  config: config,
                  classes: classes.where((c) => !c.archived).toList(),
                  studentsById: studentsById,
                  presenzePerClasse: presenze,
                  aulas: aulas,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Parrocchia',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings_outlined,
                  size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Accesso riservato',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'La vista parrocchiale è disponibile solo al Responsabile '
                'Catechistico con modalità attiva.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/settings'),
                icon: const Icon(Icons.settings),
                label: const Text('Vai alle impostazioni'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stato interno di espansione dei nodi (percorsi/classi).
class _ParishTree extends StatefulWidget {
  final ParishConfig config;
  final List<SchoolClass> classes;
  final Map<String, Student> studentsById;
  final Map<String, List<Map<String, dynamic>>> presenzePerClasse;
  final List<Aula> aulas;

  const _ParishTree({
    required this.config,
    required this.classes,
    required this.studentsById,
    required this.presenzePerClasse,
    required this.aulas,
  });

  @override
  State<_ParishTree> createState() => _ParishTreeState();
}

class _ParishTreeState extends State<_ParishTree> {
  /// Anno catechistico espanso (livello 1).
  bool _annoEspanso = true;

  /// Percorsi espansi per livello 2 (chiave = percorso).
  final Set<String> _expandedPercorsi = {};

  /// Classi espanne per livello 3 (chiave = classId).
  final Set<String> _expandedClassi = {};

  @override
  Widget build(BuildContext context) {
    final percorsi = widget.classes.map((c) => c.percorso).toSet().toList()
      ..sort();

    final nClassi = widget.classes.length;
    final nRagazzi = widget.classes
        .fold<int>(0, (sum, c) => sum + c.studentIds.length);
    final nCatechisti = widget.classes
        .fold<int>(0, (sum, c) => sum + c.catechistIds.length);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Header(config: widget.config),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.groups_rounded,
                label: 'Classi',
                value: nClassi,
                color: const Color(0xFF174A7E),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.person_rounded,
                label: 'Ragazzi',
                value: nRagazzi,
                color: const Color(0xFF2E7D32),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.school_rounded,
                label: 'Catechisti',
                value: nCatechisti,
                color: const Color(0xFFB34700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Funzioni rapide',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF174A7E),
              ),
        ),
        const SizedBox(height: 12),
        _QuickActions(),
        const SizedBox(height: 16),
        Text(
          'Albero parrocchiale',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF174A7E),
              ),
        ),
        const SizedBox(height: 12),
        if (percorsi.isEmpty)
          const _EmptyState()
        else
          _buildAnno(context, percorsi),
      ],
    );
  }

  /// Livello 1 — Anno Catechistico: radice dell'albero gerarchico.
  Widget _buildAnno(BuildContext context, List<String> percorsi) {
    final nClassi =
        widget.classes.fold<int>(0, (sum, c) => sum + (percorsi.contains(c.percorso) ? 1 : 0));
    final nRagazzi = widget.classes.fold<int>(
        0, (sum, c) => sum + (percorsi.contains(c.percorso) ? c.studentIds.length : 0));
    final nCatechisti = widget.classes.fold<int>(
        0, (sum, c) => sum + (percorsi.contains(c.percorso) ? c.catechistIds.length : 0));

    return _TreeCard(
      key: const ValueKey('anno_catechistico'),
      leading: _LevelBadge(
        level: 1,
        color: const Color(0xFF174A7E),
        icon: Icons.calendar_month_rounded,
      ),
      title: widget.config.annoLabel == 'Anno catechistico non impostato'
          ? 'Anno catechistico'
          : widget.config.annoLabel,
      subtitle:
          '${percorsi.length} percorsi · $nClassi classi · $nRagazzi ragazzi · $nCatechisti catechisti',
      onTap: () => setState(() => _annoEspanso = !_annoEspanso),
      trailing: Icon(_annoEspanso
          ? Icons.expand_less_rounded
          : Icons.expand_more_rounded),
      children: _annoEspanso
          ? [
              ...percorsi.map(
                (percorso) => _buildPercorso(context, percorso),
              ),
            ]
          : null,
    );
  }

  /// Livello 2 — Percorso/Gruppo (es. Prima Comunione, Cresima).
  Widget _buildPercorso(BuildContext context, String percorso) {
    final percorsoClasses =
        widget.classes.where((c) => c.percorso == percorso).toList();
    final isExpanded = _expandedPercorsi.contains(percorso);
    final nRagazzi = percorsoClasses
        .fold<int>(0, (sum, c) => sum + c.studentIds.length);
    final nCatechisti = percorsoClasses.fold<int>(
      0,
      (sum, c) => sum + c.catechistIds.length,
    );

    return _TreeCard(
      key: ValueKey('percorso_$percorso'),
      indent: true,
      leading: _LevelBadge(
        level: 2,
        color: const Color(0xFF174A7E),
        icon: Icons.route_outlined,
      ),
      title: percorso.isEmpty ? 'Senza percorso' : percorso,
      subtitle: '$nRagazzi ragazzi · $nCatechisti catechisti',
      onTap: () => setState(() {
        if (isExpanded) {
          _expandedPercorsi.remove(percorso);
        } else {
          _expandedPercorsi.add(percorso);
        }
      }),
      trailing: Icon(isExpanded
          ? Icons.expand_less_rounded
          : Icons.expand_more_rounded),
      children: isExpanded
          ? [
              if (percorsoClasses.isEmpty)
                const _HintText('Nessuna classe in questo percorso.')
              else
                ...percorsoClasses.map((c) => _buildClasse(context, c)),
            ]
          : null,
    );
  }

  /// Livello 3 — Classe/Sezione (es. Comunione A, Comunione B).
  Widget _buildClasse(BuildContext context, SchoolClass cls) {
    final isExpanded = _expandedClassi.contains(cls.id);
    final classRecords = widget.presenzePerClasse[cls.id] ?? [];
    final presenceRate = _presenceRate(classRecords);

    return _TreeCard(
      key: ValueKey('classe_${cls.id}'),
      indent: true,
      leading: _LevelBadge(
        level: 3,
        color: const Color(0xFF2E7D32),
        icon: Icons.groups_rounded,
      ),
      title: cls.name,
      subtitle:
          '${cls.studentIds.length} ragazzi · Liv. ${cls.livello} · presenze ${presenceRate.toStringAsFixed(0)}%',
      onTap: () => setState(() {
        if (isExpanded) {
          _expandedClassi.remove(cls.id);
        } else {
          _expandedClassi.add(cls.id);
        }
      }),
      trailing: Icon(isExpanded
          ? Icons.expand_less_rounded
          : Icons.expand_more_rounded),
      children: isExpanded
          ? [
              _buildCatechisti(context, cls),
              const Divider(height: 20),
              _buildRagazzi(context, cls),
            ]
          : null,
    );
  }

  /// Livello 4 — Catechisti assegnati (Titolare / Co-titolo).
  Widget _buildCatechisti(BuildContext context, SchoolClass cls) {
    final roleRepo = ClassesRepository();
    final catechisti = <Widget>[];
    for (final catId in cls.catechistIds) {
      final role = roleRepo.roleOf(cls, catId);
      final name = _catechistName(cls, catId);
      final isTitolare = role == ClassesRepository.roleTitolare;
      catechisti.add(
        _TreeCard(
          indent: true,
          leading: _LevelBadge(
            level: 4,
            color: isTitolare ? const Color(0xFFB34700) : const Color(0xFF6A4FA3),
            icon: isTitolare ? Icons.star_rounded : Icons.person_rounded,
          ),
          title: name,
          subtitle: isTitolare ? 'Titolare' : 'Co-titolo / Aiuto',
          dense: true,
        ),
      );
    }
    if (catechisti.isEmpty) {
      catechisti.add(const _HintText('Nessun catechista assegnato.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SubHeader('Catechisti assegnati'),
        const SizedBox(height: 6),
        ...catechisti,
      ],
    );
  }

  Widget _buildRagazzi(BuildContext context, SchoolClass cls) {
    final ragazzi = <Widget>[];
    final studenti = cls.studentIds
        .map((id) => widget.studentsById[id])
        .whereType<Student>()
        .toList()
      ..sort(Student.compareBySurname);

    if (studenti.isEmpty) {
      ragazzi.add(const _HintText('Nessun ragazzo iscritto.'));
    }
    for (final student in studenti) {
      final stato = _statoPresenza(student.id, cls.id);
      ragazzi.add(
        _TreeCard(
          indent: true,
          leading: _LevelBadge(
            level: 5,
            color: _statoColor(stato),
            icon: _statoIcon(stato),
          ),
          title: '${student.name} ${student.surname}'.trim(),
          subtitle: _statoLabel(stato),
          dense: true,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SubHeader('Ragazzi iscritti'),
        const SizedBox(height: 6),
        ...ragazzi,
      ],
    );
  }

  String _statoPresenza(String studentId, String classId) {
    final records = widget.presenzePerClasse[classId] ?? [];
    // Ultima presenza nota del ragazzo.
    for (var i = records.length - 1; i >= 0; i--) {
      final presence = Map<String, dynamic>.from(
        records[i]['presence'] as Map? ?? {},
      );
      final stato = presence[studentId]?.toString();
      if (stato != null) return stato;
    }
    return 'NC';
  }

  double _presenceRate(List<Map<String, dynamic>> records) {
    var presenze = 0;
    var assenze = 0;
    for (final r in records) {
      final presence = Map<String, dynamic>.from(r['presence'] as Map? ?? {});
      for (final value in presence.values) {
        if (value == 'Presente') presenze++;
        if (value == 'Assente') assenze++;
      }
    }
    final total = presenze + assenze;
    if (total == 0) return 0;
    return presenze / total * 100;
  }

  String _catechistName(SchoolClass cls, String catechistId) {
    // Il catechista locale è noto; gli altri ID sono hashe: mostriamo
    // un'etichetta generica derivata dalla fine dell'ID.
    if (catechistId == AuthService.localUserId) {
      try {
        final name =
            LocalDatabaseCache.localUserName;
        if (name.isNotEmpty) return name;
      } catch (_) {}
      return 'Catechista locale';
    }
    return 'Catechista (${catechistId.length > 6 ? catechistId.substring(catechistId.length - 6) : catechistId})';
  }

  IconData _statoIcon(String stato) => switch (stato) {
        'Presente' => Icons.check_circle_rounded,
        'Assente' => Icons.cancel_rounded,
        _ => Icons.help_outline_rounded,
      };

  Color _statoColor(String stato) => switch (stato) {
        'Presente' => Colors.green,
        'Assente' => Colors.red,
        _ => Colors.grey,
      };

  String _statoLabel(String stato) => switch (stato) {
        'Presente' => 'Ultima presenza: Presente',
        'Assente' => 'Ultima presenza: Assente',
        _ => 'Nessuna presenza registrata',
      };
}

/// Cache di lettura del nome utente locale (evita dipendenza da AuthService).
class LocalDatabaseCache {
  static String get localUserName {
    try {
      return LocalDatabase.auth().get('local_user_name', defaultValue: '')
          as String? ??
          '';
    } catch (_) {
      return '';
    }
  }
}

class _Header extends StatelessWidget {
  final ParishConfig config;

  const _Header({required this.config});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF174A7E), Color(0xFF2368B1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.church_rounded, color: Colors.white, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.nomeParrocchia.trim().isEmpty
                      ? 'Parrocchia'
                      : config.nomeParrocchia.trim(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                if (config.diocesi.trim().isNotEmpty)
                  Text(
                    config.diocesi.trim(),
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Anno ${config.annoLabel}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
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

class _TreeCard extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final List<Widget>? children;
  final bool indent;
  final bool dense;

  const _TreeCard({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.children,
    this.indent = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget card = Container(
      margin: EdgeInsets.only(left: indent ? 20 : 0, bottom: 8),
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: dense ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainer
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? theme.colorScheme.outline.withValues(alpha: 0.2)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: dense ? 13 : 15,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDark ? Colors.grey.shade400 : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );

    if (onTap != null) {
      card = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: card,
      );
    }

    if (children == null) return card;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [card, ...children!],
    );
  }
}

class _LevelBadge extends StatelessWidget {
  final int level;
  final Color color;
  final IconData icon;

  const _LevelBadge({
    required this.level,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.25 : 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _SubHeader extends StatelessWidget {
  final String text;

  const _SubHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _HintText extends StatelessWidget {
  final String text;

  const _HintText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey.shade400
              : Colors.black54,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Column(
        children: [
          Icon(Icons.account_tree_outlined, size: 44, color: Colors.grey),
          SizedBox(height: 12),
          Text(
            'Nessuna classe ancora presente. Configura la parrocchia e '
            'crea i percorsi dalla gestione amministrativa.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Card con un dato statistico riassuntivo della parrocchia.
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainer
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)
              : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.25 : 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 10),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark
                  ? Theme.of(context).colorScheme.onSurface
                  : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Griglia di accesso rapido alle funzioni amministrative del Responsabile.
class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickActionData(
        icon: Icons.groups_rounded,
        label: 'Classi',
        subtitle: 'Crea classi e assegna i catechisti',
        color: const Color(0xFF174A7E),
        route: '/parrocchia/classi',
      ),
      _QuickActionData(
        icon: Icons.person_add_alt_1_rounded,
        label: 'Catechisti',
        subtitle: 'Rubrica, telefono, classi e dispositivi',
        color: const Color(0xFF2E7D32),
        route: '/parrocchia/catechisti',
      ),
      _QuickActionData(
        icon: Icons.admin_panel_settings_rounded,
        label: 'Amministrazione',
        subtitle: 'Hub completo della parrocchia',
        color: const Color(0xFFB34700),
        route: '/parrocchia/admin',
      ),
      _QuickActionData(
        icon: Icons.network_check_rounded,
        label: 'Rete parrocchiale',
        subtitle: 'Riunioni, avvisi, titoli',
        color: const Color(0xFF6A4FA3),
        route: '/parrocchia/rete',
      ),
      _QuickActionData(
        icon: Icons.task_alt_rounded,
        label: 'Consensi',
        subtitle: 'Schede iscrizione firmate',
        color: const Color(0xFF00838F),
        route: '/parrocchia/consensi',
      ),
      _QuickActionData(
        icon: Icons.gavel_rounded,
        label: 'Registro trattamenti',
        subtitle: 'Log GDPR (Art. 30)',
        color: const Color(0xFFC62828),
        route: '/parrocchia/audit',
      ),
      _QuickActionData(
        icon: Icons.history_rounded,
        label: 'Archivio storico',
        subtitle: 'Progresso e chiusura anno',
        color: const Color(0xFFAD7F00),
        route: '/parrocchia/archivio',
      ),
      _QuickActionData(
        icon: Icons.upload_file_rounded,
        label: 'Importa ragazzi',
        subtitle: 'Da Excel o CSV',
        color: const Color(0xFF7B1FA2),
        route: '/parrocchia/import-ragazzi',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 600 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 116,
          ),
          itemCount: actions.length,
          itemBuilder: (context, index) {
            final a = actions[index];
            return _QuickActionCard(data: a);
          },
        );
      },
    );
  }
}

class _QuickActionData {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final String route;

  const _QuickActionData({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.route,
  });
}

class _QuickActionCard extends StatelessWidget {
  final _QuickActionData data;

  const _QuickActionCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push(data.route),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark
              ? Theme.of(context).colorScheme.surfaceContainer
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark
                ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)
                : Colors.grey.shade200,
          ),
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
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: data.color.withValues(alpha: isDark ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(data.icon, color: data.color, size: 22),
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? Theme.of(context).colorScheme.onSurface
                    : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              data.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}