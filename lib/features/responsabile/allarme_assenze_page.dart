// ══════════════════════════════════════════════════════════════════════════════
// allarme_assenze_page.dart — CatechHub (allerta assenze prolungate)
//
// Tab "Allarmi assenze": vista aggregata delle presenze parrocchiali con
// il sistema di allerta "assenze prolungate". La soglia è personalizzabile
// e persistita nella ParishConfig (sogliaAssenzeConsecutive). I ragazzi che
// superano la soglia vengono evidenziati al Responsabile per il contatto
// diretto con le famiglie (tel: / SMS).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/parish_config.dart';
import '../students/students_repository.dart';
import 'presenze_parrocchiali_service.dart';
import 'responsabile_providers.dart';

/// Tab di monitoraggio delle presenze parrocchiali e allerta assenze.
class AllarmeAssenzePage extends ConsumerStatefulWidget {
  const AllarmeAssenzePage({super.key});

  @override
  ConsumerState<AllarmeAssenzePage> createState() => _AllarmeAssenzePageState();
}

class _AllarmeAssenzePageState extends ConsumerState<AllarmeAssenzePage> {
  late int _soglia;

  @override
  void initState() {
    super.initState();
    _soglia =
        ref
                .read(parishConfigRepositoryProvider)
                .getConfig()
                .sogliaAssenzeConsecutive ==
            0
        ? ParishConfig.defaultSogliaAssenzeConsecutive
        : ref
              .read(parishConfigRepositoryProvider)
              .getConfig()
              .sogliaAssenzeConsecutive;
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// Dialog per personalizzare la soglia di assenze consecutive.
  Future<void> _editSoglia() async {
    final controller = TextEditingController(text: _soglia.toString());
    final config = ref.read(parishConfigRepositoryProvider).getConfig();

    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Soglia assenze prolungate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vengono evidenziati i ragazzi con almeno questo numero di '
              'assenze consecutive. Soglia consigliata: 3.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () {
                    final v = int.tryParse(controller.text) ?? 3;
                    if (v > 1) controller.text = (v - 1).toString();
                  },
                ),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: controller,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    final v = int.tryParse(controller.text) ?? 3;
                    controller.text = (v + 1).toString();
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v != null && v >= 2) {
                Navigator.pop(context, v);
              } else {
                _snack('Inserisci un valore >= 2.');
              }
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      try {
        await ref
            .read(parishConfigRepositoryProvider)
            .save(config.copyWith(sogliaAssenzeConsecutive: result));
        setState(() => _soglia = result);
        _snack('Soglia aggiornata a $result assenze consecutive.');
      } catch (e) {
        _snack('Errore: $e');
      }
    }
  }

  /// Vuota tutte le presenze per classe nel box (refresh manuale).
  Future<void> _refresh() async {
    setState(() {});
  }

  Future<void> _contactFamily(AllertaAssenza alert) async {
    final student = (await StudentsRepository().getAllStudentsSync())
        .where((s) => s.id == alert.studentId)
        .firstOrNull;
    final phone = student?.motherPhone.isNotEmpty == true
        ? student!.motherPhone
        : (student?.fatherPhone.isNotEmpty == true
              ? student!.fatherPhone
              : null);
    if (phone == null) {
      if (!mounted) return;
      _snack('Nessun recapito famigliare registrato per ${alert.fullName}.');
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contatta la famiglia'),
        content: Text('Vuoi chiamare ${alert.fullName} al numero $phone?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.phone_rounded, size: 18),
            label: const Text('Chiama'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final ok = await launchUrl(uri);
      if (!ok) _snack('Impossibile avviare la chiamata.');
    } catch (_) {
      _snack('Impossibile avviare la chiamata.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(parrocchiaClassesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _header(isDark),
          const SizedBox(height: 12),
          classesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Errore: $e'),
            data: (classes) {
              final alertsFuture = const PresenzeParrocchialiService()
                  .rilevaIstanza(threshold: _soglia, classes: classes);
              return FutureBuilder<List<AllertaAssenza>>(
                future: alertsFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _alertList(snapshot.data!, isDark);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _header(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainer
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Allerta assenze prolungate',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isDark ? Colors.white : const Color(0xFF174A7E),
                  ),
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.tune_rounded, size: 16),
                label: Text('Soglia: $_soglia'),
                onPressed: _editSoglia,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Ragazzi con N assenze consecutive (da impostare) vengono '
            'evidenziati per permettere un contatto diretto con le famiglie.',
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _alertList(List<AllertaAssenza> alerts, bool isDark) {
    if (alerts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Column(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              color: Colors.green,
              size: 44,
            ),
            SizedBox(height: 10),
            Text(
              'Nessun allarme attivo. Tutti i ragazzi sono sotto la soglia.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${alerts.length} ragazzo/i oltre la soglia',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.grey.shade300 : Colors.black87,
          ),
        ),
        const SizedBox(height: 10),
        for (final alert in alerts) _alertCard(alert, isDark),
      ],
    );
  }

  Widget _alertCard(AllertaAssenza alert, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainer
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Color(0xFFFFE0B2),
            child: Icon(Icons.person_rounded, color: Color(0xFFE65100)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${alert.className} · ${alert.assenzeConsecutive} assenze '
                  'consecutive (tot. ${alert.totaleAssenze})',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Contatta la famiglia',
            icon: Icon(
              Icons.phone_in_talk_rounded,
              color: isDark ? Colors.orange.shade300 : const Color(0xFFE65100),
            ),
            onPressed: () => _contactFamily(alert),
          ),
        ],
      ),
    );
  }
}
