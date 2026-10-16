import 'dart:async';
import 'package:flutter/material.dart';

import '../../../controller/marketplace_search_controller.dart';
import '../../../model/marketplace_home.dart';
import '../atomics/search_card_tile.dart';
import 'search_filters.dart';
import 'marketplace_suggestions.dart';

class MarketplaceSearch extends StatefulWidget {
  const MarketplaceSearch(
      {super.key,
      required this.controller,
      required this.discovery,
      required this.onOpen,
      this.onPaletteOpen});
  final MarketplaceSearchController controller;
  final Widget discovery;
  final ValueChanged<MarketplaceCardPreview> onOpen;
  final void Function(MarketplaceCardPreview card, Color? color)? onPaletteOpen;

  @override
  State<MarketplaceSearch> createState() => _MarketplaceSearchState();
}

class _MarketplaceSearchState extends State<MarketplaceSearch> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      widget.controller.warmUpSuggestions();
      unawaited(widget.controller.refreshSuggestions());
    } else {
      widget.controller.dismissSuggestions();
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(MarketplaceSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _sync();
    }
  }

  void _sync() {
    final query = widget.controller.state.query;
    if (_input.text == query) return;
    _input.value = TextEditingValue(
        text: query, selection: TextSelection.collapsed(offset: query.length));
  }

  void _changeQuery(String query) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    widget.controller.setQuery(query);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _input.dispose();
    _scroll.dispose();
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final state = widget.controller.state;
          return LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth < 360
                ? 1
                : constraints.maxWidth < 700
                    ? 2
                    : 3;
            final rows = (state.cards.length / columns).ceil();
            return CustomScrollView(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  sliver: SliverToBoxAdapter(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Marketplace',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 16),
                      TextField(
                        focusNode: _focus,
                        controller: _input,
                        maxLength: 180,
                        textInputAction: TextInputAction.search,
                        onChanged: _changeQuery,
                        onSubmitted: (_) {
                          _focus.unfocus();
                          unawaited(widget.controller.submit());
                        },
                        decoration: InputDecoration(
                            hintText: 'Cerca carta, set o numero',
                            counterText: '',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: state.query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Cancella ricerca',
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () => _changeQuery(''))),
                      ),
                      if (_focus.hasFocus)
                        TextFieldTapRegion(
                            child: MarketplaceSuggestions(
                                state: widget.controller.suggestions,
                                maxListHeight: (constraints.maxHeight -
                                        260 *
                                            (MediaQuery.textScalerOf(context)
                                                    .scale(14) /
                                                14))
                                    .clamp(128.0, 252.0)
                                    .toDouble(),
                                onSelected: (item) {
                                  _focus.unfocus();
                                  unawaited(
                                      widget.controller.selectSuggestion(item));
                                },
                                onOpenCard: (card) {
                                  _focus.unfocus();
                                  widget.controller.dismissSuggestions();
                                  widget.onOpen(card);
                                },
                                onPaletteOpen: widget.onPaletteOpen == null
                                    ? null
                                    : (card, color) {
                                        _focus.unfocus();
                                        widget.controller.dismissSuggestions();
                                        widget.onPaletteOpen!(card, color);
                                      },
                                onViewAll: () {
                                  _focus.unfocus();
                                  unawaited(widget.controller.submit());
                                })),
                      SearchFilters(
                          productType: state.productType,
                          printLanguage: state.printLanguage,
                          onChanged: (productType, printLanguage) {
                            if (_scroll.hasClients) _scroll.jumpTo(0);
                            widget.controller.setFilters(
                                productType: productType,
                                printLanguage: printLanguage);
                          }),
                      Visibility(
                          visible: !state.isActive,
                          maintainState: true,
                          child: widget.discovery),
                      if (state.isActive) ...[
                        const SizedBox(height: 12),
                        Text(
                            state.total == null
                                ? 'Risultati'
                                : 'Risultati: ${state.total}',
                            style: Theme.of(context).textTheme.titleMedium),
                        if (state.isLoading)
                          const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: LinearProgressIndicator()),
                        if (!state.isLoading &&
                            !state.hasError &&
                            state.cards.isEmpty)
                          const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                  'Nessun risultato. Prova un altro nome o numero.')),
                      ],
                    ],
                  )),
                ),
                if (state.isActive && !state.isLoading)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                            (context, row) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (var column = 0;
                                            column < columns;
                                            column++) ...[
                                          if (column > 0)
                                            const SizedBox(width: 12),
                                          Expanded(
                                              child: row * columns + column <
                                                      state.cards.length
                                                  ? SearchCardTile(
                                                      key: ValueKey(state
                                                          .cards[row * columns +
                                                              column]
                                                          .id),
                                                      card: state.cards[
                                                          row * columns +
                                                              column],
                                                      onPaletteOpen:
                                                          widget.onPaletteOpen == null
                                                              ? null
                                                              : (color) => widget
                                                                      .onPaletteOpen!(
                                                                  state.cards[row * columns + column],
                                                                  color),
                                                      onOpen: () => widget.onOpen(state.cards[row * columns + column]))
                                                  : const SizedBox.shrink()),
                                        ],
                                      ]),
                                ),
                            childCount: rows)),
                  ),
                SliverToBoxAdapter(
                    child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    if (state.hasError) ...[
                      const Text('La ricerca non e disponibile al momento.'),
                      TextButton.icon(
                          onPressed: widget.controller.retry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Riprova')),
                    ] else if (state.isLoadingMore)
                      const CircularProgressIndicator()
                    else if (state.hasMore && !state.isLoading)
                      OutlinedButton.icon(
                          onPressed: widget.controller.loadMore,
                          icon: const Icon(Icons.expand_more_rounded),
                          label: const Text('Carica altri')),
                  ]),
                )),
              ],
            );
          });
        },
      );
}
