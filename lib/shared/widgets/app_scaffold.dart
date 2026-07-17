// ══════════════════════════════════════════════════════════════════════════════
// app_scaffold.dart — CatechHub (widget di layout principale)
//
// Scaffold universale dell'applicazione CatechHub. Avvolge ogni pagina
// dell'app fornendo:
//   - Sidebar desktop persistente (SideMenu)
//   - Top bar con titolo contestuale e back-to-home
//   - Body content container con sfondo bianco e ombreggiatura
//   - Bottom navigation bar mobile (5 voci: Home, Gruppo, Programma,
//     Documenti, Impostazioni)
//
// CONTESTO PROGETTO:
//   CatechHub è un'app offline-first per registri di catechismo con
//   architettura a pagina singola (SPA). Tutte le pagine (dashboard,
//   anagrafica studenti, presenze, documenti, impostazioni, sync
//   Bluetooth, catechesi, ecc.) sono renderizzate come child di questo
//   scaffold, garantendo coerenza visiva e navigazione unificata.
//   Il widget distingue automaticamente il layout desktop (>= 900px)
//   con sidebar laterale da quello mobile con bottom navigation bar.
//
// USO:
//   return AppScaffold(
//     title: 'Dashboard',
//     child: DashboardContent(),
//   );
//
// DIPENDENZA CRITICA:
//   Dipende da go_router per:
//   - Ottenere la route corrente (GoRouterState.of(context))
//   - Navigare sulle route (context.go())
//   La mappa route↔indice deve rimanere sincronizzata con router.dart.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'side_menu.dart';

class AppScaffold extends StatelessWidget {
  /// Titolo visualizzato nella top bar di ogni pagina.
  final String title;

  /// Contenuto principale della pagina (iniettato da ogni feature).
  final Widget child;

  /// FAB opzionale (es. "Aggiungi studente" in StudentsPage, "Nuovo
  /// incontro" in PlanningPage, "Nuovo documento" in DocumentsPage).
  final Widget? floatingActionButton;

  const AppScaffold({
    super.key,
    required this.title,
    required this.child,
    this.floatingActionButton,
  });

  /// Converte la path della route corrente nell'indice della
  /// bottom navigation bar (mobile) o della sidebar evidenziazione.
  ///
  /// MANTENERE SINCRONIZZATO CON router.dart:
  ///   index 0 → '/' (Dashboard)
  ///   index 1 → '/my-group'
  ///   index 2 → '/planning'
  ///   index 3 → '/documents'
  ///   index 4 → '/settings'
  int _indexFromLocation(String location) {
    if (location.startsWith('/my-group')) return 1;
    if (location.startsWith('/planning')) return 2;
    if (location.startsWith('/documents')) return 3;
    if (location.startsWith('/settings')) return 4;

    return 0;
  }

  /// Converte l'indice della navigation bar nella path della route.
  /// È l'inversa di _indexFromLocation.
  String _routeFromIndex(int index) {
    switch (index) {
      case 0:
        return '/';

      case 1:
        return '/my-group';

      case 2:
        return '/planning';

      case 3:
        return '/documents';

      case 4:
        return '/settings';

      default:
        return '/';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Breakpoint desktop: oltre 900px mostra la sidebar anziché la
    // bottom navigation. Questo breakpoint è allineato con le
    // dimensioni tipiche di tablet orizzontale.
    final isDesktop = MediaQuery.of(context).size.width > 900;

    // Legge la route corrente da GoRouter per determinare:
    // 1. Quale voce della navigation bar evidenziare (currentIndex)
    // 2. Se mostrare il pulsante back (solo sottopagine, non sezioni principali)
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexFromLocation(location);
    final showBackToHome =
        !['/', '/my-group', '/planning', '/documents', '/settings']
            .contains(location);

    return Scaffold(
      // Sfondo grigio chiaro: colore di base dell'intera app.
      // Tutti i container white si stagliano su questo sfondo.
      backgroundColor: const Color(0xFFF5F8FC),
      floatingActionButton: floatingActionButton,

      // ─── BODY: Sidebar (desktop) + Content ───────────────────────────
      body: SafeArea(
        child: Row(
          children: [
            // Sidebar desktop: visibile solo su schermi > 900px.
            // Include il menu di navigazione SideMenu con sfondo
            // gradiente blu (#174A7E → #2368B1). Usata da tutte le
            // pagine come navigazione persistente su tablet/desktop.
            if (isDesktop)
              Container(
                width: 270,
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF174A7E),
                      Color(0xFF2368B1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.15),
                      blurRadius: 25,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const SideMenu(isSidebar: true),
              ),

            // Area contenuto principale: si espande a riempire lo
            // spazio residuo (Expanded). Include top bar + child.
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  top: 16,
                  right: 16,
                  bottom: isDesktop ? 16 : 0,
                  left: isDesktop ? 0 : 16,
                ),
                child: Column(
                  children: [
                    // ─── TOP BAR ─────────────────────────────────────
                    // Barra superiore con: back button (opzionale),
                    // titolo pagina, icona chiesa. Stile coerente su
                    // tutte le pagine dell'app. Il back button appare
                    // solo sulle sottopagine (non sulle sezioni principali).
                    Container(
                      height: 78,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          if (showBackToHome) ...[
                            Tooltip(
                              message: 'Torna alla Home',
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_rounded),
                                color: const Color(0xFF174A7E),
                                onPressed: () {
                                  if (context.canPop()) {
                                    context.pop();
                                  } else {
                                    context.go('/');
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              title,
                              style:
                                  theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF174A7E),
                              ),
                            ),
                          ),
                          // Icona chiesa: elemento decorativo che
                          // richiama l'ambito pastorale dell'app.
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF2FF),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.church_rounded,
                              color: Color(0xFF174A7E),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // ─── PAGE BODY ───────────────────────────────────
                    // Contenitore bianco con bordi arrotondati e ombra
                    // leggera. Ogni pagina dell'app viene renderizzata
                    // qui come child. Questo contenitore garantisce:
                    // - Sfondo bianco uniforme per tutti i contenuti
                    // - Spaziatura interna (20px) su tutti i lati
                    // - Scroll gestito dalla pagina child (ListView,
                    //   SingleChildScrollView, ecc.)
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // ─── MOBILE BOTTOM NAVIGATION ─────────────────────────────────
      // Navigazione a 5 voci (Material 3 NavigationBar) visibile solo
      // su schermi ≤ 900px. Le voci corrispondono alle route principali:
      //   Home ('/'), Gruppo ('/my-group'), Programma ('/planning'),
      //   Documenti ('/documents'), Impostazioni ('/settings').
      // La selezione corrente è determinata da currentIndex derivato
      // dalla route GoRouter. Il design è coerente con le specifiche
      // Material 3: indicatorColor trasparente blu, icon filled per
      // la voce selezionata, outline per le non selezionate.
      bottomNavigationBar: isDesktop
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: NavigationBar(
                  height: 72,
                  backgroundColor: Colors.white,
                  selectedIndex: currentIndex,
                  indicatorColor:
                      const Color(0xFF174A7E).withValues(alpha: 0.15),

                  onDestinationSelected: (index) {
                    context.go(_routeFromIndex(index));
                  },

                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_rounded),
                      selectedIcon: Icon(Icons.dashboard),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.groups_rounded),
                      selectedIcon: Icon(Icons.groups),
                      label: 'Gruppo',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.calendar_month_outlined),
                      selectedIcon: Icon(Icons.calendar_month),
                      label: 'Programma',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.description_outlined),
                      selectedIcon: Icon(Icons.description),
                      label: 'Documenti',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: 'Impostazioni',
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
