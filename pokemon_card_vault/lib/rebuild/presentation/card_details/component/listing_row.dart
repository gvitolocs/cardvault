import 'package:flutter/material.dart';
import '../../../controller/cart_controller.dart';
import '../../../model/card.dart';
import '../../../model/listing.dart';
import '../../shared/component/listing_cart_price.dart';

class ListingRow extends StatelessWidget {
  const ListingRow(
      {super.key,
      required this.listing,
      required this.card,
      required this.previewOnly,
      required this.cart});
  final MarketplaceListing listing;
  final MarketplaceCard? card;
  final CartController cart;
  final bool previewOnly;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant)),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(listing.sellerName,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (listing.country.isNotEmpty)
                      _tag(context, 'Paese ${listing.country}'),
                    if (listing.condition.isNotEmpty)
                      _tag(context, listing.condition),
                    if (listing.language.isNotEmpty)
                      _tag(context, 'Lingua ${listing.language}'),
                    for (final attribute in listing.attributes)
                      _tag(context, attribute),
                  ]),
                  const SizedBox(height: 12),
                  ListingCartPrice(
                      card: card,
                      listing: listing,
                      cart: cart,
                      previewOnly: previewOnly,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700)),
                  Text('${listing.stock} disponibili'),
                  if (listing.comment.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(listing.comment)),
                  const SizedBox(height: 12),
                  // Solo i controlli dell'offerta modificata osservano la sua quantità.
                  if (previewOnly)
                    const OutlinedButton(
                        onPressed: null, child: Text('Offerta dimostrativa'))
                  else
                    ValueListenableBuilder<bool>(
                        valueListenable: cart.editable,
                        builder: (context, canEdit, _) =>
                            ValueListenableBuilder<int>(
                                valueListenable: cart.quantityFor(listing.id),
                                builder: (context, quantity, _) => Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (quantity > 0) ...[
                                            Row(children: [
                                              IconButton(
                                                  tooltip:
                                                      'Diminuisci quantità',
                                                  onPressed: canEdit
                                                      ? () =>
                                                          cart.decreaseListing(
                                                              listing.id)
                                                      : null,
                                                  icon:
                                                      const Icon(Icons.remove)),
                                              Expanded(
                                                  child: Text(
                                                      '$quantity nel carrello',
                                                      textAlign:
                                                          TextAlign.center)),
                                              IconButton(
                                                  tooltip: 'Aumenta quantità',
                                                  onPressed: !canEdit ||
                                                          quantity >=
                                                              listing.stock ||
                                                          card == null
                                                      ? null
                                                      : () => cart.addListing(
                                                          card!, listing),
                                                  icon: const Icon(Icons.add)),
                                            ]),
                                            OutlinedButton.icon(
                                                onPressed: canEdit
                                                    ? () => cart.removeListing(
                                                        listing.id)
                                                    : null,
                                                icon: const Icon(Icons
                                                    .remove_shopping_cart_outlined),
                                                label: const Text(
                                                    'Rimuovi dal carrello')),
                                          ],
                                        ]))),
                ])),
      );

  Widget _tag(BuildContext context, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8)),
      child: Text(text));
}
