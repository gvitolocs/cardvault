import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pokemon_card.dart';
import '../services/card_service.dart';

final cardProvider = StateNotifierProvider<CardNotifier, CardState>((ref) {
  return CardNotifier();
});

class CardState {
  final List<PokemonCard> cards;
  final List<PokemonCard> filteredCards;
  final bool isLoading;
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
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
    this.selectedRarity = '',
    this.selectedType = '',
    this.selectedSet = '',
    this.minPrice = 0.0,
    this.maxPrice = 10000.0,
    this.showOnlyInStock = false,
    this.sortBy = 'name',
    this.sortAscending = true,
  });

  CardState copyWith({
    List<PokemonCard>? cards,
    List<PokemonCard>? filteredCards,
    bool? isLoading,
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
      isLoading: isLoading ?? this.isLoading,
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

  Future<void> _loadCards() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final cards = await _cardService.getAllCards();
      state = state.copyWith(
        cards: cards,
        filteredCards: cards,
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
      filtered = filtered
          .where((card) =>
              card.name
                  .toLowerCase()
                  .contains(state.searchQuery.toLowerCase()) ||
              card.description
                  .toLowerCase()
                  .contains(state.searchQuery.toLowerCase()) ||
              card.tags.any((tag) =>
                  tag.toLowerCase().contains(state.searchQuery.toLowerCase())))
          .toList();
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
    state = state.copyWith(
      searchQuery: '',
      selectedRarity: '',
      selectedType: '',
      selectedSet: '',
      minPrice: 0.0,
      maxPrice: 10000.0,
      showOnlyInStock: false,
      sortBy: 'name',
      sortAscending: true,
    );
    _applyFilters();
  }
}
