import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../model/card_ownership.dart';
import '../atomics/collection_quantity_badge.dart';
import 'card_language_selector.dart';

/// Collection controls straddle the outline; a matching inner header inset
/// keeps their paint above the image, not over names or rules text.
/// The compact flag still has a 48px target within the pocket's hit bounds.
class CardOwnershipEdgeControls extends StatelessWidget {
  const CardOwnershipEdgeControls({
    super.key,
    required this.ownership,
    required this.cardName,
    required this.child,
    this.outsideFrame = false,
    this.onLanguageSelected,
  });
  final CardOwnership ownership;
  final String cardName;
  final Widget child;

  /// Cardex has no inner header; controls touch the border from outside.
  final bool outsideFrame;
  final ValueChanged<String>? onLanguageSelected;

  static double railHeight(BuildContext context) =>
      math.max(24, MediaQuery.textScalerOf(context).scale(11) * 1.2 + 8);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, constraints) => Stack(children: [
            Positioned.fill(
                top: outsideFrame
                    ? railHeight(context)
                    : railHeight(context) / 2,
                child: child),
            if (ownership.known && ownership.total > 0)
              Positioned(
                  top: outsideFrame
                      ? railHeight(context) -
                          (MediaQuery.textScalerOf(context).scale(11) * 1.2 + 6)
                      : 2,
                  right: 48,
                  child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: math.max(1, constraints.maxWidth - 52)),
                      child: CollectionQuantityBadge(
                          quantity: ownership.total, compact: true))),
            if ((ownership.known || ownership.hasConfirmedCopies) &&
                onLanguageSelected != null)
              Positioned(
                  top: outsideFrame
                      ? railHeight(context) - 24
                      : railHeight(context) / 2 - 12,
                  right: 0,
                  child: CardLanguageSelector(
                      ownership: ownership,
                      cardName: cardName,
                      compact: true,
                      onSelected: onLanguageSelected!)),
          ]));
}
