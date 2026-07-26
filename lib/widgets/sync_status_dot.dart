import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/nearby_sync_provider.dart';
import '../features/sync/p2p/p2p_sync_service.dart';

enum SyncDotColor { red, amber, green, cyan }

class SyncStatusDot extends ConsumerWidget {
  const SyncStatusDot({super.key});

  SyncDotColor _resolveColor(P2PSyncState? state) {
    if (state == null) return SyncDotColor.red;

    if (state.status == P2PSyncStatus.syncing) {
      return SyncDotColor.green;
    }

    if (state.isDataUpToDate && state.lastSyncAt != null) {
      return SyncDotColor.cyan;
    }

    if (state.nearbyAssociationsCount > 0) {
      return SyncDotColor.amber;
    }

    return SyncDotColor.red;
  }

  Color _toMaterialColor(SyncDotColor c) {
    switch (c) {
      case SyncDotColor.red:
        return Colors.red;
      case SyncDotColor.amber:
        return Colors.amber;
      case SyncDotColor.green:
        return Colors.green;
      case SyncDotColor.cyan:
        return Colors.cyan;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(nearbySyncStateProvider);

    return syncState.when(
      data: (state) {
        if (!state.isBackgroundSyncActive) {
          return const SizedBox.shrink();
        }
        if (state.largeSyncInProgress && state.totalRecordsToExchange > 0) {
          final progress = state.syncProgressPercent;
          return _ProgressDot(
            color: _toMaterialColor(_resolveColor(state)),
            progress: progress,
            percent: (progress * 100).round(),
          );
        }
        return _Dot(color: _toMaterialColor(_resolveColor(state)));
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _ProgressDot extends StatelessWidget {
  final Color color;
  final double progress;
  final int percent;
  const _ProgressDot({
    required this.color,
    required this.progress,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              backgroundColor: color.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Text(
            '$percent',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
