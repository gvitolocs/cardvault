import 'package:flutter/material.dart';

import '../../../model/card.dart';
import '../../shared/atomics/card_illustration.dart';

String _price(double value) =>
    '${value.toStringAsFixed(2).replaceAll('.', ',')} €';

/// Presenta una carta e delega le azioni ai callback della schermata.
class CardTile extends StatelessWidget {
  const CardTile({
    super.key,
    required this.card,
    required this.favorite,
    required this.onFavorite,
    required this.onOpen,
    required this.onAdd,
  });

  final DemoCard card;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              CardIllustration(card: card),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton.filledTonal(
                  tooltip: favorite
                      ? 'Rimuovi dai preferiti'
                      : 'Salva nei preferiti',
                  onPressed: onFavorite,
                  icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Text(card.name,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text('${card.expansion} · ${card.number}',
                style: const TextStyle(color: Color(0xFFA8AABB), fontSize: 12)),
            const SizedBox(height: 12),
            Text(_price(card.price),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                  onPressed: onAdd, child: const Text('Aggiungi')),
            ),
          ]),
        ),
      ),
    );
  }
}
