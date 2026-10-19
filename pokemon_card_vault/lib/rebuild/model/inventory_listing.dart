import 'cardex.dart';

class InventorySnapshot {
  InventorySnapshot(
      {required List<InventoryListing> items, required this.complete})
      : items = List.unmodifiable(items);
  final List<InventoryListing> items;
  final bool complete;
}

/// Owner stock, not a purchase offer: a paused or unpriced card is still owned.
class InventoryListing {
  const InventoryListing({required this.item, required this.status});
  final OwnedCard item;
  final String status;

  factory InventoryListing.fromJson(Map<String, dynamic> json) =>
      InventoryListing(
        item: OwnedCard.fromJson({
          ...json,
          'quantity': json['quantityAvailable'],
          'holo': json['holo'] == true || json['foilState'] == 'holo',
          'reverse': json['reverse'] == true || json['foilState'] == 'reverse',
        }),
        status: '${json['status'] ?? ''}'.trim().toLowerCase(),
      );

  bool get isOwned =>
      (status == 'active' || status == 'paused') && item.quantity > 0;
}
