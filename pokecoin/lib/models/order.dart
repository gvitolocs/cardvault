enum ShippingStatus {
  ordered,
  shipped,
  delivered,
  cancelled, // Nuovo stato aggiunto
}

class Order {
  final String id;
  final List<OrderItem> items;
  ShippingStatus status;

  Order({
    required this.id,
    required this.items,
    this.status = ShippingStatus.ordered,
  });
}

class OrderItem {
  final String cardId;
  final String name;
  final String condition;
  final String expansion;
  final double price;
  final int quantity; // Aggiunto il campo mancante

  OrderItem({
    required this.cardId,
    required this.name,
    required this.condition,
    required this.expansion,
    required this.price,
    required this.quantity,
  });
}
