import 'package:flutter/material.dart';
import '../../../style/card_ownership_style.dart';

class CollectionQuantityBadge extends StatelessWidget {
  const CollectionQuantityBadge(
      {super.key,
      required this.quantity,
      this.compact = false,
      this.edgeAccent = true});
  final int quantity;
  final bool compact;
  final bool edgeAccent;

  @override
  Widget build(BuildContext context) => Semantics(
      label: '$quantity copie possedute in totale',
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: compact && edgeAccent
                ? CardOwnershipStyle.owned
                : CardOwnershipStyle.background,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: compact && edgeAccent
                    ? CardOwnershipStyle.owned
                    : Colors.white38)),
        child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 6 : 9, vertical: compact ? 2 : 4),
            child: ExcludeSemantics(
                child: Text('×$quantity',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: compact && edgeAccent
                            ? const Color(0xFF111622)
                            : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 11 : 12,
                        height: 1.2)))),
      ));
}
