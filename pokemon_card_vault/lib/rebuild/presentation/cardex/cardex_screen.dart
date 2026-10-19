import 'package:flutter/material.dart';
import '../../controller/cardex_controller.dart';
import '../../constants/cardex_album_layout_constants.dart';
import '../../model/cardex.dart';
import '../../model/marketplace_home.dart';
import 'component/card_album.dart';
import 'component/collection_notice.dart';
import 'component/card_album_loading.dart';
import 'atomics/collection_sync_action.dart';

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
                    Row(children: [
                      if (!controller.viewingCollection)
                        Expanded(
                            child: Text(
                                controller.expansion?.name ??
                                    'Scegli un’espansione',
                                style: Theme.of(context).textTheme.titleLarge))
                      else
                        const Spacer(),
                      CollectionSyncAction(
                          collection: controller.collection,
                          onRefresh: controller.retryCollection),
                    ]),
                    if (controller.collection.status !=
                        CollectionStatus.loading)
                      CollectionNotice(
                          status: controller.collection.status,
                          onRetry: controller.retryCollection),
                    if (!controller.viewingCollection &&
                        controller.expansion == null)
                      const Text(
                          'Apri Espansioni in alto, a destra del carrello.'),
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
                  ]))),
          SliverPadding(
              padding: const EdgeInsets.symmetric(
                  horizontal: CardexAlbumLayoutConstants.horizontalMargin),
              sliver: SliverToBoxAdapter(
                  child: controller.viewingCollection &&
                          controller.collection.status ==
                              CollectionStatus.loading &&
                          visible.isEmpty
                      ? const CardAlbumLoading()
                      : CardAlbum(
                          key: ValueKey(
                              '${controller.viewingCollection ? "collection" : controller.expansion?.slug}-${controller.filter.name}'),
                          cards: visible,
                          sourceCardCount: controller.cards.length,
                          collection: controller.collection,
                          ownershipFor: controller.ownershipFor,
                          onLanguageSelected: controller.selectOwnedLanguage,
                          onPageVisible: controller.viewingCollection
                              ? null
                              : controller.onAlbumPageVisible,
                          onOpen: onOpen))),
          SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverToBoxAdapter(
                  child: Column(children: [
                if (!controller.viewingCollection && controller.loadingPage)
                  Semantics(
                      liveRegion: true,
                      child: const Column(children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8),
                        Text('Caricamento altre carte…'),
                      ])),
                if (controller.viewingCollection &&
                    controller.ownershipKnown &&
                    visible.isEmpty)
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
                    controller.hasMore &&
                    controller.pageError)
                  OutlinedButton(
                      onPressed: controller.loadMore,
                      child: const Text('Riprova carte')),
              ]))),
        ]);
      });
}
