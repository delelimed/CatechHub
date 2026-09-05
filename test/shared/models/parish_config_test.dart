// ============================================================================
// TEST: ParishConfig Model
// Copre: default, copyWith, serializzazione, valori non validi per durata.
// ============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:CatechHub/shared/models/parish_config.dart';

void main() {
  group('Costruttore ParishConfig', () {
    test('usa valori di default (modalità disattivata, consenso 12 mesi)', () {
      const config = ParishConfig();
      expect(config.isResponsabileModeActive, isFalse);
      expect(config.nomeParrocchia, '');
      expect(config.diocesi, '');
      expect(config.annoCatechisticoCorrente, '');
      expect(config.durataValiditaConsensoMesi, 12);
    });

    test('ParishConfig.empty è l\'istanza di default', () {
      const empty = ParishConfig.empty;
      expect(empty.isResponsabileModeActive, isFalse);
      expect(empty, const ParishConfig());
    });
  });

  group('copyWith', () {
    test('crea una copia con solo i campi sovrascritti', () {
      const base = ParishConfig(
        nomeParrocchia: 'San Francesco',
        annoCatechisticoCorrente: '2025-2026',
      );
      final updated = base.copyWith(diocesi: 'Roma');
      expect(updated.nomeParrocchia, 'San Francesco');
      expect(updated.diocesi, 'Roma');
      expect(updated.annoCatechisticoCorrente, '2025-2026');
      expect(updated.durataValiditaConsensoMesi, 12);
    });

    test('copia identica se nessun campo fornito', () {
      const base = ParishConfig(
        nomeParrocchia: 'X',
        durataValiditaConsensoMesi: 6,
      );
      expect(base.copyWith(), base);
    });
  });

  group('Serializzazione', () {
    test('toMap/fromMap preserva tutti i campi', () {
      const config = ParishConfig(
        isResponsabileModeActive: true,
        nomeParrocchia: 'Parrocchia San Giovanni',
        diocesi: 'Diocesi di Milano',
        annoCatechisticoCorrente: '2026-2027',
        durataValiditaConsensoMesi: 18,
      );
      final roundtrip = ParishConfig.fromMap(config.toMap());
      expect(roundtrip, config);
    });

    test('fromMap gestisce campi mancanti con default', () {
      final config = ParishConfig.fromMap(<String, dynamic>{});
      expect(config, ParishConfig.empty);
    });

    test('durata non valida (<=0 o mancante) torna a 12 mesi di default', () {
      expect(
        ParishConfig.fromMap({'durataValiditaConsensoMesi': 0}),
        const ParishConfig(durataValiditaConsensoMesi: 12),
      );
      expect(
        ParishConfig.fromMap({'durataValiditaConsensoMesi': -5}),
        const ParishConfig(durataValiditaConsensoMesi: 12),
      );
    });

    test('annoLabel ritorna fallback quando assente', () {
      expect(const ParishConfig().annoLabel, 'Anno catechistico non impostato');
      expect(
        const ParishConfig(annoCatechisticoCorrente: '2026-2027').annoLabel,
        '2026-2027',
      );
    });
  });
}
