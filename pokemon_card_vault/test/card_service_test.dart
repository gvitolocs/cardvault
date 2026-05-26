import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pokoin/models/pokemon_card.dart';
import 'package:pokoin/providers/card_provider.dart';
import 'package:pokoin/providers/recent_views_provider.dart';
import 'package:pokoin/services/card_service.dart';

PokemonCard _searchCard({
  required String id,
  required String name,
  String set = 'Test Set',
  String number = '1/100',
  String rarity = 'Card',
  String type = 'Trading card',
  List<String> tags = const [],
  String trainerName = '',
}) {
  return PokemonCard(
    id: id,
    name: name,
    imageUrl: 'https://cdn.pokoin.com/cards/$id.png',
    rarity: rarity,
    type: type,
    hp: 0,
    attacks: const [],
    price: 1000,
    description: 'Search ranking fixture',
    set: set,
    number: number,
    artist: '',
    stock: 0,
    rating: 0,
    reviewCount: 0,
    isFoil: false,
    isHolo: false,
    releaseDate: DateTime(2026),
    tags: tags,
    condition: 'NM',
    isGraded: false,
    trainerName: trainerName,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('search language persistence', () {
    test('new users default to English', () async {
      final notifier = CardNotifier(autoLoad: false);
      addTearDown(notifier.dispose);

      await notifier.ensureSearchLanguageLoaded();

      expect(notifier.state.searchLanguage, 'en');
    });

    test('loads saved language on provider startup', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.marketplace.search_language': 'fr',
      });
      final notifier = CardNotifier(autoLoad: false);
      addTearDown(notifier.dispose);

      await notifier.ensureSearchLanguageLoaded();

      expect(notifier.state.searchLanguage, 'fr');
    });

    test('invalid saved language falls back to English and clears storage',
        () async {
      SharedPreferences.setMockInitialValues({
        'flutter.marketplace.search_language': 'klingon',
      });
      final notifier = CardNotifier(autoLoad: false);
      addTearDown(notifier.dispose);

      await notifier.ensureSearchLanguageLoaded();

      final prefs = await SharedPreferences.getInstance();
      expect(notifier.state.searchLanguage, 'en');
      expect(prefs.getString('marketplace.search_language'), isNull);
    });

    test('setSearchLanguage normalizes and persists the selection', () async {
      final notifier = CardNotifier(autoLoad: false);
      addTearDown(notifier.dispose);

      notifier.setSearchLanguage('JP');
      await notifier.searchLanguagePersistForTest();

      final prefs = await SharedPreferences.getInstance();
      expect(notifier.state.searchLanguage, 'ja');
      expect(prefs.getString('marketplace.search_language'), 'ja');
    });
  });

  group('marketplace warmup', () {
    test('home snapshot availability wins over stale spotlight card state',
        () async {
      final staleSpotlightCard = _searchCard(
        id: '360108',
        name: 'Mega Diancie ex',
        set: 'Mega Evolution',
      );
      final cheapestSnapshotCard = staleSpotlightCard.copyWith(
        price: 4244,
        stock: 0,
        hasCardTraderListing: true,
        cardtraderEligibleListingCount: 56,
      );
      final service = _MarketplaceWarmupCardService(
        snapshot: MarketplaceHomeSnapshot(
          cards: [cheapestSnapshotCard],
          sections: MarketplaceHomeSections(
            recentlySeenIds: const [],
            bestSellerIds: [cheapestSnapshotCard.id],
            featuredIds: [cheapestSnapshotCard.id],
          ),
        ),
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.cacheCards([staleSpotlightCard]);
      await notifier.warmMarketplaceAfterDetail();

      final spotlightCard = notifier.state.spotlightCards.single;
      final catalogCard = notifier.state.cards
          .singleWhere((card) => card.id == cheapestSnapshotCard.id);
      expect(spotlightCard.price, 4244);
      expect(spotlightCard.hasCardTraderListing, isTrue);
      expect(spotlightCard.cardtraderEligibleListingCount, 56);
      expect(spotlightCard.isMarketAvailable, isTrue);
      expect(catalogCard.price, 4244);
      expect(catalogCard.isMarketAvailable, isTrue);
    });

    test(
        'detail warmup loads marketplace snapshot when only detail card exists',
        () async {
      final detailCard = _searchCard(
        id: '316600',
        name: 'Leafeon',
        set: 'Prismatic Evolutions',
      );
      final marketplaceCard = _searchCard(
        id: '316698',
        name: 'Fan Rotom',
        set: 'Prismatic Evolutions',
      );
      final service = _MarketplaceWarmupCardService(
        snapshot: MarketplaceHomeSnapshot(
          cards: [marketplaceCard],
          sections: MarketplaceHomeSections(
            recentlySeenIds: [detailCard.id],
            bestSellerIds: [marketplaceCard.id],
            featuredIds: const [],
          ),
        ),
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.cacheCards([detailCard]);

      await notifier.warmMarketplaceAfterDetail();

      expect(service.marketplaceSnapshotCalls, 1);
      expect(notifier.state.hasMarketplaceLoadCompleted, isTrue);
      expect(notifier.state.homeSections?.recentlySeenIds, [detailCard.id]);
      expect(
        notifier.state.cards.map((card) => card.id),
        containsAll([detailCard.id, marketplaceCard.id]),
      );
    });

    test('detail warmup does not refetch when marketplace is already warm',
        () async {
      final marketplaceCard = _searchCard(id: '25', name: 'Pikachu');
      final service = _MarketplaceWarmupCardService(
        cachedSnapshot: MarketplaceHomeSnapshot(
          cards: [marketplaceCard],
          sections: MarketplaceHomeSections(
            recentlySeenIds: [marketplaceCard.id],
            bestSellerIds: const [],
            featuredIds: const [],
          ),
        ),
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: true,
      );
      addTearDown(notifier.dispose);

      await Future<void>.delayed(Duration.zero);
      await notifier.warmMarketplaceAfterDetail();

      expect(service.cachedSnapshotCalls, 1);
      expect(service.marketplaceSnapshotCalls, 0);
      expect(notifier.state.hasMarketplaceLoadCompleted, isTrue);
      expect(
          notifier.state.homeSections?.recentlySeenIds, [marketplaceCard.id]);
    });

    test('navigation transition defers marketplace warmup UI updates',
        () async {
      final marketplaceCard = _searchCard(id: '25', name: 'Pikachu');
      final service = _MarketplaceWarmupCardService(
        snapshot: MarketplaceHomeSnapshot(
          cards: [marketplaceCard],
          sections: MarketplaceHomeSections(
            recentlySeenIds: const [],
            bestSellerIds: [marketplaceCard.id],
            featuredIds: const [],
          ),
        ),
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.beginNavigationTransition(
        duration: const Duration(milliseconds: 60),
      );
      await notifier.warmMarketplaceAfterDetail();

      expect(service.marketplaceSnapshotCalls, 0);
      expect(notifier.state.homeSections, isNull);
      expect(notifier.state.cards, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 90));
      await Future<void>.delayed(Duration.zero);

      expect(service.marketplaceSnapshotCalls, 1);
      expect(notifier.state.homeSections?.bestSellerIds, [marketplaceCard.id]);
      expect(notifier.state.cards.map((card) => card.id), [marketplaceCard.id]);
    });

    test(
        'stale detail hydration result is ignored after navigation token changes',
        () async {
      final staleCard = _searchCard(
        id: '25',
        name: 'Pikachu',
        number: '',
      );
      final hydratedCard = staleCard.copyWith(number: '025/165');
      final service = _MarketplaceWarmupCardService()
        ..cardsById[staleCard.id] = hydratedCard
        ..cardByIdDelay = const Duration(milliseconds: 80);
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.cacheCards([staleCard]);
      final warmup = notifier.warmDetailCards([staleCard]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      notifier.beginNavigationTransition();
      await warmup;

      expect(service.cardByIdCalls, 1);
      expect(notifier.state.cards.single.number, isEmpty);
    });
  });

  test('CardTrader blueprint mapping removes generic Pokemon badge fallback',
      () {
    final service = CardService();

    final card = service.cardFromBlueprintForTest({
      'id': 281194,
      'name': 'Gengar ex',
      'cdn_image_url': 'https://cdn.pokoin.com/cards/gengar.png',
      'preview_image_url': 'https://cdn.pokoin.com/previews/gengar.webp',
      'homepage_image_url': 'https://cdn.pokoin.com/cards/gengar_homepage.webp',
      'blueprint': {
        'name': 'Gengar ex',
        'category_name': 'Pokemon',
        'editable_properties': [
          {'name': 'number', 'value': '193/162'},
        ],
      },
      'expansion': {'name': 'Temporal Forces'},
    });

    expect(card.name, 'Gengar ex');
    expect(card.set, 'Temporal Forces');
    expect(card.number, '193/162');
    expect(card.rarity, 'Card');
    expect(card.type, 'Card');
    expect(card.stock, 0);
    expect(card.tags, isNot(contains('Pokemon')));
    expect(card.imageUrl, 'https://pokoin.com/card-images/cards/gengar.png');
    expect(card.previewImageUrl,
        'https://pokoin.com/card-images/previews/gengar.webp');
    expect(
      card.homepageImageUrl,
      'https://pokoin.com/card-images/cards/gengar_homepage.webp',
    );
  });

  test('CardTrader blueprint mapping leaves external image URLs unchanged', () {
    final service = CardService();

    final card = service.cardFromBlueprintForTest({
      'id': 42,
      'name': 'External card',
      'image_url': 'https://images.pokemontcg.io/base1/4_hires.png',
      'blueprint': <String, dynamic>{},
      'expansion': <String, dynamic>{},
    });

    expect(card.imageUrl, 'https://images.pokemontcg.io/base1/4_hires.png');
    expect(
      card.previewImageUrl,
      'https://images.pokemontcg.io/base1/4_hires.png',
    );
    expect(
      card.homepageImageUrl,
      'https://images.pokemontcg.io/base1/4_hires.png',
    );
  });

  test('marketplace row keeps CardTrader availability for tile stock display',
      () {
    final service = CardService();

    final card = service.cardFromMarketplaceRowForTest({
      'card_id': 497712,
      'name': 'Magikarp',
      'set_name': 'Paldea Evolved',
      'card_number': '203/193',
      'rarity': 'Illustration Rare',
      'card_type': 'Trading card',
      'cdn_image_url': 'https://cdn.pokoin.com/cards/magikarp.webp',
      'listed_quantity': 0,
      'lowest_price_pkn': 1600,
      'has_cardtrader_listing': true,
      'cardtrader_eligible_listing_count': 1,
    });

    expect(card.stock, 0);
    expect(card.price, 1600);
    expect(card.hasCardTraderListing, isTrue);
    expect(card.cardtraderEligibleListingCount, 1);
    expect(card.isMarketAvailable, isTrue);

    final notifier = CardNotifier(autoLoad: false);
    addTearDown(notifier.dispose);
    notifier.cacheCards([card]);
    notifier.toggleInStockFilter();

    expect(notifier.state.filteredCards.map((card) => card.id), ['497712']);
  });

  test('competitive snapshot parses dashboard deck and tournament groups', () {
    final snapshot = CompetitiveSnapshot.fromJson({
      'summary': {
        'tournamentCount': 1,
        'totalPlayers': 64,
        'tournamentsWithStandings': 1,
        'tournamentsWithPairings': 1,
      },
      'games': const [],
      'tournaments': const [],
      'dashboard': {
        'topDecks': [
          {
            'deckId': '284',
            'archetype': 'Charizard',
            'game': 'PTCG',
            'format': 'STANDARD',
            'formatLabel': 'Standard',
            'count': 5,
            'share': 62.5,
            'featuredPlayer': 'Player One',
            'featuredPlacing': 1,
            'featuredRecord': {'wins': 7, 'losses': 1, 'ties': 0},
            'featuredTournamentId': 'top123',
            'featuredTournamentName': 'Rare Candy Showdown',
            'featuredTournamentDate': '2026-05-25T00:00:00.000Z',
            'featuredDecklistId': 'deck123',
            'representativeCardId': '12345',
            'representativeCardName': 'Charizard ex',
            'representativeCardSetName': 'Obsidian Flames',
            'representativeCardNumber': '125/197',
            'representativeCardPath':
                '/marketplace/en/cards/12345/charizard-ex',
            'imageUrl': 'https://cdn.pokoin.com/cards/charizard.webp',
            'cardImageUrl': 'https://cdn.pokoin.com/cards/charizard.webp',
          },
        ],
        'recentTournaments': [
          {
            'id': 'abc123',
            'name': 'Rare Candy Showdown',
            'game': 'PTCG',
            'gameName': 'Pokemon TCG',
            'format': 'STANDARD',
            'formatLabel': 'Standard',
            'date': '2026-05-25T00:00:00.000Z',
            'players': 64,
            'isOnline': true,
            'phases': const [],
          },
        ],
      },
      'deck': {
        'id': '284',
        'name': 'Dragapult',
        'points': 2648,
        'share': 41.74,
        'variants': ['Dragapult Dusknoir'],
      },
      'coreCards': [
        {
          'name': 'Dragapult ex',
          'count': 3,
          'inclusionShare': 99.81,
          'setCode': 'TWM',
          'collectorNumber': '130',
        }
      ],
      'results': [
        {
          'tournamentId': '544',
          'tournamentName': 'Regional Campinas',
          'placing': 2,
          'playerName': 'Francisco Osorio',
          'decklistId': '27143',
        }
      ],
      'players': [
        {
          'playerId': '6816',
          'playerName': 'Nathan O.',
          'rank': 1,
          'points': 204,
        }
      ],
      'decklists': [
        {
          'decklistId': '27143',
          'deckId': '284',
          'deckName': 'Dragapult',
          'tournamentName': 'Regional Campinas',
          'playerName': 'Francisco Osorio',
          'cards': [
            {
              'name': 'Dreepy',
              'count': 4,
              'section': 'pokémon',
              'setCode': 'TWM',
              'collectorNumber': '128',
              'marketplaceCardId': '287830',
              'marketplacePath':
                  '/marketplace/en/cards/575660/card-dreepy-128-167-twilight-masquerade',
              'imageUrl':
                  'https://cdn.pokoin.com/previews/287830_dreepy-128-167-twilight-masquerade.webp',
            }
          ],
        }
      ],
      'decklist': {
        'decklistId': '27143',
        'deckId': '284',
        'deckName': 'Dragapult',
        'formatLabel': 'Standard',
        'tournamentId': '544',
        'tournamentName': 'Regional Campinas',
        'tournamentDate': '2026-05-10',
        'placing': 2,
        'placingLabel': '2nd',
        'variant': 'Dragapult Dusknoir',
        'playerId': '6816',
        'playerName': 'Francisco Osorio',
        'sourceUrl': 'https://limitlesstcg.com/decks/list/27143',
      },
      'cards': [
        {
          'name': 'Dreepy',
          'count': 4,
          'section': 'pokémon',
          'setCode': 'TWM',
          'collectorNumber': '128',
          'marketplaceCardId': '287830',
          'marketplacePath':
              '/marketplace/en/cards/575660/card-dreepy-128-167-twilight-masquerade',
          'imageUrl':
              'https://cdn.pokoin.com/previews/287830_dreepy-128-167-twilight-masquerade.webp',
        }
      ],
      'years': [2026, 2025],
    });

    expect(snapshot.summary.tournamentCount, 1);
    expect(snapshot.dashboard.topDecks.single.deckId, '284');
    expect(snapshot.dashboard.topDecks.single.archetype, 'Charizard');
    expect(snapshot.dashboard.topDecks.single.share, 62.5);
    expect(snapshot.dashboard.topDecks.single.featuredWins, 7);
    expect(snapshot.dashboard.topDecks.single.representativeCardName,
        'Charizard ex');
    expect(snapshot.dashboard.topDecks.single.cardImageUrl,
        'https://cdn.pokoin.com/cards/charizard.webp');
    expect(snapshot.years, [2026, 2025]);
    expect(snapshot.dashboard.recentTournaments.single.id, 'abc123');
    expect(snapshot.selectedDeck?.name, 'Dragapult');
    expect(snapshot.coreCards.single.name, 'Dragapult ex');
    expect(snapshot.deckResults.single.decklistId, '27143');
    expect(snapshot.deckPlayers.single.playerName, 'Nathan O.');
    expect(snapshot.decklists.single.cards.single.name, 'Dreepy');
    expect(snapshot.decklists.single.playerName, 'Francisco Osorio');
    expect(snapshot.decklists.single.cards.single.marketplaceCardId, '287830');
    expect(snapshot.decklists.single.cards.single.imageUrl,
        contains('cdn.pokoin.com/previews'));
    expect(snapshot.selectedDecklist?.decklistId, '27143');
    expect(snapshot.selectedDecklist?.deckName, 'Dragapult');
    expect(snapshot.selectedDecklist?.placingLabel, '2nd');
    expect(snapshot.decklistCards.single.name, 'Dreepy');
  });

  test('marketplace row uses canonical CardTrader cache price', () {
    final service = CardService();

    final card = service.cardFromMarketplaceRowForTest({
      'card_id': 316600,
      'name': 'Servine',
      'set_name': 'Black & White',
      'card_number': '4/114',
      'rarity': 'Uncommon',
      'card_type': 'Trading card',
      'cdn_image_url': 'https://cdn.pokoin.com/cards/servine.webp',
      'listed_quantity': 0,
      'has_cardtrader_listing': true,
      'cardtrader_eligible_listing_count': 2,
      'cardtrader_lowest_price_pkn': 420,
    });

    expect(card.stock, 0);
    expect(card.price, 420);
    expect(card.isMarketAvailable, isTrue);
  });

  test('marketplace version row uses canonical homepage cheapest price', () {
    final service = CardService();

    final card = service.cardFromVersionRowForTest({
      'card_id': 391030,
      'name': 'Mega Venusaur ex',
      'expansion_name': 'Play! Pokémon Prize Pack Series',
      'expansion_number': '003/132',
      'rarity': 'Promo',
      'card_type': 'Trading card',
      'cdn_image_url': 'https://cdn.pokoin.com/cards/mega-venusaur-ex.webp',
      'listed_quantity': 7,
      'lowest_price_pkn': 615,
      'has_cardtrader_listing': true,
      'cardtrader_eligible_listing_count': 3,
    });

    expect(card.stock, 7);
    expect(card.price, 615);
    expect(card.hasCardTraderListing, isTrue);
    expect(card.cardtraderEligibleListingCount, 3);
    expect(card.isMarketAvailable, isTrue);
  });

  test('marketplace result rows do not synthesize fallback prices', () {
    final service = CardService();

    final card = service.cardFromVersionRowForTest({
      'card_id': 391034,
      'name': 'Ledian',
      'expansion_name': 'Play! Pokémon Prize Pack Series',
      'expansion_number': '003/142',
      'rarity': 'Promo',
      'card_type': 'Trading card',
      'cdn_image_url': 'https://cdn.pokoin.com/cards/ledian.webp',
      'listed_quantity': 0,
      'lowest_price_pkn': null,
      'has_cardtrader_listing': false,
      'cardtrader_eligible_listing_count': 0,
    });

    expect(card.price, 0);
    expect(card.stock, 0);
    expect(card.isMarketAvailable, isFalse);
  });

  test('PokemonCard JSON reads cached CardTrader price fields', () {
    final card = PokemonCard.fromJson({
      'id': '038040',
      'name': 'Briar',
      'imageUrl': 'https://cdn.pokoin.com/cards/briar.webp',
      'rarity': 'Ultra Rare',
      'type': 'Trading card',
      'stock': 0,
      'hasCardTraderListing': true,
      'cardtraderEligibleListingCount': 1,
      'cardtraderLowestPricePkn': '760',
      'reviewCount': 0,
      'isFoil': false,
      'isHolo': false,
      'tags': const [],
    });

    expect(card.price, 760);
    expect(card.isMarketAvailable, isTrue);
  });

  test('MarketplaceCheapestPrice parses CardTrader cache payload', () {
    final price = MarketplaceCheapestPrice.fromJson({
      'cardId': '241674',
      'pricePkn': '4244.0000000000000000',
      'available': true,
      'listingCount': '56',
      'listedQuantity': '73',
      'canonicalPath':
          '/marketplace/en/cards/483348/card-drowzee-210-198-scarlet-violet',
      'publicNumber': '483348',
      'cardtrader': {
        'source': 'cheapest_homepage_cache_blueprint',
      },
    });

    expect(price.cardId, '241674');
    expect(price.pricePkn, 4244);
    expect(price.available, isTrue);
    expect(price.listingCount, 56);
    expect(price.listedQuantity, 73);
    expect(price.publicNumber, '483348');
    expect(
      price.canonicalPath,
      '/marketplace/en/cards/483348/card-drowzee-210-198-scarlet-violet',
    );
  });

  test('cheapest price query includes canonical path public and internal ids',
      () {
    final service = CardService();

    final query = service.marketplaceCheapestPriceQueryForTest([
      '/marketplace/en/cards/612154/card-morelull-008-191-surging-sparks',
      '483348',
    ]);

    expect(query['cardIds'], '612154,306077,483348');
    expect(
      query['canonicalPath'],
      '/marketplace/en/cards/612154/card-morelull-008-191-surging-sparks',
    );
  });

  test('cheapest price query builds structured fallback requests', () {
    final service = CardService();

    final queries = service.marketplaceCheapestPriceQueriesForTest([
      'structured:drowzee|scarlet violet|210/198',
      'structured:morelull|surging sparks|008/191',
    ]);

    expect(queries, [
      {
        'name': 'drowzee',
        'setName': 'scarlet violet',
        'number': '210/198',
        'limit': '1',
      },
      {
        'name': 'morelull',
        'setName': 'surging sparks',
        'number': '008/191',
        'limit': '1',
      },
    ]);
  });

  test('marketplace row maps watchlist count to integer star metric', () {
    final service = CardService();

    final card = service.cardFromMarketplaceRowForTest({
      'card_id': 316600,
      'name': 'Leafeon',
      'set_name': 'Prismatic Evolutions',
      'card_number': '144/131',
      'rarity': 'Rare',
      'card_type': 'Trading card',
      'cdn_image_url': 'https://cdn.pokoin.com/cards/leafeon.webp',
      'watchlist_count': 42,
      'cart_holder_count': 6,
    });

    expect(card.watchlistCount, 42);
    expect(card.cartHolderCount, 6);
    expect(card.cartMetricCount, 6);
    expect(card.rating, 42);
    expect(card.starMetricCount, 42);
  });

  test('PokemonCard JSON reads analytics counts from analytics payload', () {
    final card = PokemonCard.fromJson({
      'id': '316600',
      'name': 'Leafeon',
      'imageUrl': 'https://cdn.pokoin.com/cards/leafeon.webp',
      'rarity': 'Rare',
      'type': 'Trading card',
      'price': 1000,
      'stock': 0,
      'rating': 0,
      'reviewCount': 0,
      'isFoil': false,
      'isHolo': false,
      'tags': const [],
      'analytics': {'watchlistCount': 9, 'cartHolderCount': 3},
    });

    expect(card.watchlistCount, 9);
    expect(card.cartHolderCount, 3);
    expect(card.starMetricCount, 9);
    expect(card.toJson()['watchlistCount'], 9);
    expect(card.toJson()['cartHolderCount'], 3);
  });

  test('marketplace version mapping uses public image proxy for CDN artwork',
      () {
    final service = CardService();

    final card = service.cardFromVersionRowForTest({
      'card_id': '248856',
      'name': 'Magikarp',
      'expansion_name': 'Paldea Evolved',
      'expansion_number': 'Illustration Rare | 203/193',
      'cdn_image_url':
          'https://cdn.pokoin.com/248856_magikarp-203-193-paldea-evolved.png',
      'preview_image_url':
          'https://cdn.pokoin.com/previews/248856_magikarp-203-193-paldea-evolved.webp',
      'homepage_image_url':
          'https://cdn.pokoin.com/248856_magikarp-203-193-paldea-evolved_homepage.webp',
    });

    expect(
      card.imageUrl,
      'https://pokoin.com/card-images/248856_magikarp-203-193-paldea-evolved.png',
    );
    expect(
      card.previewImageUrl,
      'https://pokoin.com/card-images/previews/248856_magikarp-203-193-paldea-evolved.webp',
    );
    expect(
      card.homepageImageUrl,
      'https://pokoin.com/card-images/248856_magikarp-203-193-paldea-evolved_homepage.webp',
    );
  });

  test('CardTrader blueprint mapping reads image URL from blueprint fallback',
      () {
    final service = CardService();

    final card = service.cardFromBlueprintForTest({
      'id': 43,
      'name': 'Blueprint image card',
      'blueprint': {
        'image_url': 'https://cdn.pokoin.com/blueprint/card.png',
      },
      'expansion': <String, dynamic>{},
    });

    expect(card.imageUrl, 'https://pokoin.com/card-images/blueprint/card.png');
    expect(card.previewImageUrl,
        'https://pokoin.com/card-images/blueprint/card.png');
    expect(card.homepageImageUrl,
        'https://pokoin.com/card-images/blueprint/card.png');
  });

  test('search cancel payload uses stable anonymous-safe shape', () {
    final payload = CardService().searchCancelPayloadForTest(
      sessionId: 'flutter-12345678-1',
      lastQuery: ' pikachu ',
      reason: ' blur ',
    );

    expect(payload['search_session_id'], 'flutter-12345678-1');
    expect(payload['last_query'], 'pikachu');
    expect(payload['reason'], 'blur');
    expect(payload['client'], isA<String>());
    expect(payload['locale'], isA<String>());
  });

  group('autocomplete fuzzy ranking', () {
    test('single-edit pokemon misspells rank the closest card first', () {
      final service = CardService();
      final cards = [
        _searchCard(id: '1', name: 'Pikachu ex', number: '063/193'),
        _searchCard(id: '2', name: 'Pidgeot ex', number: '164/197'),
        _searchCard(id: '3', name: 'Squirtle', number: '063/165'),
        _searchCard(id: '4', name: 'Gyarados', number: '020/165'),
      ];

      expect(
        service.rankSearchCandidatesForTest(cards, 'pikacu').first.name,
        startsWith('Pikachu'),
      );
      expect(
        service.rankSearchCandidatesForTest(cards, 'squirtel').first.name,
        'Squirtle',
      );
      expect(
        service.rankSearchCandidatesForTest(cards, 'gyrados').first.name,
        'Gyarados',
      );
    });

    test('transposed letters are treated as one typo', () {
      final service = CardService();
      final cards = [
        _searchCard(id: '1', name: 'Charizard ex', number: '199/165'),
        _searchCard(id: '2', name: 'Charmander', number: '044/165'),
        _searchCard(id: '3', name: 'Squirtle', number: '063/165'),
        _searchCard(id: '4', name: 'Wartortle', number: '008/165'),
      ];

      expect(
        service.rankSearchCandidatesForTest(cards, 'cahrizard').first.name,
        startsWith('Charizard'),
      );
      expect(
        service.rankSearchCandidatesForTest(cards, 'squirtel').first.name,
        'Squirtle',
      );
    });

    test('near full-name typo ranks Charizard over noisy set matches', () {
      final service = CardService();
      final cards = [
        _searchCard(
          id: '1',
          name: 'Carkol',
          number: '006/021',
          set: 'Charizard VMAX Starter Set 2',
        ),
        _searchCard(id: '2', name: 'Charizard', number: '014/177'),
        _searchCard(id: '3', name: 'Charizard ex', number: '002/177'),
      ];

      final results = service.rankSearchCandidatesForTest(cards, 'carizard');

      expect(results.first.name, startsWith('Charizard'));
      expect(results.take(2).map((card) => card.name),
          everyElement(contains('Charizard')));
    });

    test('exact name query keeps multiple matching variants above noise', () {
      final service = CardService();
      final cards = [
        _searchCard(id: '1', name: 'Lechonk', number: '066/078'),
        _searchCard(id: '2', name: 'Lechonk', number: '154/198'),
        _searchCard(id: '3', name: 'Metal Energy', set: 'Happy Combination'),
        _searchCard(
            id: '4', name: 'Poke Ball', set: 'Shining Pokemon Gift Box'),
      ];

      final results = service.rankSearchCandidatesForTest(cards, 'lechonk');

      expect(results.take(2).map((card) => card.name), everyElement('Lechonk'));
    });

    test('single-word exact queries reject loose character-only noise', () {
      final service = CardService();
      final cards = [
        _searchCard(
          id: '1',
          name: 'Porygon',
          number: 'No.137',
          set: 'Expansion Sheet',
        ),
        _searchCard(
          id: '2',
          name: 'Pokemon Communication',
          number: '008/019',
          set:
              'CSMA: Arceus & Dialga & Palkia-GX Advanced Deck Building Gift Box',
        ),
        _searchCard(
          id: '3',
          name: 'Koraidon ex',
          number: '005/006',
          set: 'CSVH4pC: Reward Pack',
        ),
      ];

      final results = service.rankSearchCandidatesForTest(cards, 'porygon');

      expect(results.map((card) => card.name), ['Porygon']);
    });

    test('localized trainer aliases rank owner cards over generic pokemon', () {
      final service = CardService();
      final cards = [
        _searchCard(
          id: '1',
          name: "Cynthia's Garchomp ex",
          number: '091/063',
          tags: const ['Cynthia', 'Camilla'],
          trainerName: 'Cynthia',
        ),
        _searchCard(id: '2', name: 'Garchomp', number: '024/054'),
        _searchCard(id: '3', name: 'Camerupt', number: '023/106'),
      ];

      final camilla = service.rankSearchCandidatesForTest(cards, 'camilla');
      expect(camilla.first.name, "Cynthia's Garchomp ex");

      final ownerQuery =
          service.rankSearchCandidatesForTest(cards, 'garchomp camilla');
      expect(ownerQuery.first.name, "Cynthia's Garchomp ex");
    });

    test('compact rarity misspells expand to spaced rarity labels', () {
      final service = CardService();
      final cards = [
        _searchCard(
          id: '1',
          name: 'Mew ex',
          rarity: 'Special Illustration Rare',
          tags: const ['Special Illustration Rare'],
        ),
        _searchCard(
          id: '2',
          name: 'Mewtwo ex',
          rarity: 'Double Rare',
          tags: const ['Double Rare'],
        ),
      ];

      final results =
          service.rankSearchCandidatesForTest(cards, 'specialillustrationrare');

      expect(results.first.name, 'Mew ex');
    });

    test('ordered character coverage moves stronger partial matches up', () {
      final service = CardService();
      final cards = [
        _searchCard(
          id: '1',
          name: 'Porygon',
          number: 'No.137',
          set: 'Expansion Sheet',
        ),
        _searchCard(
          id: '2',
          name: 'Pikachu Lv.15',
          number: '025/025',
          set: 'Japanese Promo',
        ),
        _searchCard(
          id: '3',
          name: 'Pikachu',
          number: '025/151',
          set: 'Collect 151',
        ),
      ];

      final results = service.rankSearchCandidatesForTest(cards, 'pikach 15');

      expect(results.first.name, 'Pikachu Lv.15');
      expect(results.first.set, 'Japanese Promo');
    });

    test(
        'static catalog exact autocomplete keeps Porygon variants above por noise',
        () {
      final service = CardService();
      final cards = [
        _searchCard(id: '1', name: 'Porygon', set: '151', number: '137/165'),
        _searchCard(
          id: '2',
          name: 'Porygon2',
          set: 'Stellar Crown',
          number: '144/175',
        ),
        _searchCard(id: '3', name: 'Porygon-Z', set: 'Unbroken Bonds'),
        _searchCard(id: '4', name: 'Vaporeon', set: 'Display Set Gift Box'),
        _searchCard(id: '5', name: 'Eevee', set: 'Display Set Gift Box Eevee'),
        _searchCard(id: '6', name: 'Pokemon Communication'),
      ];

      final results = service.rankSearchCandidatesForTest(cards, 'porygon');

      expect(results.take(3).map((card) => card.name),
          everyElement(startsWith('Porygon')));
      expect(results.map((card) => card.name), isNot(contains('Vaporeon')));
      expect(results.map((card) => card.name),
          isNot(contains('Pokemon Communication')));
    });

    test(
        'short prefixes allow typo-tolerant warmup without outranking exact names',
        () {
      final service = CardService();
      final cards = [
        _searchCard(id: '1', name: 'Porygon', set: '151'),
        _searchCard(id: '2', name: 'Porygon2', set: 'Stellar Crown'),
        _searchCard(
            id: '3', name: 'Vaporeon', set: 'CSGC Display Set Gift Box'),
        _searchCard(id: '4', name: 'Professor Research'),
      ];

      final results = service.rankSearchCandidatesForTest(cards, 'por');

      expect(results.first.name, startsWith('Porygon'));
      expect(results.take(2).map((card) => card.name),
          everyElement(startsWith('Porygon')));
    });

    test('collector abbreviations rank common shorthand names', () {
      final service = CardService();
      final cards = [
        _searchCard(id: '1', name: 'Charizard ex', set: '151'),
        _searchCard(id: '2', name: 'Charmander', set: '151'),
        _searchCard(id: '3', name: 'Venusaur ex', set: '151'),
        _searchCard(id: '4', name: 'Blastoise ex', set: '151'),
      ];

      expect(
        service.rankSearchCandidatesForTest(cards, 'char ex').first.name,
        'Charizard ex',
      );
      expect(
        service.rankSearchCandidatesForTest(cards, 'venu ex').first.name,
        'Venusaur ex',
      );
      expect(
        service.rankSearchCandidatesForTest(cards, 'blast ex').first.name,
        'Blastoise ex',
      );
    });

    test('standalone v filters to real V variants', () {
      final service = CardService();
      final cards = [
        _searchCard(id: '1', name: 'Darkrai V', set: 'Astral Radiance'),
        _searchCard(id: '2', name: 'Venusaur', set: '151'),
        _searchCard(id: '3', name: 'Vileplume', set: 'Jungle'),
        _searchCard(id: '4', name: 'Pikachu VMAX', set: 'Vivid Voltage'),
      ];

      final results = service.rankSearchCandidatesForTest(cards, 'v');

      expect(results.map((card) => card.name), contains('Darkrai V'));
      expect(results.map((card) => card.name), isNot(contains('Venusaur')));
      expect(results.map((card) => card.name), isNot(contains('Vileplume')));
    });

    test('standalone n is allowed as one-character name intent', () {
      final service = CardService();
      final cards = [
        _searchCard(id: '1', name: 'N', set: 'Promo'),
        _searchCard(id: '2', name: 'Ninetales', set: '151'),
        _searchCard(id: '3', name: 'Nest Ball', set: 'Scarlet & Violet'),
      ];

      final results = service.rankSearchCandidatesForTest(cards, 'n');
      final names = results.map((card) => card.name).toList();

      expect(names.first, 'N');
      expect(names, containsAll(['Ninetales', 'Nest Ball']));
    });

    test('all one-character terms are sent as remote autocomplete intent', () {
      final service = CardService();

      expect(service.searchQueryVariantsForTest('p'), ['p']);
      expect(service.searchQueryVariantsForTest('z'), ['z']);
      expect(service.searchQueryVariantsForTest('v'), ['v']);
    });

    test('variation intent beats expansion name matches', () {
      final service = CardService();
      final cards = [
        _searchCard(id: '1', name: 'EX', set: 'Unseen Forces'),
        _searchCard(
            id: '2', name: 'Eevee', number: '063/100', set: 'EX Sandstorm'),
        _searchCard(
            id: '3', name: 'Eevee', number: '069/113', set: 'EX Delta Species'),
        _searchCard(
            id: '4',
            name: 'Eevee ex',
            number: '075/131',
            set: 'Play! Pokemon Prize Pack Series'),
      ];

      final results = service.rankSearchCandidatesForTest(cards, 'eevee ex');

      expect(results.first.name, 'Eevee ex');
    });

    test('partial variation prefixes beat expansion name matches', () {
      final service = CardService();
      final cards = [
        _searchCard(id: '1', name: 'Mimikyu', set: 'GX Battle Boost'),
        _searchCard(id: '2', name: 'Mimikyu GX', set: 'Lost Thunder'),
        _searchCard(id: '3', name: 'Mimikyu ex', set: 'Paldean Fates'),
      ];

      final gxResults = service.rankSearchCandidatesForTest(cards, 'mimikyu g');
      final exResults = service.rankSearchCandidatesForTest(cards, 'mimikyu e');

      expect(gxResults.map((card) => card.name), ['Mimikyu GX']);
      expect(exResults.map((card) => card.name), ['Mimikyu ex']);
    });

    test('vmax prefixes are variation intent, not loose text', () {
      final service = CardService();
      final cards = [
        _searchCard(id: '1', name: 'Pikachu VMAX', set: 'Vivid Voltage'),
        _searchCard(id: '2', name: 'Pikachu', set: 'VMAX Climax'),
      ];

      final results = service.rankSearchCandidatesForTest(cards, 'pikachu vm');

      expect(results.map((card) => card.name), ['Pikachu VMAX']);
    });

    test('common misspells keep zero and one typo matches over set matches',
        () {
      final service = CardService();
      final cards = [
        _searchCard(id: '1', name: 'Gardevoir ex', set: 'Scarlet & Violet'),
        _searchCard(id: '2', name: 'Garchomp ex', set: 'Paradox Rift'),
        _searchCard(id: '3', name: 'Energy Switch', set: 'Gardevoir Deck'),
        _searchCard(id: '4', name: 'Rare Candy', set: 'Garchomp Deck'),
      ];

      expect(
        service.rankSearchCandidatesForTest(cards, 'gardevior').first.name,
        'Gardevoir ex',
      );
      expect(
        service.rankSearchCandidatesForTest(cards, 'garchomp').first.name,
        'Garchomp ex',
      );
    });

    test('number abbreviations are useful but do not beat exact name matches',
        () {
      final service = CardService();
      final cards = [
        _searchCard(id: '1', name: 'Crobat', number: '091/083'),
        _searchCard(id: '2', name: 'Crobat ex', number: '091/106'),
        _searchCard(id: '3', name: 'Potion', number: '091/165'),
      ];

      final exactName = service.rankSearchCandidatesForTest(cards, 'crobat');
      expect(exactName.take(2).map((card) => card.name),
          everyElement(contains('Crobat')));

      final number = service.rankSearchCandidatesForTest(cards, '091');
      expect(
          number.map((card) => card.number), everyElement(startsWith('091')));
    });

    test('multi-token typo and expansion number search ranks the intended card',
        () {
      final service = CardService();
      final cards = [
        _searchCard(
          id: '1',
          name: 'Pikachu',
          set: '151',
          number: '025/165',
        ),
        _searchCard(
          id: '2',
          name: 'Pikachu ex',
          set: 'Journey Together',
          number: '179/159',
        ),
        _searchCard(
          id: '3',
          name: 'Charmander',
          set: '151',
          number: '004/165',
        ),
      ];

      final results = service.rankSearchCandidatesForTest(cards, 'piachu 151');

      expect(results.first.name, 'Pikachu');
      expect(results.first.set, '151');
    });

    test('multi-token rarity query keeps card name stronger than rarity noise',
        () {
      final service = CardService();
      final cards = [
        _searchCard(
          id: '1',
          name: 'Mew ex',
          set: 'Paldean Fates',
          number: '232/091',
          rarity: 'Special Illustration Rare',
          tags: const ['Special Illustration Rare'],
        ),
        _searchCard(
          id: '2',
          name: 'Energy Switch',
          set: 'Deck',
          rarity: 'Special Illustration Rare',
          tags: const ['Special Illustration Rare'],
        ),
        _searchCard(id: '3', name: 'Mewtwo ex', rarity: 'Double Rare'),
      ];

      final results = service.rankSearchCandidatesForTest(
        cards,
        'mew special illustration rare',
      );

      expect(results.first.name, 'Mew ex');
    });

    test('equal local scores keep source order instead of alphabetical order',
        () {
      final service = CardService();
      final cards = [
        _searchCard(id: '1', name: 'Zulu', number: '151'),
        _searchCard(id: '2', name: 'Abcd', number: '151'),
      ];

      final results = service.rankSearchCandidatesForTest(cards, '151');

      expect(results.map((card) => card.name), ['Zulu', 'Abcd']);
    });
  });

  group('remote search order preservation', () {
    test('candidate row mapping dedupes while preserving backend rank', () {
      final service = CardService();

      final cards = service.searchCandidateCardsFromRowsForTest([
        {
          'card_id': '274416',
          'name': 'Mew ex',
          'set_name': 'Paldean Fates',
          'card_number': '232/091',
          'rarity': 'Special Illustration Rare',
          'card_type': 'Pokemon',
        },
        {
          'card_id': '287350',
          'name': 'Mew',
          'set_name': 'Pokemon Card 151',
          'card_number': '005/016',
          'rarity': 'Card',
          'card_type': 'Pokemon',
        },
        {
          'card_id': '999999',
          'name': 'Mewtwo',
          'set_name': 'Promo',
          'card_number': '150/165',
          'rarity': 'Card',
          'card_type': 'Pokemon',
        },
        {
          'card_id': '287350',
          'name': 'Mew duplicate',
          'set_name': 'Pokemon Card 151',
          'card_number': '005/016',
          'rarity': 'Card',
          'card_type': 'Pokemon',
        },
      ]);

      expect(cards.map((card) => card.name), ['Mew ex', 'Mew', 'Mewtwo']);
      expect(cards.map((card) => card.id).toSet(), hasLength(cards.length));
    });

    test('version row mapping preserves database canonical path', () {
      final service = CardService();

      final card = service.cardFromVersionRowForTest({
        'card_id': '122739',
        'name': 'Cresselia Lv.43',
        'expansion_name': 'Majestic Dawn',
        'expansion_number': '2/100',
        'rarity': 'Holo Rare',
        'card_type': 'Pokemon',
        'canonical_path':
            '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn',
      });

      expect(
        card.canonicalPath,
        '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn',
      );
    });

    test('version row mapping prefers structured emoji slots', () {
      final service = CardService();

      final card = service.cardFromVersionRowForTest({
        'card_id': '274416',
        'name': 'Mew ex',
        'expansion_name': 'Paldean Fates',
        'expansion_number': 'Special Illustration Rare | 232/091',
        'rarity': 'Special Illustration Rare',
        'card_type': 'Trading card',
        'emoji': '🔮  💎 💎',
        'card_identity_emojis': ['🔮', '✨'],
        'rarity_variant_emoji': '🎨',
      });

      expect(card.emoji, '🔮 ✨ 🎨');
    });

    test('version row mapping normalizes legacy emoji strings', () {
      final service = CardService();

      final card = service.cardFromVersionRowForTest({
        'card_id': '316779',
        'name': 'Leafeon ex',
        'expansion_name': 'Prismatic Evolutions',
        'expansion_number': 'Special Illustration Rare | 144/131',
        'rarity': 'Special Illustration Rare',
        'card_type': 'Trading card',
        'emoji': '🦊 ✨ 💎 💎',
      });

      expect(card.emoji, '🦊 ✨ 🎨');
    });

    test('version row mapping repairs legacy two-token rarity emoji', () {
      final service = CardService();

      final card = service.cardFromVersionRowForTest({
        'card_id': '111409',
        'name': 'Servine',
        'expansion_name': 'Black & White',
        'expansion_number': '4/114',
        'rarity': 'Uncommon',
        'card_type': 'Trading card',
        'emoji': '🐍 🌿',
      });

      expect(card.emoji, '🐍 🌿 🔷');
    });

    test(
        'version row mapping replaces generic identity emoji for known species',
        () {
      final service = CardService();

      final camerupt = service.cardFromVersionRowForTest({
        'card_id': '391051',
        'name': 'Mega Camerupt ex',
        'expansion_name': 'Play! Pokémon Prize Pack Series',
        'expansion_number': '022/132',
        'rarity': 'Promo',
        'card_type': 'Trading card',
        'emoji': '🃏 ✨ 🎟️',
      });
      final sharpedo = service.cardFromVersionRowForTest({
        'card_id': '356913',
        'name': 'Mega Sharpedo ex',
        'expansion_name': 'Phantasmal Flames',
        'expansion_number': 'Special Illustration Rare | 127/094',
        'rarity': 'Special Illustration Rare',
        'card_type': 'Trading card',
        'emoji': '🃏 ✨ 🎨',
      });
      final regirock = service.cardFromVersionRowForTest({
        'card_id': '370745',
        'name': 'Regirock ex',
        'expansion_name': 'Ascended Heroes',
        'expansion_number': 'Ultra Rare | 107/217',
        'rarity': 'Ultra Rare',
        'card_type': 'Trading card',
        'emoji': '🃏 ✨ 💎',
      });

      expect(camerupt.emoji, '🐫 🌋 🎟️');
      expect(sharpedo.emoji, '🦈 🌊 🎨');
      expect(regirock.emoji, '🪨 🌟 💎');
    });

    test('provider remote result helper preserves backend rank, not names', () {
      final results = remoteSearchResultsForTest([
        _searchCard(id: '3', name: 'Zulu Mew'),
        _searchCard(id: '1', name: 'Alpha Mew'),
        _searchCard(id: '2', name: 'Middle Mew'),
        _searchCard(id: '1', name: 'Alpha duplicate'),
      ]);

      expect(results.map((card) => card.name), [
        'Zulu Mew',
        'Alpha Mew',
        'Middle Mew',
      ]);
      expect(results.map((card) => card.id), ['3', '1', '2']);
    });

    test('preview cache does not downgrade rich home card metadata', () {
      final notifier = CardNotifier(autoLoad: false);
      addTearDown(notifier.dispose);

      final richCard = _searchCard(
        id: '296385',
        name: 'Black Kyurem ex',
        rarity: 'Special Illustration Rare',
        type: 'Dragon',
        tags: const ['Dragon', 'Special Illustration Rare'],
      ).copyWith(
        imageUrl: 'https://cdn.pokoin.com/cards/296385/full.jpg',
        previewImageUrl: 'https://cdn.pokoin.com/cards/296385/preview.webp',
        homepageImageUrl: 'https://cdn.pokoin.com/cards/296385/homepage.webp',
        emoji: '🌟💧🪽',
        cardPalette: const {'dominant': '#0EA5E9'},
      );
      final previewCard = _searchCard(
        id: '296385',
        name: 'Black Kyurem ex',
        rarity: 'Card',
        type: 'Trading card',
      ).copyWith(
        imageUrl: 'https://cdn.pokoin.com/cards/296385/full.jpg',
        previewImageUrl: 'https://cdn.pokoin.com/cards/296385/preview.webp',
        homepageImageUrl: '',
        emoji: '',
        cardPalette: const {},
      );

      notifier.cacheCards([richCard]);
      notifier.cacheCards([previewCard]);

      final merged = notifier.state.cards.single;
      expect(
        merged.homepageImageUrl,
        'https://cdn.pokoin.com/cards/296385/homepage.webp',
      );
      expect(merged.emoji, '🌟💧🪽');
      expect(merged.cardPalette, {'dominant': '#0EA5E9'});
      expect(merged.rarity, 'Special Illustration Rare');
      expect(merged.type, 'Dragon');
    });

    test('detail cache survives later marketplace preview merges', () {
      final notifier = CardNotifier(autoLoad: false);
      addTearDown(notifier.dispose);

      final detailCard = _searchCard(
        id: '248768',
        name: 'Drifloon Lv. 17',
        number: '6/17',
        rarity: 'Promo',
        type: 'Psychic',
        tags: const ['POP Series 6', 'Promo'],
      ).copyWith(
        description:
            'Imported from CardTrader blueprint data. Seller listings are managed on Pokoin.',
        imageUrl: 'https://cdn.pokoin.com/cards/248768/full.jpg',
        previewImageUrl: 'https://cdn.pokoin.com/cards/248768/preview.webp',
        homepageImageUrl: 'https://cdn.pokoin.com/cards/248768/homepage.webp',
        cardPalette: const {'dominant': '#7C3AED'},
      );
      final previewCard = _searchCard(
        id: '248768',
        name: 'Drifloon Lv. 17',
        number: '',
        rarity: 'Card',
        type: 'Trading card',
      ).copyWith(
        description: 'Saved from your recent marketplace views.',
        previewImageUrl: 'https://cdn.pokoin.com/cards/248768/preview.webp',
        homepageImageUrl: '',
        cardPalette: const {},
      );

      notifier.cacheCards([detailCard]);
      notifier.cacheCards([previewCard]);

      final merged = notifier.state.cards.single;
      expect(merged.number, '6/17');
      expect(merged.rarity, 'Promo');
      expect(merged.type, 'Psychic');
      expect(merged.homepageImageUrl,
          'https://cdn.pokoin.com/cards/248768/homepage.webp');
      expect(merged.cardPalette, {'dominant': '#7C3AED'});
      expect(needsMarketplaceDetailHydration(merged), isFalse);
    });

    test('detail hydration is only required for lightweight card rows', () {
      final marketplaceProjection = _searchCard(
        id: '248768',
        name: 'Drifloon Lv. 17',
        number: '6/17',
      ).copyWith(
        description:
            'Imported from the Pokoin marketplace version index. Full blueprint data is loaded on card detail.',
      );
      final recentOnly = _searchCard(
        id: '248768',
        name: 'Drifloon Lv. 17',
        number: '',
      ).copyWith(description: 'Saved from your recent marketplace views.');

      expect(needsMarketplaceDetailHydration(marketplaceProjection), isFalse);
      expect(needsMarketplaceDetailHydration(recentOnly), isTrue);
    });

    test('typed remote helper does not locally rerank hot or fuzzy cards', () {
      final results = remoteSearchResultsForTest([
        _searchCard(id: '20', name: 'Pidgey'),
        _searchCard(id: '10', name: 'Pikachu'),
        _searchCard(id: '30', name: "Ash's Pikachu"),
      ]);

      expect(results.map((card) => card.name), [
        'Pidgey',
        'Pikachu',
        "Ash's Pikachu",
      ]);
    });

    test('autocomplete context round trip preserves backend order fields only',
        () {
      final context = SearchAutocompleteContext.fromJson({
        'query': 'pi',
        'language': 'en',
        'card_ids': ['2', '1'],
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        'strategy': 'name_table_direct',
        'non_name_context': {
          'depth_scores': {'2': 3, '1': 3},
        },
        'candidate_labels': [
          {
            'id': '2',
            'name': 'Pichu',
            'item_kind': 'single',
          },
          {
            'id': '1',
            'name': 'Pikachu',
            'item_kind': 'single',
          },
        ],
      });

      expect(context.canRefine('pik', 'en'), isTrue);
      expect(context.toJson()['card_ids'], ['2', '1']);
      expect(context.candidateLabels.map((label) => label.name), [
        'Pichu',
        'Pikachu',
      ]);
      expect(
        (context.toJson()['non_name_context'] as Map)['depth_scores'],
        {'2': 3, '1': 3},
      );
    });

    test('autocomplete context parses predictive pool tokens', () {
      final context = SearchAutocompleteContext.fromJson({
        'query': 'mewt',
        'language': 'en',
        'card_ids': ['1'],
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        'strategy': 'predictive_dimension_pool',
        'non_name_context': {
          'predictive_pool': {
            'predicted_tokens': [
              {
                'normalized': 'mewtwo',
                'display': 'Mewtwo',
                'confidence': 91.5,
                'source_rank': 1,
                'language': 'en',
                'name_fragment': 'mewt',
                'representative_card_ids': ['1', '2'],
                'representative_labels': [
                  {'id': '1', 'name': 'Mewtwo'},
                ],
              },
            ],
          },
        },
      });

      expect(context.predictedNameTokens, hasLength(1));
      final token = context.predictedNameTokens.single;
      expect(token.display, 'Mewtwo');
      expect(token.normalized, 'mewtwo');
      expect(token.confidence, 91.5);
      expect(token.source, 'search_context.predictive_pool');
      expect(token.representativeCardIds, ['1', '2']);
      expect(token.representativeLabels.single.name, 'Mewtwo');
    });

    test('token prediction response parses compact endpoint shape', () {
      final tokens = CardService().predictedNameTokensFromJsonForTest([
        {
          'display_token': 'Pikachu',
          'normalized_token': 'pikachu',
          'confidence': 96,
          'source_rank': 1,
          'language': 'en',
          'matched_prefix': 'p',
          'card_count': 120,
          'ids_count': 120,
          'representative_card_ids': ['25', '26', '27'],
        },
      ]);

      expect(tokens, hasLength(1));
      expect(tokens.single.display, 'Pikachu');
      expect(tokens.single.normalized, 'pikachu');
      expect(tokens.single.source, 'token_predict');
      expect(tokens.single.representativeCardIds, ['25', '26', '27']);
    });

    test('token prediction context parses candidates and validates refinement',
        () {
      final context = SearchTokenPredictionContext.fromJson({
        'query': 'pi',
        'fragment': 'pi',
        'prediction_fragment': 'pi',
        'normalized_fragment': 'pi',
        'language': 'en',
        'depth': 2,
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        'source': 'supabase_postgres',
        'candidates': [
          {
            'display_token': 'Pikachu',
            'normalized_token': 'pikachu',
            'confidence': 96,
            'representative_card_ids': ['25'],
          },
        ],
      });

      expect(context.canRefine('pik', 'en'), isTrue);
      expect(context.canRefine('par', 'en'), isFalse);
      expect(context.canRefine('pik', 'fr'), isFalse);
      expect(context.candidates.single.display, 'Pikachu');
      expect(context.toJson()['candidates'], hasLength(1));
    });

    test('search completion only extends the active trailing name token', () {
      expect(searchCompletionForQuery('m', 'Mew'), 'Mew');
      expect(searchCompletionForQuery('mewt', 'Mewtwo'), 'Mewtwo');
      expect(searchCompletionForQuery('tapu l', 'Tapu Lele'), 'Tapu Lele');
      expect(searchCompletionForQuery('tapu k', 'Tapu Koko'), 'Tapu Koko');
      expect(searchCompletionForQuery('mew t', 'Mewtwo'), 'Mewtwo');
      expect(searchCompletionSuffixStart('tapu l', 'Tapu Lele'), 6);
      expect(searchCompletionSuffixStart('mew t', 'Mewtwo'), 4);
      expect(
          searchCompletionForQuery('mew 23 mewt', 'Mewtwo'), 'mew 23 Mewtwo');
      expect(searchCompletionForQuery('mew m', 'Mewtwo'), 'mew Mewtwo');
      expect(searchCompletionForQuery('mega darkr', 'Darkrai'), 'mega Darkrai');
      expect(searchCompletionForQuery('mewtwo', 'Mewtwo'), isEmpty);
      expect(searchCompletionForQuery('mew 232', 'Mewtwo'), isEmpty);
      expect(searchCompletionForQuery('pik', 'Mewtwo'), isEmpty);
    });

    test('autocomplete context keeps bounded ids and typed depth scores only',
        () {
      final context = SearchAutocompleteContext.fromJson({
        'query': 'pi',
        'language': 'en',
        'card_ids': [
          for (var index = 1; index <= 1005; index += 1) '$index',
          '2',
        ],
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        'strategy': 'name_table_direct',
        'non_name_context': {
          'depth_scores': {
            '1': 999,
            '2': '7',
            '1000': 4,
            '1001': 8,
            'missing': 3,
          },
          'depth_unit': 'meaningful_query_character',
        },
      });

      expect(context.cardIds, hasLength(1005));
      expect(context.cardIds.take(3), ['1', '2', '3']);
      expect(context.cardIds.last, '1005');
      expect(context.depthScores, {
        '1': 512,
        '2': 7,
        '1000': 4,
        '1001': 8,
      });
      expect(
        (context.toJson()['non_name_context'] as Map)['depth_scores'],
        {'1': 512, '2': 7, '1000': 4, '1001': 8},
      );
      expect(context.toJson()['card_ids'], hasLength(1005));
    });

    test('autocomplete context parses large lightweight ladder metadata', () {
      final context = SearchAutocompleteContext.fromJson({
        'query': 'pi',
        'language': 'en',
        'card_ids': [
          for (var index = 1; index <= 5000; index += 1) '$index',
          'overflow',
        ],
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        'strategy': 'name_table_direct',
        'candidate_id_ladder': {
          'depth': 2,
          'requestedLimit': 5000,
          'appliedLimit': 5000,
          'safeCap': 5000,
        },
        'non_name_context': {
          'depth_scores': {'1': 2, '5000': 2},
          'latest_depths': {'1': 2, '5000': 2},
          'latest_orders': {'1': 0, '5000': 4999},
        },
        'candidate_labels': [
          for (var index = 1; index <= 5000; index += 1)
            {'id': '$index', 'name': 'Pikachu $index'},
        ],
      });

      expect(context.cardIds, hasLength(5000));
      expect(context.candidateIdLadder['requestedLimit'], 5000);
      expect(context.candidateIdLadder['appliedLimit'], 5000);
      expect(context.latestDepths['5000'], 2);
      expect(context.latestOrders['5000'], 4999);
      expect(context.candidateLabels, hasLength(5000));
      expect(context.toJson()['card_ids'], hasLength(5000));
    });

    test('lightweight fallback keeps close Pikachu rows while loading', () {
      final context = SearchAutocompleteContext.fromJson({
        'query': 'pika',
        'language': 'en',
        'card_ids': ['1', '2', '3'],
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        'strategy': 'ranked_pool',
        'non_name_context': {
          'depth_scores': {'1': 8, '2': 4, '3': 1},
        },
        'candidate_labels': [
          {'id': '1', 'name': 'Pikachu'},
          {'id': '2', 'name': 'Pikachu ex'},
          {'id': '3', 'name': "Ash's Pikachu"},
        ],
      });

      final rows = searchPreviewFallbackRowsForTest(
        query: 'pikachu',
        context: context,
      );

      expect(rows.map((card) => card.name), ['Pikachu', 'Pikachu ex']);
      expect(rows.every((card) => card.imageUrl.isEmpty), isTrue);
    });

    test('lightweight fallback preserves ranked context order', () {
      final rows = searchPreviewFallbackRowsForTest(
        query: 'pikachu',
        context: _contextForLabels(
          'pikachu',
          const [
            SearchCandidateLabel(id: '165', name: 'Pikachu & Zekrom GX'),
            SearchCandidateLabel(id: '186', name: 'Pikachu & Zekrom GX'),
            SearchCandidateLabel(id: '25', name: 'Pikachu'),
          ],
          latestDepth: 6,
        ),
      );

      expect(rows.map((card) => card.name).take(3), [
        'Pikachu & Zekrom GX',
        'Pikachu & Zekrom GX',
        'Pikachu',
      ]);
    });

    test('numeric typo query renders ranked context labels instead of skeleton',
        () {
      final context = SearchAutocompleteContext.fromJson({
        'query': 'mee 2',
        'language': 'en',
        'card_ids': ['274416', '320660', '251471'],
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        'strategy': 'typed_predictive_ngrams',
        'non_name_context': {
          'depth_scores': {'274416': 8, '320660': 7, '251471': 6},
          'latest_depths': {'274416': 4, '320660': 4, '251471': 4},
          'latest_orders': {'274416': 0, '320660': 1, '251471': 2},
        },
        'candidate_labels': [
          {
            'id': '274416',
            'name': 'Mew ex',
            'set_name': 'Paldean Fates',
            'card_number': '232/091',
          },
          {
            'id': '320660',
            'name': 'Mew V',
            'set_name': 'World Championship Decks 2023',
            'card_number': '113/264',
          },
          {
            'id': '251471',
            'name': 'Mew ex',
            'set_name': 'Pokemon Card 151',
            'card_number': '232/165',
          },
        ],
      });

      final rows = searchPreviewFallbackRowsForTest(
        query: 'mee 232',
        retainedRows: [
          _searchCard(id: 'hot-1', name: 'Charizard', number: '006/165'),
        ],
        context: context,
      );

      expect(rows.map((card) => card.id), ['274416', '251471']);
      expect(rows.first.name, 'Mew ex');
      expect(rows.first.number, '232/091');
      expect(rows.map((card) => card.id), isNot(contains('hot-1')));
    });

    test('numeric query without ranked ids does not use unrelated hot rows',
        () {
      final rows = searchPreviewFallbackRowsForTest(
        query: 'mee 232',
        retainedRows: [
          _searchCard(id: 'hot-1', name: 'Charizard', number: '006/165'),
          _searchCard(id: 'hot-2', name: 'Pikachu', number: '025/165'),
        ],
      );

      expect(rows, isEmpty);
    });

    test('lightweight fallback does not rerank context by depth hints', () {
      final rows = searchPreviewFallbackRowsForTest(
        query: 'pikachu',
        context: SearchAutocompleteContext.fromJson({
          'query': 'pikachu',
          'language': 'en',
          'card_ids': ['1', '2', '3'],
          'created_at_ms': DateTime.now().millisecondsSinceEpoch,
          'strategy': 'ranked_pool',
          'non_name_context': {
            'depth_scores': {'1': 20, '2': 3, '3': 4},
            'latest_depths': {'1': 2, '2': 3, '3': 4},
            'latest_orders': {'1': 0, '2': 0, '3': 0},
          },
          'candidate_labels': [
            {'id': '1', 'name': 'Pikachu From Depth Two'},
            {'id': '2', 'name': 'Pikachu From Depth Three'},
            {'id': '3', 'name': 'Pikachu From Depth Four'},
          ],
        }),
        latestDepths: const {'1': 2, '2': 3, '3': 4},
        depthScores: const {'1': 20, '2': 3, '3': 4},
        latestOrders: const {'1': 0, '2': 0, '3': 0},
      );

      expect(rows.map((card) => card.id), ['1', '2', '3']);
    });

    test('multi-token fallback drops unmatched short refinements', () {
      final rows = searchPreviewFallbackRowsForTest(
        query: 'pikachu g',
        context: _contextForLabels(
          'pikachu g',
          const [
            SearchCandidateLabel(id: '1', name: 'Pikachu'),
            SearchCandidateLabel(id: '2', name: 'Raichu'),
          ],
          latestDepth: 2,
        ),
      );

      expect(rows, isEmpty);
    });

    test('multi-token fallback ranks variation prefixes first', () {
      final retainedRows = [
        _searchCard(id: '1', name: 'Mimikyu'),
        _searchCard(id: '2', name: 'Mimikyu ex'),
        _searchCard(id: '3', name: 'Mimikyu', set: 'EX Sandstorm'),
        _searchCard(id: '4', name: 'Mimikyu GX'),
      ];
      final rows = searchPreviewFallbackRowsForTest(
        query: 'mimikyu e',
        retainedRows: retainedRows,
        context: _contextForCards('mimikyu e', retainedRows),
      );

      expect(rows.map((card) => card.name), ['Mimikyu ex']);
    });

    test('mega d ranked rows stay visible through mega dar pending', () {
      final retainedRows = [
        _searchCard(id: '1', name: 'Mega Dragonite ex'),
        _searchCard(id: '2', name: 'Mega Dragalge ex'),
        _searchCard(id: '3', name: 'Mega Diancie ex'),
      ];
      final rows = searchPreviewFallbackRowsForTest(
        query: 'mega dar',
        retainedRows: retainedRows,
        context: _contextForCards('mega d', retainedRows),
      );

      expect(rows.map((card) => card.id), ['1', '2', '3']);
    });

    test('multi-token fallback handles longer variation prefixes', () {
      final retainedRows = [
        _searchCard(id: '1', name: 'Pikachu', set: 'VMAX Climax'),
        _searchCard(id: '2', name: 'Pikachu VMAX'),
        _searchCard(id: '3', name: 'Pikachu V'),
      ];
      final rows = searchPreviewFallbackRowsForTest(
        query: 'pikachu vm',
        retainedRows: retainedRows,
        context: _contextForCards('pikachu vm', retainedRows),
      );

      expect(rows.map((card) => card.name), ['Pikachu VMAX']);
    });

    test('multi-token fallback requires completed variation tokens', () {
      final retainedRows = [
        _searchCard(id: '1', name: 'Mimikyu'),
        _searchCard(id: '2', name: 'Mimikyu ex'),
        _searchCard(id: '3', name: 'Mimikyu', set: 'EX Sandstorm'),
        _searchCard(id: '4', name: 'Mimikyu GX'),
      ];
      final rows = searchPreviewFallbackRowsForTest(
        query: 'mimikyu ex',
        retainedRows: retainedRows,
        context: _contextForCards('mimikyu ex', retainedRows),
      );

      expect(rows.map((card) => card.name), ['Mimikyu ex']);
    });

    test('variation boost recomputes when the suffix changes', () {
      final retainedRows = [
        _searchCard(id: '1', name: 'Mimikyu'),
        _searchCard(id: '2', name: 'Mimikyu ex'),
        _searchCard(id: '3', name: 'Mimikyu GX'),
      ];

      final exRows = searchPreviewFallbackRowsForTest(
        query: 'mimikyu e',
        retainedRows: retainedRows,
        context: _contextForCards('mimikyu e', retainedRows),
      );
      final gxRows = searchPreviewFallbackRowsForTest(
        query: 'mimikyu g',
        retainedRows: retainedRows,
        context: _contextForCards('mimikyu g', retainedRows),
      );

      expect(exRows.map((card) => card.name), ['Mimikyu ex']);
      expect(gxRows.map((card) => card.name), ['Mimikyu GX']);
    });

    test('single-token fallback keeps real short card and trainer names', () {
      final nRows = searchPreviewFallbackRowsForTest(
        query: 'n',
        retainedRows: [
          _searchCard(id: '1', name: 'N'),
          _searchCard(id: '2', name: 'Ninetales'),
          _searchCard(id: '3', name: 'Nest Ball'),
        ],
        context: _contextForLabels(
          'n',
          const [
            SearchCandidateLabel(id: '1', name: 'N'),
            SearchCandidateLabel(id: '2', name: 'Ninetales'),
            SearchCandidateLabel(id: '3', name: 'Nest Ball'),
          ],
          latestDepth: 1,
        ),
      );
      final azRows = searchPreviewFallbackRowsForTest(
        query: 'az',
        retainedRows: [
          _searchCard(id: '4', name: 'AZ'),
          _searchCard(id: '5', name: 'Azumarill'),
          _searchCard(id: '6', name: 'Gardevoir ex'),
        ],
        context: _contextForLabels(
          'az',
          const [
            SearchCandidateLabel(id: '4', name: 'AZ'),
            SearchCandidateLabel(id: '5', name: 'Azumarill'),
            SearchCandidateLabel(id: '6', name: 'Gardevoir ex'),
          ],
          latestDepth: 2,
        ),
      );

      expect(nRows.map((card) => card.name), ['N']);
      expect(azRows.map((card) => card.name), ['AZ']);
    });

    test('numeric fallback preserves compatible ranked context order', () {
      final retainedRows = [
        _searchCard(id: '1', name: 'Mew', number: '216/091'),
        _searchCard(id: '2', name: 'Mew ex', number: '053/091'),
        _searchCard(id: '3', name: 'Mew ex', number: '216/091'),
        _searchCard(id: '4', name: 'Mew ex', set: 'EX Sandstorm'),
      ];
      final rows = searchPreviewFallbackRowsForTest(
        query: 'mew ex 216',
        retainedRows: retainedRows,
        context: _contextForCards('mew ex 216', retainedRows),
      );

      expect(rows.map((card) => card.id), ['3']);
    });

    test('fallback hierarchy uses set token after higher priority layers', () {
      final retainedRows = [
        _searchCard(id: '1', name: 'Mew', set: 'Pokemon 151'),
        _searchCard(id: '2', name: 'Mew', set: 'Paldean Fates'),
      ];
      final rows = searchPreviewFallbackRowsForTest(
        query: 'mew paldean',
        retainedRows: retainedRows,
        context: _contextForCards('mew paldean', retainedRows),
      );

      expect(rows.map((card) => card.id), ['2']);
    });

    test('Rare Candy alias fallback does not keep stale generic pool first',
        () {
      final retainedRows = [
        _searchCard(
          id: 'generic-1',
          name: 'Rare Candy',
          set: 'Metagross Expert Deck',
          number: '009/014',
        ),
        _searchCard(
          id: 'generic-2',
          name: 'Rare Candy',
          set: 'Scarlet & Violet JP: Premium Trainer Box ex',
          number: '003/028',
        ),
        _searchCard(
          id: 'hgss-1',
          name: 'Rare Candy',
          set: 'Unleashed',
          number: '82/95',
        ),
      ];

      for (final query in [
        'rare candy heartgold',
        'rare candy heart gold',
        'rare candy hgss',
        'rare candy unleashed',
        'rare candy 82/95',
      ]) {
        final rows = searchPreviewFallbackRowsForTest(
          query: query,
          retainedRows: retainedRows,
          context: _contextForCards('rare candy', retainedRows),
        );

        expect(rows.first.id, 'hgss-1', reason: query);
        expect(rows.first.set, 'Unleashed', reason: query);
        expect(rows.first.number, '82/95', reason: query);
      }
    });

    test('compound tag-team names need typed second root to outrank standalone',
        () {
      final service = CardService();
      final cards = [
        _searchCard(
          id: 'tag-team',
          name: 'Umbreon & Darkrai GX',
          set: 'Unified Minds',
        ),
        _searchCard(id: 'standalone', name: 'Umbreon', set: 'Unleashed'),
        _searchCard(id: 'variant', name: 'Umbreon VMAX', set: 'Evolving Skies'),
        _searchCard(
            id: 'darkrai-cresselia', name: 'Darkrai & Cresselia LEGEND'),
      ];

      expect(
        service.rankSearchCandidatesForTest(cards, 'umbreon').first.id,
        'standalone',
      );
      expect(
        service
            .rankSearchCandidatesForTest(cards, 'umbreon unleashed')
            .first
            .id,
        'standalone',
      );
      expect(
        service.rankSearchCandidatesForTest(cards, 'umbreon darkrai').first.id,
        'tag-team',
      );
      expect(
        service
            .rankSearchCandidatesForTest(cards, 'darkrai cresselia')
            .first
            .id,
        'darkrai-cresselia',
      );
    });

    test('fallback hierarchy supports rarity abbreviations', () {
      final retainedRows = [
        _searchCard(id: '1', name: 'Mew ex', rarity: 'Double Rare'),
        _searchCard(
          id: '2',
          name: 'Mew ex',
          rarity: 'Special Illustration Rare',
        ),
      ];
      final rows = searchPreviewFallbackRowsForTest(
        query: 'mew sir',
        retainedRows: retainedRows,
        context: _contextForCards('mew sir', retainedRows),
      );

      expect(rows.map((card) => card.id), ['2']);
    });

    test('fallback hierarchy treats owners as card variation identity', () {
      final retainedRows = [
        _searchCard(id: '1', name: 'Pikachu'),
        _searchCard(
          id: '2',
          name: "Ash's Pikachu",
          trainerName: 'Ash',
        ),
        _searchCard(id: '3', name: "Rocket's Pikachu"),
      ];
      final rows = searchPreviewFallbackRowsForTest(
        query: 'pikachu ash',
        retainedRows: retainedRows,
        context: _contextForCards('pikachu ash', retainedRows),
      );

      expect(rows.map((card) => card.id), ['2']);
    });

    test('retained rows without ranked context stay hidden after typing', () {
      final rows = searchPreviewFallbackRowsForTest(
        query: 'pikachu',
        retainedRows: [
          _searchCard(id: '1', name: 'Charizard'),
          _searchCard(id: '2', name: "Ash's Pikachu"),
          _searchCard(id: '3', name: 'Pikachu'),
        ],
      );

      expect(rows, isEmpty);
    });

    test('full backend rows replace lightweight fallback contents', () {
      final fallback = searchPreviewFallbackRowsForTest(
        query: 'pikachu',
        context: _contextForLabels(
          'pikachu',
          const [
            SearchCandidateLabel(id: '1', name: 'Pikachu'),
          ],
          latestDepth: 3,
        ),
      );
      final backend = remoteSearchResultsForTest([
        _searchCard(
          id: '1',
          name: 'Pikachu',
          set: 'Base Set',
          number: '58/102',
        ),
      ]);

      expect(fallback.single.imageUrl, isEmpty);
      expect(backend.single.imageUrl, isNotEmpty);
      expect(backend.single.set, 'Base Set');
    });

    test('lightweight fallback renders only top twenty rows', () {
      final labels = [
        for (var index = 1; index <= 50; index += 1)
          SearchCandidateLabel(id: '$index', name: 'Pikachu $index'),
      ];
      final rows = searchPreviewFallbackRowsForTest(
        query: 'pikachu',
        context: _contextForLabels('pikachu', labels, latestDepth: 3),
      );

      expect(rows, hasLength(searchPreviewLimit));
      expect(rows.last.id, '$searchPreviewLimit');
    });

    test('autocomplete preview rows materialize only the visible cap', () {
      final service = CardService();
      final rows = [
        for (var index = 1; index <= 50; index += 1)
          {
            'card_id': '$index',
            'name': 'Backend ranked $index',
            'set_name': 'Test Set',
            'card_number': '$index/100',
            'rarity': 'Card',
            'card_type': 'Pokemon',
          },
      ];

      final cards = service.searchAutocompletePreviewCardsFromRowsForTest(rows);

      expect(cards, hasLength(searchPreviewLimit));
      expect(cards.first.id, '1');
      expect(cards.last.id, '$searchPreviewLimit');
    });

    test(
        'autocomplete response derives context from rows when card ids omitted',
        () {
      final previews = [
        _searchCard(id: '1', name: 'Mega Dragonite ex'),
        _searchCard(id: '2', name: 'Mega Dragalge ex'),
      ];
      final context = autocompleteContextFromResponseForTest(
        context: SearchAutocompleteContext.fromJson({
          'query': 'mega d',
          'language': 'en',
          'card_ids': const [],
          'created_at_ms': DateTime.now().millisecondsSinceEpoch,
          'strategy': 'typed_predictive_ngrams',
        }),
        previews: previews,
        query: 'mega d',
      );

      expect(context?.cardIds, ['1', '2']);
      expect(context?.candidateLabels.map((label) => label.name), [
        'Mega Dragonite ex',
        'Mega Dragalge ex',
      ]);
    });
  });

  group('empty focus preview', () {
    test('caps rendered hot cache and prepends two recent blueprints', () {
      final hotCards = List.generate(
        100,
        (index) => _searchCard(
          id: '${index + 1}',
          name: 'Hot ${index + 1}',
        ),
      );
      final recentViews = [
        RecentCardView.fromCard(hotCards[5], DateTime(2026, 5, 21, 11, 2)),
        RecentCardView(
          cardId: 'sealed-1',
          name: 'Elite Trainer Box',
          expansion: 'Test Set',
          number: '',
          imageUrl: 'https://cdn.pokoin.com/cards/sealed-1.png',
          previewImageUrl: 'https://cdn.pokoin.com/cards/sealed-1.png',
          homepageImageUrl:
              'https://cdn.pokoin.com/cards/sealed-1_homepage.webp',
          viewedAt: DateTime(2026, 5, 21, 11),
          itemKind: 'product',
          productType: 'elite_trainer_box',
        ),
        RecentCardView.fromCard(hotCards[6], DateTime(2026, 5, 21, 10)),
      ];

      final previews = emptyFocusPreviewsForTest(hotCards, recentViews);

      expect(previews, hasLength(searchPreviewLimit));
      expect(previews[0].id, '6');
      expect(previews[1].id, 'sealed-1');
      expect(previews[1].itemKind, 'product');
      expect(previews[1].productType, 'elite_trainer_box');
      expect(
        previews[1].homepageImageUrl,
        'https://cdn.pokoin.com/cards/sealed-1_homepage.webp',
      );
      expect(previews[2].id, '1');
      expect(
          previews.map((card) => card.id).toSet(), hasLength(previews.length));
      expect(previews.last.id, '19');
    });

    test('provider uses local data on empty focus without service calls', () {
      final service = _CountingCardService();
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.cacheCards([
        _searchCard(id: '1', name: 'Cached Pikachu'),
        _searchCard(id: '2', name: 'Cached Charizard'),
      ]);
      notifier.showHotSearchPreviewsForEmptyFocus();

      expect(notifier.state.previewQuery, isEmpty);
      expect(notifier.state.isSearchingPreviews, isFalse);
      expect(notifier.state.searchPreviews.map((card) => card.id), ['1', '2']);
      expect(service.hotCalls, 0);
      expect(service.autocompleteCalls, 0);
      expect(service.autocompleteWithContextCalls, 0);
    });

    test('typed query retains empty hot previews while backend is pending', () {
      final service = _CountingCardService();
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.cacheCards([
        _searchCard(id: '1', name: "Ash's Pikachu"),
        _searchCard(id: '2', name: 'Pidgey'),
      ]);
      notifier.showHotSearchPreviewsForEmptyFocus();

      notifier.searchPreviewsOnly('pika');

      expect(notifier.state.previewQuery, 'pika');
      expect(notifier.state.isSearchingPreviews, isTrue);
      expect(notifier.state.searchPreviews.map((card) => card.id), ['1', '2']);
    });

    test('typed query uses ranked context fallback while loading', () async {
      final service = _CountingCardService(
        autocompleteCards: [_searchCard(id: '10', name: 'Remote Pikachu')],
        autocompleteContext: _contextForLabels(
          'pik',
          const [
            SearchCandidateLabel(id: '10', name: 'Remote Pikachu'),
            SearchCandidateLabel(id: '20', name: 'Pikachu Context'),
          ],
          latestDepth: 3,
        ),
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.cacheCards([
        _searchCard(id: '1', name: 'Pikachu'),
        _searchCard(id: '2', name: 'Pidgey'),
        _searchCard(id: '3', name: "Ash's Pikachu"),
      ]);
      notifier.showHotSearchPreviewsForEmptyFocus();

      notifier.searchPreviewsOnly('pik');
      await Future<void>.delayed(const Duration(milliseconds: 180));
      notifier.searchPreviewsOnly('pika');

      expect(notifier.state.searchPreviews.map((card) => card.name), [
        'Remote Pikachu',
        'Pikachu Context',
      ]);
      expect(notifier.state.isSearchingPreviews, isTrue);
    });

    test('typed preview keeps last ranked pool until new rows arrive',
        () async {
      final service = _SequenceCardService(
        responseDelay: const Duration(milliseconds: 80),
        responses: {
          'pika': _AutocompleteFixture(
            cards: [
              _searchCard(id: 'old-1', name: 'Pikachu'),
              _searchCard(id: 'old-2', name: 'Pikachu ex'),
            ],
            context: _contextForLabels(
              'pika',
              const [
                SearchCandidateLabel(id: 'old-1', name: 'Pikachu'),
                SearchCandidateLabel(id: 'old-2', name: 'Pikachu ex'),
              ],
              latestDepth: 4,
            ),
          ),
          'pikac': _AutocompleteFixture(
            cards: [_searchCard(id: 'new-1', name: 'Pikachu VMAX')],
            context: _contextForLabels(
              'pikac',
              const [
                SearchCandidateLabel(id: 'new-1', name: 'Pikachu VMAX'),
              ],
              latestDepth: 5,
            ),
          ),
        },
      );
      final notifier = CardNotifier(cardService: service, autoLoad: false);
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('pika');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(notifier.state.searchPreviews.map((card) => card.id), [
        'old-1',
        'old-2',
      ]);

      notifier.searchPreviewsOnly('pikac');

      expect(notifier.state.isSearchingPreviews, isTrue);
      expect(notifier.state.searchPreviews.map((card) => card.id), [
        'old-1',
        'old-2',
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(notifier.state.isSearchingPreviews, isFalse);
      expect(notifier.state.searchPreviews.map((card) => card.id), ['new-1']);
    });

    test('typed previews use precise autocomplete service only', () async {
      final service = _CountingCardService(
        autocompleteCards: [_searchCard(id: '10', name: 'Remote Pikachu')],
        autocompleteContext: _contextForLabels(
          'pika',
          const [SearchCandidateLabel(id: '10', name: 'Remote Pikachu')],
          latestDepth: 4,
        ),
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('pika');
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(service.autocompleteCalls, 0);
      expect(service.autocompleteWithContextCalls, 1);
      expect(service.lastAutocompleteQuery, 'pika');
      expect(notifier.state.isSearchingPreviews, isFalse);
      expect(notifier.state.searchPreviews.map((card) => card.id), ['10']);
    });

    test('typed previews render rows when backend context is omitted',
        () async {
      final service = _CountingCardService(
        autocompleteCards: [
          _searchCard(id: '1', name: 'Broad Pikachu'),
          _searchCard(id: '2', name: 'Broader Pikachu ex'),
        ],
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('pikachu');
      expect(notifier.state.isSearchingPreviews, isTrue);
      expect(notifier.state.searchPreviews, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(service.autocompleteCalls, 0);
      expect(service.autocompleteWithContextCalls, 1);
      expect(notifier.state.isSearchingPreviews, isFalse);
      expect(notifier.state.searchPreviews.map((card) => card.id), ['1', '2']);
    });

    test('search exit clears retained backend pool', () async {
      final service = _SequenceCardService(
        responseDelay: const Duration(milliseconds: 40),
        responses: {
          'p': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'p',
              const [SearchCandidateLabel(id: '25', name: 'Pikachu')],
              latestDepth: 1,
            ),
          ),
        },
      );
      final notifier = CardNotifier(cardService: service, autoLoad: false);
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('p');
      await Future<void>.delayed(const Duration(milliseconds: 180));
      notifier.exitSearch(reason: 'blur');
      notifier.searchPreviewsOnly('pik');

      expect(notifier.state.searchPreviews, isEmpty);
      expect(notifier.state.isSearchingPreviews, isTrue);
    });

    test('new search path does not reuse unrelated retained pool', () async {
      final service = _SequenceCardService(
        responseDelay: const Duration(milliseconds: 40),
        responses: {
          'p': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'p',
              const [SearchCandidateLabel(id: '25', name: 'Pikachu')],
              latestDepth: 1,
            ),
          ),
        },
      );
      final notifier = CardNotifier(cardService: service, autoLoad: false);
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('p');
      await Future<void>.delayed(const Duration(milliseconds: 180));
      notifier.searchPreviewsOnly('char');

      expect(notifier.state.searchPreviews, isEmpty);
      expect(notifier.state.searchCompletion, isEmpty);
      expect(service.cancelCalls, 1);
      expect(service.lastCancelReason, 'query_branch');
    });

    test('exit sends cancel and prevents stale previews from rendering',
        () async {
      final service = _CountingCardService(
        autocompleteCards: [_searchCard(id: '10', name: 'Remote Pikachu')],
        autocompleteDelay: const Duration(milliseconds: 80),
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('pika');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      notifier.exitSearch(reason: 'blur');
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(service.cancelCalls, 1);
      expect(service.lastCancelReason, 'blur');
      expect(service.lastCancelQuery, 'pika');
      expect(service.lastAutocompleteSearchSessionId, isNotEmpty);
      expect(
        service.lastCancelSessionId,
        service.lastAutocompleteSearchSessionId,
      );
      expect(notifier.state.previewQuery, isEmpty);
      expect(notifier.state.searchPreviews, isEmpty);
      expect(notifier.state.isSearchingPreviews, isFalse);
    });

    test('typed previews render only the visible cap from remote cards',
        () async {
      final cards = [
        for (var index = 1; index <= 50; index += 1)
          _searchCard(id: '$index', name: 'Pikachu $index'),
      ];
      final service = _CountingCardService(
        autocompleteCards: cards,
        autocompleteContext: _contextForCards('pika', cards),
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('pika');
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(notifier.state.searchPreviews, hasLength(searchPreviewLimit));
      expect(notifier.state.searchPreviews.first.id, '1');
      expect(notifier.state.searchPreviews.last.id, '$searchPreviewLimit');
    });

    test('one and two character typed previews warm silently', () async {
      final service = _CountingCardService(
        autocompleteCards: [_searchCard(id: '10', name: 'Remote Pikachu')],
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('p');
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(service.autocompleteWithContextCalls, 1);
      expect(service.lastAutocompletePoolLimit, searchPreviewHotCacheLimit);
      expect(notifier.state.previewQuery, 'p');
      expect(notifier.state.isSearchingPreviews, isFalse);
      expect(notifier.state.searchPreviews, isEmpty);

      notifier.searchPreviewsOnly('pi');
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(service.autocompleteWithContextCalls, 2);
      expect(service.lastAutocompletePoolLimit, 5000);
      expect(notifier.state.previewQuery, 'pi');
      expect(notifier.state.isSearchingPreviews, isFalse);
      expect(notifier.state.searchPreviews, isEmpty);
      expect(service.autocompleteCalls, 0);
    });

    test('single p uses generated first-char suggestion before network',
        () async {
      final service = _CountingCardService(
        predictedNameTokens: const [
          SearchPredictedNameToken(
            normalized: 'piplup',
            display: 'Piplup',
            confidence: 93,
            source: 'token_predict',
            language: 'en',
          ),
        ],
      )..tokenPredictDelayMs = 120;
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('p');

      expect(notifier.state.searchCompletion, 'Pikachu');
      expect(notifier.state.searchCompletionSource, 'first_char_static');

      await Future<void>.delayed(const Duration(milliseconds: 220));

      expect(service.tokenPredictCalls, 1);
      expect(notifier.state.searchCompletion, 'Piplup');
      expect(notifier.state.searchCompletionSource, 'token_predict');
    });

    test('empty token response keeps compatible ghost completion', () async {
      final service = _SequenceCardService(
        responseDelay: Duration.zero,
        tokenResponses: {
          'mega d': const [
            SearchPredictedNameToken(
              normalized: 'megadiancieex',
              display: 'Mega Diancie ex',
              confidence: 88,
              source: 'token_predict',
              language: 'en',
            ),
          ],
          'mega di': const [],
        },
        responses: {
          'mega d': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'mega d',
              const [
                SearchCandidateLabel(id: '1', name: 'Mega Dragonite ex'),
              ],
              latestDepth: 5,
            ),
          ),
        },
      );
      final notifier = CardNotifier(cardService: service, autoLoad: false);
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('mega d');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(notifier.state.searchCompletion, 'Mega Diancie ex');
      notifier.searchPreviewsOnly('mega di');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(notifier.state.searchCompletion, 'Mega Diancie ex');
    });

    test('backend pool is retained while next character loads', () async {
      final service = _SequenceCardService(
        responseDelay: const Duration(milliseconds: 80),
        responses: {
          'p': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'p',
              const [
                SearchCandidateLabel(id: '25', name: 'Pikachu'),
                SearchCandidateLabel(id: '393', name: 'Piplup'),
              ],
              latestDepth: 1,
            ),
          ),
          'pik': _AutocompleteFixture(
            cards: [_searchCard(id: '25', name: 'Pikachu')],
            context: _contextForLabels(
              'pik',
              const [SearchCandidateLabel(id: '25', name: 'Pikachu')],
              latestDepth: 3,
            ),
          ),
        },
      );
      final notifier = CardNotifier(cardService: service, autoLoad: false);
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('p');
      await Future<void>.delayed(const Duration(milliseconds: 220));

      notifier.searchPreviewsOnly('pik');

      expect(notifier.state.isSearchingPreviews, isTrue);
      expect(notifier.state.searchPreviews.map((card) => card.name), [
        'Pikachu',
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 220));

      expect(notifier.state.searchPreviews.map((card) => card.name), [
        'Pikachu',
      ]);
    });

    test('mega d pool is retained through mega dar pending and empty response',
        () async {
      final service = _SequenceCardService(
        responseDelay: const Duration(milliseconds: 80),
        responses: {
          'mega d': _AutocompleteFixture(
            cards: [
              _searchCard(id: '1', name: 'Mega Dragonite ex'),
              _searchCard(id: '2', name: 'Mega Dragalge ex'),
              _searchCard(id: '3', name: 'Mega Diancie ex'),
            ],
            context: _contextForLabels(
              'mega d',
              const [
                SearchCandidateLabel(id: '1', name: 'Mega Dragonite ex'),
                SearchCandidateLabel(id: '2', name: 'Mega Dragalge ex'),
                SearchCandidateLabel(id: '3', name: 'Mega Diancie ex'),
              ],
              latestDepth: 5,
            ),
          ),
          'mega dar': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'mega dar',
              const [],
              latestDepth: 7,
            ),
          ),
        },
      );
      final notifier = CardNotifier(cardService: service, autoLoad: false);
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('mega d');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      notifier.searchPreviewsOnly('mega dar');

      expect(notifier.state.isSearchingPreviews, isTrue);
      expect(notifier.state.searchPreviews.map((card) => card.id), [
        '1',
        '2',
        '3',
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(notifier.state.isSearchingPreviews, isFalse);
      expect(notifier.state.searchPreviews.map((card) => card.id), [
        '1',
        '2',
        '3',
      ]);
    });

    test(
        'mega dark renders returned backend rows when fallback filter is empty',
        () async {
      final megaD = [
        _searchCard(id: '349110', name: 'Mega Dragonite ex'),
        _searchCard(id: '360096', name: 'Mega Dragonite ex'),
        _searchCard(id: '360108', name: 'Mega Dragonite ex'),
      ];
      final megaDark = [
        _searchCard(id: '363686', name: 'Mega Meganium ex'),
        _searchCard(id: '370649', name: 'Mega Meganium ex'),
        _searchCard(id: '370910', name: 'Mega Meganium ex'),
      ];
      final service = _SequenceCardService(
        responseDelay: const Duration(milliseconds: 80),
        responses: {
          'mega d': _AutocompleteFixture(
            cards: megaD,
            context: _contextForCards('mega d', megaD),
          ),
          'mega da': _AutocompleteFixture(
            cards: megaDark,
            context: _contextForCards('mega da', megaDark),
          ),
          'mega dar': _AutocompleteFixture(
            cards: megaDark,
            context: _contextForCards('mega dar', megaDark),
          ),
          'mega dark': _AutocompleteFixture(
            cards: megaDark,
            context: _contextForCards('mega dark', megaDark),
          ),
        },
      );
      final notifier = CardNotifier(cardService: service, autoLoad: false);
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('mega d');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      notifier.searchPreviewsOnly('mega da');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      notifier.searchPreviewsOnly('mega dar');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      notifier.searchPreviewsOnly('mega dark');

      expect(notifier.state.isSearchingPreviews, isTrue);
      expect(notifier.state.searchPreviews, isNotEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 220));

      expect(notifier.state.isSearchingPreviews, isFalse);
      expect(notifier.state.searchPreviews.map((card) => card.id), [
        '363686',
        '370649',
        '370910',
      ]);
    });

    test('mega d retained pool clears on branch change', () async {
      final service = _SequenceCardService(
        responseDelay: const Duration(milliseconds: 80),
        responses: {
          'mega d': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'mega d',
              const [
                SearchCandidateLabel(id: '1', name: 'Mega Dragonite ex'),
              ],
              latestDepth: 5,
            ),
          ),
        },
      );
      final notifier = CardNotifier(cardService: service, autoLoad: false);
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('mega d');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      notifier.searchPreviewsOnly('mega z');

      expect(notifier.state.searchPreviews, isEmpty);
      expect(service.cancelCalls, 1);
      expect(service.lastCancelReason, 'query_branch');
    });

    test('third character typed preview becomes visible', () async {
      final service = _CountingCardService(
        autocompleteCards: [_searchCard(id: '10', name: 'Remote Pikachu')],
        autocompleteContext: _contextForLabels(
          'pik',
          const [SearchCandidateLabel(id: '10', name: 'Remote Pikachu')],
          latestDepth: 3,
        ),
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('pik');
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(service.lastAutocompletePoolLimit, 2500);
      expect(notifier.state.previewQuery, 'pik');
      expect(notifier.state.isSearchingPreviews, isFalse);
      expect(notifier.state.searchPreviews.map((card) => card.id), ['10']);
    });

    test(
        'predicted token suggestion updates and accepts only prefix completion',
        () async {
      final service = _CountingCardService(
        autocompleteCards: [_searchCard(id: '150', name: 'Mewtwo')],
        autocompleteContext: _contextForLabels(
          'mewt',
          const [SearchCandidateLabel(id: '150', name: 'Mewtwo')],
          latestDepth: 4,
        ),
        predictedNameTokens: const [
          SearchPredictedNameToken(
            normalized: 'mewtwo',
            display: 'Mewtwo',
            confidence: 93,
            source: 'token_predict',
            language: 'en',
          ),
        ],
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('mewt');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(notifier.state.searchCompletion, 'Mewtwo');
      expect(notifier.state.searchCompletionConfidence, 93);
      expect(notifier.state.searchCompletionSource, 'token_predict');
      expect(service.tokenPredictCalls, 1);
      expect(service.autocompleteWithContextCalls, 0);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final completed = notifier.acceptSearchCompletion('mewt');

      expect(completed, 'Mewtwo');
      expect(notifier.state.searchCompletion, isEmpty);
      expect(notifier.state.previewQuery, 'Mewtwo');
    });

    test('predicted token suggestion completes two-token name phrase',
        () async {
      final service = _CountingCardService(
        autocompleteCards: [_searchCard(id: '786', name: 'Tapu Lele')],
        autocompleteContext: _contextForLabels(
          'tapu l',
          const [SearchCandidateLabel(id: '786', name: 'Tapu Lele')],
          latestDepth: 5,
        ),
        predictedNameTokens: const [
          SearchPredictedNameToken(
            normalized: 'tapulele',
            display: 'Tapu Lele',
            confidence: 92,
            source: 'token_predict',
            language: 'en',
          ),
        ],
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('tapu l');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(notifier.state.searchCompletion, 'Tapu Lele');
      expect(service.tokenPredictCalls, 1);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final completed = notifier.acceptSearchCompletion('tapu l');

      expect(completed, 'Tapu Lele');
      expect(notifier.state.searchCompletion, isEmpty);
      expect(notifier.state.previewQuery, 'Tapu Lele');
      expect(notifier.state.previewQuery, isNot('tapu l Lele'));
    });

    test('single letter predicted token accepts token name not card variant',
        () async {
      final service = _CountingCardService(
        autocompleteCards: [_searchCard(id: '151', name: 'Mew V')],
        autocompleteContext: _contextForLabels(
          'm',
          const [SearchCandidateLabel(id: '151', name: 'Mew V')],
          latestDepth: 1,
        ),
        predictedNameTokens: const [
          SearchPredictedNameToken(
            normalized: 'mew',
            display: 'Mew',
            confidence: 95,
            source: 'token_predict',
            language: 'en',
          ),
        ],
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('m');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(notifier.state.searchCompletion, 'Mew');
      expect(service.tokenPredictCalls, 1);
      expect(service.autocompleteWithContextCalls, 0);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final completed = notifier.acceptSearchCompletion('m');

      expect(completed, 'Mew');
      expect(notifier.state.previewQuery, 'Mew');
      expect(notifier.state.previewQuery, isNot('Mew V'));
    });

    test('fast token prediction appears before full autocomplete pool',
        () async {
      final service = _CountingCardService(
        autocompleteCards: [_searchCard(id: '150', name: 'Mewtwo')],
        autocompleteContext: _contextForLabels(
          'mewt',
          const [SearchCandidateLabel(id: '150', name: 'Mewtwo')],
          latestDepth: 4,
        ),
        predictedNameTokens: const [
          SearchPredictedNameToken(
            normalized: 'mewtwo',
            display: 'Mewtwo',
            confidence: 94,
            source: 'token_predict',
            language: 'en',
          ),
        ],
        autocompleteDelay: const Duration(milliseconds: 180),
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('mewt');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(notifier.state.searchCompletion, 'Mewtwo');
      expect(notifier.state.searchPreviews, isEmpty);
      expect(service.tokenPredictCalls, 1);

      await Future<void>.delayed(const Duration(milliseconds: 240));

      expect(service.autocompleteWithContextCalls, 1);
    });

    test('completion-only typing predicts without preview autocomplete',
        () async {
      final service = _CountingCardService(
        predictedNameTokens: const [
          SearchPredictedNameToken(
            normalized: 'mewtwo',
            display: 'Mewtwo',
            confidence: 94,
            source: 'token_predict',
            language: 'en',
          ),
        ],
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.predictSearchCompletionOnly('mewt');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(notifier.state.previewQuery, 'mewt');
      expect(notifier.state.searchPreviews, isEmpty);
      expect(notifier.state.isSearchingPreviews, isFalse);
      expect(notifier.state.searchCompletion, 'Mewtwo');
      expect(service.tokenPredictCalls, 1);
      expect(service.autocompleteWithContextCalls, 0);
    });

    test('backend preview rows do not replace token-predict completion',
        () async {
      final service = _CountingCardService(
        autocompleteCards: [_searchCard(id: '393', name: 'Piplup')],
        autocompleteContext: SearchAutocompleteContext.fromJson({
          'query': 'pik',
          'language': 'en',
          'card_ids': ['393'],
          'created_at_ms': DateTime.now().millisecondsSinceEpoch,
          'strategy': 'supabase_name_index',
          'non_name_context': {
            'predictive_pool': {
              'predicted_tokens': [
                {
                  'normalized': 'piplup',
                  'display': 'Piplup',
                  'confidence': 93,
                  'source': 'meta.predictive',
                  'language': 'en',
                },
              ],
            },
          },
          'candidate_labels': [
            {'id': '393', 'name': 'Piplup'},
          ],
        }),
        autocompletePredictedNameTokens: const [
          SearchPredictedNameToken(
            normalized: 'piplup',
            display: 'Piplup',
            confidence: 93,
            source: 'meta.predictive',
            language: 'en',
          ),
        ],
        predictedNameTokens: const [
          SearchPredictedNameToken(
            normalized: 'pikachu',
            display: 'Pikachu',
            confidence: 98,
            source: 'token_predict',
            language: 'en',
          ),
        ],
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('pik');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(notifier.state.searchCompletion, 'Pikachu');
      expect(notifier.state.searchCompletionSource, 'token_predict');

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(service.autocompleteWithContextCalls, 1);
      expect(notifier.state.searchCompletion, 'Pikachu');
      expect(notifier.state.searchCompletionSource, 'token_predict');
    });

    test('backend predicted metadata does not create ghost completion',
        () async {
      final service = _CountingCardService(
        autocompleteCards: [_searchCard(id: '393', name: 'Piplup')],
        autocompleteContext: SearchAutocompleteContext.fromJson({
          'query': 'pip',
          'language': 'en',
          'card_ids': ['393'],
          'created_at_ms': DateTime.now().millisecondsSinceEpoch,
          'strategy': 'supabase_name_index',
          'non_name_context': {
            'predictive_pool': {
              'predicted_tokens': [
                {
                  'normalized': 'piplup',
                  'display': 'Piplup',
                  'confidence': 93,
                  'source': 'meta.predictive',
                  'language': 'en',
                },
              ],
            },
          },
          'candidate_labels': [
            {'id': '393', 'name': 'Piplup'},
          ],
        }),
        autocompletePredictedNameTokens: const [
          SearchPredictedNameToken(
            normalized: 'piplup',
            display: 'Piplup',
            confidence: 93,
            source: 'meta.predictive',
            language: 'en',
          ),
        ],
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('pip');
      await Future<void>.delayed(const Duration(milliseconds: 220));

      expect(service.tokenPredictCalls, 1);
      expect(service.autocompleteWithContextCalls, 1);
      expect(
          notifier.state.searchPreviews.map((card) => card.name), ['Piplup']);
      expect(notifier.state.searchCompletion, isEmpty);
      expect(notifier.state.searchCompletionSource, isEmpty);
    });

    test('stale fast token prediction cannot overwrite current query',
        () async {
      final service = _CountingCardService(
        predictedNameTokens: const [
          SearchPredictedNameToken(
            normalized: 'mewtwo',
            display: 'Mewtwo',
            confidence: 94,
            source: 'token_predict',
            language: 'en',
          ),
        ],
      )..tokenPredictDelayMs = 100;
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('mewt');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      notifier.searchPreviewsOnly('pik');
      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(notifier.state.previewQuery, 'pik');
      expect(notifier.state.searchCompletion, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 160));
    });

    test(
        'predicted token suggestion clears on branch change and language change',
        () async {
      final service = _CountingCardService(
        autocompleteCards: [_searchCard(id: '150', name: 'Mewtwo')],
        autocompleteContext: _contextForLabels(
          'mewt',
          const [SearchCandidateLabel(id: '150', name: 'Mewtwo')],
          latestDepth: 4,
        ),
        predictedNameTokens: const [
          SearchPredictedNameToken(
            normalized: 'mewtwo',
            display: 'Mewtwo',
            confidence: 93,
            source: 'meta.predictive',
            language: 'en',
          ),
        ],
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('mewt');
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(notifier.state.searchCompletion, 'Mewtwo');

      notifier.searchPreviewsOnly('pika');
      expect(notifier.state.searchCompletion, isEmpty);

      notifier.searchPreviewsOnly('mewt');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(notifier.state.searchCompletion, 'Mewtwo');

      notifier.setSearchLanguage('fr');
      expect(notifier.state.searchCompletion, isEmpty);
    });

    test('fast token prediction passes previous context while appending',
        () async {
      final service = _CountingCardService(
        predictedNameTokens: const [
          SearchPredictedNameToken(
            normalized: 'pikachu',
            display: 'Pikachu',
            confidence: 96,
            source: 'token_predict',
            language: 'en',
          ),
        ],
      );
      service.tokenPredictionContext = SearchTokenPredictionContext.fromJson({
        'query': 'p',
        'fragment': 'p',
        'normalized_fragment': 'p',
        'language': 'en',
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        'candidates': [
          {'display_token': 'Pikachu', 'normalized_token': 'pikachu'},
          {'display_token': 'Piplup', 'normalized_token': 'piplup'},
        ],
      });
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('p');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(service.lastPreviousPredictionContext, isNull);

      service.tokenPredictionContext = SearchTokenPredictionContext.fromJson({
        'query': 'pi',
        'fragment': 'pi',
        'normalized_fragment': 'pi',
        'language': 'en',
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        'candidates': [
          {'display_token': 'Pikachu', 'normalized_token': 'pikachu'},
        ],
      });
      notifier.searchPreviewsOnly('pi');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(service.lastPreviousPredictionContext?.normalizedFragment, 'p');
    });

    test('autocomplete receives current token prediction context', () async {
      final service = _CountingCardService(
        autocompleteCards: [_searchCard(id: '25', name: 'Pikachu')],
        autocompleteContext: _contextForLabels(
          'pik',
          const [SearchCandidateLabel(id: '25', name: 'Pikachu')],
          latestDepth: 3,
        ),
        predictedNameTokens: const [
          SearchPredictedNameToken(
            normalized: 'pikachu',
            display: 'Pikachu',
            confidence: 96,
            source: 'token_predict',
            language: 'en',
          ),
        ],
      );
      service.tokenPredictionContext = SearchTokenPredictionContext.fromJson({
        'query': 'pi',
        'fragment': 'pi',
        'normalized_fragment': 'pi',
        'language': 'en',
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        'candidates': [
          {'display_token': 'Pikachu', 'normalized_token': 'pikachu'},
        ],
      });
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('pi');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      notifier.searchPreviewsOnly('pik');
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(
          service.lastAutocompletePredictionContext?.normalizedFragment, 'pi');
    });

    test(
        'typed previews render candidate labels when rows are not materialized',
        () async {
      final service = _CountingCardService(
        autocompleteContext: SearchAutocompleteContext.fromJson({
          'query': 'pik',
          'language': 'en',
          'card_ids': ['2', '1'],
          'created_at_ms': DateTime.now().millisecondsSinceEpoch,
          'strategy': 'ranked_pool',
          'non_name_context': {
            'depth_scores': {'1': 9, '2': 4},
            'latest_depths': {'1': 3, '2': 4},
            'latest_orders': {'1': 0, '2': 1},
          },
          'candidate_labels': [
            {'id': '1', 'name': 'Pikachu High Score'},
            {'id': '2', 'name': 'Pikachu Deep Match'},
          ],
        }),
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('pik');
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(notifier.state.isSearchingPreviews, isFalse);
      expect(notifier.state.searchPreviews.map((card) => card.id), ['1', '2']);
      expect(
        notifier.state.searchPreviews.every((card) => card.imageUrl.isEmpty),
        isTrue,
      );
    });

    test('fast name previews cannot overwrite ranked context rows', () async {
      final service = _CountingCardService(
        autocompleteCards: [
          _searchCard(id: '1', name: 'Mimikyu'),
          _searchCard(id: '2', name: 'Mimikyu ex'),
          _searchCard(id: '3', name: 'Mimikyu', set: 'EX Sandstorm'),
        ],
        autocompleteContext: _contextForLabels(
          'mimikyu',
          const [
            SearchCandidateLabel(id: '2', name: 'Mimikyu ex'),
          ],
          latestDepth: 7,
        ),
        autocompleteDelay: const Duration(milliseconds: 250),
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('mimikyu ex');
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(notifier.state.isSearchingPreviews, isTrue);
      expect(notifier.state.searchPreviews, isEmpty);
      expect(service.autocompleteCalls, 0);
      await Future<void>.delayed(const Duration(milliseconds: 260));
      expect(notifier.state.searchPreviews.map((card) => card.name), [
        'Mimikyu ex',
      ]);
    });

    test('fresh rare candy query keeps cached hot previews while pending',
        () async {
      final hotCard = _searchCard(id: 'hot-1', name: 'Charizard ex');
      final rareCandy = _searchCard(
        id: '131642',
        name: 'Rare Candy',
        set: 'Unleashed',
        number: '82/95',
      );
      final service = _MarketplaceWarmupCardService(
        cachedSnapshot: MarketplaceHomeSnapshot(
          cards: [hotCard],
          sections: MarketplaceHomeSections(
            recentlySeenIds: const [],
            bestSellerIds: [hotCard.id],
            featuredIds: const [],
          ),
        ),
      )
        ..autocompleteDelay = const Duration(milliseconds: 250)
        ..autocompleteResponses = {
          'rare candy': _AutocompleteFixture(
            cards: [rareCandy],
            context: _contextForLabels(
              'rare candy',
              const [
                SearchCandidateLabel(
                  id: '131642',
                  name: 'Rare Candy',
                  setName: 'Unleashed',
                  number: '82/95',
                ),
              ],
              latestDepth: 9,
            ),
          ),
        };
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: true,
      );
      addTearDown(notifier.dispose);

      await Future<void>.delayed(Duration.zero);

      notifier.searchPreviewsOnly('rare candy');
      expect(notifier.state.isSearchingPreviews, isTrue);
      expect(notifier.state.searchPreviews.map((card) => card.id), ['hot-1']);

      await Future<void>.delayed(const Duration(milliseconds: 420));

      expect(service.autocompleteWithContextCalls, 1);
      expect(notifier.state.isSearchingPreviews, isFalse);
      expect(notifier.state.searchPreviews.map((card) => card.id), ['131642']);
    });

    test('Flutter 2pikabench warms then renders ranked local fallback',
        () async {
      final service = _SequenceCardService(
        responses: {
          'p': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'p',
              const [
                SearchCandidateLabel(id: '1', name: 'Pikachu'),
                SearchCandidateLabel(id: '2', name: 'Pikachu ex'),
                SearchCandidateLabel(id: '3', name: "Ash's Pikachu"),
                SearchCandidateLabel(id: '4', name: 'Pidgey'),
              ],
              latestDepth: 1,
            ),
          ),
          'pi': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'pi',
              const [
                SearchCandidateLabel(id: '1', name: 'Pikachu'),
                SearchCandidateLabel(id: '2', name: 'Pikachu ex'),
                SearchCandidateLabel(id: '3', name: "Ash's Pikachu"),
                SearchCandidateLabel(id: '4', name: 'Pidgey'),
              ],
              latestDepth: 2,
            ),
          ),
          'pik': _AutocompleteFixture(
            cards: [_searchCard(id: '1', name: 'Pikachu')],
            context: _contextForLabels(
              'pik',
              const [
                SearchCandidateLabel(id: '1', name: 'Pikachu'),
                SearchCandidateLabel(id: '2', name: 'Pikachu ex'),
                SearchCandidateLabel(id: '3', name: "Ash's Pikachu"),
              ],
              latestDepth: 3,
            ),
          ),
          'pika': _AutocompleteFixture(
            cards: [_searchCard(id: '1', name: 'Pikachu')],
            context: _contextForLabels(
              'pika',
              const [
                SearchCandidateLabel(id: '1', name: 'Pikachu'),
                SearchCandidateLabel(id: '2', name: 'Pikachu ex'),
                SearchCandidateLabel(id: '3', name: "Ash's Pikachu"),
              ],
              latestDepth: 4,
            ),
          ),
          'pikac': _AutocompleteFixture(
            cards: [_searchCard(id: '1', name: 'Pikachu')],
            context: _contextForLabels(
              'pikac',
              const [
                SearchCandidateLabel(id: '1', name: 'Pikachu'),
                SearchCandidateLabel(id: '2', name: 'Pikachu ex'),
              ],
              latestDepth: 5,
            ),
          ),
        },
      );
      final notifier = CardNotifier(
        cardService: service,
        autoLoad: false,
      );
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('p');
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(notifier.state.isSearchingPreviews, isFalse);
      expect(notifier.state.searchPreviews, isEmpty);

      notifier.searchPreviewsOnly('pi');
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(notifier.state.isSearchingPreviews, isFalse);
      expect(notifier.state.searchPreviews, isEmpty);

      notifier.searchPreviewsOnly('pik');
      expect(notifier.state.isSearchingPreviews, isTrue);
      expect(notifier.state.searchPreviews.map((card) => card.id).take(3), [
        '1',
        '2',
        '3',
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 180));

      notifier.searchPreviewsOnly('pika');
      expect(notifier.state.searchPreviews.map((card) => card.id).take(3), [
        '1',
        '2',
        '3',
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 180));

      notifier.searchPreviewsOnly('pikac');
      expect(notifier.state.searchPreviews.map((card) => card.id), ['1', '2']);
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(service.autocompleteCalls, 0);
      expect(service.autocompleteWithContextCalls, 5);
      expect(notifier.state.searchPreviews.map((card) => card.id), ['1', '2']);
    });

    test('Flutter prefix pool history uses latest compatible ranked pool',
        () async {
      final service = _SequenceCardService(
        responseDelay: const Duration(milliseconds: 80),
        responses: {
          'p': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'p',
              const [
                SearchCandidateLabel(id: 'p-only', name: 'Pidgey'),
                SearchCandidateLabel(id: 'shared', name: 'Pikachu'),
              ],
              latestDepth: 1,
            ),
          ),
          'pi': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'pi',
              const [
                SearchCandidateLabel(id: 'pi-only', name: 'Pichu'),
                SearchCandidateLabel(id: 'shared', name: 'Pikachu'),
              ],
              latestDepth: 2,
            ),
          ),
          'pik': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'pik',
              const [
                SearchCandidateLabel(id: 'shared', name: 'Pikachu'),
                SearchCandidateLabel(id: 'pik-only', name: "Ash's Pikachu"),
              ],
              latestDepth: 3,
            ),
          ),
          'pika': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'pika',
              const [
                SearchCandidateLabel(id: 'pika-only', name: 'Pikachu ex'),
                SearchCandidateLabel(id: 'shared', name: 'Pikachu'),
              ],
              latestDepth: 4,
            ),
          ),
        },
      );
      final notifier = CardNotifier(cardService: service, autoLoad: false);
      addTearDown(notifier.dispose);

      for (final query in ['p', 'pi', 'pik']) {
        notifier.searchPreviewsOnly(query);
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }

      notifier.searchPreviewsOnly('pika');
      expect(notifier.state.isSearchingPreviews, isTrue);
      expect(notifier.state.searchPreviews.map((card) => card.id), [
        'shared',
        'pik-only',
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(notifier.state.searchPreviews.map((card) => card.id), [
        'pika-only',
        'shared',
      ]);
    });

    test('prefix pool history clears on backspace and language changes',
        () async {
      final service = _SequenceCardService(
        responseDelay: const Duration(milliseconds: 80),
        responses: {
          'pik': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'pik',
              const [
                SearchCandidateLabel(id: '1', name: 'Pikachu'),
              ],
              latestDepth: 3,
            ),
          ),
          'pika': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'pika',
              const [
                SearchCandidateLabel(id: '1', name: 'Pikachu'),
              ],
              latestDepth: 4,
            ),
          ),
        },
      );
      final notifier = CardNotifier(cardService: service, autoLoad: false);
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('pik');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      notifier.searchPreviewsOnly('pika');
      expect(notifier.state.searchPreviews.map((card) => card.id), ['1']);

      notifier.searchPreviewsOnly('pi');
      expect(notifier.state.searchPreviews, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      notifier.searchPreviewsOnly('pik');
      expect(notifier.state.searchPreviews, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 220));
      notifier.searchPreviewsOnly('pika');
      expect(notifier.state.searchPreviews.map((card) => card.id), ['1']);
      notifier.setSearchLanguage('it');
      notifier.searchPreviewsOnly('pikac');
      expect(notifier.state.searchPreviews, isEmpty);
    });

    test('historical prefix pool respects completed variation token', () async {
      final service = _SequenceCardService(
        responseDelay: const Duration(milliseconds: 80),
        responses: {
          'mimikyu': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'mimikyu',
              const [
                SearchCandidateLabel(id: '1', name: 'Mimikyu'),
                SearchCandidateLabel(id: '2', name: 'Mimikyu ex'),
              ],
              latestDepth: 7,
            ),
          ),
          'mimikyu e': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'mimikyu e',
              const [
                SearchCandidateLabel(id: '2', name: 'Mimikyu ex'),
              ],
              latestDepth: 8,
            ),
          ),
        },
      );
      final notifier = CardNotifier(cardService: service, autoLoad: false);
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('mimikyu');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      notifier.searchPreviewsOnly('mimikyu e');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      notifier.searchPreviewsOnly('mimikyu ex');

      expect(notifier.state.searchPreviews.map((card) => card.id), ['2']);
    });

    test('historical prefix pool stays visible for unmatched extension',
        () async {
      final service = _SequenceCardService(
        responseDelay: const Duration(milliseconds: 80),
        responses: {
          'mega': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'mega',
              const [
                SearchCandidateLabel(id: '1', name: 'Mega Meganium ex'),
                SearchCandidateLabel(id: '2', name: 'Mega Turbo'),
              ],
              latestDepth: 4,
            ),
          ),
        },
      );
      final notifier = CardNotifier(cardService: service, autoLoad: false);
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('mega');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      notifier.searchPreviewsOnly('mega dark');

      expect(notifier.state.isSearchingPreviews, isTrue);
      expect(notifier.state.searchPreviews.map((card) => card.id), ['1', '2']);
    });

    test('unmatched extension fallback clears on unrelated branch change',
        () async {
      final service = _SequenceCardService(
        responseDelay: const Duration(milliseconds: 80),
        responses: {
          'mega': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'mega',
              const [
                SearchCandidateLabel(id: '1', name: 'Mega Meganium ex'),
              ],
              latestDepth: 4,
            ),
          ),
        },
      );
      final notifier = CardNotifier(cardService: service, autoLoad: false);
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('mega');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      notifier.searchPreviewsOnly('dark');

      expect(notifier.state.searchPreviews, isEmpty);
      expect(service.cancelCalls, 1);
      expect(service.lastCancelReason, 'query_branch');
    });

    test('historical numeric pool bridges mee 232 while response is pending',
        () async {
      final service = _SequenceCardService(
        responseDelay: const Duration(milliseconds: 80),
        responses: {
          'mee': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'mee',
              const [
                SearchCandidateLabel(
                  id: '274416',
                  name: 'Mew ex',
                  number: '232/091',
                ),
                SearchCandidateLabel(
                  id: '320660',
                  name: 'Mew V',
                  number: '113/264',
                ),
              ],
              latestDepth: 3,
            ),
          ),
          'mee 2': _AutocompleteFixture(
            cards: const [],
            context: _contextForLabels(
              'mee 2',
              const [
                SearchCandidateLabel(
                  id: '274416',
                  name: 'Mew ex',
                  number: '232/091',
                ),
                SearchCandidateLabel(
                  id: '251471',
                  name: 'Mew ex',
                  number: '232/165',
                ),
                SearchCandidateLabel(
                  id: '320660',
                  name: 'Mew V',
                  number: '113/264',
                ),
              ],
              latestDepth: 4,
            ),
          ),
        },
      );
      final notifier = CardNotifier(cardService: service, autoLoad: false);
      addTearDown(notifier.dispose);

      notifier.searchPreviewsOnly('mee');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      notifier.searchPreviewsOnly('mee 2');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      notifier.searchPreviewsOnly('mee 232');

      expect(notifier.state.isSearchingPreviews, isTrue);
      expect(notifier.state.searchPreviews.map((card) => card.id), [
        '274416',
        '251471',
      ]);
    });

    test('candidate ID request ladder halves to a 1000 floor', () {
      expect(searchPreviewCandidateIdLimitForTest('p'),
          searchPreviewHotCacheLimit);
      expect(searchPreviewCandidateIdLimitForTest('pi'), 5000);
      expect(searchPreviewCandidateIdLimitForTest('pik'), 2500);
      expect(searchPreviewCandidateIdLimitForTest('pika'), 1250);
      expect(searchPreviewCandidateIdLimitForTest('pikac'), 500);
      expect(searchPreviewCandidateIdLimitForTest('pikachu'), 500);
    });
  });

  group('similar version filtering', () {
    test('excludes only exact blueprint ids from current versions', () {
      final service = CardService();
      final current = _searchCard(
        id: '100',
        name: 'Pikachu',
        set: 'Base Set',
        number: '58/102',
      );
      final versions = [
        current,
        _searchCard(
          id: '101',
          name: 'Pikachu',
          set: 'Base Set',
          number: '58a/102',
        ),
      ];
      final similar = [
        _searchCard(id: '101', name: 'Pikachu', set: 'Base Set'),
        _searchCard(id: '1000', name: 'Pikachu', set: 'Jungle'),
        _searchCard(id: '102', name: 'Raichu', set: 'Base Set'),
      ];

      final filtered = service.excludeSimilarVersionCardsForTest(
        current,
        versions,
        similar,
      );

      expect(filtered.map((card) => card.id), ['1000', '102']);
    });
  });
}

class _CountingCardService extends CardService {
  _CountingCardService({
    this.autocompleteCards = const [],
    this.autocompleteContext,
    this.predictedNameTokens = const [],
    this.autocompletePredictedNameTokens,
    this.autocompleteDelay = Duration.zero,
  });

  final List<PokemonCard> autocompleteCards;
  final SearchAutocompleteContext? autocompleteContext;
  final List<SearchPredictedNameToken> predictedNameTokens;
  final List<SearchPredictedNameToken>? autocompletePredictedNameTokens;
  final Duration autocompleteDelay;
  SearchTokenPredictionContext? tokenPredictionContext;
  int hotCalls = 0;
  int autocompleteCalls = 0;
  int autocompleteWithContextCalls = 0;
  int tokenPredictCalls = 0;
  int tokenPredictDelayMs = 0;
  int cancelCalls = 0;
  String? lastAutocompleteQuery;
  int? lastAutocompletePoolLimit;
  SearchTokenPredictionContext? lastAutocompletePredictionContext;
  String? lastAutocompleteSearchSessionId;
  String? lastTokenPredictQuery;
  SearchTokenPredictionContext? lastPreviousPredictionContext;
  String? lastCancelSessionId;
  String? lastCancelQuery;
  String? lastCancelReason;

  @override
  Future<List<PokemonCard>> getHotMarketplaceCards({
    int limit = 1000,
    String window = '24h',
  }) async {
    hotCalls++;
    return const [];
  }

  @override
  Future<List<PokemonCard>> searchAutocompleteCards(
    String query, {
    int limit = 20,
    int poolLimit = 15874,
    String searchLanguage = 'en',
    String previewMode = '',
    SearchAutocompleteContext? previousSearchContext,
    SearchTokenPredictionContext? predictionContext,
    String? searchSessionId,
  }) async {
    autocompleteCalls++;
    lastAutocompleteQuery = query;
    lastAutocompletePoolLimit = poolLimit;
    lastAutocompletePredictionContext = predictionContext;
    lastAutocompleteSearchSessionId = searchSessionId;
    return autocompleteCards;
  }

  @override
  Future<SearchAutocompleteResult> searchAutocompleteCardsWithContext(
    String query, {
    int limit = 20,
    int poolLimit = 15874,
    String searchLanguage = 'en',
    String previewMode = '',
    SearchAutocompleteContext? previousSearchContext,
    SearchTokenPredictionContext? predictionContext,
    String? searchSessionId,
  }) async {
    autocompleteWithContextCalls++;
    lastAutocompleteQuery = query;
    lastAutocompletePoolLimit = poolLimit;
    lastAutocompletePredictionContext = predictionContext;
    lastAutocompleteSearchSessionId = searchSessionId;
    if (autocompleteDelay > Duration.zero) {
      await Future<void>.delayed(autocompleteDelay);
    }
    return SearchAutocompleteResult(
      cards: autocompleteCards,
      context: autocompleteContext,
      predictedNameTokens:
          autocompletePredictedNameTokens ?? predictedNameTokens,
    );
  }

  @override
  Future<List<SearchPredictedNameToken>> predictSearchNameTokens(
    String query, {
    int limit = 5,
    String searchLanguage = 'en',
    SearchTokenPredictionContext? previousPredictionContext,
  }) async {
    final result = await predictSearchNameTokensWithContext(
      query,
      limit: limit,
      searchLanguage: searchLanguage,
      previousPredictionContext: previousPredictionContext,
    );
    return result.tokens;
  }

  @override
  Future<SearchTokenPredictionResult> predictSearchNameTokensWithContext(
    String query, {
    int limit = 5,
    String searchLanguage = 'en',
    SearchTokenPredictionContext? previousPredictionContext,
  }) async {
    tokenPredictCalls++;
    lastTokenPredictQuery = query;
    lastPreviousPredictionContext = previousPredictionContext;
    if (tokenPredictDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: tokenPredictDelayMs));
    }
    return SearchTokenPredictionResult(
      tokens: predictedNameTokens,
      context: tokenPredictionContext,
    );
  }

  @override
  Future<void> cancelSearchSession({
    required String sessionId,
    required String lastQuery,
    String reason = 'exit',
  }) async {
    cancelCalls++;
    lastCancelSessionId = sessionId;
    lastCancelQuery = lastQuery;
    lastCancelReason = reason;
  }
}

class _AutocompleteFixture {
  const _AutocompleteFixture({
    required this.cards,
    required this.context,
  });

  final List<PokemonCard> cards;
  final SearchAutocompleteContext context;
}

class _SequenceCardService extends CardService {
  _SequenceCardService({
    required this.responses,
    this.tokenResponses = const {},
    this.responseDelay = Duration.zero,
  });

  final Map<String, _AutocompleteFixture> responses;
  final Map<String, List<SearchPredictedNameToken>> tokenResponses;
  final Duration responseDelay;
  int autocompleteCalls = 0;
  int autocompleteWithContextCalls = 0;
  int tokenPredictCalls = 0;
  int cancelCalls = 0;
  String? lastCancelReason;

  @override
  Future<List<PokemonCard>> searchAutocompleteCards(
    String query, {
    int limit = 20,
    int poolLimit = 15874,
    String searchLanguage = 'en',
    String previewMode = '',
    SearchAutocompleteContext? previousSearchContext,
    SearchTokenPredictionContext? predictionContext,
    String? searchSessionId,
  }) async {
    autocompleteCalls++;
    return responses[query]?.cards ?? const [];
  }

  @override
  Future<SearchAutocompleteResult> searchAutocompleteCardsWithContext(
    String query, {
    int limit = 20,
    int poolLimit = 15874,
    String searchLanguage = 'en',
    String previewMode = '',
    SearchAutocompleteContext? previousSearchContext,
    SearchTokenPredictionContext? predictionContext,
    String? searchSessionId,
  }) async {
    autocompleteWithContextCalls++;
    if (responseDelay > Duration.zero) {
      await Future<void>.delayed(responseDelay);
    }
    final fixture = responses[query];
    return SearchAutocompleteResult(
      cards: fixture?.cards ?? const [],
      context: fixture?.context,
    );
  }

  @override
  Future<SearchTokenPredictionResult> predictSearchNameTokensWithContext(
    String query, {
    int limit = 5,
    String searchLanguage = 'en',
    SearchTokenPredictionContext? previousPredictionContext,
  }) async {
    tokenPredictCalls++;
    return SearchTokenPredictionResult(
      tokens: tokenResponses[query] ?? const [],
    );
  }

  @override
  Future<void> cancelSearchSession({
    required String sessionId,
    required String lastQuery,
    String reason = 'exit',
  }) async {
    cancelCalls++;
    lastCancelReason = reason;
  }
}

class _MarketplaceWarmupCardService extends CardService {
  _MarketplaceWarmupCardService({
    this.cachedSnapshot,
    this.snapshot,
  });

  final MarketplaceHomeSnapshot? cachedSnapshot;
  final MarketplaceHomeSnapshot? snapshot;
  final Map<String, PokemonCard> cardsById = {};
  Map<String, _AutocompleteFixture> autocompleteResponses = const {};
  Duration autocompleteDelay = Duration.zero;
  Duration cardByIdDelay = Duration.zero;
  int cachedCardsCalls = 0;
  int cachedSnapshotCalls = 0;
  int cachedSpotlightCalls = 0;
  int marketplaceSnapshotCalls = 0;
  int allCardsCalls = 0;
  int cardByIdCalls = 0;
  int autocompleteWithContextCalls = 0;

  @override
  Future<List<PokemonCard>> getCachedCards() async {
    cachedCardsCalls++;
    return const [];
  }

  @override
  Future<MarketplaceHomeSnapshot?> getCachedMarketplaceHomeSnapshot() async {
    cachedSnapshotCalls++;
    return cachedSnapshot;
  }

  @override
  Future<List<PokemonCard>> getCachedSpotlightCards() async {
    cachedSpotlightCalls++;
    return const [];
  }

  @override
  Future<MarketplaceHomeSnapshot?> getMarketplaceHomeSnapshot() async {
    marketplaceSnapshotCalls++;
    return snapshot;
  }

  @override
  Future<List<PokemonCard>> getAllCards() async {
    allCardsCalls++;
    return const [];
  }

  @override
  Future<PokemonCard?> getCardById(String id) async {
    cardByIdCalls++;
    if (cardByIdDelay > Duration.zero) {
      await Future<void>.delayed(cardByIdDelay);
    }
    return cardsById[id];
  }

  @override
  Future<SearchAutocompleteResult> searchAutocompleteCardsWithContext(
    String query, {
    int limit = 20,
    int poolLimit = 15874,
    String searchLanguage = 'en',
    String previewMode = '',
    SearchAutocompleteContext? previousSearchContext,
    SearchTokenPredictionContext? predictionContext,
    String? searchSessionId,
  }) async {
    autocompleteWithContextCalls++;
    if (autocompleteDelay > Duration.zero) {
      await Future<void>.delayed(autocompleteDelay);
    }
    final fixture = autocompleteResponses[query];
    return SearchAutocompleteResult(
      cards: fixture?.cards ?? const [],
      context: fixture?.context,
    );
  }

  @override
  Future<SearchTokenPredictionResult> predictSearchNameTokensWithContext(
    String query, {
    int limit = 5,
    String searchLanguage = 'en',
    SearchTokenPredictionContext? previousPredictionContext,
  }) async {
    return const SearchTokenPredictionResult();
  }
}

SearchAutocompleteContext _contextForLabels(
  String query,
  List<SearchCandidateLabel> labels, {
  required int latestDepth,
}) {
  return SearchAutocompleteContext.fromJson({
    'query': query,
    'language': 'en',
    'card_ids': labels.map((label) => label.id).toList(),
    'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    'strategy': 'flutter_2pikabench',
    'non_name_context': {
      'depth_scores': {
        for (final label in labels) label.id: latestDepth,
      },
      'latest_depths': {
        for (final label in labels) label.id: latestDepth,
      },
      'latest_orders': {
        for (var index = 0; index < labels.length; index += 1)
          labels[index].id: index,
      },
    },
    'candidate_labels': labels.map((label) => label.toJson()).toList(),
  });
}

SearchAutocompleteContext _contextForCards(
  String query,
  List<PokemonCard> cards,
) {
  return _contextForLabels(
    query,
    [
      for (final card in cards)
        SearchCandidateLabel(
          id: card.id,
          name: card.name,
          setName: card.set,
          number: card.number,
          trainerName: card.trainerName,
          itemKind: card.itemKind,
          productType: card.productType,
        ),
    ],
    latestDepth:
        query.replaceAll(RegExp(r'[^a-z0-9]', caseSensitive: false), '').length,
  );
}
