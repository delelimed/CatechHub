import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../core/storage/local_database.dart';

final syncConflictsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final box = LocalDatabase.syncConflicts();
  yield _loadConflicts(box);
  await for (final _ in box.watch()) {
    yield _loadConflicts(box);
  }
});

List<Map<String, dynamic>> _loadConflicts(Box<Map> box) {
  final conflicts = <Map<String, dynamic>>[];
  for (final key in box.keys) {
    final raw = box.get(key);
    if (raw == null) continue;
    final data = Map<String, dynamic>.from(raw);
    if (data['resolved'] == true) continue;
    conflicts.add(data);
  }
  return conflicts;
}

class ConflictResolutionPage extends ConsumerWidget {
  const ConflictResolutionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflicts = ref.watch(syncConflictsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Conflitti sync')),
      body: conflicts.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 64, color: Colors.green),
                  SizedBox(height: 16),
                  Text('Nessun conflitto presente',
                      style: TextStyle(fontSize: 16)),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (ctx, i) => _ConflictCard(conflict: items[i]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Errore')),
      ),
    );
  }
}

class _ConflictCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> conflict;
  const _ConflictCard({required this.conflict});

  @override
  ConsumerState<_ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends ConsumerState<_ConflictCard> {
  @override
  Widget build(BuildContext context) {
    final c = widget.conflict;
    final fields = (c['conflictingFields'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final localData = Map<String, dynamic>.from(c['localData'] ?? {});
    final remoteData = Map<String, dynamic>.from(c['remoteData'] ?? {});

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        leading: const Icon(Icons.warning_amber, color: Colors.orange),
        title: Text(
          _labelFor(c['boxName'] as String? ?? ''),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('Record: ${c['recordId']}'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Campi in conflitto:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...fields.map((f) => _FieldConflict(
                      field: f,
                      localValue: localData[f]?.toString() ?? '(vuoto)',
                      remoteValue: remoteData[f]?.toString() ?? '(vuoto)',
                    )),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.my_location),
                        label: const Text('Tieni mio'),
                        onPressed: () =>
                            _resolve(c, localData, fields, 'local'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.sync),
                        label: const Text('Tieni remoto'),
                        onPressed: () =>
                            _resolve(c, remoteData, fields, 'remote'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _labelFor(String boxName) {
    switch (boxName) {
      case 'students_box':
        return 'Studente';
      case 'classes_box':
        return 'Classe';
      case 'attendance_box':
        return 'Presenze';
      case 'planning_box':
        return 'Incontro';
      case 'documents_box':
        return 'Documento';
      case 'attachments_box':
        return 'Allegato';
      case 'contact_notes_box':
        return 'Nota contatto';
      case 'catechesi_box':
        return 'Catechesi';
      case 'student_daily_notes_box':
        return 'Nota giornaliera';
      default:
        return boxName;
    }
  }

  Future<void> _resolve(
    Map<String, dynamic> conflict,
    Map<String, dynamic> chosenData,
    List<String> fields,
    String choice,
  ) async {
    final boxName = conflict['boxName'] as String;
    final recordId = conflict['recordId'] as String;

    try {
      final box = Hive.box<Map>(boxName);
      final existing = LocalDatabase.toStringDynamicMap(box.get(recordId));
      for (final f in fields) {
        if (chosenData.containsKey(f)) {
          existing[f] = chosenData[f];
        }
      }
      existing['updatedAt'] = DateTime.now().toUtc().toIso8601String();
      existing['lastModifiedBy'] = choice == 'local'
          ? 'Risolto (scelto locale)'
          : 'Risolto (scelto remoto)';
      await box.put(recordId, existing);

      final conflictsBox = LocalDatabase.syncConflicts();
      final key = '$boxName:$recordId';
      final stored = Map<String, dynamic>.from(conflictsBox.get(key) ?? {});
      stored['resolved'] = true;
      stored['resolvedAt'] = DateTime.now().toUtc().toIso8601String();
      stored['resolution'] = choice;
      await conflictsBox.put(key, stored);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Conflitto risolto: $choice'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _FieldConflict extends StatelessWidget {
  final String field;
  final String localValue;
  final String remoteValue;

  const _FieldConflict({
    required this.field,
    required this.localValue,
    required this.remoteValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _ValueChip(label: 'Locale', value: localValue),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _ValueChip(
                    label: 'Remoto', value: remoteValue, isRemote: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  final String label;
  final String value;
  final bool isRemote;

  const _ValueChip({
    required this.label,
    required this.value,
    this.isRemote = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isRemote
            ? Colors.blue.withValues(alpha: 0.1)
            : Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isRemote ? Colors.blue : Colors.green)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(fontSize: 12),
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
