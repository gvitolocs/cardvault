import 'package:flutter/material.dart';

import '../../../model/marketplace_home.dart';
import 'marketplace_slider.dart';
import '../../shared/atomics/marketplace_thumbnail.dart';

/// Presentazione delle espansioni già selezionate e ordinate dal servizio.
class Espansioni extends StatelessWidget {
  const Espansioni({
    super.key,
    required this.expansions,
    required this.onSelected,
    this.isLoading = false,
    this.hasError = false,
    this.onRetry,
  });

  final List<MarketplaceExpansion> expansions;
  final ValueChanged<MarketplaceExpansion> onSelected;
  final bool isLoading;
  final bool hasError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final width = (MediaQuery.sizeOf(context).width - 60).clamp(180.0, 220.0);
    return MarketplaceSlider(
      title: 'Nuove espansioni',
      storageKey: 'rebuild-expansioni',
      itemCount: expansions.length,
      height: 136 + scale.scale(16) * 2.6 + scale.scale(13) * 1.5,
      emptyText: hasError
          ? 'Le espansioni non sono disponibili al momento.'
          : 'Nessuna espansione disponibile.',
      isLoading: isLoading,
      hasError: hasError,
      onRetry: onRetry,
      itemBuilder: (context, index) {
        final expansion = expansions[index];
        return SizedBox(
          width: width,
          child: Material(
            key: ValueKey(expansion.slug),
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onSelected(expansion),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  MarketplaceThumbnail(
                    imageUrl: expansion.imageUrl,
                    width: width - 24,
                    height: 88,
                  ),
                  const SizedBox(height: 12),
                  Text(expansion.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16,
                          height: 1.3,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${expansion.cardCount} carte',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, height: 1.3)),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
