import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_service.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../classes/classes_provider.dart';
import '../planning/planning_provider.dart';
import 'attendance_repository.dart';

class AttendanceMeetingsPage extends ConsumerStatefulWidget {
  const AttendanceMeetingsPage({super.key});

  @override
  ConsumerState<AttendanceMeetingsPage> createState() => _AttendanceMeetingsPageState();
}

class _AttendanceMeetingsPageState extends ConsumerState<AttendanceMeetingsPage> {
  bool _showPast = false;

  Stream<Map<String, bool>> _getAttendanceStatus() {
    return AttendanceRepository().getAttendance().map((records) {
      return {for (final record in records) record['id'].toString(): true};
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final classesAsync = ref.watch(classesStreamProvider);
    final planningRepo = ref.watch(planningRepoProvider);

    return AppScaffold(
      title: 'Seleziona incontro',
      child: classesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _EmptyState(
          icon: Icons.gpp_bad_rounded,
          title: 'Errore',
          subtitle: e.toString(),
        ),
        data: (classes) {
          final myClass = classes.where(
            (c) => c.catechistIds.contains(AuthService.localUserId),
          );

          if (myClass.isEmpty) {
            return const _EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Attenzione',
              subtitle: 'Non sei associato a nessuna classe come catechista',
            );
          }

          final classId = myClass.first.id;

          return StreamBuilder(
            stream: planningRepo.getMeetings(),
            builder: (context, meetingsSnapshot) {
              if (!meetingsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);

              var meetings = meetingsSnapshot.data!
                  .where((m) => m.classId == classId && !m.isReunion)
                  .toList();

              if (_showPast) {
                meetings = meetings.where((m) => m.date.isBefore(today)).toList();
                meetings.sort((a, b) => b.date.compareTo(a.date));
              } else {
                meetings = meetings.where((m) => !m.date.isBefore(today)).toList();
                meetings.sort((a, b) => a.date.compareTo(b.date));
              }

              if (meetings.isEmpty) {
                return Column(
                  children: [
                    _buildToggleBar(),
                    const Expanded(
                      child: _EmptyState(
                        icon: Icons.event_note_rounded,
                        title: 'Nessun incontro',
                        subtitle: 'Non ci sono incontri programmati per la tua classe.',
                      ),
                    ),
                  ],
                );
              }

              return StreamBuilder<Map<String, bool>>(
                stream: _getAttendanceStatus(),
                builder: (context, attendanceSnapshot) {
                  final attendanceMap = attendanceSnapshot.data ?? {};

                  return ListView.builder(
                    padding: const EdgeInsets.only(
                      bottom: 100,
                      left: 4,
                      right: 4,
                      top: 16,
                    ),
                    itemCount: meetings.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Column(
                          children: [
                            _buildToggleBar(),
                            const SizedBox(height: 14),
                            _GridButton(
                              onTap: () => context.push('/attendance-grid'),
                            ),
                          ],
                        );
                      }
                      final m = meetings[index - 1];
                      final exists = attendanceMap[m.id] ?? false;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => context.push('/attendance', extra: m),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isDark
                                    ? [
                                        colorScheme.surfaceContainer,
                                        colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                      ]
                                    : [
                                        Colors.white,
                                        Colors.blue.shade50.withValues(alpha: 0.35),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: isDark ? colorScheme.outline.withValues(alpha: 0.2) : Colors.blue.shade100),
                              boxShadow: [
                                BoxShadow(
                                  color: isDark
                                      ? Colors.black.withValues(alpha: 0.3)
                                      : Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
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
                                        DateFormat('MMM', 'it_IT')
                                            .format(m.date)
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 10,
                                        ),
                                      ),
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
                                          color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
                                        ),
                                      ),
                                      if (exists) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: Colors.green.withValues(alpha: 0.4),
                                            ),
                                          ),
                                          child: const Text(
                                            'Presenza già registrata',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.green,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 16,
                                  color: isDark ? Colors.grey.shade500 : Colors.grey,
                                ),
                              ],
                            ),
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

  Widget _buildToggleBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _ToggleChip(
              label: _showPast ? 'Prossimi' : 'Passati',
              icon: _showPast ? Icons.upcoming_rounded : Icons.history_rounded,
              onTap: () {
                setState(() => _showPast = !_showPast);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
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

class _GridButton extends StatelessWidget {
  final VoidCallback onTap;

  const _GridButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF174A7E), Color(0xFF2A6BB0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Visualizza Griglia',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Registro presenze completo',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Apri',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

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
                color: isDark ? colorScheme.primaryContainer.withValues(alpha: 0.3) : Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 42, color: isDark ? colorScheme.primary : const Color(0xFF174A7E)),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? colorScheme.onSurface : null),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade700, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
