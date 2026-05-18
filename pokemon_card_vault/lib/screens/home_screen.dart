import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/pokemon_card.dart';
import '../providers/auth_provider.dart';
import '../providers/card_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/recent_views_provider.dart';
import '../services/card_service.dart';
import '../utils/price_format.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class MarketplaceSearchScreen extends ConsumerStatefulWidget {
  const MarketplaceSearchScreen({
    super.key,
    required this.initialQuery,
    this.expansion,
    this.productType,
  });

  final String initialQuery;
  final String? expansion;
  final String? productType;

  @override
  ConsumerState<MarketplaceSearchScreen> createState() =>
      _MarketplaceSearchScreenState();
}

class _MarketplaceSearchScreenState
    extends ConsumerState<MarketplaceSearchScreen> {
  late final TextEditingController _controller;
  final CardService _cardService = CardService();
  List<PokemonCard> _results = const [];
  bool _isSearching = false;
  String? _error;
  int _requestId = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runSearch(widget.initialQuery);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final requestId = ++_requestId;
    final normalizedQuery = query.trim();
    final expansion = widget.expansion?.trim();
    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final productType = widget.productType?.trim();
      final results = expansion != null && expansion.isNotEmpty
          ? await _cardService.getCardsByExpansion(expansion)
          : productType != null && productType.isNotEmpty
              ? normalizedQuery.length < 2
                  ? await _cardService.getMarketplaceCardsByProductType(
                      productType,
                      limit: 240,
                    )
                  : await _cardService.searchMarketplaceCards(
                      normalizedQuery,
                      limit: 240,
                      productType: productType,
                    )
              : normalizedQuery.length < 2
                  ? await _cardService.getAllCards()
                  : await _cardService.searchMarketplaceCards(
                      normalizedQuery,
                      limit: 240,
                    );
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _results = const [];
        _isSearching = false;
        _error = '$error';
      });
    }
  }

  void _onSearchChanged(String value) {
    final expansion = widget.expansion?.trim();
    final productType = widget.productType?.trim();
    if (expansion?.isNotEmpty == true || productType?.isNotEmpty == true) {
      context.go(
        Uri(
          path: '/marketplace/search',
          queryParameters: {
            if (value.trim().isNotEmpty) 'q': value.trim(),
            if (productType?.isNotEmpty == true) 'productType': productType!,
          },
        ).toString(),
      );
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      _runSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final expansion = widget.expansion?.trim();
    final productType = widget.productType?.trim();
    final title = expansion != null && expansion.isNotEmpty
        ? 'Cards in $expansion'
        : productType != null && productType.isNotEmpty
            ? _productTypeTitle(productType)
            : 'Marketplace search';
    final singles =
        _results.where((card) => card.itemKind != 'product').toList();
    final products =
        _results.where((card) => card.itemKind == 'product').toList();

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: const Color(0xE60A1026),
        title: Text(title),
        leading: IconButton(
          onPressed: () => _goBackOr(context, '/marketplace'),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1220),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              TextField(
                controller: _controller,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  prefixIcon:
                      const Icon(Icons.search, color: Color(0xFFFACC15)),
                  hintText: 'Search singles and sealed products',
                  hintStyle: const TextStyle(color: Color(0xFF93A4C8)),
                  filled: true,
                  fillColor: const Color(0xFF111936),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              if (_isSearching)
                const LinearProgressIndicator(color: Color(0xFFFACC15)),
              if (_error != null) ...[
                Text(
                  'Search failed: $_error',
                  style: const TextStyle(color: Color(0xFFFCA5A5)),
                ),
                const SizedBox(height: 14),
              ],
              _SearchResultsHeader(query: query, count: _results.length),
              const SizedBox(height: 24),
              _SearchResultSection(
                title: productType == 'card' ? 'Graded candidates' : 'Singles',
                cards: singles,
              ),
              const SizedBox(height: 28),
              _SearchResultSection(title: 'Products', cards: products),
            ],
          ),
        ),
      ),
    );
  }

  String _productTypeTitle(String productType) {
    switch (productType) {
      case 'booster_box':
        return 'Booster boxes';
      case 'booster_pack':
        return 'Boosters';
      case 'card':
        return 'Graded candidates';
      default:
        return 'Marketplace search';
    }
  }
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 12;
  int _visibleCount = _pageSize;
  final List<_MarketFilter> _quickFilters = const [
    _MarketFilter(label: 'Holo grails', query: 'holo'),
    _MarketFilter(label: 'Trainer cards', query: 'trainer'),
    _MarketFilter(label: 'Booster boxes', query: 'booster'),
    _MarketFilter(label: 'Under 50k PKN', maxPrice: 50000),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetTransientSearch();
      ref.read(cardProvider.notifier).refreshCards();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardState = ref.watch(cardProvider);
    final cartState = ref.watch(cartProvider);
    final cachedBalance = ref.watch(cachedPknBalanceProvider).valueOrNull;
    final balance =
        ref.watch(pknBalanceProvider).valueOrNull ?? cachedBalance ?? 0;
    final cards = cardState.filteredCards;
    final catalog = cardState.cards;
    final recentViewsState = ref.watch(recentViewsProvider);
    final recentViews = recentViewsState.views;
    final personalizedCards = cardState.searchQuery.trim().isEmpty
        ? _rankCardsByRecentViews(cards, recentViews)
        : cards;
    final visibleCards = personalizedCards.take(_visibleCount).toList();
    final sections = _MarketplaceSections.fromCards(
      catalog,
      cachedSections: cardState.homeSections,
      recentViews: recentViews,
    );
    if (cardState.searchQuery.isEmpty && _searchController.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && cardState.searchQuery.isEmpty) {
          _searchController.clear();
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xE60A1026),
            title: const Text('Pokoin'),
            actions: [
              TextButton(
                  onPressed: () => context.go('/'), child: const Text('Home')),
              TextButton(
                  onPressed: () => context.go('/scan'),
                  child: const Text('Scan')),
              TextButton(
                  onPressed: () => context.go('/marketplace/signal'),
                  child: const Text('Signal')),
              _WalletBalanceButton(
                balance: balance,
                onTap: () => context.go('/wallet'),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.icon(
                  onPressed: () => context.go('/cart'),
                  icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                  label: Text('${cartState.itemCount}'),
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1220),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SearchAndControls(
                        controller: _searchController,
                        state: cardState,
                        quickFilters: _quickFilters,
                        onSearch: (value) {
                          setState(() => _visibleCount = _pageSize);
                          ref.read(cardProvider.notifier).searchCards(value);
                        },
                        onSort: (value) {
                          setState(() => _visibleCount = _pageSize);
                          ref.read(cardProvider.notifier).sortCards(value);
                        },
                        onFilter: _applyFilter,
                        onPreviewSelected: (card) {
                          ref.read(cardProvider.notifier).recordCardInteraction(
                                card,
                                'click',
                                source: 'search_preview',
                              );
                          _resetTransientSearch();
                          context.go('/card/${card.id}');
                        },
                        onClear: () {
                          setState(() => _visibleCount = _pageSize);
                          _searchController.clear();
                          ref.read(cardProvider.notifier).clearFilters();
                        },
                      ),
                      const SizedBox(height: 24),
                      if (cardState.isLoading)
                        const _LoadingMarket()
                      else if (cardState.error != null)
                        _ErrorState(error: cardState.error!)
                      else ...[
                        if (sections.recentlySeen.isNotEmpty ||
                            recentViewsState.isLoading) ...[
                          _CardCarouselSection(
                            title: 'Recently seen',
                            subtitle: null,
                            cards: sections.recentlySeen,
                            isLoading: recentViewsState.isLoading &&
                                sections.recentlySeen.isEmpty,
                          ),
                          const SizedBox(height: 24),
                        ],
                        _CardCarouselSection(
                          title: 'Best sellers',
                          subtitle:
                              'Demand-weighted picks until live sale history is available.',
                          cards: sections.bestSellers,
                        ),
                        const SizedBox(height: 24),
                        _CardCarouselSection(
                          title: 'Featured',
                          subtitle:
                              'Collector picks across sets and rarity bands.',
                          cards: sections.featured,
                        ),
                        const SizedBox(height: 24),
                        const _SuggestedCategories(),
                        const SizedBox(height: 28),
                        const _MarketHeader(),
                        const SizedBox(height: 16),
                        _MarketplaceGrid(cards: visibleCards),
                        const SizedBox(height: 18),
                        if (visibleCards.length < personalizedCards.length)
                          Center(
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() {
                                _visibleCount += _pageSize;
                              }),
                              icon: const Icon(Icons.expand_more),
                              label: Text(
                                'Show next ${math.min(_pageSize, personalizedCards.length - visibleCards.length)} cards',
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _applyFilter(_MarketFilter filter) {
    final notifier = ref.read(cardProvider.notifier);
    setState(() => _visibleCount = _pageSize);
    if (filter.query != null) {
      _searchController.text = filter.query!;
      notifier.searchCards(filter.query!);
    }
    if (filter.maxPrice != null) {
      notifier.filterByPriceRange(0, filter.maxPrice!);
    }
  }

  void _resetTransientSearch() {
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    }
    ref.read(cardProvider.notifier).clearFilters();
    if (mounted) {
      setState(() => _visibleCount = _pageSize);
    }
  }
}

class _WalletBalanceButton extends StatelessWidget {
  const _WalletBalanceButton({
    required this.balance,
    required this.onTap,
  });

  final int balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
      label: Text(formatPkn(balance, decimals: 0)),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFFACC15),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _SearchAndControls extends StatelessWidget {
  final TextEditingController controller;
  final CardState state;
  final List<_MarketFilter> quickFilters;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onSort;
  final ValueChanged<_MarketFilter> onFilter;
  final ValueChanged<PokemonCard> onPreviewSelected;
  final VoidCallback onClear;

  const _SearchAndControls({
    required this.controller,
    required this.state,
    required this.quickFilters,
    required this.onSearch,
    required this.onSort,
    required this.onFilter,
    required this.onPreviewSelected,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        TextField(
                          controller: controller,
                          onChanged: onSearch,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Color(0xFFFACC15),
                            ),
                            suffixIcon: state.isSearchingPreviews
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFFACC15),
                                      ),
                                    ),
                                  )
                                : null,
                            hintText:
                                'Search Pikachu, Base Set, holo, artist...',
                            hintStyle:
                                const TextStyle(color: Color(0xFF93A4C8)),
                            filled: true,
                            fillColor: const Color(0xFF111936),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        _SearchPreviewPanel(
                          query: state.searchQuery,
                          cards: state.searchPreviews,
                          isSearching: state.isSearchingPreviews,
                          onSelected: onPreviewSelected,
                          onShowAll: (query) => context.go(
                            Uri(
                              path: '/marketplace/search',
                              queryParameters: {'q': query},
                            ).toString(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  PopupMenuButton<String>(
                    tooltip: 'Sort',
                    onSelected: onSort,
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                          value: 'price', child: Text('Sort by price')),
                      PopupMenuItem(
                          value: 'rarity', child: Text('Sort by rarity')),
                      PopupMenuItem(
                          value: 'rating', child: Text('Sort by rating')),
                      PopupMenuItem(value: 'name', child: Text('Sort by name')),
                    ],
                    child: const _RoundControl(icon: Icons.sort, label: 'Sort'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(onPressed: onClear, child: const Text('Clear')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final filter in quickFilters)
                  ChoiceChip(
                    label: Text(filter.label),
                    selected: _isActive(filter),
                    onSelected: (_) => onFilter(filter),
                    selectedColor: const Color(0xFFFACC15),
                    backgroundColor: const Color(0xFF111936),
                    labelStyle: TextStyle(
                      color: _isActive(filter)
                          ? const Color(0xFF111827)
                          : const Color(0xFFE5E7EB),
                      fontWeight: FontWeight.w700,
                    ),
                    side:
                        BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isActive(_MarketFilter filter) {
    return state.searchQuery == filter.query && filter.query != null ||
        filter.maxPrice != null && state.maxPrice == filter.maxPrice;
  }
}

class _SearchPreviewPanel extends StatelessWidget {
  const _SearchPreviewPanel({
    required this.query,
    required this.cards,
    required this.isSearching,
    required this.onSelected,
    required this.onShowAll,
  });

  final String query;
  final List<PokemonCard> cards;
  final bool isSearching;
  final ValueChanged<PokemonCard> onSelected;
  final ValueChanged<String> onShowAll;

  @override
  Widget build(BuildContext context) {
    final trimmedQuery = query.trim();
    if (trimmedQuery.length < 2 || cards.isEmpty) {
      return const SizedBox.shrink();
    }

    final singles = cards.where(_isSingle).take(20).toList();
    final products = cards.where(_isProduct).take(20).toList();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1024),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SearchPreviewSection(
            title: 'Singles',
            icon: Icons.style_outlined,
            cards: singles,
            query: trimmedQuery,
            isSearching: isSearching,
            showSpinner: true,
            onSelected: onSelected,
            onShowAll: onShowAll,
          ),
          _SearchPreviewSection(
            title: 'Products',
            icon: Icons.inventory_2_outlined,
            cards: products,
            query: trimmedQuery,
            isSearching: isSearching,
            onSelected: onSelected,
            onShowAll: onShowAll,
          ),
        ],
      ),
    );
  }

  bool _isProduct(PokemonCard card) => card.itemKind == 'product';

  bool _isSingle(PokemonCard card) => !_isProduct(card);
}

class _SearchPreviewSection extends StatelessWidget {
  const _SearchPreviewSection({
    required this.title,
    required this.icon,
    required this.cards,
    required this.query,
    required this.isSearching,
    required this.onSelected,
    required this.onShowAll,
    this.showSpinner = false,
  });

  final String title;
  final IconData icon;
  final List<PokemonCard> cards;
  final String query;
  final bool isSearching;
  final ValueChanged<PokemonCard> onSelected;
  final ValueChanged<String> onShowAll;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 40,
          color: const Color(0xFF111936),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(icon, size: 16, color: const Color(0xFFFACC15)),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFFACC15),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => onShowAll(query),
                child: const Text('Show all'),
              ),
              if (showSpinner && isSearching) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
              const SizedBox(width: 12),
            ],
          ),
        ),
        for (final card in cards)
          _SearchPreviewRow(card: card, onSelected: onSelected),
      ],
    );
  }
}

class _SearchPreviewRow extends StatelessWidget {
  const _SearchPreviewRow({
    required this.card,
    required this.onSelected,
  });

  final PokemonCard card;
  final ValueChanged<PokemonCard> onSelected;

  @override
  Widget build(BuildContext context) {
    final isProduct = card.itemKind == 'product';
    final kindLabel = isProduct ? card.type : 'Singles';
    final title = _previewTitle(card);
    return InkWell(
      onTap: () => onSelected(card),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF1E2A4A))),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 50,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: const Color(0xFF111936),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: CachedNetworkImage(
                imageUrl: card.previewImageUrl,
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => const Icon(
                  Icons.style,
                  color: Color(0xFFFACC15),
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    card.set,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF93A4C8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  kindLabel,
                  style: const TextStyle(
                    color: Color(0xFF93A4C8),
                    fontSize: 12,
                  ),
                ),
                Text(
                  isProduct
                      ? 'Product'
                      : card.rarity == 'Card'
                          ? 'View card'
                          : card.rarity,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFACC15),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _previewTitle(PokemonCard card) {
    return _cardTitleWithNumber(card);
  }
}

void _goBackOr(BuildContext context, String fallbackPath) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  context.go(fallbackPath);
}

class _CardCarouselSection extends StatelessWidget {
  const _CardCarouselSection({
    required this.title,
    required this.cards,
    this.subtitle,
    this.isLoading = false,
  });

  final String title;
  final String? subtitle;
  final List<PokemonCard> cards;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty && !isLoading) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(title: title, subtitle: subtitle),
        const SizedBox(height: 14),
        if (isLoading)
          const _RecentViewsLoadingStrip()
        else
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) => SizedBox(
                width: 360,
                child: _FeaturedCard(card: cards[index]),
              ),
            ),
          ),
      ],
    );
  }
}

class _RecentViewsLoadingStrip extends StatelessWidget {
  const _RecentViewsLoadingStrip();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 178,
      child: Row(
        children: List.generate(
          2,
          (index) => Expanded(
            child: Container(
              margin: EdgeInsets.only(right: index == 0 ? 14 : 0),
              decoration: BoxDecoration(
                color: const Color(0xFF111936),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Center(
                child: Container(
                  width: 160,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0x22FACC15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MarketHeader extends StatelessWidget {
  const _MarketHeader();

  @override
  Widget build(BuildContext context) {
    return const _SectionHeading(
      title: 'Card spotlight',
      subtitle:
          'Dynamically refreshed marketplace picks based on recent signals.',
    );
  }
}

class _SearchResultsHeader extends StatelessWidget {
  const _SearchResultsHeader({required this.query, required this.count});

  final String query;
  final int count;

  @override
  Widget build(BuildContext context) {
    return _SectionHeading(
      title: query.isEmpty ? 'All marketplace results' : 'Results for "$query"',
    );
  }
}

class _SearchResultSection extends StatelessWidget {
  const _SearchResultSection({required this.title, required this.cards});

  final String title;
  final List<PokemonCard> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          title: title,
          subtitle: cards.isEmpty ? null : '${cards.length} matching $title.',
        ),
        const SizedBox(height: 16),
        _MarketplaceGrid(
          cards: cards,
          emptyTitle: title == 'Products'
              ? 'Products are unavailable'
              : 'No singles match these filters',
          emptyBody: title == 'Products'
              ? 'No sealed products are available for this search yet.'
              : 'Try searching for a broader card name, set, or rarity.',
        ),
      ],
    );
  }
}

class _MarketplaceGrid extends StatelessWidget {
  final List<PokemonCard> cards;
  final String emptyTitle;
  final String emptyBody;

  const _MarketplaceGrid({
    required this.cards,
    this.emptyTitle = 'No cards match these filters',
    this.emptyBody =
        'Try clearing filters or searching for a broader set, rarity or Pokémon name.',
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return _EmptyMarket(title: emptyTitle, body: emptyBody);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width > 1120
            ? 4
            : width > 830
                ? 3
                : width > 560
                    ? 2
                    : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: columns == 1 ? 0.86 : 0.68,
          ),
          itemBuilder: (context, index) => _MarketCard(card: cards[index]),
        );
      },
    );
  }
}

class _MarketCard extends ConsumerWidget {
  final PokemonCard card;

  const _MarketCard({required this.card});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final isFavorite = favorites.isFavorite(card.id);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        onTap: () {
          ref.read(cardProvider.notifier).recordCardInteraction(
                card,
                'click',
                source: 'market_grid',
              );
          ref.read(cardProvider.notifier).clearFilters();
          context.go('/card/${card.id}');
        },
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _CardImageFrame(
                      imageUrl: card.imageUrl,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
                      padding: const EdgeInsets.all(14),
                      fallbackSize: 54,
                    ),
                  ),
                  if (card.rarity.isNotEmpty && card.rarity != 'Card')
                    Positioned(
                        top: 12,
                        left: 12,
                        child: _Badge(
                            text: card.rarity, color: const Color(0xFFFACC15))),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: IconButton.filledTonal(
                      onPressed: () => ref
                          .read(favoritesProvider.notifier)
                          .toggleFavorite(card.id),
                      icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _cardTitleWithNumber(card),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    card.set,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF93A4C8)),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MiniSignal(
                          icon: Icons.star,
                          text: card.rating.toStringAsFixed(1)),
                      _MiniSignal(
                        icon: Icons.inventory_2_outlined,
                        text: card.stock > 0
                            ? '${card.stock} in stock'
                            : 'Out of stock',
                      ),
                      if (card.isHolo)
                        const _MiniSignal(
                            icon: Icons.auto_awesome, text: 'Holo'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _marketPriceLabel(card),
                          style: TextStyle(
                            color: const Color(0xFFFACC15),
                            fontSize: card.stock > 0 ? 22 : 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: () {
                          ref.read(cardProvider.notifier).recordCardInteraction(
                                card,
                                'click',
                                source: 'market_grid_button',
                              );
                          ref.read(cardProvider.notifier).clearFilters();
                          context.go('/card/${card.id}');
                        },
                        child: const Text('View'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedCard extends ConsumerWidget {
  final PokemonCard card;

  const _FeaturedCard({required this.card});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF111B3F), Color(0xFF0B1020)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        onTap: () {
          ref.read(cardProvider.notifier).recordCardInteraction(
                card,
                'click',
                source: 'market_carousel',
              );
          ref.read(cardProvider.notifier).clearFilters();
          context.go('/card/${card.id}');
        },
        borderRadius: BorderRadius.circular(18),
        child: Row(
          children: [
            _CardImageFrame(
              imageUrl: card.imageUrl,
              width: 126,
              height: 170,
              borderRadius: BorderRadius.circular(16),
              padding: const EdgeInsets.all(6),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (card.itemKind == 'product' ||
                      (card.rarity.isNotEmpty && card.rarity != 'Card')) ...[
                    _Badge(
                      text:
                          card.itemKind == 'product' ? card.type : card.rarity,
                      color: const Color(0xFF38BDF8),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    _cardTitleWithNumber(card),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(card.set,
                      style: const TextStyle(color: Color(0xFFB8C4E6))),
                  const SizedBox(height: 10),
                  Text(
                    _marketPriceLabel(card),
                    style: const TextStyle(
                      color: Color(0xFFFACC15),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _marketPriceLabel(PokemonCard card) {
  return card.stock > 0 ? formatPkn(card.price) : 'Out of stock';
}

String _cardTitleWithNumber(PokemonCard card) {
  final number = card.number.trim();
  if (number.isEmpty) {
    return card.name;
  }
  return '${card.name} #$number';
}

class _CardImageFrame extends StatelessWidget {
  const _CardImageFrame({
    required this.imageUrl,
    required this.borderRadius,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(6),
    this.fallbackSize = 24,
  });

  final String imageUrl;
  final BorderRadius borderRadius;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final double fallbackSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: borderRadius,
      ),
      clipBehavior: Clip.none,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        errorWidget: (_, __, ___) => Icon(
          Icons.style,
          color: const Color(0xFFFACC15),
          size: fallbackSize,
        ),
      ),
    );
  }
}

class _LoadingMarket extends StatelessWidget {
  const _LoadingMarket();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;

  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return _Notice(title: 'Marketplace unavailable', body: error);
  }
}

class _EmptyMarket extends StatelessWidget {
  const _EmptyMarket({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return _Notice(title: title, body: body);
  }
}

class _Notice extends StatelessWidget {
  final String title;
  final String body;

  const _Notice({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xCC111936),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          const Icon(Icons.search_off, color: Color(0xFFFACC15), size: 42),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20)),
          const SizedBox(height: 8),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFB8C4E6))),
        ],
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  final IconData icon;
  final String label;

  const _RoundControl({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFACC15)),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionHeading({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: const TextStyle(color: Color(0xFF93A4C8), height: 1.4),
          ),
        ],
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
            fontSize: 12),
      ),
    );
  }
}

class _MiniSignal extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniSignal({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF38BDF8), size: 15),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(color: Color(0xFFB8C4E6), fontSize: 12)),
      ],
    );
  }
}

class _MarketFilter {
  final String label;
  final String? query;
  final double? maxPrice;

  const _MarketFilter({
    required this.label,
    this.query,
    this.maxPrice,
  });
}

List<PokemonCard> _rankCardsByRecentViews(
  List<PokemonCard> cards,
  List<RecentCardView> recentViews,
) {
  if (recentViews.isEmpty || cards.isEmpty) {
    return cards;
  }

  final recentIds = <String, int>{};
  final recentNames = <String, int>{};
  final recentExpansions = <String, int>{};
  for (var index = 0; index < recentViews.length; index++) {
    final view = recentViews[index];
    final weight = recentViews.length - index;
    recentIds[view.cardId] = weight * 1000;
    final name = _normalizePersonalizationKey(view.name);
    if (name.isNotEmpty) {
      recentNames[name] = math.max(recentNames[name] ?? 0, weight * 80);
    }
    final expansion = _normalizePersonalizationKey(view.expansion);
    if (expansion.isNotEmpty) {
      recentExpansions[expansion] =
          math.max(recentExpansions[expansion] ?? 0, weight * 35);
    }
  }

  final ranked = [...cards]..sort((a, b) {
      final score = _recentViewScore(
        b,
        recentIds,
        recentNames,
        recentExpansions,
      ).compareTo(
        _recentViewScore(a, recentIds, recentNames, recentExpansions),
      );
      if (score != 0) {
        return score;
      }
      return a.name.compareTo(b.name);
    });
  return ranked;
}

int _recentViewScore(
  PokemonCard card,
  Map<String, int> ids,
  Map<String, int> names,
  Map<String, int> expansions,
) {
  final name = _normalizePersonalizationKey(card.name);
  final expansion = _normalizePersonalizationKey(card.set);
  return (ids[card.id] ?? 0) +
      (names[name] ?? 0) +
      (expansions[expansion] ?? 0);
}

String _normalizePersonalizationKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

class _MarketplaceSections {
  const _MarketplaceSections({
    required this.recentlySeen,
    required this.bestSellers,
    required this.featured,
  });

  final List<PokemonCard> recentlySeen;
  final List<PokemonCard> bestSellers;
  final List<PokemonCard> featured;

  factory _MarketplaceSections.fromCards(
    List<PokemonCard> cards, {
    MarketplaceHomeSections? cachedSections,
    List<RecentCardView> recentViews = const [],
  }) {
    final personalized = _rankCardsByRecentViews(cards, recentViews);
    final recentCards = _cardsForRecentViews(recentViews, cards);
    if (cachedSections != null) {
      final byId = {for (final card in cards) card.id: card};
      final recentlySeen = _cardsForIds(cachedSections.recentlySeenIds, byId);
      final bestSellers = _cardsForIds(cachedSections.bestSellerIds, byId);
      final featured = _cardsForIds(cachedSections.featuredIds, byId);
      if (recentlySeen.isNotEmpty ||
          bestSellers.isNotEmpty ||
          featured.isNotEmpty) {
        return _MarketplaceSections(
          recentlySeen: recentCards,
          bestSellers: bestSellers.isNotEmpty
              ? bestSellers
              : personalized.take(9).toList(),
          featured:
              featured.isNotEmpty ? featured : personalized.take(9).toList(),
        );
      }
    }

    final byPrice = [...personalized]
      ..sort((a, b) => b.price.compareTo(a.price));
    final byHolo = personalized
        .where((card) =>
            card.isHolo ||
            card.isFoil ||
            card.rarity.toLowerCase().contains('rare'))
        .toList();
    final featured = byHolo.isNotEmpty ? byHolo : personalized;
    return _MarketplaceSections(
      recentlySeen: recentCards,
      bestSellers: byPrice.take(9).toList(),
      featured: featured.take(9).toList(),
    );
  }

  static List<PokemonCard> _cardsForIds(
    List<String> ids,
    Map<String, PokemonCard> byId,
  ) {
    return ids.map((id) => byId[id]).whereType<PokemonCard>().take(9).toList();
  }

  static List<PokemonCard> _cardsForRecentViews(
    List<RecentCardView> views,
    List<PokemonCard> cards,
  ) {
    final byId = {for (final card in cards) card.id: card};
    final cardsByNameAndSet = <String, PokemonCard>{};
    for (final card in cards) {
      cardsByNameAndSet.putIfAbsent(
        '${_normalizePersonalizationKey(card.name)}|${_normalizePersonalizationKey(card.set)}',
        () => card,
      );
    }
    return views
        .map((view) =>
            byId[view.cardId] ??
            cardsByNameAndSet[
                '${_normalizePersonalizationKey(view.name)}|${_normalizePersonalizationKey(view.expansion)}'] ??
            _cardFromRecentView(view))
        .whereType<PokemonCard>()
        .take(9)
        .toList();
  }

  static PokemonCard _cardFromRecentView(RecentCardView view) {
    return PokemonCard(
      id: view.cardId,
      name: view.name,
      imageUrl: view.imageUrl,
      previewImageUrl: view.previewImageUrl,
      rarity: 'Card',
      type: 'Trading card',
      hp: 0,
      attacks: const [],
      price: (1000 + (_recentViewSeed(view.cardId) % 120000)).toDouble(),
      description: 'Saved from your recent marketplace views.',
      set: view.expansion,
      number: view.number,
      artist: '',
      stock: 0,
      rating: 0,
      reviewCount: 0,
      isFoil: false,
      isHolo: false,
      releaseDate: view.viewedAt,
      tags: [view.expansion, 'Card', 'Trading card', 'single', 'card'],
      condition: 'NM',
      isGraded: false,
      itemKind: 'single',
      productType: 'card',
    );
  }

  static int _recentViewSeed(String value) {
    return value.codeUnits.fold<int>(0, (sum, unit) => sum + unit * 31);
  }
}

class _SuggestedCategories extends StatelessWidget {
  const _SuggestedCategories();

  @override
  Widget build(BuildContext context) {
    const categories = [
      _CategoryCard(
        title: 'Booster boxes',
        query: '',
        productType: 'booster_box',
        card: _CategoryCardData(
          id: '249796',
          name: 'Pokemon Card 151 Booster Box',
          imageUrl:
              'https://cdn.pokoin.com/249796_pokemon-card-151-booster-box-pokemon-card-151.jpg',
          set: 'Pokemon Card 151',
          number: '',
          itemKind: 'product',
          productType: 'booster_box',
        ),
      ),
      _CategoryCard(
        title: 'Boosters',
        query: '',
        productType: 'booster_pack',
        card: _CategoryCardData(
          id: '258625',
          name: '151 Booster',
          imageUrl: 'https://cdn.pokoin.com/258625_151-booster-151.jpg',
          set: '151',
          number: '258625',
          itemKind: 'product',
          productType: 'booster_pack',
        ),
      ),
      _CategoryCard(
        title: 'Graded candidates',
        query: 'special illustration rare',
        productType: 'card',
        card: _CategoryCardData(
          id: '274416',
          name: 'Mew ex',
          imageUrl:
              'https://cdn.pokoin.com/274416_mew-ex-special-illustration-rare-232-091-paldean-fates.jpg',
          set: 'Paldean Fates',
          number: 'Special Illustration Rare | 232/091',
          itemKind: 'single',
          productType: 'card',
        ),
      ),
    ];

    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          title: 'Suggested categories',
          subtitle: 'Quick entry points for common CardTrader-style browsing.',
        ),
        SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: categories,
        ),
      ],
    );
  }
}

class _CategoryCardData {
  const _CategoryCardData({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.set,
    required this.number,
    required this.itemKind,
    required this.productType,
  });

  final String id;
  final String name;
  final String imageUrl;
  final String set;
  final String number;
  final String itemKind;
  final String productType;
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.title,
    required this.query,
    required this.productType,
    required this.card,
  });

  final String title;
  final String query;
  final String productType;
  final _CategoryCardData card;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: InkWell(
        onTap: () => context.go(
          Uri(
            path: '/marketplace/search',
            queryParameters: {
              if (query.isNotEmpty) 'q': query,
              'productType': productType,
            },
          ).toString(),
        ),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xCC0B1024),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              _CardImageFrame(
                imageUrl: card.imageUrl,
                width: 86,
                height: 86,
                borderRadius: BorderRadius.circular(12),
                padding: const EdgeInsets.all(5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'You might like: ${card.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFB8C4E6)),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Find out more',
                      style: TextStyle(
                        color: Color(0xFFFACC15),
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFFFACC15),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
