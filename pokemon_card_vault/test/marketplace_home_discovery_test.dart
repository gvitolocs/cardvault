import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/models/pokemon_card.dart';
import 'package:pokoin/models/marketplace_expansion.dart';
import 'package:pokoin/widgets/marketplace_home_discovery.dart';

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

  testWidgets('utility bar exposes and invokes all four destinations',
      (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      bottomNavigationBar: MarketplaceUtilityBar(
        onSearch: () => tapped.add('search'),
        onScanner: () => tapped.add('scanner'),
        onListings: () => tapped.add('dashboard'),
        onProfile: () => tapped.add('profile'),
      ),
    )));
    for (final label in ['Ricerca', 'Scanner', 'Elenco', 'Profilo']) {
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(tapped, ['search', 'scanner', 'dashboard', 'profile']);
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
