import 'package:flutter/material.dart';
import '../../../model/marketplace_home.dart';
import '../../../style/cardex_style.dart';
import '../../shared/atomics/marketplace_thumbnail.dart';

/// Tasca dell'album: stato sconosciuto distinto da carta mancante.
class AlbumCard extends StatelessWidget {
  const AlbumCard(
      {super.key,
      required this.card,
      required this.quantity,
      required this.ownershipKnown,
      required this.onOpen});
  final MarketplaceCardPreview card;
  final int quantity;
  final bool ownershipKnown;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final owned = quantity > 0;
    final status = !ownershipKnown
        ? 'Catalogo'
        : owned
            ? 'Posseduta · ×$quantity'
            : 'Mancante';
    return Semantics(
      label: '${card.name}, ${card.number}, $status',
      button: true,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: CardexStyle.sleeve,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: ownershipKnown && owned
                      ? CardexStyle.accent
                      : Colors.white12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: LayoutBuilder(builder: (context, constraints) {
              final image = MarketplaceThumbnail(
                  imageUrl:
                      card.imageUrl.isEmpty ? card.fullImageUrl : card.imageUrl,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight);
              return ownershipKnown && !owned
                  ? ColorFiltered(
                      colorFilter: CardexStyle.grayscale,
                      child: Opacity(opacity: .55, child: image))
                  : image;
            })),
            const SizedBox(height: 8),
            Text(card.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(card.number,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(status,
                maxLines: 2,
                style: TextStyle(
                    fontSize: 11,
                    color: ownershipKnown && owned
                        ? CardexStyle.accent
                        : Colors.white70)),
          ]),
        ),
      ),
    );
  }
}
