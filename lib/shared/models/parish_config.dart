// ══════════════════════════════════════════════════════════════════════════════
// parish_config.dart — CatechHub (configurazione parrocchiale)
//
// Modulo "Responsabile Catechistico": rappresenta la configurazione locale
// della parrocchia. È il singolo record persistito nel box Hive
// `parish_config_box` con chiave fissa [ParishConfig.storageKey].
//
// REGOLE:
//   - [isResponsabileModeActive] sblocca la dashboard e i menu dedicati al
//     Responsabile Catechistico.
//   - [durataValiditaConsensoMesi] definisce la validità del consenso GDPR
//     al trattamento dei dati dei minori (default 12 mesi).
//   - La configurazione è locale-first: nessun dato lascia il dispositivo
//     senza un esplicito scambio P2P.
// ══════════════════════════════════════════════════════════════════════════════

/// Configurazione della parrocchia (singolo record, chiave fissa).
class ParishConfig {
  /// Chiave Hive dell'unico record di configurazione parrocchiale.
  static const storageKey = 'parish_config';

  /// Durata di default della validità del consenso GDPR (in mesi).
  static const int defaultDurataConsensoMesi = 12;

  /// Soglia di default per le assenze consecutive (allerta).
  static const int defaultSogliaAssenzeConsecutive = 3;

  /// Se true, la modalità "Responsabile Catechistico" è attiva: vengono
  /// sbloccate dashboard e menu dedicati (classi globali, aule, log GDPR).
  final bool isResponsabileModeActive;

  /// Nome della parrocchia (es. "Parrocchia San Francesco d'Assisi").
  final String nomeParrocchia;

  /// Diocesi di appartenenza (es. "Diocesi di Roma").
  final String diocesi;

  /// Anno catechistico corrente (es. "2026-2027").
  final String annoCatechisticoCorrente;

  /// Validità del consenso GDPR espresso dai genitori/tutori (in mesi).
  /// Default: [defaultDurataConsensoMesi].
  final int durataValiditaConsensoMesi;

  /// Soglia di assenze consecutive per attivare l'allerta (default 3).
  final int sogliaAssenzeConsecutive;

  const ParishConfig({
    this.isResponsabileModeActive = false,
    this.nomeParrocchia = '',
    this.diocesi = '',
    this.annoCatechisticoCorrente = '',
    this.durataValiditaConsensoMesi = defaultDurataConsensoMesi,
    this.sogliaAssenzeConsecutive = defaultSogliaAssenzeConsecutive,
  });

  /// Configurazione "vuota" di default (modalità Responsabile disattivata).
  static const empty = ParishConfig();

  ParishConfig copyWith({
    bool? isResponsabileModeActive,
    String? nomeParrocchia,
    String? diocesi,
    String? annoCatechisticoCorrente,
    int? durataValiditaConsensoMesi,
    int? sogliaAssenzeConsecutive,
  }) {
    return ParishConfig(
      isResponsabileModeActive:
          isResponsabileModeActive ?? this.isResponsabileModeActive,
      nomeParrocchia: nomeParrocchia ?? this.nomeParrocchia,
      diocesi: diocesi ?? this.diocesi,
      annoCatechisticoCorrente:
          annoCatechisticoCorrente ?? this.annoCatechisticoCorrente,
      durataValiditaConsensoMesi:
          durataValiditaConsensoMesi ?? this.durataValiditaConsensoMesi,
      sogliaAssenzeConsecutive:
          sogliaAssenzeConsecutive ?? this.sogliaAssenzeConsecutive,
    );
  }

  factory ParishConfig.fromMap(Map<String, dynamic> data) {
    final rawDurata = data['durataValiditaConsensoMesi'];
    final rawSoglia = data['sogliaAssenzeConsecutive'];
    return ParishConfig(
      isResponsabileModeActive: data['isResponsabileModeActive'] == true,
      nomeParrocchia: data['nomeParrocchia'] ?? '',
      diocesi: data['diocesi'] ?? '',
      annoCatechisticoCorrente: data['annoCatechisticoCorrente'] ?? '',
      durataValiditaConsensoMesi: rawDurata is int
          ? (rawDurata > 0 ? rawDurata : defaultDurataConsensoMesi)
          : defaultDurataConsensoMesi,
      sogliaAssenzeConsecutive: rawSoglia is int
          ? (rawSoglia > 0 ? rawSoglia : defaultSogliaAssenzeConsecutive)
          : defaultSogliaAssenzeConsecutive,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isResponsabileModeActive': isResponsabileModeActive,
      'nomeParrocchia': nomeParrocchia,
      'diocesi': diocesi,
      'annoCatechisticoCorrente': annoCatechisticoCorrente,
      'durataValiditaConsensoMesi': durataValiditaConsensoMesi,
      'sogliaAssenzeConsecutive': sogliaAssenzeConsecutive,
    };
  }

  /// Anno catechistico formattato o fallback leggibile.
  String get annoLabel =>
      annoCatechisticoCorrente.trim().isEmpty
          ? 'Anno catechistico non impostato'
          : annoCatechisticoCorrente.trim();

  @override
  bool operator ==(Object other) =>
      other is ParishConfig &&
      other.isResponsabileModeActive == isResponsabileModeActive &&
      other.nomeParrocchia == nomeParrocchia &&
      other.diocesi == diocesi &&
      other.annoCatechisticoCorrente == annoCatechisticoCorrente &&
      other.durataValiditaConsensoMesi == durataValiditaConsensoMesi &&
      other.sogliaAssenzeConsecutive == sogliaAssenzeConsecutive;

  @override
  int get hashCode => Object.hash(
        isResponsabileModeActive,
        nomeParrocchia,
        diocesi,
        annoCatechisticoCorrente,
        durataValiditaConsensoMesi,
        sogliaAssenzeConsecutive,
      );
}
