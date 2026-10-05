import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// These imports also exercise the real source in the Flutter-only harness.
// ignore: avoid_relative_lib_imports
import '../lib/models/pokemon_card.dart';
// ignore: avoid_relative_lib_imports
import '../lib/models/marketplace_expansion.dart';
// ignore: avoid_relative_lib_imports
import '../lib/widgets/marketplace_home_discovery.dart';

MarketplaceExpansion expansion(
  String name, {
  int count = 100,
  int? id,
  DateTime? date,
}) =>
    MarketplaceExpansion(
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      cardCount: count,
      symbolImageUrl: '',
      logoImageUrl: '',
      defaultSymbolUrl: '',
      expansionId: id,
      releaseDate: date,
    );

PokemonCard card(String id, {double price = 1}) => PokemonCard(
      id: id,
      name: 'Card $id',
      imageUrl: '',
      rarity: 'Rare',
      type: 'Card',
      hp: 0,
      attacks: const [],
      price: price,
      description: '',
      set: 'Test',
      number: '1',
      artist: '',
      stock: 1,
      rating: 0,
      reviewCount: 0,
      isFoil: false,
      isHolo: false,
      releaseDate: DateTime(2026),
      tags: const [],
      condition: 'NM',
      isGraded: false,
    );

void main() {
  test('mobile discovery retains only backend-selected cards', () {
    final cards = List.generate(1000, (index) => card('$index'));
    final selected =
        marketplaceDiscoverySourceCards(cards, ['12', '24', 'missing', '12']);
    expect(selected.map((card) => card.id), ['12', '24']);
    expect(cards.length, 1000);
    expect(marketplaceDiscoverySourceCards(cards, const []), isEmpty);
  });

  test('bounded discovery retains backend ranking and new-arrival set hints',
      () {
    final cards = [card('a'), card('b'), card('c')];
    final selected = marketplaceDiscoverySourceCards(cards, ['b', 'c']);
    expect(
        marketplaceBestSellers(selected, ['c', 'missing', 'b'])
            .map((card) => card.id),
        ['c', 'b']);
    expect(
        marketplaceCardsForRankedIds(selected, ['b', 'b', 'missing'])
            .map((card) => card.set),
        ['Test']);
  });

  test('ranked discovery caps visible cards without changing catalog records',
      () {
    final cards = List.generate(100, (index) => card('$index'));
    final ids = List.generate(100, (index) => '${99 - index}');
    final ranked = marketplaceCardsForRankedIds(cards, ids);
    expect(ranked.map((card) => card.id),
        List.generate(12, (index) => '${99 - index}'));
    expect(cards.first.id, '0');
  });

  test('legacy expansions use catalog order rather than alphabetical order',
      () {
    final result = recentHomeExpansions(
      [expansion('Alpha old'), expansion('Zeta new')],
      catalogOrder: {'Alpha old': 1, 'Zeta new': 2},
    );
    expect(result.map((set) => set.name), ['Zeta new', 'Alpha old']);
    expect(result.every((set) => set.releaseDate == null), isTrue);
  });

  test('live new-arrival hints rank sets absent from the bundled registry', () {
    final result = recentHomeExpansions(
      [expansion('Known'), expansion('Just added')],
      catalogOrder: {'Known': 100},
      newArrivalSets: ['Just added'],
    );
    expect(result.first.name, 'Just added');
  });

  test('real release dates sort descending when provided', () {
    final result = recentHomeExpansions([
      expansion('Old', id: 500, date: DateTime(2020)),
      expansion('New', id: 1, date: DateTime(2026)),
    ]);
    expect(result.first.name, 'New');
  });

  test('blank, empty and duplicate expansions do not fill the rail', () {
    final result = recentHomeExpansions([
      expansion(''),
      expansion('Empty', count: 0),
      expansion('Known'),
      expansion('Known'),
      expansion('Other'),
    ], limit: 1);
    expect(result, hasLength(1));
    expect(recentHomeExpansions([expansion('Known')], limit: 0), isEmpty);
  });

  test('best sellers keep backend ranking without substituting expensive cards',
      () {
    final cards = [card('cheap'), card('expensive', price: 500)];
    expect(
        marketplaceBestSellers(
                cards, ['cheap', 'missing', 'cheap', 'expensive'])
            .map((value) => value.id),
        ['cheap', 'expensive']);
    expect(marketplaceBestSellers(cards, const []), isEmpty);
  });

  test(
      'expansion metadata parses optional dates and keeps legacy responses valid',
      () {
    final legacy = MarketplaceExpansion.fromJson({'name': 'Legacy'});
    expect(legacy.releaseDate, isNull);
    final enriched = MarketplaceExpansion.fromJson({
      'name': 'New',
      'releaseDate': '2026-09-01',
      'expansion_id': '123',
    });
    expect(enriched.releaseDate, DateTime(2026, 9, 1));
    expect(enriched.expansionId, 123);
    expect(
        MarketplaceExpansion.fromJson({'releaseDate': 'unknown'}).releaseDate,
        isNull);
  });

  testWidgets('utility bar exposes and invokes all five destinations',
      (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      bottomNavigationBar: MarketplaceUtilityBar(
        onSearch: () => tapped.add('search'),
        onScanner: () => tapped.add('scanner'),
        onWallet: () => tapped.add('wallet'),
        onListings: () => tapped.add('dashboard'),
        onProfile: () => tapped.add('profile'),
      ),
    )));
    for (final label in ['Ricerca', 'Scanner', 'Wallet', 'Elenco', 'Profilo']) {
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(tapped, ['search', 'scanner', 'wallet', 'dashboard', 'profile']);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 1200.0]) {
    testWidgets('expansion slider scrolls and selects a set at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      MarketplaceExpansion? selected;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: RecentExpansionsCarousel(
          expansions: List.generate(8, (index) => expansion('Set $index')),
          onSelected: (set) => selected = set,
        ),
      )));
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('recent-expansions-slider'));
      expect(tester.widget<ListView>(slider).scrollDirection, Axis.horizontal);
      await tester.tap(find.text('Set 0'));
      expect(selected?.name, 'Set 0');
      await tester.tap(find.byTooltip('Espansioni successive'));
      await tester.pumpAndSettle();
      expect(find.text('Set 0').hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty expansion response exposes a retry action',
      (tester) async {
    var retried = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: RecentExpansionsCarousel(
        expansions: const [],
        onSelected: (_) {},
        onRetry: () => retried = true,
      ),
    )));
    await tester.tap(find.text('Riprova'));
    expect(retried, isTrue);
    expect(tester.takeException(), isNull);
  });
}
