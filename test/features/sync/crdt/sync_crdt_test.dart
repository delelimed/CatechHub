import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:CatechHub/features/sync/crdt/sync_crdt.dart';

void main() {
  group('VectorClock', () {
    test('increment aggiunge e incrementa', () {
      final a = const VectorClock().increment('node1').increment('node1');
      expect(a.counters['node1'], 2);
    });

    test('merge prende il massimo per nodo', () {
      final a = const VectorClock().increment('a').increment('a');
      final b = const VectorClock().increment('a').increment('b');
      final merged = VectorClock.merge(a, b);
      expect(merged.counters['a'], 2);
      expect(merged.counters['b'], 1);
    });
  });

  group('AttendanceCrdt', () {
    Map<String, dynamic> record(
      String updatedAt, {
      required Map<String, dynamic> presence,
      Map<String, dynamic>? meta,
    }) {
      return {
        'updatedAt': updatedAt,
        'lastModifiedBy': 'Catechista',
        'presence': presence,
        'presenceMeta': ?meta,
      };
    }

    test('studenti presenti solo su un lato vengono mantenuti', () {
      final local = record(
        '2026-01-01T10:00:00.000Z',
        presence: {'s1': 'Presente'},
      );
      final remote = record(
        '2026-01-01T10:00:00.000Z',
        presence: {'s2': 'Assente'},
      );

      final merged = AttendanceCrdt.mergePresence(
        localData: local,
        remoteData: remote,
      );

      expect(merged['presence'], {'s1': 'Presente', 's2': 'Assente'});
    });

    test('su uno studente concorrente vince il timestamp più recente', () {
      final local = record(
        '2026-01-01T10:00:00.000Z',
        presence: {'s1': 'Presente'},
        meta: {
          's1': {'t': 1000, 'by': 'A'},
        },
      );
      final remote = record(
        '2026-01-01T10:00:00.000Z',
        presence: {'s1': 'Assente'},
        meta: {
          's1': {'t': 2000, 'by': 'B'},
        },
      );

      final merged = AttendanceCrdt.mergePresence(
        localData: local,
        remoteData: remote,
      );

      expect(merged['presence']['s1'], 'Assente');
      expect(merged['presenceMeta']['s1']['t'], 2000);
    });

    test('con timestamp identici vince l\'autore in modo deterministico', () {
      final local = record(
        '2026-01-01T10:00:00.000Z',
        presence: {'s1': 'Presente'},
        meta: {
          's1': {'t': 1000, 'by': 'A'},
        },
      );
      final remote = record(
        '2026-01-01T10:00:00.000Z',
        presence: {'s1': 'Assente'},
        meta: {
          's1': {'t': 1000, 'by': 'B'},
        },
      );

      final merged = AttendanceCrdt.mergePresence(
        localData: local,
        remoteData: remote,
      );

      // B > A → vince B
      expect(merged['presence']['s1'], 'Assente');
    });

    test('record legacy senza meta usa il fallback del timestamp record', () {
      final local = record(
        '2026-01-02T10:00:00.000Z',
        presence: {'s1': 'Presente'},
      );
      final remote = record(
        '2026-01-01T10:00:00.000Z',
        presence: {'s1': 'Assente'},
      );

      final merged = AttendanceCrdt.mergePresence(
        localData: local,
        remoteData: remote,
      );

      // Il locale è più recente (senza meta) → presente vince
      expect(merged['presence']['s1'], 'Presente');
    });
  });

  group('SignedLww', () {
    const secret = 'shared-secret';
    const box = 'students';
    const id = 's1';
    final iso = DateTime.utc(2026, 7, 1, 12).toIso8601String();
    final sig = SignedLww.sign(
      boxName: box,
      recordId: id,
      updatedAtIso: iso,
      secretKey: secret,
    );

    test('la firma è verificabile', () {
      expect(
        SignedLww.verify(
          boxName: box,
          recordId: id,
          updatedAtIso: iso,
          signature: sig,
          secretKey: secret,
        ),
        true,
      );
    });

    test('la firma non si verifica con chiave diversa', () {
      expect(
        SignedLww.verify(
          boxName: box,
          recordId: id,
          updatedAtIso: iso,
          signature: sig,
          secretKey: 'wrong-secret',
        ),
        false,
      );
    });

    test('un timestamp contraffatto (nuovo ma non firmato) non vince', () {
      final localIso = DateTime.utc(2026, 7, 1, 10).toIso8601String();
      final forgedIso = DateTime.utc(2026, 7, 2, 10).toIso8601String();

      final remoteWins = SignedLww.remoteWins(
        boxName: box,
        recordId: id,
        localUpdatedAtIso: localIso,
        localSignature: SignedLww.sign(
          boxName: box,
          recordId: id,
          updatedAtIso: localIso,
          secretKey: secret,
        ),
        remoteUpdatedAtIso: forgedIso,
        remoteSignature: null,
        secretKey: secret,
      );

      // Il remoto dichiara di essere più recente ma NON ha firma valida →
      // rifiutiamo il timestamp inventato.
      expect(remoteWins, false);
    });

    test('un timestamp firmato più recente vince', () {
      final localIso = DateTime.utc(2026, 7, 1, 10).toIso8601String();
      final newerIso = DateTime.utc(2026, 7, 2, 10).toIso8601String();

      final remoteWins = SignedLww.remoteWins(
        boxName: box,
        recordId: id,
        localUpdatedAtIso: localIso,
        localSignature: SignedLww.sign(
          boxName: box,
          recordId: id,
          updatedAtIso: localIso,
          secretKey: secret,
        ),
        remoteUpdatedAtIso: newerIso,
        remoteSignature: SignedLww.sign(
          boxName: box,
          recordId: id,
          updatedAtIso: newerIso,
          secretKey: secret,
        ),
        secretKey: secret,
      );

      expect(remoteWins, true);
    });

    test('codificato come JSON il payload è stabile', () {
      final decoded =
          jsonDecode(jsonEncode({'sig': sig})) as Map<String, dynamic>;
      expect(decoded['sig'], sig);
    });
  });
}
