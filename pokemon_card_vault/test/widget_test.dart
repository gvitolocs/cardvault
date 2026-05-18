// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

import 'package:pokoin/main.dart';
import 'package:pokoin/models/pokemon_card.dart';
import 'package:pokoin/providers/card_provider.dart';
import 'package:pokoin/screens/home_screen.dart';

PokemonCard _card(int index) {
  return PokemonCard(
    id: '$index',
    name: 'Card $index',
    imageUrl: 'https://cdn.pokoin.com/cards/$index.png',
    rarity: index.isEven ? 'Rare Holo' : 'Card',
    type: 'Trading card',
    hp: 0,
    attacks: const [],
    price: (1000 + index).toDouble(),
    description: 'Test card',
    set: 'Test Set',
    number: '$index/20',
    artist: '',
    stock: 0,
    rating: 0,
    reviewCount: 0,
    isFoil: index.isEven,
    isHolo: index.isEven,
    releaseDate: DateTime(2026),
    tags: const ['Test Set'],
    condition: 'NM',
    isGraded: false,
  );
}

void main() {
  setUpAll(() {
    final hiveDir = Directory.systemTemp.createTempSync('pokoin_widget_test_');
    Hive.init(hiveDir.path);
  });

  testWidgets('Pokoin app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: PokoinApp(),
      ),
    );

    // Verify that the app loads
    expect(find.text('Pokoin'), findsWidgets);
  });

  testWidgets(
      'Marketplace browse renders first 12 cards instead of full catalog',
      (WidgetTester tester) async {
    final cards = List.generate(20, (index) => _card(index + 1));
    final router = GoRouter(
      initialLocation: '/marketplace',
      routes: [
        GoRoute(
          path: '/marketplace',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/card/:id',
          builder: (context, state) => const SizedBox.shrink(),
        ),
        GoRoute(
            path: '/', builder: (context, state) => const SizedBox.shrink()),
        GoRoute(
            path: '/scan',
            builder: (context, state) => const SizedBox.shrink()),
        GoRoute(
            path: '/wallet',
            builder: (context, state) => const SizedBox.shrink()),
        GoRoute(
            path: '/cart',
            builder: (context, state) => const SizedBox.shrink()),
        GoRoute(
            path: '/marketplace/signal',
            builder: (context, state) => const SizedBox.shrink()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    container.read(cardProvider.notifier).state =
        CardState(cards: cards, filteredCards: cards);
    await tester.pumpAndSettle();

    expect(find.text('Card spotlight'), findsOneWidget);
    expect(find.textContaining('results'), findsNothing);
    expect(find.text('Card 1 #1/20'), findsWidgets);
    expect(find.text('View'), findsWidgets);
    expect(find.text('Add'), findsNothing);
  });
}
