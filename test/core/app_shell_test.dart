import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:createai_studio/core/widgets/app_shell.dart';

/// A minimal 2-branch shell router - enough to get a real
/// [StatefulNavigationShell] instance into [AppShell] without pulling in
/// every real screen/provider the full app router depends on.
GoRouter _testRouter() => GoRouter(
      initialLocation: '/a',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/a', builder: (context, state) => const Text('Branch A')),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/b', builder: (context, state) => const Text('Branch B')),
            ]),
          ],
        ),
      ],
    );

Future<void> _pumpAtWidth(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(child: MaterialApp.router(routerConfig: _testRouter())),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a bottom NavigationBar at phone (compact) width', (tester) async {
    await _pumpAtWidth(tester, 400);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('shows a collapsed NavigationRail at tablet (medium) width', (tester) async {
    await _pumpAtWidth(tester, 700);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);
  });

  testWidgets('shows an extended NavigationRail at desktop (expanded) width', (tester) async {
    await _pumpAtWidth(tester, 1200);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
  });
}
