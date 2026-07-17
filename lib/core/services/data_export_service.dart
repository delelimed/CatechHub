// ══════════════════════════════════════════════════════════════════════════════
// data_export_service.dart — CatechHub (export/import dati + backup cifrato)
//
// Servizio completo per l'esportazione e l'importazione di tutti i dati
// dell'applicazione. Supporta:
//   - Export completo di tutti i moduli
//   - Export selettivo per categorie
//   - Import con merge (strategia last-write-wins)
//   - Cifratura end-to-end con password (AES-256-GCM + PBKDF2)
//   - Allegati inclusi come Base64 nel pacchetto
//   - Verifica checksum e integrità strutturale
//
// CONTESTO PROGETTO:
//   Il backup/ripristino è una funzione critica: i catechisti hanno dati
//   preziosi (anagrafica, presenze, documenti) che devono poter essere
//   trasferiti tra dispositivi o salvati come backup. L'export cifrato
//   garantisce che i dati rimangano protetti anche fuori dall'app.
//
//   L'import usa merge per campo (non sovrascrive l'intero record),
//   preservando i dati locali non presenti nell'import.
//   La verifica d'integrità (verifyDataIntegrity) controlla che il
//   pacchetto contenga i campi minimi obbligatori.
//
// MODULI ESPORTABILI:
//   anagrafica (studenti + classi), agenda (presenze), programmazione,
//   allegati (per tipo: student/meeting/catechesi), documenti,
//   note contatto, catechesi, associazioni catechesi-giornate,
//   annotazioni giornaliere studenti.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:typed_data';
import 'package:hive/hive.dart';
import '../auth/auth_service.dart';
import '../storage/encrypted_file_storage.dart';
import '../storage/local_database.dart';
import '../../shared/models/catechesi_model.dart';
import '../../shared/models/student_model.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/planning_meeting.dart';
import '../../shared/models/attachment_model.dart';
import '../../shared/models/contact_note_model.dart';
import '../../shared/models/student_daily_note_model.dart';
import 'encryption_service.dart';

typedef PhaseCallback = void Function(String phase);

class DataExportService {
  /// Esporta TUTTI i dati del database in una mappa annidata.
  static Future<Map<String, dynamic>> exportAllData() async {
    final Map<String, dynamic> allData = {
      'anagrafica': _exportAnagrafica(),
      'allegati_studenti': await _exportAllegatiPerTipo('student'),
      'agenda': _exportAgenda(),
      'programmazione': _exportProgrammazione(),
      'allegati_giornate': await _exportAllegatiPerTipo('meeting'),
      'documenti': _exportDocumenti(),
      'note_contatto': _exportNoteContatto(),
      'catechesi': _exportCatechesi(),
      'associazioni_catechesi': _exportAssociazioniCatechesi(),
      'allegati_catechesi': await _exportAllegatiPerTipo('catechesi'),
      'annotazioni_giornaliere': _exportStudentDailyNotes(),
    };
    return allData;
  }

  /// Esporta solo i moduli selezionati (per condivisione selettiva).
  static Future<Map<String, dynamic>> exportSelectiveData({
    bool includeAnagrafica = false, bool includeAgenda = false,
    bool includeProgrammazione = false, bool includeDocumenti = false,
    bool includeContactNotes = false, bool includeAnagraficaAttachments = false,
    bool includeAgendaAttachments = false, bool includeCatechesi = false,
    bool includeAnnotazioni = false,
  }) async {
    final Map<String, dynamic> selectiveData = {};
    if (includeAnagrafica) {
      selectiveData['anagrafica'] = _exportAnagrafica();
      if (includeAnagraficaAttachments) selectiveData['allegati_studenti'] = await _exportAllegatiPerTipo('student');
    }
    if (includeAgenda) selectiveData['agenda'] = _exportAgenda();
    if (includeProgrammazione) {
      selectiveData['programmazione'] = _exportProgrammazione();
      if (includeAgendaAttachments) selectiveData['allegati_giornate'] = await _exportAllegatiPerTipo('meeting');
    }
    if (includeDocumenti) selectiveData['documenti'] = _exportDocumenti();
    if (includeContactNotes) selectiveData['note_contatto'] = _exportNoteContatto();
    if (includeCatechesi) {
      selectiveData['catechesi'] = _exportCatechesi();
      selectiveData['associazioni_catechesi'] = _exportAssociazioniCatechesi();
    }
    if (includeAnnotazioni) selectiveData['annotazioni_giornaliere'] = _exportStudentDailyNotes();
    return selectiveData;
  }

  // ─── EXPORT SINGOLI MODULI ─────────────────────────────────────────

  static Map<String, dynamic> _exportAnagrafica() {
    final students = LocalDatabase.values(LocalDatabase.students(), (id, data) => Student.fromMap(id, data));
    final classes = LocalDatabase.values(LocalDatabase.classes(), (id, data) => SchoolClass.fromMap(id, data));
    return {
      'students': students.map((s) => s.toMap()..['id'] = s.id).toList(),
      'classes': classes.map((c) => c.toMap()..['id'] = c.id).toList(),
    };
  }

  static Map<String, dynamic> _exportAgenda() {
    final attendance = LocalDatabase.values(LocalDatabase.attendance(), (id, data) => {'id': id, ...data});
    return {'attendance': attendance};
  }

  static Map<String, dynamic> _exportProgrammazione() {
    final planning = LocalDatabase.values(LocalDatabase.planning(), (id, data) => PlanningMeeting.fromMap(id, data));
    return {'planning': planning.map((p) => p.toMap()..['id'] = p.id).toList()};
  }

  static Map<String, dynamic> _exportDocumenti() {
    final documents = LocalDatabase.values(LocalDatabase.documents(), (id, data) => {'id': id, ...data});
    final deliveries = LocalDatabase.values(LocalDatabase.documentDeliveries(), (id, data) => {'id': id, ...data});
    return {'documents': documents, 'deliveries': deliveries};
  }

  static Future<Map<String, dynamic>> _exportAllegatiPerTipo(String parentType) async {
    final all = LocalDatabase.values(LocalDatabase.attachments(), (id, data) => Attachment.fromMap(id, data));
    final filtered = all.where((a) => a.parentType == parentType).toList();
    final List<Map<String, dynamic>> withData = [];
    for (final a in filtered) {
      final map = a.toMap()..['id'] = a.id;
      try { map['fileData'] = base64Encode(await EncryptedFileStorage.read(a.id)); } catch (_) {}
      withData.add(map);
    }
    return {'attachments': withData, 'parentType': parentType};
  }

  static Map<String, dynamic> _exportCatechesi() {
    final catechesi = LocalDatabase.values(LocalDatabase.catechesi(), (id, data) => Catechesi.fromMap(id, data));
    return {'catechesi': catechesi.map((c) => c.toMap()..['id'] = c.id).toList()};
  }

  static Map<String, dynamic> _exportAssociazioniCatechesi() {
    final box = LocalDatabase.meetingCatechesi();
    final associations = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      final value = box.get(key);
      if (value is List) associations.add({'meetingId': key.toString(), 'catechesiIds': value});
    }
    return {'associazioni': associations};
  }

  static Map<String, dynamic> _exportNoteContatto() {
    final notes = LocalDatabase.values(LocalDatabase.contactNotes(), (id, data) => ContactNote.fromMap(id, data));
    return {'notes': notes.map((n) => n.toMap()..['id'] = n.id).toList()};
  }

  static Map<String, dynamic> _exportStudentDailyNotes() {
    final notes = LocalDatabase.values(LocalDatabase.studentDailyNotes(), (id, data) => StudentDailyNote.fromMap(id, data));
    return {'notes': notes.map((n) => n.toMap()..['id'] = n.id).toList()};
  }

  // ─── IMPORT CON MERGE ───────────────────────────────────────────────

/// Importa dati ricevuti facendo merge con quelli esistenti.
  /// Strategia: merge per singolo campo (non sovrascrive l'intero record).
  static Future<void> importData(Map<String, dynamic> receivedData, {PhaseCallback? onPhase}) async {
    onPhase?.call('Importazione anagrafica ragazzi...');
    if (receivedData.containsKey('anagrafica')) await _importAnagrafica(receivedData['anagrafica']);
    onPhase?.call('Importazione allegati studenti...');
    if (receivedData.containsKey('allegati_studenti')) await _importAllegati(receivedData['allegati_studenti'], 'student');
    onPhase?.call('Importazione presenze...');
    if (receivedData.containsKey('agenda')) await _importAgenda(receivedData['agenda']);
    onPhase?.call('Importazione programmazione...');
    if (receivedData.containsKey('programmazione')) await _importProgrammazione(receivedData['programmazione']);
    onPhase?.call('Importazione allegati giornate...');
    if (receivedData.containsKey('allegati_giornate')) await _importAllegati(receivedData['allegati_giornate'], 'meeting');
    onPhase?.call('Importazione documenti...');
    if (receivedData.containsKey('documenti')) await _importDocumenti(receivedData['documenti']);
    if (receivedData.containsKey('allegati')) await _importAllegatiGenerici(receivedData['allegati']);
    onPhase?.call('Importazione note di contatto...');
    if (receivedData.containsKey('note_contatto')) await _importNoteContatto(receivedData['note_contatto']);
    onPhase?.call('Importazione catechesi...');
    if (receivedData.containsKey('catechesi')) await _importCatechesi(receivedData['catechesi']);
    if (receivedData.containsKey('associazioni_catechesi')) await _importAssociazioniCatechesi(receivedData['associazioni_catechesi']);
    if (receivedData.containsKey('allegati_catechesi')) await _importAllegati(receivedData['allegati_catechesi'], 'catechesi');
    onPhase?.call('Importazione annotazioni...');
    if (receivedData.containsKey('annotazioni_giornaliere')) await _importStudentDailyNotes(receivedData['annotazioni_giornaliere']);
    onPhase?.call('Aggiornamento classi...');
    await _ensureLocalCatechistInClasses();
  }

  /// After importing classes, ensures the local catechist ID is present
  /// in every class's [catechistIds], so UI filters work correctly
  /// when importing on a different device.
  static Future<void> _ensureLocalCatechistInClasses() async {
    final box = LocalDatabase.classes();
    final localId = AuthService.localUserId;
    for (final key in box.keys) {
      final data = LocalDatabase.toStringDynamicMap(box.get(key));
      final ids = (data['catechistIds'] as List? ?? []).map((e) => e.toString()).toList();
      if (!ids.contains(localId)) {
        ids.add(localId);
        data['catechistIds'] = ids;
        await box.put(key, data);
      }
    }
  }

  static Map<String, dynamic> _mergeMaps(Map<String, dynamic> localData, Map<String, dynamic> incomingData) {
    final merged = Map<String, dynamic>.from(localData);
    for (final entry in incomingData.entries) {
      if (entry.key == 'id' || entry.value == null) continue;
      if (merged[entry.key] != entry.value) merged[entry.key] = entry.value;
    }
    return merged;
  }

  static Future<void> _mergeBoxRecords(Box<Map> box, List<dynamic>? incomingItems) async {
    if (incomingItems == null) return;
    for (final item in incomingItems) {
      final record = Map<String, dynamic>.from(item as Map);
      final id = record.remove('id') as String? ?? LocalDatabase.newId();
      final existing = LocalDatabase.toStringDynamicMap(box.get(id));
      if (existing.isEmpty) {
        await box.put(id, record);
      } else {
        final merged = _mergeMaps(existing, record);
        if (merged.toString() != existing.toString()) await box.put(id, merged);
      }
    }
  }

  static Future<void> _importAnagrafica(Map<String, dynamic> data) async {
    await _mergeBoxRecords(LocalDatabase.students(), data['students'] as List<dynamic>?);
    // Sostituisci completamente le classi (non merge) per evitare duplicati/vecchi dati
    final classesBox = LocalDatabase.classes();
    await classesBox.clear();
    final incomingClasses = data['classes'] as List<dynamic>?;
    if (incomingClasses != null) {
      for (final item in incomingClasses) {
        final record = Map<String, dynamic>.from(item as Map);
        final id = record.remove('id') as String? ?? LocalDatabase.newId('class');
        await classesBox.put(id, record);
      }
    }
  }

  static Future<void> _importAgenda(Map<String, dynamic> data) async {
    await _mergeBoxRecords(LocalDatabase.attendance(), data['attendance'] as List<dynamic>?);
  }

  static Future<void> _importProgrammazione(Map<String, dynamic> data) async {
    await _mergeBoxRecords(LocalDatabase.planning(), data['planning'] as List<dynamic>?);
  }

  static Future<void> _importDocumenti(Map<String, dynamic> data) async {
    await _mergeBoxRecords(LocalDatabase.documents(), data['documents'] as List<dynamic>?);
    await _mergeBoxRecords(LocalDatabase.documentDeliveries(), data['deliveries'] as List<dynamic>?);
  }

  static Future<void> _importAllegati(Map<String, dynamic> allegatiData, String parentType) async {
    final box = LocalDatabase.attachments();
    final incoming = allegatiData['attachments'] as List<dynamic>?;
    if (incoming == null) return;
    for (final item in incoming) {
      final map = Map<String, dynamic>.from(item as Map);
      final id = map.remove('id') as String? ?? LocalDatabase.newId('attachment');
      final local = LocalDatabase.toStringDynamicMap(box.get(id));
      final localAtt = local.isEmpty ? null : Attachment.fromMap(id, local);
      final fileDataB64 = map.remove('fileData') as String?;
      final incomingTime = DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);

      if (localAtt != null) {
        if (fileDataB64 != null && fileDataB64.isNotEmpty) {
          if (localAtt.fileHash == map['fileHash']) {
            final merged = _mergeMaps(local, map);
            if (merged.toString() != local.toString()) await box.put(id, merged);
            continue;
          }
          if (incomingTime.isAfter(localAtt.createdAt)) {
            await EncryptedFileStorage.write(id, Uint8List.fromList(base64Decode(fileDataB64)));
            final merged = _mergeMaps(local, map);
            await box.put(id, merged);
            continue;
          }
        }
        final merged = _mergeMaps(local, map);
        if (merged.toString() != local.toString()) await box.put(id, merged);
        continue;
      }

      if (fileDataB64 != null && fileDataB64.isNotEmpty) {
        await EncryptedFileStorage.write(id, Uint8List.fromList(base64Decode(fileDataB64)));
      }
      await box.put(id, map);
    }
  }

  static Future<void> _importAllegatiGenerici(Map<String, dynamic> allegatiData) async {
    // Stessa logica di _importAllegati ma senza filtro parentType (retrocompatibilità)
    final box = LocalDatabase.attachments();
    final incoming = allegatiData['attachments'] as List<dynamic>?;
    if (incoming == null) return;
    for (final item in incoming) {
      final map = Map<String, dynamic>.from(item as Map);
      final id = map.remove('id') as String? ?? LocalDatabase.newId('attachment');
      final local = LocalDatabase.toStringDynamicMap(box.get(id));
      final localAtt = local.isEmpty ? null : Attachment.fromMap(id, local);
      final fileDataB64 = map.remove('fileData') as String?;
      final incomingTime = DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);

      if (localAtt != null) {
        if (fileDataB64 != null && fileDataB64.isNotEmpty) {
          if (localAtt.fileHash == map['fileHash']) {
            final merged = _mergeMaps(local, map);
            if (merged.toString() != local.toString()) await box.put(id, merged);
            continue;
          }
          if (incomingTime.isAfter(localAtt.createdAt)) {
            await EncryptedFileStorage.write(id, Uint8List.fromList(base64Decode(fileDataB64)));
            final merged = _mergeMaps(local, map);
            await box.put(id, merged);
            continue;
          }
        }
        final merged = _mergeMaps(local, map);
        if (merged.toString() != local.toString()) await box.put(id, merged);
        continue;
      }

      if (fileDataB64 != null && fileDataB64.isNotEmpty) {
        await EncryptedFileStorage.write(id, Uint8List.fromList(base64Decode(fileDataB64)));
      }
      await box.put(id, map);
    }
  }

  static Future<void> _importNoteContatto(Map<String, dynamic> data) async {
    await _mergeBoxRecords(LocalDatabase.contactNotes(), data['notes'] as List<dynamic>?);
  }

  static Future<void> _importCatechesi(Map<String, dynamic> data) async {
    await _mergeBoxRecords(LocalDatabase.catechesi(), data['catechesi'] as List<dynamic>?);
  }

  static Future<void> _importStudentDailyNotes(Map<String, dynamic> data) async {
    await _mergeBoxRecords(LocalDatabase.studentDailyNotes(), data['notes'] as List<dynamic>?);
  }

  static Future<void> _importAssociazioniCatechesi(Map<String, dynamic> data) async {
    final box = LocalDatabase.meetingCatechesi();
    final incoming = data['associazioni'] as List<dynamic>?;
    if (incoming == null) return;
    for (final item in incoming) {
      final map = Map<String, dynamic>.from(item as Map);
      final meetingId = map['meetingId']?.toString() ?? '';
      final ids = (map['catechesiIds'] as List<dynamic>?)?.cast<String>() ?? [];
      if (meetingId.isNotEmpty) await box.put(meetingId, ids);
    }
  }

  // ─── VERIFICA INTEGRITÀ ─────────────────────────────────────────────

  /// Verifica che il pacchetto ricevuto contenga i campi minimi richiesti.
  static bool verifyDataIntegrity(Map<String, dynamic> receivedData, {bool requireFullPackage = true}) {
    if (requireFullPackage) {
      for (final field in ['anagrafica', 'agenda', 'programmazione', 'documenti']) {
        if (!receivedData.containsKey(field)) return false;
      }
      return true;
    }
    const supported = {'anagrafica', 'agenda', 'programmazione', 'documenti', 'allegati_studenti', 'allegati_giornate', 'note_contatto', 'allegati', 'catechesi', 'associazioni_catechesi', 'annotazioni_giornaliere'};
    return receivedData.keys.any(supported.contains);
  }

  // ─── EXPORT/IMPORT CIFRATO ──────────────────────────────────────────

  /// Esporta tutti i dati cifrati con password (AES-256-GCM + PBKDF2).
  static Future<String> exportEncryptedData(String password) async {
    final allData = await exportAllData();
    return EncryptionService.encryptData(allData, password);
  }

  /// Importa dati cifrati con verifica password e integrità.
  static Future<void> importEncryptedData(String encryptedData, String password, {PhaseCallback? onPhase}) async {
    onPhase?.call('Decifratura backup in corso...');
    final decryptedData = EncryptionService.decryptData(encryptedData, password);
    onPhase?.call('Verifica integrità dati...');
    if (!verifyDataIntegrity(decryptedData)) throw Exception('Integrità dei dati non valida');
    await importData(decryptedData, onPhase: onPhase);
  }

  /// Verifica la password per dati cifrati (senza importare).
  static bool verifyEncryptedPassword(String encryptedData, String password) {
    return EncryptionService.verifyPassword(encryptedData, password);
  }
}
