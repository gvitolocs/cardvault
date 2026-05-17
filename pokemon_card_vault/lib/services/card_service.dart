import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/pokemon_card.dart';

class CardService {
  // Local storage
  static const String _cardsBoxName = 'pokemon_cards';
  static const Map<String, double> _pknPrices = <String, double>{
    '1': 495,
    '2': 149995,
    '3': 99995,
    '4': 74995,
    '5': 44995,
    '6': 39995,
  };

  Future<void> _initHive() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(PokemonCardAdapter());
    }
  }

  Future<List<PokemonCard>> getAllCards() async {
    await _initHive();

    try {
      // Try to get from local storage first
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      if (box.isNotEmpty) {
        final cards = _normalizeCards(box.values.toList());
        await _saveCardsToLocal(cards);
        return cards;
      }

      // If no local data, use sample cards directly
      final sampleCards = _getSampleCards();
      await _saveCardsToLocal(sampleCards);
      return sampleCards;
    } catch (e) {
      debugPrint('Error getting cards: $e');
      return _getSampleCards();
    }
  }

  Future<void> _saveCardsToLocal(List<PokemonCard> cards) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      await box.clear();
      for (int i = 0; i < cards.length; i++) {
        await box.put(i, cards[i]);
      }
    } catch (e) {
      debugPrint('Error saving cards to local storage: $e');
    }
  }

  List<PokemonCard> _normalizeCards(List<PokemonCard> cards) {
    return cards
        .map(
          (card) => card.copyWith(
            stock: 0,
            price: _pknPrices[card.id] ?? card.price,
          ),
        )
        .toList();
  }

  Future<PokemonCard?> getCardById(String id) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      return box.values.firstWhere((card) => card.id == id);
    } catch (e) {
      debugPrint('Error getting card by ID: $e');
      return null;
    }
  }

  Future<List<PokemonCard>> searchCards(String query) async {
    try {
      final allCards = await getAllCards();
      return allCards
          .where((card) =>
              card.name.toLowerCase().contains(query.toLowerCase()) ||
              card.description.toLowerCase().contains(query.toLowerCase()) ||
              card.tags.any(
                  (tag) => tag.toLowerCase().contains(query.toLowerCase())))
          .toList();
    } catch (e) {
      debugPrint('Error searching cards: $e');
      return [];
    }
  }

  Future<List<PokemonCard>> getCardsByRarity(String rarity) async {
    try {
      final allCards = await getAllCards();
      return allCards.where((card) => card.rarity == rarity).toList();
    } catch (e) {
      debugPrint('Error getting cards by rarity: $e');
      return [];
    }
  }

  Future<List<PokemonCard>> getCardsByType(String type) async {
    try {
      final allCards = await getAllCards();
      return allCards.where((card) => card.type == type).toList();
    } catch (e) {
      debugPrint('Error getting cards by type: $e');
      return [];
    }
  }

  Future<List<PokemonCard>> getCardsBySet(String setName) async {
    try {
      final allCards = await getAllCards();
      return allCards.where((card) => card.set == setName).toList();
    } catch (e) {
      debugPrint('Error getting cards by set: $e');
      return [];
    }
  }

  Future<void> addCard(PokemonCard card) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      await box.add(card);
    } catch (e) {
      debugPrint('Error adding card: $e');
      rethrow;
    }
  }

  Future<void> updateCard(PokemonCard card) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      final key = box.keys
          .firstWhere((key) => box.get(key)?.id == card.id, orElse: () => -1);
      if (key != -1) {
        await box.put(key, card);
      }
    } catch (e) {
      debugPrint('Error updating card: $e');
      rethrow;
    }
  }

  Future<void> deleteCard(String cardId) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      final key = box.keys
          .firstWhere((key) => box.get(key)?.id == cardId, orElse: () => -1);
      if (key != -1) {
        await box.delete(key);
      }
    } catch (e) {
      debugPrint('Error deleting card: $e');
      rethrow;
    }
  }

  List<PokemonCard> _getSampleCards() {
    return [
      PokemonCard(
        id: '1',
        name: 'Pikachu',
        imageUrl: 'https://images.pokemontcg.io/base1/58_hires.png',
        rarity: 'Common',
        type: 'Lightning',
        hp: 40,
        attacks: ['Thunder Shock', 'Thunder'],
        price: _pknPrices['1']!,
        description: 'A cute electric mouse Pokémon.',
        set: 'Base Set',
        number: '58',
        artist: 'Atsuko Nishida',
        stock: 0,
        rating: 4.5,
        reviewCount: 23,
        isFoil: false,
        isHolo: false,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Lightning', 'Common', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
      PokemonCard(
        id: '2',
        name: 'Charizard',
        imageUrl: 'https://images.pokemontcg.io/base1/4_hires.png',
        rarity: 'Rare Holo',
        type: 'Fire',
        hp: 120,
        attacks: ['Fire Spin', 'Flamethrower'],
        price: _pknPrices['2']!,
        description: 'A powerful dragon Pokémon.',
        set: 'Base Set',
        number: '4',
        artist: 'Mitsuhiro Arita',
        stock: 0,
        rating: 4.9,
        reviewCount: 156,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Fire', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
      PokemonCard(
        id: '3',
        name: 'Blastoise',
        imageUrl: 'https://images.pokemontcg.io/base1/2_hires.png',
        rarity: 'Rare Holo',
        type: 'Water',
        hp: 100,
        attacks: ['Hydro Pump', 'Rain Dance'],
        price: _pknPrices['3']!,
        description: 'A powerful water turtle Pokémon.',
        set: 'Base Set',
        number: '2',
        artist: 'Mitsuhiro Arita',
        stock: 0,
        rating: 4.7,
        reviewCount: 89,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Water', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
      PokemonCard(
        id: '4',
        name: 'Venusaur',
        imageUrl: 'https://images.pokemontcg.io/base1/15_hires.png',
        rarity: 'Rare Holo',
        type: 'Grass',
        hp: 100,
        attacks: ['Solar Beam', 'Razor Leaf'],
        price: _pknPrices['4']!,
        description: 'A powerful grass dinosaur Pokémon.',
        set: 'Base Set',
        number: '15',
        artist: 'Mitsuhiro Arita',
        stock: 0,
        rating: 4.6,
        reviewCount: 67,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Grass', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
      PokemonCard(
        id: '5',
        name: 'Alakazam',
        imageUrl: 'https://images.pokemontcg.io/base1/1_hires.png',
        rarity: 'Rare Holo',
        type: 'Psychic',
        hp: 80,
        attacks: ['Confuse Ray', 'Psybeam'],
        price: _pknPrices['5']!,
        description: 'A powerful psychic Pokémon.',
        set: 'Base Set',
        number: '1',
        artist: 'Mitsuhiro Arita',
        stock: 0,
        rating: 4.4,
        reviewCount: 45,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Psychic', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
      PokemonCard(
        id: '6',
        name: 'Machamp',
        imageUrl: 'https://images.pokemontcg.io/base1/8_hires.png',
        rarity: 'Rare Holo',
        type: 'Fighting',
        hp: 100,
        attacks: ['Karate Chop', 'Submission'],
        price: _pknPrices['6']!,
        description: 'A powerful fighting Pokémon.',
        set: 'Base Set',
        number: '8',
        artist: 'Mitsuhiro Arita',
        stock: 0,
        rating: 4.3,
        reviewCount: 34,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Fighting', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
    ];
  }
}
