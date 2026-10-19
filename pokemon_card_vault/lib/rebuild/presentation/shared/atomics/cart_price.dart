import 'package:flutter/material.dart';

/// Azione alla sinistra del prezzo, con testo adattabile su telefoni piccoli.
class CartPrice extends StatelessWidget {
  const CartPrice(
      {super.key,
      required this.price,
      required this.onAdd,
      this.tooltip = 'Aggiungi al carrello',
      this.busy = false,
      this.style,
      this.maxLines});
  final String price, tooltip;
  final VoidCallback? onAdd;
  final bool busy;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Row(children: [
        IconButton.filledTonal(
          tooltip: tooltip,
          onPressed: busy ? null : onAdd,
          icon: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_shopping_cart_outlined),
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Text(price,
                maxLines: maxLines,
                overflow: maxLines == null ? null : TextOverflow.ellipsis,
                style: style ??
                    TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700))),
      ]);
}
