import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokoin/screens/not_found_screen.dart';

void main() {
  testWidgets('unknown routes render Wobbuffet-inspired 404',
      (WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/missing-card-cave',
      errorBuilder: (context, state) => PokoinNotFoundScreen(
        location: state.uri.toString(),
      ),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: '/marketplace',
          builder: (context, state) => const Text('Marketplace'),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: router),
    );

    await tester.pumpAndSettle();

    expect(
      find.image(const AssetImage('assets/images/wobbuffet_404.png')),
      findsOneWidget,
    );
    expect(find.text('Wobba wobba... page not found'), findsOneWidget);
    expect(find.textContaining('/missing-card-cave'), findsOneWidget);
    expect(find.text('Back to marketplace'), findsOneWidget);

    await tester.tap(find.text('Back to marketplace'));
    await tester.pumpAndSettle();

    expect(find.text('Marketplace'), findsOneWidget);
  });
}
