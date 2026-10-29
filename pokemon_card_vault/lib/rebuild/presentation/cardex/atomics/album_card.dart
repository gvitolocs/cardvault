import 'package:flutter/material.dart';
import '../../../model/marketplace_home.dart';
import '../../../model/card_ownership.dart';
import '../../../model/cardex.dart';
import '../../shared/component/card_ownership_artwork.dart';
import '../../shared/component/card_ownership_edge_controls.dart';
import '../../shared/atomics/card_ownership_frame.dart';
import '../../shared/atomics/marketplace_thumbnail.dart';
import 'album_card_caption.dart';
import '../../shared/component/viewport_artwork.dart';
import 'cardex_artwork_window.dart';
import '../../shared/component/collection_artwork_scope.dart';
import '../../shared/component/collection_card_artwork.dart';

/// Tasca dell'album: stato sconosciuto distinto da carta mancante.
class AlbumCard extends StatelessWidget {
  const AlbumCard(
      {super.key,
      required this.card,
      required this.quantity,
      required this.ownershipKnown,
      this.ownership,
      this.onLanguageSelected,
      this.viewportPosition,
      this.pageChanges,
      this.artworkOnly = false,
      required this.onOpen});
  final MarketplaceCardPreview card;
  final int quantity;
  final bool ownershipKnown;
  final CardOwnership? ownership;
  final ValueChanged<String>? onLanguageSelected;
  final ScrollPosition? viewportPosition;
  final Listenable? pageChanges;
  // Portfolio keeps the complete card. Only the Cardex album opts into this.
  final bool artworkOnly;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final artworkScope = CollectionArtworkScope.maybeOf(context);
    final owned = quantity > 0;
    final view = ownership ??
        CardOwnership(
            cardId: card.id,
            status: ownershipKnown
                ? CollectionStatus.ready
                : CollectionStatus.guest,
            total: quantity,
            languages: const []);
    final status = !ownershipKnown
        ? view.hasConfirmedCopies
            ? 'Posseduta · quantità in aggiornamento'
            : ownership?.status == CollectionStatus.loading
                ? 'Sincronizzazione…'
                : 'Catalogo'
        : owned
            ? 'Posseduta · ×$quantity'
            : 'Mancante';
    return Semantics(
      label: '${card.name}, ${card.number}, ${card.expansion}, $status',
      button: true,
      child: InkWell(
        onTap: onOpen,
        borderRadius: CardOwnershipFrame.radius,
        child: CardOwnershipEdgeControls(
            ownership: view,
            cardName: card.name,
            outsideFrame: artworkOnly,
            onLanguageSelected: onLanguageSelected,
            child: Column(children: [
              Expanded(
                  child: CardOwnershipFrame(
                owned: view.hasConfirmedCopies,
                inset: artworkOnly ? 0 : 2,
                child: Padding(
                    padding: EdgeInsets.only(
                        top: artworkOnly
                            ? 0
                            : CardOwnershipEdgeControls.railHeight(context) /
                                2),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final languagePreview = view.displayPreview;
                      final imageUrl =
                          languagePreview?.imageUrl.isNotEmpty == true
                              ? languagePreview!.imageUrl
                              : languagePreview?.fullImageUrl.isNotEmpty == true
                                  ? languagePreview!.fullImageUrl
                                  : card.imageUrl.isEmpty
                                      ? card.fullImageUrl
                                      : card.imageUrl;
                      Widget scan(String url, VoidCallback? onError) {
                        if (!artworkOnly) {
                          return MarketplaceThumbnail(
                              imageUrl: url,
                              onError: onError,
                              width: constraints.maxWidth,
                              height: constraints.maxHeight);
                        }
                        return CardexArtworkWindow(
                            child: LayoutBuilder(
                                builder: (_, scan) => MarketplaceThumbnail(
                                    imageUrl: url,
                                    onError: onError,
                                    decodeLogicalWidth: constraints.maxWidth,
                                    width: scan.maxWidth,
                                    height: scan.maxHeight)));
                      }

                      Widget image(BuildContext _) => artworkScope == null
                          ? scan(imageUrl, null)
                          : CollectionCardArtwork(
                              controller: artworkScope.controller,
                              cardId: card.id,
                              language: artworkScope.languageFor(card.id),
                              fallbackUrl: imageUrl,
                              imageBuilder: scan);

                      return CardOwnershipArtwork(
                          image: viewportPosition == null
                              ? image(context)
                              : ViewportArtwork(
                                  key: ValueKey(card.id),
                                  position: viewportPosition!,
                                  pageChanges: pageChanges,
                                  builder: image),
                          cardName: card.name,
                          ownership: view,
                          showControls: false,
                          caption: artworkOnly
                              ? AlbumCardCaption(
                                  overlay: true,
                                  number: card.number,
                                  expansion: card.expansion,
                                  status: view.hasConfirmedCopies
                                      ? null
                                      : !ownershipKnown || !owned
                                          ? status
                                          : null)
                              : null);
                    })),
              )),
              if (!artworkOnly)
                SizedBox(
                  height: AlbumCardCaption.footerHeight(context),
                  child: Align(
                      alignment: Alignment.topLeft,
                      child: AlbumCardCaption(
                          number: card.number, expansion: card.expansion)),
                ),
            ])),
      ),
    );
  }
}
