import 'package:flutter/material.dart';
import '../../../style/app_theme_surfaces.dart';

/// Keeps the content mounted when switching between illustrated and plain themes.
class ThemedPageBackground extends StatelessWidget {
  const ThemedPageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final asset =
        Theme.of(context).extension<AppThemeSurfaces>()?.pageBackground;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: asset == null
                  ? const SizedBox.shrink()
                  : Image.asset(
                      asset,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.none,
                      excludeFromSemantics: true,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
