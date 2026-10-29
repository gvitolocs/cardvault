import 'package:flutter/material.dart';
import 'dart:async';
import '../../model/scanner.dart';
import '../../model/listing_draft.dart';
import '../shared/component/scan_clipboard_button.dart';
import '../shared/component/scan_clipboard_sheet.dart';

import '../../model/card.dart';
import 'component/card_tile.dart';
import 'component/marketplace_discovery.dart';
import 'component/marketplace_search.dart';
import '../shared/component/marketplace_cart_sheet.dart';
import '../shared/component/expansion_drawer.dart';
import '../shared/component/utility_bar.dart';
import '../shared/component/themed_page_background.dart';
import '../scanner/scanner_screen.dart';
import '../../model/marketplace_home.dart';
import '../../controller/marketplace_controller.dart';
import '../card_details/card_details.dart';
import '../cardex/cardex_screen.dart';
import '../portfolio/portfolio_screen.dart';
import '../profile/profile_screen.dart';
import '../account/account_screen.dart';
import '../shared/component/collection_language_button.dart';
import '../shared/component/collection_artwork_scope.dart';
import '../shared/atomics/themed_icon.dart';
import '../../style/app_theme_icons.dart';

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
    _controller.account.addListener(_syncScannerUser);
    _syncScannerUser();
  }

  @override
  void didUpdateWidget(MarketplaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncSearch);
      oldWidget.controller.account.removeListener(_syncScannerUser);
      _controller.addListener(_syncSearch);
      _controller.account.addListener(_syncScannerUser);
      _syncScannerUser();
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

  void _syncScannerUser() {
    final uid = _controller.account.session.user?.id;
    _controller.scanner.setUser(uid);
    unawaited(_controller.clipboard.setUser(uid));
  }

  @override
  void dispose() {
    _controller.removeListener(_syncSearch);
    _controller.account.removeListener(_syncScannerUser);
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
    _showCatalogPreview(
        expansion.name, '${expansion.cardCount} carte nel catalogo');
  }

  Future<void> _showLogin() async {
    _controller.account.clearFeedback();
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (loginContext) => AccountScreen(
              controller: _controller.account,
              onAuthenticated: () => Navigator.of(loginContext).pop(),
              onGuest: () => Navigator.of(loginContext).pop(),
            )));
  }

  Future<void> _showClipboard() async {
    final selected = await showScanClipboardSheet(
        context: context, controller: _controller.clipboard);
    if (mounted && selected != null) await _showDraft(selected);
  }

  Future<void> _showScannedCard(ScannedCard card) async {
    final draft = _controller.clipboard.find(card.id);
    if (draft != null) await _showDraft(draft);
  }

  Future<void> _showDraft(ListingDraft draft) async {
    if (!mounted) return;
    await _openCard(draft.preview, draft: draft);
  }

  Future<void> _loginForDraft(String id) async {
    final guest = !_controller.clipboard.authenticated
        ? _controller.clipboard.find(id)
        : null;
    await _showLogin();
    if (!mounted) return;
    // This one guest draft is carried only after its user explicitly requested login.
    if (guest != null && _controller.account.session.user != null) {
      await _controller.clipboard.importDraft(guest);
    }
  }

  void _showCatalogCardPreview(MarketplaceCardPreview card,
      [Color? cardColor]) {
    _openCard(card, cardColor: cardColor);
  }

  void _showCollectionCard(MarketplaceCardPreview card) =>
      _openCard(_controller.cardex.artworkPreview(card), showOwnership: true);

  Future<void> _openCard(MarketplaceCardPreview card,
      {Color? cardColor,
      bool showOwnership = false,
      ListingDraft? draft}) async {
    final detailsController = _controller.createCardDetails(card.id);
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CardDetails(
              preview: card,
              controller: detailsController,
              cart: _controller.cart,
              initialColor: cardColor,
              ownershipController: showOwnership ? _controller.cardex : null,
              clipboard: _controller.clipboard,
              draftId: draft?.id,
              onOpenClipboard: _showClipboard,
              onDraftLogin:
                  draft == null ? _showLogin : () => _loginForDraft(draft.id),
              sellerName: _controller.account.session.user?.displayName ??
                  'Pokoin seller',
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
        endDrawer: Builder(
            builder: (drawerContext) => ExpansionDrawer(
                  controller: _controller.cardex,
                  onClose: () => Scaffold.of(drawerContext).closeEndDrawer(),
                  onSelect: (expansion) {
                    Scaffold.of(drawerContext).closeEndDrawer();
                    _controller.openCardexExpansion(expansion);
                  },
                  onCollection: () {
                    Scaffold.of(drawerContext).closeEndDrawer();
                    _controller.selectTab(3);
                    _controller.cardex.showCollection();
                  },
                )),
        endDrawerEnableOpenDragGesture: false,
        appBar: AppBar(
          title: LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth < 64) {
              return Image.asset('assets/brand/pokoin-96.png',
                  width: 30, height: 30, semanticLabel: 'pokoin');
            }
            return Row(children: [
              Image.asset('assets/brand/pokoin-96.png', width: 30, height: 30),
              const SizedBox(width: 10),
              const Flexible(
                  child: Text('pokoin',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800))),
            ]);
          }),
          actions: [
            if (_controller.selectedTab == 2 || _controller.selectedTab == 3)
              CollectionLanguageButton(
                  controller: _controller.cardex.artwork,
                  onSelected: _controller.cardex.setArtworkLanguage),
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
                    child: const ThemedIcon(
                        slot: AppThemeIcon.cart,
                        fallback: Icons.shopping_bag_outlined),
                  ),
                );
              },
            ),
            Builder(
                builder: (scaffoldContext) => IconButton(
                      tooltip: 'Espansioni per era',
                      icon: const ThemedIcon(
                          slot: AppThemeIcon.filters,
                          fallback: Icons.filter_list_rounded),
                      onPressed: () {
                        _controller.cardex.start();
                        Scaffold.of(scaffoldContext).openEndDrawer();
                      },
                    )),
            ScanClipboardButton(
                controller: _controller.clipboard, onPressed: _showClipboard),
            const SizedBox(width: 8),
          ],
        ),
        body: ThemedPageBackground(
          child: SafeArea(
            top: false,
            child: CollectionArtworkScope(
                controller: _controller.cardex.artwork,
                languageFor: _controller.cardex.artworkLanguageFor,
                child: switch (_controller.selectedTab) {
                  0 => _marketplace(),
                  1 => ScannerScreen(
                      controller: _controller.scanner,
                      onOpenCard: _showScannedCard,
                      onLogin: _showLogin,
                      onSaved: () {
                        _controller.cardex.retryCollection();
                      }),
                  2 => PortfolioScreen(
                      controller: _controller.cardex,
                      onOpen: _showCollectionCard),
                  3 => CardexScreen(
                      controller: _controller.cardex,
                      onOpen: _showCollectionCard),
                  4 => ProfileScreen(
                      controller: _controller.profile,
                      onLogin: _showLogin,
                      onPortfolio: () => _controller.selectTab(2),
                      onCardex: () => _controller.selectTab(3),
                      onOpenCard: (id) => _showCatalogCardPreview(
                          MarketplaceCardPreview(
                              id: id, name: 'Carta #$id', expansion: ''))),
                  _ => _marketplace(),
                }),
          ),
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
        cart: _controller.cart,
        controller: _controller.search,
        onOpen: _showCatalogCardPreview,
        onPaletteOpen: _showCatalogCardPreview,
        discovery: ValueListenableBuilder(
          valueListenable: _controller.discovery,
          builder: (context, state, _) => MarketplaceDiscovery(
            cart: _controller.cart,
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
                      prefixIcon: const ThemedIcon(
                          slot: AppThemeIcon.search,
                          fallback: Icons.search_rounded),
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
                          cart: _controller.cart,
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
