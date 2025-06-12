import 'package:flutter/foundation.dart';
import 'card_model.dart';
import 'order.dart';

class CartItem {
  final CardModel card;
  final String condition;
  final String expansion;
  int quantity;

  CartItem({
    required this.card,
    required this.condition,
    required this.expansion,
    this.quantity = 1,
  });

  double get price => card.price;

  String get imageUrl => card.imageUrl;

  String get name => card.name;

  double get totalPrice => price * quantity;
}

class Cart with ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  void addItem(CardModel card, String condition, String expansion) {
    final existingItem = _findItem(card, condition, expansion);
    if (existingItem != null) {
      existingItem.quantity++;
    } else {
      _items.add(CartItem(
        card: card,
        condition: condition,
        expansion: expansion,
      ));
    }
    notifyListeners();
  }

  void removeItem(CartItem item) {
    _items.remove(item);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  double get totalAmount {
    return _items.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  CartItem? _findItem(CardModel card, String condition, String expansion) {
    try {
      return _items.firstWhere(
        (item) =>
            item.card == card &&
            item.condition == condition &&
            item.expansion == expansion,
      );
    } catch (_) {
      return null;
    }
  }

  // -------------------
  // ORDINI
  // -------------------

  final List<Order> _orders = [];

  List<Order> get orders => List.unmodifiable(_orders);

  // Funzione per creare un ordine a partire dal carrello
  Order placeOrder() {
    final newOrder = Order(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      items: _items
          .map((cartItem) => OrderItem(
                cardId: cartItem.card.id,
                name: cartItem.name,
                condition: cartItem.condition,
                expansion: cartItem.expansion,
                price: cartItem.price,
                quantity: cartItem.quantity,
              ))
          .toList(),
      status: ShippingStatus.ordered,
    );

    _orders.add(newOrder);
    clear(); // svuota il carrello dopo l'ordine
    notifyListeners();
    return newOrder;
  }

  // Funzione per aggiornare lo stato di un ordine (con avanzamento automatico)
  void advanceOrderStatus(String orderId) {
    final order = _orders.firstWhere(
      (o) => o.id == orderId,
      orElse: () => throw Exception('Ordine non trovato'),
    );

    switch (order.status) {
      case ShippingStatus.ordered:
        order.status = ShippingStatus.shipped;
        break;
      case ShippingStatus.shipped:
        order.status = ShippingStatus.delivered;
        break;
      case ShippingStatus.delivered:
        // già consegnato, non fa nulla
        break;
      case ShippingStatus.cancelled:
        // TODO: Handle this case.
        throw UnimplementedError();
    }

    notifyListeners();
  }

  // Se vuoi aggiornare direttamente lo stato a uno specifico:
  void updateOrderStatus(String orderId, ShippingStatus status) {
    final order = _orders.firstWhere(
      (o) => o.id == orderId,
      orElse: () => throw Exception('Ordine non trovato'),
    );
    order.status = status;
    notifyListeners();
  }
}
