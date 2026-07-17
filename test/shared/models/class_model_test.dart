// ============================================================================
// TEST: SchoolClass Model
// Copre: serializzazione, deserializzazione, copyWith, gestione studentIds
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/shared/models/class_model.dart';

void main() {
  // ── Costruttore ──
  group('Costruttore SchoolClass', () {
    test('crea una classe con tutti i campi', () {
      // Arrange: prepara gli ID di studenti e catechisti
      final studentIds = ['s1', 's2', 's3'];
      final catechistIds = ['cat1'];
      // Act: crea l'istanza di SchoolClass
      final schoolClass = SchoolClass(
        id: 'c1',
        name: 'Prima Elementare',
        studentIds: studentIds,
        catechistIds: catechistIds,
      );
      // Assert: verifica che tutti i campi siano corretti
      expect(schoolClass.id, 'c1');
      expect(schoolClass.name, 'Prima Elementare');
      expect(schoolClass.studentIds, ['s1', 's2', 's3']);
      expect(schoolClass.catechistIds, ['cat1']);
    });
  });

  // ── Serializzazione ──
  group('Serializzazione SchoolClass', () {
    test('toMap genera una mappa corretta', () {
      // Arrange: crea una classe
      final schoolClass = SchoolClass(
        id: 'c2',
        name: 'Seconda Elementare',
        studentIds: ['s1', 's2'],
        catechistIds: ['cat1', 'cat2'],
      );
      // Act: serializza
      final map = schoolClass.toMap();
      // Assert: verifica i campi della mappa
      expect(map['name'], 'Seconda Elementare');
      expect(map['studentIds'], ['s1', 's2']);
      expect(map['catechistIds'], ['cat1', 'cat2']);
      // toMap non include l'id (chiave Hive)
      expect(map.containsKey('id'), isFalse);
    });

    test('fromMap ricostruisce la classe dalla mappa', () {
      // Arrange: prepara una mappa
      final map = {
        'name': 'Terza Elementare',
        'studentIds': ['s3', 's4', 's5'],
        'catechistIds': ['cat3'],
      };
      // Act: deserializza
      final schoolClass = SchoolClass.fromMap('c3', map);
      // Assert: verifica la ricostruzione
      expect(schoolClass.id, 'c3');
      expect(schoolClass.name, 'Terza Elementare');
      expect(schoolClass.studentIds, ['s3', 's4', 's5']);
      expect(schoolClass.catechistIds, ['cat3']);
    });

    test('fromMap gestisce liste nulli con liste vuote', () {
      // Arrange: mappa senza le liste di ID
      final map = <String, dynamic>{
        'name': 'Classe Vuota',
      };
      // Act: deserializza
      final schoolClass = SchoolClass.fromMap('c4', map);
      // Assert: le liste devono essere vuote, non null
      expect(schoolClass.studentIds, isEmpty);
      expect(schoolClass.catechistIds, isEmpty);
    });

    test('fromMap converte elementi non-stringa in stringa', () {
      // Arrange: mappa con ID numerici (caso legacy)
      final map = {
        'name': 'Classe Legacy',
        'studentIds': [101, 102],
        'catechistIds': [1],
      };
      // Act: deserializza
      final schoolClass = SchoolClass.fromMap('c5', map);
      // Assert: gli ID devono essere convertiti in stringa
      expect(schoolClass.studentIds, ['101', '102']);
      expect(schoolClass.catechistIds, ['1']);
    });
  });

  // ── copyWith ──
  group('SchoolClass.copyWith', () {
    test('crea una copia con campi sovrascritti', () {
      // Arrange: crea una classe
      final original = SchoolClass(
        id: 'c1',
        name: 'Prima',
        studentIds: ['s1'],
        catechistIds: ['cat1'],
      );
      // Act: crea una copia con un nome diverso
      final copy = original.copyWith(name: 'Seconda');
      // Assert: il nome e cambiato, gli altri campi rimangono
      expect(copy.name, 'Seconda');
      expect(copy.id, 'c1');
      expect(copy.studentIds, ['s1']);
    });

    test('crea una copia con studentIds aggiornati', () {
      // Arrange: crea una classe con un solo studente
      final original = SchoolClass(
        id: 'c1',
        name: 'Classe',
        studentIds: ['s1'],
        catechistIds: [],
      );
      // Act: aggiunge uno studente tramite copyWith
      final copy = original.copyWith(studentIds: ['s1', 's2', 's3']);
      // Assert: la lista e aggiornata
      expect(copy.studentIds, hasLength(3));
      expect(copy.studentIds, contains('s3'));
    });
  });
}
