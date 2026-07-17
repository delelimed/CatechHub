import '../../shared/models/attachment_model.dart';
import '../../shared/models/attachment_parent_type.dart';
import 'encrypted_file_storage.dart';
import 'local_database.dart';

/// Categorie di dati cancellabili selettivamente dall'utente.
///
/// CONTESTO PROGETTO:
/// CateREG permette di cancellare dati per categoria (anagrafica, presenze,
/// giornate, allegati, catechesi, note contatto) senza dover resettare
/// l'intera app. Questo è utile ad esempio a inizio anno catechistico
/// per eliminare solo le presenze mantenendo l'anagrafica dei ragazzi.
enum DataDeletionCategory {
  /// Dati anagrafici: ragazzi, classi/gruppi, consegna documenti.
  anagrafica,

  /// Presenze/appelli: registrazioni giornaliere delle presenze.
  presenze,

  /// Giornate di catechesi: pianificazione degli incontri.
  giornate,

  /// Catechesi: argomenti e contenuti delle catechesi.
  catechesi,

  /// Note di contatto: comunicazioni con le famiglie.
  noteContatto,

  /// Allegati: file vault (foto, documenti, PDF) + relativi metadati.
  allegati,

  /// Documenti e consegne: certificati, autorizzazioni, consegne.
  documenti,
}

/// Resoconto delle quantità di dati presenti prima della cancellazione.
/// Mostrato all'utente nella UI (Impostazioni -> Elimina Dati) per
/// informarlo su cosa verrà rimosso.
class DataDeletionCounts {
  const DataDeletionCounts({
    required this.students,
    required this.attendance,
    required this.planning,
    required this.catechesi,
    required this.contactNotes,
    required this.attachments,
    required this.documents,
    required this.deliveries,
  });

  final int students;
  final int attendance;
  final int planning;
  final int catechesi;
  final int contactNotes;
  final int attachments;
  final int documents;
  final int deliveries;

  int get total => students + attendance + planning + catechesi + contactNotes + attachments + documents + deliveries;
}

/// Servizio per la cancellazione selettiva dei dati.
///
/// COLLABORAZIONI:
/// - [LocalDatabase]: accesso ai Box Hive per cancellare metadati.
/// - [EncryptedFileStorage]: eliminazione dei file vault fisici.
/// - [AttachmentModel]: lettura dei metadati per filtrare allegati
///   associati a una categoria (es. allegati dei ragazzi vs giornate).
///
/// FLUSSO:
/// 1. getCounts() -> conta i record esistenti per ogni categoria.
/// 2. deleteSelected() -> cancella nell'ordine: allegati (file + metadati),
///    presenze, giornate, anagrafica con svuotamento classi e consegne doc.
///
/// NOTA: L'ordine di cancellazione è importante: gli allegati vengono
/// rimossi PRIMA dei genitori (studenti/giornate) per evitare dati orfani
/// nel vault cifrato.
class DataDeletionService {
  /// Conta i record attuali per ogni categoria di dati.
  /// Usato dalla UI per mostrare un riepilogo prima della conferma.
  DataDeletionCounts getCounts() {
    return DataDeletionCounts(
      students: LocalDatabase.students().length,
      attendance: LocalDatabase.attendance().length,
      planning: LocalDatabase.planning().length,
      catechesi: LocalDatabase.catechesi().length,
      contactNotes: LocalDatabase.contactNotes().length,
      attachments: LocalDatabase.attachments().length,
      documents: LocalDatabase.documents().length,
      deliveries: LocalDatabase.documentDeliveries().length,
    );
  }

  /// Esegue la cancellazione selettiva delle categorie richieste.
  ///
  /// ORDINE DI ESECUZIONE:
  /// 1. Allegati: se richiesto, elimina TUTTI i file vault + metadati.
  ///    Se NON richiesto ma vengono cancellati studenti o giornate,
  ///    elimina SOLO gli allegati associati a quei genitori (per evitare
  ///    file orfani senza riferimenti nel DB).
  /// 2. Presenze: pulizia del Box attendance.
  /// 3. Giornate: pulizia del Box planning.
  /// 4. Anagrafica: pulizia studenti, classi (con reset lista IDs) e
  ///    consegna documenti.
  Future<void> deleteSelected(Set<DataDeletionCategory> categories) async {
    if (categories.isEmpty) {
      throw Exception('Seleziona almeno una voce da cancellare');
    }

    if (categories.contains(DataDeletionCategory.allegati)) {
      await _deleteAllAttachments();
    } else {
      if (categories.contains(DataDeletionCategory.anagrafica)) {
        await _deleteAttachmentsForParentType(AttachmentParentType.student);
      }
      if (categories.contains(DataDeletionCategory.giornate)) {
        await _deleteAttachmentsForParentType(AttachmentParentType.meeting);
      }
    }

    if (categories.contains(DataDeletionCategory.presenze)) {
      await LocalDatabase.attendance().clear();
    }

    if (categories.contains(DataDeletionCategory.giornate)) {
      await LocalDatabase.planning().clear();
      await LocalDatabase.meetingCatechesi().clear();
    }

    if (categories.contains(DataDeletionCategory.catechesi)) {
      await LocalDatabase.catechesi().clear();
      await LocalDatabase.meetingCatechesi().clear();
    }

    if (categories.contains(DataDeletionCategory.noteContatto)) {
      await LocalDatabase.contactNotes().clear();
    }

    if (categories.contains(DataDeletionCategory.documenti)) {
      await LocalDatabase.documents().clear();
      await LocalDatabase.documentDeliveries().clear();
    }

    if (categories.contains(DataDeletionCategory.anagrafica)) {
      await _deleteAnagrafica();
    }
  }

  /// Cancella anagrafica: studenti, classi (con reset IDs) e consegne doc.
  /// Le classi non vengono cancellate ma solo svuotate dei riferimenti agli
  /// studenti, per mantenere la struttura organizzativa dell'anno.
  Future<void> _deleteAnagrafica() async {
    await LocalDatabase.students().clear();

    final classesBox = LocalDatabase.classes();
    for (final classKey in classesBox.keys) {
      final data = LocalDatabase.toStringDynamicMap(classesBox.get(classKey));
      data['studentIds'] = <String>[];
      await classesBox.put(classKey, data);
    }

    await LocalDatabase.documentDeliveries().clear();
  }

  /// Elimina TUTTI gli allegati: file vault + metadati Box.
  /// Esegue una doppia pulizia: prima i file uno per uno (per sicurezza),
  /// poi svuota il Box dei metadati, poi elimina l'intera directory vault
  /// (per rimuovere eventuali file orfani).
  Future<void> _deleteAllAttachments() async {
    final box = LocalDatabase.attachments();
    for (final key in box.keys.toList()) {
      await EncryptedFileStorage.delete(key.toString());
    }
    await box.clear();
    await EncryptedFileStorage.deleteAll();
  }

  /// Elimina solo gli allegati associati a un dato tipo genitore.
  /// Esempio: se si cancellano le giornate, vengono rimossi gli allegati
  /// con parentType == 'meeting', ma NON quelli dei ragazzi.
  /// Questo evita di perdere foto/documenti importanti dei ragazzi quando
  /// si puliscono solo le giornate.
  Future<void> _deleteAttachmentsForParentType(String parentType) async {
    final box = LocalDatabase.attachments();
    final toRemove = <String>[];

    for (final key in box.keys) {
      final id = key.toString();
      final data = LocalDatabase.toStringDynamicMap(box.get(key));
      final attachment = Attachment.fromMap(id, data);
      if (attachment.parentType == parentType) {
        toRemove.add(id);
      }
    }

    for (final id in toRemove) {
      await EncryptedFileStorage.delete(id);
      await box.delete(id);
    }
  }
}
