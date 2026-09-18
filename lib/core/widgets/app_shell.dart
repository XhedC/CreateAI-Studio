import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_bottom_navigation.dart';
import 'mini_player.dart';
import 'offline_banner.dart';

/// Hosts the 5 bottom-nav tabs (Home, Create, History, Projects, Profile)
/// as a [StatefulShellRoute], preserving each tab's navigation stack and
/// scroll position when switching tabs.
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

  @override
  Widget build(BuildContext context) {
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
            onDestinationSelected: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
          ),
        ],
      ),
    );
  }
}
