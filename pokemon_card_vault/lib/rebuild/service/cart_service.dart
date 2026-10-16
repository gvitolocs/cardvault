import 'package:flutter/foundation.dart';

import '../model/card.dart';
import '../model/cart_item.dart';
import '../model/listing.dart';

/// Carrello in memoria: offerte reali in PKN e articoli demo separati in EUR.
/// Non dipende da BuildContext, widget, autenticazione o API.
class CartService extends ChangeNotifier {
  final _items = <String, CartItem>{};
  final _listingItems = <String, ListingCartItem>{};
  List<ListingCartItem> get listingItems =>
      List.unmodifiable(_listingItems.values);
  double get totalPkn =>
      _listingItems.values.fold(0, (sum, item) => sum + item.totalPkn);
  int listingQuantity(String id) => _listingItems[id]?.quantity ?? 0;

  /// Snapshot non modificabile: lo stato cambia solo attraverso il servizio.
  List<CartItem> get items => List.unmodifiable(_items.values);

  /// Numero di articoli, incluse le quantità della stessa carta.
  int get itemCount =>
      _items.values.fold(0, (sum, item) => sum + item.quantity) +
      _listingItems.values.fold(0, (sum, item) => sum + item.quantity);

  bool addListing(MarketplaceCard card, MarketplaceListing listing) {
    if (listing.cardId != card.id || !listing.isAvailable) return false;
    final quantity = listingQuantity(listing.id);
    if (quantity >= listing.stock) return false;
    _listingItems[listing.id] =
        ListingCartItem(card: card, listing: listing, quantity: quantity + 1);
    notifyListeners();
    return true;
  }

  void decreaseListing(String id) {
    final item = _listingItems[id];
    if (item == null) return;
    if (item.quantity == 1) {
      _listingItems.remove(id);
    } else {
      _listingItems[id] = ListingCartItem(
          card: item.card, listing: item.listing, quantity: item.quantity - 1);
    }
    notifyListeners();
  }

  void removeListing(String id) {
    if (_listingItems.remove(id) != null) notifyListeners();
  }

  double get totalPrice =>
      _items.values.fold(0, (sum, item) => sum + item.totalPrice);

  void addCard(DemoCard card) {
    // Solo demo: gli articoli reali entrano tramite addListing, mai dal prezzo
    // indicativo del catalogo. I due totali non mescolano EUR e PKN.
    _items[card.id] = CartItem(
      card: card,
      quantity: (_items[card.id]?.quantity ?? 0) + 1,
    );
    notifyListeners();
  }

  /// Rimuove l'intera riga, mantenendo il comportamento del prototipo.
  void removeCard(String cardId) {
    if (_items.remove(cardId) != null) notifyListeners();
  }

  // Collegamento futuro: sincronizzazione/persistenza tramite cartProvider.
  // Il checkout reale richiede offerte aggiornate e autenticazione.
  // Qui non ci sono chiamate ai servizi esterni né pagamenti.
}
