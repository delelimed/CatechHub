// ══════════════════════════════════════════════════════════════════════════════
// dashboard_card.dart — CatechHub (carta informativa per la dashboard)
//
// Widget card riutilizzabile per la visualizzazione di metriche e
// informazioni sintetiche nella dashboard principale dell'app.
//
// CONTESTO PROGETTO:
//   La dashboard di CatechHub mostra una panoramica dello stato del
//   gruppo catechistico: presenze medie, assenze elevate, prossimo
//   incontro, documenti in attesa, azioni rapide. Questo widget fornisce
//   una card standardizzata per presentare voci informative (es. metriche,
//   riepiloghi) con icona, titolo e sottotitolo in un layout verticale.
//
//   Anche se la dashboard_page.dart attuale costruisce i propri pannelli
//   internamente (_MetricPanel, _HighAbsencePanel, ecc.), questo widget
//   rimane disponibile come building block per future viste dashboard
//   o per uso in altre sezioni dell'app che richiedono cards informative
//   con formato icona + titolo + descrizione.
//
// STRUTTURA:
//   ┌─────────────────────┐
//   │  [icona 40px]       │
//   │                     │
//   │  Titolo (titleLarge)│
//   │                     │
//   │  Sottotitolo        │
//   └─────────────────────┘
//
// PARAMETRI:
//   - [icon]: IconData da mostrare in alto (es. Icons.trending_up)
//   - [title]: Testo principale in titleLarge
//   - [subtitle]: Testo descrittivo secondario
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class DashboardCard extends StatelessWidget {
  /// Titolo principale della card (es. "Presenze medie", "Assenze elevate").
  final String title;

  /// Sottotitolo descrittivo (es. "85%", "3 studenti con >= 6 assenze").
  final String subtitle;

  /// Icona rappresentativa della metrica (es. Icons.trending_up_rounded).
  final IconData icon;

  const DashboardCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 40),
            const Spacer(),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(subtitle),
          ],
        ),
      ),
    );
  }
}
