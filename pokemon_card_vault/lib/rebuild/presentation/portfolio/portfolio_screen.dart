import 'package:flutter/material.dart';
import '../../controller/cardex_controller.dart';
import '../../model/cardex.dart';
import '../../model/marketplace_home.dart';
import '../cardex/component/album_grid.dart';
import '../cardex/component/collection_notice.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen(
      {super.key, required this.controller, required this.onOpen});
  final CardexController controller;
  final ValueChanged<MarketplaceCardPreview> onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final collection = controller.collection;
        return CustomScrollView(
            key: const PageStorageKey('portfolio'),
            slivers: [
              SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverToBoxAdapter(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Portfolio',
                            style: Theme.of(context).textTheme.headlineLarge),
                        const Text('Le carte della tua collezione Pokoin.'),
                        CollectionNotice(
                            status: collection.status,
                            onRetry: controller.retryCollection),
                        if (collection.status == CollectionStatus.loading &&
                            collection.items.isNotEmpty)
                          Text(
                              '${collection.cards.length} carte caricate · sincronizzazione in corso'),
                        if (collection.status == CollectionStatus.ready) ...[
                          TextButton.icon(
                              onPressed: controller.retryCollection,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Aggiorna collezione')),
                          const SizedBox(height: 16),
                          Text(
                              '${collection.cards.length} carte diverse · ${collection.copies} copie'),
                          if (collection.items.isEmpty)
                            const Padding(
                                padding: EdgeInsets.only(top: 20),
                                child:
                                    Text('La tua collezione è ancora vuota.')),
                        ],
                      ]))),
              SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: AlbumGrid(
                      cards: collection.cards,
                      collection: collection,
                      ownershipFor: controller.ownershipFor,
                      onLanguageSelected: controller.selectOwnedLanguage,
                      onOpen: onOpen)),
            ]);
      });
}
