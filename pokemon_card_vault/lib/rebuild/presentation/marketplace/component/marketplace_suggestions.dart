import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../../../model/marketplace_home.dart';
import '../../../model/marketplace_suggestions.dart';
import '../atomics/suggestion_card_tile.dart';

/// Presentation only: receives state and callbacks, owns no data access.
class MarketplaceSuggestions extends StatelessWidget {
  const MarketplaceSuggestions(
      {super.key,
      required this.state,
      required this.onSelected,
      required this.onOpenCard,
      required this.onViewAll,
      this.onPaletteOpen,
      this.maxListHeight = 252});
  final MarketplaceSuggestionsState state;
  final ValueChanged<LocalSuggestion> onSelected;
  final ValueChanged<MarketplaceCardPreview> onOpenCard;
  final void Function(MarketplaceCardPreview card, Color? color)? onPaletteOpen;
  final VoidCallback onViewAll;
  final double maxListHeight;

  @override
  Widget build(BuildContext context) {
    if (!state.loading &&
        !state.cardsLoading &&
        !state.cardsError &&
        state.items.isEmpty &&
        state.cards.isEmpty) {
      return const SizedBox.shrink();
    }
    final rows = <Widget>[
      if (state.cards.isNotEmpty) ...[
        for (final card in state.cards)
          SuggestionCardTile(
              key: ValueKey(card.id),
              card: card,
              onOpen: () => onOpenCard(card),
              onPaletteOpen: onPaletteOpen == null
                  ? null
                  : (color) => onPaletteOpen!(card, color)),
      ],
      if (state.cardsError)
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child:
                Text('Impossibile caricare le versioni. Riprova la ricerca.')),
      if (state.items.isNotEmpty) ...[
        const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Nomi, espansioni e artisti')),
        for (final item in state.items)
          ListTile(
              dense: true,
              leading: Icon(item.kind == 'artist'
                  ? Icons.brush_outlined
                  : item.kind == 'set'
                      ? Icons.collections_bookmark_outlined
                      : Icons.style_outlined),
              title: Text(item.display,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(item.kind == 'artist'
                  ? 'Artista'
                  : item.kind == 'set'
                      ? 'Espansione'
                      : 'Nome'),
              onTap: () => onSelected(item)),
      ],
    ];
    return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text('Suggerimenti')),
                  if (state.loading || state.cardsLoading)
                    LinearProgressIndicator(
                        minHeight: 2,
                        semanticsLabel: state.cardsLoading
                            ? 'Caricamento versioni dal catalogo'
                            : 'Ricerca suggerimenti'),
                  ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxListHeight),
                      child: ListView.builder(
                          shrinkWrap: true,
                          primary: false,
                          scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                          addAutomaticKeepAlives: false,
                          itemCount: rows.length,
                          itemBuilder: (context, index) => rows[index])),
                  TextButton(
                      onPressed: onViewAll,
                      child: const Text('Mostra tutti i risultati')),
                ])));
  }
}
