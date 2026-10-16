import 'package:flutter/material.dart';

/// A phone-width offer: its purchase action never requires sideways scrolling.
class MarketplaceMobileListingLayout extends StatelessWidget {
  const MarketplaceMobileListingLayout({
    super.key,
    required this.seller,
    required this.product,
    required this.price,
    required this.actions,
  });

  final Widget seller;
  final Widget product;
  final Widget price;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: seller),
              const SizedBox(width: 12),
              Expanded(child: price),
            ],
          ),
          const SizedBox(height: 10),
          product,
          const SizedBox(height: 12),
          actions,
        ],
      ),
    );
  }
}

class MarketplaceListingCartButton extends StatelessWidget {
  const MarketplaceListingCartButton({
    super.key,
    required this.inCart,
    required this.onPressed,
  });

  final bool inCart;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(inCart ? Icons.remove_shopping_cart : Icons.add_shopping_cart),
      label: Text(
        inCart ? 'Rimuovi dal carrello' : 'Aggiungi al carrello',
        textAlign: TextAlign.center,
      ),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFFACC15),
        foregroundColor: const Color(0xFF0A1026),
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}
