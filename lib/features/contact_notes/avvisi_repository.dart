import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/avviso_template_model.dart';

final avvisiRepoProvider = Provider<AvvisiRepository>((ref) {
  return AvvisiRepository();
});

final avvisiTemplatesProvider = StreamProvider<List<AvvisoTemplate>>((ref) {
  final repo = ref.watch(avvisiRepoProvider);
  return repo.watchAll();
});

class AvvisiRepository {
  Box<Map> get _box => LocalDatabase.avvisi();

  List<AvvisoTemplate> getAll() {
    return LocalDatabase.values(_box, (id, data) => AvvisoTemplate.fromMap(id, data));
  }

  Stream<List<AvvisoTemplate>> watchAll() {
    return LocalDatabase.watchList(_box, (id, data) => AvvisoTemplate.fromMap(id, data));
  }

  /// Stream in tempo reale degli avvisi appartenenti alla classe
  /// identificata dal [classUniqueCode].
  Stream<List<AvvisoTemplate>> watchByClass(String classUniqueCode) {
    return LocalDatabase.watchList(_box, (id, data) => AvvisoTemplate.fromMap(id, data))
        .map((templates) => templates
            .where((t) => t.classUniqueCode == classUniqueCode)
            .toList());
  }

  /// Lettura sincrona degli avvisi di una classe.
  List<AvvisoTemplate> getByClassSync(String classUniqueCode) {
    return LocalDatabase.values(_box, (id, data) => AvvisoTemplate.fromMap(id, data))
        .where((t) => t.classUniqueCode == classUniqueCode)
        .toList();
  }

  Future<void> save(AvvisoTemplate template) async {
    final id = template.id.isEmpty
        ? LocalDatabase.newId('avviso_template')
        : template.id;
    await _box.put(id, template.toMap());
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
  }
}
