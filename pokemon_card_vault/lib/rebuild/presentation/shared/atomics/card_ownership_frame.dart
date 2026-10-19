import 'package:flutter/material.dart';
import '../../../style/card_ownership_style.dart';

/// Reusable, synchronous UI asset: no raster/SVG loading or image decoding.
/// Ownership must come from confirmed account evidence, never a catalog guess.
class CardOwnershipFrame extends StatelessWidget {
  const CardOwnershipFrame(
      {super.key, required this.owned, required this.child});
  final bool owned;
  final Widget child;
  static const radius = BorderRadius.all(Radius.circular(12));
  static const _owned = BoxDecoration(
      color: CardOwnershipStyle.sleeve,
      borderRadius: radius,
      border:
          Border.fromBorderSide(BorderSide(color: CardOwnershipStyle.owned)));
  static const _neutral = BoxDecoration(
      color: CardOwnershipStyle.sleeve,
      borderRadius: radius,
      border: Border.fromBorderSide(BorderSide(color: Colors.white12)));

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(2),
      clipBehavior: Clip.antiAlias,
      decoration: owned ? _owned : _neutral,
      child: child);
}
