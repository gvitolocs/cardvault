import '../model/card.dart';
import '../model/cart_item.dart';
import '../model/listing.dart';

/// Compatibilità con le righe di old/providers/cart_provider.dart, senza
/// importarne Riverpod, modelli Hive o logica applicativa.
class CartCodec {
  static Map<String, dynamic> encodeItem(ListingCartItem item) {
    final listing = item.listing.toJson();
    return {
      ...item.storedData,
      ...listing,
      'card': {
        if (item.storedData['card'] is Map)
          ...Map<String, dynamic>.from(item.storedData['card'] as Map),
        ...item.card.toJson(),
        'hp': item.card.hp ?? 0,
        'price': item.listing.pricePkn,
        'stock': item.listing.stock,
      },
      'listingId': item.listing.id,
      'unitPricePkn': item.listing.pricePkn,
      'quantity': item.quantity,
      'listing': listing,
    };
  }

  static ListingCartItem? decodeItem(Object? value) {
    if (value is! Map) return null;
    final row = Map<String, dynamic>.from(value);
    if (row['card'] is! Map) return null;
    final card =
        MarketplaceCard.fromJson(Map<String, dynamic>.from(row['card'] as Map));
    final data = row['listing'] is Map
        ? Map<String, dynamic>.from(row['listing'] as Map)
        : (Map<String, dynamic>.from(row)
          ..remove('card')
          ..remove('quantity'));
    final listing = MarketplaceListing.fromJson({
      ...data,
      'id': row['listingId'] ?? data['id'],
      'cardId': data['cardId'] ?? card.id,
      'pricePkn': data['pricePkn'] ?? row['unitPricePkn'],
      'status': data['status'] ?? 'active',
    });
    final quantity = int.tryParse('${row['quantity']}');
    if (card.id.isEmpty ||
        card.name.isEmpty ||
        listing.id.isEmpty ||
        listing.cardId != card.id ||
        quantity == null ||
        quantity <= 0 ||
        !listing.pricePkn.isFinite ||
        listing.pricePkn <= 0 ||
        listing.stock < 0) {
      return null;
    }
    return ListingCartItem(
        card: card,
        listing: listing,
        quantity: quantity,
        storedData: Map.unmodifiable(row));
  }

  static List<ListingCartItem> decodeItems(Iterable<Object?> rows) => [
        for (final row in rows)
          if (decodeItem(row) case final item?) item,
      ];

  static Map<String, dynamic> encodeSnapshot(CartSnapshot snapshot) => {
        'version': 1,
        'items': snapshot.items.map(encodeItem).toList(),
        'pending': {
          for (final entry in snapshot.pending.entries)
            entry.key:
                entry.value.item == null ? null : encodeItem(entry.value.item!)
        },
      };

  static CartSnapshot decodeSnapshot(Map value) {
    if (value['version'] != 1 ||
        value['items'] is! List ||
        value['pending'] is! Map) {
      throw const FormatException('Invalid cart snapshot');
    }
    final items = decodeItems(value['items'] as List);
    if (items.length != (value['items'] as List).length) {
      throw const FormatException('Invalid saved cart item');
    }
    final pending = <String, CartEdit>{};
    for (final entry in (value['pending'] as Map).entries) {
      final item = decodeItem(entry.value);
      if (entry.key is! String ||
          (entry.key as String).isEmpty ||
          (entry.value != null &&
              (item == null || item.listing.id != entry.key))) {
        throw const FormatException('Invalid pending cart edit');
      }
      pending[entry.key as String] = CartEdit(item);
    }
    return CartSnapshot(items: items, pending: pending);
  }

  /// Applica solo le righe modificate: conserva righe legacy non rappresentabili
  /// e modifiche fatte da altri dispositivi su offerte diverse.
  static List<Object?> applyEdits(
      List<Object?> rows, Map<String, CartEdit> edits) {
    final remaining = Map.of(edits);
    final result = <Object?>[];
    for (final row in rows) {
      final key = row is Map ? '${row['listingId'] ?? ''}' : '';
      if (!edits.containsKey(key)) {
        result.add(row);
      } else if (remaining.remove(key) case final edit?) {
        if (edit.item != null) result.add(encodeItem(edit.item!));
      }
    }
    for (final edit in remaining.values) {
      if (edit.item != null) result.add(encodeItem(edit.item!));
    }
    if (result.length > 100) throw StateError('Cart limit exceeded');
    return result;
  }
}
