import 'package:flutter/material.dart';
import '../../../model/cardex.dart';
import '../../../model/card_ownership.dart';
import '../../../model/marketplace_home.dart';
import '../../../style/cardex_style.dart';
import '../atomics/album_card.dart';

/// Due colonne come le pagine di un album; costruisce solo le tasche visibili.
class AlbumGrid extends StatelessWidget {
  const AlbumGrid(
      {super.key,
      required this.cards,
      required this.collection,
      this.ownershipFor,
      this.onLanguageSelected,
      required this.onOpen});
  final List<MarketplaceCardPreview> cards;
  final CardCollection collection;
  final CardOwnership Function(String)? ownershipFor;
  final void Function(String, String)? onLanguageSelected;
  final ValueChanged<MarketplaceCardPreview> onOpen;

  @override
  Widget build(BuildContext context) =>
      SliverLayoutBuilder(builder: (context, constraints) {
        final columns = constraints.crossAxisExtent >= 700 ? 4 : 2;
        final width =
            (constraints.crossAxisExtent - (columns - 1) * 12) / columns;
        return SliverGrid.builder(
            itemCount: cards.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: (width - 4) / CardexStyle.cardAspectRatio + 4),
            itemBuilder: (context, index) {
              final card = cards[index];
              return DecoratedBox(
                  decoration: const BoxDecoration(color: CardexStyle.seam),
                  child: AlbumCard(
                      card: card,
                      quantity: collection.quantityFor(card.id),
                      ownership: ownershipFor?.call(card.id),
                      onLanguageSelected: onLanguageSelected == null
                          ? null
                          : (language) =>
                              onLanguageSelected!(card.id, language),
                      ownershipKnown:
                          collection.status == CollectionStatus.ready,
                      onOpen: () => onOpen(card)));
            });
      });
}
