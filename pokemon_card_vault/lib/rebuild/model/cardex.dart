import 'marketplace_home.dart';

enum CollectionStatus { loading, guest, ready, unavailable }

enum CardexFilter { all, owned, missing }

/// Una copia/variante posseduta. Nessun accesso a Firebase nel modello.
class OwnedCard {
  const OwnedCard(
      {required this.card,
      required this.quantity,
      this.id = '',
      this.listingId = '',
      this.sourceListingId = '',
      this.language = '',
      this.holo = false,
      this.reverse = false});

  factory OwnedCard.fromJson(Map<String, dynamic> json) => OwnedCard(
        id: '${json['id'] ?? ''}'.trim(),
        listingId: '${json['listingId'] ?? ''}'.trim(),
        sourceListingId: '${json['sourceListingId'] ?? ''}'.trim(),
        card: MarketplaceCardPreview(
          id: '${json['cardId'] ?? json['blueprintId'] ?? ''}'.trim(),
          name: '${json['cardName'] ?? json['name'] ?? ''}',
          expansion: '${json['setName'] ?? ''}',
          number: '${json['collectorNumber'] ?? ''}',
          imageUrl: '${json['cardImageUrl'] ?? ''}',
        ),
        quantity: num.tryParse('${json['quantity'] ?? 0}')?.toInt() ?? 0,
        language: '${json['language'] ?? ''}',
        holo: json['holo'] == true,
        reverse: json['reverse'] == true,
      );

  final MarketplaceCardPreview card;
  final String id, listingId, sourceListingId;
  final int quantity;
  final String language;
  final bool holo, reverse;
}

class CardCollection {
  CardCollection({required this.status, List<OwnedCard> items = const []})
      : items = List.unmodifiable(items
            .where((item) => item.quantity > 0 && item.card.id.isNotEmpty));
  final CollectionStatus status;
  final List<OwnedCard> items;

  /// Solo ID canonici Pokoin: nomi simili non rendono posseduta un'altra stampa.
  int quantityFor(String id) => items
      .where((item) => item.card.id == id)
      .fold(0, (sum, item) => sum + item.quantity);
  bool owns(String id) => quantityFor(id) > 0;
  int get copies => items.fold(0, (sum, item) => sum + item.quantity);
  List<MarketplaceCardPreview> get cards => List.unmodifiable({
        for (final item in items) item.card.id: item.card,
      }.values);
}

class CardexPage {
  CardexPage(
      {required this.expansion,
      required List<MarketplaceCardPreview> cards,
      required this.offset,
      required this.hasMore,
      required this.total})
      : cards = List.unmodifiable(cards);
  final MarketplaceExpansion expansion;
  final List<MarketplaceCardPreview> cards;
  final int offset, total;
  final bool hasMore;
}
