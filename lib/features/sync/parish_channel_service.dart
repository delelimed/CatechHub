// ══════════════════════════════════════════════════════════════════════════════
// parish_channel_service.dart — CatechHub (Canale Parrocchiale globale)
//
// Modulo "Rete Catechistica Parrocchiale". Gestisce i dati del Global Parish
// Channel: riunioni/eventi parrocchiali e avvisi generali (senza classe).
//
// CONTESTO PROGETTO:
//   Questi dati sono considerati pubblici per la rete parrocchiale e vengono
//   scambiati IN CHIARO tra tutti i dispositivi associati, indipendentemente
//   dal titolo sulle singole classi. Sono quindi sincronizzabili anche con
//   dispositivi "Senza Titolo" per le classi.
//
//   Il payload di sync usa lo stesso formato SyncRecord del HiveSyncEngine
//   (LWW su updatedAt) per coerenza con il resto dell'app.
//
// STORAGE:
//   - Riunioni: box "parish_events_box" (chiave = id).
//   - Avvisi parrocchiali: box "avvisi_box" con classUniqueCode == null.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:hive/hive.dart';

import '../../core/services/crypto_utils.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models/avviso_template_model.dart';
import '../../shared/models/parish_event.dart';
import 'p2p/hive_sync_engine.dart';

class ParishChannelService {
  ParishChannelService._();

  static Box<Map> get _eventsBox => LocalDatabase.parishEvents();
  static Box<Map> get _avvisiBox => LocalDatabase.avvisi();

  // ─────────────────────────────────────────────────────────────────────────
  // RIUNIONI / EVENTI PARROCCHIALI
  // ─────────────────────────────────────────────────────────────────────────

  static List<ParishEvent> getAllEvents() {
    return LocalDatabase.values(
      _eventsBox,
      (id, data) => ParishEvent.fromMap(id, data),
    )..sort((a, b) => b.date.compareTo(a.date));
  }

  static Stream<List<ParishEvent>> watchAllEvents() {
    return LocalDatabase.watchList(
      _eventsBox,
      (id, data) => ParishEvent.fromMap(id, data),
    );
  }

  static Future<ParishEvent> saveEvent(ParishEvent event) async {
    final id = event.id.isEmpty
        ? LocalDatabase.newId('parish_event')
        : event.id;
    await _eventsBox.put(id, event.toMap());
    return ParishEvent.fromMap(
      id,
      LocalDatabase.toStringDynamicMap(_eventsBox.get(id)),
    );
  }

  static Future<void> deleteEvent(String id) async {
    await _eventsBox.delete(id);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AVVISI PARROCCHIALI (globali, senza classe)
  // ─────────────────────────────────────────────────────────────────────────

  static List<AvvisoTemplate> getAllParishAvvisi() {
    return LocalDatabase.values(
      _avvisiBox,
      (id, data) => AvvisoTemplate.fromMap(id, data),
    ).where((a) => a.classUniqueCode == null).toList();
  }

  static Future<AvvisoTemplate> saveParishAvviso(AvvisoTemplate avviso) async {
    final id = avviso.id.isEmpty
        ? LocalDatabase.newId('avviso_parrocchia')
        : avviso.id;
    await _avvisiBox.put(id, avviso.toMap());
    return AvvisoTemplate.fromMap(
      id,
      LocalDatabase.toStringDynamicMap(_avvisiBox.get(id)),
    );
  }

  static Future<void> deleteParishAvviso(String id) async {
    await _avvisiBox.delete(id);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SYNC DEL CANALE GLOBALE (in chiaro per la rete)
  // ─────────────────────────────────────────────────────────────────────────

  /// Costruisce il payload da inviare: record SyncRecord per eventi e avvisi
  /// parrocchiali. Ritorna `{ 'events': [...], 'avvisi': [...] }`.
  static Map<String, dynamic> buildChannelPayload() {
    final events = <Map<String, dynamic>>[];
    for (final key in _eventsBox.keys) {
      final id = key.toString();
      final raw = _eventsBox.get(id);
      if (raw == null) continue;
      events.add(
        SyncRecord.fromHiveEntry(
          id: id,
          boxName: LocalDatabase.parishEventsBox,
          entry: LocalDatabase.toStringDynamicMap(raw),
        ).toJson(),
      );
    }

    final avvisi = <Map<String, dynamic>>[];
    for (final key in _avvisiBox.keys) {
      final id = key.toString();
      final raw = _avvisiBox.get(id);
      if (raw == null) continue;
      final data = LocalDatabase.toStringDynamicMap(raw);
      final code = data['classUniqueCode']?.toString();
      if (code != null && code.isNotEmpty) continue;
      avvisi.add(
        SyncRecord.fromHiveEntry(
          id: id,
          boxName: LocalDatabase.avvisiBox,
          entry: data,
        ).toJson(),
      );
    }

    return {
      'events': events,
      'avvisi': avvisi,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Applica un payload ricevuto dal canale parrocchiale con merge LWW.
  /// Ritorna il numero totale di record applicati.
  static Future<int> applyChannelPayload(Map<String, dynamic> payload) async {
    var applied = 0;
    applied += await _mergeIntoBox(
      LocalDatabase.parishEventsBox,
      payload['events'] as List<dynamic>? ?? const [],
    );
    applied += await _mergeIntoBox(
      LocalDatabase.avvisiBox,
      payload['avvisi'] as List<dynamic>? ?? const [],
    );
    return applied;
  }

  static Future<int> _mergeIntoBox(
    String boxName,
    List<dynamic> serialized,
  ) async {
    var applied = 0;
    final box = boxName == LocalDatabase.avvisiBox ? _avvisiBox : _eventsBox;
    for (final raw in serialized) {
      if (raw is! Map) continue;
      final record = SyncRecord.fromJson(Map<String, dynamic>.from(raw));
      try {
        final localRaw = box.get(record.id);
        if (localRaw == null) {
          if (record.isDeleted) continue;
          await box.put(record.id, record.data);
          applied++;
          continue;
        }
        final localData = LocalDatabase.toStringDynamicMap(localRaw);
        final localUpdatedAt =
            DateTime.tryParse(
              localData['updatedAt']?.toString() ?? '',
            )?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0).toUtc();

        if (record.isDeleted && !(localData['isDeleted'] == true)) {
          await box.put(record.id, {
            ...localData,
            'isDeleted': true,
            'updatedAt': record.updatedAt.toUtc().toIso8601String(),
          });
          applied++;
        } else if (record.updatedAt.isAfter(localUpdatedAt)) {
          final data = Map<String, dynamic>.from(record.data);
          data.remove('_conflicts');
          await box.put(record.id, data);
          applied++;
        }
      } catch (_) {}
    }
    return applied;
  }

  /// Checksum del payload (per log/deduplica opzionale).
  static String payloadChecksum(Map<String, dynamic> payload) {
    return sha256HexSync(jsonEncode(payload)).substring(0, 12);
  }
}
