import 'package:flutter/foundation.dart';

import '../model/card.dart';
import '../model/cart_item.dart';
import '../model/listing.dart';
import '../service/cart_service.dart';

/// Coordina CartService ed espone stato e azioni alla presentazione.
/// Snapshot e totali vengono ricalcolati solo dopo una modifica del carrello.
class CartController extends ChangeNotifier {
  CartController({CartService? service})
      : _service = service ?? CartService(),
        _ownsService = service == null {
    _service.addListener(_onCartChanged);
  }

  final CartService _service;
  final bool _ownsService;
  List<CartItem>? _items;
  int? _itemCount;
  double? _totalPrice;
  List<ListingCartItem>? _listingItems;
  double? _totalPkn;
  final _quantities = <String, ValueNotifier<int>>{};

  List<CartItem> get items => _items ??= _service.items;
  int get itemCount => _itemCount ??= _service.itemCount;
  double get totalPrice => _totalPrice ??= _service.totalPrice;
  List<ListingCartItem> get listingItems =>
      _listingItems ??= _service.listingItems;
  double get totalPkn => _totalPkn ??= _service.totalPkn;
  ValueListenable<int> quantityFor(String id) => _quantities.putIfAbsent(
      id, () => ValueNotifier(_service.listingQuantity(id)));
  bool addListing(MarketplaceCard card, MarketplaceListing listing) =>
      _service.addListing(card, listing);
  void decreaseListing(String id) => _service.decreaseListing(id);
  void removeListing(String id) => _service.removeListing(id);

  void addCard(DemoCard card) => _service.addCard(card);
  void removeCard(String cardId) => _service.removeCard(cardId);

  void _onCartChanged() {
    _items = null;
    _itemCount = null;
    _totalPrice = null;
    _listingItems = null;
    _totalPkn = null;
    for (final entry in _quantities.entries) {
      entry.value.value = _service.listingQuantity(entry.key);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _service.removeListener(_onCartChanged);
    for (final notifier in _quantities.values) {
      notifier.dispose();
    }
    if (_ownsService) _service.dispose();
    super.dispose();
  }
}
