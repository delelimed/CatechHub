import 'package:hive_flutter/hive_flutter.dart';

import '../../features/archive/historical_record_repository.dart';
import '../../features/sync/p2p/p2p_security_service.dart';
import '../../shared/models/attachment_model.dart';
import '../../shared/models/attachment_parent_type.dart';
import '../security/security_manager.dart';
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

  /// Associazioni con altri catechisti e dispositivi.
  associazioni,
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
    required this.associations,
  });

  final int students;
  final int attendance;
  final int planning;
  final int catechesi;
  final int contactNotes;
  final int attachments;
  final int documents;
  final int deliveries;
  final int associations;

  int get total => students + attendance + planning + catechesi + contactNotes + attachments + documents + deliveries + associations;
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
  /// Conta i record per una specifica classe (o totali se [classId] è null).
  DataDeletionCounts getCounts({String? classId}) {
    if (classId == null) {
      return DataDeletionCounts(
        students: LocalDatabase.students().length,
        attendance: LocalDatabase.attendance().length,
        planning: LocalDatabase.planning().length,
        catechesi: LocalDatabase.catechesi().length,
        contactNotes: LocalDatabase.contactNotes().length,
        attachments: LocalDatabase.attachments().length,
        documents: LocalDatabase.documents().length,
        deliveries: LocalDatabase.documentDeliveries().length,
        associations: LocalDatabase.trustedDevices().length,
      );
    }

    final studentIdsInClass = _getStudentIdsInClass(classId);
    return DataDeletionCounts(
      students: studentIdsInClass.length,
      attendance: _countAttendanceForClass(classId),
      planning: _countPlanningForClass(classId),
      catechesi: _countByUniqueCode(LocalDatabase.catechesi(), classId),
      contactNotes: _countContactNotesForStudents(studentIdsInClass),
      attachments: 0,
      documents: _countByUniqueCode(LocalDatabase.documents(), classId),
      deliveries: 0,
      associations: LocalDatabase.trustedDevices().length,
    );
  }

  List<String> _getStudentIdsInClass(String classId) {
    final classData = LocalDatabase.classes().get(classId);
    if (classData == null) return [];
    final map = LocalDatabase.toStringDynamicMap(classData);
    return (map['studentIds'] as List? ?? []).map((e) => e.toString()).toList();
  }

  int _countAttendanceForClass(String classId) {
    final box = LocalDatabase.attendance();
    int count = 0;
    for (final key in box.keys) {
      final data = LocalDatabase.toStringDynamicMap(box.get(key));
      if (data['classId'] == classId) count++;
    }
    return count;
  }

  int _countPlanningForClass(String classId) {
    final box = LocalDatabase.planning();
    int count = 0;
    for (final key in box.keys) {
      final data = LocalDatabase.toStringDynamicMap(box.get(key));
      if (data['classId'] == classId) count++;
    }
    return count;
  }

  int _countContactNotesForStudents(List<String> studentIds) {
    if (studentIds.isEmpty) return 0;
    final studentSet = studentIds.toSet();
    final box = LocalDatabase.contactNotes();
    int count = 0;
    for (final key in box.keys) {
      final data = LocalDatabase.toStringDynamicMap(box.get(key));
      if (studentSet.contains(data['studentId'])) count++;
    }
    return count;
  }

  int _countByUniqueCode(Box<Map> box, String classId) {
    final classData = LocalDatabase.classes().get(classId);
    if (classData == null) return 0;
    final classMap = LocalDatabase.toStringDynamicMap(classData);
    final uniqueCode = classMap['uniqueCode'] as String?;
    if (uniqueCode == null || uniqueCode.isEmpty) return box.length;
    int count = 0;
    for (final key in box.keys) {
      final data = LocalDatabase.toStringDynamicMap(box.get(key));
      if (data['classUniqueCode'] == uniqueCode) count++;
    }
    return count;
  }

  /// Esegue la cancellazione selettiva delle categorie richieste per una
  /// specifica classe. Se [classId] è null, opera sull'intero database.
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
  Future<void> deleteSelected(Set<DataDeletionCategory> categories, {String? classId}) async {
    if (categories.isEmpty) {
      throw Exception('Seleziona almeno una voce da cancellare');
    }

    if (classId == null) {
      await _deleteAll(categories);
      return;
    }

    await _deleteForClass(categories, classId);
  }

  Future<void> _deleteAll(Set<DataDeletionCategory> categories) async {
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
      // L'archivio storico è legato agli studenti: lo svuoto con l'anagrafica.
      await LocalDatabase.historicalRecords().clear();
    }

    if (categories.contains(DataDeletionCategory.associazioni)) {
      await P2PSecurityService().removeAllAssociations();
    }
  }

  Future<void> _deleteForClass(Set<DataDeletionCategory> categories, String classId) async {
    final classData = LocalDatabase.classes().get(classId);
    final classMap = classData != null ? LocalDatabase.toStringDynamicMap(classData) : null;
    final uniqueCode = classMap?['uniqueCode'] as String?;
    final studentIdsInClass = _getStudentIdsInClass(classId);
    final studentSet = studentIdsInClass.toSet();

    if (categories.contains(DataDeletionCategory.anagrafica)) {
      for (final sid in studentIdsInClass) {
        await LocalDatabase.students().delete(sid);
      }
      // Rimuove anche gli snapshot storici dei ragazzi cancellati.
      await HistoricalRecordRepository()
          .deleteRecordsForStudents(studentIdsInClass);
      if (classMap != null) {
        classMap['studentIds'] = <String>[];
        await LocalDatabase.classes().put(classId, classMap);
      }
      final deliveriesBox = LocalDatabase.documentDeliveries();
      for (final key in deliveriesBox.keys.toList()) {
        final data = LocalDatabase.toStringDynamicMap(deliveriesBox.get(key));
        data.removeWhere((k, _) => studentSet.contains(k));
        if (data.isEmpty) {
          await deliveriesBox.delete(key);
        } else {
          await deliveriesBox.put(key, data);
        }
      }
    }

    if (categories.contains(DataDeletionCategory.presenze)) {
      final attBox = LocalDatabase.attendance();
      for (final key in attBox.keys.toList()) {
        final data = LocalDatabase.toStringDynamicMap(attBox.get(key));
        if (data['classId'] == classId) {
          await attBox.delete(key);
        }
      }
    }

    if (categories.contains(DataDeletionCategory.giornate)) {
      final planBox = LocalDatabase.planning();
      final keysToDelete = <dynamic>[];
      for (final key in planBox.keys) {
        final data = LocalDatabase.toStringDynamicMap(planBox.get(key));
        if (data['classId'] == classId) keysToDelete.add(key);
      }
      for (final key in keysToDelete) {
        await planBox.delete(key);
        await LocalDatabase.attendance().delete(key);
        await LocalDatabase.meetingCatechesi().delete(key);
      }
    }

    if (categories.contains(DataDeletionCategory.catechesi)) {
      await _deleteByUniqueCode(LocalDatabase.catechesi(), uniqueCode);
      if (uniqueCode == null || uniqueCode.isEmpty) {
        await LocalDatabase.meetingCatechesi().clear();
      }
    }

    if (categories.contains(DataDeletionCategory.noteContatto)) {
      final cnBox = LocalDatabase.contactNotes();
      for (final key in cnBox.keys.toList()) {
        final data = LocalDatabase.toStringDynamicMap(cnBox.get(key));
        if (studentSet.contains(data['studentId'])) {
          await cnBox.delete(key);
        }
      }
    }

    if (categories.contains(DataDeletionCategory.documenti)) {
      await _deleteByUniqueCode(LocalDatabase.documents(), uniqueCode);
      if (uniqueCode != null && uniqueCode.isNotEmpty) {
        final deliveriesBox = LocalDatabase.documentDeliveries();
        for (final key in deliveriesBox.keys.toList()) {
          final data = LocalDatabase.toStringDynamicMap(deliveriesBox.get(key));
          data.removeWhere((k, _) => studentSet.contains(k));
          if (data.isEmpty) {
            await deliveriesBox.delete(key);
          } else {
            await deliveriesBox.put(key, data);
          }
        }
      } else {
        await LocalDatabase.documents().clear();
        await LocalDatabase.documentDeliveries().clear();
      }
    }

    if (categories.contains(DataDeletionCategory.allegati)) {
      await _deleteAllAttachments();
    }
  }

  Future<void> _deleteByUniqueCode(Box<Map> box, String? uniqueCode) async {
    if (uniqueCode == null || uniqueCode.isEmpty) {
      await box.clear();
      return;
    }
    for (final key in box.keys.toList()) {
      final data = LocalDatabase.toStringDynamicMap(box.get(key));
      if (data['classUniqueCode'] == uniqueCode) {
        await box.delete(key);
      }
    }
  }

  Future<void> _deleteAnagrafica() async {
    await LocalDatabase.students().clear();
    final classesBox = LocalDatabase.classes();
    for (final key in classesBox.keys.toList()) {
      final data = LocalDatabase.toStringDynamicMap(classesBox.get(key));
      data['studentIds'] = <String>[];
      await classesBox.put(key, data);
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

  /// CANCELLAZIONE TOTALE: elimina TUTTI i dati, le chiavi crittografiche,
  /// le associazioni P2P, e resetta l'app allo stato di onboarding.
  ///
  /// Questa operazione:
  /// 1. Svuota tutti i box Hive (classi, studenti, presenze, ecc.)
  /// 2. Elimina tutti i file vault cifrati (allegati)
  /// 3. Rimuove tutte le associazioni P2P e le chiavi di sincronizzazione
  /// 4. Cancella i segreti e la chiave master dallo StrongBox/TEE
  /// 5. Pulisce i dati di autenticazione e sessione
  /// 6. Resetta il flag onboarding_completed per tornare all'onboarding
  ///
  /// Dopo questa chiamata, l'app DEVE essere reindirizzata alla home
  /// per innescare il redirect verso l'onboarding.
  Future<void> deleteAllAndReset() async {
    // 1. Elimina tutti gli allegati (file vault + metadati)
    await _deleteAllAttachments();

    // 2. Svuota tutti i box dati (non auth)
    await LocalDatabase.students().clear();
    await LocalDatabase.classes().clear();
    await LocalDatabase.planning().clear();
    await LocalDatabase.attendance().clear();
    await LocalDatabase.documents().clear();
    await LocalDatabase.documentDeliveries().clear();
    await LocalDatabase.contactNotes().clear();
    await LocalDatabase.catechesi().clear();
    await LocalDatabase.meetingCatechesi().clear();
    await LocalDatabase.studentDailyNotes().clear();
    await LocalDatabase.trustedDevices().clear();
    await LocalDatabase.meetingNotifications().clear();
    await LocalDatabase.avvisi().clear();
    await LocalDatabase.parishConfig().clear();
    await LocalDatabase.historicalRecords().clear();

    // 3. Rimuove tutte le associazioni P2P, identità locale e chiavi crittografiche
    await P2PSecurityService().resetAllSecurityData();

    // 4. Pulisce il box di autenticazione e resetta onboarding
    await LocalDatabase.auth().clear();
    await LocalDatabase.auth().put('onboarding_completed', false);

    // 5. Cancella la chiave master dallo StrongBox/TEE (FlutterSecureStorage)
    //    Questo forza la rigenerazione della chiave al prossimo avvio.
    await SecurityManager.instance.resetForTesting();
  }
}
