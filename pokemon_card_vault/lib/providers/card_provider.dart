import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pokemon_card.dart';
import 'recent_views_provider.dart';
import '../services/card_service.dart';
import '../services/flutter_debug_log.dart';
import '../services/search_debug_trace.dart';
import '../utils/card_url.dart';
import '../constants/first_char_token_suggestions.dart';

final cardProvider = StateNotifierProvider<CardNotifier, CardState>((ref) {
  return CardNotifier();
});

const int searchPreviewLimit = 20;
const int searchPreviewVisibleRows = 9;
const int searchPreviewWarmupChars = 1;
const int searchPreviewVisibleChars = 3;
const int searchPreviewHotCacheLimit = 1000;
const int _searchPreviewMaxPrefixPools = 16;
const int _searchPreviewMaxAggregatePrefixIds = 20000;
const String _searchLanguagePreferenceKey = 'marketplace.search_language';
const Set<String> _supportedSearchLanguages = {
  'en',
  'it',
  'fr',
  'de',
  'es',
  'pt',
  'nl',
  'pl',
  'ru',
  'ko',
  'id',
  'th',
  'ja',
  'zh-cn',
  'zh-tw',
};

List<PokemonCard> emptyFocusPreviewsForTest(
  List<PokemonCard> hotCards,
  List<RecentCardView> recentViews,
) {
  return _emptyFocusPreviews(hotCards, recentViews.take(2).toList());
}

List<PokemonCard> remoteSearchResultsForTest(
  List<PokemonCard> results, {
  int? limit,
}) {
  return _remoteSearchResults(results, limit: limit);
}

List<PokemonCard> searchPreviewFallbackRowsForTest({
  required String query,
  List<PokemonCard> retainedRows = const [],
  List<SearchCandidateLabel> labels = const [],
  SearchAutocompleteContext? context,
  Map<String, int> latestDepths = const {},
  Map<String, int> depthScores = const {},
  Map<String, int> latestOrders = const {},
  int limit = searchPreviewLimit,
}) {
  return _searchPreviewFallbackRows(
    query: query,
    retainedRows: retainedRows,
    labels: labels,
    context: context,
    latestDepths: latestDepths,
    depthScores: depthScores,
    latestOrders: latestOrders,
    limit: limit,
  );
}

SearchAutocompleteContext? autocompleteContextFromResponseForTest({
  required SearchAutocompleteContext? context,
  required List<PokemonCard> previews,
  required String query,
  String language = 'en',
}) {
  final notifier = CardNotifier(autoLoad: false);
  try {
    return notifier._autocompleteContextFromResponse(
      context: context,
      previews: previews,
      query: query,
      language: language,
    );
  } finally {
    notifier.dispose();
  }
}

int searchPreviewCandidateIdLimitForTest(String query) {
  return _searchPreviewCandidateIdLimit(query);
}

String normalizeSearchLanguage(String value) {
  final normalized = value.trim().toLowerCase();
  switch (normalized) {
    case 'jp':
      return 'ja';
    case 'zh':
      return 'zh-cn';
    default:
      return _supportedSearchLanguages.contains(normalized) ? normalized : 'en';
  }
}

bool needsMarketplaceDetailHydration(PokemonCard card) {
  if (card.itemKind == 'product' || card.productType != 'card') {
    return false;
  }
  if (card.number.trim().isEmpty) {
    return true;
  }
  return false;
}

String? _storedSearchLanguage(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final normalized = normalizeSearchLanguage(trimmed);
  return normalized == 'en' && trimmed.toLowerCase() != 'en'
      ? null
      : normalized;
}

class CardState {
  final List<PokemonCard> cards;
  final List<PokemonCard> filteredCards;
  final List<PokemonCard> searchPreviews;
  final List<PokemonCard> remoteSearchResults;
  final List<PokemonCard> spotlightCards;
  final MarketplaceHomeSections? homeSections;
  final bool isLoading;
  final bool isSearchingPreviews;
  final String? error;
  final String searchQuery;
  final String remoteSearchQuery;
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
  final String searchCompletion;
  final double searchCompletionConfidence;
  final String searchCompletionSource;
  final bool hasMarketplaceLoadCompleted;

  CardState({
    this.cards = const [],
    this.filteredCards = const [],
    this.searchPreviews = const [],
    this.remoteSearchResults = const [],
    this.spotlightCards = const [],
    this.homeSections,
    this.isLoading = false,
    this.isSearchingPreviews = false,
    this.error,
    this.searchQuery = '',
    this.remoteSearchQuery = '',
    this.previewQuery = '',
    this.selectedRarity = '',
    this.selectedType = '',
    this.selectedSet = '',
    this.minPrice = 0.0,
    this.maxPrice = 5000000.0,
    this.showOnlyInStock = false,
    this.sortBy = 'source',
    this.sortAscending = true,
    this.searchLanguage = 'en',
    this.searchCompletion = '',
    this.searchCompletionConfidence = 0,
    this.searchCompletionSource = '',
    this.hasMarketplaceLoadCompleted = false,
  });

  CardState copyWith({
    List<PokemonCard>? cards,
    List<PokemonCard>? filteredCards,
    List<PokemonCard>? searchPreviews,
    List<PokemonCard>? remoteSearchResults,
    List<PokemonCard>? spotlightCards,
    MarketplaceHomeSections? homeSections,
    bool? isLoading,
    bool? isSearchingPreviews,
    String? error,
    String? searchQuery,
    String? remoteSearchQuery,
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
    String? searchCompletion,
    double? searchCompletionConfidence,
    String? searchCompletionSource,
    bool? hasMarketplaceLoadCompleted,
  }) {
    return CardState(
      cards: cards ?? this.cards,
      filteredCards: filteredCards ?? this.filteredCards,
      searchPreviews: searchPreviews ?? this.searchPreviews,
      remoteSearchResults: remoteSearchResults ?? this.remoteSearchResults,
      spotlightCards: spotlightCards ?? this.spotlightCards,
      homeSections: homeSections ?? this.homeSections,
      isLoading: isLoading ?? this.isLoading,
      isSearchingPreviews: isSearchingPreviews ?? this.isSearchingPreviews,
      error: error ?? this.error,
      searchQuery: searchQuery ?? this.searchQuery,
      remoteSearchQuery: remoteSearchQuery ?? this.remoteSearchQuery,
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
      searchCompletion: searchCompletion ?? this.searchCompletion,
      searchCompletionConfidence:
          searchCompletionConfidence ?? this.searchCompletionConfidence,
      searchCompletionSource:
          searchCompletionSource ?? this.searchCompletionSource,
      hasMarketplaceLoadCompleted:
          hasMarketplaceLoadCompleted ?? this.hasMarketplaceLoadCompleted,
    );
  }
}

class _MergedMarketplaceFields {
  const _MergedMarketplaceFields({
    required this.price,
    required this.stock,
    required this.hasCardTraderListing,
    required this.cardtraderEligibleListingCount,
    required this.watchlistCount,
    required this.cartHolderCount,
    required this.rating,
  });

  final double price;
  final int stock;
  final bool hasCardTraderListing;
  final int cardtraderEligibleListingCount;
  final int watchlistCount;
  final int cartHolderCount;
  final double rating;
}

class CardNotifier extends StateNotifier<CardState> {
  CardNotifier({
    CardService? cardService,
    bool autoLoad = true,
  })  : _cardService = cardService ?? CardService(),
        super(CardState()) {
    _searchLanguageLoad = _loadStoredSearchLanguage();
    if (autoLoad) {
      _initialCacheLoad = _loadCachedCards();
      _warmSearchPreviews();
    } else {
      _initialCacheLoad = Future<void>.value();
    }
  }

  final CardService _cardService;
  late final Future<void> _initialCacheLoad;
  late final Future<void> _searchLanguageLoad;
  Future<void> _searchLanguagePersist = Future<void>.value();
  bool _searchLanguageChangedLocally = false;
  int _searchPreviewRequestId = 0;
  int _searchRequestId = 0;
  int _searchTokenPredictRequestId = 0;
  int _navigationPriorityToken = 0;
  bool _marketplaceWarmStarted = false;
  bool _navigationTransitionActive = false;
  bool _refreshCardsAfterNavigation = false;
  Timer? _searchPreviewDebounce;
  Timer? _searchTokenPredictDebounce;
  Timer? _navigationPriorityTimer;
  SearchAutocompleteContext? _searchAutocompleteContext;
  String? _searchSessionId;
  String _lastSearchSessionQuery = '';
  int _searchSessionSequence = 0;
  List<PokemonCard> _hotSearchPreviewCache = const [];
  final Map<String, List<PokemonCard>> _retainedSearchPreviewsByScope = {};
  final Map<String, SearchCandidateLabel> _searchCandidateLabelsById = {};
  final Map<String, int> _searchCandidateLatestDepthById = {};
  final Map<String, int> _searchCandidateDepthScoreById = {};
  final Map<String, int> _searchCandidateLatestOrderById = {};
  final Map<String, _SearchPrefixPool> _searchPrefixPoolsByKey = {};
  List<SearchPredictedNameToken> _searchPredictedNameTokens = const [];
  SearchTokenPredictionContext? _searchTokenPredictionContext;

  bool get _hasWarmMarketplaceData =>
      state.hasMarketplaceLoadCompleted || state.homeSections != null;

  int get navigationPriorityToken => _navigationPriorityToken;
  bool get isNavigationTransitionActive => _navigationTransitionActive;

  Future<void> ensureSearchLanguageLoaded() => _searchLanguageLoad;

  Future<void> searchLanguagePersistForTest() => _searchLanguagePersist;

  int beginNavigationTransition({
    Duration duration = const Duration(milliseconds: 850),
  }) {
    _navigationPriorityToken++;
    _navigationTransitionActive = true;
    _marketplaceWarmStarted = false;
    _searchRequestId++;
    _searchPreviewRequestId++;
    _searchTokenPredictRequestId++;
    _searchPreviewDebounce?.cancel();
    _searchTokenPredictDebounce?.cancel();
    _navigationPriorityTimer?.cancel();
    _navigationPriorityTimer = Timer(duration, _finishNavigationTransition);
    return _navigationPriorityToken;
  }

  bool shouldSkipNavigationDeferredResult(int token) {
    return !mounted ||
        token != _navigationPriorityToken ||
        _navigationTransitionActive;
  }

  void _finishNavigationTransition() {
    if (!mounted) {
      return;
    }
    _navigationTransitionActive = false;
    if (_refreshCardsAfterNavigation) {
      _refreshCardsAfterNavigation = false;
      unawaited(refreshCards());
    }
  }

  Future<void> _loadStoredSearchLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawLanguage = prefs.getString(_searchLanguagePreferenceKey);
      final storedLanguage = _storedSearchLanguage(rawLanguage);
      if (rawLanguage != null && storedLanguage == null) {
        await prefs.remove(_searchLanguagePreferenceKey);
      } else if (storedLanguage != null && storedLanguage != rawLanguage) {
        await prefs.setString(_searchLanguagePreferenceKey, storedLanguage);
      }
      if (!mounted ||
          _searchLanguageChangedLocally ||
          storedLanguage == null ||
          storedLanguage == state.searchLanguage) {
        return;
      }
      _changeSearchLanguage(storedLanguage);
    } catch (_) {
      // Search stays usable with the default English language if local storage
      // is unavailable.
    }
  }

  Future<void> _saveSearchLanguage(String language) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _searchLanguagePreferenceKey,
        normalizeSearchLanguage(language),
      );
    } catch (_) {
      // Preference persistence is best effort and must not block searching.
    }
  }

  Future<void> _loadCachedCards() async {
    final token = _navigationPriorityToken;
    try {
      final cachedCards = await _cardService.getCachedCards();
      final cachedSnapshot =
          await _cardService.getCachedMarketplaceHomeSnapshot();
      final cachedSpotlightCards = await _cardService.getCachedSpotlightCards();
      if (!mounted || token != _navigationPriorityToken) {
        return;
      }
      if (cachedCards.isNotEmpty || cachedSnapshot != null) {
        final warmedCards = cachedSnapshot == null
            ? cachedCards
            : _mergeCards(cachedCards, cachedSnapshot.cards);
        _hotSearchPreviewCache = _hotCardsFromSnapshot(cachedSnapshot) ??
            _hotCardsFromCards(warmedCards);
        state = state.copyWith(
          cards: warmedCards,
          filteredCards: warmedCards,
          spotlightCards: _spotlightCardsFromSources(
            cachedSnapshot,
            warmedCards,
            cachedSpotlightCards,
          ),
          homeSections: cachedSnapshot?.sections,
          isLoading: false,
          hasMarketplaceLoadCompleted: true,
          error: null,
        );
        _applyFilters();
      } else {
        state = state.copyWith(isLoading: true, error: null);
      }
    } catch (e) {
      if (!mounted || token != _navigationPriorityToken) {
        return;
      }
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> _loadCards({
    bool preserveCurrent = true,
    int? navigationToken,
  }) async {
    final token = navigationToken ?? _navigationPriorityToken;
    FlutterDebugLog.instance.record(
      'provider.load_cards.start',
      category: 'provider',
      payload: {
        'currentCardCount': state.cards.length,
        'hasHomeSections': state.homeSections != null,
      },
    );
    try {
      await _initialCacheLoad;
      if (!mounted || token != _navigationPriorityToken) {
        _marketplaceWarmStarted = false;
        return;
      }
      if (state.cards.isEmpty && !state.isLoading) {
        state = state.copyWith(isLoading: true, error: null);
      }

      final snapshot = await _cardService.getMarketplaceHomeSnapshot();
      if (!mounted || token != _navigationPriorityToken) {
        _marketplaceWarmStarted = false;
        return;
      }
      final cards = snapshot == null
          ? await _cardService.getAllCards()
          : await _cardService.getCachedCards();
      if (!mounted || token != _navigationPriorityToken) {
        _marketplaceWarmStarted = false;
        return;
      }
      final loadedCards =
          snapshot == null ? cards : _mergeCards(cards, snapshot.cards);
      final mergedCards = preserveCurrent
          ? _mergeCards(
              loadedCards,
              state.cards,
              preserveExistingMarketplaceFields: true,
            )
          : loadedCards;
      _hotSearchPreviewCache =
          _hotCardsFromSnapshot(snapshot) ?? _hotCardsFromCards(mergedCards);
      final cachedSpotlightCards = await _cardService.getCachedSpotlightCards();
      if (!mounted || token != _navigationPriorityToken) {
        _marketplaceWarmStarted = false;
        return;
      }
      state = state.copyWith(
        cards: mergedCards,
        filteredCards: mergedCards,
        spotlightCards: _spotlightCardsFromSources(
          snapshot,
          mergedCards,
          cachedSpotlightCards,
        ),
        homeSections: snapshot?.sections,
        isLoading: false,
        hasMarketplaceLoadCompleted: true,
      );
      _applyFilters();
      FlutterDebugLog.instance.record(
        'provider.load_cards.end',
        category: 'provider',
        payload: {
          'cardCount': mergedCards.length,
          'snapshotLoaded': snapshot != null,
          'hotPreviewCount': _hotSearchPreviewCache.length,
        },
      );
    } catch (e) {
      if (!mounted || token != _navigationPriorityToken) {
        _marketplaceWarmStarted = false;
        return;
      }
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      FlutterDebugLog.instance.recordError(
        'provider.load_cards.error',
        e,
        category: 'provider',
      );
    }
  }

  void searchCards(String query) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isNotEmpty) {
      _prepareSearchSessionForQuery(normalizedQuery);
    }
    final searchSessionId =
        normalizedQuery.isEmpty ? null : _ensureSearchSession(normalizedQuery);
    state = state.copyWith(
      searchQuery: query,
      remoteSearchResults:
          normalizedQuery.isEmpty ? const [] : state.remoteSearchResults,
      remoteSearchQuery: normalizedQuery.isEmpty ? '' : state.remoteSearchQuery,
      searchCompletion: normalizedQuery.isEmpty
          ? ''
          : _validatedSearchCompletion(normalizedQuery),
      searchCompletionConfidence: normalizedQuery.isEmpty
          ? 0
          : _searchCompletionConfidence(normalizedQuery),
      searchCompletionSource: normalizedQuery.isEmpty
          ? ''
          : _searchCompletionSource(normalizedQuery),
    );
    _applyFilters();
    _loadSearchPreviews(query, searchSessionId: searchSessionId);
    _loadFullSearchResults(query, searchSessionId: searchSessionId);
    final firstMatch =
        state.filteredCards.isEmpty ? null : state.filteredCards.first;
    if (_meaningfulSearchLength(query.trim()) >= 1 && firstMatch != null) {
      _cardService.recordMarketplaceEvent(
        firstMatch,
        'search',
        source: 'marketplace_search',
        metadata: {
          'query': query.trim(),
          'resultRank': 1,
          'resultCount': state.filteredCards.length,
          'language': state.searchLanguage,
        },
      );
    }
  }

  void searchPreviewsOnly(String query) {
    _searchRequestId++;
    _searchPreviewRequestId++;
    _searchTokenPredictRequestId++;
    _searchPreviewDebounce?.cancel();
    _searchTokenPredictDebounce?.cancel();
    SearchDebugTrace.instance.record('provider.preview.input', {
      'query': query,
      'searchRequestId': _searchRequestId,
      'previewRequestId': _searchPreviewRequestId,
    });
    final wasShowingEmptyFocusPreviews = state.previewQuery.trim().isEmpty &&
        state.searchPreviews.isNotEmpty &&
        !state.isSearchingPreviews;
    final normalizedQuery = query.trim();
    final isQueryBranchChange = normalizedQuery.isNotEmpty &&
        _isSearchSessionBranchChange(normalizedQuery);
    if (normalizedQuery.isNotEmpty) {
      _prepareSearchSessionForQuery(normalizedQuery);
    }
    final searchSessionId =
        normalizedQuery.isEmpty ? null : _ensureSearchSession(normalizedQuery);
    _applyFirstCharCompletionCache(normalizedQuery);
    final canShowTypedPopup =
        _meaningfulSearchLength(normalizedQuery) >= searchPreviewVisibleChars;
    state = state.copyWith(
      previewQuery: query,
      searchPreviews: normalizedQuery.isNotEmpty &&
              (wasShowingEmptyFocusPreviews || !canShowTypedPopup)
          ? const []
          : state.searchPreviews,
      isSearchingPreviews:
          normalizedQuery.isNotEmpty && wasShowingEmptyFocusPreviews
              ? canShowTypedPopup
              : state.isSearchingPreviews && canShowTypedPopup,
      searchCompletion: _validatedSearchCompletion(normalizedQuery),
      searchCompletionConfidence: _searchCompletionConfidence(normalizedQuery),
      searchCompletionSource: _searchCompletionSource(normalizedQuery),
    );
    if (normalizedQuery.isEmpty) {
      _cancelSearchSession(reason: 'clear');
      _clearSearchPrefixPoolHistory();
      _searchTokenPredictionContext = null;
      SearchDebugTrace.instance.record('provider.preview.empty_focus', {
        'cachedHotCount': _hotSearchPreviewCache.length,
      });
      state = state.copyWith(
        previewQuery: '',
        searchPreviews: const [],
        isSearchingPreviews: false,
        searchCompletion: '',
        searchCompletionConfidence: 0,
        searchCompletionSource: '',
      );
      return;
    }
    if (wasShowingEmptyFocusPreviews) {
      SearchDebugTrace.instance.record('provider.preview.clear_empty_hot', {
        'query': normalizedQuery,
        'reason': 'typed_remote_authoritative',
      });
    }
    final emptyFocusPreviews = wasShowingEmptyFocusPreviews
        ? state.searchPreviews
        : const <PokemonCard>[];
    final filteredPreviews = _pendingSearchPreviewFallbackForQuery(
      normalizedQuery,
      retainedPreviews: emptyFocusPreviews,
      includeHotFallback: !isQueryBranchChange,
    );
    if (_meaningfulSearchLength(normalizedQuery) < searchPreviewWarmupChars &&
        !_isStandaloneVariationQuery(normalizedQuery)) {
      SearchDebugTrace.instance.record('provider.preview.clear_short_query', {
        'query': normalizedQuery,
        'meaningfulChars': _meaningfulSearchLength(normalizedQuery),
      });
      state = state.copyWith(
        previewQuery: '',
        searchPreviews: const [],
        isSearchingPreviews: false,
        searchCompletion: '',
        searchCompletionConfidence: 0,
        searchCompletionSource: '',
      );
      return;
    }
    final tokenPredictRequestId = _searchTokenPredictRequestId;
    _searchTokenPredictDebounce = Timer(
      const Duration(milliseconds: 35),
      () => unawaited(_loadSearchTokenPrediction(
        normalizedQuery,
        requestId: tokenPredictRequestId,
        language: state.searchLanguage,
      )),
    );
    state = state.copyWith(
      searchPreviews: canShowTypedPopup ? filteredPreviews : const [],
      isSearchingPreviews: canShowTypedPopup,
    );
    _searchPreviewDebounce = Timer(
      const Duration(milliseconds: 120),
      () {
        SearchDebugTrace.instance.record('provider.preview.debounce_fire', {
          'query': normalizedQuery,
          'delayMs': 120,
        });
        _loadSearchPreviews(
          normalizedQuery,
          searchSessionId: searchSessionId,
        );
      },
    );
    SearchDebugTrace.instance.record('provider.preview.debounce_scheduled', {
      'query': normalizedQuery,
      'delayMs': 120,
    });
  }

  void predictSearchCompletionOnly(String query) {
    _searchRequestId++;
    _searchPreviewRequestId++;
    _searchTokenPredictRequestId++;
    _searchPreviewDebounce?.cancel();
    _searchTokenPredictDebounce?.cancel();
    final normalizedQuery = query.trim();
    if (normalizedQuery.isNotEmpty) {
      _prepareSearchSessionForQuery(normalizedQuery);
      _ensureSearchSession(normalizedQuery);
    }
    _applyFirstCharCompletionCache(normalizedQuery);
    state = state.copyWith(
      previewQuery: query,
      searchPreviews: const [],
      isSearchingPreviews: false,
      searchCompletion: _validatedSearchCompletion(normalizedQuery),
      searchCompletionConfidence: _searchCompletionConfidence(normalizedQuery),
      searchCompletionSource: _searchCompletionSource(normalizedQuery),
    );
    if (normalizedQuery.isEmpty) {
      _cancelSearchSession(reason: 'clear');
      _clearSearchPrefixPoolHistory();
      state = state.copyWith(
        previewQuery: '',
        searchCompletion: '',
        searchCompletionConfidence: 0,
        searchCompletionSource: '',
      );
      return;
    }
    if (_meaningfulSearchLength(normalizedQuery) < searchPreviewWarmupChars &&
        !_isStandaloneVariationQuery(normalizedQuery)) {
      state = state.copyWith(
        searchCompletion: '',
        searchCompletionConfidence: 0,
        searchCompletionSource: '',
      );
      return;
    }
    final tokenPredictRequestId = _searchTokenPredictRequestId;
    _searchTokenPredictDebounce = Timer(
      const Duration(milliseconds: 35),
      () => unawaited(_loadSearchTokenPrediction(
        normalizedQuery,
        requestId: tokenPredictRequestId,
        language: state.searchLanguage,
      )),
    );
  }

  void clearSearchPreviews() {
    _searchRequestId++;
    _searchPreviewRequestId++;
    _searchTokenPredictRequestId++;
    _searchPreviewDebounce?.cancel();
    _searchTokenPredictDebounce?.cancel();
    _searchAutocompleteContext = null;
    _searchPredictedNameTokens = const [];
    _searchTokenPredictionContext = null;
    _cancelSearchSession(reason: 'clear');
    _clearSearchPrefixPoolHistory();
    state = state.copyWith(
      previewQuery: '',
      searchPreviews: const [],
      isSearchingPreviews: false,
      searchCompletion: '',
      searchCompletionConfidence: 0,
      searchCompletionSource: '',
    );
  }

  void setSearchLanguage(String language) {
    final normalized = normalizeSearchLanguage(language);
    if (normalized == state.searchLanguage) {
      _searchLanguageChangedLocally = true;
      _searchLanguagePersist = _saveSearchLanguage(normalized);
      return;
    }
    _searchLanguageChangedLocally = true;
    _searchLanguagePersist = _saveSearchLanguage(normalized);
    _changeSearchLanguage(normalized);
  }

  void _changeSearchLanguage(String normalized) {
    _searchAutocompleteContext = null;
    _searchPredictedNameTokens = const [];
    _searchTokenPredictionContext = null;
    _cancelSearchSession(reason: 'language_change');
    _clearSearchPrefixPoolHistory();
    state = state.copyWith(
      searchLanguage: normalized,
      searchCompletion: '',
      searchCompletionConfidence: 0,
      searchCompletionSource: '',
    );
    final searchSessionId = _meaningfulSearchLength(state.previewQuery) >=
                searchPreviewWarmupChars ||
            _meaningfulSearchLength(state.searchQuery.trim()) >= 1 ||
            _isStandaloneVariationQuery(state.searchQuery)
        ? _ensureSearchSession(
            state.previewQuery.trim().isNotEmpty
                ? state.previewQuery
                : state.searchQuery,
          )
        : null;
    if (_meaningfulSearchLength(state.previewQuery) >=
        searchPreviewWarmupChars) {
      _loadSearchPreviews(
        state.previewQuery,
        searchSessionId: searchSessionId,
      );
    }
    if (_meaningfulSearchLength(state.searchQuery.trim()) >= 1 ||
        _isStandaloneVariationQuery(state.searchQuery)) {
      _loadFullSearchResults(
        state.searchQuery,
        searchSessionId: searchSessionId,
      );
    }
  }

  Future<void> _loadFullSearchResults(
    String query, {
    String? searchSessionId,
  }) async {
    final requestId = ++_searchRequestId;
    final normalizedQuery = query.trim();
    if (_meaningfulSearchLength(normalizedQuery) < 1 &&
        !_isStandaloneVariationQuery(normalizedQuery)) {
      return;
    }

    final results = await _cardService.searchMarketplaceCards(
      normalizedQuery,
      limit: 240,
      searchLanguage: state.searchLanguage,
      searchSessionId: searchSessionId,
    );
    if (requestId != _searchRequestId ||
        normalizedQuery != state.searchQuery.trim()) {
      return;
    }
    if (results.isEmpty) {
      return;
    }
    final remoteResults = _remoteSearchResults(results, limit: 240);
    state = state.copyWith(
      cards: _mergeCards(state.cards, remoteResults),
      remoteSearchResults: remoteResults,
      remoteSearchQuery: normalizedQuery,
    );
    _applyFilters();
  }

  void recordCardInteraction(
    PokemonCard card,
    String eventType, {
    String source = 'marketplace',
    Map<String, Object?> metadata = const {},
  }) {
    _cardService.recordMarketplaceEvent(
      card,
      eventType,
      source: source,
      metadata: metadata,
    );
  }

  Future<PokemonCard?> loadCardById(String id) async {
    final existing = _findLoadedCard(id);
    if (existing != null) {
      if (_needsDetailHydration(existing)) {
        final refreshed = await _refreshCardById(id);
        return refreshed ?? existing;
      }
      unawaited(_refreshCardById(id));
      return existing;
    }

    final cached = await _cardService.getCachedCardById(id);
    if (cached != null) {
      state = state.copyWith(cards: _mergeCards(state.cards, [cached]));
      _applyFilters();
      unawaited(_refreshCardById(id));
      return cached;
    }

    final card = await _cardService.getCardById(id);
    if (card == null) {
      return null;
    }

    state = state.copyWith(cards: _mergeCards(state.cards, [card]));
    _applyFilters();
    recordCardInteraction(card, 'view', source: 'card_detail_direct');
    return card;
  }

  Future<PokemonCard?> loadCardByDetailSlug(String slug) async {
    final normalizedSlug = normalizeCardDetailSlug(slug);
    final existing = _findLoadedCardBySlug(normalizedSlug);
    if (existing != null) {
      if (_needsDetailHydration(existing)) {
        final refreshed = await _refreshCardById(existing.id);
        return refreshed ?? existing;
      }
      return existing;
    }

    final cached = await _cardService.getCachedCardByDetailSlug(normalizedSlug);
    if (cached != null) {
      state = state.copyWith(cards: _mergeCards(state.cards, [cached]));
      _applyFilters();
      return cached;
    }

    final card = await _cardService.getCardByDetailSlug(normalizedSlug);
    if (card == null) {
      return null;
    }

    state = state.copyWith(cards: _mergeCards(state.cards, [card]));
    _applyFilters();
    recordCardInteraction(card, 'view', source: 'card_detail_slug_direct');
    return card;
  }

  Future<PokemonCard?> _refreshCardById(
    String id, {
    int? navigationToken,
  }) async {
    try {
      final card = await _cardService.getCardById(id);
      if (card == null ||
          !mounted ||
          (navigationToken != null &&
              (navigationToken != _navigationPriorityToken ||
                  _navigationTransitionActive))) {
        return null;
      }
      state = state.copyWith(cards: _mergeCards(state.cards, [card]));
      _applyFilters();
      return card;
    } catch (_) {
      // Cached detail pages should not regress if the background refresh fails.
      return null;
    }
  }

  bool _needsDetailHydration(PokemonCard card) {
    return needsMarketplaceDetailHydration(card);
  }

  Future<void> _loadSearchPreviews(
    String query, {
    String? searchSessionId,
  }) async {
    final requestId = ++_searchPreviewRequestId;
    final normalizedQuery = query.trim();
    final meaningfulChars = _meaningfulSearchLength(normalizedQuery);
    final isStandaloneVariationQuery =
        _isStandaloneVariationQuery(normalizedQuery);
    final canShowAutocomplete = meaningfulChars >= searchPreviewVisibleChars;
    SearchDebugTrace.instance.record('provider.preview.load_start', {
      'query': normalizedQuery,
      'requestId': requestId,
      'meaningfulChars': meaningfulChars,
      'canShowAutocomplete': canShowAutocomplete,
      'language': state.searchLanguage,
    });
    if (meaningfulChars < searchPreviewWarmupChars &&
        !isStandaloneVariationQuery) {
      SearchDebugTrace.instance.record('provider.preview.load_clear_short', {
        'query': normalizedQuery,
        'requestId': requestId,
      });
      state = state.copyWith(
        previewQuery: '',
        searchPreviews: const [],
        isSearchingPreviews: false,
        searchCompletion: '',
        searchCompletionConfidence: 0,
        searchCompletionSource: '',
      );
      return;
    }

    final requestedLanguage = state.searchLanguage;
    final previousContext = _searchAutocompleteContext?.canRefine(
              normalizedQuery,
              requestedLanguage,
            ) ==
            true
        ? _searchAutocompleteContext
        : null;
    SearchDebugTrace.instance.record('provider.preview.local_disabled', {
      'query': normalizedQuery,
      'requestId': requestId,
      'reason': 'remote_authoritative',
      'localHotCount': 0,
    });
    final filteredPreviews =
        _pendingSearchPreviewFallbackForQuery(normalizedQuery);
    state = state.copyWith(
      searchPreviews: canShowAutocomplete ? filteredPreviews : const [],
      isSearchingPreviews: canShowAutocomplete,
    );

    SearchDebugTrace.instance.record('provider.preview.remote_start', {
      'query': normalizedQuery,
      'requestId': requestId,
      'limit': searchPreviewLimit,
      'poolLimit': _searchPreviewCandidateIdLimit(normalizedQuery),
      'language': requestedLanguage,
      if (searchSessionId?.isNotEmpty == true)
        'searchSessionId': searchSessionId,
    });
    final preciseResult = await _cardService.searchAutocompleteCardsWithContext(
      normalizedQuery,
      limit: searchPreviewLimit,
      poolLimit: _searchPreviewCandidateIdLimit(normalizedQuery),
      searchLanguage: requestedLanguage,
      previousSearchContext: previousContext,
      predictionContext: _searchTokenPredictionContext?.canRefine(
                normalizedQuery,
                requestedLanguage,
              ) ==
              true
          ? _searchTokenPredictionContext
          : null,
      searchSessionId: searchSessionId,
    );
    if (!mounted) {
      return;
    }
    final effectiveContext = _autocompleteContextFromResponse(
      context: preciseResult.context,
      previews: preciseResult.cards,
      query: normalizedQuery,
      language: requestedLanguage,
    );
    final contextIds = effectiveContext?.cardIds ?? const <String>[];
    final contextIdSet = contextIds.toSet();
    final previewById = <String, PokemonCard>{
      for (final card in preciseResult.cards)
        if (contextIdSet.contains(card.id)) card.id: card,
    };
    final previews = contextIds
        .map((id) => previewById[id])
        .whereType<PokemonCard>()
        .take(searchPreviewLimit)
        .toList(growable: false);
    final effectivePreviews = previews.isNotEmpty
        ? previews
        : preciseResult.cards.take(searchPreviewLimit).toList(growable: false);
    final currentQuery = state.previewQuery.trim();
    final currentMeaningfulChars = _meaningfulSearchLength(currentQuery);
    final currentCanShowAutocomplete =
        currentMeaningfulChars >= searchPreviewVisibleChars;
    final responseStillMatchesCurrentPool = normalizedQuery == currentQuery &&
        requestedLanguage == state.searchLanguage;
    final responseCompatibleWithCurrentPool =
        requestedLanguage == state.searchLanguage &&
            currentQuery.isNotEmpty &&
            _prefixPoolQueryExtends(normalizedQuery, currentQuery);
    SearchDebugTrace.instance.record('provider.preview.remote_response', {
      'query': normalizedQuery,
      'requestId': requestId,
      'previewCount': effectivePreviews.length,
      'poolSize': preciseResult.poolSize,
      'poolSource': preciseResult.poolSource,
      'currentQuery': currentQuery,
      'responseStillMatchesCurrentPool': responseStillMatchesCurrentPool,
      'latestRequestId': _searchPreviewRequestId,
    });
    if (requestId != _searchPreviewRequestId) {
      if (responseCompatibleWithCurrentPool) {
        _rememberSearchPoolResponse(
          query: normalizedQuery,
          language: requestedLanguage,
          context: effectiveContext,
          previews: effectivePreviews,
          searchSessionId: searchSessionId,
        );
        final pendingFallback = _fallbackPreviewsForQuery(currentQuery);
        if (currentCanShowAutocomplete && pendingFallback.isNotEmpty) {
          state = state.copyWith(searchPreviews: pendingFallback);
        }
      }
      SearchDebugTrace.instance.record('provider.preview.remote_drop_stale', {
        'query': normalizedQuery,
        'requestId': requestId,
        'latestRequestId': _searchPreviewRequestId,
        'responseStillMatchesCurrentPool': responseStillMatchesCurrentPool,
      });
      return;
    }
    if (responseStillMatchesCurrentPool) {
      if (effectiveContext != null) {
        _searchAutocompleteContext = effectiveContext;
      } else if (_searchAutocompleteContext?.canRefine(
            currentQuery,
            requestedLanguage,
          ) !=
          true) {
        _searchAutocompleteContext = null;
      }
      _rememberSearchPoolResponse(
        query: currentQuery.isEmpty ? normalizedQuery : currentQuery,
        language: requestedLanguage,
        context: effectiveContext,
        previews: effectivePreviews,
        searchSessionId: searchSessionId,
      );
    } else {
      _searchAutocompleteContext = null;
      _searchPredictedNameTokens = const [];
      _searchTokenPredictionContext = null;
    }
    final shouldShowAutocomplete = responseStillMatchesCurrentPool
        ? currentCanShowAutocomplete
        : canShowAutocomplete;
    SearchDebugTrace.instance.record('provider.preview.render', {
      'query': currentQuery.isEmpty ? normalizedQuery : currentQuery,
      'requestId': requestId,
      'renderedPreviews': effectivePreviews.length,
      'top': effectivePreviews
          .take(8)
          .map((card) => {
                'id': card.id,
                'name': card.name,
                'set': card.set,
                'number': card.number,
              })
          .toList(),
    });
    if (responseStillMatchesCurrentPool) {
      _rememberSearchPreviews(
        currentQuery.isEmpty ? normalizedQuery : currentQuery,
        requestedLanguage,
        effectivePreviews,
        searchSessionId: searchSessionId,
      );
    }
    final fallbackPreviews = responseStillMatchesCurrentPool
        ? _fallbackPreviewsForQuery(
            currentQuery.isEmpty ? normalizedQuery : currentQuery)
        : _fallbackPreviewsForQuery(normalizedQuery);
    final renderedPreviews =
        fallbackPreviews.isNotEmpty ? fallbackPreviews : effectivePreviews;
    state = state.copyWith(
      searchPreviews: shouldShowAutocomplete ? renderedPreviews : const [],
      isSearchingPreviews: requestId == _searchPreviewRequestId
          ? false
          : state.isSearchingPreviews,
      searchCompletion: responseStillMatchesCurrentPool
          ? _validatedSearchCompletion(currentQuery)
          : _validatedSearchCompletion(normalizedQuery),
      searchCompletionConfidence: responseStillMatchesCurrentPool
          ? _searchCompletionConfidence(currentQuery)
          : _searchCompletionConfidence(normalizedQuery),
      searchCompletionSource: responseStillMatchesCurrentPool
          ? _searchCompletionSource(currentQuery)
          : _searchCompletionSource(normalizedQuery),
    );
  }

  Future<void> _loadSearchTokenPrediction(
    String query, {
    required int requestId,
    required String language,
  }) async {
    final normalizedQuery = query.trim();
    if (_meaningfulSearchLength(normalizedQuery) < searchPreviewWarmupChars) {
      return;
    }
    SearchDebugTrace.instance.record('provider.completion.fast_start', {
      'query': normalizedQuery,
      'requestId': requestId,
      'language': language,
    });
    final previousContext = _searchTokenPredictionContext?.canRefine(
              normalizedQuery,
              language,
            ) ==
            true
        ? _searchTokenPredictionContext
        : null;
    final result = await _cardService.predictSearchNameTokensWithContext(
      normalizedQuery,
      limit: 5,
      searchLanguage: language,
      previousPredictionContext: previousContext,
    );
    if (!mounted ||
        requestId != _searchTokenPredictRequestId ||
        normalizedQuery != state.previewQuery.trim() ||
        language != state.searchLanguage) {
      SearchDebugTrace.instance.record('provider.completion.fast_drop_stale', {
        'query': normalizedQuery,
        'requestId': requestId,
        'latestRequestId': _searchTokenPredictRequestId,
      });
      return;
    }
    final tokens = result.tokens;
    if (tokens.isEmpty &&
        _existingPredictionCanComplete(normalizedQuery, language)) {
      _searchTokenPredictionContext = result.context ?? previousContext;
    } else {
      _searchPredictedNameTokens = tokens;
      _searchTokenPredictionContext = result.context;
    }
    SearchDebugTrace.instance.record('provider.completion.fast_tokens', {
      'query': normalizedQuery,
      'requestId': requestId,
      'count': tokens.length,
      'top': tokens
          .take(3)
          .map((token) => {
                'display': token.display,
                'confidence': token.confidence,
                'source': token.source,
              })
          .toList(growable: false),
    });
    state = state.copyWith(
      searchCompletion: _validatedSearchCompletion(normalizedQuery),
      searchCompletionConfidence: _searchCompletionConfidence(normalizedQuery),
      searchCompletionSource: _searchCompletionSource(normalizedQuery),
    );
  }

  Future<void> _warmSearchPreviews() async {
    final token = _navigationPriorityToken;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted || token != _navigationPriorityToken) {
      return;
    }
    try {
      await _initialCacheLoad;
      final snapshot = await _cardService.getMarketplaceHomeSnapshot();
      if (!mounted || token != _navigationPriorityToken) {
        return;
      }
      if (snapshot != null) {
        _hotSearchPreviewCache =
            _hotCardsFromSnapshot(snapshot) ?? _hotSearchPreviewCache;
        final warmedCards = _mergeCards(state.cards, snapshot.cards);
        state = state.copyWith(
          cards: warmedCards,
          filteredCards: state.searchQuery.trim().isEmpty
              ? warmedCards
              : state.filteredCards,
          spotlightCards: _spotlightCardsFromSources(
            snapshot,
            warmedCards,
            state.spotlightCards,
          ),
          homeSections: snapshot.sections,
        );
        _applyFilters();
      }
    } catch (_) {
      // Best-effort warmup only; real searches still handle retries.
    }
  }

  void showHotSearchPreviewsForEmptyFocus({
    List<RecentCardView> recentViews = const [],
  }) {
    _searchRequestId++;
    _searchPreviewRequestId++;
    _searchTokenPredictRequestId++;
    _searchPreviewDebounce?.cancel();
    _searchTokenPredictDebounce?.cancel();
    _searchAutocompleteContext = null;
    _searchPredictedNameTokens = const [];
    _searchTokenPredictionContext = null;
    _clearSearchPrefixPoolHistory();
    final requestId = _searchPreviewRequestId;
    final recentBlueprints = recentViews.take(2).toList(growable: false);
    final localHotCards = _hotSearchPreviewCache.isNotEmpty
        ? _hotSearchPreviewCache
        : _hotCardsFromCards(state.cards);
    final cached = _emptyFocusPreviews(
      localHotCards,
      recentBlueprints,
    );
    state = state.copyWith(
      previewQuery: '',
      searchPreviews: cached,
      isSearchingPreviews: false,
      searchCompletion: '',
      searchCompletionConfidence: 0,
      searchCompletionSource: '',
    );
    SearchDebugTrace.instance.record('provider.preview.empty_focus_local', {
      'requestId': requestId,
      'cachedHotCount': _hotSearchPreviewCache.length,
      'localHotCount': localHotCards.length,
      'renderedCount': cached.length,
      'cacheLimit': searchPreviewHotCacheLimit,
      'renderLimit': searchPreviewLimit,
      'recentBlueprintCount': recentBlueprints.length,
    });
  }

  List<PokemonCard>? _hotCardsFromSnapshot(MarketplaceHomeSnapshot? snapshot) {
    if (snapshot == null) {
      return null;
    }
    final byId = {for (final card in snapshot.cards) card.id: card};
    final ids = [
      ...snapshot.sections.bestSellerIds,
      ...snapshot.sections.recentlySeenIds,
      ...snapshot.sections.featuredIds,
    ];
    final cards = <PokemonCard>[];
    final seen = <String>{};
    for (final id in ids) {
      final card = byId[id];
      if (card == null || !seen.add(card.id)) {
        continue;
      }
      cards.add(card);
      if (cards.length >= searchPreviewHotCacheLimit) {
        break;
      }
    }
    if (cards.isNotEmpty) {
      return cards;
    }
    return _hotCardsFromCards(snapshot.cards);
  }

  List<PokemonCard> _spotlightCardsFromSources(
    MarketplaceHomeSnapshot? snapshot,
    List<PokemonCard> cards,
    List<PokemonCard> cachedSpotlightCards,
  ) {
    final byId = <String, PokemonCard>{
      for (final card in cachedSpotlightCards)
        if (card.id.isNotEmpty) card.id: card,
      for (final card in cards)
        if (card.id.isNotEmpty) card.id: card,
      for (final card in snapshot?.cards ?? const <PokemonCard>[])
        if (card.id.isNotEmpty) card.id: card,
    };
    final orderedIds = [
      ...?snapshot?.sections.featuredIds,
      ...?snapshot?.sections.bestSellerIds,
      ...?snapshot?.sections.recentlySeenIds,
      ...cachedSpotlightCards.map((card) => card.id),
      ...cards.map((card) => card.id),
    ];
    final seen = <String>{};
    final warmed = <PokemonCard>[];
    for (final id in orderedIds) {
      final card = byId[id];
      if (card == null ||
          !seen.add(id) ||
          card.itemKind == 'product' ||
          card.productType != 'card') {
        continue;
      }
      warmed.add(card);
      if (warmed.length >= 48) {
        break;
      }
    }
    return warmed;
  }

  List<PokemonCard> _hotCardsFromCards(List<PokemonCard> cards) {
    final deduped = _mergeCards(const [], cards)
        .where((card) =>
            card.previewImageUrl.isNotEmpty || card.imageUrl.isNotEmpty)
        .take(searchPreviewHotCacheLimit)
        .toList();
    return deduped;
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
    final normalizedSearchQuery = state.searchQuery.trim();
    final hasCurrentRemoteSearch = normalizedSearchQuery.isNotEmpty &&
        normalizedSearchQuery == state.remoteSearchQuery &&
        state.remoteSearchResults.isNotEmpty;
    List<PokemonCard> filtered = hasCurrentRemoteSearch
        ? List.from(state.remoteSearchResults)
        : List.from(state.cards);

    // Search filter
    if (state.searchQuery.isNotEmpty && !hasCurrentRemoteSearch) {
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
      filtered = filtered.where((card) => card.isMarketAvailable).toList();
    }

    // Preserve API/cache ranking by default; only reorder when a user-facing
    // sort option explicitly asks for it.
    if (state.sortBy != 'source') {
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
            comparison = 0;
        }
        return state.sortAscending ? comparison : -comparison;
      });
    }

    state = state.copyWith(filteredCards: filtered);
  }

  Future<void> refreshCards() async {
    await _initialCacheLoad;
    if (_hasWarmMarketplaceData) {
      state = state.copyWith(
        isLoading: false,
        error: null,
        hasMarketplaceLoadCompleted: true,
      );
      _marketplaceWarmStarted = true;
      return;
    }
    if (_navigationTransitionActive) {
      _refreshCardsAfterNavigation = true;
      return;
    }
    if (_marketplaceWarmStarted) {
      return;
    }
    _marketplaceWarmStarted = true;
    unawaited(_loadCards(navigationToken: _navigationPriorityToken));
  }

  Future<void> warmMarketplaceAfterDetail() async {
    if (_marketplaceWarmStarted || _hasWarmMarketplaceData) {
      FlutterDebugLog.instance.record(
        'provider.warm_after_detail.skipped',
        category: 'provider',
        payload: {
          'reason':
              _marketplaceWarmStarted ? 'already_started' : 'already_warm',
          'hasMarketplaceLoadCompleted': state.hasMarketplaceLoadCompleted,
          'hasHomeSections': state.homeSections != null,
        },
      );
      return;
    }
    if (_navigationTransitionActive) {
      _refreshCardsAfterNavigation = true;
      FlutterDebugLog.instance.record(
        'provider.warm_after_detail.skipped',
        category: 'provider',
        payload: {
          'reason': 'navigation_active',
          'hasMarketplaceLoadCompleted': state.hasMarketplaceLoadCompleted,
          'hasHomeSections': state.homeSections != null,
        },
      );
      return;
    }
    _marketplaceWarmStarted = true;
    final token = _navigationPriorityToken;
    FlutterDebugLog.instance.record(
      'provider.warm_after_detail.start',
      category: 'provider',
      payload: {
        'delayMs': 250,
        'currentCardCount': state.cards.length,
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted ||
        token != _navigationPriorityToken ||
        _navigationTransitionActive ||
        _hasWarmMarketplaceData) {
      if (mounted && !_hasWarmMarketplaceData) {
        _marketplaceWarmStarted = false;
        if (_navigationTransitionActive) {
          _refreshCardsAfterNavigation = true;
        }
      }
      FlutterDebugLog.instance.record(
        'provider.warm_after_detail.skipped',
        category: 'provider',
        payload: {
          'reason': !mounted
              ? 'disposed'
              : token != _navigationPriorityToken
                  ? 'navigation_started'
                  : _navigationTransitionActive
                      ? 'navigation_active'
                      : 'became_warm_during_delay',
          'hasMarketplaceLoadCompleted': state.hasMarketplaceLoadCompleted,
          'hasHomeSections': state.homeSections != null,
        },
      );
      return;
    }
    try {
      await _loadCards(navigationToken: token);
      FlutterDebugLog.instance.record(
        'provider.warm_after_detail.end',
        category: 'provider',
        payload: {'cardCount': state.cards.length},
      );
    } catch (error, stackTrace) {
      FlutterDebugLog.instance.recordError(
        'provider.warm_after_detail.error',
        error,
        stackTrace: stackTrace,
        category: 'provider',
      );
      rethrow;
    }
  }

  Future<void> warmMarketplaceFromLanding() async {
    if (_marketplaceWarmStarted || _hasWarmMarketplaceData) {
      return;
    }
    if (_navigationTransitionActive) {
      _refreshCardsAfterNavigation = true;
      return;
    }
    _marketplaceWarmStarted = true;
    await _loadCards(navigationToken: _navigationPriorityToken);
  }

  Future<void> addCard(PokemonCard card) async {
    try {
      await _cardService.addCard(card);
      await _loadCards(preserveCurrent: false);
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

  Future<void> warmDetailCards(Iterable<PokemonCard> cards) async {
    if (_navigationTransitionActive) {
      return;
    }
    final token = _navigationPriorityToken;
    final ids = <String>[];
    final seen = <String>{};
    for (final card in cards) {
      final id = card.id.trim();
      if (id.isEmpty || !seen.add(id)) {
        continue;
      }
      final current = _findLoadedCard(id) ?? card;
      if (!needsMarketplaceDetailHydration(current)) {
        continue;
      }
      ids.add(id);
      if (ids.length >= 12) {
        break;
      }
    }
    for (final id in ids) {
      if (!mounted || token != _navigationPriorityToken) {
        return;
      }
      await _refreshCardById(id, navigationToken: token);
    }
  }

  void _rememberSearchPreviews(
    String query,
    String language,
    List<PokemonCard> previews, {
    String? searchSessionId,
  }) {
    final typedQuery = query.trim();
    if (typedQuery.isEmpty || previews.isEmpty) {
      return;
    }
    final visible = _remoteSearchResults(previews, limit: searchPreviewLimit);
    if (visible.isEmpty) {
      return;
    }
    final sessionId = (searchSessionId ?? _searchSessionId ?? '').trim();
    _retainedSearchPreviewsByScope[_previewRetentionKey(
      typedQuery,
      language,
      sessionId,
    )] = visible;
    _rememberCandidateLabels(
      visible.map(
        (card) => SearchCandidateLabel(
          id: card.id,
          name: card.name,
          itemKind: card.itemKind,
          productType: card.productType,
          setName: card.set,
          number: card.number,
          trainerName: card.trainerName,
        ),
      ),
    );
  }

  void _rememberSearchPoolResponse({
    required String query,
    required String language,
    required SearchAutocompleteContext? context,
    required List<PokemonCard> previews,
    String? searchSessionId,
  }) {
    _rememberCandidateContext(context);
    _rememberSearchPrefixPool(
      query: query,
      language: language,
      context: context,
      previews: previews,
      searchSessionId: searchSessionId,
    );
  }

  SearchAutocompleteContext? _autocompleteContextFromResponse({
    required SearchAutocompleteContext? context,
    required List<PokemonCard> previews,
    required String query,
    required String language,
  }) {
    if (context == null) {
      return _derivedAutocompleteContextFromRows(
        query: query,
        language: language,
        previews: previews,
      );
    }
    if (context.cardIds.isNotEmpty || previews.isEmpty) {
      return context;
    }
    final derived = _derivedAutocompleteContextFromRows(
      query: query,
      language: language,
      previews: previews,
    );
    if (derived == null) {
      return context;
    }
    return SearchAutocompleteContext(
      query: context.query.trim().isEmpty ? derived.query : context.query,
      language:
          context.language.trim().isEmpty ? derived.language : context.language,
      cardIds: derived.cardIds,
      createdAtMs:
          context.createdAtMs > 0 ? context.createdAtMs : derived.createdAtMs,
      strategy:
          context.strategy.trim().isEmpty ? derived.strategy : context.strategy,
      candidateIdLadder: context.candidateIdLadder,
      depthScores: context.depthScores.isEmpty
          ? derived.depthScores
          : context.depthScores,
      latestDepths: context.latestDepths.isEmpty
          ? derived.latestDepths
          : context.latestDepths,
      latestOrders: context.latestOrders.isEmpty
          ? derived.latestOrders
          : context.latestOrders,
      nonNameContext: context.nonNameContext,
      candidateLabels: context.candidateLabels.isEmpty
          ? derived.candidateLabels
          : context.candidateLabels,
      predictedNameTokens: context.predictedNameTokens,
    );
  }

  SearchAutocompleteContext? _derivedAutocompleteContextFromRows({
    required String query,
    required String language,
    required List<PokemonCard> previews,
  }) {
    final normalizedQuery = query.trim();
    final normalizedLanguage = language.trim().toLowerCase();
    if (normalizedQuery.isEmpty ||
        normalizedLanguage.isEmpty ||
        previews.isEmpty) {
      return null;
    }
    final ids = <String>[];
    final labels = <SearchCandidateLabel>[];
    final seen = <String>{};
    for (final card in previews) {
      final id = card.id.trim();
      if (id.isEmpty || !seen.add(id)) {
        continue;
      }
      ids.add(id);
      labels.add(SearchCandidateLabel(
        id: id,
        name: card.name,
        itemKind: card.itemKind,
        productType: card.productType,
        setName: card.set,
        number: card.number,
        trainerName: card.trainerName,
      ));
    }
    if (ids.isEmpty) {
      return null;
    }
    final depth = _meaningfulSearchLength(normalizedQuery);
    return SearchAutocompleteContext(
      query: normalizedQuery,
      language: normalizedLanguage,
      cardIds: List.unmodifiable(ids),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      strategy: 'derived_from_rows',
      depthScores: Map.unmodifiable({for (final id in ids) id: depth}),
      latestDepths: Map.unmodifiable({for (final id in ids) id: depth}),
      latestOrders: Map.unmodifiable({
        for (var index = 0; index < ids.length; index += 1) ids[index]: index,
      }),
      candidateLabels: List.unmodifiable(labels),
    );
  }

  void _rememberCandidateLabels(Iterable<SearchCandidateLabel>? labels) {
    if (labels == null) {
      return;
    }
    for (final label in labels) {
      if (label.id.isEmpty || label.name.isEmpty) {
        continue;
      }
      _searchCandidateLabelsById[label.id] = label;
      if (_searchCandidateLabelsById.length > 10000) {
        final removedId = _searchCandidateLabelsById.keys.first;
        _searchCandidateLabelsById.remove(removedId);
        _searchCandidateLatestDepthById.remove(removedId);
        _searchCandidateDepthScoreById.remove(removedId);
        _searchCandidateLatestOrderById.remove(removedId);
      }
    }
  }

  void _rememberCandidateContext(SearchAutocompleteContext? context) {
    if (context == null) {
      return;
    }
    _rememberCandidateLabels(context.candidateLabels);
    for (var index = 0; index < context.cardIds.length; index += 1) {
      final id = context.cardIds[index];
      final latestDepth = context.latestDepths[id];
      if (latestDepth != null && latestDepth > 0) {
        _searchCandidateLatestDepthById[id] = latestDepth;
      }
      final depthScore = context.depthScores[id];
      if (depthScore != null && depthScore > 0) {
        _searchCandidateDepthScoreById[id] = depthScore;
      }
      final latestOrder = context.latestOrders[id] ?? index;
      _searchCandidateLatestOrderById[id] = latestOrder;
    }
  }

  String acceptSearchCompletion(String query, {bool triggerSearch = true}) {
    final completion = _validatedSearchCompletion(query.trim());
    if (completion.isEmpty) {
      return query;
    }
    SearchDebugTrace.instance.record('provider.completion.accept', {
      'query': query.trim(),
      'completion': completion,
      'confidence': _searchCompletionConfidence(query.trim()),
      'source': _searchCompletionSource(query.trim()),
    });
    state = state.copyWith(
      previewQuery: completion,
      searchQuery:
          state.searchQuery.trim().isEmpty ? state.searchQuery : completion,
      searchCompletion: '',
      searchCompletionConfidence: 0,
      searchCompletionSource: '',
    );
    _searchPredictedNameTokens = const [];
    _searchTokenPredictionContext = null;
    if (triggerSearch) {
      searchPreviewsOnly(completion);
    }
    return completion;
  }

  String _validatedSearchCompletion(String query) {
    final prediction = _bestSearchCompletionToken(query);
    if (prediction == null) {
      return '';
    }
    final completion = searchCompletionForQuery(query, prediction.display);
    return completion == query.trim() ? '' : completion;
  }

  double _searchCompletionConfidence(String query) {
    final prediction = _bestSearchCompletionToken(query);
    return prediction == null ? 0 : prediction.confidence;
  }

  String _searchCompletionSource(String query) {
    final prediction = _bestSearchCompletionToken(query);
    return prediction == null ? '' : prediction.source;
  }

  bool _existingPredictionCanComplete(String query, String language) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || _searchPredictedNameTokens.isEmpty) {
      return false;
    }
    for (final token in _searchPredictedNameTokens) {
      if (token.language.isNotEmpty &&
          token.language.toLowerCase() != language.toLowerCase()) {
        continue;
      }
      if (_tokenCanCompleteQuery(normalizedQuery, token)) {
        return true;
      }
    }
    return false;
  }

  void _applyFirstCharCompletionCache(String query) {
    final token = _firstCharCompletionToken(query, state.searchLanguage);
    if (token == null) {
      if (_searchPredictedNameTokens.any(
        (prediction) => prediction.source == 'first_char_static',
      )) {
        _searchPredictedNameTokens = const [];
      }
      return;
    }
    _searchPredictedNameTokens = [token];
  }

  SearchPredictedNameToken? _firstCharCompletionToken(
    String query,
    String language,
  ) {
    if (language.toLowerCase() != 'en') {
      return null;
    }
    final normalizedQuery = query.trim();
    if (_meaningfulSearchLength(normalizedQuery) != 1) {
      return null;
    }
    final key = _compactSearchCompletionText(normalizedQuery);
    if (key.length != 1) {
      return null;
    }
    final suggestion = firstCharTokenSuggestions[key];
    if (suggestion == null || suggestion.language.toLowerCase() != 'en') {
      return null;
    }
    return SearchPredictedNameToken(
      normalized: suggestion.normalized,
      display: suggestion.display,
      confidence: suggestion.confidence,
      sourceRank: 1,
      language: suggestion.language,
      source: 'first_char_static',
      nameFragment: key,
    );
  }

  SearchPredictedNameToken? _bestSearchCompletionToken(String query) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || _searchPredictedNameTokens.isEmpty) {
      return null;
    }
    for (final token in _searchPredictedNameTokens) {
      if (token.language.isNotEmpty &&
          token.language.toLowerCase() != state.searchLanguage.toLowerCase()) {
        continue;
      }
      if (_tokenCanCompleteQuery(normalizedQuery, token)) {
        return token;
      }
    }
    return null;
  }

  bool _tokenCanCompleteQuery(String query, SearchPredictedNameToken token) {
    final normalizedQuery = query.trim();
    final completion = searchCompletionForQuery(normalizedQuery, token.display);
    if (completion.isEmpty || completion == normalizedQuery) {
      return false;
    }
    if (token.isStructuredDimension) {
      return true;
    }
    final compactQuery = _compactSearchCompletionText(normalizedQuery);
    final compactDisplay = _compactSearchCompletionText(token.display);
    return compactQuery.isNotEmpty && compactDisplay.startsWith(compactQuery);
  }

  void _rememberSearchPrefixPool({
    required String query,
    required String language,
    required SearchAutocompleteContext? context,
    required List<PokemonCard> previews,
    String? searchSessionId,
  }) {
    final normalizedQuery = _normalizePrefixPoolQuery(query);
    final normalizedLanguage = language.trim().toLowerCase();
    final sessionId = (searchSessionId ?? _searchSessionId ?? '').trim();
    final ids = context?.cardIds.isNotEmpty == true
        ? context!.cardIds
        : previews.map((card) => card.id).toList(growable: false);
    if (normalizedQuery.isEmpty ||
        normalizedLanguage.isEmpty ||
        sessionId.isEmpty ||
        ids.isEmpty) {
      return;
    }

    final idLimit = _searchPreviewCandidateIdLimit(normalizedQuery);
    final seen = <String>{};
    final boundedIds = <String>[];
    for (final id in ids) {
      final normalizedId = id.trim();
      if (normalizedId.isEmpty || !seen.add(normalizedId)) {
        continue;
      }
      boundedIds.add(normalizedId);
      if (boundedIds.length >= idLimit) {
        break;
      }
    }
    if (boundedIds.isEmpty) {
      return;
    }

    _rememberCandidateLabels(context?.candidateLabels);
    _rememberCandidateLabels(previews.map(
      (card) => SearchCandidateLabel(
        id: card.id,
        name: card.name,
        itemKind: card.itemKind,
        productType: card.productType,
        setName: card.set,
        number: card.number,
        trainerName: card.trainerName,
      ),
    ));

    final depth = _meaningfulSearchLength(normalizedQuery);
    final depthScores = <String, int>{};
    final latestDepths = <String, int>{};
    final latestOrders = <String, int>{};
    for (var index = 0; index < boundedIds.length; index += 1) {
      final id = boundedIds[index];
      depthScores[id] =
          context?.depthScores[id] ?? context?.latestDepths[id] ?? depth;
      latestDepths[id] = context?.latestDepths[id] ?? depth;
      latestOrders[id] = context?.latestOrders[id] ?? index;
    }

    final key = _previewRetentionKey(
      normalizedQuery,
      normalizedLanguage,
      sessionId,
    );
    _searchPrefixPoolsByKey[key] = _SearchPrefixPool(
      key: key,
      query: normalizedQuery,
      language: normalizedLanguage,
      sessionId: sessionId,
      cardIds: List.unmodifiable(boundedIds),
      depth: depth,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      depthScores: Map.unmodifiable(depthScores),
      latestDepths: Map.unmodifiable(latestDepths),
      latestOrders: Map.unmodifiable(latestOrders),
    );
    _trimSearchPrefixPools();
  }

  void _trimSearchPrefixPools() {
    while (_searchPrefixPoolsByKey.length > _searchPreviewMaxPrefixPools) {
      _removeOldestSearchPrefixPool();
    }
    while (_searchPrefixPoolsByKey.values.fold<int>(
          0,
          (sum, pool) => sum + pool.cardIds.length,
        ) >
        _searchPreviewMaxAggregatePrefixIds) {
      if (!_removeOldestSearchPrefixPool()) {
        break;
      }
    }
  }

  bool _removeOldestSearchPrefixPool() {
    if (_searchPrefixPoolsByKey.isEmpty) {
      return false;
    }
    String? oldestKey;
    int? oldestUpdatedAt;
    for (final entry in _searchPrefixPoolsByKey.entries) {
      final updatedAt = entry.value.updatedAtMs;
      if (oldestUpdatedAt == null || updatedAt < oldestUpdatedAt) {
        oldestUpdatedAt = updatedAt;
        oldestKey = entry.key;
      }
    }
    if (oldestKey == null) {
      return false;
    }
    _searchPrefixPoolsByKey.remove(oldestKey);
    _retainedSearchPreviewsByScope.remove(oldestKey);
    return true;
  }

  void _clearSearchPrefixPoolHistory() {
    _searchPrefixPoolsByKey.clear();
    _retainedSearchPreviewsByScope.clear();
    _searchCandidateLabelsById.clear();
    _searchCandidateLatestDepthById.clear();
    _searchCandidateDepthScoreById.clear();
    _searchCandidateLatestOrderById.clear();
    _searchPredictedNameTokens = const [];
    _searchTokenPredictionContext = null;
  }

  void _prepareSearchSessionForQuery(String query) {
    if (!_isSearchSessionBranchChange(query)) {
      return;
    }
    _cancelSearchSession(reason: 'query_branch');
    _searchAutocompleteContext = null;
    _clearSearchPrefixPoolHistory();
  }

  bool _isSearchSessionBranchChange(String query) {
    final currentSessionId = _searchSessionId;
    if (currentSessionId == null || currentSessionId.isEmpty) {
      return false;
    }
    final lastQuery = _normalizePrefixPoolQuery(_lastSearchSessionQuery);
    final nextQuery = _normalizePrefixPoolQuery(query);
    if (lastQuery.isEmpty ||
        nextQuery.isEmpty ||
        _prefixPoolQueryExtends(lastQuery, nextQuery)) {
      return false;
    }
    return true;
  }

  String _previewRetentionKey(
    String query,
    String language,
    String sessionId,
  ) {
    return '${language.trim().toLowerCase()}::${sessionId.trim()}::'
        '${_normalizePrefixPoolQuery(query)}';
  }

  List<PokemonCard> _fallbackPreviewsForQuery(String query) {
    final normalizedQuery = query.trim();
    if (_meaningfulSearchLength(normalizedQuery) < searchPreviewVisibleChars) {
      return const [];
    }
    final language = state.searchLanguage;
    final sessionId = _searchSessionId ?? '';
    final prefixPoolPreviews = _searchPreviewFallbackRowsFromPrefixPools(
      query: normalizedQuery,
      language: language,
      sessionId: sessionId,
      pools: _searchPrefixPoolsByKey.values,
      retainedRowsByScope: _retainedSearchPreviewsByScope,
      labelsById: _searchCandidateLabelsById,
      limit: searchPreviewLimit,
    );
    if (prefixPoolPreviews.isNotEmpty) {
      return prefixPoolPreviews;
    }
    final context = _searchAutocompleteContext;
    if (context == null || context.cardIds.isEmpty) {
      return const [];
    }
    if (context.query != normalizedQuery &&
        !context.canRefine(normalizedQuery, language)) {
      return const [];
    }
    final retainedRows = _retainedSearchPreviewsByScope[
            _previewRetentionKey(normalizedQuery, language, sessionId)] ??
        const <PokemonCard>[];
    return _searchPreviewFallbackRows(
      query: normalizedQuery,
      retainedRows: retainedRows,
      context: context,
      latestDepths: _searchCandidateLatestDepthById,
      depthScores: _searchCandidateDepthScoreById,
      latestOrders: _searchCandidateLatestOrderById,
      limit: searchPreviewLimit,
    );
  }

  List<PokemonCard> _pendingSearchPreviewFallbackForQuery(
    String query, {
    List<PokemonCard> retainedPreviews = const [],
    bool includeHotFallback = true,
  }) {
    final fallbackPreviews = _fallbackPreviewsForQuery(query);
    if (fallbackPreviews.isNotEmpty) {
      return fallbackPreviews;
    }
    if (_meaningfulSearchLength(query.trim()) < searchPreviewVisibleChars) {
      return const [];
    }
    if (retainedPreviews.isNotEmpty) {
      return _remoteSearchResults(retainedPreviews, limit: searchPreviewLimit);
    }
    if (!includeHotFallback) {
      return const [];
    }
    final hotCards = _hotSearchPreviewCache.isNotEmpty
        ? _hotSearchPreviewCache
        : _hotCardsFromCards(state.cards);
    return _emptyFocusPreviews(hotCards, const []);
  }

  Future<void> updateCard(PokemonCard card) async {
    try {
      await _cardService.updateCard(card);
      await _loadCards(preserveCurrent: false);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteCard(String cardId) async {
    try {
      await _cardService.deleteCard(cardId);
      await _loadCards(preserveCurrent: false);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void clearFilters() {
    _searchRequestId++;
    _searchPreviewRequestId++;
    _searchTokenPredictRequestId++;
    _searchPreviewDebounce?.cancel();
    _searchTokenPredictDebounce?.cancel();
    _cancelSearchSession(reason: 'clear_filters');
    _clearSearchPrefixPoolHistory();
    _searchAutocompleteContext = null;
    state = state.copyWith(
      searchQuery: '',
      remoteSearchQuery: '',
      remoteSearchResults: const [],
      previewQuery: '',
      searchPreviews: const [],
      isSearchingPreviews: false,
      searchCompletion: '',
      searchCompletionConfidence: 0,
      searchCompletionSource: '',
      selectedRarity: '',
      selectedType: '',
      selectedSet: '',
      minPrice: 0.0,
      maxPrice: 5000000.0,
      showOnlyInStock: false,
      sortBy: 'source',
      sortAscending: true,
    );
    _applyFilters();
  }

  @override
  void dispose() {
    _searchPreviewDebounce?.cancel();
    _searchTokenPredictDebounce?.cancel();
    _navigationPriorityTimer?.cancel();
    _cancelSearchSession(reason: 'dispose');
    _clearSearchPrefixPoolHistory();
    super.dispose();
  }

  void exitSearch({String reason = 'exit'}) {
    final hadActiveSearch = _searchSessionId?.isNotEmpty == true ||
        state.previewQuery.isNotEmpty ||
        state.searchPreviews.isNotEmpty ||
        state.isSearchingPreviews;
    if (!hadActiveSearch) {
      return;
    }
    _searchRequestId++;
    _searchPreviewRequestId++;
    _searchTokenPredictRequestId++;
    _searchPreviewDebounce?.cancel();
    _searchTokenPredictDebounce?.cancel();
    _searchAutocompleteContext = null;
    _searchPredictedNameTokens = const [];
    _cancelSearchSession(reason: reason);
    _clearSearchPrefixPoolHistory();
    state = state.copyWith(
      previewQuery: '',
      searchPreviews: const [],
      isSearchingPreviews: false,
      searchCompletion: '',
      searchCompletionConfidence: 0,
      searchCompletionSource: '',
    );
  }

  String _ensureSearchSession(String query) {
    final trimmedQuery = query.trim();
    final current = _searchSessionId;
    if (current != null && current.isNotEmpty) {
      _lastSearchSessionQuery = trimmedQuery;
      return current;
    }
    _searchSessionSequence += 1;
    final id =
        'flutter-${DateTime.now().microsecondsSinceEpoch}-$_searchSessionSequence';
    _searchSessionId = id;
    _lastSearchSessionQuery = trimmedQuery;
    SearchDebugTrace.instance.record('provider.search_session.start', {
      'searchSessionId': id,
      'query': trimmedQuery,
    });
    return id;
  }

  void _cancelSearchSession({required String reason}) {
    final id = _searchSessionId;
    if (id == null || id.isEmpty) {
      _lastSearchSessionQuery = '';
      return;
    }
    final lastQuery = _lastSearchSessionQuery;
    _searchSessionId = null;
    _lastSearchSessionQuery = '';
    SearchDebugTrace.instance.record('provider.search_session.cancel', {
      'searchSessionId': id,
      'query': lastQuery,
      'reason': reason,
    });
    unawaited(_cardService.cancelSearchSession(
      sessionId: id,
      lastQuery: lastQuery,
      reason: reason,
    ));
  }

  PokemonCard? _findLoadedCard(String id) {
    for (final card in state.cards) {
      if (card.id == id) {
        return card;
      }
    }
    return null;
  }

  PokemonCard? _findLoadedCardBySlug(String slug) {
    final normalizedSlug = normalizeCardDetailSlug(slug);
    if (normalizedSlug.isEmpty) {
      return null;
    }
    for (final card in state.cards) {
      if (cardDetailSlugsMatch(cardDetailSlug(card), normalizedSlug) ||
          cardDetailSlugsMatch(legacyCardDetailSlug(card), normalizedSlug)) {
        return card;
      }
    }
    return null;
  }

  List<PokemonCard> _mergeCards(
    List<PokemonCard> current,
    List<PokemonCard> incoming, {
    bool preserveExistingMarketplaceFields = false,
  }) {
    final byId = <String, PokemonCard>{
      for (final card in current) card.id: card,
    };
    for (final card in incoming) {
      final existing = byId[card.id];
      byId[card.id] = existing == null
          ? card
          : _mergeCard(
              existing,
              card,
              preserveExistingMarketplaceFields:
                  preserveExistingMarketplaceFields,
            );
    }
    return byId.values.toList();
  }

  PokemonCard _mergeCard(
    PokemonCard existing,
    PokemonCard incoming, {
    bool preserveExistingMarketplaceFields = false,
  }) {
    final marketplace = _mergedMarketplaceFields(
      existing,
      incoming,
      preserveExistingMarketplaceFields: preserveExistingMarketplaceFields,
    );
    return incoming.copyWith(
      imageUrl: _preferRicherText(incoming.imageUrl, existing.imageUrl),
      previewImageUrl:
          _preferRicherText(incoming.previewImageUrl, existing.previewImageUrl),
      homepageImageUrl: _preferRicherText(
        incoming.homepageImageUrl,
        existing.homepageImageUrl,
      ),
      rarity: _preferRicherLabel(incoming.rarity, existing.rarity, 'Card'),
      type: _preferRicherLabel(incoming.type, existing.type, 'Card'),
      description: _preferRicherDescription(
        incoming.description,
        existing.description,
      ),
      set: _preferRicherText(incoming.set, existing.set),
      number: _preferRicherText(incoming.number, existing.number),
      artist: _preferRicherText(incoming.artist, existing.artist),
      tags: _mergeStringList(existing.tags, incoming.tags),
      trainerName:
          _preferRicherText(incoming.trainerName, existing.trainerName),
      expansionSymbolUrl: _preferRicherText(
        incoming.expansionSymbolUrl,
        existing.expansionSymbolUrl,
      ),
      expansionLogoUrl: _preferRicherText(
        incoming.expansionLogoUrl,
        existing.expansionLogoUrl,
      ),
      cardPalette: incoming.cardPalette.isNotEmpty
          ? incoming.cardPalette
          : existing.cardPalette,
      emoji: _preferRicherText(incoming.emoji, existing.emoji),
      price: marketplace.price,
      stock: marketplace.stock,
      canonicalPath:
          _preferRicherText(incoming.canonicalPath, existing.canonicalPath),
      hasCardTraderListing: marketplace.hasCardTraderListing,
      cardtraderEligibleListingCount:
          marketplace.cardtraderEligibleListingCount,
      watchlistCount: marketplace.watchlistCount,
      cartHolderCount: marketplace.cartHolderCount,
      rating: marketplace.rating,
    );
  }

  _MergedMarketplaceFields _mergedMarketplaceFields(
    PokemonCard existing,
    PokemonCard incoming, {
    required bool preserveExistingMarketplaceFields,
  }) {
    final source = preserveExistingMarketplaceFields ? existing : incoming;
    return _MergedMarketplaceFields(
      price: source.price,
      stock: source.stock,
      hasCardTraderListing: source.hasCardTraderListing,
      cardtraderEligibleListingCount: source.cardtraderEligibleListingCount,
      watchlistCount: existing.watchlistCount > incoming.watchlistCount
          ? existing.watchlistCount
          : incoming.watchlistCount,
      cartHolderCount: existing.cartHolderCount > incoming.cartHolderCount
          ? existing.cartHolderCount
          : incoming.cartHolderCount,
      rating:
          existing.rating > incoming.rating ? existing.rating : incoming.rating,
    );
  }

  String _preferRicherText(String incoming, String existing) {
    return incoming.trim().isNotEmpty ? incoming : existing;
  }

  String _preferRicherLabel(
    String incoming,
    String existing,
    String generic,
  ) {
    final cleanIncoming = incoming.trim();
    final cleanExisting = existing.trim();
    if (cleanIncoming.isEmpty) return existing;
    if (cleanExisting.isNotEmpty &&
        _isGenericCardLabel(cleanIncoming, generic)) {
      return existing;
    }
    return incoming;
  }

  bool _isGenericCardLabel(String value, String generic) {
    final normalized = value.toLowerCase();
    return normalized == generic.toLowerCase() ||
        normalized == 'card' ||
        normalized == 'trading card';
  }

  String _preferRicherDescription(String incoming, String existing) {
    final cleanIncoming = incoming.trim();
    final cleanExisting = existing.trim();
    if (cleanIncoming.isEmpty) return existing;
    if (cleanExisting.isNotEmpty && _isLightweightDescription(cleanIncoming)) {
      return existing;
    }
    return incoming;
  }

  bool _isLightweightDescription(String description) {
    final normalized = description.toLowerCase();
    return normalized.contains('full blueprint data is loaded') ||
        normalized.contains('autocomplete projection') ||
        normalized.contains('hot marketplace analytics') ||
        normalized.contains('saved from your recent marketplace views');
  }

  List<String> _mergeStringList(List<String> existing, List<String> incoming) {
    final seen = <String>{};
    final merged = <String>[];
    for (final value in [...incoming, ...existing]) {
      final clean = value.trim();
      if (clean.isEmpty || !seen.add(clean.toLowerCase())) {
        continue;
      }
      merged.add(value);
    }
    return merged;
  }

  bool _matchesSearchTerms(PokemonCard card, List<String> terms) {
    if (terms.isEmpty) {
      return true;
    }
    if (terms.length == 1 && _isVariationSearchTerm(terms.first)) {
      return _cardHasVariation(card, terms.first) ||
          (terms.first == 'vstar' && _cardHasSetToken(card, terms.first));
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

  bool _isStandaloneVariationQuery(String query) {
    final terms = _searchTerms(query);
    return terms.length == 1 && _isVariationSearchTerm(terms.first);
  }

  List<String> _searchTerms(String query) {
    return _normalizeVariationSearchPhrases(query)
        .toLowerCase()
        .replaceAllMapped(
          RegExp(r'\b([a-z0-9]+)s\b'),
          (match) => "${match.group(1)}'s",
        )
        .split(RegExp(r'[^a-z0-9]+'))
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty)
        .toList();
  }

  String _normalizeVariationSearchPhrases(String value) {
    return value
        .replaceAll('&', ' tagteam ')
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
      'tagteam',
    };
    return variations.contains(term.replaceAll(RegExp(r'[^a-z0-9]'), ''));
  }

  bool _cardHasVariation(PokemonCard card, String term) {
    return _previewCardHasVariation(card, term);
  }

  bool _cardHasSetToken(PokemonCard card, String term) {
    final normalizedTerm = term.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalizedTerm.isEmpty) {
      return false;
    }
    return RegExp('(^|[^a-z0-9])$normalizedTerm([^a-z0-9]|\$)')
        .hasMatch(card.set.toLowerCase());
  }

  int _meaningfulSearchLength(String query) {
    return RegExp(r'[a-z0-9]', caseSensitive: false).allMatches(query).length;
  }
}

int _searchPreviewCandidateIdLimit(String query) {
  final depth =
      RegExp(r'[a-z0-9]', caseSensitive: false).allMatches(query).length;
  if (depth <= 1) {
    return searchPreviewHotCacheLimit;
  }
  if (depth == 2) {
    return 5000;
  }
  if (depth == 3) {
    return 2500;
  }
  if (depth == 4) {
    return 1250;
  }
  return 500;
}

String searchCompletionForQuery(String query, String predictedToken) {
  final typed = query.trim();
  final predicted = predictedToken.trim();
  if (typed.isEmpty || predicted.isEmpty) {
    return '';
  }
  final compactTyped = _compactSearchCompletionText(typed);
  final compactPredicted = _compactSearchCompletionText(predicted);
  if (compactTyped.isNotEmpty &&
      compactTyped.length < compactPredicted.length &&
      compactPredicted.startsWith(compactTyped)) {
    return predicted;
  }
  final match = RegExp(r"([A-Za-z0-9][A-Za-z0-9'\-]*)\s*$").firstMatch(typed);
  if (match == null) {
    return '';
  }
  final fragment = match.group(1) ?? '';
  if (fragment.isEmpty ||
      fragment.length >= predicted.length ||
      !predicted.toLowerCase().startsWith(fragment.toLowerCase())) {
    return '';
  }
  return '${typed.substring(0, match.start)}$predicted';
}

String _compactSearchCompletionText(String value) {
  return value
      .replaceAll('&', ' tagteam ')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}

int searchCompletionSuffixStart(String typedQuery, String completionText) {
  final typed = typedQuery.trim();
  final completion = completionText.trim();
  if (typed.isEmpty || completion.isEmpty) {
    return 0;
  }
  final lowerCompletion = completion.toLowerCase();
  if (lowerCompletion.startsWith(typed.toLowerCase())) {
    return typed.length;
  }
  final compactTyped = _compactSearchCompletionText(typed);
  final compactCompletion = _compactSearchCompletionText(completion);
  if (compactTyped.isEmpty ||
      compactTyped.length >= compactCompletion.length ||
      !compactCompletion.startsWith(compactTyped)) {
    return 0;
  }
  var compactOffset = 0;
  for (var index = 0; index < completion.length; index += 1) {
    final char = completion[index];
    if (_compactSearchCompletionText(char).isEmpty) {
      continue;
    }
    compactOffset += 1;
    if (compactOffset >= compactTyped.length) {
      return index + 1;
    }
  }
  return 0;
}

class _SearchPrefixPool {
  const _SearchPrefixPool({
    required this.key,
    required this.query,
    required this.language,
    required this.sessionId,
    required this.cardIds,
    required this.depth,
    required this.updatedAtMs,
    required this.depthScores,
    required this.latestDepths,
    required this.latestOrders,
  });

  final String key;
  final String query;
  final String language;
  final String sessionId;
  final List<String> cardIds;
  final int depth;
  final int updatedAtMs;
  final Map<String, int> depthScores;
  final Map<String, int> latestDepths;
  final Map<String, int> latestOrders;
}

List<PokemonCard> _searchPreviewFallbackRowsFromPrefixPools({
  required String query,
  required String language,
  required String sessionId,
  required Iterable<_SearchPrefixPool> pools,
  required Map<String, List<PokemonCard>> retainedRowsByScope,
  required Map<String, SearchCandidateLabel> labelsById,
  int limit = searchPreviewLimit,
}) {
  final normalizedQuery = _normalizePrefixPoolQuery(query);
  final normalizedLanguage = language.trim().toLowerCase();
  final normalizedSessionId = sessionId.trim();
  if (normalizedQuery.isEmpty ||
      normalizedLanguage.isEmpty ||
      normalizedSessionId.isEmpty) {
    return const [];
  }

  final compatiblePools = pools
      .where(
        (pool) =>
            pool.language == normalizedLanguage &&
            pool.sessionId == normalizedSessionId &&
            _prefixPoolQueryExtends(pool.query, normalizedQuery),
      )
      .toList(growable: false);
  if (compatiblePools.isEmpty) {
    return const [];
  }

  _SearchPrefixPool? latestCompatiblePool;
  for (final pool in compatiblePools) {
    final current = latestCompatiblePool;
    if (current == null ||
        pool.depth > current.depth ||
        (pool.depth == current.depth &&
            pool.updatedAtMs > current.updatedAtMs)) {
      latestCompatiblePool = pool;
    }
  }
  final pool = latestCompatiblePool;
  if (pool == null) {
    return const [];
  }

  final retainedRowsById = <String, PokemonCard>{};
  for (final card in retainedRowsByScope[pool.key] ?? const <PokemonCard>[]) {
    retainedRowsById.putIfAbsent(card.id, () => card);
  }

  final seen = <String>{};
  final candidates = <_SearchPreviewFallbackCandidate>[];
  for (var index = 0; index < pool.cardIds.length; index += 1) {
    final id = pool.cardIds[index];
    if (id.isEmpty || !seen.add(id)) {
      continue;
    }
    final card =
        retainedRowsById[id] ?? _placeholderCardFromLabel(labelsById[id]);
    if (card == null) {
      continue;
    }
    candidates.add(_SearchPreviewFallbackCandidate(
      card: card,
      latestDepth: pool.latestDepths[id] ?? pool.depth,
      depthScore: pool.depthScores[id] ?? pool.depth,
      order: pool.latestOrders[id] ?? index,
    ));
  }

  final terms = _typedPreviewTerms(normalizedQuery);
  final filtered = terms.any(_isNumericPreviewTerm)
      ? _filterPrefixPoolCandidatesByStructuredSuffixes(candidates, terms)
      : _filterFallbackCandidatesByTerms(candidates, terms);
  if (filtered.isEmpty) {
    if (normalizedQuery.length > pool.query.length &&
        _prefixPoolQueryExtends(pool.query, normalizedQuery)) {
      return candidates
          .map((entry) => entry.card)
          .take(limit)
          .toList(growable: false);
    }
    return const [];
  }

  filtered.sort((a, b) => a.order.compareTo(b.order));
  return filtered
      .map((entry) => entry.card)
      .take(limit)
      .toList(growable: false);
}

String _normalizePrefixPoolQuery(String query) {
  return query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

bool _prefixPoolQueryExtends(String previousQuery, String nextQuery) {
  final previous = _normalizePrefixPoolQuery(previousQuery);
  final next = _normalizePrefixPoolQuery(nextQuery);
  if (previous.isEmpty || next.isEmpty || previous.length > next.length) {
    return false;
  }
  return next.startsWith(previous);
}

List<_SearchPreviewFallbackCandidate>
    _filterPrefixPoolCandidatesByStructuredSuffixes(
  List<_SearchPreviewFallbackCandidate> candidates,
  List<String> terms,
) {
  var narrowed = candidates;
  final suffixTerms = terms.isNotEmpty && _isNumericPreviewTerm(terms.first)
      ? terms
      : terms.skip(1);
  for (final term in suffixTerms) {
    if (_isNumericPreviewTerm(term)) {
      narrowed = narrowed
          .where((candidate) => _previewCardMatchesNumber(candidate.card, term))
          .toList(growable: false);
    } else {
      narrowed = _refineFallbackCandidatesByToken(narrowed, term);
    }
    if (narrowed.isEmpty) {
      return const [];
    }
  }
  return narrowed;
}

List<PokemonCard> _searchPreviewFallbackRows({
  required String query,
  required List<PokemonCard> retainedRows,
  required SearchAutocompleteContext? context,
  List<SearchCandidateLabel> labels = const [],
  Map<String, int> latestDepths = const {},
  Map<String, int> depthScores = const {},
  Map<String, int> latestOrders = const {},
  int limit = searchPreviewLimit,
}) {
  final terms = _typedPreviewTerms(query);
  if (terms.isEmpty) {
    return const [];
  }
  final contextIds = context?.cardIds ?? const <String>[];
  if (contextIds.isEmpty) {
    return const [];
  }
  final contextIdSet = contextIds.toSet();
  final mergedDepthScores = <String, int>{
    ...depthScores,
    ...?context?.depthScores,
  };
  final mergedLatestDepths = <String, int>{
    ...latestDepths,
    ...?context?.latestDepths,
  };
  final mergedLatestOrders = <String, int>{
    ...latestOrders,
    ...?context?.latestOrders,
  };
  final idOrder = <String, int>{
    for (var index = 0; index < contextIds.length; index += 1)
      contextIds[index]: index,
  };
  final byId = <String, PokemonCard>{};
  for (final card in retainedRows) {
    if (contextIdSet.contains(card.id) && !byId.containsKey(card.id)) {
      byId[card.id] = card;
    }
  }
  final labelsById = <String, SearchCandidateLabel>{};
  for (final label in [
    ...?context?.candidateLabels,
    ...labels,
  ]) {
    if (contextIdSet.contains(label.id) && label.name.isNotEmpty) {
      labelsById[label.id] = label;
    }
  }
  final seen = <String>{};
  final candidates = <_SearchPreviewFallbackCandidate>[];
  for (final id in contextIds) {
    if (id.isEmpty || !seen.add(id)) {
      continue;
    }
    final card = byId[id] ?? _placeholderCardFromLabel(labelsById[id]);
    if (card == null) {
      continue;
    }
    candidates.add(_SearchPreviewFallbackCandidate(
      card: card,
      latestDepth: mergedLatestDepths[id] ?? 0,
      depthScore: mergedDepthScores[id] ?? 0,
      order: mergedLatestOrders[id] ??
          idOrder[id] ??
          (1 << 20) + candidates.length,
    ));
  }
  final ranked = _rankedPoolCandidatesForNumericTerms(terms, candidates) ??
      _filterFallbackCandidatesByTerms(candidates, terms);
  final filtered = terms.any(_isNumericPreviewTerm)
      ? _filterPrefixPoolCandidatesByStructuredSuffixes(ranked, terms)
      : ranked;
  if (filtered.isEmpty) {
    final contextQuery = _normalizePrefixPoolQuery(context?.query ?? '');
    final fallbackQuery = _normalizePrefixPoolQuery(query);
    if (contextQuery.length < fallbackQuery.length &&
        _prefixPoolQueryExtends(contextQuery, fallbackQuery)) {
      return candidates
          .map((entry) => entry.card)
          .take(limit)
          .toList(growable: false);
    }
    return const [];
  }
  return filtered
      .map((entry) => entry.card)
      .take(limit)
      .toList(growable: false);
}

List<_SearchPreviewFallbackCandidate>? _rankedPoolCandidatesForNumericTerms(
  List<String> terms,
  List<_SearchPreviewFallbackCandidate> candidates,
) {
  if (terms.isEmpty ||
      candidates.isEmpty ||
      !terms.any(_isNumericPreviewTerm)) {
    return null;
  }
  final ranked = candidates
      .where(
        (candidate) =>
            candidate.latestDepth > 0 ||
            candidate.depthScore > 0 ||
            candidate.order < (1 << 20),
      )
      .toList(growable: false);
  return ranked.isEmpty ? null : ranked;
}

bool _isNumericPreviewTerm(String term) {
  return RegExp(r'^[0-9]+[a-z]*$').hasMatch(term);
}

class _SearchPreviewFallbackCandidate {
  const _SearchPreviewFallbackCandidate({
    required this.card,
    required this.latestDepth,
    required this.depthScore,
    required this.order,
  });

  final PokemonCard card;
  final int latestDepth;
  final int depthScore;
  final int order;
}

List<_SearchPreviewFallbackCandidate> _filterFallbackCandidatesByTerms(
  List<_SearchPreviewFallbackCandidate> candidates,
  List<String> terms,
) {
  if (terms.isEmpty || candidates.isEmpty) {
    return candidates;
  }
  if (terms.length == 1) {
    return candidates
        .where(
          (candidate) => _previewCardMatchesSingleFallbackTerm(
              candidate.card, terms.first),
        )
        .toList(growable: false);
  }
  var narrowed = candidates
      .where(
        (candidate) =>
            _previewCardMatchesNameOrBroadTerm(candidate.card, terms.first),
      )
      .toList(growable: false);
  if (narrowed.isEmpty) {
    return const [];
  }
  for (final term in terms.skip(1)) {
    narrowed = _refineFallbackCandidatesByToken(narrowed, term);
    if (narrowed.isEmpty) {
      return const [];
    }
  }
  return narrowed;
}

List<_SearchPreviewFallbackCandidate> _refineFallbackCandidatesByToken(
  List<_SearchPreviewFallbackCandidate> candidates,
  String term,
) {
  if (term.isEmpty || candidates.isEmpty) {
    return candidates;
  }
  final completedVariationMatches = _isPreviewVariationSearchTerm(term)
      ? candidates
          .where((candidate) => _previewCardHasVariation(candidate.card, term))
          .toList(growable: false)
      : const <_SearchPreviewFallbackCandidate>[];
  if (_isPreviewVariationSearchTerm(term)) {
    return completedVariationMatches;
  }

  final layers = [
    candidates
        .where(
            (candidate) => _previewCardHasVariationPrefix(candidate.card, term))
        .toList(growable: false),
    candidates
        .where((candidate) =>
            _previewCardMatchesOwnerVariation(candidate.card, term))
        .toList(growable: false),
    candidates
        .where((candidate) => _previewCardMatchesNumber(candidate.card, term))
        .toList(growable: false),
    candidates
        .where((candidate) =>
            _previewCardMatchesExpansionAlias(candidate.card, term))
        .toList(growable: false),
    candidates
        .where((candidate) => _previewCardMatchesSetName(candidate.card, term))
        .toList(growable: false),
    candidates
        .where((candidate) => _previewCardMatchesRarity(candidate.card, term))
        .toList(growable: false),
    if (term.length >= 3)
      candidates
          .where(
            (candidate) =>
                _previewCardMatchesTypedTerms(candidate.card, [term]),
          )
          .toList(growable: false),
  ];
  for (final layer in layers) {
    if (layer.isNotEmpty) {
      return layer;
    }
  }
  return const [];
}

PokemonCard? _placeholderCardFromLabel(SearchCandidateLabel? label) {
  if (label == null || label.id.isEmpty || label.name.isEmpty) {
    return null;
  }
  final itemKind = label.itemKind == 'product' ? 'product' : 'single';
  final productType = label.productType.isEmpty ? 'card' : label.productType;
  final type = itemKind == 'product' ? _productTypeLabel(productType) : 'Card';
  return PokemonCard(
    id: label.id,
    name: label.name,
    imageUrl: '',
    previewImageUrl: '',
    rarity: itemKind == 'product' ? type : 'Card',
    type: type,
    hp: 0,
    attacks: const [],
    price: 0,
    description: 'Lightweight autocomplete preview.',
    set: label.setName,
    number: label.number,
    artist: '',
    stock: 0,
    rating: 0,
    reviewCount: 0,
    isFoil: false,
    isHolo: false,
    releaseDate: DateTime.now(),
    tags: [
      type,
      itemKind,
      productType,
      if (label.trainerName.isNotEmpty) label.trainerName,
    ],
    condition: 'NM',
    isGraded: false,
    itemKind: itemKind,
    productType: productType,
    trainerName: label.trainerName,
  );
}

bool _previewCardMatchesSingleFallbackTerm(PokemonCard card, String term) {
  if (term.isEmpty) {
    return true;
  }
  if (_isPreviewVariationSearchTerm(term)) {
    return _previewCardHasVariation(card, term);
  }
  final compactName = _compactPreviewField(card.name);
  if (term.length >= 5) {
    return compactName == term || compactName.startsWith(term);
  }
  final exactShortName = _previewDisplayTokens(card).any((token) {
    return token == term ||
        _compactPreviewField(card.name) == term ||
        _compactPreviewField(card.trainerName) == term;
  });
  if (term.length <= 2) {
    return exactShortName;
  }
  return exactShortName || _previewCardMatchesTypedTerms(card, [term]);
}

bool _previewCardMatchesNameOrBroadTerm(PokemonCard card, String term) {
  if (term.isEmpty) {
    return true;
  }
  if (_isPreviewVariationSearchTerm(term)) {
    return _previewCardHasVariation(card, term);
  }
  if (term.length <= 2) {
    return _previewDisplayTokens(card).any((token) => token == term) ||
        _compactPreviewField(card.name) == term ||
        _compactPreviewField(card.trainerName) == term;
  }
  return _previewCardMatchesTypedTerms(card, [term]);
}

bool _previewCardMatchesTypedTerms(PokemonCard card, List<String> terms) {
  final fields = [
    card.name,
    card.set,
    card.number,
    card.trainerName,
    card.rarity,
    card.type,
    card.productType,
    ...card.tags,
  ].where((field) => field.trim().isNotEmpty).toList();
  if (fields.isEmpty) {
    return false;
  }
  return terms.every(
    (term) => fields.any(
      (field) =>
          _compactPreviewField(field) == term ||
          _compactPreviewField(field).startsWith(term) ||
          _previewFieldWords(field).any((word) => word.startsWith(term)),
    ),
  );
}

bool _previewCardHasVariationPrefix(PokemonCard card, String term) {
  final normalizedTerm = _compactPreviewField(term);
  if (normalizedTerm.isEmpty) {
    return false;
  }
  for (final variation in _previewVariationTerms) {
    if (variation.startsWith(normalizedTerm) &&
        _previewCardHasVariation(card, variation)) {
      return true;
    }
  }
  return false;
}

bool _previewCardMatchesNumber(PokemonCard card, String term) {
  if (!RegExp(r'^[0-9]+[a-z]*$').hasMatch(term)) {
    return false;
  }
  return _previewFieldWords(card.number).any(
    (token) => token == term || token.startsWith(term),
  );
}

bool _previewCardMatchesExpansionAlias(PokemonCard card, String term) {
  final compactSet = _compactPreviewField(card.set);
  if (compactSet.isEmpty) {
    return false;
  }
  return _previewExpansionAliasTargets(term).any((target) {
    return compactSet == target ||
        compactSet.startsWith(target) ||
        target.startsWith(compactSet);
  });
}

bool _previewCardMatchesSetName(PokemonCard card, String term) {
  return _previewFieldWords(card.set).any(
    (token) => token == term || token.startsWith(term),
  );
}

bool _previewCardMatchesOwnerVariation(PokemonCard card, String term) {
  final normalizedTerm = _compactPreviewField(term);
  if (normalizedTerm.isEmpty) {
    return false;
  }
  final trainerTokens = _previewFieldWords(card.trainerName);
  if (trainerTokens.any((token) => token == term || token.startsWith(term))) {
    return true;
  }
  final name = card.name.toLowerCase();
  return RegExp('(^|[^a-z0-9])$normalizedTerm\\s*\'s([^a-z0-9]|\$)')
      .hasMatch(name);
}

bool _previewCardMatchesRarity(PokemonCard card, String term) {
  final normalizedTerm = _previewRarityAlias(term);
  final rarityWords = [
    ..._previewFieldWords(card.rarity),
    _compactPreviewField(card.rarity),
    for (final tag in card.tags) ..._previewFieldWords(tag),
    for (final tag in card.tags) _compactPreviewField(tag),
  ].where((token) => token.isNotEmpty).toSet();
  return rarityWords.any((token) {
    return token == normalizedTerm ||
        token.startsWith(normalizedTerm) ||
        _previewRarityAlias(token) == normalizedTerm;
  });
}

String _previewRarityAlias(String term) {
  switch (_compactPreviewField(term)) {
    case 'sar':
    case 'sir':
      return 'specialillustrationrare';
    case 'ir':
      return 'illustrationrare';
    case 'ur':
      return 'ultrarare';
    case 'sr':
      return 'secretrare';
    case 'hr':
      return 'hyperrare';
    case 'dr':
      return 'doublerare';
    case 'ar':
      return 'art';
    default:
      return _compactPreviewField(term);
  }
}

bool _previewCardHasVariation(PokemonCard card, String term) {
  final normalizedTerm = _compactPreviewField(term);
  if (normalizedTerm.isEmpty) {
    return false;
  }
  final targets = _previewVariationTargets(normalizedTerm);
  if (targets.isNotEmpty && !targets.contains(normalizedTerm)) {
    return targets.any((target) => _previewCardHasVariation(card, target));
  }
  final text = [
    card.name,
    card.rarity,
    card.type,
    card.productType,
  ].join(' ').toLowerCase();
  switch (normalizedTerm) {
    case 'lvx':
      return RegExp(r'(^|[^a-z0-9])(lv\.?x|level x)([^a-z0-9]|$)')
              .hasMatch(text) ||
          _previewCardHasExactTag(card, normalizedTerm);
    case 'lv':
      return RegExp(r'(^|[^a-z0-9])lv\.?([0-9]+|x)([^a-z0-9]|$)')
              .hasMatch(text) ||
          _previewCardHasExactTag(card, normalizedTerm);
    case 'v':
      return RegExp(r'(^|[^a-z0-9])v([^a-z0-9]|$)').hasMatch(text) ||
          _previewCardHasExactTag(card, normalizedTerm);
    case 'mega':
      return RegExp(r'(^|[^a-z0-9])(mega|m)([^a-z0-9]|$)').hasMatch(text) ||
          _previewCardHasExactTag(card, normalizedTerm);
    case 'tagteam':
      return RegExp(r'(^|[^a-z0-9])(tag\s*team|tagteam|&)([^a-z0-9]|$)')
              .hasMatch(text) ||
          _previewCardHasExactTag(card, normalizedTerm);
    case 'goldstar':
      return RegExp(r'(^|[^a-z0-9])(gold\s*star|goldstar)([^a-z0-9]|$)')
              .hasMatch(text) ||
          _previewCardHasExactTag(card, normalizedTerm);
    case 'acespec':
      return RegExp(r'(^|[^a-z0-9])(ace\s*spec|acespec)([^a-z0-9]|$)')
              .hasMatch(text) ||
          _previewCardHasExactTag(card, normalizedTerm);
    default:
      return RegExp('(^|[^a-z0-9])$normalizedTerm([^a-z0-9]|\$)')
              .hasMatch(text) ||
          _previewCardHasExactTag(card, normalizedTerm);
  }
}

bool _previewCardHasExactTag(PokemonCard card, String normalizedTerm) {
  return card.tags.any((tag) => _compactPreviewField(tag) == normalizedTerm);
}

bool _isPreviewVariationSearchTerm(String term) {
  return _previewVariationTargets(term).isNotEmpty;
}

const Set<String> _previewVariationTerms = {
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
  'tagteam',
  'delta',
  'goldstar',
  'acespec',
};

List<String> _previewVariationTargets(String term) {
  final normalizedTerm = _compactPreviewField(term);
  if (normalizedTerm.isEmpty) {
    return const [];
  }
  if (_previewVariationTerms.contains(normalizedTerm)) {
    return [normalizedTerm];
  }
  if (normalizedTerm == 'g' ||
      normalizedTerm == 'e' ||
      normalizedTerm.length >= 2) {
    return _previewVariationTerms
        .where((variation) => variation.startsWith(normalizedTerm))
        .toList(growable: false);
  }
  return const [];
}

List<String> _typedPreviewTerms(String query) {
  return query
      .replaceAll(
          RegExp(r'\bhearth\s+gold\b', caseSensitive: false), 'hearthgold')
      .replaceAll(
          RegExp(r'\bheart\s+gold\b', caseSensitive: false), 'heartgold')
      .replaceAll(
          RegExp(r'\bsoul\s+silver\b', caseSensitive: false), 'soulsilver')
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .map(_compactPreviewField)
      .where((term) => term.isNotEmpty)
      .toList(growable: false);
}

List<String> _previewExpansionAliasTargets(String term) {
  switch (_compactPreviewField(term)) {
    case 'hgss':
    case 'hgs':
    case 'heartgold':
    case 'hearthgold':
    case 'heartgoldsoulsilver':
    case 'soulsilver':
      return const [
        'heartgoldsoulsilver',
        'unleashed',
        'undaunted',
        'triumphant',
        'calloflegends',
      ];
    default:
      return const [];
  }
}

List<String> _previewDisplayTokens(PokemonCard card) {
  return [
    card.name,
    card.trainerName,
    card.productType,
    card.itemKind,
  ].expand(_previewFieldWords).toList(growable: false);
}

String _compactPreviewField(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

List<String> _previewFieldWords(String value) {
  return value
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .map(_compactPreviewField)
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
}

List<PokemonCard> _emptyFocusPreviews(
  List<PokemonCard> hotCards,
  List<RecentCardView> recentViews,
) {
  if (hotCards.isEmpty && recentViews.isEmpty) {
    return const [];
  }

  final byId = {for (final card in hotCards) card.id: card};
  final previews = <PokemonCard>[];
  final seen = <String>{};
  for (final view in recentViews) {
    final id = view.cardId.trim();
    if (id.isEmpty || !seen.add(id)) {
      continue;
    }
    previews.add(byId[id] ?? _cardFromRecentView(view));
    if (previews.length >= searchPreviewLimit) {
      return previews;
    }
  }

  for (final card in hotCards) {
    if (card.id.isEmpty || !seen.add(card.id)) {
      continue;
    }
    previews.add(card);
    if (previews.length >= searchPreviewLimit) {
      break;
    }
  }
  return previews;
}

List<PokemonCard> _remoteSearchResults(
  Iterable<PokemonCard> results, {
  int? limit,
}) {
  final seen = <String>{};
  final ordered = <PokemonCard>[];
  for (final card in results) {
    final id = card.id.trim();
    if (id.isEmpty || !seen.add(id)) {
      continue;
    }
    ordered.add(card);
    if (limit != null && ordered.length >= limit) {
      break;
    }
  }
  return ordered;
}

PokemonCard _cardFromRecentView(RecentCardView view) {
  final isProduct = view.itemKind == 'product' || view.productType != 'card';
  final type = isProduct ? _productTypeLabel(view.productType) : 'Card';
  return PokemonCard(
    id: view.cardId,
    name: view.name,
    imageUrl: view.imageUrl,
    previewImageUrl: view.previewImageUrl,
    homepageImageUrl: view.homepageImageUrl,
    rarity: isProduct ? type : 'Card',
    type: type,
    hp: 0,
    attacks: const [],
    price: (1000 + (_recentViewSeed(view.cardId) % 120000)).toDouble(),
    description: 'Saved from your recent marketplace views.',
    set: view.expansion,
    number: view.number,
    artist: '',
    stock: 0,
    rating: 0,
    reviewCount: 0,
    isFoil: false,
    isHolo: false,
    releaseDate: view.viewedAt,
    tags: [view.expansion, type, view.itemKind, view.productType],
    condition: 'NM',
    isGraded: false,
    itemKind: isProduct ? 'product' : 'single',
    productType: isProduct ? view.productType : 'card',
  );
}

String _productTypeLabel(String productType) {
  switch (productType) {
    case 'booster_pack':
      return 'Booster pack';
    case 'booster_box':
      return 'Booster box';
    case 'booster_bundle':
      return 'Booster bundle';
    case 'elite_trainer_box':
      return 'Elite Trainer Box';
    case 'tin':
      return 'Tin';
    case 'collection_box':
      return 'Collection box';
    case 'deck':
      return 'Deck';
    case 'championship_deck':
      return 'Championship deck';
    case 'accessory':
      return 'Accessory';
    case 'sealed_product':
      return 'Sealed product';
    default:
      return 'Card';
  }
}

int _recentViewSeed(String value) {
  return value.codeUnits.fold<int>(0, (sum, unit) => sum + unit * 31);
}
