import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/breakpoints.dart';
import 'app_bottom_navigation.dart';
import 'mini_player.dart';
import 'offline_banner.dart';

/// Hosts the 5 nav tabs (Home, Create, History, Projects, Profile) as a
/// [StatefulShellRoute], preserving each tab's navigation stack and scroll
/// position when switching tabs.
///
/// Layout adapts to the window's [AppFormFactor] rather than the platform -
/// a phone-sized window always gets the bottom bar and a tablet/desktop-sized
/// one always gets a side rail, regardless of OS. See
/// docs/CROSS_PLATFORM_ARCHITECTURE.md "Responsive UI".
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _items = [
    AppNavItem(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    AppNavItem(
      label: 'Create',
      icon: Icons.add_circle_outline_rounded,
      selectedIcon: Icons.add_circle_rounded,
    ),
    AppNavItem(
      label: 'History',
      icon: Icons.history_rounded,
      selectedIcon: Icons.history_rounded,
    ),
    AppNavItem(
      label: 'Projects',
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder_rounded,
    ),
    AppNavItem(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  void _onDestinationSelected(int index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    final formFactor = Breakpoints.of(context);

    if (formFactor == AppFormFactor.compact) {
      return Scaffold(
        body: Column(
          children: [
            const OfflineBanner(),
            Expanded(child: navigationShell),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            AppBottomNavigation(
              items: _items,
              currentIndex: navigationShell.currentIndex,
              onDestinationSelected: _onDestinationSelected,
            ),
          ],
        ),
      );
    }

    // Medium/expanded (tablet/desktop-sized window): a side rail instead of
    // a bottom bar gives the content area the full window width, and an
    // extended rail (icon + label) once there's room for it per Material 3
    // guidance rather than icon-only at every wide size.
    final extended = formFactor == AppFormFactor.expanded;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            minExtendedWidth: 200,
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onDestinationSelected,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            destinations: [
              for (final item in _items)
                NavigationRailDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: Text(item.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                const OfflineBanner(),
                const MiniPlayer(),
                Expanded(child: navigationShell),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
