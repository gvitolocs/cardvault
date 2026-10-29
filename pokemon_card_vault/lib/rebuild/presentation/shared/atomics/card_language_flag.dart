import 'package:flutter/material.dart';
import '../../../constants/card_language_constants.dart';
import '../../../style/card_ownership_style.dart';

/// Local font glyph only: never fetches or decodes a flag image.
class CardLanguageFlag extends StatelessWidget {
  const CardLanguageFlag(
      {super.key, this.code, required this.owned, this.compact = false});
  final String? code;
  final bool owned;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final flag = Text(cardLanguageFlags[code] ?? '🌐',
        textScaler: compact ? TextScaler.noScaling : null,
        style: compact
            ? CardOwnershipStyle.flagText.copyWith(fontSize: 16, height: 1)
            : CardOwnershipStyle.flagText);
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
  const CardLanguageBadge(
      {super.key,
      this.code,
      required this.owned,
      this.compact = false,
      this.edgeAccent = true});
  final String? code;
  final bool owned;
  final bool compact;
  final bool edgeAccent;
  static const _decoration = BoxDecoration(
      color: CardOwnershipStyle.background,
      borderRadius: BorderRadius.all(Radius.circular(14)),
      border: Border.fromBorderSide(BorderSide(color: Colors.white38)));
  static const _ownedEdge = BoxDecoration(
      color: CardOwnershipStyle.owned,
      borderRadius: BorderRadius.all(Radius.circular(14)),
      border:
          Border.fromBorderSide(BorderSide(color: CardOwnershipStyle.owned)));
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 48,
      height: 48,
      // Keep the transparent part of the 48px target hit-testable too.
      child: ColoredBox(
          color: Colors.transparent,
          child: Align(
              alignment: compact ? Alignment.topRight : Alignment.center,
              child: DecoratedBox(
                  decoration:
                      compact && owned && edgeAccent ? _ownedEdge : _decoration,
                  child: Padding(
                      padding: compact
                          ? const EdgeInsets.all(3)
                          : const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 3),
                      child: CardLanguageFlag(
                          code: code, owned: owned, compact: compact))))));
}
