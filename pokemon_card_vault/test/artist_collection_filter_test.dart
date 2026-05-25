import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/models/pokemon_card.dart';
import 'package:pokoin/screens/artist_collection_screen.dart';

PokemonCard _artistCard({
  required String id,
  required String name,
  String number = '1/100',
  String rarity = 'Card',
  String type = 'Pokemon',
  List<String> tags = const [],
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
    description: 'Artist collection fixture',
    set: 'Test Set',
    number: number,
    artist: 'Test Artist',
    stock: 0,
    rating: 0,
    reviewCount: 0,
    isFoil: false,
    isHolo: false,
    releaseDate: DateTime(2026),
    tags: tags,
    condition: 'NM',
    isGraded: false,
  );
}

void main() {
  group('artist card filters', () {
    test('illustration filter matches illustration rarity metadata', () {
      final card = _artistCard(
        id: 'illustration',
        name: 'Squirtle',
        rarity: 'Illustration Rare',
        number: '170/165',
      );

      expect(ArtistCardFilter.illustrations.matches(card), isTrue);
      expect(ArtistCardFilter.fullArts.matches(card), isTrue);
      expect(ArtistCardFilter.normalCards.matches(card), isFalse);
    });

    test('full arts filter matches explicit full-art labels', () {
      final card = _artistCard(
        id: 'full-art',
        name: 'Lillie',
        rarity: 'Ultra Rare',
        number: 'Full Art | 151/149',
      );

      expect(ArtistCardFilter.fullArts.matches(card), isTrue);
      expect(ArtistCardFilter.normalCards.matches(card), isFalse);
    });

    test('normal cards exclude full-art and illustration variants', () {
      final card = _artistCard(
        id: 'normal',
        name: 'Pikachu',
        rarity: 'Common',
        number: '025/100',
      );

      expect(ArtistCardFilter.normalCards.matches(card), isTrue);
      expect(ArtistCardFilter.fullArts.matches(card), isFalse);
      expect(ArtistCardFilter.illustrations.matches(card), isFalse);
    });
  });
}
