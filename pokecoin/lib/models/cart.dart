import 'package:flutter/foundation.dart';
import 'card_model.dart';

class Cart with ChangeNotifier {
  final List<CardModel> _items = [];

  List<CardModel> get items => _items;

  void addItem(CardModel card) {
    _items.add(card);
    notifyListeners();
  }

  void removeItem(CardModel card) {
    _items.removeWhere((item) => item.id == card.id);
    notifyListeners();
  }

  double get totalAmount {
    return _items.fold(0.0, (sum, item) => sum + item.price);
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
