import 'package:flutter/material.dart';
import '../atomics/themed_icon.dart';
import '../../../style/app_theme_icons.dart';
import '../../../style/app_theme_surfaces.dart';

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
    final background =
        Theme.of(context).extension<AppThemeSurfaces>()?.navigationBackground;
    final navigation = NavigationBar(
      selectedIndex: selectedIndex,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: onDestinationSelected,
      destinations: const [
        NavigationDestination(
            icon: ThemedIcon(
                slot: AppThemeIcon.market, fallback: Icons.storefront_outlined),
            label: 'Market'),
        NavigationDestination(
            icon: ThemedIcon(
                slot: AppThemeIcon.scanner,
                fallback: Icons.document_scanner_outlined),
            label: 'Scansiona'),
        NavigationDestination(
            icon: ThemedIcon(
                slot: AppThemeIcon.portfolio,
                fallback: Icons.collections_bookmark_outlined),
            label: 'Portfolio'),
        NavigationDestination(
            icon: ThemedIcon(
                slot: AppThemeIcon.cardex, fallback: Icons.menu_book_outlined),
            label: 'Cardex'),
        NavigationDestination(
            icon: ThemedIcon(
                slot: AppThemeIcon.profile,
                fallback: Icons.person_outline_rounded),
            label: 'Profilo'),
      ],
    );
    if (background == null) return navigation;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              color: Theme.of(context).appBarTheme.backgroundColor ??
                  Theme.of(context).colorScheme.surface,
              child: Image.asset(
                background,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
                excludeFromSemantics: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        navigation,
      ],
    );
  }
}
