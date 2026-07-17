// ============================================================================
// TEST: PlanningMeeting Model
// Copre: serializzazione, deserializzazione, gestione titolo legacy, flag isReunion
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/shared/models/planning_meeting.dart';

void main() {
  // ── Serializzazione ──
  group('Serializzazione PlanningMeeting', () {
    test('toMap e fromMap sono reversibili', () {
      // Arrange: prepara una riunione di programmazione
      final original = PlanningMeeting(
        id: 'pm1',
        classId: 'c1',
        createdBy: 'cat1',
        date: DateTime(2024, 6, 15),
        title: 'Lezione sulla preghiera',
        activity: 'Gioco introduttivo + catechesi',
        notes: 'Portare il materiale didattico',
        isReunion: false,
      );
      // Act: serializza e deserializza
      final map = original.toMap();
      final restored = PlanningMeeting.fromMap('pm1', map);
      // Assert: i campi corrispondono
      expect(restored.classId, 'c1');
      expect(restored.title, 'Lezione sulla preghiera');
      expect(restored.activity, 'Gioco introduttivo + catechesi');
      expect(restored.isReunion, false);
    });

    test('fromMap genera un titolo di default se mancante', () {
      // Arrange: mappa senza titolo (caso legacy)
      final map = {
        'classId': 'c1',
        'date': '2024-06-15T00:00:00.000',
      };
      // Act: deserializza senza titolo
      final meeting = PlanningMeeting.fromMap('pm2', map);
      // Assert: il titolo deve essere generato dalla data
      expect(meeting.title, contains('Giornata del'));
      expect(meeting.title, contains('15'));
      expect(meeting.title, contains('6'));
    });

    test('fromMap accetta un titolo legacy vuoto e genera default', () {
      // Arrange: mappa con titolo vuoto
      final map = {
        'classId': 'c1',
        'date': '2024-03-20T00:00:00.000',
        'title': '',
      };
      // Act: deserializza
      final meeting = PlanningMeeting.fromMap('pm3', map);
      // Assert: il titolo deve essere generato dalla data
      expect(meeting.title, contains('Giornata del'));
      expect(meeting.title, contains('20'));
      expect(meeting.title, contains('3'));
    });

    test('fromMap legge isReunion dal campo isReunion', () {
      // Arrange: mappa con isReunion = true
      final map = {
        'classId': 'c1',
        'date': '2024-06-15T00:00:00.000',
        'title': 'Riunione catechisti',
        'isReunion': true,
      };
      // Act: deserializza
      final meeting = PlanningMeeting.fromMap('pm4', map);
      // Assert: isReunion deve essere true
      expect(meeting.isReunion, isTrue);
    });

    test('fromMap imposta isReunion a false se non presente', () {
      // Arrange: mappa senza campo isReunion
      final map = {
        'classId': 'c1',
        'date': '2024-06-15T00:00:00.000',
        'title': 'Lezione normale',
      };
      // Act: deserializza
      final meeting = PlanningMeeting.fromMap('pm5', map);
      // Assert: isReunion deve essere false
      expect(meeting.isReunion, isFalse);
    });

    test('fromMap legge notes da campo notes o publicNotes (legacy)', () {
      // Arrange: mappa con il campo legacy publicNotes
      final map = {
        'classId': 'c1',
        'date': '2024-06-15T00:00:00.000',
        'title': 'Test',
        'publicNotes': 'Note dal campo legacy',
      };
      // Act: deserializza
      final meeting = PlanningMeeting.fromMap('pm6', map);
      // Assert: notes deve essere letto da publicNotes
      expect(meeting.notes, 'Note dal campo legacy');
    });
  });
}
