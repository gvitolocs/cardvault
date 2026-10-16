import 'package:flutter/material.dart';
import '../../../style/card_details_style.dart';
import '../atomics/card_details_panel.dart';
import '../atomics/detail_badge.dart';

class CardDetailsHeader extends StatelessWidget {
  const CardDetailsHeader({
    super.key,
    required this.name,
    required this.subtitle,
    required this.favorite,
    required this.onFavorite,
    required this.onInfo,
    this.types = const [],
  });
  final String name, subtitle;
  final List<String> types;
  final bool favorite;
  final VoidCallback onFavorite, onInfo;

  @override
  Widget build(BuildContext context) => CardDetailsPanel(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Text(name,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800))),
            IconButton.filledTonal(
                tooltip:
                    favorite ? 'Rimuovi dai preferiti' : 'Salva nei preferiti',
                onPressed: onFavorite,
                icon: Icon(favorite ? Icons.favorite : Icons.favorite_border)),
            IconButton.filledTonal(
                tooltip: 'Informazioni carta',
                onPressed: onInfo,
                icon: const Icon(Icons.info_outline)),
          ]),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(
                  color: CardDetailsStyle.yellow, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final type in types) DetailBadge(label: type),
            const DetailBadge(label: '0,95 € · demo'),
            const DetailBadge(label: '72h +131,7% · demo'),
          ]),
        ]),
      );
}
