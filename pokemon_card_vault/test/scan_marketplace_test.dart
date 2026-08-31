import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/models/pokemon_card.dart';
import 'package:pokoin/utils/scan_marketplace.dart';

PokemonCard _card({
  String id = '220962',
  String name = 'Espurr',
  String number = '58/122',
  String set = 'BREAKpoint',
  String rarity = 'Common',
}) {
  return PokemonCard(
    id: id,
    name: name,
    imageUrl: 'https://cdn.pokoin.com/cards/$id.png',
    rarity: rarity,
    type: 'Trading card',
    hp: 0,
    attacks: const [],
    price: 0,
    description: '',
    set: set,
    number: number,
    artist: '',
    stock: 0,
    rating: 0,
    reviewCount: 0,
    isFoil: false,
    isHolo: false,
    releaseDate: DateTime(2016),
    tags: const [],
    condition: 'NM',
    isGraded: false,
  );
}

void main() {
  test('scan JSON does not treat TCGplayer id as a CardTrader blueprint', () {
    final hit = CardScanHit.fromJson({
      'id': '888001',
      'name': 'Espurr',
      'collector_number': '58/122',
      'set': 'BREAKpoint',
      'score': 0.53,
    });

    expect(hit.tcgplayerId, '888001');
    expect(hit.cardtraderBlueprintId, isEmpty);
    expect(
      scanHitMarketplacePath(
        name: hit.name,
        collectorNumber: hit.collectorNumber,
        setName: hit.setName,
        cardtraderBlueprintId: hit.cardtraderBlueprintId,
      ),
      '/marketplace/search?q=Espurr+58', // Fast-only fallback when no catalog row
    );
  });

  test('blueprint id becomes doubled marketplace path', () {
    expect(
      scanHitMarketplacePath(
        name: 'Espurr',
        collectorNumber: '58/122',
        setName: 'BREAKpoint',
        rarity: 'Common',
        cardtraderBlueprintId: '110481',
      ),
      '/marketplace/en/cards/220962/common-espurr-58-122-breakpoint',
    );
  });

  test('matched marketplace card wins over TCGplayer product id', () {
    final matched = _card();
    expect(
      scanHitMarketplacePath(
        name: 'Espurr',
        collectorNumber: '58/122',
        setName: 'BREAKpoint',
        cardtraderBlueprintId: '',
        matchedCard: matched,
      ),
      '/marketplace/en/cards/220962/common-espurr-58-122-breakpoint',
    );
  });

  test('autocomplete picker keeps Tinkatink not Tinkaton', () {
    final picked = pickMarketplaceCardForScanHit(
      name: 'Tinkatink',
      collectorNumber: '096/182',
      setName: 'Paradox Rift',
      candidates: [
        _card(
          id: '269695',
          name: 'Tinkaton',
          number: '096/190',
          set: 'Shiny Treasure ex',
        ),
        _card(
          id: '239497',
          name: 'Tinkatink',
          number: '040/073',
          set: 'Triplet Beat',
        ),
        _card(
          id: '261001',
          name: 'Tinkatink',
          number: '096/182',
          set: 'Paradox Rift',
        ),
      ],
    );

    expect(picked?.id, '261001');
  });
}
