import 'package:flutter/material.dart';
import '../../../constants/card_language_constants.dart';
import '../../../controller/collection_artwork_controller.dart';
import '../atomics/card_language_flag.dart';

class CollectionLanguageButton extends StatelessWidget {
  const CollectionLanguageButton(
      {super.key, required this.controller, required this.onSelected});
  final CollectionArtworkController controller;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => PopupMenuButton<String>(
            tooltip:
                'Lingua immagini: ${cardLanguageLabels[controller.language]}',
            initialValue: controller.language,
            onSelected: onSelected,
            icon: CardLanguageFlag(
                code: controller.language, owned: true, compact: true),
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                  enabled: false, child: Text('Lingua delle immagini')),
              for (final entry in cardLanguageLabels.entries)
                CheckedPopupMenuItem<String>(
                    value: entry.key,
                    checked: entry.key == controller.language,
                    child: Row(children: [
                      CardLanguageFlag(
                          code: entry.key, owned: true, compact: true),
                      const SizedBox(width: 12),
                      Expanded(child: Text(entry.value)),
                    ])),
            ],
          ));
}
