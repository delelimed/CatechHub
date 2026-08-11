// ══════════════════════════════════════════════════════════════════════════════
// admin_section_pages.dart - CatechHub (schermate autonome della gestione)
//
// Ogni sezione amministrativa del Responsabile vive in una pagina a schermo
// pieno raggiungibile dall'hub [ResponsabileAdminPage]. Niente tab affollati:
// su tablet e smartphone si naviga una funzione alla volta.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../shared/widgets/app_scaffold.dart';
import 'allarme_assenze_page.dart';
import 'aula_management_page.dart';
import 'classi_management_page.dart';
import 'iscrizioni_page.dart';

/// Schermata autonoma: gestione classi e assegnazione catechisti.
class ClassiRoutePage extends StatelessWidget {
  const ClassiRoutePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'Classi',
      child: ClassiManagementPage(),
    );
  }
}

/// Schermata autonoma: iscrizioni, censimento e passaggio d'anno.
class IscrizioniRoutePage extends StatelessWidget {
  const IscrizioniRoutePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'Iscrizioni',
      child: IscrizioniPage(),
    );
  }
}

/// Schermata autonoma: aule e orari settimanali.
class LogisticaRoutePage extends StatelessWidget {
  const LogisticaRoutePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'Logistica',
      child: AulaManagementSection(),
    );
  }
}

/// Schermata autonoma: allarme assenze prolungate.
class AllarmiRoutePage extends StatelessWidget {
  const AllarmiRoutePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'Allarme assenze',
      child: AllarmeAssenzePage(),
    );
  }
}
