import 'package:flutter/material.dart';

class CardDetailsPanel extends StatelessWidget {
  const CardDetailsPanel({super.key, required this.child, this.color});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          color: color ?? Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18)),
      foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(16), child: child));
}
