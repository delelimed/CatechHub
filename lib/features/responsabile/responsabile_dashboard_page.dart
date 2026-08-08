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

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Header(config: widget.config),
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
        'Giustificato' => Icons.event_available_rounded,
        _ => Icons.help_outline_rounded,
      };

  Color _statoColor(String stato) => switch (stato) {
        'Presente' => Colors.green,
        'Assente' => Colors.red,
        'Giustificato' => Colors.orange,
        _ => Colors.grey,
      };

  String _statoLabel(String stato) => switch (stato) {
        'Presente' => 'Ultima presenza: Presente',
        'Assente' => 'Ultima presenza: Assente',
        'Giustificato' => 'Ultima presenza: Giustificato',
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
          if (trailing != null) trailing!,
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