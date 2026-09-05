// ══════════════════════════════════════════════════════════════════════════════
// side_menu.dart — CatechHub (menu di navigazione laterale)
//
// Widget di navigazione primario per la sidebar desktop. Contiene il
// logo/brand "CatechHub" e le voci di menu per le sezioni principali
// dell'applicazione.
//
// CONTESTO PROGETTO:
//   CatechHub supporta due modalità di navigazione:
//     1. Sidebar desktop (isSidebar: true) — renderizzata all'interno
//        del container con gradiente blu in AppScaffold. Usata su
//        schermi > 900px. Sfondo scuro con testo bianco.
//     2. (Potenziale uso come drawer mobile) — può essere riutilizzato
//        come navigation drawer con isSidebar: false, usando colori
//        chiari per adattarsi a sfondo bianco.
//
//   Le voci del menu sono 6: Dashboard, Il mio gruppo, Programmazione,
//   Documenti, Catechesi, Impostazioni. La voce attiva è determinata
//   dal confronto con la route corrente di GoRouter e viene evidenziata
//   con sfondo semitrasparente e testo in grassetto.
//
// RELAZIONE CON app_scaffold.dart:
//   AppScaffold include SideMenu(isSidebar: true) nella colonna
//   sinistra del layout desktop. SideMenu NON gestisce la bottom
//   navigation (quella è in AppScaffold), ma condivide la stessa
//   mappa route↔selezione basata su GoRouterState.
//
// ANIMAZIONE:
//   Ogni voce di menu usa AnimatedContainer (180ms) per una transizione
//   fluida dello sfondo al cambiamento della selezione.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/user_role.dart';
import '../utils/app_mode.dart';

class SideMenu extends StatelessWidget {
  /// true = sidebar desktop (sfondo scuro, testo bianco, usato in
  /// AppScaffold). false = variante chiara per potenziale drawer.
  final bool isSidebar;

  const SideMenu({super.key, this.isSidebar = false});

  @override
  Widget build(BuildContext context) {
    // Route corrente: usata per determinare la voce di menu selezionata
    // tramite confronto esatto con la path di ogni item.
    final location = GoRouterState.of(context).uri.toString();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 30),

          // ─── BRAND ─────────────────────────────────────────────────
          // Nome dell'applicazione in evidenza all'inizio del menu.
          // Su sidebar desktop appare bianco; nella variante drawer
          // appare nel colore primario aziendale (#174A7E).
          Text(
            'CatechHub',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: isSidebar ? Colors.white : const Color(0xFF174A7E),
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 25),

          // ─── VOCI DI MENU ──────────────────────────────────────────
          // La navigazione dipende dal ruolo:
          //   - Catechista: Dashboard, Gruppo, Programmazione, Documenti,
          //     Catechesi, Impostazioni.
          //   - Responsabile: Dashboard parrocchiale e funzioni della
          //     parrocchia (Classi, Iscrizioni, Catechisti, Logistica,
          //     Consensi, Rete, Archivio) + Impostazioni.
          if (UserRole.isResponsabile) ...[
            _item(
              context,
              location,
              '/parrocchia',
              Icons.dashboard_rounded,
              'Dashboard',
            ),
            _item(
              context,
              location,
              '/parrocchia/classi',
              Icons.class_rounded,
              'Classi',
            ),
            _item(
              context,
              location,
              '/parrocchia/iscrizioni',
              Icons.how_to_reg_rounded,
              'Iscrizioni',
            ),
            _item(
              context,
              location,
              '/parrocchia/catechisti',
              Icons.people_alt_rounded,
              'Catechisti',
            ),
            _item(
              context,
              location,
              '/parrocchia/logistica',
              Icons.meeting_room_rounded,
              'Logistica',
            ),
            _item(
              context,
              location,
              '/parrocchia/consensi',
              Icons.task_alt_rounded,
              'Consensi',
            ),
            _item(
              context,
              location,
              '/parrocchia/rete',
              Icons.network_check_rounded,
              'Rete parrocchiale',
            ),
            _item(
              context,
              location,
              '/parrocchia/archivio',
              Icons.history_rounded,
              'Archivio storico',
            ),
          ] else ...[
            _item(context, location, '/', Icons.dashboard_rounded, 'Dashboard'),
            _item(
              context,
              location,
              '/my-group',
              Icons.groups_rounded,
              'Il mio gruppo',
            ),
            _item(
              context,
              location,
              '/planning',
              Icons.calendar_month_rounded,
              'Programmazione',
            ),
            _item(
              context,
              location,
              '/documents',
              Icons.description_rounded,
              'Documenti',
            ),
            _item(
              context,
              location,
              '/catechesi',
              Icons.menu_book_rounded,
              'Catechesi',
            ),
            if (AppModeUtils.canViewLogistica())
              _item(
                context,
                location,
                '/parrocchia/logistica',
                Icons.meeting_room_rounded,
                'Aule e orari',
              ),
          ],
          _item(
            context,
            location,
            '/settings',
            Icons.settings_rounded,
            'Impostazioni',
          ),
        ],
      ),
    );
  }

  /// Costruisce una singola voce di menu.
  ///
  /// Parametri:
  ///   - [context]: BuildContext per tema e navigazione
  ///   - [location]: route corrente (per confronto selezione)
  ///   - [route]: path GoRouter su cui navigare al tap
  ///   - [icon]: icona Material Design della voce
  ///   - [title]: etichetta testuale della voce
  ///
  /// La voce è selezionata quando location == route. La selezione
  /// modifica:
  ///   - Sfondo: semitrasparente (bianco su sidebar, blu su drawer)
  ///   - Testo: grassetto (bold)
  ///   - Icona: colore pieno anziché grigio
  /// L'animazione dello sfondo è gestita da AnimatedContainer (180ms).
  Widget _item(
    BuildContext context,
    String location,
    String route,
    IconData icon,
    String title,
  ) {
    final selected = location == route;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? (isSidebar
                    ? Colors.white.withValues(alpha: 0.15)
                    : const Color(0xFF174A7E).withValues(alpha: 0.1))
              : Colors.transparent,
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),

          leading: Icon(
            icon,
            color: selected
                ? (isSidebar ? Colors.white : const Color(0xFF174A7E))
                : (isSidebar ? Colors.white70 : Colors.grey.shade700),
          ),

          title: Text(
            title,
            style: TextStyle(
              color: isSidebar ? Colors.white : Colors.black87,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),

          onTap: () {
            context.go(route);
          },
        ),
      ),
    );
  }
}
