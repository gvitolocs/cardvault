import 'package:flutter/material.dart';

/// Presenta le sezioni del prototipo ancora non attive.
class NavigationPlaceholder extends StatelessWidget {
  const NavigationPlaceholder({
    super.key,
    required this.selectedIndex,
    required this.onExploreMarketplace,
  });

  final int selectedIndex;
  final VoidCallback onExploreMarketplace;

  @override
  Widget build(BuildContext context) {
    const titles = [
      'Marketplace',
      'Scansiona',
      'Portfolio',
      'Cardex',
      'Profilo',
      'Wallet'
    ];
    const descriptions = [
      '',
      'Inquadra una carta per riconoscerla e ritrovarla nel marketplace.',
      'Le carte della tua collezione.',
      'Il catalogo delle carte da collezionare.',
      'Qui potrai gestire il tuo account e la tua collezione.',
      'Qui potrai consultare il saldo e le tue attività.',
    ];
    const icons = [
      Icons.storefront_outlined,
      Icons.document_scanner_outlined,
      Icons.collections_bookmark_outlined,
      Icons.menu_book_outlined,
      Icons.person_outline_rounded,
      Icons.account_balance_wallet_outlined,
    ];
    // Collegamenti futuri: LiveCardScanScreen (scanner), wallet/main.dart
    // (wallet) e ProfileScreen + AuthService (account). Nessuna istanza qui.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icons[selectedIndex],
              size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 20),
          Text(titles[selectedIndex],
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(descriptions[selectedIndex], textAlign: TextAlign.center),
          const SizedBox(height: 12),
          const Text('Anteprima · sezione non attiva'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onExploreMarketplace,
            child: const Text('Esplora il marketplace'),
          ),
        ]),
      ),
    );
  }
}
