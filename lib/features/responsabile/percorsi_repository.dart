// ══════════════════════════════════════════════════════════════════════════════
// percorsi_repository.dart — CatechHub (percorsi catechistici personalizzabili)
//
// Modulo "Responsabile Catechistico": gestisce l'elenco dei percorsi
// catechistici usato per la creazione delle classi. I percorsi di default
// sono Battesimo, Comunione, Confermazione e Post Cresima, ma il Responsabile
// può modificarli, eliminarli o crearne di nuovi.
//
// Persistenza: la lista è salvata nel box `parish_config_box` (chiave fissa),
// così sopravvive al purge dei dati demo della guida. La scrittura è
// riservata al ruolo Responsabile.
// ══════════════════════════════════════════════════════════════════════════════

import '../../core/storage/local_database.dart';
import '../../shared/models/user_role.dart';

/// Percorsi catechistici di default proposti al primo avvio.
const List<String> kDefaultPercorsiClassi = [
  'Battesimo',
  'Comunione',
  'Confermazione',
  'Post Cresima',
];

/// Repository dei percorsi catechistici personalizzabili.
class PercorsiRepository {
  /// Chiave Hive (box parish_config) della lista dei percorsi.
  static const storageKey = 'percorsi_catechistici';

  /// True se l'utente corrente può gestire i percorsi (solo Responsabile).
  bool get canManage => UserRole.isResponsabile;

  /// Legge l'elenco dei percorsi; se assente ritorna i default.
  List<String> getPercorsi() {
    try {
      final raw = LocalDatabase.parishConfig().get(storageKey);
      if (raw is List) {
        final cleaned = raw
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
        if (cleaned.isNotEmpty) return cleaned;
      }
    } catch (_) {}
    return List.of(kDefaultPercorsiClassi);
  }

  /// Salva l'elenco dei percorsi (deduplicato e ripulito). Solo il
  /// Responsabile può scrivere.
  Future<List<String>> savePercorsi(List<String> percorsi) async {
    if (!canManage) {
      throw UnsupportedError(
        'Solo il Responsabile Catechistico può gestire i percorsi.',
      );
    }
    final cleaned = percorsi
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    await LocalDatabase.parishConfig().put(storageKey, cleaned);
    await LocalDatabase.parishConfig().flush();
    return cleaned;
  }

  /// Ripristina i percorsi di default.
  Future<List<String>> resetToDefaults() async {
    return savePercorsi(List.of(kDefaultPercorsiClassi));
  }
}
