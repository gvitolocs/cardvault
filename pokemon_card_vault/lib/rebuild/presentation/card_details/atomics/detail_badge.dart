import 'package:flutter/material.dart';
import '../../../style/card_details_style.dart';

class DetailBadge extends StatelessWidget {
  const DetailBadge({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: const TextStyle(
              color: CardDetailsStyle.yellow, fontWeight: FontWeight.w600)));
}
