// ============================================================================
// TEST: Inizializzazione Profilo e Onboarding
// Copre: validazione campi obbligatori, PIN minimo, profileData
// ============================================================================
import 'package:flutter_test/flutter_test.dart';

/// ── Eccezione personalizzata per errori di validazione del form ──
class FormException implements Exception {
  final String message;
  const FormException(this.message);

  @override
  String toString() => 'FormException: $message';
}

/// ── Modello semplificato per il profilo del catechista ──
class CatechistProfile {
  final String firstName;
  final String lastName;
  final String groupName;
  final String pin;

  const CatechistProfile({
    required this.firstName,
    required this.lastName,
    required this.groupName,
    required this.pin,
  });
}

/// ── Servizio di validazione del profilo ──
/// Implementa la stessa logica di AuthService.setupInitialPin
class ProfileValidator {
  /// Valida il PIN: deve avere almeno 4 cifre.
  static void validatePin(String pin) {
    if (pin.length < 4) {
      throw const FormException('Il PIN deve essere di almeno 4 cifre');
    }
  }

  /// Valida i campi obbligatori del profilo.
  /// Nome, cognome e gruppo non possono essere vuoti o solo spazi.
  static void validateProfile(CatechistProfile profile) {
    if (profile.firstName.trim().isEmpty) {
      throw const FormException('Il nome e obbligatorio');
    }
    if (profile.lastName.trim().isEmpty) {
      throw const FormException('Il cognome e obbligatorio');
    }
    if (profile.groupName.trim().isEmpty) {
      throw const FormException('Il nome del gruppo e obbligatorio');
    }
  }

  /// Validazione completa: profilo + PIN.
  static void validateAll(CatechistProfile profile) {
    validateProfile(profile);
    validatePin(profile.pin);
  }

  /// Verifica se il profilo e completo (tutti i campi obbligatori compilati).
  static bool isProfileComplete(CatechistProfile profile) {
    return profile.firstName.trim().isNotEmpty &&
        profile.lastName.trim().isNotEmpty &&
        profile.groupName.trim().isNotEmpty;
  }
}

/// ── Modello semplificato per lo studente con validazione form ──
class StudentForm {
  String name;
  String surname;
  String motherPhone;
  String fatherPhone;

  StudentForm({
    this.name = '',
    this.surname = '',
    this.motherPhone = '',
    this.fatherPhone = '',
  });
}

/// ── Validatore del form di inserimento ragazzo/genitore ──
class StudentFormValidator {
  /// Valida il nome dello studente: non puo essere vuoto.
  static void validateName(String name) {
    if (name.trim().isEmpty) {
      throw const FormException('Il nome dello studente e obbligatorio');
    }
  }

  /// Valida il cognome dello studente: non puo essere vuoto.
  static void validateSurname(String surname) {
    if (surname.trim().isEmpty) {
      throw const FormException('Il cognome dello studente e obbligatorio');
    }
  }

  /// Valida il numero di telefono della madre.
  /// Accetta solo cifre, spazi, prefissi internazionali e il + iniziale.
  static void validateMotherPhone(String phone) {
    if (phone.trim().isEmpty) {
      throw const FormException('Il numero di telefono della madre e obbligatorio');
    }
    if (!_isValidPhoneFormat(phone)) {
      throw const FormException(
        'Il numero di telefono della madre non e in un formato valido. '
        'Usa solo cifre, eventualmente con prefisso internazionale.',
      );
    }
  }

  /// Valida il numero di telefono del padre.
  static void validateFatherPhone(String phone) {
    if (phone.trim().isEmpty) {
      throw const FormException('Il numero di telefono del padre e obbligatorio');
    }
    if (!_isValidPhoneFormat(phone)) {
      throw const FormException(
        'Il numero di telefono del padre non e in un formato valido.',
      );
    }
  }

  /// Validazione completa del form di inserimento ragazzo.
  static void validateAll(StudentForm form) {
    validateName(form.name);
    validateSurname(form.surname);
    validateMotherPhone(form.motherPhone);
    validateFatherPhone(form.fatherPhone);
  }

  /// Verifica il formato del telefono.
  /// Accetta: cifre, spazi, trattini, e il prefisso + iniziale.
  /// Lunghezza minima: 8 caratteri (es. "3331234567").
  static bool _isValidPhoneFormat(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\+]'), '');
    if (cleaned.length < 8) return false;
    if (!RegExp(r'^\d+$').hasMatch(cleaned)) return false;
    return true;
  }
}

void main() {
  // ══════════════════════════════════════════════════
  //  Validazione Profilo Catechista (Onboarding)
  // ══════════════════════════════════════════════════
  group('Profilo Catechista - Onboarding', () {
    test('validazione completa con dati validi non solleva eccezioni', () {
      // Arrange: profilo con tutti i campi compilati
      final profile = CatechistProfile(
        firstName: 'Mario',
        lastName: 'Rossi',
        groupName: 'Prima Elementare',
        pin: '1234',
      );
      // Act/Assert: la validazione non deve sollevare eccezioni
      expect(() => ProfileValidator.validateAll(profile), returnsNormally);
    });

    test('solleva FormException se il nome e vuoto', () {
      // Arrange: profilo con nome vuoto
      final profile = CatechistProfile(
        firstName: '',
        lastName: 'Rossi',
        groupName: 'Gruppo',
        pin: '1234',
      );
      // Act/Assert: deve sollevare FormException
      expect(
        () => ProfileValidator.validateProfile(profile),
        throwsA(isA<FormException>().having(
          (e) => e.message,
          'messaggio',
          contains('nome'),
        )),
      );
    });

    test('solleva FormException se il cognome e vuoto', () {
      // Arrange: profilo con cognome vuoto
      final profile = CatechistProfile(
        firstName: 'Mario',
        lastName: '',
        groupName: 'Gruppo',
        pin: '1234',
      );
      // Act/Assert: deve sollevare FormException per il cognome
      expect(
        () => ProfileValidator.validateProfile(profile),
        throwsA(isA<FormException>().having(
          (e) => e.message,
          'messaggio',
          contains('cognome'),
        )),
      );
    });

    test('solleva FormException se il gruppo e vuoto', () {
      // Arrange: profilo con gruppo vuoto
      final profile = CatechistProfile(
        firstName: 'Mario',
        lastName: 'Rossi',
        groupName: '',
        pin: '1234',
      );
      // Act/Assert: deve sollevare FormException per il gruppo
      expect(
        () => ProfileValidator.validateProfile(profile),
        throwsA(isA<FormException>().having(
          (e) => e.message,
          'messaggio',
          contains('gruppo'),
        )),
      );
    });

    test('solleva FormException se il PIN e troppo corto', () {
      // Arrange: PIN con sole 3 cifre
      final profile = CatechistProfile(
        firstName: 'Mario',
        lastName: 'Rossi',
        groupName: 'Gruppo',
        pin: '123',
      );
      // Act/Assert: deve sollevare FormException per il PIN
      expect(
        () => ProfileValidator.validatePin(profile.pin),
        throwsA(isA<FormException>().having(
          (e) => e.message,
          'messaggio',
          contains('4 cifre'),
        )),
      );
    });

    test('accetta un PIN di 4 cifre', () {
      // Act/Assert: PIN di 4 cifre deve essere valido
      expect(() => ProfileValidator.validatePin('1234'), returnsNormally);
    });

    test('accetta un PIN lungo (6+ cifre)', () {
      // Act/Assert: PIN lungo deve essere valido
      expect(() => ProfileValidator.validatePin('123456'), returnsNormally);
    });

    test('isProfileComplete restituisce true con tutti i campi', () {
      // Arrange: profilo completo
      final profile = CatechistProfile(
        firstName: 'Mario',
        lastName: 'Rossi',
        groupName: 'Gruppo',
        pin: '1234',
      );
      // Act/Assert: deve essere completo
      expect(ProfileValidator.isProfileComplete(profile), isTrue);
    });

    test('isProfileComplete restituisce false con campo mancante', () {
      // Arrange: profilo con nome vuoto
      final profile = CatechistProfile(
        firstName: '',
        lastName: 'Rossi',
        groupName: 'Gruppo',
        pin: '1234',
      );
      // Act/Assert: NON deve essere completo
      expect(ProfileValidator.isProfileComplete(profile), isFalse);
    });
  });

  // ══════════════════════════════════════════════════
  //  Validazione Form Inserimento Ragazzi
  // ══════════════════════════════════════════════════
  group('Form Inserimento Ragazzi - Validazione', () {
    test('validazione completa con dati validi non solleva eccezioni', () {
      // Arrange: form con tutti i campi validi
      final form = StudentForm(
        name: 'Mario',
        surname: 'Rossi',
        motherPhone: '3331234567',
        fatherPhone: '3339876543',
      );
      // Act/Assert: la validazione deve passare
      expect(() => StudentFormValidator.validateAll(form), returnsNormally);
    });

    test('solleva FormException se il nome e vuoto', () {
      // Arrange: form con nome vuoto
      final form = StudentForm(
        name: '',
        surname: 'Rossi',
        motherPhone: '3331234567',
        fatherPhone: '3339876543',
      );
      // Act/Assert: deve sollevare eccezione
      expect(
        () => StudentFormValidator.validateName(form.name),
        throwsA(isA<FormException>()),
      );
    });

    test('solleva FormException se il cognome e vuoto', () {
      // Arrange: form con cognome vuoto
      final form = StudentForm(
        name: 'Mario',
        surname: '',
        motherPhone: '3331234567',
        fatherPhone: '3339876543',
      );
      // Act/Assert: deve sollevare eccezione
      expect(
        () => StudentFormValidator.validateSurname(form.surname),
        throwsA(isA<FormException>()),
      );
    });

    test('solleva FormException se il telefono della madre e vuoto', () {
      // Arrange: telefono madre vuoto
      final form = StudentForm(
        name: 'Mario',
        surname: 'Rossi',
        motherPhone: '',
        fatherPhone: '3339876543',
      );
      // Act/Assert: deve sollevare eccezione
      expect(
        () => StudentFormValidator.validateMotherPhone(form.motherPhone),
        throwsA(isA<FormException>()),
      );
    });

    test('solleva FormException per telefono madre malformato (lettere)', () {
      // Arrange: telefono con lettere
      final form = StudentForm(
        name: 'Mario',
        surname: 'Rossi',
        motherPhone: 'abc1234567',
        fatherPhone: '3339876543',
      );
      // Act/Assert: deve sollevare eccezione per formato non valido
      expect(
        () => StudentFormValidator.validateMotherPhone(form.motherPhone),
        throwsA(isA<FormException>().having(
          (e) => e.message,
          'messaggio',
          contains('formato'),
        )),
      );
    });

    test('solleva FormException per telefono padre troppo corto', () {
      // Arrange: telefono con meno di 8 cifre
      final form = StudentForm(
        name: 'Mario',
        surname: 'Rossi',
        motherPhone: '3331234567',
        fatherPhone: '1234567', // solo 7 cifre
      );
      // Act/Assert: deve sollevare eccezione
      expect(
        () => StudentFormValidator.validateFatherPhone(form.fatherPhone),
        throwsA(isA<FormException>()),
      );
    });

    test('accetta telefono con prefisso internazionale +39', () {
      // Arrange: telefono con prefisso internazionale
      final phone = '+39 333 123 4567';
      // Act/Assert: deve essere valido
      expect(
        () => StudentFormValidator.validateMotherPhone(phone),
        returnsNormally,
      );
    });

    test('accetta telefono con trattini e spazi', () {
      // Arrange: telefono formattato
      final phone = '333-123-4567';
      // Act/Assert: deve essere valido
      expect(
        () => StudentFormValidator.validateFatherPhone(phone),
        returnsNormally,
      );
    });
  });
}
