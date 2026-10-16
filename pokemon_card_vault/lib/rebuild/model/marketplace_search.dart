import 'marketplace_home.dart';
import 'package:pokoin_suggest/pokoin_suggest.dart' show ArtistQuery;

class MarketplaceSearchRequest {
  const MarketplaceSearchRequest({
    required this.query,
    this.productType = '',
    this.printLanguage = 'all',
    this.searchLanguage = 'en',
    this.offset = 0,
    this.limit = 24,
    this.artist,
  });

  final String query;
  final String productType;
  final String printLanguage;
  final String searchLanguage;
  final int offset;
  final int limit;
  final ArtistQuery? artist;
}

class MarketplaceSearchPage {
  MarketplaceSearchPage(
      {required List<MarketplaceCardPreview> cards,
      required this.hasMore,
      this.total})
      : cards = List.unmodifiable(cards);

  final List<MarketplaceCardPreview> cards;
  final bool hasMore;
  final int? total;
}

class MarketplaceSearchState {
  MarketplaceSearchState({
    this.query = '',
    this.productType = '',
    this.printLanguage = 'all',
    List<MarketplaceCardPreview> cards = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasError = false,
    this.hasMore = false,
    this.total,
  }) : cards = List.unmodifiable(cards);

  final String query;
  final String productType;
  final String printLanguage;
  final List<MarketplaceCardPreview> cards;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasError;
  final bool hasMore;
  final int? total;
  bool get isActive =>
      query.trim().isNotEmpty ||
      productType.isNotEmpty ||
      printLanguage != 'all';
}
