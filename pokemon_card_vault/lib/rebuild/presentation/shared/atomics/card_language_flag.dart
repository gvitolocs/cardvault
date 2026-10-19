import 'package:flutter/material.dart';
import '../../../constants/card_language_constants.dart';
import '../../../style/card_ownership_style.dart';

/// Local font glyph only: never fetches or decodes a flag image.
class CardLanguageFlag extends StatelessWidget {
  const CardLanguageFlag({super.key, this.code, required this.owned});
  final String? code;
  final bool owned;
  @override
  Widget build(BuildContext context) {
    final flag = Text(cardLanguageFlags[code] ?? '🌐',
        style: CardOwnershipStyle.flagText);
    return ExcludeSemantics(
        child: owned
            ? flag
            : ColorFiltered(
                colorFilter: CardOwnershipStyle.grayscale,
                child: Opacity(opacity: .5, child: flag)));
  }
}

/// Identical geometry for provisional evidence and the ready language menu.
class CardLanguageBadge extends StatelessWidget {
  const CardLanguageBadge({super.key, this.code, required this.owned});
  final String? code;
  final bool owned;
  static const _decoration = BoxDecoration(
      color: CardOwnershipStyle.background,
      borderRadius: BorderRadius.all(Radius.circular(14)),
      border: Border.fromBorderSide(BorderSide(color: Colors.white38)));
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 48,
      height: 48,
      child: Center(
          child: DecoratedBox(
              decoration: _decoration,
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  child: CardLanguageFlag(code: code, owned: owned)))));
}
