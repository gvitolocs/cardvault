import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pokemon_card.dart';
import '../services/card_service.dart';

final cardProvider = StateNotifierProvider<CardNotifier, CardState>((ref) {
  return CardNotifier();
});

class CardState {
  final List<PokemonCard> cards;
  final List<PokemonCard> filteredCards;
  final List<PokemonCard> searchPreviews;
  final MarketplaceHomeSections? homeSections;
  final bool isLoading;
  final bool isSearchingPreviews;
  final String? error;
  final String searchQuery;
  final String selectedRarity;
  final String selectedType;
  final String selectedSet;
  final double minPrice;
  final double maxPrice;
  final bool showOnlyInStock;
  final String sortBy;
  final bool sortAscending;

  CardState({
    this.cards = const [],
    this.filteredCards = const [],
    this.searchPreviews = const [],
    this.homeSections,
    this.isLoading = false,
    this.isSearchingPreviews = false,
    this.error,
    this.searchQuery = '',
    this.selectedRarity = '',
    this.selectedType = '',
    this.selectedSet = '',
    this.minPrice = 0.0,
    this.maxPrice = 5000000.0,
    this.showOnlyInStock = false,
    this.sortBy = 'name',
    this.sortAscending = true,
  });

  CardState copyWith({
    List<PokemonCard>? cards,
    List<PokemonCard>? filteredCards,
    List<PokemonCard>? searchPreviews,
    MarketplaceHomeSections? homeSections,
    bool? isLoading,
    bool? isSearchingPreviews,
    String? error,
    String? searchQuery,
    String? selectedRarity,
    String? selectedType,
    String? selectedSet,
    double? minPrice,
    double? maxPrice,
    bool? showOnlyInStock,
    String? sortBy,
    bool? sortAscending,
  }) {
    return CardState(
      cards: cards ?? this.cards,
      filteredCards: filteredCards ?? this.filteredCards,
      searchPreviews: searchPreviews ?? this.searchPreviews,
      homeSections: homeSections ?? this.homeSections,
      isLoading: isLoading ?? this.isLoading,
      isSearchingPreviews: isSearchingPreviews ?? this.isSearchingPreviews,
      error: error ?? this.error,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedRarity: selectedRarity ?? this.selectedRarity,
      selectedType: selectedType ?? this.selectedType,
      selectedSet: selectedSet ?? this.selectedSet,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      showOnlyInStock: showOnlyInStock ?? this.showOnlyInStock,
      sortBy: sortBy ?? this.sortBy,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }
}

class CardNotifier extends StateNotifier<CardState> {
  CardNotifier() : super(CardState()) {
    _loadCards();
  }

  final CardService _cardService = CardService();
  int _searchPreviewRequestId = 0;
  int _searchRequestId = 0;

  Future<void> _loadCards() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final cards = await _cardService.getAllCards();
      final snapshot = await _cardService.getMarketplaceHomeSnapshot();
      state = state.copyWith(
        cards: cards,
        filteredCards: cards,
        homeSections: snapshot?.sections,
        isLoading: false,
      );
      _applyFilters();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void searchCards(String query) {
    state = state.copyWith(searchQuery: query);
    _applyFilters();
    _loadSearchPreviews(query);
    _loadFullSearchResults(query);
    final firstMatch =
        state.filteredCards.isEmpty ? null : state.filteredCards.first;
    if (query.trim().length >= 2 && firstMatch != null) {
      _cardService.recordMarketplaceEvent(
        firstMatch.id,
        'search',
        source: 'marketplace_search',
      );
    }
  }

  Future<void> _loadFullSearchResults(String query) async {
    final requestId = ++_searchRequestId;
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) {
      return;
    }

    final results = await _cardService.searchMarketplaceCards(
      normalizedQuery,
      limit: 240,
    );
    if (requestId != _searchRequestId ||
        normalizedQuery != state.searchQuery.trim()) {
      return;
    }
    if (results.isEmpty) {
      return;
    }
    state = state.copyWith(
      cards: _mergeCards(state.cards, results),
      filteredCards: results,
    );
  }

  void recordCardInteraction(
    PokemonCard card,
    String eventType, {
    String source = 'marketplace',
  }) {
    _cardService.recordMarketplaceEvent(card.id, eventType, source: source);
  }

  Future<PokemonCard?> loadCardById(String id) async {
    final existing = _findLoadedCard(id);
    if (existing != null) {
      return existing;
    }

    final card = await _cardService.getCardById(id);
    if (card == null) {
      return null;
    }

    if (_findLoadedCard(card.id) == null) {
      state = state.copyWith(cards: [...state.cards, card]);
      _applyFilters();
    }
    return card;
  }

  Future<void> _loadSearchPreviews(String query) async {
    final requestId = ++_searchPreviewRequestId;
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) {
      state = state.copyWith(
        searchPreviews: const [],
        isSearchingPreviews: false,
      );
      return;
    }

    final shouldWaitForRemote = _hasNumericSearchTerm(normalizedQuery);
    final localPreviews = shouldWaitForRemote
        ? const <PokemonCard>[]
        : _rankLocalPreviews(state.cards, normalizedQuery, limit: 40);
    state = state.copyWith(
      searchPreviews: localPreviews,
      isSearchingPreviews: true,
    );

    final previews = await _cardService.searchCardPreviews(
      normalizedQuery,
      fallbackCards: state.cards,
      limit: 40,
    );
    if (requestId != _searchPreviewRequestId) {
      return;
    }
    state = state.copyWith(
      searchPreviews: previews,
      isSearchingPreviews: false,
    );
  }

  void filterByRarity(String rarity) {
    state = state.copyWith(selectedRarity: rarity);
    _applyFilters();
  }

  void filterByType(String type) {
    state = state.copyWith(selectedType: type);
    _applyFilters();
  }

  void filterBySet(String set) {
    state = state.copyWith(selectedSet: set);
    _applyFilters();
  }

  void filterByPriceRange(double minPrice, double maxPrice) {
    state = state.copyWith(minPrice: minPrice, maxPrice: maxPrice);
    _applyFilters();
  }

  void toggleInStockFilter() {
    state = state.copyWith(showOnlyInStock: !state.showOnlyInStock);
    _applyFilters();
  }

  void sortCards(String sortBy, {bool? ascending}) {
    state = state.copyWith(
      sortBy: sortBy,
      sortAscending: ascending ?? !state.sortAscending,
    );
    _applyFilters();
  }

  void _applyFilters() {
    List<PokemonCard> filtered = List.from(state.cards);

    // Search filter
    if (state.searchQuery.isNotEmpty) {
      final terms = _searchTerms(state.searchQuery);
      filtered =
          filtered.where((card) => _matchesSearchTerms(card, terms)).toList();
    }

    // Rarity filter
    if (state.selectedRarity.isNotEmpty) {
      filtered = filtered
          .where((card) => card.rarity == state.selectedRarity)
          .toList();
    }

    // Type filter
    if (state.selectedType.isNotEmpty) {
      filtered =
          filtered.where((card) => card.type == state.selectedType).toList();
    }

    // Set filter
    if (state.selectedSet.isNotEmpty) {
      filtered =
          filtered.where((card) => card.set == state.selectedSet).toList();
    }

    // Price filter
    filtered = filtered
        .where((card) =>
            card.price >= state.minPrice && card.price <= state.maxPrice)
        .toList();

    // Stock filter
    if (state.showOnlyInStock) {
      filtered = filtered.where((card) => card.stock > 0).toList();
    }

    // Sort
    filtered.sort((a, b) {
      int comparison = 0;
      switch (state.sortBy) {
        case 'name':
          comparison = a.name.compareTo(b.name);
          break;
        case 'price':
          comparison = a.price.compareTo(b.price);
          break;
        case 'rating':
          comparison = a.rating.compareTo(b.rating);
          break;
        case 'releaseDate':
          comparison = a.releaseDate.compareTo(b.releaseDate);
          break;
        case 'rarity':
          comparison = a.rarity.compareTo(b.rarity);
          break;
        default:
          comparison = a.name.compareTo(b.name);
      }
      return state.sortAscending ? comparison : -comparison;
    });

    state = state.copyWith(filteredCards: filtered);
  }

  Future<void> refreshCards() async {
    await _loadCards();
  }

  Future<void> addCard(PokemonCard card) async {
    try {
      await _cardService.addCard(card);
      await _loadCards();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> updateCard(PokemonCard card) async {
    try {
      await _cardService.updateCard(card);
      await _loadCards();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteCard(String cardId) async {
    try {
      await _cardService.deleteCard(cardId);
      await _loadCards();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void clearFilters() {
    _searchRequestId++;
    state = state.copyWith(
      searchQuery: '',
      searchPreviews: const [],
      isSearchingPreviews: false,
      selectedRarity: '',
      selectedType: '',
      selectedSet: '',
      minPrice: 0.0,
      maxPrice: 5000000.0,
      showOnlyInStock: false,
      sortBy: 'name',
      sortAscending: true,
    );
    _applyFilters();
  }

  List<PokemonCard> _rankLocalPreviews(
    List<PokemonCard> cards,
    String query, {
    required int limit,
  }) {
    final normalizedQuery = query.toLowerCase();
    final ranked = cards
        .map((card) => MapEntry(card, _localSearchScore(card, normalizedQuery)))
        .where((entry) => entry.value > 0)
        .toList()
      ..sort((a, b) {
        final score = b.value.compareTo(a.value);
        if (score != 0) {
          return score;
        }
        return a.key.name.compareTo(b.key.name);
      });
    return ranked.map((entry) => entry.key).take(limit).toList();
  }

  int _localSearchScore(PokemonCard card, String query) {
    final name = card.name.toLowerCase();
    final set = card.set.toLowerCase();
    final number = card.number.toLowerCase();
    final tags = card.tags.join(' ').toLowerCase();
    final haystack = '$name $set $number $tags';
    final terms = _searchTerms(query);

    if (number == query) {
      return 980;
    }
    if (number.startsWith(query)) {
      return 880;
    }
    if (_wordStartsWith(number, query)) {
      return 840;
    }
    if (name == query) {
      return 1000;
    }
    if (terms.length > 1 && terms.every(haystack.contains)) {
      var score = 520;
      var matchedName = false;
      var matchedSet = false;
      var matchedNumber = false;
      for (final term in terms) {
        if (number == term) {
          score += 220;
          matchedNumber = true;
        } else if (number.startsWith(term)) {
          score += 190;
          matchedNumber = true;
        } else if (_wordStartsWith(number, term)) {
          score += 170;
          matchedNumber = true;
        } else if (number.contains(term)) {
          score += 140;
          matchedNumber = true;
        } else if (name.startsWith(term)) {
          score += 190;
          matchedName = true;
        } else if (_wordStartsWith(name, term)) {
          score += 150;
          matchedName = true;
        } else if (name.contains(term)) {
          score += 80;
          matchedName = true;
        } else if (set.startsWith(term)) {
          score += 180;
          matchedSet = true;
        } else if (_wordStartsWith(set, term)) {
          score += 160;
          matchedSet = true;
        } else if (set.contains(term)) {
          score += 120;
          matchedSet = true;
        }
      }
      if (matchedName && matchedSet) {
        score += 140;
      }
      if (matchedNumber && matchedName) {
        score += 180;
      } else if (matchedNumber && matchedSet) {
        score += 120;
      }
      return score;
    }
    if (name.startsWith(query)) {
      return 800;
    }
    if (name.contains(query)) {
      return 600;
    }
    if (number.contains(query)) {
      return 700;
    }
    if (set.contains(query)) {
      return 350;
    }
    if (tags.contains(query)) {
      return 180;
    }
    return 0;
  }

  PokemonCard? _findLoadedCard(String id) {
    for (final card in state.cards) {
      if (card.id == id) {
        return card;
      }
    }
    return null;
  }

  List<PokemonCard> _mergeCards(
    List<PokemonCard> current,
    List<PokemonCard> incoming,
  ) {
    final byId = <String, PokemonCard>{
      for (final card in current) card.id: card,
    };
    for (final card in incoming) {
      byId[card.id] = card;
    }
    return byId.values.toList();
  }

  bool _matchesSearchTerms(PokemonCard card, List<String> terms) {
    if (terms.isEmpty) {
      return true;
    }
    final haystack = [
      card.name,
      card.set,
      card.number,
      card.description,
      ...card.tags,
    ].join(' ').toLowerCase();
    return terms.every(haystack.contains);
  }

  List<String> _searchTerms(String query) {
    return query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .map((term) => term.trim())
        .where((term) => term.length >= 2)
        .toList();
  }

  bool _hasNumericSearchTerm(String query) {
    return _searchTerms(query).any((term) => RegExp(r'\d').hasMatch(term));
  }

  bool _wordStartsWith(String value, String term) {
    return value
        .split(RegExp(r'[^a-z0-9]+'))
        .any((word) => word.startsWith(term));
  }
}
