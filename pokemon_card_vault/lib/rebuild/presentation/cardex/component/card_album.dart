import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../model/cardex.dart';
import '../../../model/marketplace_home.dart';
import '../../../style/cardex_style.dart';
import '../atomics/album_card.dart';

/// Sei tasche per foglio; su tablet due fogli affiancati. Si costruisce solo
/// lo sfoglio visibile, non tutte le miniature del catalogo.
class CardAlbum extends StatefulWidget {
  const CardAlbum(
      {super.key,
      required this.cards,
      required this.collection,
      required this.onOpen});
  final List<MarketplaceCardPreview> cards;
  final CardCollection collection;
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
    if (widget.cards.isEmpty) return const SizedBox.shrink();
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
      final columns = MediaQuery.textScalerOf(context).scale(14) > 20 ? 2 : 3;
      final rows = 6 ~/ columns;
      final tileWidth = (leafWidth - 20 - (columns - 1) * 8) / columns;
      final textHeight = MediaQuery.textScalerOf(context).scale(100);
      final rowHeight = math.max(120.0, (tileWidth - 20) * 1.4 + textHeight);
      return Column(children: [
        SizedBox(
            height: rowHeight * rows + (rows - 1) * 8 + 44,
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
                      : 'Pagina ${_page + 1} di $count · ${widget.cards.length} carte',
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
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
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
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
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
                        quantity: widget.collection.quantityFor(card.id),
                        ownershipKnown:
                            widget.collection.status == CollectionStatus.ready,
                        onOpen: () => widget.onOpen(card));
                  })),
          const SizedBox(height: 4),
          Text('$number',
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ]),
      );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }
}
