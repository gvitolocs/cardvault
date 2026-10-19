import 'package:flutter/material.dart';
import '../../../controller/cart_controller.dart';
import '../../../model/cart_add_result.dart';
import '../atomics/cart_price.dart';
import '../price_format.dart';

/// Osserva solo l'azione della carta interessata. Nessuna richiesta al build:
/// il controller verifica le inserzioni soltanto al tap.
class QuickAddPrice extends StatelessWidget {
  const QuickAddPrice(
      {super.key,
      required this.cardId,
      required this.price,
      required this.cart,
      this.style,
      this.maxLines});
  final String cardId, price;
  final CartController cart;
  final TextStyle? style;
  final int? maxLines;

  Future<void> _add(BuildContext context) async {
    final result = await cart.addCheapestOffer(cardId);
    if (!context.mounted || result.status == CartAddStatus.sessionChanged) {
      return;
    }
    final message = switch (result.status) {
      CartAddStatus.added =>
        'Aggiunta al carrello · ${result.listing!.sellerName} · ${result.listing!.condition} ${result.listing!.language} · ${pknPrice(result.listing!.pricePkn)}',
      CartAddStatus.unavailable =>
        'Nessuna inserzione disponibile per questa carta.',
      CartAddStatus.full =>
        'Quantità disponibile raggiunta o carrello pieno. Puoi scegliere un’altra inserzione nei dettagli.',
      CartAddStatus.notReady =>
        'Attendi il recupero del carrello oppure riprova dal pannello del carrello.',
      _ => 'Impossibile recuperare le inserzioni. Riprova.',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: cart.editable,
        builder: (context, editable, _) => ValueListenableBuilder<bool>(
          valueListenable: cart.adding(cardId),
          builder: (context, busy, _) => CartPrice(
            price: price,
            style: style,
            maxLines: maxLines,
            busy: busy,
            tooltip: 'Aggiungi al carrello · offerta più economica',
            onAdd: editable ? () => _add(context) : null,
          ),
        ),
      );
}
