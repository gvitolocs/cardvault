import 'package:flutter/material.dart';
import '../../../style/app_theme_icons.dart';

/// Local-only themed artwork. Tooltips/touch targets remain on the parent.
class ThemedIcon extends StatelessWidget {
  const ThemedIcon({super.key, required this.slot, required this.fallback});
  final AppThemeIcon slot;
  final IconData fallback;
  @override
  Widget build(BuildContext context) {
    final asset = Theme.of(context).extension<AppThemeIcons>()?.assets[slot];
    if (asset == null) return Icon(fallback);
    return Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Image.asset(asset.path,
            width: asset.width,
            height: asset.height,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => Icon(fallback)));
  }
}
