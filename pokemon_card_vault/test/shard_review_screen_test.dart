import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokoin/models/app_user_profile.dart';
import 'package:pokoin/models/pokemon_card.dart';
import 'package:pokoin/providers/auth_provider.dart';
import 'package:pokoin/screens/earn_pkn_screen.dart';

GoRouter _router(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/earn',
        builder: (context, state) => const EarnPknScreen(),
      ),
      GoRoute(
        path: '/shard-review',
        builder: (context, state) => const ShardReviewScreen(),
      ),
      GoRoute(
        path: '/marketplace/connect',
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: '/marketplace',
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const SizedBox.shrink(),
      ),
    ],
  );
}

PokemonCard _card({
  required String id,
  required String name,
  required String set,
  required String number,
  String rarity = 'Card',
}) {
  return PokemonCard(
    id: id,
    name: name,
    imageUrl: 'https://pokoin.com/card-images/cards/$id.webp',
    previewImageUrl: 'https://pokoin.com/card-images/previews/$id.webp',
    rarity: rarity,
    type: 'Trading card',
    hp: 0,
    attacks: const [],
    price: 1000,
    description: 'Deck suggestion fixture',
    set: set,
    number: number,
    artist: '',
    stock: 0,
    rating: 0,
    reviewCount: 0,
    isFoil: false,
    isHolo: false,
    releaseDate: DateTime(2026),
    tags: [set, rarity],
    condition: 'NM',
    isGraded: false,
  );
}

void main() {
  Widget appForRoute(
    String initialLocation, {
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(routerConfig: _router(initialLocation)),
    );
  }

  test('Limitless deck parser imports cards and reports unknown lines', () {
    const deckList = '''
Pokémon: 18
3 Mega Kangaskhan ex MEG 104
this line is not a card

Trainer: 27
4 Crispin SCR 133

Energy: 15
8 Grass Energy MEE 1
''';

    final result = parseLimitlessDeckList(deckList);

    expect(result.cards, hasLength(3));
    expect(result.cards.first.quantity, 3);
    expect(result.cards.first.name, 'Mega Kangaskhan ex');
    expect(result.cards.first.setCode, 'MEG');
    expect(result.cards.first.collectorNumber, '104');
    expect(result.cards.first.category, 'Pokemon');
    expect(result.warnings, isNotEmpty);
    expect(result.warnings.first, contains('not imported'));
  });

  test('deck version suggestions prefer exact parsed card version', () {
    const parsed = ParsedDeckCard(
      quantity: 3,
      name: 'Dunsparce',
      setCode: 'JTG',
      collectorNumber: '120',
      category: 'Pokemon',
      rawLine: '3 Dunsparce JTG 120',
    );
    final ranked = rankDeckVersionSuggestionsForCard(parsed, [
      _card(
        id: '2',
        name: 'Dunsparce',
        set: 'Temporal Forces',
        number: '128',
        rarity: 'Common',
      ),
      _card(
        id: '1',
        name: 'Dunsparce',
        set: 'JTG',
        number: '120',
        rarity: 'Common',
      ),
      _card(
        id: '3',
        name: 'Dudunsparce',
        set: 'JTG',
        number: '121',
      ),
    ]);

    expect(ranked, hasLength(3));
    expect(ranked.first.card.id, '1');
    expect(ranked.first.label, 'Dunsparce (JTG 120)');
    expect(ranked.first.imageUrl, contains('/1.webp'));
  });

  test('deck version suggestions map Limitless set codes before fuzzy versions',
      () {
    const parsed = ParsedDeckCard(
      quantity: 4,
      name: 'Dreepy',
      setCode: 'TWM',
      collectorNumber: '128',
      category: 'Pokemon',
      rawLine: '4 Dreepy TWM 128',
    );

    final ranked = rankDeckVersionSuggestionsForCard(parsed, [
      _card(
        id: 'fs',
        name: 'Dreepy',
        set: 'Fusion Strike',
        number: '128/264',
        rarity: 'Common',
      ),
      _card(
        id: 'twm',
        name: 'Dreepy',
        set: 'Twilight Masquerade',
        number: '128/167',
        rarity: 'Common',
      ),
    ]);

    expect(ranked.first.card.id, 'twm');
    expect(ranked.first.label, 'Dreepy (Twilight Masquerade 128/167)');
  });

  testWidgets('Reserve tile opens standalone shard review route',
      (WidgetTester tester) async {
    await tester.pumpWidget(appForRoute('/earn'));
    await tester.pumpAndSettle();

    expect(find.byType(ShardReviewScreen), findsNothing);
    await tester.tap(find.text('Reserve').first);
    await tester.pumpAndSettle();

    expect(find.byType(ShardReviewScreen), findsOneWidget);
    expect(find.text('Request A PKN Shard Review'), findsWidgets);
  });

  testWidgets('Card list mode keeps deck textbox behind deck import',
      (WidgetTester tester) async {
    await tester.pumpWidget(appForRoute('/shard-review'));
    await tester.pumpAndSettle();

    expect(find.text('Card list'), findsOneWidget);
    expect(find.text('Deck shard'), findsOneWidget);
    expect(find.text('Deck import'), findsOneWidget);
    expect(find.text('Paste Limitless decklist'), findsNothing);

    await tester.ensureVisible(find.text('Deck import'));
    await tester.tap(find.text('Deck import'));
    await tester.pumpAndSettle();

    expect(find.text('Paste Limitless decklist'), findsOneWidget);
  });

  testWidgets('Deck shard imports deck cards and asks for selections',
      (WidgetTester tester) async {
    await tester.pumpWidget(appForRoute('/shard-review'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Deck shard'));
    await tester.tap(find.text('Deck shard'));
    await tester.pumpAndSettle();

    expect(find.text('Paste Limitless decklist'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Paste Limitless decklist'),
      'Pokemon: 18\n3 Mega Kangaskhan ex MEG 104\n'
      'Trainer: 27\n4 Crispin SCR 133\n'
      'Energy: 15\n8 Grass Energy MEE 1',
    );
    await tester.ensureVisible(find.text('Import decklist'));
    await tester.tap(find.text('Import decklist'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Imported 3 deck rows'), findsOneWidget);
    expect(find.textContaining('Mega Kangaskhan'), findsWidgets);
    expect(find.text('Version for Mega Kangaskhan ex'), findsOneWidget);
    expect(find.text('Language'), findsWidgets);
    expect(find.text('Condition'), findsWidgets);
  });

  testWidgets('prefills email when signed-in profile email loads',
      (WidgetTester tester) async {
    final profileController = StreamController<AppUserProfile?>();
    addTearDown(profileController.close);

    await tester.pumpWidget(
      appForRoute(
        '/shard-review',
        overrides: [
          userProfileProvider.overrideWith((ref) => profileController.stream),
        ],
      ),
    );
    await tester.pump();

    final emailField = find.widgetWithText(TextFormField, 'Email');
    expect(tester.widget<TextFormField>(emailField).controller?.text, isEmpty);

    profileController.add(
      AppUserProfile(
        uid: 'google-user',
        email: 'google.user@example.com',
        displayName: 'Google User',
        username: 'googleuser',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TextFormField>(emailField).controller?.text,
      'google.user@example.com',
    );
  });

  testWidgets('does not overwrite manually typed email when profile loads',
      (WidgetTester tester) async {
    final profileController = StreamController<AppUserProfile?>();
    addTearDown(profileController.close);

    await tester.pumpWidget(
      appForRoute(
        '/shard-review',
        overrides: [
          userProfileProvider.overrideWith((ref) => profileController.stream),
        ],
      ),
    );
    await tester.pump();

    final emailField = find.widgetWithText(TextFormField, 'Email');
    await tester.enterText(emailField, 'custom@example.com');
    await tester.pump();

    profileController.add(
      AppUserProfile(
        uid: 'google-user',
        email: 'google.user@example.com',
        displayName: 'Google User',
        username: 'googleuser',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TextFormField>(emailField).controller?.text,
      'custom@example.com',
    );
  });
}
