import '../../core/storage/local_database.dart';
import '../../shared/utils/auth_utils.dart';

/// Repository per la gestione dei documenti (certificati, autorizzazioni,
/// moduli, fogli informativi) e delle loro consegne in CateREG.
///
/// Si appoggia a due box Hive distinti:
/// - `documents`: memorizza i metadati di ciascun documento (titolo, data creazione)
/// - `documentDeliveries`: per ogni documento, una mappa studente -> {givenOutAt, receivedAt}
///
/// I metodi sono disponibili sia in versione sincrona che in stream per
/// supportare gli aggiornamenti reattivi dell'interfaccia utente tramite Riverpod.
class DocumentsRepository {
  final _documentsBox = LocalDatabase.documents();
  final _deliveriesBox = LocalDatabase.documentDeliveries();

  /// Restituisce uno stream della lista di tutti i documenti, ordinati per
  /// data di creazione decrescente (dal più recente).
  Stream<List<Map<String, dynamic>>> getDocuments() {
    return LocalDatabase.watchList(
      _documentsBox,
      (id, data) => {'id': id, ...data},
    ).map((documents) {
      documents.sort((a, b) {
        final aDate = DateTime.tryParse(a['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(b['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      return documents;
    });
  }

  /// Versione sincrona di [getDocuments]. Restituisce la lista completa dei
  /// documenti senza attivare un listener sullo stream.
  List<Map<String, dynamic>> getDocumentsSync() {
    final documents = LocalDatabase.values(
      _documentsBox,
      (id, data) => {'id': id, ...data},
    );
    documents.sort((a, b) {
      final aDate = DateTime.tryParse(a['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse(b['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return documents;
  }

  /// Crea un nuovo documento con il titolo indicato e lo persiste su Hive.
  /// Viene generato un ID univoco (formato 'document_xxx') e il timestamp
  /// corrente viene salvato come 'createdAt'.
  Future<void> addDocument(String title) async {
    final id = LocalDatabase.newId('document');
    final catechistName = getCurrentCatechistName();
    await _documentsBox.put(id, {
      'title': title,
      'createdAt': DateTime.now().toIso8601String(),
      'lastModifiedBy': catechistName,
    });
  }

  /// Aggiorna il titolo di un documento esistente.
  Future<void> updateDocument(String id, String newTitle) async {
    final data = _documentsBox.get(id);
    if (data != null) {
      final updated = Map<String, dynamic>.from(data);
      updated['title'] = newTitle;
      updated['lastModifiedBy'] = getCurrentCatechistName();
      await _documentsBox.put(id, updated);
    }
  }

  /// Elimina un documento e tutte le sue consegne associate da Hive.
  /// Rimuove sia la voce dal box `documents` che quella dal box
  /// `documentDeliveries` (identificata dallo stesso [id]).
  Future<void> deleteDocument(String id) async {
    await _documentsBox.delete(id);
    await _deliveriesBox.delete(id);
  }

  /// Restituisce uno stream della mappa delle consegne per il documento
  /// identificato da [docId]. Il primo yield emette immediatamente il valore
  /// corrente; i successivi vengono emessi ad ogni modifica del box Hive.
  Stream<Map<String, dynamic>> getDeliveries(String docId) async* {
    yield getDeliveriesSync(docId);
    yield* _deliveriesBox.watch(key: docId).map((_) => getDeliveriesSync(docId));
  }

  /// Versione sincrona di [getDeliveries]. Legge la mappa delle consegne
  /// direttamente dal box Hive senza attivare un listener.
  Map<String, dynamic> getDeliveriesSync(String docId) {
    return LocalDatabase.toStringDynamicMap(_deliveriesBox.get(docId));
  }

  /// Registra o annulla la consegna (givenOut) del documento a uno studente.
  ///
  /// Se [isCurrentlyGiven] è true, annulla sia la consegna che l'eventuale
  /// ritiro (azzera entrambi i timestamp). Se false, registra il timestamp
  /// corrente come givenOutAt. I dati vengono salvati nella mappa delle
  /// consegne del documento nel box `documentDeliveries`.
  Future<void> setGivenOut({
    required String docId,
    required String studentId,
    required bool isCurrentlyGiven,
  }) async {
    final deliveries = getDeliveriesSync(docId);
    final current = Map<String, dynamic>.from(deliveries[studentId] as Map? ?? {});

    if (isCurrentlyGiven) {
      current['givenOutAt'] = null;
      current['receivedAt'] = null;
    } else {
      current['givenOutAt'] = DateTime.now().toIso8601String();
    }

    final catechistName = getCurrentCatechistName();
    current['lastModifiedBy'] = catechistName;
    deliveries[studentId] = current;
    await _deliveriesBox.put(docId, deliveries);
  }

  /// Registra o annulla il ritiro (received) del documento da uno studente.
  ///
  /// Se [isCurrentlyReceived] è true, annulla il ritiro (azzera receivedAt).
  /// Se false, registra il timestamp corrente come receivedAt. Il pulsante
  /// corrispondente nell'UI è abilitato solo se il documento è già stato
  /// consegnato (givenOutAt non nullo).
  Future<void> setReceived({
    required String docId,
    required String studentId,
    required bool isCurrentlyReceived,
  }) async {
    final deliveries = getDeliveriesSync(docId);
    final current = Map<String, dynamic>.from(deliveries[studentId] as Map? ?? {});

    if (isCurrentlyReceived) {
      current['receivedAt'] = null;
    } else {
      current['receivedAt'] = DateTime.now().toIso8601String();
    }

    final catechistName = getCurrentCatechistName();
    current['lastModifiedBy'] = catechistName;
    deliveries[studentId] = current;
    await _deliveriesBox.put(docId, deliveries);
  }

  /// Esonera o riattiva uno studente dalla consegna del documento.
  ///
  /// Se [isCurrentlyExonerated] è true, revoca l'esonero (azzera exoneratedAt).
  /// Se false, registra il timestamp corrente come exoneratedAt.
  /// Lo studente esonerato viene mostrato nella UI in grigio con scritta "Esonerato".
  Future<void> setExonerated({
    required String docId,
    required String studentId,
    required bool isCurrentlyExonerated,
  }) async {
    final deliveries = getDeliveriesSync(docId);
    final current = Map<String, dynamic>.from(deliveries[studentId] as Map? ?? {});

    if (isCurrentlyExonerated) {
      current.remove('exoneratedAt');
    } else {
      current['exoneratedAt'] = DateTime.now().toIso8601String();
    }

    final catechistName = getCurrentCatechistName();
    current['lastModifiedBy'] = catechistName;
    deliveries[studentId] = current;
    await _deliveriesBox.put(docId, deliveries);
  }
}
