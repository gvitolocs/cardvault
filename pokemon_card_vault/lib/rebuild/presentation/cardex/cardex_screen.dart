import 'package:flutter/material.dart';
import '../../controller/cardex_controller.dart';
import '../../model/cardex.dart';
import '../../model/marketplace_home.dart';
import 'component/card_album.dart';
import 'component/collection_notice.dart';

class CardexScreen extends StatelessWidget {
  const CardexScreen(
      {super.key, required this.controller, required this.onOpen});
  final CardexController controller;
  final ValueChanged<MarketplaceCardPreview> onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final visible = controller.visibleCards;
        return CustomScrollView(key: const PageStorageKey('cardex'), slivers: [
          SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              sliver: SliverToBoxAdapter(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Cardex',
                        style: Theme.of(context).textTheme.headlineLarge),
                    const Text('Il tuo album, una carta alla volta.'),
                    CollectionNotice(
                        status: controller.collection.status,
                        onRetry: controller.retryCollection),
                    if (controller.ownershipKnown)
                      TextButton.icon(
                          onPressed: controller.retryCollection,
                          icon: const Icon(Icons.refresh),
                          label: Text(
                              'Aggiorna collezione · ${controller.collection.cards.length} carte · ${controller.collection.copies} copie')),
                    if (controller.loadingExpansions)
                      const LinearProgressIndicator(),
                    if (controller.expansionsError)
                      TextButton(
                          onPressed: controller.loadExpansions,
                          child: const Text('Riprova espansioni')),
                    if (!controller.loadingExpansions &&
                        !controller.expansionsError &&
                        controller.expansions.isEmpty)
                      const Text('Nessuna espansione disponibile.'),
                    if (controller.expansions.isNotEmpty ||
                        controller.ownershipKnown)
                      DropdownButton<String>(
                          isExpanded: true,
                          value: controller.viewingCollection
                              ? '__collection__'
                              : controller.expansion?.slug,
                          hint: const Text('Scegli un’espansione'),
                          items: [
                            if (controller.ownershipKnown)
                              const DropdownMenuItem(
                                  value: '__collection__',
                                  child: Text(
                                      'Le mie carte · tutte le espansioni',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                            ...controller.expansions.map((expansion) =>
                                DropdownMenuItem(
                                    value: expansion.slug,
                                    child: Text(expansion.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)))
                          ],
                          onChanged: (slug) {
                            if (slug == '__collection__') {
                              controller.showCollection();
                            } else if (slug != null) {
                              controller.selectExpansion(controller.expansions
                                  .firstWhere((item) => item.slug == slug));
                            }
                          }),
                    if (!controller.viewingCollection &&
                        controller.expansion != null) ...[
                      Text(
                          '${controller.total} carte nel catalogo · ${controller.cards.length} caricate'),
                      if (controller.ownershipKnown)
                        Text(
                            '${controller.cards.where((card) => controller.collection.owns(card.id)).length} possedute tra le carte caricate'),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, children: [
                        for (final filter in CardexFilter.values)
                          ChoiceChip(
                              label: Text(switch (filter) {
                                CardexFilter.all => 'Tutte',
                                CardexFilter.owned => 'Possedute',
                                CardexFilter.missing => 'Mancanti'
                              }),
                              selected: controller.filter == filter,
                              onSelected: controller.ownershipKnown
                                  ? (_) => controller.setFilter(filter)
                                  : null),
                      ]),
                    ],
                    if (controller.viewingCollection)
                      const Text(
                          'Le tue carte a colori. Scegli un’espansione per vedere anche le mancanti.'),
                  ]))),
          SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                  child: CardAlbum(
                      key: ValueKey(
                          '${controller.viewingCollection ? "collection" : controller.expansion?.slug}-${controller.filter.name}'),
                      cards: visible,
                      collection: controller.collection,
                      onOpen: onOpen))),
          SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverToBoxAdapter(
                  child: Column(children: [
                if (!controller.viewingCollection && controller.loadingPage)
                  const CircularProgressIndicator(),
                if (controller.viewingCollection && visible.isEmpty)
                  const Text('La tua collezione è ancora vuota.'),
                if (!controller.viewingCollection &&
                    !controller.loadingPage &&
                    !controller.pageError &&
                    controller.expansion != null &&
                    visible.isEmpty)
                  Text(controller.hasMore
                      ? 'Nessuna carta per questo filtro nelle pagine caricate.'
                      : 'Nessuna carta per questo filtro.'),
                if (!controller.viewingCollection && controller.pageError)
                  const Text('Impossibile caricare le carte dell’album.'),
                if (!controller.viewingCollection &&
                    !controller.loadingPage &&
                    controller.hasMore)
                  OutlinedButton(
                      onPressed: controller.loadMore,
                      child: Text(controller.pageError
                          ? 'Riprova carte'
                          : 'Carica altre carte')),
              ]))),
        ]);
      });
}
