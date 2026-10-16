import 'card.dart';
import 'listing.dart';

class ListingCartItem {
  const ListingCartItem(
      {required this.card, required this.listing, required this.quantity});
  final MarketplaceCard card;
  final MarketplaceListing listing;
  final int quantity;
  double get totalPkn => listing.pricePkn * quantity;
}

/// Riga immutabile del carrello locale del prototipo.
class CartItem {
  const CartItem({required this.card, required this.quantity});

  final DemoCard card;
  final int quantity;

  double get totalPrice => card.price * quantity;
}
