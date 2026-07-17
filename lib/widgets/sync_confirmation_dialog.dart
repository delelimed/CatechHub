import 'package:flutter/material.dart';

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
    return AlertDialog(
      icon: Icon(
        Icons.sync_alt,
        size: 48,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text('Sincronizzazione richiesta'),
      content: Text(
        'Vuoi sincronizzare i dati con $catechistName?',
        textAlign: TextAlign.center,
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
