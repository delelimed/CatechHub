import 'package:flutter/material.dart';

class LastModifiedInfo extends StatelessWidget {
  final DateTime? createdAt;
  final DateTime updatedAt;
  final String lastModifiedBy;
  final bool compact;

  const LastModifiedInfo({
    super.key,
    this.createdAt,
    required this.updatedAt,
    required this.lastModifiedBy,
    this.compact = false,
  });

  String _format(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _relative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'pochi secondi fa';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minuti fa';
    if (diff.inHours < 24) return '${diff.inHours} ore fa';
    if (diff.inDays < 7) return '${diff.inDays} giorni fa';
    return _format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: Colors.grey[500],
      fontSize: compact ? 11 : 12,
    );

    if (compact) {
      return Text(
        '${_relative(updatedAt)}${lastModifiedBy.isNotEmpty ? ' · $lastModifiedBy' : ''}',
        style: muted,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (createdAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('Creata: ${_format(createdAt!)}', style: muted),
          ),
        Text(
          'Ultima modifica: ${_format(updatedAt)}${lastModifiedBy.isNotEmpty ? ' da $lastModifiedBy' : ''}',
          style: muted,
        ),
      ],
    );
  }
}
