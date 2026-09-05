// ============================================================================
// TEST: ConsensiService — stato del consenso e derivazione della scadenza
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/features/responsabile/consensi_service.dart';
import 'package:CatechHub/shared/models/student_model.dart';

void main() {
  Student student({bool firmato = false, DateTime? firma, DateTime? scadenza}) {
    return Student(
      id: 's1',
      name: 'Mario',
      surname: 'Rossi',
      birthDate: DateTime(2012, 1, 1),
      motherName: '',
      motherSurname: '',
      fatherName: '',
      fatherSurname: '',
      motherPhone: '',
      fatherPhone: '',
      studentPhone: '',
      consensoPrivacyFirmato: firmato,
      dataFirmaConsenso: firma,
      dataScadenzaTrattamento: scadenza,
    );
  }

  group('ConsensiService.stato', () {
    test('ritorna nonFirmato se la scheda non e firmata', () {
      final s = student(firmato: false);
      expect(
        ConsensiService.stato(s, now: DateTime(2026, 8, 8)),
        StatoConsenso.nonFirmato,
      );
    });

    test('ritorna valido se dentro la validita', () {
      final firma = DateTime(2026, 1, 1);
      final s = student(
        firmato: true,
        firma: firma,
        scadenza: DateTime(2027, 1, 1),
      );
      expect(
        ConsensiService.stato(s, now: DateTime(2026, 8, 8)),
        StatoConsenso.valido,
      );
    });

    test('ritorna scaduto dopo la scadenza', () {
      final firma = DateTime(2025, 1, 1);
      final s = student(
        firmato: true,
        firma: firma,
        scadenza: DateTime(2026, 1, 1),
      );
      expect(
        ConsensiService.stato(s, now: DateTime(2026, 8, 8)),
        StatoConsenso.scaduto,
      );
    });

    test('calcola la scadenza di fallback (firma + 12 mesi)', () {
      final firma = DateTime(2026, 1, 1);
      final s = student(firmato: true, firma: firma);
      expect(
        ConsensiService.stato(s, now: DateTime(2026, 8, 8)),
        StatoConsenso.valido,
      );
      expect(
        ConsensiService.stato(s, now: DateTime(2027, 2, 1)),
        StatoConsenso.scaduto,
      );
    });
  });

  group('ConsensiService.info', () {
    test('esporta firma e scadenza nella rationalizzazione risposta', () {
      final s = student(
        firmato: true,
        firma: DateTime(2026, 1, 1),
        scadenza: DateTime(2027, 1, 1),
      );
      final info = ConsensiService.info(s, now: DateTime(2026, 8, 8));
      expect(info.eValido, isTrue);
      expect(info.eFirmato, isTrue);
      expect(info.firma, DateTime(2026, 1, 1));
      expect(info.scadenza, DateTime(2027, 1, 1));
    });
  });
}
