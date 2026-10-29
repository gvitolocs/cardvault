import 'package:flutter/material.dart';
import '../app_theme_icons.dart';

/// The existing Rebuild palette, unchanged. Default uses Flutter icons only.
abstract final class DefaultTheme {
  static ThemeData build() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF11121A),
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE9FF72),
            brightness: Brightness.dark,
            primary: const Color(0xFFE9FF72),
            surface: const Color(0xFF1D1F2C)),
        inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF1D1F2C),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none)),
        extensions: const [AppThemeIcons()],
      );
}
