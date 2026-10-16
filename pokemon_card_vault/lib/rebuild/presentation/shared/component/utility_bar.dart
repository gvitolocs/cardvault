import 'package:flutter/material.dart';

/// Barra inferiore del prototipo: presenta la scheda e delega la selezione.
class UtilityBar extends StatelessWidget {
  const UtilityBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: onDestinationSelected,
      destinations: const [
        NavigationDestination(
            icon: Icon(Icons.storefront_outlined), label: 'Market'),
        NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined), label: 'Scansiona'),
        NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            label: 'Portfolio'),
        NavigationDestination(
            icon: Icon(Icons.menu_book_outlined), label: 'Cardex'),
        NavigationDestination(
            icon: Icon(Icons.person_outline_rounded), label: 'Profilo'),
      ],
    );
  }
}
