import 'package:flutter/material.dart';
import '../../../controller/cart_controller.dart';
import '../../../model/card.dart';
import '../../../model/card_details_state.dart';
import '../../shared/price_format.dart';
import 'listing_row.dart';

/// Gruppo con righe lazy e pagina di quattro offerte gestita dal controller.
class ListingOriginGroup extends StatelessWidget {
  const ListingOriginGroup(
      {super.key,
      required this.group,
      required this.card,
      required this.cart,
      required this.previewOnly,
      this.onMore,
      this.onToggle});
  final ListingGroup group;
  final MarketplaceCard? card;
  final CartController cart;
  final bool previewOnly;
  final VoidCallback? onMore, onToggle;

  @override
  Widget build(BuildContext context) {
    final shown = group.shown;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      sliver: DecoratedSliver(
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant)),
        sliver: SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverMainAxisGroup(slivers: [
            SliverToBoxAdapter(
                child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                child: Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(group.origin.label,
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                            '${group.expanded ? '${shown.length} di ' : ''}${group.offers.length} inserzioni · da ${pknPrice(group.lowestPrice)}'),
                      ])),
                  if (onToggle != null)
                    Icon(
                        group.expanded ? Icons.expand_less : Icons.expand_more),
                ]),
              ),
            )),
            if (group.expanded) ...[
              SliverList(
                  delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ListingRow(
                                key: ValueKey(shown[index].id),
                                listing: shown[index],
                                card: card,
                                cart: cart,
                                previewOnly: previewOnly),
                          ),
                      childCount: shown.length)),
              if (group.hasMore && onMore != null)
                SliverToBoxAdapter(
                    child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onMore,
                    icon: const Icon(Icons.expand_more),
                    label: Text('Mostra altre ${group.nextCount}'),
                  ),
                )),
            ],
          ]),
        ),
      ),
    );
  }
}
