import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pokemon_card.dart';
import '../services/card_service.dart';

final cardProvider = StateNotifierProvider<CardNotifier, CardState>((ref) {
  return CardNotifier();
});

const int searchPreviewLimit = 20;
const int searchPreviewPoolLimit = 1000;
const int searchPreviewVisibleRows = 9;
const int searchPreviewWarmupChars = 1;
const int searchPreviewVisibleChars = 3;

const Map<String, String> _raritySearchAliases = {
  'goldstar': 'gold star',
  'shiningrare': 'shining rare',
  'shinystar': 'shiny star',
  'illustrationrare': 'illustration rare',
  'specialillustrationrare': 'special illustration rare',
  'amazingerare': 'amazing rare',
  'radiantrare': 'radiant rare',
  'ultrarare': 'ultra rare',
  'secretrare': 'secret rare',
  'hyperrare': 'hyper rare',
  'doublerare': 'double rare',
  'rareholo': 'rare holo',
  'holographicrare': 'holographic rare',
  'holorare': 'holo rare',
};

const Map<String, String> _trainerSearchAliases = {
  'camilla': 'cynthia',
  'cynthia': 'cynthia',
  'shirona': 'cynthia',
  'n': 'n',
  'lance': 'lance',
  'camus': 'lance',
  'misty': 'misty',
  'ondine': 'misty',
  'kasumi': 'misty',
  'brock': 'brock',
  'pierre': 'brock',
  'takeshi': 'brock',
  'erika': 'erika',
  'giovanni': 'giovanni',
  'sabrina': 'sabrina',
  'sandra': 'clair',
  'clair': 'clair',
  'iris': 'iris',
  'steven': 'steven',
  'rochard': 'steven',
  'diantha': 'diantha',
  'lilia': 'lillie',
  'lillie': 'lillie',
  'gladio': 'gladion',
  'gladion': 'gladion',
  'marnie': 'marnie',
  'mary': 'marnie',
  'hop': 'hop',
  'dandel': 'leon',
  'leon': 'leon',
  'roy': 'raihan',
  'raihan': 'raihan',
  'nemona': 'nemona',
  'peonia': 'peonia',
  'iono': 'iono',
  'kissara': 'iono',
};

const Set<String> _ownershipStopWords = {
  'di',
  'de',
  'del',
  'della',
  'da',
  'du',
  'des',
  'of',
  'the',
  'owned',
  'owner',
};

class CardState {
  final List<PokemonCard> cards;
  final List<PokemonCard> filteredCards;
  final List<PokemonCard> searchPreviews;
  final MarketplaceHomeSections? homeSections;
  final bool isLoading;
  final bool isSearchingPreviews;
  final String? error;
  final String searchQuery;
  final String previewQuery;
  final String selectedRarity;
  final String selectedType;
  final String selectedSet;
  final double minPrice;
  final double maxPrice;
  final bool showOnlyInStock;
  final String sortBy;
  final bool sortAscending;
  final String searchLanguage;

  CardState({
    this.cards = const [],
    this.filteredCards = const [],
    this.searchPreviews = const [],
    this.homeSections,
    this.isLoading = false,
    this.isSearchingPreviews = false,
    this.error,
    this.searchQuery = '',
    this.previewQuery = '',
    this.selectedRarity = '',
    this.selectedType = '',
    this.selectedSet = '',
    this.minPrice = 0.0,
    this.maxPrice = 5000000.0,
    this.showOnlyInStock = false,
    this.sortBy = 'name',
    this.sortAscending = true,
    this.searchLanguage = 'en',
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
    String? previewQuery,
    String? selectedRarity,
    String? selectedType,
    String? selectedSet,
    double? minPrice,
    double? maxPrice,
    bool? showOnlyInStock,
    String? sortBy,
    bool? sortAscending,
    String? searchLanguage,
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
      previewQuery: previewQuery ?? this.previewQuery,
      selectedRarity: selectedRarity ?? this.selectedRarity,
      selectedType: selectedType ?? this.selectedType,
      selectedSet: selectedSet ?? this.selectedSet,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      showOnlyInStock: showOnlyInStock ?? this.showOnlyInStock,
      sortBy: sortBy ?? this.sortBy,
      sortAscending: sortAscending ?? this.sortAscending,
      searchLanguage: searchLanguage ?? this.searchLanguage,
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
  List<PokemonCard> _previewCandidatePool = const [];
  String _previewPoolKey = '';
  String _previewPoolLanguage = 'en';

  Future<void> _loadCards() async {
    try {
      final cachedCards = await _cardService.getCachedCards();
      final cachedSnapshot =
          await _cardService.getCachedMarketplaceHomeSnapshot();
      if (cachedCards.isNotEmpty || cachedSnapshot != null) {
        final warmedCards = cachedSnapshot == null
            ? cachedCards
            : _mergeCards(cachedCards, cachedSnapshot.cards);
        state = state.copyWith(
          cards: warmedCards,
          filteredCards: warmedCards,
          homeSections: cachedSnapshot?.sections,
          isLoading: false,
          error: null,
        );
        _applyFilters();
      } else {
        state = state.copyWith(isLoading: true, error: null);
      }

      final snapshot = await _cardService.getMarketplaceHomeSnapshot();
      final cards = snapshot == null
          ? await _cardService.getAllCards()
          : await _cardService.getCachedCards();
      final mergedCards =
          snapshot == null ? cards : _mergeCards(cards, snapshot.cards);
      state = state.copyWith(
        cards: mergedCards,
        filteredCards: mergedCards,
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

  void searchPreviewsOnly(String query) {
    _searchRequestId++;
    state = state.copyWith(previewQuery: query);
    _loadSearchPreviews(query);
  }

  void setSearchLanguage(String language) {
    final normalized = language.trim().toLowerCase();
    if (normalized == state.searchLanguage) {
      return;
    }
    _clearPreviewPool();
    state = state.copyWith(searchLanguage: normalized);
    if (_meaningfulSearchLength(state.previewQuery) >=
        searchPreviewWarmupChars) {
      _loadSearchPreviews(state.previewQuery);
    }
    if (state.searchQuery.trim().length >= 2) {
      _loadFullSearchResults(state.searchQuery);
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
      searchLanguage: state.searchLanguage,
    );
    if (requestId != _searchRequestId ||
        normalizedQuery != state.searchQuery.trim()) {
      return;
    }
    if (results.isEmpty) {
      return;
    }
    state = state.copyWith(cards: _mergeCards(state.cards, results));
    _applyFilters();
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
    recordCardInteraction(card, 'view', source: 'card_detail_direct');
    return card;
  }

  Future<void> _loadSearchPreviews(String query) async {
    final requestId = ++_searchPreviewRequestId;
    final normalizedQuery = query.trim();
    final meaningfulChars = _meaningfulSearchLength(normalizedQuery);
    final canShowAutocomplete = meaningfulChars >= searchPreviewVisibleChars;
    if (meaningfulChars < searchPreviewWarmupChars) {
      _clearPreviewPool();
      state = state.copyWith(
        previewQuery: '',
        searchPreviews: const [],
        isSearchingPreviews: false,
      );
      return;
    }

    final poolKey = _candidatePoolKey(normalizedQuery);
    final requestedLanguage = state.searchLanguage;
    final hasCurrentPool = _previewCandidatePool.isNotEmpty &&
        _previewPoolKey == poolKey &&
        _previewPoolLanguage == requestedLanguage;
    final candidatePool = _previewCandidatePool;
    final localPreviews = hasCurrentPool
        ? _rankLocalPreviews(
            candidatePool,
            normalizedQuery,
            limit: searchPreviewLimit,
          )
        : const <PokemonCard>[];
    final visiblePreviews = canShowAutocomplete
        ? localPreviews.isNotEmpty
            ? localPreviews
            : state.searchPreviews
        : const <PokemonCard>[];
    state = state.copyWith(
      searchPreviews: visiblePreviews,
      isSearchingPreviews:
          canShowAutocomplete && !(hasCurrentPool && localPreviews.isNotEmpty),
    );

    if (hasCurrentPool &&
        localPreviews.isNotEmpty &&
        !_isStructuredPreviewQuery(normalizedQuery)) {
      return;
    }

    final previews = await _cardService.searchAutocompleteCards(
      normalizedQuery,
      limit: searchPreviewPoolLimit,
      poolLimit: searchPreviewPoolLimit,
      searchLanguage: requestedLanguage,
    );
    final currentQuery = state.previewQuery.trim();
    final currentPoolKey = _candidatePoolKey(currentQuery);
    final currentMeaningfulChars = _meaningfulSearchLength(currentQuery);
    final currentCanShowAutocomplete =
        currentMeaningfulChars >= searchPreviewVisibleChars;
    final responseStillMatchesCurrentPool =
        poolKey == currentPoolKey && requestedLanguage == state.searchLanguage;
    if (requestId != _searchPreviewRequestId &&
        !responseStillMatchesCurrentPool) {
      return;
    }
    final nextCandidatePool = previews.isEmpty ? candidatePool : previews;
    _previewCandidatePool = nextCandidatePool;
    _previewPoolKey = poolKey;
    _previewPoolLanguage = requestedLanguage;
    final shouldShowAutocomplete = responseStillMatchesCurrentPool
        ? currentCanShowAutocomplete
        : canShowAutocomplete;
    final nextPreviews = nextCandidatePool.isNotEmpty
        ? _rankLocalPreviews(
            nextCandidatePool,
            currentQuery.isEmpty ? normalizedQuery : currentQuery,
            limit: searchPreviewLimit,
          )
        : state.searchPreviews;
    state = state.copyWith(
      searchPreviews: shouldShowAutocomplete ? nextPreviews : const [],
      isSearchingPreviews: requestId == _searchPreviewRequestId
          ? false
          : state.isSearchingPreviews,
    );
  }

  void _clearPreviewPool() {
    _previewCandidatePool = const [];
    _previewPoolKey = '';
    _previewPoolLanguage = state.searchLanguage;
  }

  String _candidatePoolKey(String query) {
    final terms = _searchTerms(query);
    if (_isStructuredPreviewQuery(query)) {
      return terms.join('|');
    }
    final normalized = query.toLowerCase();
    final buffer = StringBuffer();
    for (final match
        in RegExp(r'[a-z0-9]', caseSensitive: false).allMatches(normalized)) {
      buffer.write(match.group(0));
      if (buffer.length >= searchPreviewVisibleChars) {
        break;
      }
    }
    return buffer.toString();
  }

  bool _isStructuredPreviewQuery(String query) {
    final terms = _searchTerms(query);
    if (terms.length < 2) {
      return false;
    }
    return terms.any((term) => RegExp(r'^[0-9]+$').hasMatch(term)) ||
        terms.any(_isVariationSearchTerm) ||
        terms.any(_isRaritySearchTerm) ||
        terms.any(_isExpansionAliasSearchTerm);
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

  void cacheCards(Iterable<PokemonCard> cards) {
    final incoming = cards.where((card) => card.id.isNotEmpty).toList();
    if (incoming.isEmpty) {
      return;
    }
    state = state.copyWith(cards: _mergeCards(state.cards, incoming));
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
    _searchPreviewRequestId++;
    state = state.copyWith(
      searchQuery: '',
      previewQuery: '',
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
      searchLanguage: 'en',
    );
    _applyFilters();
  }

  List<PokemonCard> _rankLocalPreviews(
    List<PokemonCard> cards,
    String query, {
    required int limit,
  }) {
    final queryVariants = _searchQueryVariants([query]);
    final ranked = cards
        .map((card) => MapEntry(
              card,
              queryVariants.fold<int>(
                0,
                (score, query) => math.max(
                  score,
                  _localSearchScore(card, query.toLowerCase()),
                ),
              ),
            ))
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
    final trainerName = card.trainerName.toLowerCase();
    final isProduct = card.itemKind == 'product';
    final isPokemonIdentity = _isPokemonIdentityCard(card);
    final number = isProduct ? '' : card.number.toLowerCase();
    final tags = card.tags.join(' ').toLowerCase();
    final haystack = isProduct
        ? '$name $set $trainerName $tags'
        : '$name $set $trainerName $number $tags';
    final terms = _searchTerms(query);
    final compactQuery = query.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactName = name.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactSet = set.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactNumber = number.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactTrainerName = trainerName.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactTags = tags.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactHaystack = [
      compactName,
      compactNumber,
      compactSet,
      compactTrainerName,
      compactTags,
    ].where((part) => part.isNotEmpty).join();
    final nameCoverageBonus =
        _characterCoverageScore(compactName, compactQuery);
    final coverageBonus = math.max(
      nameCoverageBonus,
      _characterCoverageScore(compactHaystack, compactQuery) ~/ 2,
    );
    int boost(int score) => score + coverageBonus;
    final hasNumberTerm =
        terms.any((term) => RegExp(r'^[0-9]+$').hasMatch(term));
    final hasVariationTerm = terms.any(_isVariationSearchTerm);
    final hasRarityTerm = terms.any(_isRaritySearchTerm);
    final hasExpansionAliasTerm = terms.any(_isExpansionAliasSearchTerm);
    final hasTextTerm = terms.any(
      (term) =>
          !RegExp(r'^[0-9]+$').hasMatch(term) &&
          !_isVariationSearchTerm(term) &&
          !_isRaritySearchTerm(term) &&
          !_isExpansionAliasSearchTerm(term),
    );
    if (terms.length > 1 &&
        (hasNumberTerm || hasVariationTerm || hasExpansionAliasTerm) &&
        hasTextTerm) {
      var matchedName = false;
      var matchedNumber = false;
      var matchedVariation = false;
      var matchedExpansion = false;
      var matchedSet = false;
      var score = 0;
      for (final term in terms) {
        final compactTerm = term.replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (RegExp(r'^[0-9]+$').hasMatch(term)) {
          final numberTokens = _searchTerms(number);
          if (number == term ||
              compactNumber == compactTerm ||
              numberTokens.contains(term)) {
            score += 1600;
            matchedNumber = true;
          } else if (number.startsWith(term) ||
              compactNumber.startsWith(compactTerm)) {
            score += 1300;
            matchedNumber = true;
          } else if (number.contains(term) ||
              compactNumber.contains(compactTerm)) {
            score += 900;
            matchedNumber = true;
          }
          continue;
        }
        if (_isVariationSearchTerm(term)) {
          if (_cardHasVariation(card, term)) {
            score += 1500;
            matchedVariation = true;
          }
          continue;
        }
        if (_isExpansionAliasSearchTerm(term)) {
          if (_cardHasExpansionAlias(card, term)) {
            score += 1550;
            matchedExpansion = true;
          }
          continue;
        }
        if (name == term || compactName == compactTerm) {
          score += 1400;
          matchedName = true;
        } else if (name.startsWith(term) ||
            compactName.startsWith(compactTerm)) {
          score += 1150;
          matchedName = true;
        } else if (_wordStartsWith(name, term)) {
          score += 980;
          matchedName = true;
        } else if (_isLikelyNameTokenTypo(name, term)) {
          score += 920;
          matchedName = true;
        } else if (_isLikelyNameTypo(compactName, compactTerm)) {
          score += 760;
          matchedName = true;
        } else if (name.contains(term) || compactName.contains(compactTerm)) {
          score += 720;
          matchedName = true;
        } else if (set.startsWith(term) || compactSet.startsWith(compactTerm)) {
          score += 520;
          matchedSet = true;
        } else if (set.contains(term) || compactSet.contains(compactTerm)) {
          score += 360;
          matchedSet = true;
        }
      }
      if (matchedName && matchedNumber) {
        return boost(score + 5200);
      }
      if (matchedName && matchedVariation) {
        return boost(score + 4400);
      }
      if (matchedName && matchedExpansion) {
        return boost(score + 4600);
      }
      if (matchedName && matchedSet) {
        return boost(score + 700);
      }
      if (matchedNumber || matchedVariation || matchedExpansion) {
        return 0;
      }
    }
    if (number == query) {
      return boost(980);
    }
    if (number.startsWith(query)) {
      return boost(880);
    }
    if (_wordStartsWith(number, query)) {
      return boost(840);
    }
    if (name == query) {
      return boost(1000);
    }
    if (compactQuery.isNotEmpty) {
      final nameDistance = _boundedDamerauLevenshtein(
        compactName,
        compactQuery,
        math.max(2, compactQuery.length ~/ 4),
      );
      if (nameDistance <= 2 && compactQuery.length >= 5) {
        return boost(940 - (nameDistance * 70));
      }
      if (compactName.startsWith(compactQuery)) {
        return boost(760);
      }
      final fuzzyName = _fuzzyPrefixScore(compactName, compactQuery);
      if (fuzzyName > 0) {
        return boost(fuzzyName);
      }
      final fuzzySet = _fuzzyPrefixScore(compactSet, compactQuery);
      if (fuzzySet > 0) {
        return boost(fuzzySet ~/ 2);
      }
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
        } else if (trainerName == term) {
          score += 210;
          matchedName = true;
        } else if (trainerName.startsWith(term)) {
          score += 170;
          matchedName = true;
        } else if (trainerName.contains(term)) {
          score += 120;
          matchedName = true;
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
      return boost(score);
    }
    if (terms.length > 1 && hasRarityTerm && hasTextTerm) {
      var score = 420;
      var matchedName = false;
      var matchedRarity = false;
      for (final term in terms) {
        if (_isRaritySearchTerm(term)) {
          if (_cardHasRarityHint(card, term)) {
            score += 420;
            matchedRarity = true;
          }
        } else if (name.startsWith(term)) {
          score += 260;
          matchedName = true;
        } else if (_wordStartsWith(name, term)) {
          score += 220;
          matchedName = true;
        } else if (name.contains(term)) {
          score += 160;
          matchedName = true;
        }
      }
      if (matchedName && matchedRarity) {
        return boost(score);
      }
    }
    if (name.startsWith(query)) {
      return boost(isPokemonIdentity ? 1120 : 800);
    }
    if (name.contains(query)) {
      return boost(600);
    }
    if (number.contains(query)) {
      return boost(700);
    }
    if (set.contains(query)) {
      return boost(isPokemonIdentity ? 260 : 350);
    }
    if (trainerName == query) {
      return boost(760);
    }
    if (trainerName.startsWith(query)) {
      return boost(640);
    }
    if (trainerName.contains(query)) {
      return boost(480);
    }
    if (tags.contains(query)) {
      return boost(180);
    }
    if (_canUseLooseCoverageFallback(
      terms: terms,
      compactQuery: compactQuery,
      hasStructuredIntent: hasTextTerm &&
          (hasNumberTerm ||
              hasVariationTerm ||
              hasRarityTerm ||
              hasExpansionAliasTerm),
      nameCoverageBonus: nameCoverageBonus,
      coverageBonus: coverageBonus,
    )) {
      return coverageBonus;
    }
    return 0;
  }

  bool _isPokemonIdentityCard(PokemonCard card) {
    if (card.itemKind == 'product') {
      return false;
    }
    final type = card.type.toLowerCase();
    if (type.isEmpty || type == 'card') {
      return false;
    }
    return !RegExp(
            r'\b(trainer|supporter|item|stadium|energy|accessory|product|sealed)\b')
        .hasMatch(type);
  }

  bool _isLikelyNameTokenTypo(String name, String term) {
    final compactTerm = term.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (compactTerm.length < 3) {
      return false;
    }
    return _searchTerms(name).any((word) {
      final compactWord = word.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (compactWord.length < 3) {
        return false;
      }
      if (compactWord.startsWith(compactTerm) ||
          compactTerm.startsWith(compactWord)) {
        return true;
      }
      final maxDistance = compactTerm.length <= 4 ? 1 : 2;
      return _boundedDamerauLevenshtein(
            compactWord,
            compactTerm,
            maxDistance,
          ) <=
          maxDistance;
    });
  }

  bool _canUseLooseCoverageFallback({
    required List<String> terms,
    required String compactQuery,
    required bool hasStructuredIntent,
    required int nameCoverageBonus,
    required int coverageBonus,
  }) {
    if (coverageBonus < 220 || compactQuery.isEmpty) {
      return false;
    }

    // Query parts like "232", "ex", "v", or "sir" are structured intent, not
    // free text. Do not let ordered-character matching override exact fields.
    if (hasStructuredIntent) {
      return false;
    }

    // For complete single-word names, loose ordered-character coverage across
    // name + set + tags admits unrelated cards like "Pokemon Communication" for
    // "porygon". Keep it only for short in-progress typing and strong name hits.
    if (terms.length <= 1 && compactQuery.length >= 5) {
      return nameCoverageBonus >= 260;
    }

    return true;
  }

  int _fuzzyPrefixScore(String target, String query) {
    if (query.isEmpty || target.isEmpty) {
      return 0;
    }
    final windowLength = math.min(target.length, math.max(query.length + 2, 3));
    final window = target.substring(0, windowLength);
    final subsequence = _orderedCharacterMatchScore(window, query);
    if (subsequence > 0) {
      return subsequence;
    }
    final prefix = target.substring(0, math.min(target.length, query.length));
    final prefixDistance = _boundedDamerauLevenshtein(prefix, query, 2);
    if (prefixDistance <= 1) {
      return 700 - (prefixDistance * 80);
    }
    final distance = _boundedDamerauLevenshtein(window, query, 2);
    if (distance <= 1) {
      return 720 - (distance * 80);
    }
    if ((target.length - query.length).abs() <= 2) {
      final fullDistance = _boundedDamerauLevenshtein(target, query, 2);
      if (fullDistance <= 1) {
        return 720 - (fullDistance * 80);
      }
      if (fullDistance == 2 && query.length >= 5) {
        return 520;
      }
    }
    if (distance == 2 && query.length >= 3) {
      return 520;
    }
    return 0;
  }

  int _orderedCharacterMatchScore(String target, String query) {
    var targetIndex = 0;
    var gaps = 0;
    for (final codeUnit in query.codeUnits) {
      final nextIndex =
          target.indexOf(String.fromCharCode(codeUnit), targetIndex);
      if (nextIndex < 0) {
        return 0;
      }
      gaps += nextIndex - targetIndex;
      targetIndex = nextIndex + 1;
    }
    return math.max(420, 700 - (gaps * 40));
  }

  int _characterCoverageScore(String target, String query) {
    if (target.isEmpty || query.isEmpty) {
      return 0;
    }
    var targetIndex = 0;
    var matched = 0;
    var gaps = 0;
    for (final codeUnit in query.codeUnits) {
      final nextIndex =
          target.indexOf(String.fromCharCode(codeUnit), targetIndex);
      if (nextIndex < 0) {
        continue;
      }
      matched += 1;
      gaps += nextIndex - targetIndex;
      targetIndex = nextIndex + 1;
    }
    if (matched == 0) {
      return 0;
    }
    final coverage = matched / query.length;
    final matchedScore = matched * 34;
    final coverageScore = (coverage * 180).round();
    return math.max(0, matchedScore + coverageScore - (gaps * 4));
  }

  int _boundedDamerauLevenshtein(String a, String b, int maxDistance) {
    if ((a.length - b.length).abs() > maxDistance) {
      return maxDistance + 1;
    }
    final matrix = List.generate(
      a.length + 1,
      (i) => List<int>.filled(b.length + 1, 0),
    );
    for (var i = 0; i <= a.length; i += 1) {
      matrix[i][0] = i;
    }
    for (var j = 0; j <= b.length; j += 1) {
      matrix[0][j] = j;
    }
    for (var i = 1; i <= a.length; i += 1) {
      var rowMin = maxDistance + 1;
      for (var j = 1; j <= b.length; j += 1) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var value = math.min(
          math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
          matrix[i - 1][j - 1] + cost,
        );
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          value = math.min(value, matrix[i - 2][j - 2] + 1);
        }
        matrix[i][j] = value;
        rowMin = math.min(rowMin, value);
      }
      if (rowMin > maxDistance) {
        return maxDistance + 1;
      }
    }
    return matrix[a.length][b.length];
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
    return _normalizeVariationSearchPhrases(query)
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .map((term) => term.trim())
        .where((term) => term.length >= 2 || term == 'v')
        .toList();
  }

  String _normalizeVariationSearchPhrases(String value) {
    return value
        .replaceAll(RegExp(r'\blv\s*\.?\s*x\b', caseSensitive: false), 'lvx')
        .replaceAll(RegExp(r'\blevel\s+x\b', caseSensitive: false), 'lvx')
        .replaceAll(RegExp(r'\bv\s*max\b', caseSensitive: false), 'vmax')
        .replaceAll(RegExp(r'\bv\s*star\b', caseSensitive: false), 'vstar')
        .replaceAll(RegExp(r'\bg\s*x\b', caseSensitive: false), 'gx')
        .replaceAll(RegExp(r'\be\s*x\b', caseSensitive: false), 'ex');
  }

  bool _isVariationSearchTerm(String term) {
    const variations = {
      'ex',
      'v',
      'vmax',
      'vstar',
      'gx',
      'lvx',
      'lv',
      'mega',
      'break',
      'radiant',
      'shining',
      'shiny',
      'prime',
    };
    return variations.contains(term.replaceAll(RegExp(r'[^a-z0-9]'), ''));
  }

  bool _cardHasVariation(PokemonCard card, String term) {
    final normalizedTerm = term.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final text = [
      card.name,
      card.rarity,
      card.type,
      card.productType,
      ...card.tags,
    ].join(' ').toLowerCase();
    final compact = text.replaceAll(RegExp(r'[^a-z0-9]'), '');
    switch (normalizedTerm) {
      case 'lvx':
        return RegExp(r'(^|[^a-z0-9])(lv\.?x|level x)([^a-z0-9]|$)')
            .hasMatch(text);
      case 'lv':
        return RegExp(r'(^|[^a-z0-9])lv\.?([0-9]+|x)([^a-z0-9]|$)')
            .hasMatch(text);
      case 'v':
        return RegExp(r'(^|[^a-z0-9])v([^a-z0-9]|$)').hasMatch(text);
      default:
        return RegExp('(^|[^a-z0-9])$normalizedTerm([^a-z0-9]|\$)')
                .hasMatch(text) ||
            compact.contains(normalizedTerm);
    }
  }

  bool _isRaritySearchTerm(String term) {
    const rarities = {
      'sir',
      'ir',
      'ur',
      'sr',
      'rare',
      'ultra',
      'secret',
      'illustration',
      'holo',
      'shiny',
    };
    return rarities.contains(term.replaceAll(RegExp(r'[^a-z0-9]'), ''));
  }

  bool _cardHasRarityHint(PokemonCard card, String term) {
    final normalizedTerm = term.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final text = [
      card.number,
      card.rarity,
      ...card.tags,
    ].join(' ').toLowerCase();
    final normalizedText = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    switch (normalizedTerm) {
      case 'sir':
        return normalizedText.contains('special illustration rare');
      case 'ir':
        return normalizedText.contains('illustration rare');
      case 'ur':
      case 'ultra':
        return normalizedText.contains('ultra rare');
      case 'sr':
      case 'secret':
        return normalizedText.contains('secret rare');
      default:
        return normalizedText.contains(normalizedTerm);
    }
  }

  List<String> _expansionAliasTargets(String term) {
    const aliases = {
      'col': ['calloflegends'],
      'calllegends': ['calloflegends'],
      'calloflegends': ['calloflegends'],
      '151': ['151', 'pokemoncard151', 'collect151'],
      'pokemon151': ['pokemoncard151'],
      'pokemoncard151': ['pokemoncard151'],
      'collect151': ['collect151'],
      'cel': ['celebrations'],
      'pal': ['paldeaevolved'],
      'obf': ['obsidianflames'],
      'obs': ['obsidianflames'],
      'svi': ['scarletviolet'],
      'sv': ['scarletviolet'],
    };
    return aliases[term.replaceAll(RegExp(r'[^a-z0-9]'), '')] ?? const [];
  }

  bool _isExpansionAliasSearchTerm(String term) {
    return _expansionAliasTargets(term).isNotEmpty;
  }

  bool _cardHasExpansionAlias(PokemonCard card, String term) {
    final compactSet =
        card.set.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return _expansionAliasTargets(term).any(
      (target) =>
          compactSet == target ||
          compactSet.startsWith(target) ||
          target.startsWith(compactSet),
    );
  }

  bool _isLikelyNameTypo(String compactName, String compactTerm) {
    if (compactTerm.length < 5 || compactName.isEmpty) {
      return false;
    }
    return compactName.startsWith(compactTerm.substring(0, 2)) &&
        _boundedDamerauLevenshtein(compactName, compactTerm, 3) <= 3;
  }

  int _meaningfulSearchLength(String query) {
    return RegExp(r'[a-z0-9]', caseSensitive: false).allMatches(query).length;
  }

  List<String> _searchQueryVariants(Iterable<String> queries) {
    final variants = <String>[];
    for (final query in queries) {
      final normalized = query.trim().toLowerCase();
      if (normalized.length < 2) {
        continue;
      }
      _addUnique(variants, normalized);
      _addUnique(variants, _expandCompactSearchAliases(normalized));
      for (final trainerVariant in _trainerQueryVariants(normalized)) {
        _addUnique(variants, trainerVariant);
      }
      for (final alias in _raritySearchAliases.entries) {
        if (_containsCompactAlias(normalized, alias.key)) {
          _addUnique(variants, alias.value);
          _addUnique(
            variants,
            _expandCompactSearchAliases(
              normalized.replaceAll(alias.key, alias.value),
            ),
          );
        }
      }
    }
    return variants;
  }

  String _expandCompactSearchAliases(String query) {
    var expanded = query;
    for (final alias in _raritySearchAliases.entries) {
      expanded = expanded.replaceAllMapped(
        RegExp('(^|[^a-z0-9])${alias.key}([^a-z0-9]|\$)'),
        (match) => '${match.group(1)}${alias.value}${match.group(2)}',
      );
    }
    return expanded.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _containsCompactAlias(String query, String alias) {
    return RegExp('(^|[^a-z0-9])$alias([^a-z0-9]|\$)').hasMatch(query);
  }

  List<String> _trainerQueryVariants(String query) {
    final terms = _searchTerms(query);
    if (terms.length < 2) {
      return const [];
    }
    final variants = <String>[];
    for (var i = 0; i < terms.length; i += 1) {
      final canonicalTrainer = _trainerSearchAliases[terms[i]];
      if (canonicalTrainer == null) {
        continue;
      }
      final pokemonTerms = [
        for (var j = 0; j < terms.length; j += 1)
          if (j != i && !_ownershipStopWords.contains(terms[j])) terms[j],
      ];
      if (pokemonTerms.isEmpty) {
        _addUnique(variants, canonicalTrainer);
        continue;
      }
      final pokemonQuery = pokemonTerms.join(' ');
      _addUnique(variants, '$pokemonQuery $canonicalTrainer');
      _addUnique(variants, '$canonicalTrainer $pokemonQuery');
      _addUnique(variants, "$canonicalTrainer's $pokemonQuery");
    }
    return variants;
  }

  void _addUnique(List<String> values, String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.length >= 2 && !values.contains(normalized)) {
      values.add(normalized);
    }
  }

  bool _wordStartsWith(String value, String term) {
    return value
        .split(RegExp(r'[^a-z0-9]+'))
        .any((word) => word.startsWith(term));
  }
}
