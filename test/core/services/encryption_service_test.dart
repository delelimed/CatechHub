// ============================================================================
// TEST: EncryptionService
// Copre: cifratura/decifratura, derivate chiave, verifica password, salt casuali
// ============================================================================
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/core/services/encryption_service.dart';

void main() {
  // ══════════════════════════════════════════════════
  //  Cifratura e Decifratura Dati
  // ══════════════════════════════════════════════════
  group('EncryptionService - Cifratura/Decifratura', () {
    test('encryptData e decryptData sono reversibili', () {
      // Arrange: prepara dati da cifrare
      final dati = {
        'nome': 'Mario Rossi',
        'eta': 10,
        'classe': 'Prima A',
      };
      final password = 'chiaveSegreta123';
      // Act: cifra e poi decifra
      final encrypted = EncryptionService.encryptData(dati, password);
      final decrypted = EncryptionService.decryptData(encrypted, password);
      // Assert: i dati decifrati devono corrispondere a quelli originali
      expect(decrypted['nome'], 'Mario Rossi');
      expect(decrypted['eta'], 10);
      expect(decrypted['classe'], 'Prima A');
    });

    test('decryptData con password sbagliata solleva un\'eccezione', () {
      // Arrange: cifra con una password
      final dati = {'chiave': 'valore'};
      final encrypted = EncryptionService.encryptData(dati, 'passwordCorretta');
      // Act/Assert: decifrare con password errata deve lanciare eccezione
      expect(
        () => EncryptionService.decryptData(encrypted, 'passwordSbagliata'),
        throwsA(isA<Exception>()),
      );
    });

    test('encryptData genera output Base64 valido', () {
      // Arrange: dati semplici
      final dati = {'test': 'dati'};
      // Act: cifra
      final encrypted = EncryptionService.encryptData(dati, 'pwd');
      // Assert: l'output deve essere decodificabile da Base64
      expect(() => base64Decode(encrypted), returnsNormally);
    });

    test('encryptData genera output diverso ogni volta (salt/nonce casuali)', () {
      // Arrange: stessi dati e stessa password
      final dati = {'info': 'sensibili'};
      // Act: cifra due volte
      final enc1 = EncryptionService.encryptData(dati, 'pwd');
      final enc2 = EncryptionService.encryptData(dati, 'pwd');
      // Assert: i risultati devono essere diversi (salt e nonce casuali)
      expect(enc1, isNot(equals(enc2)));
    });
  });

  // ══════════════════════════════════════════════════
  //  Derivazione Chiave PBKDF2
  // ══════════════════════════════════════════════════
  group('EncryptionService - Derivazione Chiave', () {
    test('derivePasswordKeyBytes restituisce 32 byte', () {
      // Arrange: password e salt validi
      final password = 'miaPassword';
      final salt = EncryptionService.secureRandomBytes(16);
      // Act: deriva la chiave
      final key = EncryptionService.derivePasswordKeyBytes(password, salt);
      // Assert: la chiave deve essere di 32 byte
      expect(key.length, 32);
    });

    test('la stessa password e salt producono la stessa chiave', () {
      // Arrange: password e salt fissi
      final password = 'testPassword';
      final salt = EncryptionService.secureRandomBytes(16);
      // Act: deriva la chiave due volte
      final key1 = EncryptionService.derivePasswordKeyBytes(password, salt);
      final key2 = EncryptionService.derivePasswordKeyBytes(password, salt);
      // Assert: le chiavi devono essere identiche
      expect(key1, equals(key2));
    });

    test('password diverse producono chiavi diverse', () {
      // Arrange: salt uguale, password diverse
      final salt = EncryptionService.secureRandomBytes(16);
      // Act: deriva chiavi con password diverse
      final key1 = EncryptionService.derivePasswordKeyBytes('pwd1', salt);
      final key2 = EncryptionService.derivePasswordKeyBytes('pwd2', salt);
      // Assert: le chiavi devono essere diverse
      expect(key1, isNot(equals(key2)));
    });
  });

  // ══════════════════════════════════════════════════
  //  Generazione Salt e Byte Casuali
  // ══════════════════════════════════════════════════
  group('EncryptionService - Generazione Casuali', () {
    test('secureRandomBytes restituisce il numero richiesto di byte', () {
      // Act: genera 16 byte casuali
      final bytes = EncryptionService.secureRandomBytes(16);
      // Assert: deve restituire 16 byte
      expect(bytes.length, 16);
    });

    test('secureRandomBytes genera output diverso ogni volta', () {
      // Act: genera due volte
      final bytes1 = EncryptionService.secureRandomBytes(32);
      final bytes2 = EncryptionService.secureRandomBytes(32);
      // Assert: i byte devono essere diversi
      expect(bytes1, isNot(equals(bytes2)));
    });

    test('generateSalt restituisce una stringa Base64 valida', () {
      // Act: genera un salt
      final salt = EncryptionService.generateSalt();
      // Assert: deve essere decodificabile da Base64
      expect(() => base64Decode(salt), returnsNormally);
    });
  });

  // ══════════════════════════════════════════════════
  //  Verifica Password
  // ══════════════════════════════════════════════════
  group('EncryptionService - verifyPassword', () {
    test('restuisce true con password corretta', () {
      // Arrange: cifra dei dati
      final dati = {'secret': 'data'};
      final encrypted = EncryptionService.encryptData(dati, 'correctPassword');
      // Act: verifica con password corretta
      final result = EncryptionService.verifyPassword(encrypted, 'correctPassword');
      // Assert: deve restituire true
      expect(result, isTrue);
    });

    test('restuisce false con password sbagliata', () {
      // Arrange: cifra dei dati
      final dati = {'secret': 'data'};
      final encrypted = EncryptionService.encryptData(dati, 'correctPassword');
      // Act: verifica con password errata
      final result = EncryptionService.verifyPassword(encrypted, 'wrongPassword');
      // Assert: deve restituire false
      expect(result, isFalse);
    });
  });
}
