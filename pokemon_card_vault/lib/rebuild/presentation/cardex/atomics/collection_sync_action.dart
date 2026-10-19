import 'package:flutter/material.dart';
import '../../../model/cardex.dart';

/// Stable compact slot instead of a changing block of collection prose.
class CollectionSyncAction extends StatelessWidget {
  const CollectionSyncAction(
      {super.key, required this.collection, required this.onRefresh});
  final CardCollection collection;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 48,
      height: 48,
      child: switch (collection.status) {
        CollectionStatus.loading => Semantics(
            label: 'Aggiornamento della collezione in corso',
            liveRegion: true,
            child: const Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)))),
        CollectionStatus.ready => IconButton(
            tooltip:
                'Aggiorna collezione · ${collection.cards.length} carte · ${collection.copies} copie',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh)),
        _ => const SizedBox.shrink(),
      });
}
