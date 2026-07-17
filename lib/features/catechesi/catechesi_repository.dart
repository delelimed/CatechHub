import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models/attachment_parent_type.dart';
import '../../shared/models/catechesi_model.dart';
import '../attachments/attachments_repository.dart';

/// Provider Riverpod che espone un'istanza singleton di [CatechesiRepository].
///
/// Consente a qualsiasi widget dell'albero di accesso alle operazioni CRUD
/// sulle catechesi senza dover istanziare direttamente il repository.
final catechesiRepositoryProvider = Provider<CatechesiRepository>((ref) {
  return CatechesiRepository();
});

/// Repository per le operazioni CRUD sulle schede catechesi archiviate nel
/// box Hive `catechesi` del database locale cifrato di CateREG.
///
/// Fornisce sia accesso in stream (per UI reattiva) sia accesso sincrono,
/// oltre a operazioni di scrittura, aggiornamento, eliminazione con cascata
/// (cancella anche gli allegati associati) e ricerca testuale.
class CatechesiRepository {
  final _box = LocalDatabase.catechesi();

  /// Restituisce uno stream reattivo che emette la lista completa delle
  /// catechesi ogni volta che il box Hive subisce modifiche. Utilizzato
  /// dal widget [CatechesiPage] per aggiornare la UI in tempo reale.
  Stream<List<Catechesi>> watchCatechesi() {
    return LocalDatabase.watchList(
      _box,
      (id, data) => Catechesi.fromMap(id, data),
    );
  }

  /// Restituisce l'elenco completo delle catechesi in modalità sincrona
  /// (senza stream). Utile per contesti in cui serve un'istantanea dei dati.
  List<Catechesi> getCatechesiSync() {
    return LocalDatabase.values(
      _box,
      (id, data) => Catechesi.fromMap(id, data),
    );
  }

  /// Aggiunge una nuova scheda catechesi al database. Se l'ID è vuoto,
  /// genera automaticamente un nuovo identificativo tramite
  /// [LocalDatabase.newId].
  Future<void> addCatechesi(Catechesi c) async {
    final id = c.id.isEmpty ? LocalDatabase.newId('catechesi') : c.id;
    await _box.put(id, c.toMap());
  }

  /// Aggiorna una scheda catechesi esistente, sovrascrivendo il record
  /// corrispondente all'ID specificato nel box Hive.
  Future<void> updateCatechesi(String id, Catechesi c) async {
    await _box.put(id, c.toMap());
  }

  /// Elimina una scheda catechesi e tutti gli allegati a essa associati
  /// (operazione di cascade delete su [AttachmentsRepository]).
  Future<void> deleteCatechesi(String id) async {
    await AttachmentsRepository().deleteAllForParent(
      parentId: id,
      parentType: AttachmentParentType.catechesi,
    );
    await _box.delete(id);
  }

  /// Esegue una ricerca testuale su titolo, tag, riferimenti biblici e
  /// riferimenti sitografici. La ricerca è case-insensitive. Se la query
  /// è vuota restituisce tutte le catechesi.
  List<Catechesi> search(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return getCatechesiSync();

    return getCatechesiSync().where((c) {
      final matchesTitle = c.title.toLowerCase().contains(q);
      final matchesTag = c.tags.any((t) => t.toLowerCase().contains(q));
      final matchesBiblical = c.biblicalReferences.any((b) => b.toLowerCase().contains(q));
      final matchesWebsite = c.websiteReferences.any((w) => w.toLowerCase().contains(q));
      return matchesTitle || matchesTag || matchesBiblical || matchesWebsite;
    }).toList();
  }
}
