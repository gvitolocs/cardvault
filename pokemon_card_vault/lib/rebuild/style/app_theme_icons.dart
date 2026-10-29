import 'package:flutter/material.dart';

/// Presentation slots, independent of routes, providers and controllers.
enum AppThemeIcon {
  market,
  scanner,
  portfolio,
  cardex,
  profile,
  cart,
  filters,
  search,
  wallet,
  clipboard
}

@immutable
class AppThemeIconAsset {
  const AppThemeIconAsset(this.path, {this.width = 24, this.height = 24});
  final String path;
  final double width, height;
}

@immutable
class AppThemeIcons extends ThemeExtension<AppThemeIcons> {
  const AppThemeIcons({this.assets = const {}});
  final Map<AppThemeIcon, AppThemeIconAsset> assets;
  @override
  AppThemeIcons copyWith({Map<AppThemeIcon, AppThemeIconAsset>? assets}) =>
      AppThemeIcons(
          assets: assets == null ? this.assets : Map.unmodifiable(assets));
  @override
  AppThemeIcons lerp(covariant AppThemeIcons? other, double t) =>
      other == null || t < .5 ? this : other;
}
