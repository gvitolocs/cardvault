import 'package:flutter/material.dart';

/// Palette della pagina dettagli ricavata dal fondo stampato della carta.
abstract final class CardDetailsStyle {
  static const fallbackColor = Color(0xFF607D8B);
  static const yellow = Color(0xFFFFD83D);
  static const muted = Color(0xFFCDD5DF);

  static Color colorForTypes(List<String> types) {
    for (final type in types) {
      switch (type.toLowerCase()) {
        case 'fire':
        case 'fuoco':
          return const Color(0xFFF4A267);
        case 'grass':
        case 'erba':
          return const Color(0xFF82B775);
        case 'water':
        case 'acqua':
          return const Color(0xFF72ACCE);
        case 'lightning':
        case 'electric':
        case 'elettro':
          return const Color(0xFFE7C766);
        case 'psychic':
        case 'psico':
          return const Color(0xFFB197C7);
        case 'fighting':
        case 'lotta':
          return const Color(0xFFC99D7D);
        case 'darkness':
        case 'buio':
          return const Color(0xFF74859B);
        case 'metal':
        case 'metallo':
          return const Color(0xFFA3ADB1);
        case 'dragon':
        case 'drago':
          return const Color(0xFFC4AF74);
      }
    }
    return fallbackColor;
  }

  static ThemeData theme(ThemeData base, {Color cardColor = fallbackColor}) {
    final panel = Color.lerp(Colors.black, cardColor, .18)!;
    final field = Color.lerp(Colors.black, cardColor, .11)!;
    final border = Color.lerp(Colors.black, cardColor, .45)!;
    final onPage =
        ThemeData.estimateBrightnessForColor(cardColor) == Brightness.light
            ? const Color(0xFF171A20)
            : Colors.white;
    return base.copyWith(
      scaffoldBackgroundColor: cardColor,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: yellow,
        onPrimary: const Color(0xFF101318),
        primaryContainer: field,
        onPrimaryContainer: yellow,
        secondaryContainer: yellow,
        onSecondaryContainer: const Color(0xFF101318),
        surface: panel,
        onSurface: Colors.white,
        onSurfaceVariant: muted,
        outline: border,
        outlineVariant: border,
        surfaceContainerHighest: Color.lerp(Colors.black, cardColor, .27),
        surfaceContainerHigh: panel,
        surfaceContainer: panel,
        surfaceContainerLow: field,
        surfaceContainerLowest: field,
      ),
      textTheme: base.textTheme
          .apply(bodyColor: Colors.white, displayColor: Colors.white),
      appBarTheme: AppBarTheme(
          backgroundColor: cardColor,
          surfaceTintColor: Colors.transparent,
          iconTheme: const IconThemeData(color: yellow),
          actionsIconTheme: const IconThemeData(color: yellow),
          foregroundColor: onPage),
      chipTheme: base.chipTheme.copyWith(
          backgroundColor: field,
          selectedColor: yellow,
          side: BorderSide(color: border)),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
              backgroundColor: field, foregroundColor: yellow)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        labelStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: border)),
      ),
    );
  }
}
