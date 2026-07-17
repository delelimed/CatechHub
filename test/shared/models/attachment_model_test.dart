// ============================================================================
// TEST: Attachment Model
// Copre: serializzazione, etichette dimensione, rilevamento tipo file
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/shared/models/attachment_model.dart';

void main() {
  // ── Serializzazione ──
  group('Serializzazione Attachment', () {
    test('toMap e fromMap sono reversibili', () {
      // Arrange: prepara un allegato
      final original = Attachment(
        id: 'a1',
        parentId: 's1',
        parentType: 'student',
        name: 'foto_classe.jpg',
        mimeType: 'image/jpeg',
        size: 2048,
        createdAt: DateTime(2024, 6, 15),
        fileHash: 'abc123',
        description: 'Foto della classe',
      );
      // Act: serializza e deserializza
      final map = original.toMap();
      final restored = Attachment.fromMap('a1', map);
      // Assert: i campi corrispondono
      expect(restored.parentId, 's1');
      expect(restored.name, 'foto_classe.jpg');
      expect(restored.mimeType, 'image/jpeg');
      expect(restored.size, 2048);
      expect(restored.description, 'Foto della classe');
    });

    test('fromMap gestisce campi mancanti', () {
      // Arrange: mappa vuota
      final map = <String, dynamic>{};
      // Act: deserializza
      final attachment = Attachment.fromMap('a2', map);
      // Assert: valori di default
      expect(attachment.parentId, '');
      expect(attachment.mimeType, 'application/octet-stream');
      expect(attachment.size, 0);
      expect(attachment.description, isNull);
    });
  });

  // ── Etichette dimensione ──
  group('Attachment.sizeLabel', () {
    test('formatta dimensioni inferiori a 1 KB in byte', () {
      // Arrange: allegato piccolo (500 byte)
      final small = _createAttachment(500);
      // Act: richiedi l'etichetta
      // Assert: deve mostrare i byte
      expect(small.sizeLabel, '500 B');
    });

    test('formatta dimensioni in KB per file medi', () {
      // Arrange: allegato medio (1.5 KB)
      final medium = _createAttachment(1536);
      // Act: richiedi l'etichetta
      // Assert: deve mostrare i KB con un decimale
      expect(medium.sizeLabel, '1.5 KB');
    });

    test('formatta dimensioni in MB per file grandi', () {
      // Arrange: allegato grande (2.5 MB)
      final large = _createAttachment(2 * 1024 * 1024 + 512 * 1024);
      // Act: richiedi l'etichetta
      // Assert: deve mostrare i MB con un decimale
      expect(large.sizeLabel, '2.5 MB');
    });
  });

  // ── Rilevamento tipo file ──
  group('Attachment tipo file', () {
    test('isImage rileva file JPEG', () {
      // Arrange: allegato JPEG
      final jpeg = _createAttachmentWithType('image/jpeg');
      // Assert: isImage deve essere true
      expect(jpeg.isImage, isTrue);
    });

    test('isImage rileva file PNG', () {
      // Arrange: allegato PNG
      final png = _createAttachmentWithType('image/png');
      // Assert: isImage deve essere true
      expect(png.isImage, isTrue);
    });

    test('isPdf rileva file PDF', () {
      // Arrange: allegato PDF
      final pdf = _createAttachmentWithType('application/pdf');
      // Assert: isPdf deve essere true
      expect(pdf.isPdf, isTrue);
    });

    test('isImage e false per file PDF', () {
      // Arrange: allegato PDF
      final pdf = _createAttachmentWithType('application/pdf');
      // Assert: isImage deve essere false
      expect(pdf.isImage, isFalse);
    });

    test('isPdf e false per file immagine', () {
      // Arrange: allegato JPEG
      final jpeg = _createAttachmentWithType('image/jpeg');
      // Assert: isPdf deve essere false
      expect(jpeg.isPdf, isFalse);
    });
  });
}

/// Helper per creare un Attachment con una specifica dimensione.
Attachment _createAttachment(int size) {
  return Attachment(
    id: 'a',
    parentId: 'p',
    parentType: 'student',
    name: 'file',
    mimeType: 'application/octet-stream',
    size: size,
    createdAt: DateTime(2024),
    fileHash: '',
  );
}

/// Helper per creare un Attachment con un specifico mimeType.
Attachment _createAttachmentWithType(String mimeType) {
  return Attachment(
    id: 'a',
    parentId: 'p',
    parentType: 'student',
    name: 'file',
    mimeType: mimeType,
    size: 1024,
    createdAt: DateTime(2024),
    fileHash: '',
  );
}
