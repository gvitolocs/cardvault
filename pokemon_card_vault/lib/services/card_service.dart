import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/pokemon_card.dart';

class CardService {
  static const String _baseUrl = 'https://api.pokemontcg.io/v2';
  static const String _apiKey = 'your-api-key-here'; // Replace with actual API key
  
  // Local storage
  static const String _cardsBoxName = 'pokemon_cards';
  
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
        return box.values.toList();
      }
      
      // If no local data, fetch from API
      return await _fetchCardsFromAPI();
    } catch (e) {
      print('Error getting cards: $e');
      return [];
    }
  }

  Future<List<PokemonCard>> _fetchCardsFromAPI() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/cards'),
        headers: {
          'X-Api-Key': _apiKey,
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> cardsData = data['data'] ?? [];
        
        List<PokemonCard> cards = cardsData.map((cardData) {
          return PokemonCard.fromJson({
            'id': cardData['id'] ?? '',
            'name': cardData['name'] ?? '',
            'imageUrl': cardData['images']?['large'] ?? cardData['images']?['small'] ?? '',
            'rarity': cardData['rarity'] ?? 'Common',
            'type': cardData['types']?.isNotEmpty == true ? cardData['types'][0] : 'Colorless',
            'hp': int.tryParse(cardData['hp']?.toString() ?? '0') ?? 0,
            'attacks': (cardData['attacks'] as List<dynamic>?)
                ?.map((attack) => attack['name']?.toString() ?? '')
                .toList() ?? [],
            'price': _generatePrice(cardData),
            'description': cardData['flavorText'] ?? '',
            'set': cardData['set']?['name'] ?? '',
            'number': cardData['number'] ?? '',
            'artist': cardData['artist'] ?? '',
            'stock': _generateStock(),
            'rating': _generateRating(),
            'reviewCount': _generateReviewCount(),
            'isFoil': cardData['tcgplayer']?['prices']?['holofoil'] != null,
            'isHolo': cardData['tcgplayer']?['prices']?['holofoil'] != null,
            'releaseDate': DateTime.tryParse(cardData['set']?['releaseDate'] ?? '') ?? DateTime.now(),
            'tags': _generateTags(cardData),
            'condition': 'NM',
            'isGraded': false,
          });
        }).toList();

        // Save to local storage
        await _saveCardsToLocal(cards);
        return cards;
      } else {
        throw Exception('Failed to load cards: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching cards from API: $e');
      return _getSampleCards(); // Return sample data if API fails
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
      print('Error saving cards to local storage: $e');
    }
  }

  Future<PokemonCard?> getCardById(String id) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      return box.values.firstWhere((card) => card.id == id);
    } catch (e) {
      print('Error getting card by ID: $e');
      return null;
    }
  }

  Future<List<PokemonCard>> searchCards(String query) async {
    try {
      final allCards = await getAllCards();
      return allCards.where((card) =>
          card.name.toLowerCase().contains(query.toLowerCase()) ||
          card.description.toLowerCase().contains(query.toLowerCase()) ||
          card.tags.any((tag) => tag.toLowerCase().contains(query.toLowerCase()))
      ).toList();
    } catch (e) {
      print('Error searching cards: $e');
      return [];
    }
  }

  Future<List<PokemonCard>> getCardsByRarity(String rarity) async {
    try {
      final allCards = await getAllCards();
      return allCards.where((card) => card.rarity == rarity).toList();
    } catch (e) {
      print('Error getting cards by rarity: $e');
      return [];
    }
  }

  Future<List<PokemonCard>> getCardsByType(String type) async {
    try {
      final allCards = await getAllCards();
      return allCards.where((card) => card.type == type).toList();
    } catch (e) {
      print('Error getting cards by type: $e');
      return [];
    }
  }

  Future<List<PokemonCard>> getCardsBySet(String setName) async {
    try {
      final allCards = await getAllCards();
      return allCards.where((card) => card.set == setName).toList();
    } catch (e) {
      print('Error getting cards by set: $e');
      return [];
    }
  }

  Future<void> addCard(PokemonCard card) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      await box.add(card);
    } catch (e) {
      print('Error adding card: $e');
      throw e;
    }
  }

  Future<void> updateCard(PokemonCard card) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      final key = box.keys.firstWhere((key) => box.get(key)?.id == card.id, orElse: () => -1);
      if (key != -1) {
        await box.put(key, card);
      }
    } catch (e) {
      print('Error updating card: $e');
      throw e;
    }
  }

  Future<void> deleteCard(String cardId) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      final key = box.keys.firstWhere((key) => box.get(key)?.id == cardId, orElse: () => -1);
      if (key != -1) {
        await box.delete(key);
      }
    } catch (e) {
      print('Error deleting card: $e');
      throw e;
    }
  }

  // Helper methods for generating sample data
  double _generatePrice(Map<String, dynamic> cardData) {
    final rarity = cardData['rarity']?.toString().toLowerCase() ?? 'common';
    switch (rarity) {
      case 'rare holo':
        return 5.0 + (DateTime.now().millisecondsSinceEpoch % 50);
      case 'rare':
        return 2.0 + (DateTime.now().millisecondsSinceEpoch % 20);
      case 'uncommon':
        return 0.5 + (DateTime.now().millisecondsSinceEpoch % 5);
      default:
        return 0.1 + (DateTime.now().millisecondsSinceEpoch % 2);
    }
  }

  int _generateStock() {
    return 1 + (DateTime.now().millisecondsSinceEpoch % 20);
  }

  double _generateRating() {
    return 3.0 + (DateTime.now().millisecondsSinceEpoch % 20) / 10;
  }

  int _generateReviewCount() {
    return DateTime.now().millisecondsSinceEpoch % 100;
  }

  List<String> _generateTags(Map<String, dynamic> cardData) {
    List<String> tags = [];
    if (cardData['types'] != null) {
      tags.addAll((cardData['types'] as List).cast<String>());
    }
    if (cardData['rarity'] != null) {
      tags.add(cardData['rarity']);
    }
    if (cardData['set']?['name'] != null) {
      tags.add(cardData['set']['name']);
    }
    return tags;
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
        price: 0.99,
        description: 'A cute electric mouse Pokémon.',
        set: 'Base Set',
        number: '58',
        artist: 'Atsuko Nishida',
        stock: 15,
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
        price: 299.99,
        description: 'A powerful dragon Pokémon.',
        set: 'Base Set',
        number: '4',
        artist: 'Mitsuhiro Arita',
        stock: 3,
        rating: 4.9,
        reviewCount: 156,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Fire', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
    ];
  }
}
