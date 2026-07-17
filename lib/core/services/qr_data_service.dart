// ══════════════════════════════════════════════════════════════════════════════
// qr_data_service.dart — CatechHub (condivisione dati via QR code)
//
// Gestisce la creazione, cifratura, segmentazione e decodifica dei
// pacchetti di dati scambiati tramite QR code tra dispositivi.
//
// CONTESTO PROGETTO:
//   La condivisione dati è uno dei canali di sincronizzazione (l'alternativa
//   al Bluetooth RFCOMM). Il flusso è:
//   1. L'utente sceglie i dati da condividere (DataShareOptions)
//   2. I dati vengono cifrati con PIN temporaneo (AES-256-GCM, 12k iterazioni)
//   3. Il pacchetto cifrato viene segmentato in QRChunk (max 1200 byte cad.)
//   4. Ogni chunk ha checksum SHA-256 per rilevare corruzione
//   5. Il destinatario scansiona i QR, riassembla, verifica checksum, decifra
//
//   Il PIN è un numero casuale di 8 cifre, valido 3 minuti.
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
//   - EncryptionService: cifratura AES-256-GCM con fast PBKDF2 (12k iter)
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'encryption_service.dart';

class DataShareOptions {
  final bool includeAnagrafica;
  final bool includeAgenda;
  final bool includeProgrammazione;
  final bool includeDocumenti;
  final bool includeAllegati;
  final bool includeContactNotes;
  final bool includeCatechesi;
  final bool includeAnnotazioni;

  const DataShareOptions({
    this.includeAnagrafica = true,
    this.includeAgenda = true,
    this.includeProgrammazione = true,
    this.includeDocumenti = true,
    this.includeAllegati = false,
    this.includeContactNotes = false,
    this.includeCatechesi = false,
    this.includeAnnotazioni = false,
  });
}

/// Wrapper del payload cifrato con checksum SHA-256.
class DataPackage {
  final String encryptedData;
  final int totalChunks;
  final String checksum;

  DataPackage({required this.encryptedData, required this.totalChunks, required this.checksum});

  Map<String, dynamic> toMap() => {'v': 2, 'encryptedData': encryptedData, 'totalChunks': totalChunks, 'checksum': checksum};
  factory DataPackage.fromMap(Map<String, dynamic> map) => DataPackage(
    encryptedData: map['encryptedData'] ?? '', totalChunks: map['totalChunks'] ?? 1, checksum: map['checksum'] ?? '');
}

/// Singolo frammento QR con checksum per verifica integrità.
class QRChunk {
  final int chunkIndex;
  final int totalChunks;
  final String data;
  final String checksum;

  QRChunk({required this.chunkIndex, required this.totalChunks, required this.data, required this.checksum});

  Map<String, dynamic> toMap() => {'i': chunkIndex, 't': totalChunks, 'd': data, 'c': checksum};
  factory QRChunk.fromMap(Map<String, dynamic> map) =>
    QRChunk(chunkIndex: map['i'] ?? 0, totalChunks: map['t'] ?? 1, data: map['d'] ?? '', checksum: map['c'] ?? '');
  String toJson() => jsonEncode(toMap());
  factory QRChunk.fromJson(String jsonStr) => QRChunk.fromMap(jsonDecode(jsonStr));
}

class QRDataService {
  static const int maxQRSize = 1200;
  static const int pinLength = 8;

  /// Genera un PIN numerico casuale di [pinLength] cifre (es. "38572014").
  static String generatePin() {
    final random = Random.secure();
    return List.generate(pinLength, (_) => random.nextInt(10)).join();
  }

  /// Checksum SHA-256 (prime 8 cifre esadecimali) di una mappa dati.
  static String calculateChecksum(Map<String, dynamic> data) {
    return sha256.convert(utf8.encode(jsonEncode(data))).toString().substring(0, 8);
  }

  /// Checksum SHA-256 (prime 12 cifre) di una stringa dati (payload cifrato).
  static String calculatePayloadChecksum(String data) {
    return sha256.convert(utf8.encode(data)).toString().substring(0, 12);
  }

  /// Comprime una mappa in Base64 (JSON → Base64).
  static String compressData(Map<String, dynamic> data) => base64Encode(utf8.encode(jsonEncode(data)));

  /// Decomprime da Base64 a mappa.
  static Map<String, dynamic> decompressData(String compressed) {
    try { return Map<String, dynamic>.from(jsonDecode(utf8.decode(base64Decode(compressed)))); }
    catch (e) { throw Exception('Errore nella decompressione dei dati: $e'); }
  }

  /// Segmenta una stringa in chunk di max [maxQRSize] caratteri.
  static List<String> segmentData(String data) {
    final chunks = <String>[];
    for (var i = 0; i < data.length; i += maxQRSize) {
      chunks.add(data.substring(i, (i + maxQRSize < data.length) ? i + maxQRSize : data.length));
    }
    return chunks;
  }

  /// Crea un DataPackage cifrato con PIN temporaneo (valido 3 minuti).
  static DataPackage createPackage(Map<String, dynamic> data, String pin) {
    final now = DateTime.now().toUtc();
    final packagePayload = {
      'meta': {'createdAt': now.toIso8601String(), 'expiresAt': now.add(const Duration(minutes: 3)).toIso8601String()},
      'payload': data,
    };
    final encryptedData = EncryptionService.encryptData(packagePayload, pin, iterations: EncryptionService.fastShareIterations);
    return DataPackage(encryptedData: encryptedData, totalChunks: 0, checksum: calculatePayloadChecksum(encryptedData));
  }

  /// Crea un singolo QRChunk con checksum.
  static QRChunk createQRChunk(String data, int index, int total) {
    return QRChunk(chunkIndex: index, totalChunks: total, data: data, checksum: _calculateChunkChecksum(data));
  }

  static String _calculateChunkChecksum(String data) =>
    sha256.convert(utf8.encode(data)).toString().substring(0, 4);

  static bool verifyChunkChecksum(QRChunk chunk) => chunk.checksum == _calculateChunkChecksum(chunk.data);
  static bool verifyPackageChecksum(DataPackage package) => package.checksum == calculatePayloadChecksum(package.encryptedData);

  /// Riassembla chunk ordinati per indice e verifica checksum di ognuno.
  static String assembleChunks(List<QRChunk> chunks) {
    chunks.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
    if (chunks.isEmpty) return '';
    if (chunks.length != chunks.first.totalChunks) {
      throw Exception('Mancano ${chunks.first.totalChunks - chunks.length} chunk');
    }
    for (final chunk in chunks) {
      if (!verifyChunkChecksum(chunk)) throw Exception('Checksum non valido per chunk ${chunk.chunkIndex}');
    }
    return chunks.map((c) => c.data).join();
  }

  /// Estrae il DataPackage dalla stringa assemblata.
  static DataPackage extractPackage(String assembledData) {
    try {
      final package = DataPackage.fromMap(decompressData(assembledData));
      if (!verifyPackageChecksum(package)) throw Exception('Checksum del pacchetto non valido');
      return package;
    } catch (e) {
      throw Exception("Errore nell'estrazione dei dati: $e");
    }
  }

  /// Decifra e restituisce i dati del pacchetto, verificando la scadenza.
  static Map<String, dynamic> extractPackageData(String assembledData, String pin) {
    final package = extractPackage(assembledData);
    final decrypted = EncryptionService.decryptData(package.encryptedData, pin);
    if (!decrypted.containsKey('meta') || !decrypted.containsKey('payload')) {
      throw Exception('Pacchetto crittografato non valido');
    }
    final expiresAt = DateTime.parse((decrypted['meta'] as Map)['expiresAt'] as String).toUtc();
    if (DateTime.now().toUtc().isAfter(expiresAt)) throw Exception('Il pacchetto QR è scaduto');
    return Map<String, dynamic>.from(decrypted['payload'] as Map);
  }

  /// Prepara i dati selezionati per la condivisione secondo [options].
  static Map<String, dynamic> prepareDataForShare(DataShareOptions options, Map<String, dynamic> allData) {
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
    if (options.includeDocumenti) shareData['documenti'] = allData['documenti'] ?? {};
    if (options.includeContactNotes) shareData['note_contatto'] = allData['note_contatto'] ?? {};
    if (options.includeCatechesi) {
      shareData['catechesi'] = allData['catechesi'] ?? {};
      shareData['associazioni_catechesi'] = allData['associazioni_catechesi'] ?? {};
    }
    if (options.includeAnnotazioni) shareData['annotazioni_giornaliere'] = allData['annotazioni_giornaliere'] ?? {};
    return shareData;
  }
}
