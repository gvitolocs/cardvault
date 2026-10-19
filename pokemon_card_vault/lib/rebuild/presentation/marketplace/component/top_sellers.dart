import 'package:flutter/material.dart';

import '../../../model/marketplace_home.dart';
import '../atomics/card_palette_snapshot.dart';
import 'marketplace_slider.dart';
import '../../shared/atomics/marketplace_thumbnail.dart';
import '../../shared/component/quick_add_price.dart';
import '../../shared/price_format.dart';
import '../../../controller/cart_controller.dart';

/// Solo presentazione: classifica, richieste e prezzi arrivano dal servizio.
class TopSellers extends StatelessWidget {
  const TopSellers({
    super.key,
    required this.cards,
    required this.onSelected,
    this.cart,
    this.onPaletteSelected,
    this.isLoading = false,
    this.hasError = false,
    this.onRetry,
  });

  final List<MarketplaceCardPreview> cards;
  final CartController? cart;
  final ValueChanged<MarketplaceCardPreview> onSelected;
  final void Function(MarketplaceCardPreview card, Color? color)?
      onPaletteSelected;
  final bool isLoading;
  final bool hasError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final width = (MediaQuery.sizeOf(context).width - 60).clamp(180.0, 220.0);
    return MarketplaceSlider(
      title: 'Articoli più venduti',
      storageKey: 'rebuild-top-sellers',
      itemCount: cards.length,
      height: 196 +
          scale.scale(16) * 2.6 +
          scale.scale(13) * 1.5 +
          (cart == null
              ? scale.scale(16) * 1.5
              : (scale.scale(16) * 3).clamp(48, double.infinity)),
      emptyText: hasError
          ? 'I più venduti non sono disponibili al momento.'
          : 'La classifica dei più venduti non è ancora disponibile.',
      isLoading: isLoading,
      hasError: hasError,
      onRetry: onRetry,
      itemBuilder: (context, index) {
        final card = cards[index];
        return SizedBox(
          width: width,
          child: CardPaletteSnapshot(
              key: ValueKey(card.id),
              enabled: card.imageUrl.isNotEmpty && onPaletteSelected != null,
              thumbnail: MarketplaceThumbnail(
                  imageUrl: card.imageUrl, width: width - 24, height: 144),
              onSelected: (color) {
                final select = onPaletteSelected;
                if (select == null) {
                  onSelected(card);
                } else {
                  select(card, color);
                }
              },
              builder: (context, thumbnail, onTap) => Material(
                    key: ValueKey(card.id),
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
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
                                    fontSize: 16,
                                    height: 1.3,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(card.expansion,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    const TextStyle(fontSize: 13, height: 1.3)),
                            const SizedBox(height: 8),
                            if (cart != null)
                              QuickAddPrice(
                                  maxLines: 2,
                                  cardId: card.id,
                                  cart: cart!,
                                  price: card.pricePkn == null
                                      ? 'Prezzo non disponibile'
                                      : pknPrice(card.pricePkn!))
                            else
                              Text(
                                  card.pricePkn == null
                                      ? 'Prezzo non disponibile'
                                      : '${card.pricePkn!.toStringAsFixed(2).replaceAll('.', ',')} PKN',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 16,
                                      height: 1.3,
                                      fontWeight: FontWeight.w800,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary)),
                          ],
                        ),
                      ),
                    ),
                  )),
        );
      },
    );
  }
}
