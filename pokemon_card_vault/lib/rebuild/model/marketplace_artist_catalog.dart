import 'marketplace_home.dart';

class MarketplaceArtistCard {
  const MarketplaceArtistCard(this.preview, this.searchFields,
      {required this.productType, required this.printBucket});
  final MarketplaceCardPreview preview;
  final List<String> searchFields;
  final String productType, printBucket;
}

class MarketplaceArtistCatalog {
  MarketplaceArtistCatalog(List<MarketplaceArtistCard> cards)
      : cards = List.unmodifiable(cards);
  final List<MarketplaceArtistCard> cards;
}
