import 'package:flutter/material.dart';

import '../../../model/marketplace_home.dart';
import 'card_palette_snapshot.dart';
import '../../shared/atomics/marketplace_thumbnail.dart';
import '../../shared/price_format.dart';
import '../../../controller/cart_controller.dart';
import '../../shared/component/quick_add_price.dart';

class SearchCardTile extends StatelessWidget {
  const SearchCardTile(
      {super.key,
      required this.card,
      required this.onOpen,
      this.cart,
      this.onPaletteOpen});
  final MarketplaceCardPreview card;
  final VoidCallback onOpen;
  final CartController? cart;
  final ValueChanged<Color?>? onPaletteOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => CardPaletteSnapshot(
          enabled: card.imageUrl.isNotEmpty && onPaletteOpen != null,
          thumbnail: MarketplaceThumbnail(
              imageUrl: card.imageUrl,
              width: constraints.maxWidth - 24,
              height: 172),
          onSelected: (color) {
            final select = onPaletteOpen;
            if (select == null) {
              onOpen();
            } else {
              select(color);
            }
          },
          builder: (context, thumbnail, onTap) => Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      thumbnail,
                      const SizedBox(height: 12),
                      Text(card.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(card.expansion,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (card.number.isNotEmpty) Text(card.number),
                      const SizedBox(height: 8),
                      if (cart != null)
                        QuickAddPrice(
                            cardId: card.id,
                            cart: cart!,
                            price: card.pricePkn == null
                                ? 'Prezzo non disponibile'
                                : pknPrice(card.pricePkn!))
                      else
                        Text(
                            card.pricePkn == null
                                ? 'Prezzo non disponibile'
                                : pknPrice(card.pricePkn!),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700)),
                    ],
                  ),
                )),
          ),
        ),
      );
}
