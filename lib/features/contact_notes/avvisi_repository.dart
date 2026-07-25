import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/avviso_template_model.dart';

final avvisiRepoProvider = Provider<AvvisiRepository>((ref) {
  return AvvisiRepository();
});

class AvvisiRepository {
  Box<Map> get _box => LocalDatabase.avvisi();

  List<AvvisoTemplate> getAll() {
    return LocalDatabase.values(_box, (id, data) => AvvisoTemplate.fromMap(id, data));
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
