import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class PokoinLogo extends StatelessWidget {
  final double size;

  const PokoinLogo({super.key, this.size = 42});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'web/pokoin.svg',
      width: size,
      height: size,
      semanticsLabel: 'Pokoin logo',
    );
  }
}
