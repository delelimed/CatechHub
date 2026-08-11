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
import '../../shared/models/parish_config.dart';
import 'encryption_service.dart';

typedef PhaseCallback = void Function(String phase);

class DataExportService {
  /// Esporta i dati del database in una mappa annidata.
  ///
  /// Se [classId] è valorizzato, il pacchetto contiene SOLO i record della
  /// classe indicata (anagrafica, presenze, programmazione, documenti, note
  /// di contatto, annotazioni e relativi allegati). Se è `null`, il pacchetto
  /// contiene TUTTE le classi del catechista locale.
  ///
  /// In entrambi i casi vengono SEMPRE incluse le catechesi (contenuti non
  /// legati a una singola classe) e i relativi allegati.
  static Future<Map<String, dynamic>> exportAllData({String? classId}) async {
    final scope = _ExportScope.resolve(classId);
    final Map<String, dynamic> allData = {
      'anagrafica': _exportAnagrafica(scope),
      'allegati_studenti': await _exportAllegatiPerTipo('student', scope: scope),
      'agenda': _exportAgenda(scope),
      'programmazione': _exportProgrammazione(scope),
      'allegati_giornate': await _exportAllegatiPerTipo('meeting', scope: scope),
      'documenti': _exportDocumenti(scope),
      'note_contatto': _exportNoteContatto(scope),
      'catechesi': _exportCatechesi(),
      'associazioni_catechesi': _exportAssociazioniCatechesi(scope),
      'allegati_catechesi': await _exportAllegatiPerTipo('catechesi'),
      'annotazioni_giornaliere': _exportStudentDailyNotes(scope),
      'parishConfig': _exportParishConfig(),
    };
    return allData;
  }

  /// Configurazione parrocchiale (incl. modalità Responsabile attiva).
  ///
  /// Viene inclusa in ogni backup così il ripristino ricrea anche lo stato
  /// della dashboard Responsabile Catechistico.
  static Map<String, dynamic>? _exportParishConfig() {
    final raw = LocalDatabase.parishConfig().get(ParishConfig.storageKey);
    if (raw == null) return null;
    return ParishConfig.fromMap(LocalDatabase.toStringDynamicMap(raw)).toMap();
  }

  /// Esporta solo i moduli selezionati (per condivisione selettiva).
  static Future<Map<String, dynamic>> exportSelectiveData({
    bool includeAnagrafica = false, bool includeAgenda = false,
    bool includeProgrammazione = false, bool includeDocumenti = false,
    bool includeContactNotes = false, bool includeAnagraficaAttachments = false,
    bool includeAgendaAttachments = false, bool includeCatechesi = false,
    bool includeAnnotazioni = false,
  }) async {
    final scope = _ExportScope.resolve(null);
    final Map<String, dynamic> selectiveData = {};
    if (includeAnagrafica) {
      selectiveData['anagrafica'] = _exportAnagrafica(scope);
      if (includeAnagraficaAttachments) selectiveData['allegati_studenti'] = await _exportAllegatiPerTipo('student', scope: scope);
    }
    if (includeAgenda) selectiveData['agenda'] = _exportAgenda(scope);
    if (includeProgrammazione) {
      selectiveData['programmazione'] = _exportProgrammazione(scope);
      if (includeAgendaAttachments) selectiveData['allegati_giornate'] = await _exportAllegatiPerTipo('meeting', scope: scope);
    }
    if (includeDocumenti) selectiveData['documenti'] = _exportDocumenti(scope);
    if (includeContactNotes) selectiveData['note_contatto'] = _exportNoteContatto(scope);
    if (includeCatechesi) {
      selectiveData['catechesi'] = _exportCatechesi();
      selectiveData['associazioni_catechesi'] = _exportAssociazioniCatechesi(scope);
    }
    if (includeAnnotazioni) selectiveData['annotazioni_giornaliere'] = _exportStudentDailyNotes(scope);
    return selectiveData;
  }

  // ─── EXPORT SINGOLI MODULI ─────────────────────────────────────────

  static Map<String, dynamic> _exportAnagrafica(_ExportScope scope) {
    final students = LocalDatabase.values(LocalDatabase.students(), (id, data) => Student.fromMap(id, data))
        .where((s) => scope.contains(s.toMap()))
        .toList();
    return {
      'students': students.map((s) => s.toMap()..['id'] = s.id).toList(),
      'classes': scope.classes.map((c) => c.toMap()..['id'] = c.id).toList(),
    };
  }

  static Map<String, dynamic> _exportAgenda(_ExportScope scope) {
    final attendance = LocalDatabase.values(LocalDatabase.attendance(), (id, data) => {'id': id, ...data})
        .where((r) => scope.contains(r))
        .toList();
    return {'attendance': attendance};
  }

  static Map<String, dynamic> _exportProgrammazione(_ExportScope scope) {
    final planning = LocalDatabase.values(LocalDatabase.planning(), (id, data) => PlanningMeeting.fromMap(id, data))
        .where((p) => scope.contains(p.toMap()))
        .toList();
    return {'planning': planning.map((p) => p.toMap()..['id'] = p.id).toList()};
  }

  static Map<String, dynamic> _exportDocumenti(_ExportScope scope) {
    final documents = LocalDatabase.values(LocalDatabase.documents(), (id, data) => {'id': id, ...data})
        .where((d) => scope.contains(d))
        .toList();
    final docIds = documents.map((d) => d['id'].toString()).toSet();
    final deliveries = LocalDatabase.values(LocalDatabase.documentDeliveries(), (id, data) => {'id': id, ...data})
        .where((d) => docIds.contains(d['id'].toString()))
        .toList();
    return {'documents': documents, 'deliveries': deliveries};
  }

  static Future<Map<String, dynamic>> _exportAllegatiPerTipo(
    String parentType, {
    _ExportScope? scope,
  }) async {
    final all = LocalDatabase.values(LocalDatabase.attachments(), (id, data) => Attachment.fromMap(id, data));
    var filtered = all.where((a) => a.parentType == parentType).toList();

    if (scope != null && scope.classes.isNotEmpty) {
      if (parentType == 'student') {
        final studentIds = scope.studentIds;
        filtered = filtered.where((a) => studentIds.contains(a.parentId)).toList();
      } else if (parentType == 'meeting') {
        final meetingIds = scope.meetingIds;
        filtered = filtered.where((a) => meetingIds.contains(a.parentId)).toList();
      }
    }

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

  static Map<String, dynamic> _exportAssociazioniCatechesi(_ExportScope scope) {
    final box = LocalDatabase.meetingCatechesi();
    final associations = <Map<String, dynamic>>[];
    final meetingIds = scope.meetingIds;
    for (final key in box.keys) {
      if (scope.classes.isNotEmpty && !meetingIds.contains(key.toString())) continue;
      final value = box.get(key);
      if (value is List) associations.add({'meetingId': key.toString(), 'catechesiIds': value});
    }
    return {'associazioni': associations};
  }

  static Map<String, dynamic> _exportNoteContatto(_ExportScope scope) {
    final notes = LocalDatabase.values(LocalDatabase.contactNotes(), (id, data) => ContactNote.fromMap(id, data))
        .where((n) => scope.contains(n.toMap()))
        .toList();
    return {'notes': notes.map((n) => n.toMap()..['id'] = n.id).toList()};
  }

  static Map<String, dynamic> _exportStudentDailyNotes(_ExportScope scope) {
    final notes = LocalDatabase.values(LocalDatabase.studentDailyNotes(), (id, data) => StudentDailyNote.fromMap(id, data))
        .where((n) => scope.contains(n.toMap()))
        .toList();
    return {'notes': notes.map((n) => n.toMap()..['id'] = n.id).toList()};
  }

  // ─── IMPORT CON MERGE ───────────────────────────────────────────────

/// Importa dati ricevuti facendo merge con quelli esistenti.
  /// Strategia: merge per singolo campo (non sovrascrive l'intero record).
  ///
  /// Se [targetClass] è valorizzato (es. ricezione via QR code), i record
  /// classe-scoped vengono riassegnati alla classe indicata: gli studenti
  /// vengono aggiunti alla [targetClass] e nessuna classe del mittente viene
  /// importata.
  static Future<void> importData(
    Map<String, dynamic> receivedData, {
    SchoolClass? targetClass,
    PhaseCallback? onPhase,
  }) async {
    onPhase?.call('Importazione anagrafica ragazzi...');
    if (receivedData.containsKey('anagrafica')) {
      await _importAnagrafica(receivedData['anagrafica'], targetClass: targetClass);
    }
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
    onPhase?.call('Aggiornamento configurazione parrocchiale...');
    if (receivedData['parishConfig'] is Map) {
      await _importParishConfig(receivedData['parishConfig'] as Map);
    }
    onPhase?.call('Aggiornamento classi...');
    await _ensureLocalCatechistInClasses();
  }

  /// Ripristina la configurazione parrocchiale ricevuta (incl. la modalità
  /// Responsabile Catechistico). Il payload del backup è autoritativo: un
  /// ripristino completo ricrea anche lo stato della dashboard Responsabile.
  static Future<void> _importParishConfig(Map config) async {
    final incoming = ParishConfig.fromMap(LocalDatabase.toStringDynamicMap(config));
    final box = LocalDatabase.parishConfig();
    await box.put(ParishConfig.storageKey, incoming.toMap());
    await box.flush();
  }

  /// Riassegna tutti i record classe-scoped alla [targetClass].
  ///
  /// Usato quando il dispositivo ricevente deve inserire i dati ricevuti
  /// (es. via QR code) nella classe attualmente aperta: gli studenti, le
  /// presenze, la programmazione, i documenti, le note di contatto e le
  /// annotazioni vengono riscritti con il classId/classUniqueCode della
  /// classe del ricevente. La classe del mittente NON viene importata.
  static Map<String, dynamic> remapDataToClass(
    Map<String, dynamic> data,
    SchoolClass targetClass,
  ) {
    final remapped = Map<String, dynamic>.from(data);

    if (data['anagrafica'] is Map) {
      final anagrafica = Map<String, dynamic>.from(data['anagrafica'] as Map);
      final students = (anagrafica['students'] as List? ?? []).map((item) {
        final m = Map<String, dynamic>.from(item as Map);
        m['classId'] = targetClass.id;
        m['classUniqueCode'] = targetClass.uniqueCode;
        return m;
      }).toList();
      anagrafica['students'] = students;
      // La classe del mittente non viene importata: i dati confluiscono
      // nella classe corrente del ricevente.
      anagrafica.remove('classes');
      remapped['anagrafica'] = anagrafica;
    }

    if (data['agenda'] is Map) {
      final agenda = Map<String, dynamic>.from(data['agenda'] as Map);
      final attendance = (agenda['attendance'] as List? ?? []).map((item) {
        final m = Map<String, dynamic>.from(item as Map);
        m['classId'] = targetClass.id;
        m['classUniqueCode'] = targetClass.uniqueCode;
        return m;
      }).toList();
      agenda['attendance'] = attendance;
      remapped['agenda'] = agenda;
    }

    if (data['programmazione'] is Map) {
      final prog = Map<String, dynamic>.from(data['programmazione'] as Map);
      final planning = (prog['planning'] as List? ?? []).map((item) {
        final m = Map<String, dynamic>.from(item as Map);
        m['classId'] = targetClass.id;
        m['classUniqueCode'] = targetClass.uniqueCode;
        return m;
      }).toList();
      prog['planning'] = planning;
      remapped['programmazione'] = prog;
    }

    if (data['documenti'] is Map) {
      final docs = Map<String, dynamic>.from(data['documenti'] as Map);
      final documents = (docs['documents'] as List? ?? []).map((item) {
        final m = Map<String, dynamic>.from(item as Map);
        m['classUniqueCode'] = targetClass.uniqueCode;
        return m;
      }).toList();
      docs['documents'] = documents;
      remapped['documenti'] = docs;
    }

    if (data['note_contatto'] is Map) {
      final notes = Map<String, dynamic>.from(data['note_contatto'] as Map);
      final list = (notes['notes'] as List? ?? []).map((item) {
        final m = Map<String, dynamic>.from(item as Map);
        m['classUniqueCode'] = targetClass.uniqueCode;
        return m;
      }).toList();
      notes['notes'] = list;
      remapped['note_contatto'] = notes;
    }

    if (data['annotazioni_giornaliere'] is Map) {
      final notes = Map<String, dynamic>.from(data['annotazioni_giornaliere'] as Map);
      final list = (notes['notes'] as List? ?? []).map((item) {
        final m = Map<String, dynamic>.from(item as Map);
        m['classUniqueCode'] = targetClass.uniqueCode;
        return m;
      }).toList();
      notes['notes'] = list;
      remapped['annotazioni_giornaliere'] = notes;
    }

    return remapped;
  }

  /// Importa dati ricevuti inserendoli nella [targetClass].
  ///
  /// Riassegna i record classe-scoped alla classe indicata e poi importa.
  /// Le catechesi vengono comunque importate in quanto non legate a una classe.
  static Future<void> importDataIntoClass(
    Map<String, dynamic> receivedData,
    SchoolClass targetClass, {
    PhaseCallback? onPhase,
  }) async {
    final scoped = remapDataToClass(receivedData, targetClass);
    await importData(scoped, targetClass: targetClass, onPhase: onPhase);
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

  static Future<void> _importAnagrafica(Map<String, dynamic> data, {SchoolClass? targetClass}) async {
    await _mergeBoxRecords(LocalDatabase.students(), data['students'] as List<dynamic>?);
    // Aggiorna (merge/aggiornamento) le sole classi presenti nel payload,
    // preservando le altre classi (multiclasse): non si usa un clear globale,
    // altrimenti una condivisione per-classe cancellerebbe le classi non toccate.
    final classesBox = LocalDatabase.classes();
    final incomingClasses = data['classes'] as List<dynamic>?;
    if (incomingClasses != null) {
      for (final item in incomingClasses) {
        var record = Map<String, dynamic>.from(item as Map);
        final rawId = record.remove('id') as String?;
        final id = (rawId != null && rawId.isNotEmpty) ? rawId : LocalDatabase.newId('class');
        // Per una classe esistente aggiorna solo i campi ricevuti (merge),
        // così i dati locali non presenti nel payload non vanno persi.
        final existing = LocalDatabase.toStringDynamicMap(classesBox.get(id));
        if (existing.isNotEmpty) {
          final merged = _mergeMaps(existing, record);
          record = merged;
        }
        // Assicura che il catechista locale sia nella classe import import
        final catechistIds = List<String>.from(record['catechistIds'] as List? ?? []);
        if (!catechistIds.contains(AuthService.localUserId)) {
          catechistIds.add(AuthService.localUserId);
          record['catechistIds'] = catechistIds;
        }
        await classesBox.put(id, record);
      }
    }
    // Se i dati vengono inseriti nella classe corrente del ricevente
    // (es. importazione via QR code), rende visibili nella classe gli
    // studenti appena importati aggiungendoli a studentIds.
    if (targetClass != null) {
      final targetData = LocalDatabase.toStringDynamicMap(classesBox.get(targetClass.id));
      if (targetData.isNotEmpty) {
        final incomingIds = (data['students'] as List? ?? [])
            .map((item) {
              final m = Map<String, dynamic>.from(item as Map);
              return m['id']?.toString() ?? '';
            })
            .where((id) => id.isNotEmpty)
            .toSet();
        final existingIds = (targetData['studentIds'] as List? ?? [])
            .map((e) => e.toString())
            .toSet();
        targetData['studentIds'] = {...existingIds, ...incomingIds}.toList();
        await classesBox.put(targetClass.id, targetData);
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

  /// Esporta dati cifrati con password (AES-256-GCM + PBKDF2).
  ///
  /// Se [classId] è valorizzato, viene esportata solo la classe indicata;
  /// se è `null`, vengono esportate tutte le classi del catechista.
  /// Le catechesi sono sempre incluse in entrambi i casi.
  static Future<String> exportEncryptedData(String password, {String? classId}) async {
    final allData = await exportAllData(classId: classId);
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

/// Scope di esportazione per classe.
///
/// Definisce quali classi includere nel pacchetto di backup. Se il
/// `classId` richiesto è `null`, vengono incluse tutte le classi del
/// catechista locale; altrimenti solo la classe indicata.
class _ExportScope {
  final List<SchoolClass> classes;

  late final Set<String> uniqueCodes =
      classes.map((c) => c.uniqueCode).where((c) => c.isNotEmpty).toSet();

  late final Set<String> classIds =
      classes.map((c) => c.id).where((c) => c.isNotEmpty).toSet();

  _ExportScope(this.classes);

  /// Risolve lo scope: tutte le classi del catechista se [classId] è null,
  /// altrimenti la sola classe richiesta.
  static _ExportScope resolve(String? classId) {
    final allClasses = LocalDatabase.values(
      LocalDatabase.classes(),
      (id, data) => SchoolClass.fromMap(id, data),
    );
    if (classId == null) {
      return _ExportScope(
        allClasses
            .where((c) => c.catechistIds.contains(AuthService.localUserId))
            .toList(),
      );
    }
    return _ExportScope(allClasses.where((c) => c.id == classId).toList());
  }

  /// IDs degli studenti appartenenti allo scope.
  Set<String> get studentIds {
    final students = LocalDatabase.values(
      LocalDatabase.students(),
      (id, data) => Student.fromMap(id, data),
    );
    return students.where((s) => contains(s.toMap())).map((s) => s.id).toSet();
  }

  /// IDs degli incontri appartenenti allo scope.
  Set<String> get meetingIds {
    final meetings = LocalDatabase.values(
      LocalDatabase.planning(),
      (id, data) => PlanningMeeting.fromMap(id, data),
    );
    return meetings.where((m) => contains(m.toMap())).map((m) => m.id).toSet();
  }

  /// True se il record appartiene a una delle classi dello scope.
  /// Valuta prima il `classUniqueCode` (stabile tra dispositivi) e in
  /// mancanza il `classId` locale.
  bool contains(Map<String, dynamic> record) {
    if (classes.isEmpty) return false;
    final code = record['classUniqueCode']?.toString();
    if (code != null && code.isNotEmpty) return uniqueCodes.contains(code);
    final classId = record['classId']?.toString();
    if (classId != null && classId.isNotEmpty) return classIds.contains(classId);
    return false;
  }
}
