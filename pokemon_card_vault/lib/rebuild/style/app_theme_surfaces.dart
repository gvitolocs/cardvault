import 'package:flutter/material.dart';

/// Optional local artwork for the main shell, independent of navigation icons.
@immutable
class AppThemeSurfaces extends ThemeExtension<AppThemeSurfaces> {
  const AppThemeSurfaces({this.pageBackground, this.navigationBackground});

  final String? pageBackground;
  final String? navigationBackground;

  @override
  AppThemeSurfaces copyWith({
    String? pageBackground,
    String? navigationBackground,
  }) =>
      AppThemeSurfaces(
        pageBackground: pageBackground ?? this.pageBackground,
        navigationBackground: navigationBackground ?? this.navigationBackground,
      );

  @override
  AppThemeSurfaces lerp(covariant AppThemeSurfaces? other, double t) =>
      other == null || t < .5 ? this : other;
}
