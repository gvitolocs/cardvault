import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/models/pokemon_card.dart';
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
  test('CardTrader blueprint mapping removes generic Pokemon badge fallback',
      () {
    final service = CardService();

    final card = service.cardFromBlueprintForTest({
      'id': 281194,
      'name': 'Gengar ex',
      'cdn_image_url': 'https://cdn.pokoin.com/cards/gengar.png',
      'preview_image_url': 'https://cdn.pokoin.com/previews/gengar.webp',
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
    expect(card.imageUrl, '/card-images/cards/gengar.png');
    expect(card.previewImageUrl, '/card-images/previews/gengar.webp');
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

    expect(card.imageUrl, '/card-images/blueprint/card.png');
    expect(card.previewImageUrl, '/card-images/blueprint/card.png');
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
  });
}
