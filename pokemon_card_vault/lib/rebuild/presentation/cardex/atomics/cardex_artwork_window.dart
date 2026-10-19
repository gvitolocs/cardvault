import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../constants/cardex_artwork_constants.dart';
import '../../../style/cardex_style.dart';

/// Layout-only crop: the existing cached image is painted once, not rewritten.
/// Contains the entire normalized illustration window, never cover-zooms it.
/// Unused pocket space stays neutral; headers/effects remain clipped out.
class CardexArtworkWindow extends StatelessWidget {
  const CardexArtworkWindow({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final scanHeight = math.min(
            constraints.maxWidth /
                (CardexArtworkConstants.width * CardexStyle.cardAspectRatio),
            constraints.maxHeight / CardexArtworkConstants.height);
        final scanWidth = scanHeight * CardexStyle.cardAspectRatio;
        return Stack(clipBehavior: Clip.hardEdge, children: [
          // The full-scan placeholder can sit outside the cropped window.
          // Keep a visible fallback in pocket coordinates, also on HTTP errors.
          const Center(child: Icon(Icons.style_outlined, size: 40)),
          Center(
              child: SizedBox(
                  width: scanWidth * CardexArtworkConstants.width,
                  height: scanHeight * CardexArtworkConstants.height,
                  child: ClipRect(
                      child: Stack(children: [
                    Positioned(
                        left: -scanWidth * CardexArtworkConstants.left,
                        top: -scanHeight * CardexArtworkConstants.top,
                        width: scanWidth,
                        height: scanHeight,
                        child: child),
                  ])))),
        ]);
      });
}
