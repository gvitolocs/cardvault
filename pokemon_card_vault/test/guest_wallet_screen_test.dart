import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// These imports exercise the app's real guest UI and route policy.
// ignore: avoid_relative_lib_imports
import '../lib/wallet/guest_wallet_screen.dart';
// ignore: avoid_relative_lib_imports
import '../lib/utils/account_route_policy.dart';

GoRouter _router({VoidCallback? onConnectWallet}) => GoRouter(
      initialLocation: '/wallet',
      redirect: (_, state) => requiresAccountForRoute(state.matchedLocation)
          ? '/auth?from=${Uri.encodeComponent(state.uri.toString())}'
          : null,
      routes: [
        GoRoute(
          path: '/wallet',
          builder: (_, __) => GuestWalletScreen(
            onConnectWallet: onConnectWallet ?? () {},
          ),
        ),
        GoRoute(
          path: '/auth',
          builder: (_, state) => Scaffold(
            body: Text('Login ${state.uri.queryParameters['from']}'),
          ),
        ),
        for (final path in ['/marketplace', '/cardscan', '/profile', '/swap'])
          GoRoute(
            path: path,
            builder: (_, __) => Scaffold(body: Text('$path page')),
          ),
      ],
    );

void main() {
  test('only the Wallet overview becomes public', () {
    expect(requiresAccountForRoute('/wallet'), isFalse);
    expect(requiresAccountForRoute('/marketplace'), isFalse);
    for (final path in [
      '/swap',
      '/profile',
      '/inventory',
      '/collection',
      '/nft',
      '/checkout',
      '/orders',
      '/marketplace/connect',
    ]) {
      expect(requiresAccountForRoute(path), isTrue, reason: path);
    }
  });

  for (final width in [320.0, 390.0, 1100.0]) {
    for (final textScale in [1.0, 1.5]) {
      testWidgets('guest Wallet fits $width with text scale $textScale',
          (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final router = _router();
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(
          theme: ThemeData.dark(useMaterial3: true),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/wallet');
        expect(find.text('0.00 PKN'), findsOneWidget);
        expect(find.text('No activity yet'), findsOneWidget);
        await tester.ensureVisible(find.text('Not signed in'));
        await tester.pumpAndSettle();
        expect(find.text('Not signed in'), findsOneWidget);
        await tester.ensureVisible(find.text('Connect wallet'));
        await tester.pumpAndSettle();
        expect(find.text('Not connected'), findsOneWidget);
        expect(find.text('Connect wallet').hitTestable(), findsOneWidget);
        expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            2);
        expect(find.text('Ricerca').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final action in ['Send', 'Receive', 'Withdraw', 'Top up', 'Exchange']) {
    testWidgets('$action requires login and preserves its destination',
        (tester) async {
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(action));
      await tester.pumpAndSettle();
      expect(find.text('Login ${action == 'Exchange' ? '/swap' : '/wallet'}'),
          findsOneWidget);
    });
  }

  testWidgets(
      'Sign in returns to Wallet and Connect wallet has its own handler',
      (tester) async {
    var connected = false;
    final router = _router(onConnectWallet: () => connected = true);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Connect wallet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect wallet'));
    expect(connected, isTrue);
    expect(router.routeInformationProvider.value.uri.path, '/wallet');
    await tester.ensureVisible(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Login /wallet'), findsOneWidget);
  });

  for (final destination
      in {'Ricerca': '/marketplace', 'Scanner': '/cardscan'}.entries) {
    testWidgets('guest Wallet can exit to ${destination.value}',
        (tester) async {
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text(destination.key));
      await tester.pumpAndSettle();
      expect(find.text('${destination.value} page'), findsOneWidget);
    });
  }
}
