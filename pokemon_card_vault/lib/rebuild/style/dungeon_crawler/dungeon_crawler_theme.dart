import 'package:flutter/material.dart';
import '../app_theme_icons.dart';
import '../app_theme_surfaces.dart';
import '../default/default_theme.dart';

/// Only supplied artwork is enabled. Missing slots retain their Flutter icon.
abstract final class DungeonCrawlerTheme {
  static const icons = AppThemeIcons(assets: {
    AppThemeIcon.cardex:
        AppThemeIconAsset('assets/icons/Cardex.png', width: 26, height: 28),
    AppThemeIcon.portfolio:
        AppThemeIconAsset('assets/icons/Portfolio.png', width: 28, height: 28),
  });
  static const surfaces = AppThemeSurfaces(
    pageBackground: 'assets/images/Dungeon Crawler Themed/Mappa.png',
    navigationBackground:
        'assets/images/Dungeon Crawler Themed/Botttom_bar.png',
  );

  static ThemeData build() => DefaultTheme.build().copyWith(
        extensions: const [icons, surfaces],
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF4D260F),
          foregroundColor: Color(0xFFF0D9B8),
          surfaceTintColor: Colors.transparent,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          indicatorColor: Colors.transparent,
          elevation: 0,
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                color: states.contains(WidgetState.selected)
                    ? const Color(0xFFFFE3A1)
                    : const Color(0xFFF0D9B8),
              )),
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                color: states.contains(WidgetState.selected)
                    ? const Color(0xFFFFE3A1)
                    : const Color(0xFFF0D9B8),
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
                fontSize: 12,
              )),
        ),
      );
}
