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

  const DataShareOptions({
    this.includeAnagrafica = true,
    this.includeAgenda = true,
    this.includeProgrammazione = true,
    this.includeDocumenti = true,
    this.includeAllegati = false,
  });
}

class DataPackage {
  final String encryptedData;
  final int totalChunks;
  final String checksum;

  DataPackage({
    required this.encryptedData,
    required this.totalChunks,
    required this.checksum,
  });

  Map<String, dynamic> toMap() {
    return {
      'v': 2,
      'encryptedData': encryptedData,
      'totalChunks': totalChunks,
      'checksum': checksum,
    };
  }

  factory DataPackage.fromMap(Map<String, dynamic> map) {
    return DataPackage(
      encryptedData: map['encryptedData'] ?? '',
      totalChunks: map['totalChunks'] ?? 1,
      checksum: map['checksum'] ?? '',
    );
  }
}

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

  Map<String, dynamic> toMap() {
    return {'i': chunkIndex, 't': totalChunks, 'd': data, 'c': checksum};
  }

  factory QRChunk.fromMap(Map<String, dynamic> map) {
    return QRChunk(
      chunkIndex: map['i'] ?? 0,
      totalChunks: map['t'] ?? 1,
      data: map['d'] ?? '',
      checksum: map['c'] ?? '',
    );
  }

  String toJson() {
    return jsonEncode(toMap());
  }

  factory QRChunk.fromJson(String jsonStr) {
    return QRChunk.fromMap(jsonDecode(jsonStr));
  }
}

class QRDataService {
  static const int maxQRSize = 1200;
  static const int pinLength = 8;

  static String generatePin() {
    final random = Random.secure();
    return List.generate(pinLength, (_) => random.nextInt(10)).join();
  }

  static String calculateChecksum(Map<String, dynamic> data) {
    final jsonString = jsonEncode(data);
    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 8);
  }

  static String calculatePayloadChecksum(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 12);
  }

  static String compressData(Map<String, dynamic> data) {
    final jsonString = jsonEncode(data);
    return base64Encode(utf8.encode(jsonString));
  }

  static Map<String, dynamic> decompressData(String compressed) {
    try {
      final decoded = utf8.decode(base64Decode(compressed));
      return Map<String, dynamic>.from(jsonDecode(decoded));
    } catch (e) {
      throw Exception('Errore nella decompressione dei dati: $e');
    }
  }

  static List<String> segmentData(String data) {
    final chunks = <String>[];
    for (var i = 0; i < data.length; i += maxQRSize) {
      final end = (i + maxQRSize < data.length) ? i + maxQRSize : data.length;
      chunks.add(data.substring(i, end));
    }
    return chunks;
  }

  static DataPackage createPackage(Map<String, dynamic> data, String pin) {
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(const Duration(minutes: 3));

    final packagePayload = {
      'meta': {
        'createdAt': now.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
      },
      'payload': data,
    };

    final encryptedData = EncryptionService.encryptData(
      packagePayload,
      pin,
      iterations: EncryptionService.fastShareIterations,
    );
    final checksum = calculatePayloadChecksum(encryptedData);

    return DataPackage(
      encryptedData: encryptedData,
      totalChunks: 0,
      checksum: checksum,
    );
  }

  static QRChunk createQRChunk(String data, int index, int total) {
    final chunkChecksum = _calculateChunkChecksum(data);
    return QRChunk(
      chunkIndex: index,
      totalChunks: total,
      data: data,
      checksum: chunkChecksum,
    );
  }

  static String _calculateChunkChecksum(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 4);
  }

  static bool verifyChunkChecksum(QRChunk chunk) {
    final expectedChecksum = _calculateChunkChecksum(chunk.data);
    return chunk.checksum == expectedChecksum;
  }

  static bool verifyPackageChecksum(DataPackage package) {
    final expectedChecksum = calculatePayloadChecksum(package.encryptedData);
    return package.checksum == expectedChecksum;
  }

  static String assembleChunks(List<QRChunk> chunks) {
    chunks.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));

    if (chunks.isEmpty) return '';

    final total = chunks.first.totalChunks;
    if (chunks.length != total) {
      throw Exception('Mancano ${total - chunks.length} chunk');
    }

    for (final chunk in chunks) {
      if (!verifyChunkChecksum(chunk)) {
        throw Exception('Checksum non valido per chunk ${chunk.chunkIndex}');
      }
    }

    return chunks.map((chunk) => chunk.data).join();
  }

  static DataPackage extractPackage(String assembledData) {
    try {
      final package = DataPackage.fromMap(decompressData(assembledData));
      if (!verifyPackageChecksum(package)) {
        throw Exception('Checksum del pacchetto non valido');
      }
      return package;
    } catch (e) {
      throw Exception('Errore nell\'estrazione dei dati: $e');
    }
  }

  static Map<String, dynamic> extractPackageData(
    String assembledData,
    String pin,
  ) {
    final package = extractPackage(assembledData);
    final decrypted = EncryptionService.decryptData(package.encryptedData, pin);

    if (!decrypted.containsKey('meta') || !decrypted.containsKey('payload')) {
      throw Exception('Pacchetto crittografato non valido');
    }

    final meta = Map<String, dynamic>.from(decrypted['meta'] as Map);
    final expiresAt = DateTime.parse(meta['expiresAt'] as String).toUtc();
    final now = DateTime.now().toUtc();

    if (now.isAfter(expiresAt)) {
      throw Exception('Il pacchetto QR è scaduto');
    }

    return Map<String, dynamic>.from(decrypted['payload'] as Map);
  }

  static Map<String, dynamic> prepareDataForShare(
    DataShareOptions options,
    Map<String, dynamic> allData,
  ) {
    final shareData = <String, dynamic>{};

    if (options.includeAnagrafica) {
      shareData['anagrafica'] = allData['anagrafica'] ?? {};
      shareData['allegati_studenti'] = allData['allegati_studenti'] ?? {};
    }

    if (options.includeAgenda) {
      shareData['agenda'] = allData['agenda'] ?? {};
    }

    if (options.includeProgrammazione) {
      shareData['programmazione'] = allData['programmazione'] ?? {};
      shareData['allegati_giornate'] = allData['allegati_giornate'] ?? {};
    }

    if (options.includeDocumenti) {
      shareData['documenti'] = allData['documenti'] ?? {};
    }

    return shareData;
  }
}
