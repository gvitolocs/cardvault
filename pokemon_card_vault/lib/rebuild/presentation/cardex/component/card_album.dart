import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../model/cardex.dart';
import '../../../model/card_ownership.dart';
import '../../../model/marketplace_home.dart';
import '../../../style/cardex_style.dart';
import '../../../constants/cardex_artwork_constants.dart';
import '../../../constants/cardex_album_layout_constants.dart';
import '../../shared/component/card_ownership_edge_controls.dart';
import '../atomics/album_card.dart';

/// Sei tasche per foglio; su tablet due fogli affiancati. Si costruisce solo
/// lo sfoglio visibile, non tutte le miniature del catalogo.
class CardAlbum extends StatefulWidget {
  const CardAlbum(
      {super.key,
      required this.cards,
      required this.collection,
      this.ownershipFor,
      this.onLanguageSelected,
      this.onPageVisible,
      this.sourceCardCount,
      required this.onOpen});
  final List<MarketplaceCardPreview> cards;
  final CardCollection collection;
  final CardOwnership Function(String)? ownershipFor;
  final void Function(String, String)? onLanguageSelected;
  final void Function(int visibleEnd, int capacity)? onPageVisible;

  /// Unfiltered source progress also changes when a filter yields no cards.
  final int? sourceCardCount;
  final ValueChanged<MarketplaceCardPreview> onOpen;

  @override
  State<CardAlbum> createState() => _CardAlbumState();
}

class _CardAlbumState extends State<CardAlbum> {
  // La chiave del componente resetta pagina quando cambiano album o filtro.
  // Non ripristinare una pagina di un album precedente dal PageStorage esterno.
  final _pages = PageController(keepPage: false);
  int _page = 0;
  int _capacity = 6;
  ScrollPosition? _viewportPosition;
  (int, int, int, int?)? _reportedPosition;

  void _reportPosition() {
    if (widget.onPageVisible == null) return;
    final position =
        (_page, _capacity, widget.cards.length, widget.sourceCardCount);
    if (_reportedPosition == position) return;
    _reportedPosition = position;
    // Never start a controller notification/network load during layout/build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reportedPosition != position) return;
      widget.onPageVisible?.call(
          math.min(widget.cards.length, (_page + 1) * _capacity), _capacity);
    });
  }

  @override
  void didUpdateWidget(CardAlbum oldWidget) {
    super.didUpdateWidget(oldWidget);
    final last = math.max(0, (widget.cards.length / _capacity).ceil() - 1);
    if (_page > last) {
      _page = last;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(_page);
      });
    }
  }

  void _turn(int target, bool reduceMotion) {
    if (reduceMotion) {
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(target,
          duration: const Duration(milliseconds: 440),
          curve: Curves.easeInOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) {
      // A filter may hide an entire fetched page. Continue until it has useful
      // cards or the catalog finishes; the controller stops on any error.
      _reportPosition();
      return const SizedBox.shrink();
    }
    _viewportPosition = Scrollable.maybeOf(context)?.position;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final spread = constraints.maxWidth >= 700;
      final capacity = spread ? 12 : 6;
      if (capacity != _capacity) {
        final firstCard = _page * _capacity;
        _capacity = capacity;
        _page = firstCard ~/ capacity;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pages.hasClients) _pages.jumpToPage(_page);
        });
      }
      final count = (widget.cards.length / capacity).ceil();
      final leafWidth =
          (constraints.maxWidth - (spread ? 16 : 0)) / (spread ? 2 : 1);
      final columns =
          leafWidth < 420 || MediaQuery.textScalerOf(context).scale(14) > 20
              ? 2
              : 3;
      final rows = 6 ~/ columns;
      const leafInset = CardexAlbumLayoutConstants.leafPadding +
          CardexAlbumLayoutConstants.leafBorder;
      final tileWidth = (leafWidth -
              2 * leafInset -
              (columns - 1) * CardexAlbumLayoutConstants.columnGap) /
          columns;
      // Exactly the art window plus its 1px outline and external controls.
      // A fixed minimum/portrait pocket would reintroduce dark letterboxing.
      final rowHeight =
          (tileWidth - 2) / CardexArtworkConstants.artworkAspectRatio +
              2 +
              CardOwnershipEdgeControls.railHeight(context);
      final numberHeight = MediaQuery.textScalerOf(context)
              .scale(CardexAlbumLayoutConstants.pageNumberFontSize) *
          CardexAlbumLayoutConstants.pageNumberLineHeight;
      _reportPosition();
      return Column(children: [
        SizedBox(
            height: rowHeight * rows +
                (rows - 1) * CardexAlbumLayoutConstants.rowGap +
                2 * leafInset +
                CardexAlbumLayoutConstants.pageNumberGap +
                numberHeight,
            child: PageView.builder(
              controller: _pages,
              itemCount: count,
              onPageChanged: (value) => setState(() => _page = value),
              itemBuilder: (context, index) => AnimatedBuilder(
                  animation: _pages,
                  builder: (context, child) {
                    final position =
                        _pages.hasClients && _pages.position.haveDimensions
                            ? (_pages.page ?? _page.toDouble())
                            : _page.toDouble();
                    final delta = (index - position).clamp(-1.0, 1.0);
                    return Transform(
                        alignment: delta < 0
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, .001)
                          ..rotateY(reduceMotion ? 0 : delta * .48),
                        child: child);
                  },
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                            child: _leaf(
                                index * capacity,
                                index * (spread ? 2 : 1) + 1,
                                rowHeight,
                                columns)),
                        if (spread) ...[
                          Container(
                              width: 16,
                              color: CardexStyle.seam,
                              child: const Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    Icon(Icons.drag_handle, size: 14),
                                    Icon(Icons.drag_handle, size: 14),
                                    Icon(Icons.drag_handle, size: 14)
                                  ])),
                          Expanded(
                              child: _leaf(index * capacity + 6, index * 2 + 2,
                                  rowHeight, columns)),
                        ],
                      ])),
            )),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
              tooltip: 'Pagina precedente',
              onPressed:
                  _page > 0 ? () => _turn(_page - 1, reduceMotion) : null,
              icon: const Icon(Icons.chevron_left)),
          Flexible(
              child: Text(
                  spread
                      ? 'Pagine ${_page * 2 + 1}–${_page * 2 + 2} · ${widget.cards.length} carte'
                      : 'Pagina ${_page + 1} di $count · ${widget.cards.length} carte'
                          '${widget.collection.status == CollectionStatus.loading ? " · caricamento…" : ""}',
                  textAlign: TextAlign.center)),
          IconButton(
              tooltip: 'Pagina successiva',
              onPressed: _page + 1 < count
                  ? () => _turn(_page + 1, reduceMotion)
                  : null,
              icon: const Icon(Icons.chevron_right)),
        ]),
        const Text('Scorri lateralmente per sfogliare',
            style: TextStyle(color: Colors.white60)),
      ]);
    });
  }

  Widget _leaf(int start, int number, double rowHeight, int columns) =>
      Container(
        padding: const EdgeInsets.all(CardexAlbumLayoutConstants.leafPadding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: Colors.white24,
              width: CardexAlbumLayoutConstants.leafBorder),
          gradient: const LinearGradient(colors: [
            CardexStyle.pageEdge,
            CardexStyle.page,
            CardexStyle.pageEdge
          ], stops: [
            0,
            .08,
            1
          ]),
        ),
        child: Column(children: [
          Expanded(
              child: GridView.builder(
                  primary: false,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: CardexAlbumLayoutConstants.columnGap,
                      mainAxisSpacing: CardexAlbumLayoutConstants.rowGap,
                      mainAxisExtent: rowHeight),
                  itemCount: 6,
                  itemBuilder: (context, slot) {
                    final index = start + slot;
                    if (index >= widget.cards.length) {
                      return ExcludeSemantics(
                          child: DecoratedBox(
                              decoration: BoxDecoration(
                                  color: Colors.black12,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white10))));
                    }
                    final card = widget.cards[index];
                    return AlbumCard(
                        key: ValueKey(card.id),
                        card: card,
                        artworkOnly: true,
                        quantity: widget.collection.quantityFor(card.id),
                        viewportPosition: _viewportPosition,
                        pageChanges: _pages,
                        ownership: widget.ownershipFor?.call(card.id),
                        onLanguageSelected: widget.onLanguageSelected == null
                            ? null
                            : (language) =>
                                widget.onLanguageSelected!(card.id, language),
                        ownershipKnown:
                            widget.collection.status == CollectionStatus.ready,
                        onOpen: () => widget.onOpen(card));
                  })),
          const SizedBox(height: CardexAlbumLayoutConstants.pageNumberGap),
          Text('$number',
              style: const TextStyle(
                  color: Colors.white60,
                  fontSize: CardexAlbumLayoutConstants.pageNumberFontSize,
                  height: CardexAlbumLayoutConstants.pageNumberLineHeight)),
        ]),
      );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }
}
