import 'package:flutter/material.dart';
import '../../../model/card_ownership.dart';
import '../../../style/card_ownership_style.dart';
import '../atomics/card_language_flag.dart';

/// A corner flag, not a permanent rail. Grey options cannot change the selection.
class CardLanguageSelector extends StatelessWidget {
  const CardLanguageSelector(
      {super.key,
      required this.ownership,
      required this.cardName,
      this.compact = false,
      this.edgeAccent = true,
      required this.onSelected});
  final CardOwnership ownership;
  final String cardName;
  final bool compact;
  final bool edgeAccent;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = ownership.selected;
    final badge = CardLanguageBadge(
        code: ownership.displayLanguage,
        owned: ownership.hasConfirmedCopies,
        compact: compact,
        edgeAccent: edgeAccent);
    if (!ownership.known) {
      return Semantics(
          label:
              '${ownership.evidence?.label ?? "Lingua"} confermata; quantità e altre lingue in verifica',
          child: GestureDetector(
              excludeFromSemantics: true,
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: badge));
    }
    return PopupMenuButton<String>(
      tooltip: 'Lingue possedute di $cardName',
      enabled: ownership.known,
      onSelected: onSelected,
      initialValue: ownership.selectedLanguage,
      constraints:
          const BoxConstraints(minWidth: 250, maxWidth: 310, maxHeight: 420),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
            enabled: false,
            child: Text('Lingue · ${ownership.total} copie totali',
                style: Theme.of(context).textTheme.titleSmall)),
        for (final language in ownership.languages)
          PopupMenuItem<String>(
              value: language.code,
              enabled: language.owned,
              child: Semantics(
                  label: '${language.label}, ${language.quantity} copie'
                      '${language.owned ? "" : ", non posseduta"}',
                  child: Row(children: [
                    CardLanguageFlag(
                        code: language.code, owned: language.owned),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(language.label,
                            style: TextStyle(
                                color: language.owned
                                    ? null
                                    : CardOwnershipStyle.missing))),
                    Flexible(
                        child: Text('×${language.quantity}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: language.owned
                                    ? CardOwnershipStyle.owned
                                    : CardOwnershipStyle.missing))),
                    if (language.code == ownership.selectedLanguage) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.check,
                          size: 16, color: CardOwnershipStyle.owned),
                    ],
                  ]))),
        const PopupMenuItem<String>(
            enabled: false,
            child: Text(
                'Grigio: nessuna copia posseduta. Non indica le lingue di stampa disponibili.',
                style: TextStyle(fontSize: 11))),
      ],
      child: Semantics(
          label: selected == null
              ? 'Lingue: nessuna copia posseduta'
              : '${selected.label}, ${selected.quantity} copie possedute',
          button: true,
          child: badge),
    );
  }
}
