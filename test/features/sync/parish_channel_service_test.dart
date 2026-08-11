// ============================================================================
// TEST: ParishChannelService — canale parrocchiale globale (riunioni/avvisi)
// ============================================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/sync/parish_channel_service.dart';
import 'package:CatechHub/features/sync/p2p/hive_sync_engine.dart';
import 'package:CatechHub/shared/models/avviso_template_model.dart';
import 'package:CatechHub/shared/models/parish_event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_parish_channel_');
    Hive.init(tempDir.path);
    await Hive.openBox<Map>(LocalDatabase.parishEventsBox);
    await Hive.openBox<Map>(LocalDatabase.avvisiBox);
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(LocalDatabase.parishEventsBox);
    await Hive.deleteBoxFromDisk(LocalDatabase.avvisiBox);
    tempDir.deleteSync(recursive: true);
  });

  group('ParishChannelService — CRUD riunioni', () {
    test('saveEvent e getAllEvents persistono una riunione', () async {
      expect(ParishChannelService.getAllEvents(), isEmpty);

      await ParishChannelService.saveEvent(
        ParishEvent(
          id: '',
          title: 'Riunione catechisti',
          date: DateTime(2026, 9, 1),
          time: '15:00',
          location: 'Sala Don Bosco',
          notes: 'ODG: programmazione',
          createdBy: 'cat_1',
        ),
      );

      final events = ParishChannelService.getAllEvents();
      expect(events, hasLength(1));
      expect(events.first.title, 'Riunione catechisti');
      expect(events.first.location, 'Sala Don Bosco');
    });

    test('deleteEvent rimuove una riunione', () async {
      final saved = await ParishChannelService.saveEvent(
        ParishEvent(id: '', title: 'Da eliminare', date: DateTime(2026, 9, 1)),
      );
      await ParishChannelService.deleteEvent(saved.id);
      expect(ParishChannelService.getAllEvents(), isEmpty);
    });
  });

  group('ParishChannelService — avvisi parrocchiali', () {
    test('salva e legge solo gli avvisi GLOBALI (senza classe)', () async {
      await ParishChannelService.saveParishAvviso(
        const AvvisoTemplate(
          id: '',
          classUniqueCode: null,
          title: 'Avviso parrocchia',
          text: 'Riunione di stasera',
        ),
      );
      // Avviso legato a una classe: NON appartiene al canale parrocchiale.
      await LocalDatabase.avvisi().put(
        'avviso_classe_1',
        const AvvisoTemplate(
          id: 'avviso_classe_1',
          classUniqueCode: '000',
          title: 'Avviso classe',
          text: 'X',
        ).toMap(),
      );

      final globali = ParishChannelService.getAllParishAvvisi();
      expect(globali, hasLength(1));
      expect(globali.first.title, 'Avviso parrocchia');
    });
  });

  group('ParishChannelService — sync del canale globale', () {
    test('buildChannelPayload include eventi e avvisi globali, non di classe',
        () async {
      await ParishChannelService.saveEvent(
        ParishEvent(id: 'e1', title: 'E1', date: DateTime(2026, 9, 1)),
      );
      await ParishChannelService.saveParishAvviso(
        const AvvisoTemplate(
          id: 'a1',
          classUniqueCode: null,
          title: 'A1',
          text: 'testo',
        ),
      );
      await LocalDatabase.avvisi().put(
        'a2',
        const AvvisoTemplate(
          id: 'a2',
          classUniqueCode: '999',
          title: 'A2',
          text: 'classe',
        ).toMap(),
      );

      final payload = ParishChannelService.buildChannelPayload();
      final events = payload['events'] as List<dynamic>;
      final avvisi = payload['avvisi'] as List<dynamic>;

      expect(events, hasLength(1));
      expect(avvisi, hasLength(1));
      expect((avvisi.first as Map)['id'], 'a1');
    });

    test('applyChannelPayload applica i record nuovi e ignora gli identici',
        () async {
      // Stato "remoto": un evento e un avviso.
      final remoteEvent = ParishEvent(
        id: 'e_remote',
        title: 'Riunione remota',
        date: DateTime(2026, 9, 10),
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final remoteEventRecord = SyncRecord.fromHiveEntry(
        id: remoteEvent.id,
        boxName: LocalDatabase.parishEventsBox,
        entry: remoteEvent.toMap(),
      );

      final payload = {
        'events': [remoteEventRecord.toJson()],
        'avvisi': <Map<String, dynamic>>[],
      };

      // Primo apply: il record nuovo viene inserito.
      final applied = await ParishChannelService.applyChannelPayload(payload);
      expect(applied, 1);
      expect(ParishChannelService.getAllEvents(), hasLength(1));

      // Secondo apply: record identico → nessuna modifica.
      final again =
          await ParishChannelService.applyChannelPayload(payload);
      expect(again, 0);
      expect(ParishChannelService.getAllEvents(), hasLength(1));
    });

    test('applyChannelPayload LWW: vince il record con updatedAt più recente',
        () async {
      final base = ParishEvent(
        id: 'e_conflict',
        title: 'Titolo vecchio',
        date: DateTime(2026, 9, 10),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      await ParishChannelService.saveEvent(base);

      final newer = base.copyWith(
        title: 'Titolo nuovo',
        updatedAt: DateTime.utc(2026, 2, 1),
      );
      final record = SyncRecord.fromHiveEntry(
        id: newer.id,
        boxName: LocalDatabase.parishEventsBox,
        entry: newer.toMap(),
      );

      final payload = {
        'events': [record.toJson()],
        'avvisi': <Map<String, dynamic>>[],
      };
      final applied = await ParishChannelService.applyChannelPayload(payload);

      expect(applied, 1);
      final stored = ParishChannelService.getAllEvents().first;
      expect(stored.title, 'Titolo nuovo');
    });

    test('applyChannelPayload LWW: un record più vecchio NON sovrascrive',
        () async {
      final current = ParishEvent(
        id: 'e_older',
        title: 'Versione attuale',
        date: DateTime(2026, 9, 10),
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      await ParishChannelService.saveEvent(current);

      final older = current.copyWith(
        title: 'Versione obsoleta',
        updatedAt: DateTime.utc(2026, 3, 1),
      );
      final record = SyncRecord.fromHiveEntry(
        id: older.id,
        boxName: LocalDatabase.parishEventsBox,
        entry: older.toMap(),
      );
      final payload = {
        'events': [record.toJson()],
        'avvisi': <Map<String, dynamic>>[],
      };

      final applied = await ParishChannelService.applyChannelPayload(payload);
      expect(applied, 0);
      expect(ParishChannelService.getAllEvents().first.title,
          'Versione attuale');
    });

    test('applyChannelPayload propaga la cancellazione (isDeleted)', () async {
      final evt = ParishEvent(
        id: 'e_del',
        title: 'Da eliminare',
        date: DateTime(2026, 9, 10),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      await ParishChannelService.saveEvent(evt);

      final tombstone = SyncRecord.fromJson({
        'id': evt.id,
        'box': LocalDatabase.parishEventsBox,
        'data': evt.toMap(),
        'createdAt': evt.createdAt.toUtc().toIso8601String(),
        'updatedAt': '2026-01-05T00:00:00.000Z',
        'isDeleted': true,
      });
      final payload = {
        'events': [tombstone.toJson()],
        'avvisi': <Map<String, dynamic>>[],
      };

      final applied = await ParishChannelService.applyChannelPayload(payload);
      expect(applied, 1);
      final stored = LocalDatabase.parishEvents()
          .get(evt.id) as Map;
      expect(stored['isDeleted'], isTrue);
    });
  });
}
