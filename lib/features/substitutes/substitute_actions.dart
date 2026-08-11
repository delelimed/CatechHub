// ─────────────────────────────────────────────────────────────────────────
// substitute_actions.dart — azioni condivise del modulo Supplenze
// (mostra QR di delega, acquisizione dati, termine/revoca delega).
// ─────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/substitute_delegation.dart';
import '../../shared/widgets/qr_chunks_dialog.dart';
import '../../shared/widgets/qr_scanner_dialog.dart';
import 'substitute_providers.dart';

/// Ripresenta il QR di delega (chunk persistiti al momento della creazione).
Future<void> showDelegationQr(
  BuildContext context,
  SubstituteDelegation delegation,
) async {
  if (delegation.qrChunks.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('QR di delega non più disponibile sul dispositivo.'),
      ),
    );
    return;
  }
  final range = '${_fmtDate(delegation.validFrom)} → ${_fmtDate(delegation.validUntil)}';
  await QrChunksDialog.show(
    context,
    title: 'QR di delega',
    subtitle:
        'Delega della classe "${delegation.className}" a ${delegation.substituteName}.'
        '\nValidità: $range',
    chunks: delegation.qrChunks,
    footer:
        'Il Supplente deve inquadrare i QR con "Scansiona QR" mantenendo'
        ' lo stesso ordine.',
  );
}

/// Il Titolare scansiona il QR di consegna dati del Supplente e importa
/// presenze e note. Ritorna true se l'acquisizione è andata a buon fine.
Future<bool> acquireHandover(
  BuildContext context,
  WidgetRef ref,
  SubstituteDelegation delegation,
) async {
  final assembled = await QrScannerDialog.show(
    context,
    title: 'Acquisisci dati supplenza',
    hint: 'Inquadra i QR di consegna mostrati dal dispositivo del Supplente.',
  );
  if (assembled == null || !context.mounted) return false;

  try {
    final service = ref.read(substituteDelegationServiceProvider);
    final data = await service.importHandover(assembled, delegation);

    var attendanceImported = 0;
    final attendanceBox = LocalDatabase.attendance();
    for (final record in data.attendance) {
      final meetingId = record['meetingId']?.toString() ?? '';
      if (meetingId.isEmpty || attendanceBox.containsKey(meetingId)) continue;
      final map = Map<String, dynamic>.from(record);
      map.remove('id');
      map['viaDelegationId'] = delegation.delegationId;
      map['_substituteReport'] = delegation.substituteName;
      await attendanceBox.put(meetingId, map);
      attendanceImported++;
    }
    await attendanceBox.flush();

    final repo = ref.read(substituteDelegationRepoProvider);
    final notesImported = await repo.importLessonNotes(data.notes);
    await repo.markCollected(delegation.delegationId);

    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Dati acquisiti: $attendanceImported presenze e $notesImported note'
          ' importate.',
        ),
      ),
    );
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Acquisizione non riuscita: $e'),
        backgroundColor: Colors.red.shade700,
      ),
    );
    return false;
  }
}

/// "Termina Supplenza": revoca immediata da parte del Titolare.
Future<void> terminateDelegation(
  BuildContext context,
  WidgetRef ref,
  SubstituteDelegation delegation,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Termina supplenza'),
      content: const Text(
        'La classe verrà rimossa dall\'interfaccia del Supplente alla revoca.'
        '\n\nPrima della revoca assicurati di aver acquisito presenze e note'
        ' con il pulsante "Acquisisci dati".',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Termina supplenza'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final repo = ref.read(substituteDelegationRepoProvider);
  await repo.updateStatus(
    delegation.delegationId,
    SubstituteDelegationStatus.revoked,
  );

  // Mostra il QR di revoca da inquadrare con il dispositivo del Supplente.
  final service = ref.read(substituteDelegationServiceProvider);
  List<Map<String, dynamic>> chunks;
  try {
    chunks = await service.buildRevokeQrChunks(delegation);
  } catch (_) {
    chunks = const [];
  }
  if (!context.mounted) return;
  await QrChunksDialog.show(
    context,
    title: 'Revoca inviata',
    subtitle:
        'La delega "${delegation.className}" è stata revocata sul tuo'
        ' dispositivo.',
    chunks: chunks,
    footer:
        'Inquadra questi QR con il dispositivo del Supplente per rimuovere'
        ' immediatamente la classe e distruggere la chiave temporanea.',
  );
}

/// Applica un QR di revoca ricevuto dal Titolare (lato Supplente): verifica
/// la firma e, se valida, distrugge i dati locali della supplenza.
Future<bool> applyRevocation(
  BuildContext context,
  WidgetRef ref,
  String assembled,
) async {
  final service = ref.read(substituteDelegationServiceProvider);
  final delegationId = await service.verifyRevoke(assembled);
  if (delegationId == null || !context.mounted) return false;

  final repo = ref.read(substituteDelegationRepoProvider);
  final delegation = repo.getById(delegationId);
  if (delegation == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nessuna supplenza corrispondente a questa revoca.')),
    );
    return true;
  }
  await repo.updateStatus(delegationId, SubstituteDelegationStatus.revoked);
  if (!context.mounted) return true;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Supplenza "${delegation.className}" revocata. La classe non è più'
        ' visibile.',
      ),
    ),
  );
  return true;
}

String _fmtDate(DateTime d) => DateFormat('dd/MM/yyyy', 'it_IT').format(d);