import 'package:flutter/material.dart';

import '../../../model/marketplace_discovery_state.dart';
import '../../../model/marketplace_home.dart';
import '../../../controller/cart_controller.dart';
import 'espansioni.dart';
import 'top_sellers.dart';

/// Presenta gli slider; caricamento e retry sono gestiti dal controller.
class MarketplaceDiscovery extends StatelessWidget {
  const MarketplaceDiscovery({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onExpansionSelected,
    required this.onCardSelected,
    this.cart,
    this.onCardPaletteSelected,
  });

  final MarketplaceDiscoveryState state;
  final CartController? cart;
  final VoidCallback onRetry;
  final ValueChanged<MarketplaceExpansion> onExpansionSelected;
  final ValueChanged<MarketplaceCardPreview> onCardSelected;
  final void Function(MarketplaceCardPreview card, Color? color)?
      onCardPaletteSelected;

  @override
  Widget build(BuildContext context) {
    if (state.data == null && !state.isLoading && !state.hasError) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
            onPressed: onRetry,
            child: const Text('Carica espansioni e più vendute')),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.data?.fromCache == true) ...[
          Text(state.data!.refreshFailed
              ? 'Contenuti salvati · aggiornamento non riuscito'
              : state.isLoading
                  ? 'Contenuti salvati · aggiornamento in corso'
                  : 'Contenuti salvati'),
          if (!state.isLoading && state.data!.refreshFailed)
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                    onPressed: onRetry, child: const Text('Riprova'))),
          const SizedBox(height: 12),
        ],
        Espansioni(
          expansions: state.expansions,
          isLoading: state.expansionsLoading,
          hasError: state.expansionsUnavailable,
          onRetry: onRetry,
          onSelected: onExpansionSelected,
        ),
        const SizedBox(height: 28),
        TopSellers(
          cart: cart,
          cards: state.topSellers,
          isLoading: state.topSellersLoading,
          hasError: state.topSellersUnavailable,
          onRetry: onRetry,
          onSelected: onCardSelected,
          onPaletteSelected: onCardPaletteSelected,
        ),
      ],
    );
  }
}
