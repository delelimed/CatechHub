import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class SyncConfirmationDialog extends StatelessWidget {
  final String catechistName;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const SyncConfirmationDialog({
    super.key,
    required this.catechistName,
    required this.onAccept,
    required this.onReject,
  });

  static String _getCurrentClassName() {
    try {
      final box = Hive.box<Map>('classes_box');
      const uid = 'local_catechist_id';
      for (final key in box.keys) {
        final data = Map<String, dynamic>.from(box.get(key) as Map);
        final ids = (data['catechistIds'] as List? ?? []).map((e) => e.toString()).toList();
        if (ids.contains(uid)) {
          return data['name']?.toString() ?? 'Classe';
        }
      }
    } catch (_) {}
    return 'Classe corrente';
  }

  static Future<bool?> show(
    BuildContext context, {
    required String catechistName,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SyncConfirmationDialog(
        catechistName: catechistName,
        onAccept: () => Navigator.of(ctx).pop(true),
        onReject: () => Navigator.of(ctx).pop(false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final className = _getCurrentClassName();
    return AlertDialog(
      icon: Icon(
        Icons.sync_alt,
        size: 48,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text('Sincronizzazione richiesta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Vuoi sincronizzare i dati con $catechistName?',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF174A7E).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.class_, size: 16, color: const Color(0xFF174A7E)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Classe: $className',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF174A7E), fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'La sincronizzazione Bluetooth avviene solo tra dispositivi della stessa classe.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onReject,
          child: const Text('Rifiuta'),
        ),
        FilledButton(
          onPressed: onAccept,
          child: const Text('Accetta'),
        ),
      ],
    );
  }
}
