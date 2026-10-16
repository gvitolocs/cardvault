import '../model/marketplace_artist_catalog.dart';
import '../model/marketplace_search.dart';

/// Short-lived successful results only; prices/totals expire with the page.
class MarketplaceSearchCache {
  MarketplaceSearchCache({DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  static const retention = Duration(seconds: 30);
  final _pages = <({
    String q,
    String type,
    String print,
    String lang,
    int offset,
    int limit
  }),
      (DateTime, MarketplaceSearchPage)>{};
  final _artists = <String, (DateTime, MarketplaceArtistCatalog)>{};

  ({String q, String type, String print, String lang, int offset, int limit})
      _key(MarketplaceSearchRequest request) => (
            q: request.query.trim().toLowerCase(),
            type: request.productType,
            print: request.printLanguage,
            lang: request.searchLanguage,
            offset: request.offset,
            limit: request.limit
          );

  MarketplaceSearchPage? page(MarketplaceSearchRequest request) {
    final key = _key(request);
    final entry = _pages[key];
    if (entry == null) return null;
    if (_now().difference(entry.$1) >= retention) {
      _pages.remove(key);
      return null;
    }
    return entry.$2;
  }

  void rememberPage(
      MarketplaceSearchRequest request, MarketplaceSearchPage page) {
    _pages.remove(_key(request));
    _pages[_key(request)] = (_now(), page);
    while (_pages.length > 16) {
      _pages.remove(_pages.keys.first);
    }
  }

  MarketplaceArtistCatalog? artist(String slug) {
    final entry = _artists[slug];
    if (entry == null) return null;
    if (_now().difference(entry.$1) >= retention) {
      _artists.remove(slug);
      return null;
    }
    return entry.$2;
  }

  void rememberArtist(String slug, MarketplaceArtistCatalog catalog) {
    _artists.remove(slug);
    _artists[slug] = (_now(), catalog);
    while (_artists.length > 2) {
      _artists.remove(_artists.keys.first);
    }
  }
}
