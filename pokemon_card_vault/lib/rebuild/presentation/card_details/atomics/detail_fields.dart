import 'package:flutter/material.dart';

/// I campi si affiancano soltanto quando hanno spazio per etichette e icone.
class DetailFields extends StatelessWidget {
  const DetailFields({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final horizontal =
            constraints.maxWidth >= children.length * 150 * scale;
        if (horizontal) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: children[i]),
            ],
          ]);
        }
        return Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ]);
      });
}
