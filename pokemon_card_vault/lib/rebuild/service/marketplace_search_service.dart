import '../model/marketplace_search.dart';
import '../provider/marketplace_search_provider.dart';
import '../provider/marketplace_artist_provider.dart';
import '../model/marketplace_artist_catalog.dart';
import '../cache/marketplace_search_cache.dart';
import 'package:pokoin_suggest/pokoin_suggest.dart' show compactQuery;

class MarketplaceSearchService {
  MarketplaceSearchService(
      {MarketplaceSearchProvider? provider,
      MarketplaceArtistProvider? artistProvider,
      MarketplaceSearchCache? cache})
      : _provider = provider ?? MarketplaceSearchProvider(),
        _ownsProvider = provider == null,
        _artistProvider = artistProvider,
        _ownsArtistProvider = artistProvider == null,
        _cache = cache ?? MarketplaceSearchCache();

  final MarketplaceSearchProvider _provider;
  final bool _ownsProvider;
  MarketplaceArtistProvider? _artistProvider;
  final bool _ownsArtistProvider;
  final MarketplaceSearchCache _cache;
  final _artistPending = <String, Future<MarketplaceArtistCatalog>>{};

  MarketplaceSearchPage? cached(MarketplaceSearchRequest request) =>
      _cache.page(request);

  Future<MarketplaceSearchPage> search(MarketplaceSearchRequest request) async {
    if (request.offset < 0 || request.limit < 1 || request.limit > 100) {
      throw ArgumentError('Invalid pagination');
    }
    final query = request.query.trim();
    if (query.length > 180) throw ArgumentError('Search query too long');
    final page = request.artist != null
        ? await _searchArtist(request)
        : await _provider.fetch(MarketplaceSearchRequest(
            query: query,
            productType: request.productType,
            printLanguage: request.printLanguage,
            searchLanguage: request.searchLanguage,
            offset: request.offset,
            limit: request.limit));
    _cache.rememberPage(request, page);
    return page;
  }

  Future<MarketplaceArtistCatalog> _catalog(String slug) async {
    final cached = _cache.artist(slug);
    if (cached != null) return cached;
    final pending = _artistPending[slug];
    if (pending != null) return pending;
    final fetch = (_artistProvider ??= MarketplaceArtistProvider()).fetch(slug);
    _artistPending[slug] = fetch;
    try {
      final catalog = await fetch;
      _cache.rememberArtist(slug, catalog);
      return catalog;
    } finally {
      if (identical(_artistPending[slug], fetch)) _artistPending.remove(slug);
    }
  }

  Future<MarketplaceSearchPage> _searchArtist(
      MarketplaceSearchRequest request) async {
    final artist = request.artist!;
    final catalog = await _catalog(artist.slug);
    final terms = artist.remainingQuery
        .split(RegExp(r'\s+'))
        .map(compactQuery)
        .where((term) => term.isNotEmpty)
        .toList();
    bool printMatches(String value) =>
        request.printLanguage == 'all' ||
        value == request.printLanguage ||
        (request.printLanguage == 'japanese' && value == 'korean');
    final matching = catalog.cards
        .where((card) =>
            (request.productType.isEmpty ||
                card.productType == request.productType) &&
            printMatches(card.printBucket) &&
            terms.every((term) =>
                card.searchFields.any((field) => field.contains(term))))
        .map((card) => card.preview)
        .toList();
    return MarketplaceSearchPage(
        cards: matching.skip(request.offset).take(request.limit).toList(),
        total: matching.length,
        hasMore: request.offset + request.limit < matching.length);
  }

  void cancelPending() {
    _provider.cancelPending();
    _artistProvider?.cancelPending();
    // A new query must not join an artist request that has just been aborted.
    _artistPending.clear();
  }

  void dispose() {
    if (_ownsProvider) _provider.dispose();
    if (_ownsArtistProvider) _artistProvider?.dispose();
  }
}
