import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/providers/nearby_sync_provider.dart';

class SyncLogPage extends ConsumerWidget {
  const SyncLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(syncLogsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log di sincronizzazione',
            style: TextStyle(color: Colors.white)),
        backgroundColor: colorScheme.primary,
        actions: [
          if (logs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.white70),
              tooltip: 'Cancella log',
              onPressed: () {
                ref.read(nearbySyncServiceProvider).clearLogs();
              },
            ),
        ],
      ),
      body: logs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Nessun log disponibile',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'I log appariranno qui durante\ne dopo la sincronizzazione.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final entry = logs[index];
                final timeStr = DateFormat('HH:mm:ss').format(entry.timestamp);
                final dateStr = DateFormat('dd/MM/yyyy').format(entry.timestamp);
                final isError = entry.level == 'ERROR';
                final isWarn = entry.level == 'WARN';

                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isError
                              ? Colors.red
                              : isWarn
                                  ? Colors.orange
                                  : Colors.green,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: Text(
                          '$dateStr $timeStr',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.message,
                          style: TextStyle(
                            fontSize: 13,
                            color: isError
                                ? Colors.red[800]
                                : isWarn
                                    ? Colors.orange[900]
                                    : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
