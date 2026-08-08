// ============================================================================
// TEST: FieldEncryptionService — cifratura/decifratura di campo + fallback
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/core/services/field_encryption_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Chiave deterministica per i test: evita l'accesso al box auth Hive.
    FieldEncryptionService.debugSecretOverride = 'test-device-secret';
  });

  tearDown(() {
    FieldEncryptionService.debugSecretOverride = null;
  });

  group('FieldEncryptionService', () {
    test('cifra e decifra in modo reversibile', () {
      const piano = 'Allergia alle arachidi, iniezione EpiPen';
      final cifrato = FieldEncryptionService.encrypt(piano);
      expect(cifrato, isNotNull);
      expect(cifrato, startsWith('cieI1:'));
      expect(cifrato, isNot(contains(piano)));
      expect(FieldEncryptionService.decrypt(cifrato), piano);
    });

    test('input nulli o vuoti restituiscono null', () {
      expect(FieldEncryptionService.encrypt(null), isNull);
      expect(FieldEncryptionService.encrypt('   '), isNull);
      expect(FieldEncryptionService.decrypt(null), isNull);
    });

    test('decrypt lascia invariato un valore non cifrato (fallback)', () {
      expect(FieldEncryptionService.decrypt('testo in chiaro'),
          'testo in chiaro');
    });

    test('encrypt è idempotente su un valore già cifrato', () {
      final cifrato = FieldEncryptionService.encrypt('nota sensibile');
      expect(FieldEncryptionService.encrypt(cifrato), cifrato);
    });

    test('decrypt non fallisce su dati corrotti (graceful fallback)', () {
      // Valore con prefisso ma base64 corrotto: deve tornare il valore grezzo.
      final corrupted = 'cieI1:%%%non-base64%%%';
      expect(FieldEncryptionService.decrypt(corrupted), corrupted);
    });

    test('chiavi diverse producono un ciphertext non decifrabile', () {
      final plain = 'Nota riservata';
      final encA = FieldEncryptionService.encrypt(plain);
      FieldEncryptionService.debugSecretOverride = 'altro-dispositivo';
      final decB = FieldEncryptionService.decrypt(encA);
      // Il dispositivo B, con chiave diversa, non può decifrare: fallback grezzo.
      expect(decB, isNot(plain));
    });
  });
}