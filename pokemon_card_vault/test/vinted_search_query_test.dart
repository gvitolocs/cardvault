import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/models/pokemon_card.dart';
import 'package:pokoin/screens/card_detail_screen.dart';

PokemonCard _card({
  required String name,
  String number = '',
  String set = 'Ignored Expansion',
}) {
  return PokemonCard(
    id: 'test-card',
    name: name,
    imageUrl: 'https://cdn.pokoin.com/cards/test-card.png',
    rarity: 'Card',
    type: 'Trading card',
    hp: 0,
    attacks: const [],
    price: 1000,
    description: 'Vinted query fixture',
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
  group('vintedSearchQueryForCard', () {
    test('preserves long card names without extra fields', () {
      expect(
        vintedSearchQueryForCard(
          _card(name: 'Charizard VMAXx', number: '199'),
        ),
        'Charizard VMAXx',
      );
    });

    test('appends leading card number only when it fits', () {
      expect(
        vintedSearchQueryForCard(_card(name: 'Espeon VMAX', number: '65')),
        'Espeon VMAX 65',
      );
    });

    test('uses only the leading collector number before expansion total', () {
      expect(
        vintedSearchQueryForCard(_card(name: 'Mew ex', number: '216/091')),
        'Mew ex 216',
      );
    });

    test('does not append leading card number when it exceeds query limit', () {
      expect(
        vintedSearchQueryForCard(
            _card(name: 'Pikachu VMAX', number: '123/456')),
        'Pikachu VMAX',
      );
    });

    test('does not append card number when full name reaches query limit', () {
      expect(
        vintedSearchQueryForCard(_card(name: 'Pikachu VMAXxx', number: '001')),
        'Pikachu VMAXxx',
      );
    });

    test('omits expansion name from the query', () {
      expect(
        vintedSearchQueryForCard(
          _card(name: 'Mew', number: '', set: 'Scarlet & Violet 151'),
        ),
        'Mew',
      );
    });
  });

  group('displayCollectorNumberForCard', () {
    test('extracts set-code collector number from variant labels', () {
      expect(
        displayCollectorNumberForCard('Non-Holo / Cosmos Holo | PAR 160'),
        'PAR 160',
      );
    });

    test('keeps slash collector numbers compact', () {
      expect(displayCollectorNumberForCard('097 / 236'), '097/236');
    });
  });
}
