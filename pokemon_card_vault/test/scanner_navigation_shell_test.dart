import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// The isolated harness imports the real app widgets, not copies.
// ignore: avoid_relative_lib_imports
import '../lib/widgets/marketplace_cart_navigation.dart';
// ignore: avoid_relative_lib_imports
import '../lib/widgets/scanner_navigation_shell.dart';
// ignore: avoid_relative_lib_imports
import '../lib/utils/account_route_policy.dart';

GoRouter _router({
  String initialLocation = '/cardscan',
  Widget body = const Center(child: Text('Camera preview')),
  bool signedIn = true,
}) =>
    GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/marketplace',
          builder: (_, __) => const Scaffold(body: Text('Marketplace page')),
        ),
        GoRoute(
          path: '/marketplace/search',
          builder: (_, __) => const Scaffold(body: Text('Search page')),
        ),
        GoRoute(
          path: '/cardscan',
          builder: (_, __) => ScannerNavigationShell(body: body),
        ),
        for (final path in ['/wallet', '/profile'])
          GoRoute(
            path: path,
            redirect: (_, __) => signedIn || !requiresAccountForRoute(path)
                ? null
                : '/auth?from=${Uri.encodeComponent(path)}',
            builder: (_, __) => Scaffold(body: Text('$path page')),
          ),
        GoRoute(
          path: '/auth',
          builder: (_, state) => Scaffold(
              body: Text('Login ${state.uri.queryParameters['from']}')),
        ),
      ],
    );

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('scanner links stay visible at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      for (final label in ['Ricerca', 'Wallet', 'Elenco', 'Profilo']) {
        expect(find.text(label).hitTestable(), findsOneWidget);
      }
      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          1);
      expect(
          find.byTooltip('Torna al Marketplace').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final labelAndPath in {
    'Ricerca': '/marketplace',
    'Wallet': '/wallet',
    'Profilo': '/profile',
  }.entries) {
    testWidgets('scanner opens ${labelAndPath.key}', (tester) async {
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text(labelAndPath.key));
      await tester.pumpAndSettle();
      expect(
          router.routeInformationProvider.value.uri.path, labelAndPath.value);
    });
  }

  for (final labelAndPath
      in {'Wallet': '/wallet', 'Profilo': '/profile'}.entries) {
    testWidgets('${labelAndPath.key} follows the account route policy',
        (tester) async {
      final router = _router(signedIn: false);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text(labelAndPath.key));
      await tester.pumpAndSettle();
      expect(
          find.text(labelAndPath.value == '/wallet'
              ? '/wallet page'
              : 'Login ${labelAndPath.value}'),
          findsOneWidget);
    });
  }

  for (final state in ['loading', 'camera error', 'model warmup']) {
    testWidgets('Marketplace exit works during $state', (tester) async {
      final router = _router(body: Center(child: Text(state)));
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Torna al Marketplace'));
      await tester.pumpAndSettle();
      expect(find.text('Marketplace page'), findsOneWidget);
    });
  }

  testWidgets('system back from directly opened scanner returns to Marketplace',
      (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Marketplace page'), findsOneWidget);
  });

  testWidgets('system back preserves the previous pushed route',
      (tester) async {
    final router = _router(initialLocation: '/profile');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    final scan = router.push<void>('/cardscan');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await scan;
    expect(find.text('/profile page'), findsOneWidget);
  });

  testWidgets('Elenco remains wired and leaving disposes the preview body',
      (tester) async {
    var disposed = false;
    final router =
        _router(body: _PreviewProbe(onDispose: () => disposed = true));
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    // Elenco uses the shared external-dashboard callback, not a scanner action.
    final bar = tester
        .widget<MarketplaceUtilityBar>(find.byType(MarketplaceUtilityBar));
    expect(bar.onListings, isNotNull);
    await tester.tap(find.text('Ricerca'));
    await tester.pumpAndSettle();
    expect(disposed, isTrue);
  });
}

class _PreviewProbe extends StatefulWidget {
  const _PreviewProbe({required this.onDispose});
  final VoidCallback onDispose;

  @override
  State<_PreviewProbe> createState() => _PreviewProbeState();
}

class _PreviewProbeState extends State<_PreviewProbe> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('Preview probe');
}
