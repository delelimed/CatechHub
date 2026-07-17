import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

import '../data/classic_sync_models.dart';
import 'classic_connection_manager.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/storage/local_database.dart';

/// Motore di sincronizzazione P2P con logica CRDT Last-Write-Wins (LWW).
///
/// CONTESTO PROGETTO:
/// Questo è il cuore logico della sincronizzazione. Opera a livello di
/// Box Hive: estrae i record modificati da ogni box, li serializza,
/// li cifra con la chiave del dispositivo remoto, li trasmette via
/// [ClassicConnectionManager], e applica i record ricevuti con logica
/// LWW (vince il timestamp updatedAt più recente).
///
/// SICUREZZA:
/// - La box catechesi (contenuti didattici) è ESCLUSA dalla sync sia
///   in estrazione (extractModifiedRecords) che in applicazione
///   (applyRemoteRecord), per proteggere i dati sensibili delle lezioni.
/// - Il payload è cifrato con EncryptionService usando la chiave derivata
///   ECDH + HKDF specifica per ogni coppia di dispositivi.
///
/// GESTIONE:
/// - Estrazione dei record modificati dall'ultima sincronizzazione
/// - Confronto timestamp updatedAt per risoluzione conflitti
/// - Cifratura/decifratura dei payload tramite la chiave condivisa
/// - Applicazione delle modifiche ricevute al database locale
/// - Filtro di esclusione: la box catechesi NON viene mai sincronizzata
class ClassicSyncEngine {
  static final ClassicSyncEngine _instance = ClassicSyncEngine._();
  factory ClassicSyncEngine() => _instance;
  ClassicSyncEngine._();

  final ClassicConnectionManager _connectionManager =
      ClassicConnectionManager();

  /// Box Hive che partecipano alla sincronizzazione.
  ///
  /// IMPORTANTE: La box catechesi (catechesi_box) e stata ESCLUSA
  /// dalla sincronizzazione in modo tassativo. I contenuti didattici
  /// delle lezioni NON vengono mai trasmessi tra dispositivi.
  static const _syncableBoxes = {
    LocalDatabase.studentsBox: 'students',
    LocalDatabase.classesBox: 'classes',
    LocalDatabase.planningBox: 'planning',
    LocalDatabase.attendanceBox: 'attendance',
    LocalDatabase.documentsBox: 'documents',
    LocalDatabase.documentDeliveriesBox: 'document_deliveries',
    LocalDatabase.contactNotesBox: 'contact_notes',
    LocalDatabase.studentDailyNotesBox: 'student_daily_notes',
  };

  /// Estrae tutti i record modificati dopo un timestamp specifico da tutte le box.
  ///
  /// La box catechesi viene saltata esplicitamente.
  Future<List<SyncableRecord>> extractModifiedRecords(DateTime since) async {
    final records = <SyncableRecord>[];

    for (final entry in _syncableBoxes.entries) {
      final boxName = entry.key;
      final box = Hive.box<Map>(boxName);

      for (final key in box.keys) {
        final id = key.toString();
        final data = LocalDatabase.toStringDynamicMap(box.get(key));

        final updatedAt =
            DateTime.tryParse(data['updatedAt']?.toString() ?? '')?.toUtc() ??
                DateTime.tryParse(data['createdAt']?.toString() ?? '')
                        ?.toUtc() ??
                    DateTime.fromMillisecondsSinceEpoch(0).toUtc();

        if (updatedAt.isAfter(since.toUtc())) {
          records.add(SyncableRecord(
            id: id,
            boxName: boxName,
            data: data,
            createdAt:
                DateTime.tryParse(data['createdAt']?.toString() ?? '')
                        ?.toUtc() ??
                    DateTime.now().toUtc(),
            updatedAt: updatedAt,
            isDeleted: data['isDeleted'] == true,
          ));
        }
      }
    }

    return records;
  }

  /// Verifica se ci sono variazioni nei dati locali rispetto a un timestamp.
  ///
  /// Usato dal ruolo "Altro Catechista" per determinare se mostrare
  /// la richiesta di conferma all'utente prima di sincronizzare.
  Future<bool> hasPendingChanges(DateTime since) async {
    for (final entry in _syncableBoxes.entries) {
      final box = Hive.box<Map>(entry.key);

      for (final key in box.keys) {
        final data = LocalDatabase.toStringDynamicMap(box.get(key));

        final updatedAt =
            DateTime.tryParse(data['updatedAt']?.toString() ?? '')?.toUtc() ??
                DateTime.tryParse(data['createdAt']?.toString() ?? '')
                        ?.toUtc() ??
                    DateTime.fromMillisecondsSinceEpoch(0).toUtc();

        if (updatedAt.isAfter(since.toUtc())) {
          return true;
        }
      }
    }

    return false;
  }

  /// Applica un record ricevuto dal dispositivo remoto al database locale.
  /// Usa la logica LWW (Last-Write-Wins) per risolvere i conflitti.
  ///
  /// Se il record proviene dalla box catechesi (boxName contiene "catechesi"),
  /// viene scartato immediatamente prima del salvataggio.
  Future<void> applyRemoteRecord(SyncableRecord remote) async {
    if (!_syncableBoxes.containsKey(remote.boxName)) return;

    final box = Hive.box<Map>(remote.boxName);
    final localData = LocalDatabase.toStringDynamicMap(box.get(remote.id));

    if (localData.isEmpty) {
      if (!remote.isDeleted) {
        await box.put(remote.id, remote.data);
      }
      return;
    }

    final localUpdatedAt =
        DateTime.tryParse(localData['updatedAt']?.toString() ?? '')?.toUtc() ??
            DateTime.tryParse(localData['createdAt']?.toString() ?? '')
                    ?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0).toUtc();

    if (remote.winsOver(SyncableRecord(
      id: remote.id,
      boxName: remote.boxName,
      data: localData,
      createdAt: DateTime.tryParse(localData['createdAt']?.toString() ?? '')
              ?.toUtc() ??
          DateTime.now().toUtc(),
      updatedAt: localUpdatedAt,
      isDeleted: localData['isDeleted'] == true,
    ))) {
      if (remote.isDeleted) {
        final mergedData = Map<String, dynamic>.from(localData);
        mergedData['isDeleted'] = true;
        mergedData['updatedAt'] = remote.updatedAt.toIso8601String();
        await box.put(remote.id, mergedData);
      } else {
        await box.put(remote.id, remote.data);
      }
    }
  }

  /// Prepara i dati per la trasmissione: serializza e cifra.
  ///
  /// Utilizza la chiave del dispositivo remoto specifico dalla tabella
  /// TrustedDevices, permettendo la sincronizzazione multi-dispositivo
  /// con chiavi differenti per ciascun catechista.
  ///
  /// Il payload viene terminato dal carattere \n per il framing seriale.
  Future<String> preparePayload(
    List<SyncableRecord> records, {
    required String remoteDeviceId,
  }) async {
    final payload = {
      'records': records.map((r) => r.toMap()).toList(),
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'recordCount': records.length,
    };

    final remoteKey =
        await ClassicPairingService.getTrustedDeviceKey(remoteDeviceId);
    if (remoteKey == null) {
      throw Exception(
        'Nessuna chiave trovata per il dispositivo $remoteDeviceId '
        'nella tabella TrustedDevices.',
      );
    }

    return EncryptionService.encryptData(
      payload,
      remoteKey,
      iterations: EncryptionService.fastShareIterations,
    );
  }

  /// Decifrifica e applica i dati ricevuti dal dispositivo remoto.
  ///
  /// Cerca la chiave nella tabella TrustedDevices per il dispositivo mittente.
  /// Qualsiasi record imprevisto marcato come catechesi viene scartato
  /// immediatamente prima del salvataggio.
  Future<int> applyReceivedPayload(
    String encryptedPayload, {
    required String remoteDeviceId,
  }) async {
    final senderKey =
        await ClassicPairingService.getTrustedDeviceKey(remoteDeviceId);
    if (senderKey == null) {
      throw Exception(
        'Nessuna chiave trovata per il mittente $remoteDeviceId '
        'nella tabella TrustedDevices.',
      );
    }

    final decrypted = EncryptionService.decryptData(
      encryptedPayload,
      senderKey,
    );

    final recordsList = decrypted['records'] as List<dynamic>? ?? [];
    var appliedCount = 0;

    for (final recordData in recordsList) {
      final record = SyncableRecord.fromMap(
        Map<String, dynamic>.from(recordData as Map),
      );

      // FILTRO DI ESCLUSIONE: scarta qualsiasi record che appartenga
      // alla box catechesi (contenuti didattici delle lezioni).
      if (record.boxName.toLowerCase().contains('catechesi')) {
        continue;
      }

      await applyRemoteRecord(record);
      appliedCount++;
    }

    await ClassicPairingService.saveLastSyncTimestamp(DateTime.now().toUtc());

    return appliedCount;
  }

  /// Timeout per la ricezione dei dati dall'altro dispositivo (30 secondi).
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// Esegue una sessione di sincronizzazione completa bidirezionale
  /// con un singolo dispositivo remoto dalla tabella TrustedDevices.
  Future<SyncResult> performSync({required String remoteDeviceId}) async {
    try {
      if (!_connectionManager.isConnected) {
        throw Exception('Non connesso a nessun dispositivo');
      }

      final lastSync = await ClassicPairingService.getLastSyncTimestamp();

      final localRecords = await extractModifiedRecords(lastSync);

      final messageId = _generateMessageId();
      var sentCount = 0;
      if (localRecords.isNotEmpty) {
        final payload = await preparePayload(
          localRecords,
          remoteDeviceId: remoteDeviceId,
        );
        await _connectionManager.sendPayload(payload, messageId);
        sentCount = localRecords.length;
      }

      int appliedCount = 0;

      await for (final payload
          in _connectionManager.onPayloadReceived.timeout(receiveTimeout)) {
        try {
          appliedCount += await applyReceivedPayload(
            payload,
            remoteDeviceId: remoteDeviceId,
          );
        } catch (e) {
          // Log errore decifratura ma continua
        }
        break;
      }

      return SyncResult(
        success: true,
        sentRecords: sentCount,
        receivedRecords: appliedCount,
        syncTimestamp: DateTime.now().toUtc(),
      );
    } on TimeoutException {
      return SyncResult(
        success: false,
        error: 'Timeout: nessuna risposta dall\'altro dispositivo '
            '(${receiveTimeout.inSeconds}s)',
        syncTimestamp: DateTime.now().toUtc(),
      );
    } catch (e) {
      return SyncResult(
        success: false,
        error: e.toString(),
        syncTimestamp: DateTime.now().toUtc(),
      );
    }
  }

  /// Esegue la sincronizzazione con un singolo dispositivo.
  Future<SyncResult> performSyncForDevice({
    required String remoteDeviceId,
  }) async {
    final result = await performSync(remoteDeviceId: remoteDeviceId);

    if (result.success) {
      await ClassicPairingService.updateDeviceLastSyncedAt(
        remoteDeviceId,
        DateTime.now().toUtc(),
      );
    }

    return result;
  }

  String _generateMessageId() {
    final bytes = DateTime.now().toUtc().toIso8601String().codeUnits;
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }
}
