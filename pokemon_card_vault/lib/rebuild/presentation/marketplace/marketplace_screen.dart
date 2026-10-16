import 'package:flutter/material.dart';

import '../../model/card.dart';
import 'component/card_tile.dart';
import 'component/marketplace_discovery.dart';
import 'component/marketplace_search.dart';
import '../shared/component/marketplace_cart_sheet.dart';
import '../shared/component/utility_bar.dart';
import '../shared/component/navigation_placeholder.dart';
import '../../model/marketplace_home.dart';
import '../../controller/marketplace_controller.dart';
import '../card_details/card_details.dart';
import '../cardex/cardex_screen.dart';
import '../portfolio/portfolio_screen.dart';
import '../profile/profile_screen.dart';
import '../account/account_screen.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen(
      {super.key, required this.controller, this.showDiscovery = true});

  final MarketplaceController controller;
  final bool showDiscovery;

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final _searchController = TextEditingController();
  MarketplaceController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _syncSearch();
    _controller.addListener(_syncSearch);
  }

  @override
  void didUpdateWidget(MarketplaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncSearch);
      _controller.addListener(_syncSearch);
      _syncSearch();
    }
  }

  void _syncSearch() {
    final query = _controller.searchQuery;
    if (_searchController.text == query) return;
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_syncSearch);
    _searchController.dispose();
    super.dispose();
  }

  void _addToCart(DemoCard card) {
    _controller.cart.addCard(card);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${card.name} aggiunta al carrello demo')),
    );
  }

  void _showDetail(DemoCard card) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CardDetails.demo(card: card, cart: _controller.cart),
    ));
  }

  void _showExpansionPreview(MarketplaceExpansion expansion) {
    // Integrazione futura: ricerca paginata per slug/nome espansione.
    _showCatalogPreview(
        expansion.name, '${expansion.cardCount} carte nel catalogo');
  }

  void _showLogin() {
    _controller.account.clearFeedback();
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (loginContext) => AccountScreen(
              controller: _controller.account,
              onAuthenticated: () => Navigator.of(loginContext).pop(),
              onGuest: () => Navigator.of(loginContext).pop(),
            )));
  }

  void _showCatalogCardPreview(MarketplaceCardPreview card,
      [Color? cardColor]) {
    final detailsController = _controller.createCardDetails(card.id);
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CardDetails(
              preview: card,
              controller: detailsController,
              cart: _controller.cart,
              initialColor: cardColor,
            )));
  }

  void _showCatalogPreview(String title, String description) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(description),
              const SizedBox(height: 16),
              const Text('Anteprima del catalogo'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Chiudi'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Row(children: [
            Image.asset('assets/brand/pokoin-96.png', width: 30, height: 30),
            const SizedBox(width: 10),
            const Text('pokoin', style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
          actions: [
            ListenableBuilder(
              listenable: _controller.cart,
              builder: (context, _) {
                final cartCount = _controller.cart.itemCount;
                return IconButton(
                  tooltip: 'Carrello, $cartCount articoli',
                  onPressed: () => showMarketplaceCartSheet(
                    context: context,
                    controller: _controller.cart,
                  ),
                  icon: Badge(
                    isLabelVisible: cartCount > 0,
                    label: Text('$cartCount'),
                    child: const Icon(Icons.shopping_bag_outlined),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: switch (_controller.selectedTab) {
            0 => _marketplace(),
            2 => PortfolioScreen(
                controller: _controller.cardex,
                onOpen: _showCatalogCardPreview),
            3 => CardexScreen(
                controller: _controller.cardex,
                onOpen: _showCatalogCardPreview),
            4 => ProfileScreen(
                controller: _controller.profile,
                onLogin: _showLogin,
                onPortfolio: () => _controller.selectTab(2),
                onCardex: () => _controller.selectTab(3),
                onOpenCard: (id) => _showCatalogCardPreview(
                    MarketplaceCardPreview(
                        id: id, name: 'Carta #$id', expansion: ''))),
            _ => NavigationPlaceholder(
                selectedIndex: _controller.selectedTab,
                onExploreMarketplace: () => _controller.selectTab(0),
              ),
          },
        ),
        bottomNavigationBar: UtilityBar(
          selectedIndex: _controller.selectedTab,
          onDestinationSelected: _controller.selectTab,
        ),
      ),
    );
  }

  Widget _marketplace() {
    if (widget.showDiscovery) {
      return MarketplaceSearch(
        controller: _controller.search,
        onOpen: _showCatalogCardPreview,
        onPaletteOpen: _showCatalogCardPreview,
        discovery: ValueListenableBuilder(
          valueListenable: _controller.discovery,
          builder: (context, state, _) => MarketplaceDiscovery(
            state: state,
            onRetry: state.data == null && !state.hasError
                ? () => _controller.loadDiscovery()
                : _controller.retryDiscovery,
            onExpansionSelected: _showExpansionPreview,
            onCardSelected: _showCatalogCardPreview,
            onCardPaletteSelected: _showCatalogCardPreview,
          ),
        ),
      );
    }
    final cards = _controller.visibleCards;
    final filtered = _controller.isFiltered;
    // La larghezza cambia con finestra/orientamento, non con lo scroll.
    // SliverLayoutBuilder riceverebbe nuovi vincoli a ogni frame di scroll
    // e ricostruirebbe inutilmente tutte le carte del precedente Wrap.
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth - 40 < 320 ? 1 : 2;
      final rowCount = (cards.length / columns).ceil();
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('La tua prossima\ncarta è qui.',
                      style: Theme.of(context)
                          .textTheme
                          .headlineLarge
                          ?.copyWith(
                              fontWeight: FontWeight.w800, height: 1.15)),
                  const SizedBox(height: 10),
                  Text(
                      widget.showDiscovery
                          ? 'Marketplace · Rebuild'
                          : 'Marketplace · prototipo con dati di esempio',
                      style: const TextStyle(color: Color(0xFFA8AABB))),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    // Collegamento futuro: CardService.searchMarketplaceCards
                    // e searchAutocompleteCardsWithContext con debounce,
                    // annullamento delle risposte obsolete e paginazione.
                    onChanged: _controller.setSearchQuery,
                    decoration: InputDecoration(
                      hintText: 'Cerca carta, set o numero',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Cancella ricerca',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => _controller.setSearchQuery(''),
                            ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (widget.showDiscovery) ...[
                    Visibility(
                      visible: !filtered,
                      maintainState: true,
                      child: ValueListenableBuilder(
                        valueListenable: _controller.discovery,
                        builder: (context, state, _) => MarketplaceDiscovery(
                          state: state,
                          onRetry: state.data == null && !state.hasError
                              ? () => _controller.loadDiscovery()
                              : _controller.retryDiscovery,
                          onExpansionSelected: _showExpansionPreview,
                          onCardSelected: _showCatalogCardPreview,
                          onCardPaletteSelected: _showCatalogCardPreview,
                        ),
                      ),
                    ),
                    if (!filtered) const SizedBox(height: 28),
                  ],
                  Text(
                      widget.showDiscovery
                          ? 'Filtra le carte demo'
                          : 'Esplora le espansioni',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('Tutte'),
                          selected: _controller.selectedExpansion == null,
                          onSelected: (_) => _controller.selectExpansion(null),
                        ),
                      ),
                      for (final expansion in _controller.expansions)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(expansion),
                            selected:
                                _controller.selectedExpansion == expansion,
                            onSelected: (selected) => _controller
                                .selectExpansion(selected ? expansion : null),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 28),
                  Text(
                      filtered
                          ? 'Risultati · ${cards.length}'
                          : widget.showDiscovery
                              ? 'Carte demo in evidenza'
                              : 'Carte in evidenza',
                      style: Theme.of(context).textTheme.titleLarge),
                  if (!filtered) ...[
                    const SizedBox(height: 6),
                    const Text('Una selezione per iniziare a esplorare.',
                        style: TextStyle(color: Color(0xFFA8AABB))),
                  ],
                ],
              ),
            ),
          ),
          if (cards.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child:
                    Text('Nessuna carta trovata. Prova un altro nome o set.'),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            // Righe create quando si avvicinano al viewport, con altezza
            // naturale anche a testo ingrandito. Il delegate isola il repaint
            // di ogni riga tramite i suoi RepaintBoundary predefiniti.
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, row) {
                return Padding(
                  padding: EdgeInsets.only(bottom: row < rowCount - 1 ? 16 : 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var column = 0; column < columns; column++) ...[
                        if (column > 0) const SizedBox(width: 12),
                        Expanded(
                          child: row * columns + column < cards.length
                              ? CardTile(
                                  card: cards[row * columns + column],
                                  favorite: _controller.isFavorite(
                                      cards[row * columns + column].id),
                                  onFavorite: () => _controller.toggleFavorite(
                                      cards[row * columns + column]),
                                  onOpen: () => _showDetail(
                                      cards[row * columns + column]),
                                  onAdd: () =>
                                      _addToCart(cards[row * columns + column]),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                );
              }, childCount: rowCount),
            ),
          ),
        ],
      );
    });
  }
}
