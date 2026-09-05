import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:CatechHub/core/auth/auth_service.dart';
import 'package:CatechHub/core/storage/local_database.dart';
import 'package:CatechHub/features/sync/p2p/p2p_sync_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_sync_identity_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalDatabase.authBox);
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(LocalDatabase.authBox);
    tempDir.deleteSync(recursive: true);
  });

  group('AuthService.getCatechistId', () {
    test('genera un nuovo catechistId se non esiste', () {
      final id = AuthService.getCatechistId();
      expect(id, isNotEmpty);
      expect(id, startsWith('cat_'));
    });

    test('restituisce lo stesso id stabile tra chiamate successive', () {
      final id1 = AuthService.getCatechistId();
      final id2 = AuthService.getCatechistId();
      expect(id1, id2);
    });
  });

  group('AuthService.adoptCatechistId', () {
    test('un dispositivo fresco adotta il catechistId del primario', () {
      final primary = 'cat_primario';
      final adopted = AuthService.adoptCatechistId(primary);

      expect(adopted, primary);
      expect(AuthService.getCatechistId(), primary);
    });

    test(
      'adotta e sovrascrive l\'identità corrente (guardia a livello di servizio)',
      () {
        // La protezione contro la sovrascrittura di un dispositivo con classi
        // proprie è applicata in P2PSyncService._maybeAdoptRemoteCatechistId
        // tramite _hasCatechistIdentity. Qui verifichiamo il contratto base:
        // l'adozione persiste e l'identità successiva coincide con quella adottata.
        final existing = AuthService.getCatechistId();
        expect(existing, isNotEmpty);

        final adopted = AuthService.adoptCatechistId('cat_altro');
        expect(adopted, 'cat_altro');
        expect(AuthService.getCatechistId(), 'cat_altro');
      },
    );

    test('non adotta id vuoti e mantiene l\'identità corrente', () {
      final existing = AuthService.getCatechistId();
      expect(AuthService.adoptCatechistId(''), existing);
      expect(AuthService.adoptCatechistId('   '), existing);
    });

    test('adottare lo stesso id non cambia nulla', () {
      final existing = AuthService.getCatechistId();
      expect(AuthService.adoptCatechistId(existing), existing);
      expect(AuthService.getCatechistId(), existing);
    });
  });

  group('AuthService.normalizeCatechistName', () {
    test('normalizza lowercase e rimuove spazi', () {
      expect(AuthService.normalizeCatechistName('Mario  Rossi'), 'mariorossi');
      expect(AuthService.normalizeCatechistName('  Anna Verdi '), 'annaverdi');
    });

    test('è case-insensitive: due scritture diverse coincidono', () {
      expect(
        AuthService.normalizeCatechistName('MARIO ROSSI'),
        AuthService.normalizeCatechistName('mario rossi'),
      );
    });

    test('rimuove gli accenti', () {
      expect(AuthService.normalizeCatechistName('Marìo Róssi'), 'mariorossi');
      expect(
        AuthService.normalizeCatechistName('Giuseppè Fernández'),
        'giuseppefernandez',
      );
    });

    test('rimuove caratteri non alfanumerici', () {
      expect(
        AuthService.normalizeCatechistName('O\'Brien-Smith'),
        'obriensmith',
      );
    });
  });

  group('AuthService.getLocalAnagraficaKey / anagraficaKey', () {
    test('ritorna stringa vuota se il profilo non è completo', () {
      expect(AuthService.getLocalAnagraficaKey(), isEmpty);
    });

    test('anagraficaKey combina nome e cognome normalizzati', () {
      expect(AuthService.anagraficaKey(' Mario ', ' Rossi'), 'mariorossi');
    });

    test('anagraficaKey vuota se entrambi i campi sono vuoti', () {
      expect(AuthService.anagraficaKey('', ''), isEmpty);
      expect(AuthService.anagraficaKey(null, null), isEmpty);
      expect(AuthService.anagraficaKey('Mario', ''), 'mario');
    });
  });

  group('AuthService.getCatechistId (derivazione)', () {
    setUp(() async {
      final box = Hive.box(LocalDatabase.authBox);
      box.put('first_name', 'Mario');
      box.put('last_name', 'Rossi');
    });

    test('id derivato e stabile quando è configurata l\'anagrafica', () {
      final id1 = AuthService.getCatechistId();
      final id2 = AuthService.getCatechistId();
      expect(id1, id2);
      expect(id1, startsWith('cat_'));
      expect(id1.length, 4 + 16);
    });

    test('id non derivabile dal solo nome (anti-enumerazione)', () {
      // Il salt per-device rende l'id non enumerabile dal nome.
      final id = AuthService.getCatechistId();
      // Due installazioni diverse (salt diverso) producono id diversi.
      Hive.box(LocalDatabase.authBox).delete('catechist_salt');
      Hive.box(LocalDatabase.authBox).delete('catechist_id');
      final id2 = AuthService.getCatechistId();
      expect(id, isNot(id2));
    });
  });

  group('computeDefaultCatechistId', () {
    test('preferisce il creatore della classe condivisa (identità remota)', () {
      const local = 'cat_locale';
      const remote = 'cat_remoto';
      final creators = {
        'c1': 'cat_remoto', // classe creata e inviata dal remoto
        'c2': 'cat_altro',
      };
      expect(computeDefaultCatechistId(local, remote, creators), remote);
    });

    test('preferisce il creatore locale se presente', () {
      const local = 'cat_locale';
      const remote = 'cat_remoto';
      final creators = {'c1': 'cat_locale', 'c2': 'cat_remoto'};
      expect(computeDefaultCatechistId(local, remote, creators), local);
    });

    test('nessun creatore riconosciuto: ricade sull\'identità locale', () {
      const local = 'cat_locale';
      const remote = 'cat_remoto';
      expect(computeDefaultCatechistId(local, remote, {}), local);
    });

    test('nessuna classe condivisa: ricade sull\'identità locale', () {
      const local = 'cat_locale';
      const remote = 'cat_remoto';
      expect(computeDefaultCatechistId(local, remote, {}), local);
    });
  });
}
