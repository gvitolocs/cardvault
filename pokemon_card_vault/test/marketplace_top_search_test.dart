import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:pokoin/models/pokemon_card.dart';
import 'package:pokoin/providers/card_listing_provider.dart';
import 'package:pokoin/providers/card_provider.dart';
import 'package:pokoin/providers/recent_views_provider.dart';
import 'package:pokoin/screens/home_screen.dart';
import 'package:pokoin/services/card_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

PokemonCard _previewCard({
  required String id,
  required String name,
  String rarity = 'Card',
  String itemKind = 'single',
  String productType = 'card',
}) {
  return PokemonCard(
    id: id,
    name: name,
    imageUrl: '',
    rarity: rarity,
    type: productType == 'card'
        ? 'Card'
        : marketplaceProductTypeLabelForTest(productType),
    hp: 0,
    attacks: const [],
    price: 0,
    description: 'Lightweight preview',
    set: 'Test Set',
    number: '1/100',
    artist: '',
    stock: 0,
    rating: 0,
    reviewCount: 0,
    isFoil: false,
    isHolo: false,
    releaseDate: DateTime(2026),
    tags: ['Test Set', rarity, itemKind, productType],
    condition: 'NM',
    isGraded: false,
    itemKind: itemKind,
    productType: productType,
  );
}

Finder _searchPreviewSkeletonRows() {
  return find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_SearchPreviewSkeletonRow',
  );
}

void main() {
  setUpAll(() {
    final hiveDir =
        Directory.systemTemp.createTempSync('pokoin_marketplace_test_');
    Hive.init(hiveDir.path);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('exact one-result card query auto-open candidate is detected', () {
    final magikarp = _previewCard(
      id: '316389',
      name: 'Magikarp',
    ).copyWith(
      number: '203/193',
      rarity: 'Illustration Rare',
      canonicalPath:
          '/marketplace/en/cards/632778/illustration-rare-magikarp-203-193-paldea-evolved',
    );

    final match = exactSearchAutoOpenCardForTest(
      query: 'Magikarp 203/193',
      results: [magikarp],
    );

    expect(match?.id, '316389');
  });

  test('recent marketplace cards use cheapest cache availability', () {
    final recentCards = marketplaceRecentCardsForTest(
      recentViews: [
        RecentCardView(
          cardId: '349805',
          name: 'Bulbasaur',
          expansion: 'Mega Evolution',
          number: '001/132',
          imageUrl: 'https://cdn.pokoin.com/349805_bulbasaur.jpg',
          previewImageUrl: 'https://cdn.pokoin.com/previews/349805.jpg',
          homepageImageUrl: 'https://cdn.pokoin.com/home/349805.jpg',
          viewedAt: DateTime(2026),
        ),
      ],
      cheapestPricesByCardId: {
        '349805': const MarketplaceCheapestPrice(
          cardId: '349805',
          pricePkn: 224,
          available: true,
          listingCount: 191,
          listedQuantity: 1129,
        ),
      },
    );

    expect(recentCards.single.id, '349805');
    expect(recentCards.single.price, 224);
    expect(recentCards.single.stock, 1129);
    expect(recentCards.single.hasCardTraderListing, isTrue);
    expect(recentCards.single.cardtraderEligibleListingCount, 191);
    expect(recentCards.single.isMarketAvailable, isTrue);
  });

  test('recent marketplace cards omit unavailable stale cards', () {
    final recentCards = marketplaceRecentCardsForTest(
      recentViews: [
        RecentCardView(
          cardId: '391257',
          name: 'Teal Mask Ogerpon ex',
          expansion: 'CSVNC: Land of Kitakami Special Pack',
          number: '043/040',
          imageUrl: 'https://cdn.pokoin.com/391257_ogerpon.jpg',
          previewImageUrl: 'https://cdn.pokoin.com/previews/391257.jpg',
          homepageImageUrl: 'https://cdn.pokoin.com/home/391257.jpg',
          viewedAt: DateTime(2026),
        ),
      ],
      cards: [
        _previewCard(
          id: '391257',
          name: 'Teal Mask Ogerpon ex',
        ).copyWith(
          set: 'CSVNC: Land of Kitakami Special Pack',
          price: 0,
          stock: 0,
          hasCardTraderListing: false,
          cardtraderEligibleListingCount: 0,
        ),
      ],
    );

    expect(recentCards, isEmpty);
  });

  test('recent marketplace cards apply cheapest cache to catalog card', () {
    final catalogCard = _previewCard(
      id: '241674',
      name: 'Drowzee',
    ).copyWith(
      set: 'Scarlet & Violet',
      number: '210/198',
      stock: 0,
      price: 0,
    );

    final recentCards = marketplaceRecentCardsForTest(
      recentViews: [
        RecentCardView(
          cardId: '241674',
          name: 'Drowzee',
          expansion: 'Scarlet & Violet',
          number: '210/198',
          imageUrl: 'https://cdn.pokoin.com/241674_drowzee.jpg',
          previewImageUrl: 'https://cdn.pokoin.com/previews/241674.jpg',
          homepageImageUrl: 'https://cdn.pokoin.com/home/241674.jpg',
          viewedAt: DateTime(2026),
        ),
      ],
      cards: [catalogCard],
      cheapestPricesByCardId: {
        '241674': const MarketplaceCheapestPrice(
          cardId: '241674',
          pricePkn: 4244,
          available: true,
          listingCount: 56,
          listedQuantity: 73,
          canonicalPath:
              '/marketplace/en/cards/483348/card-drowzee-210-198-scarlet-violet',
          publicNumber: '483348',
        ),
      },
    );

    expect(recentCards.single.id, '241674');
    expect(recentCards.single.price, 4244);
    expect(recentCards.single.stock, 73);
    expect(recentCards.single.hasCardTraderListing, isTrue);
    expect(recentCards.single.cardtraderEligibleListingCount, 56);
    expect(recentCards.single.isMarketAvailable, isTrue);
  });

  test('homepage sections filter cached unavailable cards', () {
    final available = _previewCard(
      id: '316600',
      name: 'Leafeon',
    ).copyWith(
      price: 780,
      stock: 3,
      hasCardTraderListing: true,
      cardtraderEligibleListingCount: 1,
    );
    final unavailable = _previewCard(
      id: '391257',
      name: 'Teal Mask Ogerpon ex',
    ).copyWith(
      price: 0,
      stock: 0,
      hasCardTraderListing: false,
      cardtraderEligibleListingCount: 0,
    );

    final sections = marketplaceHomeSectionCardsForTest(
      cards: [available, unavailable],
      cachedSections: const MarketplaceHomeSections(
        recentlySeenIds: [],
        bestSellerIds: ['391257', '316600'],
        featuredIds: ['391257'],
      ),
    );

    expect(sections['bestSellers']!.map((card) => card.id), ['316600']);
    expect(sections['featured']!.map((card) => card.id), ['316600']);
    expect(
      sections.values.expand((cards) => cards),
      everyElement(predicate<PokemonCard>((card) => card.isMarketAvailable)),
    );
  });

  test(
      'recent marketplace cards resolve public route id to internal cheapest id',
      () {
    final catalogCard = _previewCard(
      id: '241674',
      name: 'Drowzee',
    ).copyWith(
      set: 'Scarlet & Violet',
      number: '210/198',
      stock: 0,
      price: 0,
    );

    final recentCards = marketplaceRecentCardsForTest(
      recentViews: [
        RecentCardView(
          cardId: '483348',
          name: 'Drowzee',
          expansion: 'Scarlet & Violet',
          number: '210/198',
          imageUrl: 'https://cdn.pokoin.com/241674_drowzee.jpg',
          previewImageUrl: 'https://cdn.pokoin.com/previews/241674.jpg',
          homepageImageUrl: 'https://cdn.pokoin.com/home/241674.jpg',
          viewedAt: DateTime(2026),
        ),
      ],
      cards: [catalogCard],
      cheapestPricesByCardId: {
        '241674': const MarketplaceCheapestPrice(
          cardId: '241674',
          pricePkn: 4244,
          available: true,
          listingCount: 56,
          listedQuantity: 73,
          canonicalPath:
              '/marketplace/en/cards/483348/card-drowzee-210-198-scarlet-violet',
          publicNumber: '483348',
        ),
      },
    );

    expect(recentCards.single.id, '241674');
    expect(recentCards.single.price, 4244);
    expect(recentCards.single.stock, 73);
    expect(recentCards.single.hasCardTraderListing, isTrue);
    expect(recentCards.single.cardtraderEligibleListingCount, 56);
    expect(recentCards.single.isMarketAvailable, isTrue);
  });

  test('recent Morelull with stale public route id hydrates cheapest price',
      () {
    final recentCards = marketplaceRecentCardsForTest(
      recentViews: [
        RecentCardView(
          cardId: '612154',
          name: 'Morelull',
          expansion: 'Surging Sparks',
          number: '008/191',
          imageUrl: 'https://cdn.pokoin.com/306077_morelull.jpg',
          previewImageUrl: 'https://cdn.pokoin.com/previews/306077.jpg',
          homepageImageUrl: 'https://cdn.pokoin.com/home/306077.jpg',
          viewedAt: DateTime(2026),
          canonicalPath:
              '/marketplace/en/cards/612154/card-morelull-008-191-surging-sparks',
        ),
      ],
      cheapestPricesByCardId: {
        '306077': const MarketplaceCheapestPrice(
          cardId: '306077',
          pricePkn: 222,
          available: true,
          listingCount: 9,
          listedQuantity: 0,
          canonicalPath:
              '/marketplace/en/cards/612154/card-morelull-008-191-surging-sparks',
          publicNumber: '612154',
        ),
      },
    );

    expect(recentCards.single.id, '306077');
    expect(recentCards.single.price, 222);
    expect(recentCards.single.stock, 0);
    expect(recentCards.single.hasCardTraderListing, isTrue);
    expect(recentCards.single.cardtraderEligibleListingCount, 9);
    expect(recentCards.single.isMarketAvailable, isTrue);
  });

  test('recent stale card matches cheapest by normalized name set number', () {
    final recentCards = marketplaceRecentCardsForTest(
      recentViews: [
        RecentCardView(
          cardId: 'stale-browser-id',
          name: 'Drowzee',
          expansion: 'Scarlet & Violet',
          number: '210/198',
          imageUrl: 'https://cdn.pokoin.com/241674_drowzee.jpg',
          previewImageUrl: 'https://cdn.pokoin.com/previews/241674.jpg',
          homepageImageUrl: 'https://cdn.pokoin.com/home/241674.jpg',
          viewedAt: DateTime(2026),
        ),
      ],
      cheapestPricesByCardId: {
        'structured:drowzee|scarlet violet|210/198':
            const MarketplaceCheapestPrice(
          cardId: '241674',
          pricePkn: 4244,
          available: true,
          listingCount: 56,
          listedQuantity: 73,
          canonicalPath:
              '/marketplace/en/cards/483348/card-drowzee-210-198-scarlet-violet',
          publicNumber: '483348',
          name: 'Drowzee',
          setName: 'Scarlet & Violet',
          number: '210/198',
        ),
      },
    );

    expect(recentCards.single.id, '241674');
    expect(recentCards.single.price, 4244);
    expect(recentCards.single.stock, 73);
    expect(recentCards.single.hasCardTraderListing, isTrue);
    expect(recentCards.single.isMarketAvailable, isTrue);
  });

  test('recent card uses persisted cheapest price on first paint', () {
    final recentCards = marketplaceRecentCardsForTest(
      recentViews: [
        RecentCardView(
          cardId: '241674',
          name: 'Drowzee',
          expansion: 'Scarlet & Violet',
          number: '210/198',
          imageUrl: 'https://cdn.pokoin.com/241674_drowzee.jpg',
          previewImageUrl: 'https://cdn.pokoin.com/previews/241674.jpg',
          homepageImageUrl: 'https://cdn.pokoin.com/home/241674.jpg',
          viewedAt: DateTime(2026),
          canonicalPath:
              '/marketplace/en/cards/483348/card-drowzee-210-198-scarlet-violet',
          publicNumber: '483348',
          pricePkn: 4244,
          available: true,
          listingCount: 56,
          listedQuantity: 0,
          priceSource: 'cheapest_homepage_cache_blueprint',
        ),
      ],
    );

    expect(recentCards.single.id, '241674');
    expect(recentCards.single.price, 4244);
    expect(recentCards.single.stock, 0);
    expect(recentCards.single.hasCardTraderListing, isTrue);
    expect(recentCards.single.cardtraderEligibleListingCount, 56);
    expect(recentCards.single.isMarketAvailable, isTrue);
  });

  test('recent cheapest hydration updates stale persisted price', () {
    final hydrated = hydrateRecentViewsWithCheapestPricesForTest(
      [
        RecentCardView(
          cardId: '306077',
          name: 'Morelull',
          expansion: 'Surging Sparks',
          number: '008/191',
          imageUrl: 'https://cdn.pokoin.com/306077_morelull.jpg',
          previewImageUrl: 'https://cdn.pokoin.com/previews/306077.jpg',
          homepageImageUrl: 'https://cdn.pokoin.com/home/306077.jpg',
          viewedAt: DateTime(2026),
          canonicalPath:
              '/marketplace/en/cards/612154/card-morelull-008-191-surging-sparks',
          publicNumber: '612154',
          pricePkn: 199,
          available: true,
          listingCount: 2,
          listedQuantity: 0,
          priceSource: 'cached',
        ),
      ],
      {
        '306077': const MarketplaceCheapestPrice(
          cardId: '306077',
          pricePkn: 222,
          available: true,
          listingCount: 9,
          listedQuantity: 3,
          canonicalPath:
              '/marketplace/en/cards/612154/card-morelull-008-191-surging-sparks',
          publicNumber: '612154',
          source: 'cheapest_homepage_cache_blueprint',
        ),
      },
    );

    expect(hydrated.single.cardId, '306077');
    expect(hydrated.single.pricePkn, 222);
    expect(hydrated.single.available, isTrue);
    expect(hydrated.single.listingCount, 9);
    expect(hydrated.single.listedQuantity, 3);
    expect(hydrated.single.priceSource, 'cheapest_homepage_cache_blueprint');
  });

  test('broad one-result card query does not auto-open', () {
    final magikarp = _previewCard(
      id: '316389',
      name: 'Magikarp',
    ).copyWith(number: '203/193');

    final match = exactSearchAutoOpenCardForTest(
      query: 'Magikarp',
      results: [magikarp],
    );

    expect(match, isNull);
  });

  test('marketplace product facet counts singles and product categories', () {
    final cards = [
      _previewCard(id: '1', name: 'Pikachu'),
      _previewCard(
        id: '2',
        name: '151 Booster',
        itemKind: 'product',
        productType: 'booster_pack',
      ),
      _previewCard(
        id: '3',
        name: '151 Booster Box',
        itemKind: 'product',
        productType: 'booster_box',
      ),
      _previewCard(
        id: '4',
        name: 'Surging Sparks Booster',
        itemKind: 'product',
        productType: 'booster_pack',
      ),
    ];

    expect(marketplaceProductFacetCountsForTest(cards), {
      'card': 1,
      'booster_box': 1,
      'booster_pack': 2,
    });
    expect(marketplaceProductTypeTitleForTest('card'), 'Graded');
    expect(marketplaceProductTypeLabelForTest('booster_pack'), 'Boosters');
  });

  test('marketplace product filter composes with expansion and rarity', () {
    final cards = [
      _previewCard(id: '1', name: 'Pikachu').copyWith(
        set: '151',
        rarity: 'Rare',
      ),
      _previewCard(
        id: '2',
        name: '151 Booster',
        itemKind: 'product',
        productType: 'booster_pack',
      ).copyWith(set: '151', rarity: 'Booster pack'),
      _previewCard(
        id: '3',
        name: 'Paldea Booster',
        itemKind: 'product',
        productType: 'booster_pack',
      ).copyWith(set: 'Paldea Evolved', rarity: 'Booster pack'),
    ];

    final filtered = applyMarketplaceSearchFiltersForTest(
      cards: cards,
      selectedProductType: 'booster_pack',
      selectedExpansion: '151',
    );

    expect(filtered.map((card) => card.id), ['2']);
  });

  testWidgets('marketplace direct load shows skeleton shell immediately',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/marketplace',
      routes: [
        GoRoute(
          path: '/marketplace',
          builder: (context, state) => const HomeScreen(),
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
        overrides: [
          cardProvider.overrideWith(
            (ref) => CardNotifier(
              cardService: _NeverLoadingCardService(),
              autoLoad: false,
            ),
          ),
          activeCardListingsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();

    expect(find.text('Recently seen'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -360));
    await tester.pump();
    expect(find.text('Best sellers'), findsOneWidget);
    expect(find.text('Featured'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('mobile marketplace sections stack three cards with see more',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cards = [
      for (var index = 1; index <= 4; index++)
        _previewCard(
          id: 'best-$index',
          name: 'Best Seller Card $index',
          rarity: 'Card',
        ).copyWith(price: (1000 - index).toDouble(), stock: 3),
      for (var index = 1; index <= 4; index++)
        _previewCard(
          id: 'featured-$index',
          name: 'Featured Card $index',
          rarity: 'Rare Holo',
        ).copyWith(price: (100 - index).toDouble(), stock: 3),
    ];

    final router = GoRouter(
      initialLocation: '/marketplace',
      routes: [
        GoRoute(
          path: '/marketplace',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/marketplace/search',
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
        overrides: [
          cardProvider.overrideWith(
            (ref) => CardNotifier(
              cardService: _CachedHomeCardService(cards),
            ),
          ),
          activeCardListingsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Best sellers'), findsOneWidget);
    expect(find.textContaining('Best Seller Card 1'), findsOneWidget);
    expect(find.textContaining('Best Seller Card 2'), findsOneWidget);
    expect(find.textContaining('Best Seller Card 3'), findsOneWidget);
    expect(find.textContaining('Best Seller Card 4'), findsNothing);
    expect(find.text('See more Best sellers'), findsOneWidget);

    final horizontalLists = tester
        .widgetList<ListView>(find.byType(ListView))
        .where((widget) => widget.scrollDirection == Axis.horizontal);
    expect(horizontalLists, isEmpty);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -780));
    await tester.pump();

    expect(find.text('Featured'), findsOneWidget);
    expect(find.textContaining('Featured Card 1'), findsOneWidget);
    expect(find.textContaining('Featured Card 2'), findsOneWidget);
    expect(find.textContaining('Featured Card 3'), findsOneWidget);
    expect(find.textContaining('Featured Card 4'), findsNothing);
    expect(find.text('See more Featured'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('compact empty search tap opens hot preview loading overlay',
      (WidgetTester tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var emptyFocusCount = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(760, 844)),
            child: Center(
              child: SizedBox(
                width: 520,
                child: MarketplaceTopSearch(
                  controller: controller,
                  focusNode: focusNode,
                  query: '',
                  isSearching: true,
                  previews: const [],
                  hintText: 'Search cards, sets, products...',
                  onEmptyFocus: () => emptyFocusCount++,
                  onChanged: (_) {},
                  onSelected: (_) {},
                  onShowAll: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(emptyFocusCount, 1);
    expect(find.text('Loading hot cards...'), findsOneWidget);
  });

  testWidgets('typed quick loading renders twenty skeleton rows',
      (WidgetTester tester) async {
    final controller = TextEditingController(text: 'pikachu g');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(760, 844)),
            child: Center(
              child: SizedBox(
                width: 520,
                child: MarketplaceTopSearch(
                  controller: controller,
                  focusNode: focusNode,
                  query: 'pikachu g',
                  isSearching: true,
                  previews: const [],
                  hintText: 'Search cards, sets, products...',
                  onChanged: (_) {},
                  onSelected: (_) {},
                  onShowAll: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(_searchPreviewSkeletonRows(), findsNWidgets(20));
    expect(find.text('Show all'), findsNothing);
    expect(find.text('No quick matches yet. Use Show all for full search.'),
        findsNothing);
    expect(find.textContaining('No remote quick results'), findsNothing);
  });

  testWidgets('completed typed empty preview does not keep skeletons',
      (WidgetTester tester) async {
    final controller = TextEditingController(text: 'mega dark');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(760, 844)),
            child: Center(
              child: SizedBox(
                width: 520,
                child: MarketplaceTopSearch(
                  controller: controller,
                  focusNode: focusNode,
                  query: 'mega dark',
                  isSearching: false,
                  previews: const [],
                  hintText: 'Search cards, sets, products...',
                  onChanged: (_) {},
                  onSelected: (_) {},
                  onShowAll: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(_searchPreviewSkeletonRows(), findsNothing);
    expect(find.text('No quick matches yet.'), findsOneWidget);
  });

  testWidgets('typed fallback preview rows render instead of skeletons',
      (WidgetTester tester) async {
    final controller = TextEditingController(text: 'pikachu');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(760, 844)),
            child: Center(
              child: SizedBox(
                width: 520,
                child: MarketplaceTopSearch(
                  controller: controller,
                  focusNode: focusNode,
                  query: 'pikachu',
                  isSearching: true,
                  previews: [_previewCard(id: '1', name: 'Pikachu')],
                  hintText: 'Search cards, sets, products...',
                  onChanged: (_) {},
                  onSelected: (_) {},
                  onShowAll: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('Pikachu'),
      ),
      findsWidgets,
    );
    expect(_searchPreviewSkeletonRows(), findsNothing);
  });

  testWidgets('ghost completion renders and Tab accepts it',
      (WidgetTester tester) async {
    final controller = TextEditingController(text: 'mewt');
    final focusNode = FocusNode();
    var accepted = '';
    var changed = '';
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(900, 844)),
            child: Center(
              child: SizedBox(
                width: 520,
                child: MarketplaceTopSearch(
                  controller: controller,
                  focusNode: focusNode,
                  query: 'mewt',
                  isSearching: false,
                  previews: const [],
                  completionText: 'Mewtwo',
                  hintText: 'Search cards, sets, products...',
                  onChanged: (value) => changed = value,
                  onSelected: (_) {},
                  onShowAll: (_) {},
                  onAcceptCompletion: (value) => accepted = value,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(find.textContaining('wo'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(accepted, 'mewt');
    expect(changed, 'Mewtwo');
    expect(controller.text, 'Mewtwo');
    expect(controller.selection.baseOffset, 'Mewtwo'.length);
  });

  testWidgets('mobile tap accepts ghost completion',
      (WidgetTester tester) async {
    final controller = TextEditingController(text: 'm');
    final focusNode = FocusNode();
    var accepted = '';
    var changed = '';
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Center(
              child: SizedBox(
                width: 340,
                child: MarketplaceTopSearch(
                  controller: controller,
                  focusNode: focusNode,
                  query: 'm',
                  isSearching: false,
                  previews: const [],
                  completionText: 'Mew',
                  hintText: 'Search cards, sets, products...',
                  onChanged: (value) => changed = value,
                  onSelected: (_) {},
                  onShowAll: (_) {},
                  onAcceptCompletion: (value) => accepted = value,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('ew'), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(accepted, 'm');
    expect(changed, 'Mew');
    expect(controller.text, 'Mew');
    expect(controller.selection.baseOffset, 'Mew'.length);
  });

  testWidgets('two-token ghost completion renders suffix and Tab accepts it',
      (WidgetTester tester) async {
    final controller = TextEditingController(text: 'tapu l');
    final focusNode = FocusNode();
    var accepted = '';
    var changed = '';
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(900, 844)),
            child: Center(
              child: SizedBox(
                width: 520,
                child: MarketplaceTopSearch(
                  controller: controller,
                  focusNode: focusNode,
                  query: 'tapu l',
                  isSearching: false,
                  previews: const [],
                  completionText: 'Tapu Lele',
                  hintText: 'Search cards, sets, products...',
                  onChanged: (value) => changed = value,
                  onSelected: (_) {},
                  onShowAll: (_) {},
                  onAcceptCompletion: (value) => accepted = value,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(find.textContaining('ele'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(accepted, 'tapu l');
    expect(changed, 'Tapu Lele');
    expect(controller.text, 'Tapu Lele');
    expect(controller.text, isNot('tapu l Lele'));
    expect(controller.selection.baseOffset, 'Tapu Lele'.length);
  });

  testWidgets('single token ghost completion accepts token not card variant',
      (WidgetTester tester) async {
    final controller = TextEditingController(text: 'm');
    final focusNode = FocusNode();
    var accepted = '';
    var changed = '';
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(900, 844)),
            child: Center(
              child: SizedBox(
                width: 520,
                child: MarketplaceTopSearch(
                  controller: controller,
                  focusNode: focusNode,
                  query: 'm',
                  isSearching: false,
                  previews: [_previewCard(id: '151', name: 'Mew V')],
                  completionText: 'Mew',
                  hintText: 'Search cards, sets, products...',
                  onChanged: (value) => changed = value,
                  onSelected: (_) {},
                  onShowAll: (_) {},
                  onAcceptCompletion: (value) => accepted = value,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(find.textContaining('ew'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(accepted, 'm');
    expect(changed, 'Mew');
    expect(controller.text, 'Mew');
    expect(controller.text, isNot('Mew V'));
  });

  testWidgets('Tab is ignored when no completion exists',
      (WidgetTester tester) async {
    final controller = TextEditingController(text: 'mewt');
    final searchFocusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(searchFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MarketplaceTopSearch(
                controller: controller,
                focusNode: searchFocusNode,
                query: 'mewt',
                isSearching: false,
                previews: const [],
                hintText: 'Search cards, sets, products...',
                onChanged: (_) {},
                onSelected: (_) {},
                onShowAll: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(searchFocusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(controller.text, 'mewt');
  });
}

class _NeverLoadingCardService extends CardService {
  final Completer<MarketplaceHomeSnapshot?> _homeSnapshot = Completer();

  @override
  Future<List<PokemonCard>> getCachedCards() async => const [];

  @override
  Future<MarketplaceHomeSnapshot?> getCachedMarketplaceHomeSnapshot() async =>
      null;

  @override
  Future<List<PokemonCard>> getCachedSpotlightCards() async => const [];

  @override
  Future<MarketplaceHomeSnapshot?> getMarketplaceHomeSnapshot() =>
      _homeSnapshot.future;

  @override
  Future<List<PokemonCard>> getAllCards() async => const [];
}

class _CachedHomeCardService extends CardService {
  _CachedHomeCardService(this.cards);

  final List<PokemonCard> cards;

  @override
  Future<List<PokemonCard>> getCachedCards() async => cards;

  @override
  Future<MarketplaceHomeSnapshot?> getCachedMarketplaceHomeSnapshot() async =>
      MarketplaceHomeSnapshot(
        cards: cards,
        sections: MarketplaceHomeSections(
          recentlySeenIds: const [],
          bestSellerIds: cards.take(4).map((card) => card.id).toList(),
          featuredIds: cards.skip(4).take(4).map((card) => card.id).toList(),
        ),
      );

  @override
  Future<List<PokemonCard>> getCachedSpotlightCards() async => const [];

  @override
  Future<MarketplaceHomeSnapshot?> getMarketplaceHomeSnapshot() async => null;

  @override
  Future<List<PokemonCard>> getAllCards() async => cards;
}
