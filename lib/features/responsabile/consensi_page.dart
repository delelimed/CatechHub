// ══════════════════════════════════════════════════════════════════════════════
// consensi_page.dart — CatechHub (consensi scheda di iscrizione + contributi)
//
// Modulo "GDPR & Privacy": vista del Responsabile per la gestione della
// scheda di iscrizione unificata firmata (che incorpora il consenso al
// trattamento dei dati) e del contributo volontario delle famiglie.
//
// Ogni card riepiloga lo stato della scheda (firmata/valida, scaduta,
// non firmata), la data di firma, la scadenza del trattamento e il
// contributo volontario. Azioni: registra firma, revoca, aggiorna contributo.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../shared/models/student_model.dart';
import '../../shared/models/user_role.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'consensi_service.dart';
import 'responsabile_providers.dart';

/// Pagina gestione consensi e contributi volontari.
class ConsensiPage extends ConsumerStatefulWidget {
  const ConsensiPage({super.key});

  @override
  ConsumerState<ConsensiPage> createState() => _ConsensiPageState();
}

class _ConsensiPageState extends ConsumerState<ConsensiPage> {
  StatoConsenso? _filtro;

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    if (!RolePermissions.currentCan(RolePermission.manageAuditLog)) {
      return AppScaffold(
        title: 'Consensi & contributi',
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Sezione riservata al Responsabile Catechistico.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return AppScaffold(
      title: 'Consensi & contributi',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _intro(context),
          const SizedBox(height: 12),
          _filters(),
          const SizedBox(height: 8),
          Expanded(
            child: ref.watch(parrocchiaStudentsProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Errore: $e')),
              data: (students) {
                final filtered = _filtro == null
                    ? students
                    : students
                        .where((s) =>
                            ConsensiService.stato(s) == _filtro)
                        .toList();
                if (filtered.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nessun ragazzo corrisponde al filtro selezionato.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(parrocchiaStudentsProvider.future),
                  child: ListView(
                    children: [
                      for (final s in filtered) _studentCard(s),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _intro(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF174A7E), Color(0xFF2368B1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Schede di iscrizione & contributi',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'La firma della scheda di iscrizione unificata abilita il '
            'trattamento dei dati del minore per finalità pastorali, con '
            'scadenza calcolata automaticamente. Il contributo è volontario.',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    Widget chip(StatoConsenso? s, String label) {
      final selected = _filtro == s;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filtro = selected ? null : s),
      );
    }

    return Wrap(
      spacing: 8,
      children: [
        chip(null, 'Tutti'),
        chip(StatoConsenso.valido, 'Firmata'),
        chip(StatoConsenso.scaduto, 'Scaduta'),
        chip(StatoConsenso.nonFirmato, 'Non firmata'),
      ],
    );
  }

  Widget _studentCard(Student s) {
    final info = ConsensiService.info(s);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
        isDark ? Theme.of(context).colorScheme.surfaceContainer : Colors.white;

    final statoColor = switch (info.stato) {
      StatoConsenso.valido => Colors.green,
      StatoConsenso.scaduto => Colors.orange,
      StatoConsenso.nonFirmato => Colors.redAccent,
    };
    final statoLabel = switch (info.stato) {
      StatoConsenso.valido => 'Scheda firmata',
      StatoConsenso.scaduto => 'Scaduta',
      StatoConsenso.nonFirmato => 'Non firmata',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_rounded, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${s.name} ${s.surname}'.trim(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statoColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statoLabel,
                  style: TextStyle(
                    color: statoColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _infoRow(
            Icons.edit_document,
            info.eFirmato
                ? 'Scheda firmata il ${_fmt(info.firma)}'
                : 'Scheda non firmata',
          ),
          if (info.scadenza != null)
            _infoRow(Icons.event_available, 'Scadenza: ${_fmt(info.scadenza)}'),
          _infoRow(
            Icons.payments_rounded,
            s.contributoVersato
                ? 'Contributo versato: ${s.contributoEuros.toStringAsFixed(2)} €'
                    '${s.annoContributo.isNotEmpty ? ' · ${s.annoContributo}' : ''}'
                : 'Contributo volontario: non versato',
          ),
          const Divider(height: 16),
          Row(
            children: [
              if (!info.eFirmato)
                FilledButton.tonalIcon(
                  onPressed: () => _registraScheda(s),
                  icon: const Icon(Icons.task_alt_rounded, size: 18),
                  label: const Text('Registra firma'),
                )
              else
                TextButton.icon(
                  onPressed: () => _revoca(s),
                  icon: const Icon(Icons.event_busy_rounded, size: 18),
                  label: const Text('Revoca'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Aggiorna contributo volontario',
                icon: const Icon(Icons.payments_rounded, size: 20),
                onPressed: () => _aggiornaContributo(s),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade400
                    : Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _registraScheda(Student s) async {
    final durata = ConsensiService.durataMesiDaConfig();
    final conferma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.task_alt_rounded),
        title: const Text('Registra scheda firmata'),
        content: Text(
          'Confermi che la famiglia di ${s.name} ${s.surname} ha firmato la '
          'scheda di iscrizione unificata? Il trattamento dei dati sarà '
          'valido per $durata mesi dalla data di oggi.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Conferma firma'),
          ),
        ],
      ),
    );
    if (conferma != true) return;
    await ConsensiService.registraScheda(s);
    _snack('Scheda firmata registrata per ${s.name} ${s.surname}.');
  }

  Future<void> _revoca(Student s) async {
    final conferma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: const Text('Revoca scheda'),
        content: Text(
          'Revocare la firma della scheda di ${s.name} ${s.surname}? '
          'L\'anagrafica non verrà eliminata, ma il trattamento dei dati '
          'non sarà più autorizzato.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoca'),
          ),
        ],
      ),
    );
    if (conferma != true) return;
    await ConsensiService.revoca(s);
    _snack('Firma revocata per ${s.name} ${s.surname}.');
  }

  Future<void> _aggiornaContributo(Student s) async {
    final ctrl = TextEditingController(
      text: s.contributoVersato
          ? s.contributoEuros.toStringAsFixed(2)
          : '20.00',
    );
    var versato = s.contributoVersato;
    String? anno = s.annoContributo;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          icon: const Icon(Icons.payments_rounded),
          title: const Text('Contributo volontario'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Contributo versato', style: TextStyle(fontSize: 14)),
                value: versato,
                onChanged: (v) => setState(() => versato = v ?? false),
              ),
              if (versato) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Importo (€)',
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixText: '€ ',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: TextEditingController(text: anno),
                  decoration: const InputDecoration(
                    labelText: 'Anno catechistico',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => anno = v,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () async {
                final euros = double.tryParse(
                      ctrl.text.trim().replaceAll(',', '.'),
                    ) ??
                    0;
                await ConsensiService.aggiornaContributo(
                  s,
                  versato: versato,
                  euros: euros,
                  anno: anno ?? '',
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _snack('Contributo aggiornato.');
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime? d) {
    if (d == null) return '-';
    return DateFormat('dd/MM/yyyy').format(d.toLocal());
  }
}