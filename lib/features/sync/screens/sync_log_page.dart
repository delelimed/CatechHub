import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/nearby_sync_provider.dart';
import '../p2p/p2p_sync_service.dart';

class SyncLogPage extends ConsumerStatefulWidget {
  const SyncLogPage({super.key});

  @override
  ConsumerState<SyncLogPage> createState() => _SyncLogPageState();
}

class _SyncLogPageState extends ConsumerState<SyncLogPage> {
  String _levelFilter = 'ALL';
  final _scrollController = ScrollController();
  bool _autoScroll = true;

  static const _levels = ['ALL', 'ERROR', 'WARN', 'INFO', 'DEBUG'];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<SyncLogEntry> _filteredLogs(List<SyncLogEntry> logs) {
    if (_levelFilter == 'ALL') return logs;
    return logs.where((e) => e.level == _levelFilter).toList();
  }

  Map<String, int> _countByLevel(List<SyncLogEntry> logs) {
    final counts = <String, int>{};
    for (final lvl in _levels) {
      if (lvl == 'ALL') continue;
      counts[lvl] = logs.where((e) => e.level == lvl).length;
    }
    return counts;
  }

  Color _levelColor(String level) {
    switch (level) {
      case 'ERROR':
        return Colors.red;
      case 'WARN':
        return Colors.orange;
      case 'INFO':
        return Colors.green;
      case 'DEBUG':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  IconData _levelIcon(String level) {
    switch (level) {
      case 'ERROR':
        return Icons.error_outline;
      case 'WARN':
        return Icons.warning_amber_rounded;
      case 'INFO':
        return Icons.info_outline;
      case 'DEBUG':
        return Icons.bug_report_outlined;
      default:
        return Icons.circle;
    }
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 10) return 'ora';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s fa';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m fa';
    if (diff.inHours < 24) return '${diff.inHours}h fa';
    return '${diff.inDays}g fa';
  }

  @override
  Widget build(BuildContext context) {
    final asyncLogs = ref.watch(syncLogsProvider);
    final allLogs = asyncLogs.asData?.value ?? [];
    final logs = _filteredLogs(allLogs);
    final counts = _countByLevel(allLogs);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log di sincronizzazione',
            style: TextStyle(color: Colors.white)),
        backgroundColor: colorScheme.primary,
        actions: [
          if (allLogs.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.copy_all, color: Colors.white70),
              tooltip: 'Copia tutti i log',
              onPressed: () {
                final text = allLogs
                    .map((e) =>
                        '[${DateFormat('HH:mm:ss').format(e.timestamp)}] [${e.level}] ${e.message}')
                    .join('\n');
                Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Log copiati negli appunti'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.white70),
              tooltip: 'Cancella log',
              onPressed: () {
                ref.read(nearbySyncServiceProvider).clearLogs();
              },
            ),
          ],
        ],
      ),
      body: allLogs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64,
                      color: isDark ? Colors.grey[700] : Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Nessun log disponibile',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'I log appariranno qui durante\ne dopo la sincronizzazione.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey[600] : Colors.grey[400],
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                _buildLogSummary(allLogs, counts, isDark),
                _buildFilterChips(),
                _buildLogCounter(logs.length, allLogs.length),
                const Divider(height: 1),
                Expanded(
                  child: logs.isEmpty
                      ? Center(
                          child: Text(
                            'Nessun log di livello "$_levelFilter"',
                            style: TextStyle(
                              color: isDark ? Colors.grey[500] : Colors.grey[500],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: logs.length,
                          itemBuilder: (_, index) =>
                              _buildLogEntry(logs[index], isDark),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildLogSummary(
      List<SyncLogEntry> allLogs, Map<String, int> counts, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[50],
        border: Border(
          bottom: BorderSide(
              color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.analytics_outlined,
              size: 18, color: isDark ? Colors.grey[400] : Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '${allLogs.length} eventi  ·  ',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          ..._levels.where((l) => l != 'ALL').map((lvl) {
            final count = counts[lvl] ?? 0;
            if (count == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _SmallBadge(
                color: _levelColor(lvl),
                label: '$lvl: $count',
              ),
            );
          }),
          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(() => _autoScroll = !_autoScroll);
            },
            child: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_top,
              size: 18,
              color: _autoScroll
                  ? (isDark ? Colors.grey[400] : Colors.grey[600])
                  : Colors.orange[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[50],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _levels.map((lvl) {
            final selected = _levelFilter == lvl;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(
                  lvl,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? Colors.white : null,
                  ),
                ),
                selected: selected,
                selectedColor: lvl == 'ALL'
                    ? Theme.of(context).colorScheme.primary
                    : _levelColor(lvl),
                checkmarkColor: Colors.white,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _levelFilter = lvl),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLogCounter(int filtered, int total) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            'Mostrati $filtered di $total log',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.grey[500] : Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(SyncLogEntry entry, bool isDark) {
    final isError = entry.level == 'ERROR';
    final isWarn = entry.level == 'WARN';
    final isDebug = entry.level == 'DEBUG';
    final timeStr = DateFormat('HH:mm:ss').format(entry.timestamp);
    final dateStr = DateFormat('dd/MM/yyyy').format(entry.timestamp);
    final color = _levelColor(entry.level);

    return InkWell(
      onLongPress: () {
        Clipboard.setData(ClipboardData(
          text: '$dateStr $timeStr [${entry.level}] ${entry.message}',
        ));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Log copiato negli appunti'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: color.withValues(alpha: 0.5), width: 3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                _levelIcon(entry.level),
                size: 14,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 68,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _relativeTime(entry.timestamp),
                    style: TextStyle(
                      fontSize: 9,
                      color: isDark ? Colors.grey[600] : Colors.grey[400],
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.grey[500] : Colors.grey[500],
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.message,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: isError
                      ? (isDark ? Colors.red[300] : Colors.red[800])
                      : isWarn
                          ? (isDark ? Colors.orange[300] : Colors.orange[900])
                          : isDebug
                              ? (isDark
                                  ? Colors.blueGrey[300]
                                  : Colors.blueGrey[700])
                              : (isDark ? Colors.grey[300] : null),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  final Color color;
  final String label;

  const _SmallBadge({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
