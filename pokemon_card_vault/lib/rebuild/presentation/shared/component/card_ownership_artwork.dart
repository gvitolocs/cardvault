import 'package:flutter/material.dart';
import '../../../model/card_ownership.dart';
import '../../../style/card_ownership_style.dart';
import '../atomics/collection_quantity_badge.dart';
import 'card_language_selector.dart';

class CardOwnershipArtwork extends StatelessWidget {
  const CardOwnershipArtwork(
      {super.key,
      required this.image,
      required this.cardName,
      required this.ownership,
      this.caption,
      this.showControls = true,
      this.onLanguageSelected});
  final Widget image;
  final String cardName;
  final CardOwnership ownership;
  final Widget? caption;
  final bool showControls;
  final ValueChanged<String>? onLanguageSelected;

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        ownership.known && ownership.total == 0
            ? ColorFiltered(
                colorFilter: CardOwnershipStyle.grayscale,
                child: Opacity(opacity: .55, child: image))
            : image,
        if (caption != null)
          Positioned(bottom: 0, left: 0, right: 0, child: caption!),
        if (showControls &&
            caption == null &&
            ownership.known &&
            ownership.total > 0)
          Positioned(
              bottom: 3,
              left: 3,
              right: 3,
              child: Align(
                  alignment: Alignment.bottomRight,
                  child: CollectionQuantityBadge(quantity: ownership.total))),
        if (showControls &&
            (ownership.known || ownership.hasConfirmedCopies) &&
            onLanguageSelected != null)
          Positioned(
              top: 0,
              right: 0,
              child: CardLanguageSelector(
                  ownership: ownership,
                  cardName: cardName,
                  onSelected: onLanguageSelected!)),
      ]);
}
