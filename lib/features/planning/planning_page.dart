import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_service.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/models/planning_meeting.dart';
import '../classes/classes_provider.dart';
import 'planning_provider.dart';
import 'planning_edit_page.dart';

class PlanningPage extends ConsumerStatefulWidget {
  const PlanningPage({super.key});

  @override
  ConsumerState<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends ConsumerState<PlanningPage> {
  bool _showPast = false;
  final _scrollController = ScrollController();
  final _monthKeys = <String, GlobalKey>{};

  GlobalKey _getMonthKey(String monthKey) {
    return _monthKeys.putIfAbsent(monthKey, () => GlobalKey());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToMonth(String monthKey) {
    final globalKey = _monthKeys[monthKey];
    final context = globalKey?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(planningRepoProvider);
    final classesAsync = ref.watch(classesStreamProvider);

    const uid = AuthService.localUserId;
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Programmazione',

      floatingActionButton: FloatingActionButton.extended(
        elevation: 4,
        backgroundColor: const Color(0xFF174A7E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Aggiungi',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        onPressed: () => _showAddMenu(context),
      ),

      child: classesAsync.when(
        data: (classes) {
          final myClass = classes.where(
            (c) => c.catechistIds.contains(uid),
          );

          if (myClass.isEmpty) {
            return _EmptyState(
              icon: Icons.groups_rounded,
              title: 'Nessuna classe assegnata',
              subtitle: 'Non risulti ancora assegnato ad un gruppo di catechismo.',
            );
          }

          final classId = myClass.first.id;

          return StreamBuilder<List<PlanningMeeting>>(
            stream: repo.getMeetings(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);

              var meetings = snapshot.data!
                  .where((m) => m.classId == classId)
                  .toList();

              if (_showPast) {
                meetings = meetings.where((m) => m.date.isBefore(today)).toList();
                meetings.sort((a, b) => b.date.compareTo(a.date));
              } else {
                meetings = meetings.where((m) => !m.date.isBefore(today)).toList();
                meetings.sort((a, b) => a.date.compareTo(b.date));
              }

              final groupedMeetings = <String, List<PlanningMeeting>>{};
              final monthKeys = <String>[];
              for (final m in meetings) {
                final key = DateFormat('MMMM yyyy', 'it_IT').format(m.date);
                if (!groupedMeetings.containsKey(key)) {
                  groupedMeetings[key] = [];
                  monthKeys.add(key);
                }
                groupedMeetings[key]!.add(m);
              }

              // Pre-registra tutte le GlobalKey per i mesi PRIMA di costruire i chip,
              // così _scrollToMonth trova sempre il context anche per i mesi non ancora renderizzati.
              for (final mk in monthKeys) {
                _getMonthKey(mk);
              }

              return ListView(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 100),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _CatechesiBanner(
                      onTap: () => context.push('/catechesi'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _ToggleChip(
                          label: _showPast ? 'Prossimi' : 'Passati',
                          icon: _showPast ? Icons.upcoming_rounded : Icons.history_rounded,
                          onTap: () {
                            setState(() => _showPast = !_showPast);
                          },
                        ),
                        if (monthKeys.isNotEmpty)
                          const SizedBox(width: 8),
                        ...monthKeys.map((mk) => _MonthChip(
                          label: mk[0].toUpperCase() + mk.substring(1),
                          onTap: () => _scrollToMonth(mk),
                        )),
                      ],
                    ),
                  ),
                  if (meetings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
                      child: Center(
                        child: Text(
                          _showPast ? 'Nessun incontro passato' : 'Nessun prossimo incontro',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                        ),
                      ),
                    ),
                  ...monthKeys.map((monthKey) {
                    final monthMeetings = groupedMeetings[monthKey]!;
                    return Column(
                      key: _getMonthKey(monthKey),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                          child: Row(
                            children: [
                              Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF174A7E).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.calendar_month_rounded, size: 16, color: const Color(0xFF174A7E)),
                                    const SizedBox(width: 6),
                                    Text(
                                      monthKey[0].toUpperCase() + monthKey.substring(1),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF174A7E),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...monthMeetings.map((m) {
                          final isReunion = m.isReunion;
                          final accentColor =
                              isReunion ? Colors.deepPurple : const Color(0xFF174A7E);

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PlanningEditPage(existing: m),
                                  ),
                                );
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white,
                                      Colors.blue.shade50.withValues(alpha: 0.35),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.blue.shade100,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 16,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 56,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: accentColor,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            DateFormat('dd').format(m.date),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            DateFormat('MMM', 'it_IT').format(m.date).toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 10,
                                            ),
                                          ),
                                          if (isReunion && m.time != null && m.time!.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              m.time!,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            m.title,
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: accentColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert_rounded),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      onSelected: (v) async {
                                        if (v == 'delete') {
                                          await repo.deleteMeeting(m.id);
                                        }
                                        if (v == 'edit') {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => PlanningEditPage(existing: m),
                                            ),
                                          );
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit_rounded),
                                              SizedBox(width: 10),
                                              Text('Modifica'),
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
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    );
                  }),
                ],
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (e, _) => Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Errore: $e',
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.event_rounded,
                color: Color(0xFF174A7E),
              ),
              title: const Text('Nuova giornata'),
              subtitle: const Text('Con appello presenze dei ragazzi'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PlanningEditPage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.groups_rounded,
                color: Colors.deepPurple.shade700,
              ),
              title: const Text('Nuova riunione'),
              subtitle: const Text('Solo programmazione, senza appello'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PlanningEditPage(isReunion: true),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF174A7E),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _MonthChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

class _CatechesiBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _CatechesiBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF174A7E),
              Color(0xFF2A6BB0),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Catechesi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Gestisci le tue raccolte di catechesi',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Apri',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
              width: 95,
              height: 95,
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 46,
                color: const Color(0xFF174A7E),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey.shade700,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
