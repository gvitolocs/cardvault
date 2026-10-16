import 'marketplace_home.dart';

/// Dati della risposta home, prima delle regole di selezione dei caroselli.
class MarketplaceHomePayload {
  MarketplaceHomePayload({
    required List<MarketplaceCardPreview> cards,
    required List<String> bestSellerIds,
    required List<String> newArrivalIds,
  })  : cards = List.unmodifiable(cards),
        bestSellerIds = List.unmodifiable(bestSellerIds),
        newArrivalIds = List.unmodifiable(newArrivalIds);

  final List<MarketplaceCardPreview> cards;
  final List<String> bestSellerIds;
  final List<String> newArrivalIds;
}
