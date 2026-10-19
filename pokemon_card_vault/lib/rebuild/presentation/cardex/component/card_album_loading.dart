import 'package:flutter/material.dart';
import '../../../style/cardex_style.dart';
import '../../../constants/cardex_artwork_constants.dart';
import '../../../constants/cardex_album_layout_constants.dart';

class CardAlbumLoading extends StatelessWidget {
  const CardAlbumLoading({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Caricamento delle prime carte della tua collezione',
      child: Row(children: [
        for (var index = 0; index < 2; index++) ...[
          if (index > 0)
            const SizedBox(width: CardexAlbumLayoutConstants.columnGap),
          Expanded(
              child: AspectRatio(
                  aspectRatio: CardexArtworkConstants.pocketAspectRatio,
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: CardexStyle.sleeve,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12))))),
        ],
      ]));
}
