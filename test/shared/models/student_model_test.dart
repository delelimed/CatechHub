// ============================================================================
// TEST: Student Model
// Copre: serializzazione, deserializzazione, ordinamento alfabetico, copyWith
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/shared/models/student_model.dart';

void main() {
  // ── Costruttore e campi obbligatori ──
  group('Costruttore Student', () {
    test('crea un istanza con tutti i campi obbligatori', () {
      // Arrange: prepara i dati di un ragazzo valido
      final now = DateTime(2024, 1, 15);
      // Act: crea l'istanza di Student
      final student = Student(
        id: 's1',
        name: 'Mario',
        surname: 'Rossi',
        birthDate: now,
        motherName: 'Lucia',
        motherSurname: 'Bianchi',
        fatherName: 'Giuseppe',
        fatherSurname: 'Rossi',
        motherPhone: '3331234567',
        fatherPhone: '3339876543',
        studentPhone: '',
      );
      // Assert: verifica che tutti i campi siano correttamente assegnati
      expect(student.id, 's1');
      expect(student.name, 'Mario');
      expect(student.surname, 'Rossi');
      expect(student.birthDate, now);
      expect(student.motherName, 'Lucia');
      expect(student.motherSurname, 'Bianchi');
      expect(student.fatherName, 'Giuseppe');
      expect(student.fatherSurname, 'Rossi');
      expect(student.motherPhone, '3331234567');
      expect(student.fatherPhone, '3339876543');
      expect(student.studentPhone, '');
      // Verifica che i campi opzionali siano null di default
      expect(student.classId, isNull);
      expect(student.allergies, isNull);
      expect(student.autonomousExits, isNull);
      expect(student.notes, isNull);
    });
  });

  // ── Serializzazione toMap / fromMap ──
  group('Serializzazione Student', () {
    test('toMap genera una mappa con tutti i campi', () {
      // Arrange: crea uno studente con tutti i campi compilati
      final student = Student(
        id: 's2',
        name: 'Giulia',
        surname: 'Verdi',
        birthDate: DateTime(2015, 6, 20),
        motherName: 'Anna',
        motherSurname: 'Neri',
        fatherName: 'Paolo',
        fatherSurname: 'Verdi',
        motherPhone: '3401112222',
        fatherPhone: '3403334444',
        studentPhone: '3405556666',
        classId: 'c1',
        allergies: 'Latte',
        autonomousExits: 'Si',
        notes: 'Nessuna nota',
      );
      // Act: serializza in mappa
      final map = student.toMap();
      // Assert: verifica che ogni campo sia presente e corretto
      expect(map['name'], 'Giulia');
      expect(map['surname'], 'Verdi');
      expect(map['birthDate'], DateTime(2015, 6, 20).toIso8601String());
      expect(map['classId'], 'c1');
      expect(map['motherName'], 'Anna');
      expect(map['motherSurname'], 'Neri');
      expect(map['fatherName'], 'Paolo');
      expect(map['fatherSurname'], 'Verdi');
      expect(map['motherPhone'], '3401112222');
      expect(map['fatherPhone'], '3403334444');
      expect(map['studentPhone'], '3405556666');
      expect(map['allergies'], 'Latte');
      expect(map['autonomousExits'], 'Si');
      expect(map['notes'], 'Nessuna nota');
    });

    test('fromMap ricostruisce correttamente lo studente dalla mappa', () {
      // Arrange: prepara una mappa con dati validi
      final map = {
        'name': 'Luca',
        'surname': 'Russo',
        'birthDate': '2012-03-10T00:00:00.000',
        'classId': 'c2',
        'motherName': 'Sara',
        'motherSurname': 'Gialli',
        'fatherName': 'Marco',
        'fatherSurname': 'Russo',
        'motherPhone': '3201234567',
        'fatherPhone': '3207654321',
        'studentPhone': '3209998888',
        'allergies': null,
        'autonomousExits': null,
        'notes': null,
      };
      // Act: deserializza dalla mappa
      final student = Student.fromMap('s3', map);
      // Assert: verifica che tutti i campi siano stati ricostruiti
      expect(student.id, 's3');
      expect(student.name, 'Luca');
      expect(student.surname, 'Russo');
      expect(student.birthDate, DateTime(2012, 3, 10));
      expect(student.classId, 'c2');
      expect(student.motherPhone, '3201234567');
      expect(student.fatherPhone, '3207654321');
    });

    test('fromMap gestisce campi mancanti con valori di default', () {
      // Arrange: mappa vuota (simula dati incompleti nel DB)
      final map = <String, dynamic>{};
      // Act: deserializza dalla mappa vuota
      final student = Student.fromMap('s4', map);
      // Assert: verifica che i campi mancanti abbiano valori di default sicuri
      expect(student.id, 's4');
      expect(student.name, '');
      expect(student.surname, '');
      expect(student.motherPhone, '');
      expect(student.fatherPhone, '');
      expect(student.studentPhone, '');
      // La data di nascita deve defaultare a DateTime.now() se mancante
      expect(student.birthDate, isNotNull);
    });

    test('fromMap gestisce data di nascita non valida con DateTime.now()', () {
      // Arrange: mappa con data non parsabile
      final map = {
        'name': 'Test',
        'surname': 'Student',
        'birthDate': 'data-non-valida',
      };
      // Act: deserializza con data corrotta
      final student = Student.fromMap('s5', map);
      // Assert: la data deve essere quella corrente (fallback)
      expect(student.birthDate, isNotNull);
      // La differenza con now deve essere minima (meno di 1 secondo)
      expect(
        DateTime.now().difference(student.birthDate).inSeconds,
        lessThan(2),
      );
    });
  });

  // ── Ordinamento alfabetico ──
  group('Ordinamento Studenti', () {
    test('compareBySurname ordina prima per cognome, poi per nome', () {
      // Arrange: prepara tre studenti con cognomi e nomi diversi
      final a = Student(
        id: '1', name: 'Marco', surname: 'Rossi',
        birthDate: DateTime(2010, 1, 1),
        motherName: '', motherSurname: '', fatherName: '', fatherSurname: '',
        motherPhone: '', fatherPhone: '', studentPhone: '',
      );
      final b = Student(
        id: '2', name: 'Anna', surname: 'Bianchi',
        birthDate: DateTime(2010, 1, 1),
        motherName: '', motherSurname: '', fatherName: '', fatherSurname: '',
        motherPhone: '', fatherPhone: '', studentPhone: '',
      );
      final c = Student(
        id: '3', name: 'Luca', surname: 'Bianchi',
        birthDate: DateTime(2010, 1, 1),
        motherName: '', motherSurname: '', fatherName: '', fatherSurname: '',
        motherPhone: '', fatherPhone: '', studentPhone: '',
      );
      // Act: applica il confronto
      final confrontoBA = Student.compareBySurname(b, a);
      final confrontoCA = Student.compareBySurname(c, a);
      final confrontoCB = Student.compareBySurname(c, b);
      // Assert: Bianchi viene prima di Rossi (alfabetico)
      expect(confrontoBA, lessThan(0)); // Bianchi < Rossi
      expect(confrontoCA, lessThan(0)); // Bianchi < Rossi
      // Tra stessi cognomi, Anna viene prima di Luca (alfabetico per nome)
      expect(confrontoCB, greaterThan(0)); // Luca > Anna
    });

    test('sortedBySurname restituisce una lista ordinata A-Z', () {
      // Arrange: prepara una lista disordinata di studenti
      final students = [
        _createStudent('Marco', 'Rossi'),
        _createStudent('Anna', 'Bianchi'),
        _createStudent('Luca', 'Verdi'),
        _createStudent('Giulia', 'Bianchi'),
      ];
      // Act: ordina la lista
      final sorted = Student.sortedBySurname(students);
      // Assert: verifica l'ordine alfabetico per cognome, poi nome
      expect(sorted[0].surname, 'Bianchi');
      expect(sorted[0].name, 'Anna');
      expect(sorted[1].surname, 'Bianchi');
      expect(sorted[1].name, 'Giulia');
      expect(sorted[2].surname, 'Rossi');
      expect(sorted[3].surname, 'Verdi');
    });
  });

  // ── copyWith ──
  group('Student.copyWith', () {
    test('crea una copia con campi sovrascritti', () {
      // Arrange: crea uno studente originale
      final original = _createStudent('Mario', 'Rossi');
      // Act: crea una copia modificando il nome
      final copy = original.copyWith(name: 'Giulia');
      // Assert: la copia ha il nuovo nome, l'originale rimane invariato
      expect(copy.name, 'Giulia');
      expect(copy.surname, 'Rossi'); // invariato
      expect(original.name, 'Mario'); // originale invariato
    });

    test('crea una copia identica se nessun campo viene fornito', () {
      // Arrange: crea uno studente
      final original = _createStudent('Paolo', 'Bianchi');
      // Act: crea una copia senza sovrascrivere nulla
      final copy = original.copyWith();
      // Assert: la copia e identica all'originale
      expect(copy.name, original.name);
      expect(copy.surname, original.surname);
      expect(copy.id, original.id);
    });
  });
}

/// Funzione helper per creare Student con campi opzionali vuoti.
/// Riduce la ripetizione nei test.
Student _createStudent(String name, String surname) {
  return Student(
    id: '${name.toLowerCase()}_${surname.toLowerCase()}',
    name: name,
    surname: surname,
    birthDate: DateTime(2010, 1, 1),
    motherName: '',
    motherSurname: '',
    fatherName: '',
    fatherSurname: '',
    motherPhone: '',
    fatherPhone: '',
    studentPhone: '',
  );
}
