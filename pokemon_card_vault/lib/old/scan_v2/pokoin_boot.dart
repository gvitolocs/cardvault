import 'package:flutter/material.dart';

/// Full-screen Pokoin mark on open. Scale/fade is 500 ms; the parent
/// must hide this after [duration] even if the scan engine is still compiling.
class PokoinBootOverlay extends StatefulWidget {
  const PokoinBootOverlay({super.key});

  static const duration = Duration(milliseconds: 500);
  static const background = Color(0xFF050816);

  @override
  State<PokoinBootOverlay> createState() => _PokoinBootOverlayState();
}

class _PokoinBootOverlayState extends State<PokoinBootOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: PokoinBootOverlay.duration,
    )..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.82, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PokoinBootOverlay.background,
      child: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Image.asset(
              'assets/pokoin-icon-opaque.png',
              width: 128,
              height: 128,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}
