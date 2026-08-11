import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/storage/local_database.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../meetings/attendance_repository.dart';
import '../students/students_repository.dart';

class StatisticsPage extends StatefulWidget {
  final String className;
  final String classId;

  const StatisticsPage({
    super.key,
    required this.className,
    required this.classId,
  });

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  _StatsData? _stats;
  bool _hasStudents = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    try {
      final studentsRepo = StudentsRepository();
      final classStudents = studentsRepo.getStudentsByClassSync(widget.classId);
      _hasStudents = classStudents.isNotEmpty;

      final attendanceRepo = AttendanceRepository();
      final allAttendance = attendanceRepo.getAttendanceSync();
      final classAttendance = allAttendance
          .where((record) => record['classId'] == widget.classId)
          .toList();

      _stats = _computeStats(classAttendance);
      setState(() {});
    } catch (e) {
      _error = 'Errore nel caricamento delle statistiche: $e';
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AppScaffold(
      title: 'Statistiche',
      child: _buildBody(context, isDark),
    );
  }

  Widget _buildBody(BuildContext context, bool isDark) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.grey.shade300 : Colors.black87,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_stats == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasStudents) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.people_outline, size: 40, color: Colors.orange.shade700),
              ),
              const SizedBox(height: 16),
              Text(
                'Nessun ragazzo registrato',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF174A7E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Aggiungi dei ragazzi al gruppo per visualizzare le statistiche.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_stats!.perMeetingStats.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.event_busy_rounded, size: 40, color: Colors.orange.shade700),
              ),
              const SizedBox(height: 16),
              Text(
                'Nessuna presenza registrata',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF174A7E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Registra le presenze per visualizzare le statistiche.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final stats = _stats!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          widget.className,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF174A7E),
          ),
        ),
        const SizedBox(height: 20),
        _StatGrid(stats: stats, isDark: isDark),
        const SizedBox(height: 24),
        _BestWorstCard(stats: stats, isDark: isDark),
        const SizedBox(height: 24),
        _AttendanceTrendChart(
          stats: stats.perMeetingStats,
          isDark: isDark,
        ),
        const SizedBox(height: 24),
        _PerMeetingBreakdown(
          stats: stats.perMeetingStats,
          isDark: isDark,
        ),
      ],
    );
  }

  _StatsData _computeStats(List<Map<String, dynamic>> attendanceRecords) {
    var totalPresent = 0;
    var totalAbsent = 0;
    var totalStudents = 0;

    final perMeetingStats = <_PerMeetingStat>[];

    for (final record in attendanceRecords) {
      final presence = Map<String, dynamic>.from(
        record['presence'] as Map? ?? {},
      );
      final dateStr = record['date'] as String? ?? '';
      final meetingId = record['id'] as String? ?? '';
      final meetingName = _meetingTitle(meetingId);

      var p = 0, a = 0;
      for (final value in presence.values) {
        if (value == 'Presente') { p++; totalPresent++; }
        if (value == 'Assente') { a++; totalAbsent++; }
      }

      final total = p + a;
      if (total > 0) {
        perMeetingStats.add(_PerMeetingStat(
          meetingId: meetingId,
          date: dateStr,
          title: meetingName,
          present: p,
          absent: a,
          total: total,
          presentPercent: p / total * 100,
        ));
      }
    }

    if (perMeetingStats.isNotEmpty) {
      totalStudents = perMeetingStats
          .map((s) => s.total)
          .reduce((a, b) => a > b ? a : b);
    }

    perMeetingStats.sort((a, b) => a.date.compareTo(b.date));

    final overallTotal = totalPresent + totalAbsent;
    final overallPresentRate =
        overallTotal > 0 ? totalPresent / overallTotal * 100 : 0.0;
    final overallAbsentRate =
        overallTotal > 0 ? totalAbsent / overallTotal * 100 : 0.0;

    final avgPresentPerMeeting = perMeetingStats.isNotEmpty
        ? perMeetingStats.map((s) => s.presentPercent).reduce((a, b) => a + b) /
            perMeetingStats.length
        : 0.0;

    final avgStudentsPerMeeting = perMeetingStats.isNotEmpty
        ? (perMeetingStats.map((s) => s.present).reduce((a, b) => a + b) /
                perMeetingStats.length)
            .round()
        : 0;

    final best = perMeetingStats.isEmpty
        ? null
        : perMeetingStats.reduce(
            (a, b) => a.presentPercent > b.presentPercent ? a : b);
    final worst = perMeetingStats.isEmpty
        ? null
        : perMeetingStats.reduce(
            (a, b) => a.presentPercent < b.presentPercent ? a : b);

    return _StatsData(
      overallPresentRate: overallPresentRate,
      overallAbsentRate: overallAbsentRate,
      avgPresentPerMeeting: avgPresentPerMeeting,
      avgStudentsPerMeeting: avgStudentsPerMeeting,
      totalMeetings: perMeetingStats.length,
      totalStudents: totalStudents,
      bestMeeting: best,
      worstMeeting: worst,
      perMeetingStats: perMeetingStats,
    );
  }

  String _meetingTitle(String meetingId) {
    final planning = LocalDatabase.planning().get(meetingId);
    if (planning == null) {
      return meetingId.length > 8
          ? meetingId.substring(0, 8)
          : meetingId;
    }
    final data = Map<String, dynamic>.from(planning);
    return data['title']?.toString() ?? data['date']?.toString() ?? meetingId;
  }
}

class _StatsData {
  final double overallPresentRate;
  final double overallAbsentRate;
  final double avgPresentPerMeeting;
  final int avgStudentsPerMeeting;
  final int totalMeetings;
  final int totalStudents;
  final _PerMeetingStat? bestMeeting;
  final _PerMeetingStat? worstMeeting;
  final List<_PerMeetingStat> perMeetingStats;

  _StatsData({
    required this.overallPresentRate,
    required this.overallAbsentRate,
    required this.avgPresentPerMeeting,
    required this.avgStudentsPerMeeting,
    required this.totalMeetings,
    required this.totalStudents,
    this.bestMeeting,
    this.worstMeeting,
    required this.perMeetingStats,
  });
}

class _PerMeetingStat {
  final String meetingId;
  final String date;
  final String title;
  final int present;
  final int absent;
  final int total;
  final double presentPercent;

  _PerMeetingStat({
    required this.meetingId,
    required this.date,
    required this.title,
    required this.present,
    required this.absent,
    required this.total,
    required this.presentPercent,
  });
}

// ─── STAT GRID ──────────────────────────────────────────────────────────────

class _StatGrid extends StatelessWidget {
  final _StatsData stats;
  final bool isDark;

  const _StatGrid({required this.stats, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Presenze medie',
                value: '${stats.overallPresentRate.toStringAsFixed(1)}%',
                icon: Icons.trending_up_rounded,
                color: Colors.green,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Assenze medie',
                value: '${stats.overallAbsentRate.toStringAsFixed(1)}%',
                icon: Icons.trending_down_rounded,
                color: Colors.red,
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Media presenze per incontro',
                value: '${stats.avgPresentPerMeeting.toStringAsFixed(1)}%',
                icon: Icons.bar_chart_rounded,
                color: Colors.blue,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Totale incontri',
                value: '${stats.totalMeetings}',
                icon: Icons.event_rounded,
                color: Colors.orange,
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                  label: 'Ragazzi nel gruppo',
                  value: '${stats.totalStudents}',
                  icon: Icons.people_rounded,
                  color: Colors.purple,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Media ragazzi per incontro',
                value: '${stats.avgStudentsPerMeeting}',
                icon: Icons.person_rounded,
                color: Colors.teal,
                isDark: isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isDark;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final borderColor = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.2)
        : Colors.grey.shade200;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade400 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── BEST / WORST MEETING ──────────────────────────────────────────────────

class _BestWorstCard extends StatelessWidget {
  final _StatsData stats;
  final bool isDark;

  const _BestWorstCard({required this.stats, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final borderColor = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.2)
        : Colors.grey.shade200;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Miglior e peggior incontro',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 14),
          if (stats.bestMeeting != null)
            _MeetingRow(
              icon: Icons.emoji_events_rounded,
              iconColor: Colors.amber,
              label: 'Migliori presenze',
              title: stats.bestMeeting!.title,
              percent: stats.bestMeeting!.presentPercent,
              isDark: isDark,
            ),
          if (stats.worstMeeting != null) ...[
            const SizedBox(height: 10),
            _MeetingRow(
              icon: Icons.warning_rounded,
              iconColor: Colors.red,
              label: 'Peggiori presenze',
              title: stats.worstMeeting!.title,
              percent: stats.worstMeeting!.presentPercent,
              isDark: isDark,
            ),
          ],
          if (stats.bestMeeting == null)
            Text(
              'Nessun dato disponibile',
              style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey),
            ),
        ],
      ),
    );
  }
}

class _MeetingRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String title;
  final double percent;
  final bool isDark;

  const _MeetingRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.title,
    required this.percent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.black54,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ),
        Text(
          '${percent.toStringAsFixed(0)}%',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: iconColor,
          ),
        ),
      ],
    );
  }
}

// ─── LINE CHART ────────────────────────────────────────────────────────────

class _AttendanceTrendChart extends StatelessWidget {
  final List<_PerMeetingStat> stats;
  final bool isDark;

  const _AttendanceTrendChart({
    required this.stats,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final borderColor = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.2)
        : Colors.grey.shade200;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Andamento presenze nel tempo',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 14),
          if (stats.isEmpty)
            Text(
              'Nessun dato disponibile',
              style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey),
            )
          else
            SizedBox(
              height: 220,
              child: _LineChart(
                stats: stats,
                isDark: isDark,
              ),
            ),
        ],
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  final List<_PerMeetingStat> stats;
  final bool isDark;

  const _LineChart({required this.stats, required this.isDark});

  String _formatDateShort(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _LineChartPainter(
            stats: stats,
            isDark: isDark,
            formatDate: _formatDateShort,
          ),
        );
      },
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_PerMeetingStat> stats;
  final bool isDark;
  final String Function(String) formatDate;

  _LineChartPainter({
    required this.stats,
    required this.isDark,
    required this.formatDate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (stats.isEmpty) return;

    final maxPresent = stats.map((s) => s.total).reduce(math.max);
    final padding = const EdgeInsets.fromLTRB(50, 16, 20, 44);
    final chartWidth = size.width - padding.left - padding.right;
    final chartHeight = size.height - padding.top - padding.bottom;

    // Griglia orizzontale
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white24 : Colors.black12).withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    final gridLines = 4;
    for (var i = 0; i <= gridLines; i++) {
      final y = padding.top + chartHeight * (1 - i / gridLines);
      canvas.drawLine(
        Offset(padding.left, y),
        Offset(size.width - padding.right, y),
        gridPaint,
      );

      // Etichette y
      final label = (maxPresent * i / gridLines).round().toString();
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          fontSize: 11,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(padding.left - tp.width - 8, y - tp.height / 2));
    }

    // Calcola punti
    final points = <Offset>[];
    final stepX = stats.length > 1 ? chartWidth / (stats.length - 1) : chartWidth / 2;

    for (var i = 0; i < stats.length; i++) {
      final x = padding.left + i * stepX;
      final y = padding.top +
          chartHeight * (1 - stats[i].present / maxPresent);
      points.add(Offset(x, y));
    }

    // Area fill sotto la linea
    if (points.length >= 2) {
      final areaPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.green.withValues(alpha: 0.25),
            Colors.green.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(padding.left, padding.top, chartWidth, chartHeight));

      final path = Path()..moveTo(points.first.dx, padding.top + chartHeight);
      for (final pt in points) {
        path.lineTo(pt.dx, pt.dy);
      }
      path.lineTo(points.last.dx, padding.top + chartHeight);
      path.close();
      canvas.drawPath(path, areaPaint);
    }

    // Linea
    if (points.length >= 2) {
      final linePaint = Paint()
        ..color = Colors.green
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, linePaint);
    }

    // Punti e linee verticali tratteggiate
    final dotPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;

    final labelPaint = Paint()
      ..color = (isDark ? Colors.white38 : Colors.black38).withValues(alpha: 0.4)
      ..strokeWidth = 0.5;

    for (var i = 0; i < points.length; i++) {
      // Punto
      canvas.drawCircle(points[i], 4, dotPaint);
      canvas.drawCircle(points[i], 2, Paint()..color = Colors.white);

      // Linea verticale tratteggiata
      if (stats.length > 1) {
        final dashWidth = 3.0, dashSpace = 3.0;
        var startY = points[i].dy;
        while (startY < padding.top + chartHeight) {
          canvas.drawLine(
            Offset(points[i].dx, startY),
            Offset(points[i].dx, (startY + dashWidth).clamp(0, padding.top + chartHeight)),
            labelPaint,
          );
          startY += dashWidth + dashSpace;
        }
      }

      // Etichetta x (data)
      final label = formatDate(stats[i].date);
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          fontSize: 10,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(points[i].dx - tp.width / 2, padding.top + chartHeight + 12),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.stats != stats || oldDelegate.isDark != isDark;
}

// ─── PER MEETING BREAKDOWN ─────────────────────────────────────────────────

class _PerMeetingBreakdown extends StatelessWidget {
  final List<_PerMeetingStat> stats;
  final bool isDark;

  const _PerMeetingBreakdown({
    required this.stats,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final borderColor = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.2)
        : Colors.grey.shade200;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dettaglio per incontro',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF174A7E),
            ),
          ),
          const SizedBox(height: 14),
          if (stats.isEmpty)
            Text(
              'Nessun dato disponibile',
              style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey),
            )
          else
            ...stats.map((stat) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AttendanceBar(
                title: stat.title,
                present: stat.present,
                absent: stat.absent,
                total: stat.total,
                percent: stat.presentPercent,
                isDark: isDark,
              ),
            )),
        ],
      ),
    );
  }
}

class _AttendanceBar extends StatelessWidget {
  final String title;
  final int present;
  final int absent;
  final int total;
  final double percent;
  final bool isDark;

  const _AttendanceBar({
    required this.title,
    required this.present,
    required this.absent,
    required this.total,
    required this.percent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final pctPresent = total > 0 ? present / total : 0.0;
    final pctAbsent = total > 0 ? absent / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${percent.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: percent >= 75
                    ? Colors.green
                    : percent >= 50
                        ? Colors.orange
                        : Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                Flexible(
                  flex: (pctPresent * 100).round().clamp(1, 100),
                  child: Container(color: Colors.green),
                ),
                Flexible(
                  flex: (pctAbsent * 100).round().clamp(1, 100),
                  child: Container(color: Colors.red.shade300),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${present}P · ${absent}A',
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
