// ============================================================================
// TEST: Catechesi Model
// Copre: serializzazione, deserializzazione, copyWith, gestione tag e riferimenti
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/shared/models/catechesi_model.dart';

void main() {
  // ── Costruttore ──
  group('Costruttore Catechesi', () {
    test('crea una catechesi con tutti i campi', () {
      // Arrange: prepara i dati di una catechesi
      final now = DateTime(2024, 6, 15);
      // Act: crea l'istanza
      final catechesi = Catechesi(
        id: 'cat1',
        title: 'La Creazione',
        tags: ['creazione', 'genesi'],
        biblicalReferences: ['Genesi 1,1-31'],
        websiteReferences: ['https://example.com'],
        photoIds: ['photo1'],
        description: 'Lezione sulla creazione del mondo',
        createdAt: now,
        updatedAt: now,
      );
      // Assert: verifica tutti i campi
      expect(catechesi.id, 'cat1');
      expect(catechesi.title, 'La Creazione');
      expect(catechesi.tags, ['creazione', 'genesi']);
      expect(catechesi.biblicalReferences, ['Genesi 1,1-31']);
      expect(catechesi.description, 'Lezione sulla creazione del mondo');
      expect(catechesi.createdAt, now);
    });
  });

  // ── Serializzazione ──
  group('Serializzazione Catechesi', () {
    test('toMap e fromMap sono reversibili', () {
      // Arrange: crea una catechesi completa
      final original = Catechesi(
        id: 'cat2',
        title: 'Il Battesimo',
        tags: ['battesimo', 'sacramenti'],
        biblicalReferences: ['Matteo 3,13-17'],
        websiteReferences: [],
        photoIds: ['p1', 'p2'],
        description: 'Il sacramento del battesimo',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 6, 1),
      );
      // Act: serializza e deserializza
      final map = original.toMap();
      final restored = Catechesi.fromMap('cat2', map);
      // Assert: i campi corrispondono
      expect(restored.title, original.title);
      expect(restored.tags, original.tags);
      expect(restored.biblicalReferences, original.biblicalReferences);
      expect(restored.description, original.description);
    });

    test('fromMap gestisce campi mancanti con default', () {
      // Arrange: mappa vuota
      final map = <String, dynamic>{};
      // Act: deserializza
      final catechesi = Catechesi.fromMap('cat3', map);
      // Assert: i campi hanno valori di default
      expect(catechesi.title, '');
      expect(catechesi.tags, isEmpty);
      expect(catechesi.biblicalReferences, isEmpty);
      expect(catechesi.description, '');
    });
  });

  // ── copyWith ──
  group('Catechesi.copyWith', () {
    test('sovrascrive solo i campi specificati', () {
      // Arrange: crea una catechesi
      final original = Catechesi(
        id: 'cat1',
        title: 'Originale',
        tags: [],
        biblicalReferences: [],
        websiteReferences: [],
        photoIds: [],
        description: 'Descrizione originale',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );
      // Act: modifica solo il titolo
      final modified = original.copyWith(title: 'Aggiornato');
      // Assert: solo il titolo e cambiato
      expect(modified.title, 'Aggiornato');
      expect(modified.description, 'Descrizione originale');
      expect(modified.id, 'cat1');
    });
  });
}
