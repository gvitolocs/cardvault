import 'package:flutter/material.dart';
import '../../../style/card_details_style.dart';
import '../atomics/card_details_panel.dart';

class CardArtworkPanel extends StatelessWidget {
  const CardArtworkPanel({
    super.key,
    required this.number,
    required this.image,
    required this.onVersions,
    this.rarity = '',
    this.demoPrice,
    this.onAddDemo,
  });
  final String number, rarity;
  final Widget image;
  final VoidCallback onVersions;
  final double? demoPrice;
  final VoidCallback? onAddDemo;

  @override
  Widget build(BuildContext context) => CardDetailsPanel(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant)),
              child: Text(number.isEmpty ? 'Carta del catalogo' : number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: CardDetailsStyle.yellow,
                      fontWeight: FontWeight.w700))),
          const SizedBox(height: 16),
          Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 266),
                  child: AspectRatio(aspectRatio: 0.716, child: image))),
          if (rarity.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
              const Icon(Icons.auto_awesome, color: CardDetailsStyle.yellow),
              Text(rarity),
            ]),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed: onVersions, child: const Text('Altre versioni')),
          if (demoPrice != null) ...[
            const SizedBox(height: 12),
            Text(
                'Prezzo di esempio: ${demoPrice!.toStringAsFixed(2).replaceAll('.', ',')} €'),
            const Text('Carta demo · dati di esempio'),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: onAddDemo,
                child: const Text('Aggiungi al carrello demo',
                    textAlign: TextAlign.center)),
          ],
        ]),
      );
}
