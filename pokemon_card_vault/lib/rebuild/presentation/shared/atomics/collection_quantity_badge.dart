import 'package:flutter/material.dart';
import '../../../style/card_ownership_style.dart';

class CollectionQuantityBadge extends StatelessWidget {
  const CollectionQuantityBadge({super.key, required this.quantity});
  final int quantity;

  @override
  Widget build(BuildContext context) => Semantics(
      label: '$quantity copie possedute in totale',
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: CardOwnershipStyle.background,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white38)),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            child: ExcludeSemantics(
                child: Text('×$quantity',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)))),
      ));
}
