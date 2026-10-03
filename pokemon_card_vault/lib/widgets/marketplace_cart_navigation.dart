import 'package:flutter/material.dart';

class MarketplaceUtilityBar extends StatelessWidget {
  const MarketplaceUtilityBar({
    super.key,
    required this.onSearch,
    required this.onScanner,
    required this.onListings,
    required this.onProfile,
    this.selectedIndex = 0,
  });

  final VoidCallback onSearch;
  final VoidCallback onScanner;
  final VoidCallback onListings;
  final VoidCallback onProfile;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF252C46))),
      ),
      child: NavigationBarTheme(
        data: const NavigationBarThemeData(
          labelTextStyle: WidgetStatePropertyAll(TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          iconTheme:
              WidgetStatePropertyAll(IconThemeData(color: Color(0xFFC4B5FD))),
        ),
        child: NavigationBar(
          height: 72,
          backgroundColor: const Color(0xFF0A1026),
          indicatorColor: const Color(0xFF302256),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) =>
              [onSearch, onScanner, onListings, onProfile][index](),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.search), label: 'Ricerca'),
            NavigationDestination(
                icon: Icon(Icons.document_scanner_outlined), label: 'Scanner'),
            NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined), label: 'Elenco'),
            NavigationDestination(
                icon: Icon(Icons.person_outline), label: 'Profilo'),
          ],
        ),
      ),
    );
  }
}
