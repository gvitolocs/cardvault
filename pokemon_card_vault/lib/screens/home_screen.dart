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
import '../constants/project_links.dart';
import '../utils/browser_capabilities.dart';
import '../utils/card_url.dart';
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
    this.searchLanguage = 'en',
  });

  final String initialQuery;
  final String? expansion;
  final String? productType;
  final String searchLanguage;

  @override
  ConsumerState<MarketplaceSearchScreen> createState() =>
      _MarketplaceSearchScreenState();
}

class _MarketplaceSearchScreenState
    extends ConsumerState<MarketplaceSearchScreen> {
  late final TextEditingController _controller;
  final FocusNode _searchFocusNode = FocusNode();
  final CardService _cardService = CardService();
  List<PokemonCard> _results = const [];
  bool _isSearching = false;
  String? _error;
  String? _selectedExpansion;
  String? _selectedRarity;
  late String _searchLanguage;
  int _requestId = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _searchLanguage = _normalizeSearchLanguage(widget.searchLanguage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runSearch(widget.initialQuery);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MarketplaceSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery ||
        oldWidget.expansion != widget.expansion ||
        oldWidget.productType != widget.productType ||
        oldWidget.searchLanguage != widget.searchLanguage) {
      _controller.text = widget.initialQuery;
      _selectedExpansion = null;
      _selectedRarity = null;
      _searchLanguage = _normalizeSearchLanguage(widget.searchLanguage);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _runSearch(widget.initialQuery);
        }
      });
    }
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
                      searchLanguage: _searchLanguage,
                    )
              : normalizedQuery.length < 2
                  ? await _cardService.getAllCards()
                  : await _cardService.searchMarketplaceCards(
                      normalizedQuery,
                      limit: 240,
                      searchLanguage: _searchLanguage,
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
    final cartState = ref.watch(cartProvider);
    final cachedBalance = ref.watch(cachedPknBalanceProvider).valueOrNull;
    final balance =
        ref.watch(pknBalanceProvider).valueOrNull ?? cachedBalance ?? 0;
    final filteredResults = _applySearchPageFilters(_results);
    final isProductCategory =
        productType != null && productType.isNotEmpty && productType != 'card';
    final isSingleCategory = productType == 'card';
    final compactTopBar = MediaQuery.sizeOf(context).width < 760;
    final title = expansion != null && expansion.isNotEmpty
        ? 'Cards in $expansion'
        : productType != null && productType.isNotEmpty
            ? _productTypeTitle(productType)
            : 'Marketplace search';
    final singles =
        filteredResults.where((card) => card.itemKind != 'product').toList();
    final products =
        filteredResults.where((card) => card.itemKind == 'product').toList();
    final content = [
      _SearchResultsHeader(query: query, count: filteredResults.length),
      const SizedBox(height: 24),
      if (!isProductCategory) ...[
        _SearchResultSection(
          title: isSingleCategory ? 'Graded candidates' : 'Singles',
          cards: singles,
        ),
        const SizedBox(height: 28),
      ],
      if (!isSingleCategory)
        _SearchResultSection(
          title: isProductCategory ? title : 'Products',
          cards: products,
        ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: const Color(0xE60A1026),
        titleSpacing: 16,
        title: Row(
          children: [
            _MarketplaceLogoButton(onTap: () => context.go('/marketplace')),
            const SizedBox(width: 14),
            Expanded(
              child: _MarketplaceTopSearch(
                controller: _controller,
                focusNode: _searchFocusNode,
                query: _controller.text,
                isSearching: _isSearching,
                previews: _results.take(15).toList(),
                hintText: 'Search cards, sets, products...',
                onChanged: (value) {
                  setState(() {});
                  _onSearchChanged(value);
                },
                onSelected: (card) => context.go(cardDetailPath(card)),
                onShowAll: (query) => context.go(
                  Uri(
                    path: '/marketplace/search',
                    queryParameters: {
                      if (query.trim().isNotEmpty) 'q': query.trim(),
                      if (productType?.isNotEmpty == true)
                        'productType': productType!,
                      if (_searchLanguage != 'en') 'lang': _searchLanguage,
                    },
                  ).toString(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SearchLanguageMenu(
              value: _searchLanguage,
              onChanged: (language) {
                setState(() => _searchLanguage = language);
                _runSearch(_controller.text);
              },
            ),
          ],
        ),
        actions: [
          if (!compactTopBar) ...[
            TextButton(
                onPressed: () => context.go('/'), child: const Text('Home')),
            TextButton(
                onPressed: () => context.go('/scan'),
                child: const Text('Scan')),
            TextButton(
                onPressed: () => context.go('/marketplace/signal'),
                child: const Text('Signal')),
          ],
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final filters = _SearchFilterPanel(
                productType: productType,
                selectedExpansion: _selectedExpansion,
                selectedRarity: _selectedRarity,
                expansionCounts: _facetCounts(
                  _results,
                  (card) => card.set,
                ),
                rarityCounts: _facetCounts(
                  _results.where((card) => card.itemKind != 'product'),
                  (card) => card.rarity,
                ),
                onExpansionChanged: (value) =>
                    setState(() => _selectedExpansion = value),
                onRarityChanged: (value) =>
                    setState(() => _selectedRarity = value),
                onClear: () => setState(() {
                  _selectedExpansion = null;
                  _selectedRarity = null;
                }),
              );
              final main = ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  if (_isSearching)
                    const LinearProgressIndicator(color: Color(0xFFFACC15)),
                  if (_error != null) ...[
                    Text(
                      'Search failed: $_error',
                      style: const TextStyle(color: Color(0xFFFCA5A5)),
                    ),
                    const SizedBox(height: 14),
                  ],
                  ...content,
                ],
              );
              if (constraints.maxWidth < 880) {
                return ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    filters,
                    const SizedBox(height: 18),
                    if (_isSearching)
                      const LinearProgressIndicator(color: Color(0xFFFACC15)),
                    if (_error != null) ...[
                      Text(
                        'Search failed: $_error',
                        style: const TextStyle(color: Color(0xFFFCA5A5)),
                      ),
                      const SizedBox(height: 14),
                    ],
                    ...content,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 300,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 22, 0, 22),
                      child: filters,
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(child: main),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<PokemonCard> _applySearchPageFilters(List<PokemonCard> cards) {
    return cards.where((card) {
      final selectedExpansion = _selectedExpansion;
      if (selectedExpansion != null &&
          selectedExpansion.isNotEmpty &&
          card.set != selectedExpansion) {
        return false;
      }
      final selectedRarity = _selectedRarity;
      if (selectedRarity != null &&
          selectedRarity.isNotEmpty &&
          card.rarity != selectedRarity) {
        return false;
      }
      return true;
    }).toList();
  }

  Map<String, int> _facetCounts(
    Iterable<PokemonCard> cards,
    String Function(PokemonCard card) valueForCard,
  ) {
    final counts = <String, int>{};
    for (final card in cards) {
      final value = valueForCard(card).trim();
      if (value.isEmpty || value == 'Card') {
        continue;
      }
      counts[value] = (counts[value] ?? 0) + 1;
    }
    return Map.fromEntries(
      counts.entries.toList()
        ..sort((a, b) {
          final count = b.value.compareTo(a.value);
          if (count != 0) {
            return count;
          }
          return a.key.compareTo(b.key);
        }),
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
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 12;
  int _visibleCount = _pageSize;

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
    _searchFocusNode.dispose();
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
    final compactTopBar = MediaQuery.sizeOf(context).width < 760;

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xE60A1026),
            titleSpacing: 16,
            title: Row(
              children: [
                _MarketplaceLogoButton(onTap: () => context.go('/marketplace')),
                const SizedBox(width: 14),
                Expanded(
                  child: _MarketplaceTopSearch(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    query: cardState.previewQuery,
                    isSearching: cardState.isSearchingPreviews,
                    previews: cardState.searchPreviews.take(15).toList(),
                    hintText: 'Search cards, sets, products...',
                    onChanged: (value) {
                      ref.read(cardProvider.notifier).searchPreviewsOnly(value);
                    },
                    onSelected: (card) {
                      ref.read(cardProvider.notifier).recordCardInteraction(
                            card,
                            'click',
                            source: 'search_preview',
                          );
                      _resetTransientSearch();
                      context.go(cardDetailPath(card));
                    },
                    onShowAll: (query) => context.go(
                      Uri(
                        path: '/marketplace/search',
                        queryParameters: {
                          'q': query,
                          if (cardState.searchLanguage != 'en')
                            'lang': cardState.searchLanguage,
                        },
                      ).toString(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SearchLanguageMenu(
                  value: cardState.searchLanguage,
                  onChanged: (language) => ref
                      .read(cardProvider.notifier)
                      .setSearchLanguage(language),
                ),
              ],
            ),
            actions: [
              if (!compactTopBar) ...[
                TextButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Home')),
                TextButton(
                    onPressed: () => context.go('/scan'),
                    child: const Text('Scan')),
                TextButton(
                    onPressed: () => context.go('/marketplace/signal'),
                    child: const Text('Signal')),
              ],
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
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cardState.isLoading)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1220),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 22),
                          child: _LoadingMarket(),
                        ),
                      ),
                    )
                  else if (cardState.error != null)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1220),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          child: _ErrorState(error: cardState.error!),
                        ),
                      ),
                    )
                  else ...[
                    if (sections.recentlySeen.isNotEmpty ||
                        recentViewsState.isLoading) ...[
                      _CardCarouselSection(
                        title: 'Recently seen',
                        cards: sections.recentlySeen,
                        isLoading: recentViewsState.isLoading &&
                            sections.recentlySeen.isEmpty,
                      ),
                      const SizedBox(height: 24),
                    ],
                    _CardCarouselSection(
                      title: 'Best sellers',
                      cards: sections.bestSellers,
                    ),
                    const SizedBox(height: 24),
                    _CardCarouselSection(
                      title: 'Featured',
                      cards: sections.featured,
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1220),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _SuggestedCategories(),
                              const SizedBox(height: 28),
                              const _MarketHeader(),
                              const SizedBox(height: 16),
                              _MarketplaceGrid(cards: visibleCards),
                              const SizedBox(height: 18),
                              if (visibleCards.length <
                                  personalizedCards.length)
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
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

class _SearchLanguageMenu extends StatelessWidget {
  const _SearchLanguageMenu({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  static const _languages = <String, String>{
    'en': 'EN',
    'it': 'IT',
    'fr': 'FR',
    'de': 'DE',
    'es': 'ES',
    'ja': 'JA',
  };

  @override
  Widget build(BuildContext context) {
    final normalized = _normalizeSearchLanguage(value);
    return PopupMenuButton<String>(
      tooltip: 'Search language',
      initialValue: normalized,
      onSelected: onChanged,
      color: const Color(0xFF111936),
      itemBuilder: (context) => [
        for (final entry in _languages.entries)
          PopupMenuItem(
            value: entry.key,
            child: Text(
              entry.value,
              style: TextStyle(
                color: entry.key == normalized
                    ? const Color(0xFFFACC15)
                    : const Color(0xFFE2E8F0),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
      ],
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF111936),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        alignment: Alignment.center,
        child: Text(
          _languages[normalized] ?? 'EN',
          style: const TextStyle(
            color: Color(0xFFFACC15),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _MarketplaceLogoButton extends StatelessWidget {
  const _MarketplaceLogoButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Image.network(
          ProjectLinks.logo,
          width: 34,
          height: 34,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.token,
            color: Color(0xFFFACC15),
          ),
        ),
      ),
    );
  }
}

String _normalizeSearchLanguage(String value) {
  switch (value.trim().toLowerCase()) {
    case 'it':
    case 'fr':
    case 'de':
    case 'es':
    case 'ja':
      return value.trim().toLowerCase();
    case 'jp':
      return 'ja';
    default:
      return 'en';
  }
}

class _MarketplaceTopSearch extends StatefulWidget {
  const _MarketplaceTopSearch({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.isSearching,
    required this.previews,
    required this.hintText,
    required this.onChanged,
    required this.onSelected,
    required this.onShowAll,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final bool isSearching;
  final List<PokemonCard> previews;
  final String hintText;
  final ValueChanged<String> onChanged;
  final ValueChanged<PokemonCard> onSelected;
  final ValueChanged<String> onShowAll;

  @override
  State<_MarketplaceTopSearch> createState() => _MarketplaceTopSearchState();
}

class _MarketplaceTopSearchState extends State<_MarketplaceTopSearch> {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  double _overlayWidth = 520;
  Timer? _removeOverlayTimer;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_syncOverlay);
  }

  @override
  void didUpdateWidget(covariant _MarketplaceTopSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_syncOverlay);
      widget.focusNode.addListener(_syncOverlay);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverlay());
  }

  @override
  void dispose() {
    _removeOverlayTimer?.cancel();
    widget.focusNode.removeListener(_syncOverlay);
    _removeOverlay();
    super.dispose();
  }

  void _syncOverlay() {
    if (!mounted) {
      return;
    }
    final shouldShow =
        widget.focusNode.hasFocus && widget.query.trim().length >= 2;
    if (!shouldShow) {
      _removeOverlayTimer?.cancel();
      _removeOverlayTimer = Timer(
        const Duration(milliseconds: 140),
        _removeOverlay,
      );
      return;
    }
    _removeOverlayTimer?.cancel();
    final fieldContext = _fieldKey.currentContext;
    final fieldSize = fieldContext?.size;
    if (fieldSize != null) {
      _overlayWidth = fieldSize.width;
    }
    if (_overlayEntry == null) {
      _overlayEntry = OverlayEntry(builder: _buildOverlay);
      Overlay.of(context).insert(_overlayEntry!);
    } else {
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _selectPreview(PokemonCard card) {
    _removeOverlayTimer?.cancel();
    _removeOverlay();
    widget.focusNode.unfocus();
    widget.onSelected(card);
  }

  void _showAll(String query) {
    _removeOverlayTimer?.cancel();
    _removeOverlay();
    widget.focusNode.unfocus();
    widget.onShowAll(query);
  }

  void _removeOverlay() {
    _removeOverlayTimer?.cancel();
    _removeOverlayTimer = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildOverlay(BuildContext context) {
    return CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, 8),
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: _overlayWidth,
          child: _SearchPreviewPanel(
            query: widget.query,
            cards: widget.previews,
            isSearching: widget.isSearching,
            onSelected: _selectPreview,
            onShowAll: _showAll,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        key: _fieldKey,
        height: 42,
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          onChanged: widget.onChanged,
          onTap: _syncOverlay,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          textInputAction: TextInputAction.search,
          onSubmitted: widget.onShowAll,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, color: Color(0xFFFACC15)),
            suffixIcon: widget.isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFFACC15),
                      ),
                    ),
                  )
                : widget.controller.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          widget.controller.clear();
                          widget.onChanged('');
                          _removeOverlay();
                        },
                        icon: const Icon(Icons.close,
                            color: Color(0xFF93A4C8), size: 18),
                      )
                    : null,
            hintText: widget.hintText,
            hintStyle: const TextStyle(color: Color(0xFF93A4C8)),
            filled: true,
            fillColor: const Color(0xFF111936),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
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

class _CardCarouselSection extends StatefulWidget {
  const _CardCarouselSection({
    required this.title,
    required this.cards,
    this.isLoading = false,
  });

  final String title;
  final List<PokemonCard> cards;
  final bool isLoading;

  @override
  State<_CardCarouselSection> createState() => _CardCarouselSectionState();
}

class _CardCarouselSectionState extends State<_CardCarouselSection> {
  final ScrollController _scrollController = ScrollController();
  bool _canScrollBack = false;
  bool _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncArrowVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncArrowVisibility());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncArrowVisibility);
    _scrollController.dispose();
    super.dispose();
  }

  void _syncArrowVisibility() {
    if (!_scrollController.hasClients) {
      if (_canScrollBack || _canScrollForward) {
        setState(() {
          _canScrollBack = false;
          _canScrollForward = false;
        });
      }
      return;
    }
    final position = _scrollController.position;
    final canScrollBack = position.pixels > position.minScrollExtent + 2;
    final canScrollForward = position.pixels < position.maxScrollExtent - 2;
    if (canScrollBack == _canScrollBack &&
        canScrollForward == _canScrollForward) {
      return;
    }
    setState(() {
      _canScrollBack = canScrollBack;
      _canScrollForward = canScrollForward;
    });
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty && !widget.isLoading) {
      return const SizedBox.shrink();
    }
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 900;
    final useDesktopControls = isDesktop && hasDesktopPointer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncArrowVisibility());
    final contentInset = screenWidth >= 1264 ? (screenWidth - 1220) / 2 : 22.0;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: contentInset),
            child: _SectionHeading(title: widget.title),
          ),
          const SizedBox(height: 14),
          if (widget.isLoading)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: contentInset),
              child: const _RecentViewsLoadingStrip(),
            )
          else
            SizedBox(
              height: 210,
              child: Stack(
                children: [
                  ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    physics: useDesktopControls
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.cards.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (context, index) => SizedBox(
                      width: 360,
                      child: _FeaturedCard(card: widget.cards[index]),
                    ),
                  ),
                  if (useDesktopControls && widget.cards.length > 2) ...[
                    if (_canScrollBack)
                      Positioned(
                        left: 16,
                        top: 72,
                        child: _CarouselArrowButton(
                          icon: Icons.chevron_left,
                          label: 'Previous cards',
                          onPressed: () => _scrollBy(-748),
                        ),
                      ),
                    if (_canScrollForward)
                      Positioned(
                        right: 16,
                        top: 72,
                        child: _CarouselArrowButton(
                          icon: Icons.chevron_right,
                          label: 'Next cards',
                          onPressed: () => _scrollBy(748),
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CarouselArrowButton extends StatelessWidget {
  const _CarouselArrowButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: const Color(0xEE0B1024),
        shape: const CircleBorder(),
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.28),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFACC15).withValues(alpha: 0.45),
              ),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFFACC15),
              size: 28,
            ),
          ),
        ),
      ),
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

class _SearchFilterPanel extends StatelessWidget {
  const _SearchFilterPanel({
    required this.productType,
    required this.selectedExpansion,
    required this.selectedRarity,
    required this.expansionCounts,
    required this.rarityCounts,
    required this.onExpansionChanged,
    required this.onRarityChanged,
    required this.onClear,
  });

  final String? productType;
  final String? selectedExpansion;
  final String? selectedRarity;
  final Map<String, int> expansionCounts;
  final Map<String, int> rarityCounts;
  final ValueChanged<String?> onExpansionChanged;
  final ValueChanged<String?> onRarityChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasFilters = selectedExpansion?.isNotEmpty == true ||
        selectedRarity?.isNotEmpty == true ||
        productType?.isNotEmpty == true;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'APPLIED FILTERS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const _FilterChipLabel(label: 'Pokémon'),
                    if (productType?.isNotEmpty == true)
                      _FilterChipLabel(label: _productTypeFilterLabel()),
                    if (selectedExpansion?.isNotEmpty == true)
                      _FilterChipLabel(label: selectedExpansion!),
                    if (selectedRarity?.isNotEmpty == true)
                      _FilterChipLabel(label: selectedRarity!),
                  ],
                ),
              ],
            ),
          ),
          _FilterDivider(),
          _FacetSection(
            title: 'EXPANSION',
            placeholder: 'Expansion',
            selectedValue: selectedExpansion,
            counts: expansionCounts,
            onChanged: onExpansionChanged,
          ),
          _FilterDivider(),
          _FacetSection(
            title: 'RARITY',
            placeholder: 'Rarity',
            selectedValue: selectedRarity,
            counts: rarityCounts,
            onChanged: onRarityChanged,
          ),
          _FilterDivider(),
          Padding(
            padding: const EdgeInsets.all(18),
            child: FilledButton(
              onPressed: hasFilters ? onClear : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1F2A44),
                disabledBackgroundColor: const Color(0x661F2A44),
                foregroundColor: Colors.white,
                disabledForegroundColor: const Color(0xFF64748B),
              ),
              child: const Text('Clear filters'),
            ),
          ),
        ],
      ),
    );
  }

  String _productTypeFilterLabel() {
    switch (productType) {
      case 'booster_box':
        return 'Booster boxes';
      case 'booster_pack':
        return 'Boosters';
      case 'card':
        return 'Singles';
      default:
        return productType ?? '';
    }
  }
}

class _FacetSection extends StatelessWidget {
  const _FacetSection({
    required this.title,
    required this.placeholder,
    required this.selectedValue,
    required this.counts,
    required this.onChanged,
  });

  final String title;
  final String placeholder;
  final String? selectedValue;
  final Map<String, int> counts;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final entries = counts.entries.take(6).toList();
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 42,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF111936),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Text(
              selectedValue?.isNotEmpty == true ? selectedValue! : placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selectedValue?.isNotEmpty == true
                    ? Colors.white
                    : const Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in entries)
            _FacetOption(
              label: entry.key,
              count: entry.value,
              selected: entry.key == selectedValue,
              onTap: () =>
                  onChanged(entry.key == selectedValue ? null : entry.key),
            ),
        ],
      ),
    );
  }
}

class _FacetOption extends StatelessWidget {
  const _FacetOption({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? const Color(0xFFFACC15)
                      : const Color(0xFF94A3B8),
                  width: selected ? 5 : 1.4,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFE5E7EB)),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '($count)',
              style: const TextStyle(color: Color(0xFF93A4C8)),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChipLabel extends StatelessWidget {
  const _FilterChipLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _FilterDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: Colors.white.withValues(alpha: 0.08));
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
          context.go(cardDetailPath(card));
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
                      fallbackImageUrl: card.previewImageUrl,
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
                          context.go(cardDetailPath(card));
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
          context.go(cardDetailPath(card));
        },
        borderRadius: BorderRadius.circular(18),
        child: Row(
          children: [
            _CardImageFrame(
              imageUrl: card.imageUrl,
              fallbackImageUrl: card.previewImageUrl,
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
  final number = _displayCollectorNumber(card.number);
  if (number.isEmpty) {
    return card.name;
  }
  return '${card.name} #$number';
}

String _displayCollectorNumber(String rawNumber) {
  final text = rawNumber.trim();
  if (text.isEmpty) {
    return '';
  }
  final parts = text
      .split(RegExp(r'\s*(?:\||•|-{2,}|–|—)\s*'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  for (final part in parts.reversed) {
    if (RegExp(r'\d+\s*/\s*\d+').hasMatch(part)) {
      return part.replaceAll(RegExp(r'\s+'), '');
    }
  }
  for (final part in parts.reversed) {
    if (RegExp(r'\d').hasMatch(part)) {
      return part;
    }
  }
  return text;
}

class _CardImageFrame extends StatelessWidget {
  const _CardImageFrame({
    required this.imageUrl,
    required this.borderRadius,
    this.fallbackImageUrl,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(6),
    this.fallbackSize = 24,
  });

  final String imageUrl;
  final String? fallbackImageUrl;
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
        errorWidget: (_, __, ___) {
          final fallback = fallbackImageUrl?.trim();
          if (fallback != null && fallback.isNotEmpty && fallback != imageUrl) {
            return CachedNetworkImage(
              imageUrl: fallback,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              errorWidget: (_, __, ___) => Icon(
                Icons.style,
                color: const Color(0xFFFACC15),
                size: fallbackSize,
              ),
            );
          }
          return Icon(
            Icons.style,
            color: const Color(0xFFFACC15),
            size: fallbackSize,
          );
        },
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

class _SectionHeading extends StatelessWidget {
  final String title;

  const _SectionHeading({required this.title});

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
      final bestSellers = _cardsForIds(cachedSections.bestSellerIds, byId);
      final featured = _cardsForIds(cachedSections.featuredIds, byId);
      if (bestSellers.isNotEmpty || featured.isNotEmpty) {
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
          previewImageUrl:
              '/card-images/previews/249796_pokemon-card-151-booster-box.jpg',
          imageUrl:
              '/card-images/249796_pokemon-card-151-booster-box-pokemon-card-151.jpg',
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
          previewImageUrl: '/card-images/previews/258625_151-booster.jpg',
          imageUrl: '/card-images/258625_151-booster-151.jpg',
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
          previewImageUrl: '/card-images/previews/274416_mew-ex.jpg',
          imageUrl:
              '/card-images/274416_mew-ex-special-illustration-rare-232-091-paldean-fates.jpg',
          set: 'Paldean Fates',
          number: '232/091',
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
    required this.previewImageUrl,
    required this.imageUrl,
    required this.set,
    required this.number,
    required this.itemKind,
    required this.productType,
  });

  final String id;
  final String name;
  final String previewImageUrl;
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
                imageUrl: card.previewImageUrl,
                fallbackImageUrl: card.imageUrl,
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
