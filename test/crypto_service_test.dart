//import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:CatechHub/core/services/encryption_service.dart';

/// Test del servizio di crittografia.
///
/// Verifica la cifratura/decifratura AES-256-GCM con diverse chiavi,
/// simulando lo scenario multi-dispositivo dove ciascun catechista
/// ha la propria chiave di pairing nella tabella TrustedDevices.
void main() {
  group('EncryptionService - Cifratura/Decifratura', () {
    test('dovrebbe cifrare e decifrare con la stessa chiave', () {
      final testData = {'nome': 'Mario', 'ruolo': 'catechista'};
      final password = 'chiave_segreta_123';

      final encrypted = EncryptionService.encryptData(testData, password);
      final decrypted = EncryptionService.decryptData(encrypted, password);

      expect(decrypted['nome'], equals('Mario'));
      expect(decrypted['ruolo'], equals('catechista'));
    });

    test('dovrebbe fallire la decifratura con chiave errata', () {
      final testData = {'nome': 'Mario'};
      final passwordCorretta = 'chiave_corretta';
      final passwordErrata = 'chiave_errata';

      final encrypted = EncryptionService.encryptData(testData, passwordCorretta);

      expect(
        () => EncryptionService.decryptData(encrypted, passwordErrata),
        throwsA(isA<Exception>()),
      );
    });

    test('dovrebbe produrre output diverso per lo stesso input (nonce casuale)', () {
      final testData = {'nome': 'Mario'};
      final password = 'chiave_fissa';

      final encrypted1 = EncryptionService.encryptData(testData, password);
      final encrypted2 = EncryptionService.encryptData(testData, password);

      // I pacchetti crittografati dovrebbero essere diversi (nonce diverso)
      expect(encrypted1, isNot(equals(encrypted2)));

      // Ma entrambi dovrebbero decifrarsi correttamente
      final dec1 = EncryptionService.decryptData(encrypted1, password);
      final dec2 = EncryptionService.decryptData(encrypted2, password);
      expect(dec1['nome'], equals('Mario'));
      expect(dec2['nome'], equals('Mario'));
    });

    test('dovrebbe verificare la password corretta', () {
      final testData = {'test': true};
      final password = 'password123';

      final encrypted = EncryptionService.encryptData(testData, password);

      expect(EncryptionService.verifyPassword(encrypted, password), isTrue);
      expect(EncryptionService.verifyPassword(encrypted, 'sbagliata'), isFalse);
    });
  });

  group('EncryptionService - Sincronizzazione Multi-Dispositivo', () {
    test('dovrebbe gestire chiavi diverse per dispositivi diversi', () {
      // Simula due catechisti con chiavi diverse nella tabella TrustedDevices
      final chiaveCatechistaA = 'chiave_pubblica_A_32byte_padding!!';
      final chiaveCatechistaB = 'chiave_pubblica_B_32byte_padding!!';

      // Il Catechista A invia dati cifrati con la sua chiave
      final datiInviatiDaA = {
        'records': [
          {'id': 'studente_1', 'nome': 'Luca'},
        ],
        'sentAt': DateTime.now().toUtc().toIso8601String(),
      };

      final payloadA = EncryptionService.encryptData(
        datiInviatiDaA,
        chiaveCatechistaA,
        iterations: EncryptionService.fastShareIterations,
      );

      // Il Catechista B riceve e decifra con la chiave di A
      final datiRicevutiDaB = EncryptionService.decryptData(
        payloadA,
        chiaveCatechistaA,
      );

      expect(datiRicevutiDaB['records'], isA<List>());
      expect((datiRicevutiDaB['records'] as List).length, equals(1));

      // Verifica che la chiave di B non possa decifrare i dati di A
      expect(
        () => EncryptionService.decryptData(payloadA, chiaveCatechistaB),
        throwsA(isA<Exception>()),
      );
    });

    test('dovrebbe gestire sincronizzazione sequenziale con due dispositivi', () {
      // Simula lo scenario: il nostro dispositivo sincronizza prima con A poi con B
      final chiaveA = 'chiave_dispositivo_A_padding!!!!!!!';
      final chiaveB = 'chiave_dispositivo_B_padding!!!!!!!';

      // Record locali da inviare a A
      final recordPerA = {
        'records': [
          {'id': 'classe_1', 'nome': 'Classe Prima'},
        ],
        'sentAt': DateTime.now().toUtc().toIso8601String(),
        'recordCount': 1,
      };

      // Record locali da inviare a B (stessi dati, chiave diversa)
      final recordPerB = {
        'records': [
          {'id': 'classe_1', 'nome': 'Classe Prima'},
        ],
        'sentAt': DateTime.now().toUtc().toIso8601String(),
        'recordCount': 1,
      };

      // Cifra con la chiave di A
      final payloadPerA = EncryptionService.encryptData(
        recordPerA,
        chiaveA,
        iterations: EncryptionService.fastShareIterations,
      );

      // Cifra con la chiave di B
      final payloadPerB = EncryptionService.encryptData(
        recordPerB,
        chiaveB,
        iterations: EncryptionService.fastShareIterations,
      );

      // Verifica che i payload siano diversi (chiavi diverse)
      expect(payloadPerA, isNot(equals(payloadPerB)));

      // Verifica decifratura con la chiave corretta
      final decifratoA = EncryptionService.decryptData(payloadPerA, chiaveA);
      final decifratoB = EncryptionService.decryptData(payloadPerB, chiaveB);

      expect(decifratoA['records'], isA<List>());
      expect(decifratoB['records'], isA<List>());

      // Verifica che A non possa decifrare i dati di B e viceversa
      expect(
        () => EncryptionService.decryptData(payloadPerA, chiaveB),
        throwsA(isA<Exception>()),
      );
      expect(
        () => EncryptionService.decryptData(payloadPerB, chiaveA),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('EncryptionService - Derivazione Chiave', () {
    test('PBKDF2 dovrebbe generare chiavi deterministiche', () {
      final password = 'test_password';
      final salt = EncryptionService.secureRandomBytes(16);

      final key1 = EncryptionService.derivePasswordKeyBytes(password, salt);
      final key2 = EncryptionService.derivePasswordKeyBytes(password, salt);

      expect(key1, equals(key2));
    });

    test('PBKDF2 dovrebbe generari chiavi diverse con salt diversi', () {
      final password = 'test_password';
      final salt1 = EncryptionService.secureRandomBytes(16);
      final salt2 = EncryptionService.secureRandomBytes(16);

      final key1 = EncryptionService.derivePasswordKeyBytes(password, salt1);
      final key2 = EncryptionService.derivePasswordKeyBytes(password, salt2);

      expect(key1, isNot(equals(key2)));
    });

    test('la chiave derivata dovrebbe essere di 32 byte (AES-256)', () {
      final password = 'test_password';
      final salt = EncryptionService.secureRandomBytes(16);

      final key = EncryptionService.derivePasswordKeyBytes(password, salt);

      expect(key.length, equals(32));
    });
  });
}
