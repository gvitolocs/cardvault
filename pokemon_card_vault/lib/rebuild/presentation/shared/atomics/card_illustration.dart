import 'package:flutter/material.dart';
import '../../../model/card.dart';

class CardIllustration extends StatelessWidget {
  const CardIllustration({super.key, required this.card});
  final DemoCard card;

  @override
  Widget build(BuildContext context) {
    // Collegamento futuro: immagini CDN del catalogo e cache immagini.
    // Il disegno astratto è un segnaposto locale, non una foto della carta.
    return AspectRatio(
      aspectRatio: 0.78,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: card.color, width: 3),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [card.color, const Color(0xFF2C2444)],
          ),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(card.icon, size: 64, color: Colors.white),
          const SizedBox(height: 12),
          const Text('POKOIN DEMO',
              style: TextStyle(fontSize: 11, letterSpacing: 2)),
        ]),
      ),
    );
  }
}
