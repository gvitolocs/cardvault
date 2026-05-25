import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/models/card_listing.dart';
import 'package:pokoin/models/pokemon_card.dart';
import 'package:pokoin/utils/card_navigation.dart';
import 'package:pokoin/utils/card_url.dart';

PokemonCard _card({
  String id = '316600',
  String name = 'Leafeon',
  String number = '005/131',
  String set = 'Prismatic Evolutions',
  String rarity = 'Rare',
}) {
  return PokemonCard(
    id: id,
    name: name,
    imageUrl: 'https://cdn.pokoin.com/cards/$id.png',
    rarity: rarity,
    type: 'Trading card',
    hp: 0,
    attacks: const [],
    price: 1000,
    description: 'URL fixture',
    set: set,
    number: number,
    artist: '',
    stock: 0,
    rating: 0,
    reviewCount: 0,
    isFoil: false,
    isHolo: false,
    releaseDate: DateTime(2026),
    tags: const [],
    condition: 'NM',
    isGraded: false,
  );
}

void main() {
  group('card detail URLs', () {
    test('generated safe path uses public-number marketplace URL', () {
      expect(
        safeCardDetailPath(_card()),
        '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
      );
    });

    test('stored canonical path wins over generated rarity slug', () {
      final card = PokemonCard.fromJson({
        'card_id': '124384',
        'name': 'Drifloon Lv.17',
        'image_url': 'https://cdn.pokoin.com/cards/drifloon.png',
        'rarity': 'Card',
        'set_name': 'POP Series 6',
        'card_number': '6/17',
        'canonical_path':
            '/marketplace/en/cards/248768/uncommon-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
      });

      expect(
        safeCardDetailPath(card),
        '/marketplace/en/cards/248768/uncommon-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
      );
      expect(
        cardDetailSlug(card),
        'uncommon-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
      );
    });

    test('database canonical path wins over generated fallback', () {
      final card = _card(
        id: '248768',
        name: 'Drifloon Lv.17',
        number: '6/17',
        set: 'POP Series 6',
        rarity: 'Card',
      );

      expect(
        safeCardDetailPathWithDatabaseCanonical(
          card,
          databaseCanonicalPath:
              '/marketplace/en/cards/497536/db-backed-drifloon',
        ),
        '/marketplace/en/cards/497536/db-backed-drifloon',
      );
      expect(
        safeCardDetailPathWithDatabaseCanonical(
          card,
          databaseCanonicalPath: '/248768/some-slug',
        ),
        '/marketplace/en/cards/497536/card-drifloon-lv-17-6-17-pop-series-6',
      );
    });

    test('database-backed resolver does not generate rarity fallback',
        () async {
      final card = _card(
        id: '122739',
        name: 'Cresselia Lv.43',
        number: '2/100',
        set: 'Majestic Dawn',
        rarity: 'Holo Rare',
      );

      final path = await resolveDatabaseBackedCardDetailPath(
        card,
        canonicalPathLookup: ({required cardId, required language}) async => '',
      );

      expect(path, isEmpty);
      expect(
        safeCardDetailPath(card),
        '/marketplace/en/cards/245478/holo-rare-cresselia-lv-43-2-100-majestic-dawn',
      );
    });

    test('database-backed resolver uses canonical lookup result', () async {
      final card = _card(
        id: '122739',
        name: 'Cresselia Lv.43',
        number: '2/100',
        set: 'Majestic Dawn',
        rarity: 'Holo Rare',
      );

      final path = await resolveDatabaseBackedCardDetailPath(
        card,
        canonicalPathLookup: ({required cardId, required language}) async {
          expect(cardId, '122739');
          expect(language, 'en');
          return '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn';
        },
      );

      expect(
        path,
        '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn',
      );
    });

    test('tile navigation path uses stored canonical path only', () async {
      final card = _card(
        id: '122739',
        name: 'Cresselia Lv.43',
        number: '2/100',
        set: 'Majestic Dawn',
        rarity: 'Holo Rare',
      ).copyWith(
        canonicalPath:
            '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn',
      );

      final path = await canonicalCardDetailNavigationPath(card);

      expect(
        path,
        '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn',
      );
    });

    test('listing model carries canonical path for inventory navigation', () {
      final listing = CardListing.fromJson('listing-1', {
        'cardId': '316600',
        'sellerUid': 'seller',
        'condition': 'NM',
        'language': 'EN',
        'pricePkn': 1000,
        'quantityAvailable': 1,
        'status': 'active',
        'cardName': 'Leafeon',
        'cardImageUrl': 'https://cdn.pokoin.com/cards/316600.png',
        'setName': 'Prismatic Evolutions',
        'collectorNumber': '005/131',
        'canonicalPath':
            '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
        'publicNumber': '633200',
      });

      final card = _card(
        id: listing.cardId,
        name: listing.cardName,
        number: listing.collectorNumber,
        set: listing.setName,
      ).copyWith(canonicalPath: listing.canonicalPath);

      expect(listing.publicNumber, '633200');
      expect(
        safeCardDetailPath(card),
        '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
      );
    });

    test('safe public path doubles pasted blueprint id', () {
      expect(
        safeCardDetailPath(_card(
          id: '139056',
          name: 'Super Rod',
          number: '',
          set: 'Gold, Silver, to a New World...',
          rarity: 'Common',
        )),
        '/marketplace/en/cards/278112/common-super-rod-gold-silver-to-a-new-world',
      );
    });

    test('legacy marketplace path includes public number and rarity slug', () {
      expect(
        marketplaceCardDetailPath(_card()),
        '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
      );
    });

    test('generated marketplace path includes Fan Rotom collector number', () {
      expect(
        marketplaceCardDetailPath(
          _card(
            id: '316698',
            name: 'Fan Rotom',
            number: '085/131',
            rarity: 'Common',
          ),
        ),
        '/marketplace/en/cards/633396/common-fan-rotom-085-131-prismatic-evolutions',
      );
    });

    test('generated marketplace path reads home snapshot collector fields', () {
      final card = PokemonCard.fromJson({
        'card_id': '316600',
        'name': 'Leafeon',
        'image_url': 'https://cdn.pokoin.com/cards/prismatic-leafeon.png',
        'rarity': 'Rare',
        'card_type': 'Pokemon',
        'set_name': 'Prismatic Evolutions',
        'card_number': '005/131',
      });

      expect(card.number, '005/131');
      expect(card.rarity, 'Rare');
      expect(
        safeCardDetailPath(card),
        '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
      );
    });

    test('versions path uses public number and human slug', () {
      expect(
        marketplaceCardVersionsPath(_card()),
        '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions/versions',
      );
    });

    test('versions path uses stored database canonical path', () {
      final card = PokemonCard.fromJson({
        'card_id': '122739',
        'name': 'Cresselia Lv.43',
        'image_url': 'https://cdn.pokoin.com/cards/cresselia.png',
        'rarity': 'Holo Rare',
        'set_name': 'Majestic Dawn',
        'card_number': '2/100',
        'canonical_path':
            '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn',
      });

      expect(
        marketplaceCardVersionsPath(card),
        '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn/versions',
      );
    });

    test('doubled id helpers decode only valid even ids', () {
      expect(doubledCardId('316600'), '633200');
      expect(cardIdFromDoubledId('633200'), '316600');
      expect(cardIdFromDoubledId('633201'), isEmpty);
      expect(cardIdFromDoubledId('leafeon'), isEmpty);
    });

    test('canonical public-number route parses to real id and slug', () {
      final route = parseMarketplaceCardRoute(
        firstSegment: '633200',
        slugSegment: 'rare-leafeon-005-131-prismatic-evolutions',
      );

      expect(route.cardId, '316600');
      expect(route.cardSlug, 'rare-leafeon-005-131-prismatic-evolutions');
      expect(route.isCanonicalShape, isTrue);
    });

    test('simple marketplace numeric route keeps real card id', () {
      final route = parseMarketplaceCardRoute(firstSegment: '316600');

      expect(route.cardId, '316600');
      expect(route.cardSlug, isNull);
      expect(route.isCanonicalShape, isFalse);
    });

    test('legacy numeric marketplace slug keeps real card id', () {
      final route = parseMarketplaceCardRoute(
        firstSegment: '316600-leafeon-005-131-prismatic-evolutions',
      );

      expect(route.cardId, '316600');
      expect(
        route.cardSlug,
        '316600-leafeon-005-131-prismatic-evolutions',
      );
      expect(route.isCanonicalShape, isFalse);
    });

    test('legacy numeric slugs remain detectable for compatibility', () {
      expect(
        legacyCardDetailSlug(_card()),
        '316600-leafeon-005-131-prismatic-evolutions',
      );
      expect(cardIdFromSlug('316600-leafeon-005-131'), '316600');
      expect(numericCardIdFromSlug('316600-leafeon-005-131'), '316600');
      expect(numericCardIdFromSlug('leafeon-005-131'), isEmpty);
      expect(cardDetailSlugHasNumericId('316600-leafeon-005-131'), isTrue);
      expect(
        cardDetailSlugHasNumericId('rare-leafeon-005-131'),
        isFalse,
      );
    });

    test('slug matching tolerates rarity prefix and collector separators', () {
      expect(
        cardDetailSlugsMatch(
          'common-fan-rotom-085-131-prismatic-evolutions',
          'fan-rotom-085/131-prismatic-evolutions',
        ),
        isTrue,
      );
      expect(
        cardDetailSlugsMatch(
          'card-fan-rotom-085-131-prismatic-evolutions',
          'common-fan-rotom-085-131-prismatic-evolutions',
        ),
        isTrue,
      );
      expect(
        cardDetailSlugsMatch(
          'card-super-rod-gold-silver-to-a-new-world',
          'common-super-rod-gold-silver-to-a-new-world',
        ),
        isTrue,
      );
      expect(
        cardDetailSlugsMatch(
          'common-fan-rotom-085-131-prismatic-evolutions',
          'common-fan-rotom-85-131-prismatic-evolutions',
        ),
        isTrue,
      );
      expect(
        cardDetailSlugsMatch(
          'rare-leafeon-005-131-prismatic-evolutions',
          'rare-leafeon-5-131-prismatic-evolutions',
        ),
        isTrue,
      );
      expect(
        cardDetailSlugsMatch(
          'common-fan-rotom-085-131-prismatic-evolutions',
          'common-fan-rotom-086-131-prismatic-evolutions',
        ),
        isFalse,
      );
    });

    test('root numeric short links stay on the direct root route', () {
      expect(isRootCardShortLink('113046'), isTrue);
      expect(marketplaceCardShortLinkRedirectPath('129834'), '/129834');
      expect(marketplaceCardShortLinkRedirectPath(' 129834 '), '/129834');
    });

    test('root detail paths remain legacy-only while safe paths are canonical',
        () {
      final card = _card(
        id: '124384',
        name: 'Drifloon Lv.17',
        number: '6/17',
        set: 'POP Series 6',
        rarity: 'Card',
      );

      expect(
        rootCardDetailPath(card),
        '/124384/card-drifloon-lv-17-6-17-pop-series-6',
      );
      expect(
        safeCardDetailPath(card),
        '/marketplace/en/cards/248768/card-drifloon-lv-17-6-17-pop-series-6',
      );
    });

    test('legacy root detail matcher identifies routes needing DB canonical',
        () {
      final card = _card(
        id: '248768',
        name: 'Drifloon Lv.17',
        number: '6/17',
        set: 'POP Series 6',
        rarity: 'Uncommon',
      );

      expect(
        isLegacyRootCardDetailPathForCard(
          path: '/248768/some-slug',
          card: card,
        ),
        isTrue,
      );
      expect(
        isLegacyRootCardDetailPathForCard(
          path: '/497536/some-slug',
          card: card,
        ),
        isTrue,
      );
      expect(
        isLegacyRootCardDetailPathForCard(
          path: '/497537/some-slug',
          card: card,
        ),
        isFalse,
      );
      expect(
        isLegacyRootCardDetailPathForCard(path: '/248768', card: card),
        isFalse,
      );
    });

    test('root short link helper ignores non-numeric slugs', () {
      expect(isRootCardShortLink('129834-leafeon'), isFalse);
      expect(marketplaceCardShortLinkRedirectPath('wallet'), isEmpty);
      expect(marketplaceCardShortLinkRedirectPath('129834-leafeon'), isEmpty);
      expect(marketplaceCardShortLinkRedirectPath(''), isEmpty);
    });

    test('router initial location preserves browser card links', () {
      expect(
        browserInitialLocationForRouter(
          Uri.parse(
            'https://pokoin.com/marketplace/en/cards/248768/card-drifloon-lv-17-6-17-pop-series-6',
          ),
        ),
        '/marketplace/en/cards/248768/card-drifloon-lv-17-6-17-pop-series-6',
      );
      expect(
        browserInitialLocationForRouter(
          Uri.parse('https://pokoin.com/129834?utm_source=discord#card'),
        ),
        '/129834?utm_source=discord#card',
      );
      expect(browserInitialLocationForRouter(Uri.file('/tmp/app')), isNull);
    });

    test('router initial location preserves stored canonical card links', () {
      expect(
        browserInitialLocationForRouter(
          Uri.parse(
            'https://pokoin.com/marketplace/en/cards/248768/uncommon-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
          ),
        ),
        '/marketplace/en/cards/248768/uncommon-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
      );
    });

    test('artist route matcher accepts all artist subpages', () {
      expect(
        isMarketplaceArtistRoutePath('/marketplace/en/artists/tomokazu-komiya'),
        isTrue,
      );
      expect(
        isMarketplaceArtistRoutePath(
          '/marketplace/en/artists/tomokazu-komiya/illustration',
        ),
        isTrue,
      );
      expect(
        isMarketplaceArtistRoutePath(
          '/marketplace/en/artists/tomokazu-komiya/full-arts',
        ),
        isTrue,
      );
      expect(
        isMarketplaceArtistRoutePath(
          '/marketplace/en/artists/tomokazu-komiya/normal-cards',
        ),
        isTrue,
      );
      expect(
        isMarketplaceArtistRoutePath(
          '/marketplace/en/artists/tomokazu-komiya/profile',
        ),
        isTrue,
      );
    });

    test('card detail drift guard repairs protected targets unless explicit',
        () {
      const leafeonRoute =
          '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions';
      expect(isMarketplaceCardDetailRoutePath(leafeonRoute), isTrue);
      expect(
        shouldRepairCardDetailRootDrift(
          previousPath: leafeonRoute,
          nextPath: '/',
          lastCardDetailRoute: leafeonRoute,
        ),
        isTrue,
      );
      expect(
        shouldRepairCardDetailRootDrift(
          previousPath: leafeonRoute,
          nextPath: '/marketplace',
          lastCardDetailRoute: leafeonRoute,
        ),
        isTrue,
      );
      expect(
        shouldRepairCardDetailRootDrift(
          previousPath: leafeonRoute,
          nextPath: '/marketplace/en/artists/kuroimori',
          lastCardDetailRoute: leafeonRoute,
        ),
        isTrue,
      );
      expect(
        shouldRepairCardDetailRootDrift(
          previousPath: '/marketplace',
          nextPath: '/marketplace/en/artists/kuroimori',
          lastCardDetailRoute: leafeonRoute,
          cardDetailMounted: true,
        ),
        isTrue,
      );
      expect(
        shouldRepairCardDetailRootDrift(
          previousPath: leafeonRoute,
          nextPath: '/marketplace',
          lastCardDetailRoute: leafeonRoute,
          hasExplicitNavigationIntent: true,
        ),
        isFalse,
      );
      expect(
        shouldRepairCardDetailRootDrift(
          previousPath: leafeonRoute,
          nextPath: '/marketplace',
          lastCardDetailRoute: leafeonRoute,
          hasExplicitNavigationIntent: true,
          browserPath: '/',
        ),
        isFalse,
      );
      expect(
        shouldRepairCardDetailRootDrift(
          previousPath: '/marketplace',
          nextPath: '/',
          lastCardDetailRoute: leafeonRoute,
        ),
        isFalse,
      );
    });

    test('card detail canonical replacement omits debug query flags', () {
      expect(
        cardDetailCanonicalReplacementLocation(
          canonicalPath:
              '/marketplace/en/cards/633200/card-leafeon-005-131-prismatic-evolutions',
          currentUri: Uri.parse(
            '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions?flutterDebug=1&utm_source=test#card',
          ),
        ),
        '/marketplace/en/cards/633200/card-leafeon-005-131-prismatic-evolutions#card',
      );
      expect(
        cardDetailCanonicalReplacementLocation(
          canonicalPath:
              '/marketplace/en/cards/633200/card-leafeon-005-131-prismatic-evolutions',
          currentUri: Uri.parse('/316600/rare-leafeon?utm_source=test'),
        ),
        '/marketplace/en/cards/633200/card-leafeon-005-131-prismatic-evolutions',
      );
    });

    test('safe card detail path returns empty instead of fallback routes', () {
      expect(
        safeCardDetailPath(_card(id: '316600')),
        '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
      );
      expect(safeCardDetailPath(_card(id: '316600-leafeon')), isEmpty);
      expect(safeCardDetailPath(_card(id: 'leafeon-cache-row')), isEmpty);
    });

    test('safe card detail path from parts returns empty for invalid ids', () {
      expect(
        safeCardDetailPathFromParts(
          id: '316600',
          name: 'Leafeon',
          number: '005/131',
          setName: 'Prismatic Evolutions',
          rarity: 'Rare',
        ),
        '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
      );
      expect(
        safeCardDetailPathFromParts(
          id: 'leafeon-cache-row',
          name: 'Leafeon',
          number: '005/131',
          setName: 'Prismatic Evolutions',
        ),
        isEmpty,
      );
      expect(
        safeCardDetailPathFromParts(
          id: '316600-leafeon',
          name: 'Leafeon',
          number: '005/131',
          setName: 'Prismatic Evolutions',
        ),
        isEmpty,
      );
    });
  });
}
