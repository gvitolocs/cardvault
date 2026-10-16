import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

/// Contenitore mobile condiviso: costruzione lazy, nessun timer o autoplay.
class MarketplaceSlider extends StatelessWidget {
  const MarketplaceSlider({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    required this.height,
    required this.emptyText,
    required this.storageKey,
    this.isLoading = false,
    this.hasError = false,
    this.onRetry,
  });

  final String title;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height;
  final String emptyText;
  final String storageKey;
  final bool isLoading;
  final bool hasError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: LinearProgressIndicator(),
          )
        else if (hasError || itemCount == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emptyText),
                if (hasError && onRetry != null)
                  TextButton(onPressed: onRetry, child: const Text('Riprova')),
              ],
            ),
          )
        else
          SizedBox(
            height: height,
            child: ListView.separated(
              key: PageStorageKey(storageKey),
              primary: false,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
              itemCount: itemCount,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: itemBuilder,
            ),
          ),
      ],
    );
  }
}
