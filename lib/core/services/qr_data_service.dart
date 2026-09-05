// ══════════════════════════════════════════════════════════════════════════════
// qr_data_service.dart — CatechHub (condivisione dati via QR code)
//
// Gestisce la creazione, cifratura, segmentazione e decodifica dei
// pacchetti di dati scambiati tramite QR code tra dispositivi.
//
// CONTESTO PROGETTO:
//   La condivisione dati è uno dei canali di sincronizzazione (l'alternativa
//   al Nearby Connections). Il flusso è:
//   1. L'utente sceglie i dati da condividere (DataShareOptions)
//   2. I dati vengono cifrati con PIN temporaneo (AES-256-GCM, KDF robusto)
//   3. Il pacchetto cifrato viene segmentato in QRChunk (max 1200 byte cad.)
//   4. Ogni chunk ha checksum SHA-256 per rilevare corruzione
//   5. Il destinatario scansiona i QR, riassembla, verifica checksum, decifra
//
//   Il PIN è un numero casuale di 12 cifre, valido 3 minuti.
//   La segmentazione in chunk permette di trasferire payload grandi
//   via QR code (es. intero database di un gruppo).
//
// CLASSI:
//   - DataShareOptions: opzioni di selezione moduli da condividere
//   - DataPackage: wrapper del payload cifrato con checksum
//   - QRChunk: singolo frammento QR (indice, totale, dati, checksum)
//   - QRDataService: metodi statici per generazione/verifica/assemblaggio
//
// DIPENDENZE:
//   - crypto (sha256): checksum dei chunk e del pacchetto
//   - EncryptionService: cifratura AES-256-GCM con KDF PBKDF2 robusto
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math';
import 'package:hive/hive.dart';
import '../storage/local_database.dart';
import 'crypto_utils.dart';
import 'encryption_service.dart';
import 'field_encryption_service.dart';

class DataShareOptions {
  final bool includeAnagrafica;
  final bool includeAgenda;
  final bool includeProgrammazione;
  final bool includeDocumenti;
  final bool includeAllegati;
  final bool includeContactNotes;
  final bool includeCatechesi;
  final bool includeAnnotazioni;

  /// Se valorizzato, limita la condivisione ai soli record della classe
  /// identificata dal codice univoco. Se `null`, condivide TUTTE le classi
  /// (equivalente alla modalità "Mio Dispositivo" del sync Bluetooth).
  final String? classUniqueCode;

  const DataShareOptions({
    this.includeAnagrafica = true,
    this.includeAgenda = true,
    this.includeProgrammazione = true,
    this.includeDocumenti = true,
    this.includeAllegati = false,
    this.includeContactNotes = false,
    this.includeCatechesi = false,
    this.includeAnnotazioni = false,
    this.classUniqueCode,
  });
}

/// Wrapper del payload cifrato con checksum SHA-256.
class DataPackage {
  final String encryptedData;
  final int totalChunks;
  final String checksum;

  DataPackage({
    required this.encryptedData,
    required this.totalChunks,
    required this.checksum,
  });

  Map<String, dynamic> toMap() => {
    'v': 2,
    'encryptedData': encryptedData,
    'totalChunks': totalChunks,
    'checksum': checksum,
  };
  factory DataPackage.fromMap(Map<String, dynamic> map) => DataPackage(
    encryptedData: map['encryptedData'] ?? '',
    totalChunks: map['totalChunks'] ?? 1,
    checksum: map['checksum'] ?? '',
  );
}

/// Singolo frammento QR con checksum per verifica integrità.
class QRChunk {
  final int chunkIndex;
  final int totalChunks;
  final String data;
  final String checksum;

  QRChunk({
    required this.chunkIndex,
    required this.totalChunks,
    required this.data,
    required this.checksum,
  });

  Map<String, dynamic> toMap() => {
    'i': chunkIndex,
    't': totalChunks,
    'd': data,
    'c': checksum,
  };
  factory QRChunk.fromMap(Map<String, dynamic> map) => QRChunk(
    chunkIndex: map['i'] ?? 0,
    totalChunks: map['t'] ?? 1,
    data: map['d'] ?? '',
    checksum: map['c'] ?? '',
  );
  String toJson() => jsonEncode(toMap());
  factory QRChunk.fromJson(String jsonStr) =>
      QRChunk.fromMap(jsonDecode(jsonStr));
}

class QRDataService {
  static const int maxQRSize = 1200;
  // PIN di 12 cifre: con 10^12 combinazioni e KDF PBKDF2-SHA256
  // (secureShareIterations = 350000) il brute-force offline del PIN QR diventa
  // impraticabile, anche per un pacchetto QR valido 3 minuti.
  static const int pinLength = 12;

  /// Genera un PIN numerico casuale di [pinLength] cifre (es. "385720147901").
  static String generatePin() {
    final random = Random.secure();
    return List.generate(pinLength, (_) => random.nextInt(10)).join();
  }

  /// Checksum SHA-256 (prime 8 cifre esadecimali) di una mappa dati.
  static String calculateChecksum(Map<String, dynamic> data) {
    return sha256HexSync(jsonEncode(data)).substring(0, 8);
  }

  /// Checksum SHA-256 (prime 12 cifre) di una stringa dati (payload cifrato).
  static String calculatePayloadChecksum(String data) {
    return sha256HexSync(data).substring(0, 12);
  }

  /// Comprime una mappa in Base64 (JSON → Base64).
  static String compressData(Map<String, dynamic> data) =>
      base64Encode(utf8.encode(jsonEncode(data)));

  /// Decomprime da Base64 a mappa.
  static Map<String, dynamic> decompressData(String compressed) {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(base64Decode(compressed))),
      );
    } catch (e) {
      throw Exception('Errore nella decompressione dei dati: $e');
    }
  }

  /// Segmenta una stringa in chunk di max [maxQRSize] caratteri.
  static List<String> segmentData(String data) {
    final chunks = <String>[];
    for (var i = 0; i < data.length; i += maxQRSize) {
      chunks.add(
        data.substring(
          i,
          (i + maxQRSize < data.length) ? i + maxQRSize : data.length,
        ),
      );
    }
    return chunks;
  }

  /// Crea un DataPackage cifrato con PIN temporaneo (valido 3 minuti).
  static Future<DataPackage> createPackage(
    Map<String, dynamic> data,
    String pin,
  ) async {
    final now = DateTime.now().toUtc();
    final packagePayload = {
      'meta': {
        'createdAt': now.toIso8601String(),
        'expiresAt': now.add(const Duration(minutes: 3)).toIso8601String(),
      },
      'payload': data,
    };
    final encryptedData = await EncryptionService.encryptData(
      packagePayload,
      pin,
      iterations: EncryptionService.secureShareIterations,
    );
    return DataPackage(
      encryptedData: encryptedData,
      totalChunks: 0,
      checksum: calculatePayloadChecksum(encryptedData),
    );
  }

  /// Crea un singolo QRChunk con checksum.
  static QRChunk createQRChunk(String data, int index, int total) {
    return QRChunk(
      chunkIndex: index,
      totalChunks: total,
      data: data,
      checksum: _calculateChunkChecksum(data),
    );
  }

  static String _calculateChunkChecksum(String data) =>
      sha256HexSync(data).substring(0, 4);

  static bool verifyChunkChecksum(QRChunk chunk) =>
      chunk.checksum == _calculateChunkChecksum(chunk.data);
  static bool verifyPackageChecksum(DataPackage package) =>
      package.checksum == calculatePayloadChecksum(package.encryptedData);

  /// Riassembla chunk ordinati per indice e verifica checksum di ognuno.
  static String assembleChunks(List<QRChunk> chunks) {
    chunks.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
    if (chunks.isEmpty) return '';
    if (chunks.length != chunks.first.totalChunks) {
      throw Exception(
        'Mancano ${chunks.first.totalChunks - chunks.length} chunk',
      );
    }
    for (final chunk in chunks) {
      if (!verifyChunkChecksum(chunk)) {
        throw Exception('Checksum non valido per chunk ${chunk.chunkIndex}');
      }
    }
    return chunks.map((c) => c.data).join();
  }

  /// Estrae il DataPackage dalla stringa assemblata.
  static DataPackage extractPackage(String assembledData) {
    try {
      final package = DataPackage.fromMap(decompressData(assembledData));
      if (!verifyPackageChecksum(package)) {
        throw Exception('Checksum del pacchetto non valido');
      }
      return package;
    } catch (e) {
      throw Exception("Errore nell'estrazione dei dati: $e");
    }
  }

  /// Decifra e restituisce i dati del pacchetto, verificando la scadenza.
  static Future<Map<String, dynamic>> extractPackageData(
    String assembledData,
    String pin,
  ) async {
    final package = extractPackage(assembledData);
    final decrypted = await EncryptionService.decryptData(
      package.encryptedData,
      pin,
    );
    if (!decrypted.containsKey('meta') || !decrypted.containsKey('payload')) {
      throw Exception('Pacchetto crittografato non valido');
    }
    final expiresAt = DateTime.parse(
      (decrypted['meta'] as Map)['expiresAt'] as String,
    ).toUtc();
    if (DateTime.now().toUtc().isAfter(expiresAt)) {
      throw Exception('Il pacchetto QR è scaduto');
    }
    return Map<String, dynamic>.from(decrypted['payload'] as Map);
  }

  /// Prepara i dati selezionati per la condivisione secondo [options].
  static Map<String, dynamic> prepareDataForShare(
    DataShareOptions options,
    Map<String, dynamic> allData,
  ) {
    final shareData = <String, dynamic>{};
    if (options.includeAnagrafica) {
      shareData['anagrafica'] = allData['anagrafica'] ?? {};
      shareData['allegati_studenti'] = allData['allegati_studenti'] ?? {};
    }
    if (options.includeAgenda) shareData['agenda'] = allData['agenda'] ?? {};
    if (options.includeProgrammazione) {
      shareData['programmazione'] = allData['programmazione'] ?? {};
      shareData['allegati_giornate'] = allData['allegati_giornate'] ?? {};
    }
    if (options.includeDocumenti) {
      shareData['documenti'] = allData['documenti'] ?? {};
    }
    if (options.includeContactNotes) {
      shareData['note_contatto'] = allData['note_contatto'] ?? {};
    }
    if (options.includeCatechesi) {
      shareData['catechesi'] = allData['catechesi'] ?? {};
      shareData['associazioni_catechesi'] =
          allData['associazioni_catechesi'] ?? {};
    }
    if (options.includeAnnotazioni) {
      shareData['annotazioni_giornaliere'] =
          allData['annotazioni_giornaliere'] ?? {};
    }
    return shareData;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DIFFERENTIAL SYNC — INDICE DATABASE E CONFRONTO
  // ═════════════════════════════════════════════════════════════════════════

  /// Costruisce l'indice del database locale per un sottoinsieme di moduli.
  /// L'indice contiene per ogni record: id, updatedAt, checksum del contenuto.
  static Map<String, dynamic> buildDatabaseIndex(DataShareOptions options) {
    final modules = <String, Map<String, dynamic>>{};
    final classCode = options.classUniqueCode;

    if (options.includeAnagrafica) {
      modules['anagrafica'] = _indexBox(
        LocalDatabase.students(),
        'students_box',
        classUniqueCode: classCode,
      );
      modules['classi'] = _indexBox(
        LocalDatabase.classes(),
        'classes_box',
        classUniqueCode: classCode,
      );
    }
    if (options.includeAgenda) {
      modules['agenda'] = _indexBox(
        LocalDatabase.attendance(),
        'attendance_box',
        classUniqueCode: classCode,
      );
    }
    if (options.includeProgrammazione) {
      modules['programmazione'] = _indexBox(
        LocalDatabase.planning(),
        'planning_box',
        classUniqueCode: classCode,
      );
    }
    if (options.includeDocumenti) {
      modules['documenti'] = _indexBox(
        LocalDatabase.documents(),
        'documents_box',
        classUniqueCode: classCode,
      );
      modules['consegne_documenti'] = _indexBox(
        LocalDatabase.documentDeliveries(),
        'document_deliveries_box',
        classUniqueCode: classCode,
      );
    }
    if (options.includeContactNotes) {
      modules['note_contatto'] = _indexBox(
        LocalDatabase.contactNotes(),
        'contact_notes_box',
        classUniqueCode: classCode,
      );
    }
    if (options.includeCatechesi) {
      modules['catechesi'] = _indexBox(
        LocalDatabase.catechesi(),
        'catechesi_box',
        classUniqueCode: classCode,
      );
      modules['associazioni_catechesi'] = _indexBox(
        LocalDatabase.meetingCatechesi(),
        'meeting_catechesi_box',
        classUniqueCode: classCode,
      );
    }
    if (options.includeAnnotazioni) {
      modules['annotazioni'] = _indexBox(
        LocalDatabase.studentDailyNotes(),
        'student_daily_notes_box',
        classUniqueCode: classCode,
      );
    }

    return {
      'v': 1,
      't': DateTime.now().toUtc().toIso8601String(),
      'm': modules,
    };
  }

  /// Indica un singolo box Hive: per ogni record estrae id e updatedAt.
  /// Supporta sia box Map che box con valori di altro tipo (es. List).
  /// Se [classUniqueCode] è valorizzato, filtra i record della sola classe.
  ///
  /// L4: l'indice NON include più il checksum del contenuto. In passato ogni
  /// voce era [id, updatedAt, checksum]: l'hash rendeva l'indice QR (mostrato
  /// in chiaro durante la condivisione) uno strumento per confrontare/finger
  /// stampare il contenuto dei record di un altro catechista. Ora l'indice
  /// espone solo la metadata minima indispensabile al diff (id + timestamp);
  /// i dati veri viaggiano SEMPRE cifrati col PIN nel pacchetto AES-GCM.
  static Map<String, dynamic> _indexBox(
    Box box,
    String boxName, {
    String? classUniqueCode,
  }) {
    final records = <List<dynamic>>[];
    String? globalLatestTs;

    for (final key in box.keys) {
      final id = key.toString();
      final raw = box.get(key);
      if (raw == null) continue;

      // M8 / Fase 3-9: i record demo non devono nemmeno essere annunciati.
      if (raw is Map) {
        final data = LocalDatabase.toStringDynamicMap(raw);
        if (data['_demo'] == true) continue;
      }

      if (classUniqueCode != null &&
          !_recordInClass(boxName, id, raw, classUniqueCode)) {
        continue;
      }

      final updatedAt = raw is Map
          ? _extractUpdatedAt(LocalDatabase.toStringDynamicMap(raw))
          : DateTime.now().toUtc().toIso8601String();

      records.add([id, updatedAt]);

      if (globalLatestTs == null || updatedAt.compareTo(globalLatestTs) > 0) {
        globalLatestTs = updatedAt;
      }
    }

    return {
      't':
          globalLatestTs ??
          DateTime.fromMillisecondsSinceEpoch(0).toUtc().toIso8601String(),
      'c': records.length,
      'r': records,
    };
  }

  static String _extractUpdatedAt(Map<String, dynamic> data) {
    final raw = data['updatedAt']?.toString();
    if (raw != null) {
      final dt = DateTime.tryParse(raw)?.toUtc();
      if (dt != null) return dt.toIso8601String();
    }
    return DateTime.fromMillisecondsSinceEpoch(0).toUtc().toIso8601String();
  }

  /// Determina se un record appartiene alla classe con [classUniqueCode].
  /// I record nelle box associative (consegne documenti, associazioni
  /// catechesi) vengono risolti tramite il record padre.
  static bool _recordInClass(
    String boxName,
    String id,
    dynamic raw,
    String classUniqueCode,
  ) {
    try {
      final data = raw is Map ? LocalDatabase.toStringDynamicMap(raw) : null;

      if (boxName == 'classes_box') {
        return data?['uniqueCode']?.toString() == classUniqueCode;
      }

      if (data != null) {
        final code = data['classUniqueCode']?.toString();
        if (code != null && code.isNotEmpty) {
          return code == classUniqueCode;
        }
        final classId = data['classId']?.toString();
        if (classId != null && classId.isNotEmpty) {
          return _classIdMatchesCode(classId, classUniqueCode);
        }
      }

      if (boxName == 'document_deliveries_box') {
        final docRaw = LocalDatabase.documents().get(id);
        if (docRaw != null) {
          final doc = LocalDatabase.toStringDynamicMap(docRaw);
          return doc['classUniqueCode']?.toString() == classUniqueCode;
        }
        return false;
      }

      if (boxName == 'meeting_catechesi_box') {
        final meetingRaw = LocalDatabase.planning().get(id);
        if (meetingRaw != null) {
          final meeting = LocalDatabase.toStringDynamicMap(meetingRaw);
          final classId = meeting['classId']?.toString();
          return classId != null &&
              classId.isNotEmpty &&
              _classIdMatchesCode(classId, classUniqueCode);
        }
        return false;
      }
    } catch (_) {}
    return false;
  }

  /// Risolve se il [classId] appartiene alla classe con [classUniqueCode].
  static bool _classIdMatchesCode(String classId, String classUniqueCode) {
    try {
      final classRaw = LocalDatabase.classes().get(classId);
      if (classRaw != null) {
        final classData = LocalDatabase.toStringDynamicMap(classRaw);
        return classData['uniqueCode']?.toString() == classUniqueCode;
      }
    } catch (_) {}
    return false;
  }

  /// Dato l'indice remoto [remoteIndex] e le opzioni di condivisione,
  /// calcola la differenza e restituisce SOLO i record da aggiornare
  /// nel formato atteso da DataExportService.importData().
  static Future<Map<String, dynamic>> computeDiffExport(
    Map<String, dynamic> remoteIndex,
    DataShareOptions options,
  ) async {
    final remoteModules = (remoteIndex['m'] as Map<String, dynamic>?) ?? {};
    final diff = <String, dynamic>{};
    final classCode = options.classUniqueCode;

    if (options.includeAnagrafica) {
      final studentsDiff = await _computeBoxDiff(
        remoteModules['anagrafica'],
        LocalDatabase.students(),
        'students_box',
        classUniqueCode: classCode,
      );
      final classesDiff = await _computeBoxDiff(
        remoteModules['classi'],
        LocalDatabase.classes(),
        'classes_box',
        classUniqueCode: classCode,
      );
      if (studentsDiff.isNotEmpty || classesDiff.isNotEmpty) {
        diff['anagrafica'] = {
          if (studentsDiff.isNotEmpty) 'students': studentsDiff,
          if (classesDiff.isNotEmpty) 'classes': classesDiff,
        };
      }
    }

    if (options.includeAgenda) {
      final agendaDiff = await _computeBoxDiff(
        remoteModules['agenda'],
        LocalDatabase.attendance(),
        'attendance_box',
        classUniqueCode: classCode,
      );
      if (agendaDiff.isNotEmpty) {
        diff['agenda'] = {'attendance': agendaDiff};
      }
    }

    if (options.includeProgrammazione) {
      final planningDiff = await _computeBoxDiff(
        remoteModules['programmazione'],
        LocalDatabase.planning(),
        'planning_box',
        classUniqueCode: classCode,
      );
      if (planningDiff.isNotEmpty) {
        diff['programmazione'] = {'planning': planningDiff};
      }
    }

    if (options.includeDocumenti) {
      final docsDiff = await _computeBoxDiff(
        remoteModules['documenti'],
        LocalDatabase.documents(),
        'documents_box',
        classUniqueCode: classCode,
      );
      final deliveriesDiff = await _computeBoxDiff(
        remoteModules['consegne_documenti'],
        LocalDatabase.documentDeliveries(),
        'document_deliveries_box',
        classUniqueCode: classCode,
      );
      if (docsDiff.isNotEmpty || deliveriesDiff.isNotEmpty) {
        diff['documenti'] = {
          if (docsDiff.isNotEmpty) 'documents': docsDiff,
          if (deliveriesDiff.isNotEmpty) 'deliveries': deliveriesDiff,
        };
      }
    }

    if (options.includeContactNotes) {
      final notesDiff = await _computeBoxDiff(
        remoteModules['note_contatto'],
        LocalDatabase.contactNotes(),
        'contact_notes_box',
        classUniqueCode: classCode,
      );
      if (notesDiff.isNotEmpty) {
        diff['note_contatto'] = {'notes': notesDiff};
      }
    }

    if (options.includeCatechesi) {
      final catechesiDiff = await _computeBoxDiff(
        remoteModules['catechesi'],
        LocalDatabase.catechesi(),
        'catechesi_box',
        classUniqueCode: classCode,
      );
      if (catechesiDiff.isNotEmpty) {
        diff['catechesi'] = {'catechesi': catechesiDiff};
      }
      final assocDiff = _computeSimpleBoxDiff(
        remoteModules['associazioni_catechesi'],
        LocalDatabase.meetingCatechesi(),
        classUniqueCode: classCode,
      );
      if (assocDiff.isNotEmpty) {
        diff['associazioni_catechesi'] = {'associazioni': assocDiff};
      }
    }

    if (options.includeAnnotazioni) {
      final annotDiff = await _computeBoxDiff(
        remoteModules['annotazioni'],
        LocalDatabase.studentDailyNotes(),
        'student_daily_notes_box',
        classUniqueCode: classCode,
      );
      if (annotDiff.isNotEmpty) {
        diff['annotazioni_giornaliere'] = {'notes': annotDiff};
      }
    }

    return diff;
  }

  /// Confronta i record locali con l'indice remoto e restituisce
  /// la lista dei record locali che sono nuovi o più aggiornati.
  static Future<List<Map<String, dynamic>>> _computeBoxDiff(
    dynamic remoteModuleData,
    Box<Map> localBox,
    String boxName, {
    String? classUniqueCode,
  }) async {
    if (remoteModuleData == null) {
      // Il modulo non esiste nel remoto: invia TUTTI i record locali
      return _allLocalRecords(
        localBox,
        boxName,
        classUniqueCode: classUniqueCode,
      );
    }

    final remoteRecords = _parseRemoteRecords(remoteModuleData);
    final needed = <Map<String, dynamic>>[];

    for (final key in localBox.keys) {
      final id = key.toString();
      final raw = localBox.get(key);
      if (raw == null) continue;
      final data = LocalDatabase.toStringDynamicMap(raw);
      // M8 / Fase 3 — item 9: esclude sempre i record demo (PII di esempio).
      if (data['_demo'] == true) continue;

      if (classUniqueCode != null &&
          !_recordInClass(boxName, id, data, classUniqueCode)) {
        continue;
      }

      final localUpdatedAt = _extractUpdatedAt(data);

      final remote = remoteRecords[id];
      if (remote == null) {
        // Record non presente nel remoto → invia
        final record = Map<String, dynamic>.from(data);
        record['id'] = id;
        needed.add(await _egressRecord(boxName, record));
      } else {
        final remoteTs = remote['ts'] as String;
        if (localUpdatedAt.compareTo(remoteTs) > 0) {
          // Locale più recente → invia
          final record = Map<String, dynamic>.from(data);
          record['id'] = id;
          needed.add(await _egressRecord(boxName, record));
        }
        // else: record identico o remoto più recente → salta
        // (L4: senza checksum nell'indice non si confrontano più i contenuti
        //  a parità di timestamp — l'hash non viene mai esposto in chiaro.)
      }
    }

    return needed;
  }

  /// Confronta record in un box non-Map (es. meetingCatechesi con valori List).
  static List<Map<String, dynamic>> _computeSimpleBoxDiff(
    dynamic remoteModuleData,
    Box localBox, {
    String? classUniqueCode,
  }) {
    if (remoteModuleData == null) {
      final all = <Map<String, dynamic>>[];
      for (final key in localBox.keys) {
        final id = key.toString();
        final val = localBox.get(key);
        if (val == null) continue;
        if (classUniqueCode != null &&
            !_recordInClass(
              'meeting_catechesi_box',
              id,
              val,
              classUniqueCode,
            )) {
          continue;
        }
        all.add({'meetingId': id, 'catechesiIds': val is List ? val : []});
      }
      return all;
    }

    final remoteRecords = _parseRemoteRecords(remoteModuleData);
    final needed = <Map<String, dynamic>>[];

    for (final key in localBox.keys) {
      final id = key.toString();
      final raw = localBox.get(key);
      if (raw == null) continue;

      if (classUniqueCode != null &&
          !_recordInClass('meeting_catechesi_box', id, raw, classUniqueCode)) {
        continue;
      }

      final remote = remoteRecords[id];

      if (remote == null) {
        needed.add({'meetingId': id, 'catechesiIds': raw is List ? raw : []});
      }
      // L4: senza checksum nell'indice, a parità di presenza remota non si
      // invia nulla (niente confronto dei contenuti in chiaro).
    }

    return needed;
  }

  /// Estrae TUTTI i record da un box (usato quando il remoto non ha il modulo).
  static Future<List<Map<String, dynamic>>> _allLocalRecords(
    Box<Map> box,
    String boxName, {
    String? classUniqueCode,
  }) async {
    final records = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      final id = key.toString();
      final raw = box.get(key);
      if (raw == null) continue;
      final data = LocalDatabase.toStringDynamicMap(raw);
      // M8 / Fase 3 — item 9: esclude sempre i record demo (PII di esempio).
      if (data['_demo'] == true) continue;
      if (classUniqueCode != null &&
          !_recordInClass(boxName, id, data, classUniqueCode)) {
        continue;
      }
      data['id'] = id;
      records.add(await _egressRecord(boxName, data));
    }
    return records;
  }

  /// Egresso QR share: i campi sensibili dello studente (cifrati per
  /// dispositivo) vengono decifrati prima della trasmissione. Il pacchetto è
  /// già protetto dal PIN (AES-256-GCM); il ricevente cifrerà con la propria
  /// chiave all'import ([DataExportService._mergeBoxRecords]).
  static Future<Map<String, dynamic>> _egressRecord(
    String boxName,
    Map<String, dynamic> record,
  ) async {
    if (boxName == 'students_box') {
      return FieldEncryptionService.decryptStudentMapForTransport(record);
    }
    return record;
  }

  /// Converte l'indice remoto in una mappa id → {ts} per confronto veloce.
  /// L4: l'indice trasporta solo id + timestamp; i checksum (cs) non vengono
  /// più trasmessi. Per retrocompatibilità un eventuale terzo elemento legacy
  /// viene ignorato.
  static Map<String, Map<String, String>> _parseRemoteRecords(
    dynamic moduleData,
  ) {
    final result = <String, Map<String, String>>{};
    if (moduleData is! Map) return result;
    final recordsList = (moduleData['r'] as List<dynamic>?) ?? [];
    for (final entry in recordsList) {
      if (entry is List && entry.length >= 2) {
        result[entry[0].toString()] = {'ts': entry[1].toString()};
      }
    }
    return result;
  }

  /// Serializza l'indice in chunk QR (ritorna mappe per compatibilità con compute).
  static List<Map<String, dynamic>> serializeIndexToChunks(
    Map<String, dynamic> indexMap,
  ) {
    final compressed = compressData(indexMap);
    final segments = segmentData(compressed);
    return segments
        .asMap()
        .entries
        .map(
          (entry) =>
              createQRChunk(entry.value, entry.key, segments.length).toMap(),
        )
        .toList();
  }

  /// Deserializza una lista di chunk QR in una mappa indice.
  static Map<String, dynamic> deserializeIndexFromChunks(List<QRChunk> chunks) {
    final assembled = assembleChunks(chunks);
    return decompressData(assembled);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // A9 — INDICE CIFRATO CON IL PIN DI SESSIONE
  // ═════════════════════════════════════════════════════════════════════════

  /// Cifra l'indice del database con il PIN di sessione e lo segmenta in
  /// chunk QR.
  ///
  /// A9: l'indice (id + timestamp dei record) NON viaggia più in chiaro.
  /// Sebbene contenga solo metadati opachi, cifrarlo impedisce che un terzo
  /// possa fotografare/leggere l'elenco dei record esistenti durante la
  /// condivisione (metadata exposure). Il PIN è quello generato dal mittente
  /// all'inizio del flusso e comunicato al ricevente prima dello scambio.
  static Future<List<Map<String, dynamic>>> encryptIndexToChunks(
    Map<String, dynamic> indexMap,
    String pin,
  ) async {
    final package = await createPackage(indexMap, pin);
    final compressedPackage = compressData(package.toMap());
    final segments = segmentData(compressedPackage);
    return segments
        .asMap()
        .entries
        .map(
          (entry) =>
              createQRChunk(entry.value, entry.key, segments.length).toMap(),
        )
        .toList();
  }

  /// Riassembla e decifra un indice ricevuto (cifrato con il PIN di sessione).
  /// Lancia [Exception] se il PIN è errato, i chunk sono incompleti/corrotti
  /// o il pacchetto è scaduto.
  static Future<Map<String, dynamic>> decryptIndexFromChunks(
    List<QRChunk> chunks,
    String pin,
  ) async {
    final assembled = assembleChunks(chunks);
    return extractPackageData(assembled, pin);
  }
}
