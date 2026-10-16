import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:pokoin_suggest/pokoin_suggest.dart' show ArtistQuery;

import '../model/marketplace_home.dart';
import '../model/marketplace_search.dart';
import '../service/marketplace_search_service.dart';
import '../service/marketplace_suggestion_service.dart';
import '../model/marketplace_suggestions.dart';

class MarketplaceSearchController extends ChangeNotifier {
  MarketplaceSearchController(
      {MarketplaceSearchService? service,
      MarketplaceSuggestionService? suggestionService,
      this.debounce = const Duration(milliseconds: 300)})
      : _service = service,
        _ownsService = service == null,
        // A caller injecting search also owns optional suggestion wiring.
        _suggestions = suggestionService ??
            (service == null ? MarketplaceSuggestionService() : null),
        _ownsSuggestions = suggestionService == null;

  MarketplaceSearchService? _service;
  final bool _ownsService;
  final MarketplaceSuggestionService? _suggestions;
  final bool _ownsSuggestions;
  MarketplaceSuggestionsState _suggestionState = MarketplaceSuggestionsState();
  bool _suggestionsVisible = false;
  // Reuse the current search page: the popup never starts a second API request.
  MarketplaceSuggestionsState get suggestions => !_suggestionsVisible
      ? MarketplaceSuggestionsState()
      : MarketplaceSuggestionsState(
          items: _suggestionState.items,
          loading: _suggestionState.loading,
          hasError: _suggestionState.hasError,
          cards: _state.isLoading ? const [] : _state.cards.take(6).toList(),
          cardsLoading: _state.isLoading,
          cardsError: _state.hasError && _state.cards.isEmpty);
  int _suggestionGeneration = 0;
  final Duration debounce;
  MarketplaceSearchState _state = MarketplaceSearchState();
  MarketplaceSearchState get state => _state;
  Timer? _timer;
  int _generation = 0;
  int _nextOffset = 0;
  bool _disposed = false;

  void setQuery(String query) {
    if (_disposed || query == _state.query) return;
    _replace(query: query);
  }

  void setFilters(
      {required String productType, required String printLanguage}) {
    if (_disposed ||
        (productType == _state.productType &&
            printLanguage == _state.printLanguage)) {
      return;
    }
    _replace(
        productType: productType,
        printLanguage: printLanguage,
        immediate: true);
  }

  void _replace(
      {String? query,
      String? productType,
      String? printLanguage,
      bool immediate = false}) {
    _timer?.cancel();
    _generation++;
    _service?.cancelPending();
    _nextOffset = 0;
    _state = MarketplaceSearchState(
        query: query ?? _state.query,
        productType: productType ?? _state.productType,
        printLanguage: printLanguage ?? _state.printLanguage);
    Timeline.instantSync('search.changed',
        arguments: {'characters': _state.query.length});
    if (_state.isActive) {
      final cached = _service?.cached(MarketplaceSearchRequest(
          query: _state.query,
          productType: _state.productType,
          printLanguage: _state.printLanguage));
      if (cached != null) {
        Timeline.instantSync('search.cacheHit');
        _acceptPage(cached, 0, 24);
      } else {
        _state = _snapshot(isLoading: true);
        if (immediate) {
          unawaited(_load(_generation, 0));
        } else {
          _timer = Timer(debounce, () => unawaited(_load(_generation, 0)));
        }
      }
    }
    unawaited(refreshSuggestions());
    notifyListeners();
  }

  void warmUpSuggestions() {
    unawaited(_warmSuggestions());
  }

  Future<void> _warmSuggestions() async {
    try {
      await _suggestions?.warmUp();
    } catch (_) {/* API search remains available. */}
  }

  Future<void> refreshSuggestions() async {
    if (_disposed) {
      return;
    }
    final generation = ++_suggestionGeneration;
    final query = _state.query;
    var meaningful = 0;
    var nonAscii = false;
    for (final unit in query.codeUnits) {
      if (unit > 127) {
        nonAscii = true;
      }
      if ((unit >= 48 && unit <= 57) ||
          (unit >= 65 && unit <= 90) ||
          (unit >= 97 && unit <= 122)) {
        meaningful++;
      }
    }
    if ((!nonAscii && meaningful < 3) || query.trim().length < 3) {
      _suggestionsVisible = false;
      _suggestionState = MarketplaceSuggestionsState();
      notifyListeners();
      return;
    }
    _suggestionsVisible = true;
    if (_suggestions == null) {
      _suggestionState = MarketplaceSuggestionsState();
      notifyListeners();
      return;
    }
    _suggestionState = MarketplaceSuggestionsState(loading: true);
    notifyListeners();
    try {
      final rows = await _suggestions.suggest(query);
      if (_disposed || generation != _suggestionGeneration) {
        return;
      }
      _suggestionState = MarketplaceSuggestionsState(items: rows);
    } catch (_) {
      if (_disposed || generation != _suggestionGeneration) {
        return;
      }
      _suggestionState = MarketplaceSuggestionsState(hasError: true);
    }
    notifyListeners();
  }

  void dismissSuggestions() {
    if (_disposed) {
      return;
    }
    _suggestionGeneration++;
    final wasVisible = _suggestionsVisible;
    _suggestionsVisible = false;
    _suggestionState = MarketplaceSuggestionsState();
    if (wasVisible) notifyListeners();
  }

  Future<void> selectSuggestion(LocalSuggestion item) {
    if (_disposed) {
      return Future.value();
    }
    _timer?.cancel();
    _generation++;
    _service?.cancelPending();
    _nextOffset = 0;
    _state = MarketplaceSearchState(
        query: item.query,
        productType: _state.productType,
        printLanguage: _state.printLanguage,
        isLoading: true);
    dismissSuggestions();
    notifyListeners();
    return _load(_generation, 0,
        resolveArtist: false, resolvedArtist: item.artist);
  }

  Future<void> submit() {
    if (_disposed || !_state.isActive) return Future.value();
    _timer?.cancel();
    dismissSuggestions();
    _generation++;
    _suggestionGeneration++;
    _service?.cancelPending();
    _nextOffset = 0;
    _state = _snapshot(isLoading: true);
    notifyListeners();
    return _load(_generation, 0);
  }

  Future<void> loadMore() {
    if (_disposed ||
        _state.isLoading ||
        _state.isLoadingMore ||
        !_state.hasMore) {
      return Future.value();
    }
    _state = _snapshot(isLoadingMore: true);
    notifyListeners();
    return _load(_generation, _nextOffset);
  }

  Future<void> retry() => _nextOffset == 0 ? submit() : loadMore();

  Future<void> _load(int generation, int offset,
      {bool resolveArtist = true, ArtistQuery? resolvedArtist}) async {
    // Reuse the analysis already requested by typing; do not rank twice.
    final query = _state.query;
    final productType = _state.productType;
    final printLanguage = _state.printLanguage;
    final suggestionService = _suggestions;
    ArtistQuery? artist = resolvedArtist;
    if (resolveArtist &&
        suggestionService != null &&
        query.trim().length >= 3) {
      try {
        artist = await suggestionService.resolveArtist(query);
      } catch (_) {/* Dictionary failure keeps the original API path usable. */}
    }
    if (_disposed || generation != _generation) return;
    final request = MarketplaceSearchRequest(
        query: query,
        artist: artist,
        productType: productType,
        printLanguage: printLanguage,
        offset: offset);
    try {
      final page =
          await (_service ??= MarketplaceSearchService()).search(request);
      if (_disposed || generation != _generation) return;
      _acceptPage(page, offset, request.limit);
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _state = _snapshot(hasError: true);
    }
    notifyListeners();
  }

  void _acceptPage(MarketplaceSearchPage page, int offset, int limit) {
    Timeline.instantSync('search.accepted',
        arguments: {'rows': page.cards.length, 'offset': offset});
    final unique = <String, MarketplaceCardPreview>{
      if (offset > 0)
        for (final card in _state.cards) card.id: card,
      for (final card in page.cards) card.id: card,
    };
    // L'offset segue le righe del server, anche se gli ID sono duplicati.
    _nextOffset = offset + limit;
    _state = _snapshot(
        cards: unique.values.toList(),
        hasMore: page.hasMore,
        total: page.total,
        preserveTotal: false);
  }

  MarketplaceSearchState _snapshot(
          {List<MarketplaceCardPreview>? cards,
          bool isLoading = false,
          bool isLoadingMore = false,
          bool hasError = false,
          bool? hasMore,
          int? total,
          bool preserveTotal = true}) =>
      MarketplaceSearchState(
          query: _state.query,
          productType: _state.productType,
          printLanguage: _state.printLanguage,
          cards: cards ?? _state.cards,
          isLoading: isLoading,
          isLoadingMore: isLoadingMore,
          hasError: hasError,
          hasMore: hasMore ?? _state.hasMore,
          total: preserveTotal ? _state.total : total);

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    if (_ownsService) _service?.dispose();
    if (_ownsSuggestions) _suggestions?.dispose();
    super.dispose();
  }
}
