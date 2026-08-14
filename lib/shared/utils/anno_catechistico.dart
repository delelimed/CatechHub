// ══════════════════════════════════════════════════════════════════════════════
// anno_catechistico.dart — CatechHub (anno catechistico corrente)
//
// Helper condiviso per calcolare l'anno catechistico corrente a partire dalla
// data odierna. L'anno catechistico inizia a settembre: ad esempio oggi
// (agosto 2026) → "2025-2026", da settembre 2026 → "2026-2027".
// Usato per precompilare il campo "Anno catechistico corrente" nell'onboarding
// e nelle impostazioni quando non ancora configurato.
// ══════════════════════════════════════════════════════════════════════════════

/// Calcola l'anno catechistico corrente (es. "2026-2027") in base alla data
/// odierna. L'anno catechistico parte a settembre.
String currentCatechisticYear() {
  final now = DateTime.now();
  final startYear = now.month >= 9 ? now.year : now.year - 1;
  return '$startYear-${startYear + 1}';
}
