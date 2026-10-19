import 'card.dart';
import 'listing.dart';

class ListingCartItem {
  const ListingCartItem(
      {required this.card,
      required this.listing,
      required this.quantity,
      this.storedData = const {}});
  final MarketplaceCard card;
  final MarketplaceListing listing;
  final int quantity;

  /// Campi legacy da preservare quando si aggiorna una riga già salvata.
  final Map<String, dynamic> storedData;
  double get totalPkn => listing.pricePkn * quantity;

  ListingCartItem withQuantity(int value) => ListingCartItem(
      card: card, listing: listing, quantity: value, storedData: storedData);
}

/// Una modifica assoluta; null è una rimozione persistente (tombstone).
class CartEdit {
  const CartEdit(this.item);
  final ListingCartItem? item;
}

/// Snapshot locale e modifiche ancora da inviare al carrello remoto.
class CartSnapshot {
  CartSnapshot(
      {Iterable<ListingCartItem> items = const [],
      Map<String, CartEdit> pending = const {}})
      : items = List.unmodifiable(items),
        pending = Map.unmodifiable(pending);
  final List<ListingCartItem> items;
  final Map<String, CartEdit> pending;
}

enum CartProblem { localRead, localWrite, remoteSync, limit }

/// Riga immutabile del carrello locale del prototipo.
class CartItem {
  const CartItem({required this.card, required this.quantity});

  final DemoCard card;
  final int quantity;

  double get totalPrice => card.price * quantity;
}
