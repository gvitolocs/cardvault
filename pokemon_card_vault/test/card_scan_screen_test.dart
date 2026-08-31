import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokoin/screens/card_scan_screen.dart';

void main() {
  testWidgets('card scan screen shows Scan and Library', (tester) async {
    final router = GoRouter(
      initialLocation: '/cardscan',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Text('home'),
        ),
        GoRoute(
          path: '/cardscan',
          builder: (context, state) => const CardScanScreen(),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Card scan'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Hold the card in frame, then Scan.'), findsOneWidget);
  });
}
