import 'package:flutter/material.dart';
import '../../../model/cardex.dart';
import '../../../model/marketplace_home.dart';
import '../../../style/cardex_style.dart';
import '../atomics/album_card.dart';

/// Due colonne come le pagine di un album; costruisce solo le tasche visibili.
class AlbumGrid extends StatelessWidget {
  const AlbumGrid(
      {super.key,
      required this.cards,
      required this.collection,
      required this.onOpen});
  final List<MarketplaceCardPreview> cards;
  final CardCollection collection;
  final ValueChanged<MarketplaceCardPreview> onOpen;

  @override
  Widget build(BuildContext context) =>
      SliverLayoutBuilder(builder: (context, constraints) {
        final columns = constraints.crossAxisExtent >= 700 ? 4 : 2;
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final width =
            (constraints.crossAxisExtent - (columns - 1) * 12) / columns;
        return SliverGrid.builder(
            itemCount: cards.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: (width - 20) * 1.4 + 90 * textScale),
            itemBuilder: (context, index) {
              final card = cards[index];
              return DecoratedBox(
                  decoration: const BoxDecoration(color: CardexStyle.seam),
                  child: AlbumCard(
                      card: card,
                      quantity: collection.quantityFor(card.id),
                      ownershipKnown:
                          collection.status == CollectionStatus.ready,
                      onOpen: () => onOpen(card)));
            });
      });
}
