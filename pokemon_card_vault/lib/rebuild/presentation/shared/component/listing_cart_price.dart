import 'package:flutter/material.dart';
import '../../../controller/cart_controller.dart';
import '../../../model/card.dart';
import '../../../model/listing.dart';
import '../atomics/cart_price.dart';
import '../price_format.dart';

/// Prezzo dell'offerta selezionata con aggiunta vincolata al suo stock.
class ListingCartPrice extends StatelessWidget {
  const ListingCartPrice(
      {super.key,
      required this.card,
      required this.listing,
      required this.cart,
      this.previewOnly = false,
      this.style});
  final MarketplaceCard? card;
  final MarketplaceListing listing;
  final CartController cart;
  final bool previewOnly;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: cart.editable,
        builder: (context, editable, _) => ValueListenableBuilder<int>(
          valueListenable: cart.quantityFor(listing.id),
          builder: (context, quantity, _) => CartPrice(
            price: pknPrice(listing.pricePkn),
            style: style,
            tooltip: previewOnly
                ? 'Offerta dimostrativa'
                : quantity >= listing.stock
                    ? 'Quantità disponibile raggiunta'
                    : 'Aggiungi al carrello',
            onAdd: !previewOnly &&
                    editable &&
                    card != null &&
                    listing.isAvailable &&
                    quantity < listing.stock
                ? () {
                    if (cart.addListing(card!, listing)) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              '${card!.name} aggiunta al carrello · ${pknPrice(listing.pricePkn)}')));
                    } else if (cart.error != null) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(cart.error!)));
                    }
                  }
                : null,
          ),
        ),
      );
}
