import 'dart:convert';
import 'dart:typed_data';

import '../storage/encrypted_file_storage.dart';
import '../storage/local_database.dart';
import '../../shared/models/student_model.dart';
import '../../shared/models/class_model.dart';
import '../../shared/models/planning_meeting.dart';
import '../../shared/models/attachment_model.dart';
import 'encryption_service.dart';

class DataExportService {
  // Esporta tutti i dati dal database
  static Future<Map<String, dynamic>> exportAllData() async {
    final Map<String, dynamic> allData = {
      'anagrafica': _exportAnagrafica(),
      'allegati_studenti': await _exportAllegatiPerTipo('student'),
      'agenda': _exportAgenda(),
      'programmazione': _exportProgrammazione(),
      'allegati_giornate': await _exportAllegatiPerTipo('meeting'),
      'documenti': _exportDocumenti(),
    };

    return allData;
  }

  // Esporta dati selettivi basati su opzioni
  static Future<Map<String, dynamic>> exportSelectiveData(bool includeAnagrafica, bool includeAgenda, bool includeProgrammazione, bool includeDocumenti, bool includeAllegati) async {
    final Map<String, dynamic> selectiveData = {};

    if (includeAnagrafica) {
      selectiveData['anagrafica'] = _exportAnagrafica();
      // Includi automaticamente allegati dei ragazzi
      selectiveData['allegati_studenti'] = await _exportAllegatiPerTipo('student');
    }

    if (includeAgenda) {
      selectiveData['agenda'] = _exportAgenda();
    }

    if (includeProgrammazione) {
      selectiveData['programmazione'] = _exportProgrammazione();
      // Includi automaticamente allegati delle giornate
      selectiveData['allegati_giornate'] = await _exportAllegatiPerTipo('meeting');
    }

    if (includeDocumenti) {
      selectiveData['documenti'] = _exportDocumenti();
    }

    return selectiveData;
  }

  // Esporta anagrafica (studenti e classi)
  static Map<String, dynamic> _exportAnagrafica() {
    final students = LocalDatabase.values(
      LocalDatabase.students(),
      (id, data) => Student.fromMap(id, data),
    );

    final classes = LocalDatabase.values(
      LocalDatabase.classes(),
      (id, data) => SchoolClass.fromMap(id, data),
    );

    return {
      'students': students.map((s) => s.toMap()..['id'] = s.id).toList(),
      'classes': classes.map((c) => c.toMap()..['id'] = c.id).toList(),
    };
  }

  // Esporta agenda (presenze)
  static Map<String, dynamic> _exportAgenda() {
    final attendance = LocalDatabase.values(
      LocalDatabase.attendance(),
      (id, data) => {'id': id, ...data},
    );

    return {
      'attendance': attendance,
    };
  }

  // Esporta programmazione (planning)
  static Map<String, dynamic> _exportProgrammazione() {
    final planning = LocalDatabase.values(
      LocalDatabase.planning(),
      (id, data) => PlanningMeeting.fromMap(id, data),
    );

    return {
      'planning': planning.map((p) => p.toMap()..['id'] = p.id).toList(),
    };
  }

  // Esporta documenti
  static Map<String, dynamic> _exportDocumenti() {
    final documents = LocalDatabase.values(
      LocalDatabase.documents(),
      (id, data) => {'id': id, ...data},
    );

    final deliveries = LocalDatabase.values(
      LocalDatabase.documentDeliveries(),
      (id, data) => {'id': id, ...data},
    );

    return {
      'documents': documents,
      'deliveries': deliveries,
    };
  }

  // Esporta allegati per tipo specifico (student o meeting)
  static Future<Map<String, dynamic>> _exportAllegatiPerTipo(String parentType) async {
    final allAttachments = LocalDatabase.values(
      LocalDatabase.attachments(),
      (id, data) => Attachment.fromMap(id, data),
    );

    // Filtra per tipo
    final filteredAttachments = allAttachments
        .where((a) => a.parentType == parentType)
        .toList();

    // Includi i dati binari (base64) di ogni allegato
    final List<Map<String, dynamic>> attachmentsWithData = [];
    for (final a in filteredAttachments) {
      final map = a.toMap()..['id'] = a.id;
      try {
        final fileBytes = await EncryptedFileStorage.read(a.id);
        map['fileData'] = base64Encode(fileBytes);
      } catch (_) {
        // File non trovato su disco: esporta solo i metadati
      }
      attachmentsWithData.add(map);
    }

    return {
      'attachments': attachmentsWithData,
      'parentType': parentType,
    };
  }

  // Importa dati ricevuti sostituendo quelli esistenti
  static Future<void> importData(Map<String, dynamic> receivedData) async {
    // Importa anagrafica
    if (receivedData.containsKey('anagrafica')) {
      await _importAnagrafica(receivedData['anagrafica']);
    }

    // Importa allegati dei ragazzi
    if (receivedData.containsKey('allegati_studenti')) {
      await _importAllegati(receivedData['allegati_studenti'], 'student');
    }

    // Importa agenda
    if (receivedData.containsKey('agenda')) {
      await _importAgenda(receivedData['agenda']);
    }

    // Importa programmazione
    if (receivedData.containsKey('programmazione')) {
      await _importProgrammazione(receivedData['programmazione']);
    }

    // Importa allegati delle giornate
    if (receivedData.containsKey('allegati_giornate')) {
      await _importAllegati(receivedData['allegati_giornate'], 'meeting');
    }

    // Importa documenti
    if (receivedData.containsKey('documenti')) {
      await _importDocumenti(receivedData['documenti']);
    }

    // Importa allegati generici (per compatibilità con vecchi export)
    if (receivedData.containsKey('allegati')) {
      await _importAllegatiGenerici(receivedData['allegati']);
    }
  }

  // Importa anagrafica
  static Future<void> _importAnagrafica(Map<String, dynamic> anagraficaData) async {
    final studentsBox = LocalDatabase.students();
    final classesBox = LocalDatabase.classes();

    // Svuota box esistenti
    await studentsBox.clear();
    await classesBox.clear();

    // Importa studenti
    final students = anagraficaData['students'] as List<dynamic>?;
    if (students != null) {
      for (final studentData in students) {
        final studentMap = studentData as Map<String, dynamic>;
        final id = studentMap['id'] as String? ?? LocalDatabase.newId('student');
        await studentsBox.put(id, studentMap);
      }
    }

    // Importa classi
    final classes = anagraficaData['classes'] as List<dynamic>?;
    if (classes != null) {
      for (final classData in classes) {
        final classMap = classData as Map<String, dynamic>;
        final id = classMap['id'] as String? ?? LocalDatabase.newId('class');
        await classesBox.put(id, classMap);
      }
    }
  }

  // Importa agenda
  static Future<void> _importAgenda(Map<String, dynamic> agendaData) async {
    final attendanceBox = LocalDatabase.attendance();

    // Svuota box esistente
    await attendanceBox.clear();

    // Importa presenze
    final attendance = agendaData['attendance'] as List<dynamic>?;
    if (attendance != null) {
      for (final attendanceData in attendance) {
        final attendanceMap = attendanceData as Map<String, dynamic>;
        final id = attendanceMap['id'] as String? ?? LocalDatabase.newId('attendance');
        await attendanceBox.put(id, attendanceMap);
      }
    }
  }

  // Importa programmazione
  static Future<void> _importProgrammazione(Map<String, dynamic> programmazioneData) async {
    final planningBox = LocalDatabase.planning();

    // Svuota box esistente
    await planningBox.clear();

    // Importa planning
    final planning = programmazioneData['planning'] as List<dynamic>?;
    if (planning != null) {
      for (final planningData in planning) {
        final planningMap = planningData as Map<String, dynamic>;
        final id = planningMap['id'] as String? ?? LocalDatabase.newId('planning');
        await planningBox.put(id, planningMap);
      }
    }
  }

  // Importa documenti
  static Future<void> _importDocumenti(Map<String, dynamic> documentiData) async {
    final documentsBox = LocalDatabase.documents();
    final deliveriesBox = LocalDatabase.documentDeliveries();

    // Svuota box esistenti
    await documentsBox.clear();
    await deliveriesBox.clear();

    // Importa documenti
    final documents = documentiData['documents'] as List<dynamic>?;
    if (documents != null) {
      for (final documentData in documents) {
        final documentMap = documentData as Map<String, dynamic>;
        final id = documentMap['id'] as String? ?? LocalDatabase.newId('document');
        await documentsBox.put(id, documentMap);
      }
    }

    // Importa consegne
    final deliveries = documentiData['deliveries'] as List<dynamic>?;
    if (deliveries != null) {
      for (final deliveryData in deliveries) {
        final deliveryMap = deliveryData as Map<String, dynamic>;
        final id = deliveryMap['id'] as String? ?? LocalDatabase.newId('delivery');
        await deliveriesBox.put(id, deliveryMap);
      }
    }
  }

  // Importa allegati per tipo specifico
  static Future<void> _importAllegati(Map<String, dynamic> allegatiData, String parentType) async {
    final attachmentsBox = LocalDatabase.attachments();

    // Rimuovi solo gli allegati del tipo specificato (inclusi i file su disco)
    final allAttachments = LocalDatabase.values(
      LocalDatabase.attachments(),
      (id, data) => Attachment.fromMap(id, data),
    );

    for (final attachment in allAttachments) {
      if (attachment.parentType == parentType) {
        await EncryptedFileStorage.delete(attachment.id);
        await attachmentsBox.delete(attachment.id);
      }
    }

    // Importa allegati con dati binari
    final attachments = allegatiData['attachments'] as List<dynamic>?;
    if (attachments != null) {
      for (final attachmentData in attachments) {
        final attachmentMap = Map<String, dynamic>.from(attachmentData as Map);
        final id = attachmentMap['id'] as String? ?? LocalDatabase.newId('attachment');

        // Salva i dati binari nel file storage se presenti
        final fileDataB64 = attachmentMap.remove('fileData') as String?;
        if (fileDataB64 != null && fileDataB64.isNotEmpty) {
          final fileBytes = Uint8List.fromList(base64Decode(fileDataB64));
          await EncryptedFileStorage.write(id, fileBytes);
        }

        await attachmentsBox.put(id, attachmentMap);
      }
    }
  }

  // Importa allegati generici (per compatibilità con vecchi export)
  static Future<void> _importAllegatiGenerici(Map<String, dynamic> allegatiData) async {
    final attachmentsBox = LocalDatabase.attachments();

    // Elimina file su disco prima di svuotare il box
    final existingAttachments = LocalDatabase.values(
      LocalDatabase.attachments(),
      (id, data) => Attachment.fromMap(id, data),
    );
    for (final attachment in existingAttachments) {
      await EncryptedFileStorage.delete(attachment.id);
    }

    // Svuota box esistente
    await attachmentsBox.clear();

    // Importa allegati con dati binari
    final attachments = allegatiData['attachments'] as List<dynamic>?;
    if (attachments != null) {
      for (final attachmentData in attachments) {
        final attachmentMap = Map<String, dynamic>.from(attachmentData as Map);
        final id = attachmentMap['id'] as String? ?? LocalDatabase.newId('attachment');

        // Salva i dati binari nel file storage se presenti
        final fileDataB64 = attachmentMap.remove('fileData') as String?;
        if (fileDataB64 != null && fileDataB64.isNotEmpty) {
          final fileBytes = Uint8List.fromList(base64Decode(fileDataB64));
          await EncryptedFileStorage.write(id, fileBytes);
        }

        await attachmentsBox.put(id, attachmentMap);
      }
    }
  }

  // Verifica integrità dei dati ricevuti
  static bool verifyDataIntegrity(Map<String, dynamic> receivedData) {
    // Verifica che i campi obbligatori siano presenti
    final requiredFields = ['anagrafica', 'agenda', 'programmazione', 'documenti'];
    
    for (final field in requiredFields) {
      if (!receivedData.containsKey(field)) {
        return false;
      }
    }

    return true;
  }

  // Esporta tutti i dati cifrati con password
  static Future<String> exportEncryptedData(String password) async {
    final allData = await exportAllData();
    return EncryptionService.encryptData(allData, password);
  }

  // Importa dati cifrati con verifica password
  static Future<void> importEncryptedData(String encryptedData, String password) async {
    final decryptedData = EncryptionService.decryptData(encryptedData, password);
    
    // Verifica integrità dati
    if (!verifyDataIntegrity(decryptedData)) {
      throw Exception('Integrità dei dati non valida');
    }

    // Importa i dati
    await importData(decryptedData);
  }

  // Verifica la password per dati cifrati
  static bool verifyEncryptedPassword(String encryptedData, String password) {
    return EncryptionService.verifyPassword(encryptedData, password);
  }
}
