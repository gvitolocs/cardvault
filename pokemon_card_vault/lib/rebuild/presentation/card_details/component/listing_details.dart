import 'package:flutter/material.dart';
import '../../../controller/card_details_controller.dart';
import '../../../controller/cart_controller.dart';
import '../../../model/card.dart';
import 'listing_origin_group.dart';
import '../atomics/listing_filter.dart';
import '../atomics/listing_filter_button.dart';

/// Sezione Shop mobile: filtri locali e righe costruite solo quando visibili.
/// Inserire tra gli slivers di un CustomScrollView, senza liste shrinkWrap.
class ListingDetails extends StatelessWidget {
  const ListingDetails(
      {super.key,
      required this.state,
      required this.onFilter,
      required this.onRetry,
      required this.cart,
      this.onLoadMore,
      this.onToggleGroup,
      this.previewOnly = false,
      this.card});
  final ListingsState state;
  final void Function({String? condition, String? language, ListingSort? sort})
      onFilter;
  final VoidCallback onRetry;
  final CartController cart;
  final MarketplaceCard? card;
  final bool previewOnly;
  final ValueChanged<String>? onLoadMore, onToggleGroup;

  @override
  Widget build(BuildContext context) {
    final conditions = state.all
        .map((e) => e.condition)
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final languages = state.all
        .map((e) => e.language)
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return SliverMainAxisGroup(slivers: [
      SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Shop',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      if (previewOnly) ...[
                        const Text(
                            'Offerte di esempio · acquisto non disponibile'),
                        const SizedBox(height: 12),
                      ],
                      if (state.loading)
                        const LinearProgressIndicator()
                      else if (state.hasError) ...[
                        const Text(
                            'Le offerte non sono disponibili al momento.'),
                        Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                                onPressed: onRetry,
                                child: const Text('Riprova offerte'))),
                      ] else ...[
                        Text(
                            '${state.visible.length} offerte${state.all.length >= 80 ? ' · prime 80 disponibili' : ''}'),
                        const SizedBox(height: 12),
                        // Il layout resta verticale anche con caratteri ingranditi.
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          ListingFilterButton(
                              label: 'Condizioni',
                              icon: Icons.tune,
                              value: state.condition,
                              choices: {
                                null: 'Qualsiasi condizione',
                                for (final value in conditions) value: value
                              },
                              onChanged: (value) => onFilter(
                                  condition: value, language: state.language)),
                          ListingFilterButton(
                              label: 'Lingua',
                              icon: Icons.language,
                              value: state.language,
                              choices: {
                                null: 'Qualsiasi lingua',
                                for (final value in languages) value: value
                              },
                              onChanged: (value) => onFilter(
                                  condition: state.condition, language: value)),
                        ]),
                        const SizedBox(height: 12),
                        ListingFilter<ListingSort>(
                            label: 'Ordina',
                            value: state.sort,
                            choices: const {
                              ListingSort.lowestPrice: 'Prezzo crescente',
                              ListingSort.highestPrice: 'Prezzo decrescente'
                            },
                            onChanged: (value) => onFilter(
                                condition: state.condition,
                                language: state.language,
                                sort: value)),
                        const SizedBox(height: 12),
                        if (state.all.isEmpty)
                          const Text('Nessuna offerta attiva per questa carta.')
                        else if (state.visible.isEmpty)
                          const Text('Nessuna offerta corrisponde ai filtri.'),
                      ],
                    ])),
          )),
      if (!state.loading && !state.hasError)
        for (final group in state.groups)
          ListingOriginGroup(
              key: ValueKey('listing-group:${group.origin.id}'),
              group: group,
              card: card,
              cart: cart,
              previewOnly: previewOnly,
              onMore: onLoadMore == null
                  ? null
                  : () => onLoadMore!(group.origin.id),
              onToggle: onToggleGroup == null
                  ? null
                  : () => onToggleGroup!(group.origin.id)),
    ]);
  }
}
