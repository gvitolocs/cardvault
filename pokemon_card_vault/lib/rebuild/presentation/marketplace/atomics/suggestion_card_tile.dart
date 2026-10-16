import 'package:flutter/material.dart';

import '../../../model/marketplace_home.dart';
import '../../shared/atomics/marketplace_thumbnail.dart';
import 'card_palette_snapshot.dart';

/// A specific catalog version; its identity and image URL come from the API.
class SuggestionCardTile extends StatelessWidget {
  const SuggestionCardTile(
      {super.key,
      required this.card,
      required this.onOpen,
      this.onPaletteOpen});

  final MarketplaceCardPreview card;
  final VoidCallback onOpen;
  final ValueChanged<Color?>? onPaletteOpen;

  @override
  Widget build(BuildContext context) {
    final number = card.number.replaceFirst(RegExp(r'^#\s*'), '');
    return CardPaletteSnapshot(
        enabled: card.imageUrl.isNotEmpty && onPaletteOpen != null,
        thumbnail: MarketplaceThumbnail(
            imageUrl: card.imageUrl, width: 40, height: 56),
        onSelected: (color) {
          final select = onPaletteOpen;
          if (select == null) {
            onOpen();
          } else {
            select(color);
          }
        },
        builder: (context, thumbnail, onTap) => ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: thumbnail,
            title: Text(number.isEmpty ? card.name : '${card.name} $number',
                maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: card.expansion.isEmpty
                ? null
                : Text(card.expansion,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: onTap));
  }
}
