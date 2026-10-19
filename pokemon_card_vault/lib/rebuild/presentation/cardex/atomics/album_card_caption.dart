import 'package:flutter/material.dart';
import '../../../style/cardex_style.dart';
import '../../shared/atomics/collection_quantity_badge.dart';

/// Thin metadata overlay: the name is already printed on the card itself.
class AlbumCardCaption extends StatelessWidget {
  const AlbumCardCaption(
      {super.key,
      required this.number,
      required this.expansion,
      this.belowArtwork = false,
      this.quantity = 0,
      this.status});
  final String number, expansion;
  final int quantity;
  final bool belowArtwork;
  final String? status;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, constraints) => DecoratedBox(
          decoration: belowArtwork
              ? const BoxDecoration(color: CardexStyle.sleeve)
              : const BoxDecoration(gradient: CardexStyle.captionGradient),
          child: Padding(
              padding: EdgeInsets.fromLTRB(5, belowArtwork ? 3 : 16, 5, 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          [number, expansion]
                              .where((part) => part.isNotEmpty)
                              .join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                      if (status != null)
                        Text(status!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 10)),
                    ])),
                if (quantity > 0) ...[
                  const SizedBox(width: 4),
                  ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth * .45),
                      child: CollectionQuantityBadge(quantity: quantity)),
                ],
              ]))));
}
