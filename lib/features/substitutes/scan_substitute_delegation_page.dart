// ─────────────────────────────────────────────────────────────────────────
// scan_substitute_delegation_page.dart — scansione QR di delega/revoca
// (Supplente)
// ─────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/qr_scanner_dialog.dart';
import 'substitute_actions.dart';
import 'substitute_providers.dart';

class ScanSubstituteDelegationPage extends ConsumerStatefulWidget {
  const ScanSubstituteDelegationPage({super.key});

  @override
  ConsumerState<ScanSubstituteDelegationPage> createState() =>
      _ScanSubstituteDelegationPageState();
}

class _ScanSubstituteDelegationPageState
    extends ConsumerState<ScanSubstituteDelegationPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppScaffold(
      title: 'Scansiona QR',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _infoCard(isDark),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _scanDelegation,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Inquadra QR di delega'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _scanRevocation,
              icon: const Icon(Icons.block_rounded),
              label: const Text('Inquadra QR di revoca'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.blue.shade100,
        ),
      ),
      child: const Text(
        'Il Titolare di una classe può delegarti temporaneamente il registro: '
        'presenze e note di lezione. Inquadra il QR di delega mostrato dal '
        'suo dispositivo per accettarla.\n\nPer interrompere la supplenza, '
        'inquadra il QR di revoca.',
        style: TextStyle(fontSize: 13),
      ),
    );
  }

  Future<void> _scanDelegation() async {
    final assembled = await QrScannerDialog.show(
      context,
      title: 'QR di delega',
      hint: 'Inquadra i QR di delega mostrati dal Titolare.',
    );
    if (assembled == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final service = ref.read(substituteDelegationServiceProvider);
      final imported = await service.importDelegation(assembled);

      final repo = ref.read(substituteDelegationRepoProvider);
      if (repo.getById(imported.delegation.delegationId) != null) {
        _finish('Delega già presente su questo dispositivo.');
        return;
      }
      await repo.importSubstituteSnapshot(
        imported.delegation,
        imported.students,
      );
      await repo.save(imported.delegation);

      _finish(
        'Supplenza "${imported.delegation.className}" accettata. La classe '
        'è ora disponibile fino al '
        '${_fmtDate(imported.delegation.validUntil)}.',
      );
    } catch (e) {
      _finish('QR di delega non valido: $e', error: true);
    }
  }

  Future<void> _scanRevocation() async {
    final assembled = await QrScannerDialog.show(
      context,
      title: 'QR di revoca',
      hint: 'Inquadra i QR di revoca mostrati dal Titolare.',
    );
    if (assembled == null || !mounted) return;

    setState(() => _busy = true);
    final ok = await applyRevocation(context, ref, assembled);
    _busy = false;
    if (!ok) _finish('Revoca non valida.', error: true);
  }

  void _finish(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
