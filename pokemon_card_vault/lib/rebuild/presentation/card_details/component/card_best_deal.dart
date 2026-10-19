import 'package:flutter/material.dart';
import '../../../controller/cart_controller.dart';
import '../../../model/card.dart';
import '../../../model/card_details_state.dart';
import '../../shared/component/listing_cart_price.dart';
import '../atomics/card_details_panel.dart';
import '../atomics/listing_filter.dart';

/// Migliore inserzione effettiva per i filtri scelti; nessun prezzo sintetico.
class CardBestDeal extends StatelessWidget {
  const CardBestDeal(
      {super.key,
      required this.state,
      required this.card,
      required this.cart,
      required this.onFilter,
      required this.onRetry,
      this.previewOnly = false});
  final ListingsState state;
  final MarketplaceCard? card;
  final CartController cart;
  final bool previewOnly;
  final void Function({String? condition, String? language, ListingSort? sort})
      onFilter;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offer = state.bestOffer;
    final conditions = state.all
        .map((offer) => offer.condition)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final languages = state.all
        .map((offer) => offer.language)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return CardDetailsPanel(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Migliore offerta',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        if (previewOnly)
          const Text('Offerte di esempio · acquisto non disponibile'),
        if (state.loading)
          const LinearProgressIndicator()
        else if (state.hasError) ...[
          const Text('Le inserzioni non sono disponibili al momento.'),
          TextButton(onPressed: onRetry, child: const Text('Riprova offerte')),
        ] else ...[
          ListingFilter<String?>(
              label: 'Condizione',
              value: state.condition,
              choices: {
                null: 'Qualsiasi condizione',
                for (final value in conditions) value: value
              },
              onChanged: (value) =>
                  onFilter(condition: value, language: state.language)),
          const SizedBox(height: 12),
          ListingFilter<String?>(
              label: 'Lingua',
              value: state.language,
              choices: {
                null: 'Qualsiasi lingua',
                for (final value in languages) value: value
              },
              onChanged: (value) =>
                  onFilter(condition: state.condition, language: value)),
          const SizedBox(height: 16),
          if (offer == null)
            const Text('Nessuna inserzione disponibile per i filtri scelti.')
          else ...[
            Text(offer.sellerName,
                style: Theme.of(context).textTheme.titleMedium),
            Text(
                '${offer.condition} · ${offer.language} · ${offer.stock} disponibili'),
            const SizedBox(height: 8),
            ListingCartPrice(
                card: card,
                listing: offer,
                cart: cart,
                previewOnly: previewOnly,
                style: Theme.of(context).textTheme.titleLarge),
          ],
        ],
      ],
    ));
  }
}
