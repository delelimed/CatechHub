import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'side_menu.dart';

class AppScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? floatingActionButton;

  const AppScaffold({
    super.key,
    required this.title,
    required this.child,
    this.floatingActionButton,
  });

  /// =========================
  /// ROUTE -> INDEX
  /// =========================
  int _indexFromLocation(String location) {
    if (location.startsWith('/my-group')) return 1;
    if (location.startsWith('/planning')) return 2;
    if (location.startsWith('/documents')) return 3;
    if (location.startsWith('/settings')) return 4;

    return 0;
  }

  /// =========================
  /// INDEX -> ROUTE
  /// =========================
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
    final isDesktop = MediaQuery.of(context).size.width > 900;

    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexFromLocation(location);
    final showBackToHome = location != '/';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      floatingActionButton: floatingActionButton,

      /// =========================
      /// BODY
      /// =========================
      body: SafeArea(
        child: Row(
          children: [
            /// =========================
            /// DESKTOP SIDEBAR
            /// =========================
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
                      color: Colors.blue.withOpacity(0.15),
                      blurRadius: 25,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const SideMenu(isSidebar: true),
              ),

            /// =========================
            /// CONTENT
            /// =========================
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
                    /// =========================
                    /// TOP BAR
                    /// =========================
                    Container(
                      height: 78,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
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
                                onPressed: () => context.go('/'),
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

                    /// =========================
                    /// PAGE BODY
                    /// =========================
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
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

      /// =========================
      /// MOBILE NAVIGATION
      /// =========================
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
                      const Color(0xFF174A7E).withOpacity(0.15),

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
