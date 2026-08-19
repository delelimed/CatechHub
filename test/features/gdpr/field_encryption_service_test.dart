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
    test('cifra e decifra in modo reversibile', () async {
      const piano = 'Allergia alle arachidi, iniezione EpiPen';
      final cifrato = await FieldEncryptionService.encrypt(piano);
      expect(cifrato, isNotNull);
      expect(cifrato, startsWith('cieI1:'));
      expect(cifrato, isNot(contains(piano)));
      expect(await FieldEncryptionService.decrypt(cifrato), piano);
    });

    test('input nulli o vuoti restituiscono null', () async {
      expect(await FieldEncryptionService.encrypt(null), isNull);
      expect(await FieldEncryptionService.encrypt('   '), isNull);
      expect(await FieldEncryptionService.decrypt(null), isNull);
    });

    test('decrypt lascia invariato un valore non cifrato (fallback)', () async {
      expect(
        await FieldEncryptionService.decrypt('testo in chiaro'),
        'testo in chiaro',
      );
    });

    test('encrypt è idempotente su un valore già cifrato', () async {
      final cifrato = await FieldEncryptionService.encrypt('nota sensibile');
      expect(await FieldEncryptionService.encrypt(cifrato), cifrato);
    });

    test('decrypt non fallisce su dati corrotti (graceful fallback)', () async {
      // Valore con prefisso ma base64 corrotto: deve tornare il valore grezzo.
      final corrupted = 'cieI1:%%%non-base64%%%';
      expect(await FieldEncryptionService.decrypt(corrupted), corrupted);
    });

    test('chiavi diverse producono un ciphertext non decifrabile', () async {
      final plain = 'Nota riservata';
      final encA = await FieldEncryptionService.encrypt(plain);
      FieldEncryptionService.debugSecretOverride = 'altro-dispositivo';
      final decB = await FieldEncryptionService.decrypt(encA);
      // Il dispositivo B, con chiave diversa, non può decifrare: fallback grezzo.
      expect(decB, isNot(plain));
    });
  });
}
