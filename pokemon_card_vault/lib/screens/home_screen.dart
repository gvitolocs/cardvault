import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/card_listing.dart';
import '../models/app_user_profile.dart';
import '../models/pokemon_card.dart';
import '../providers/auth_provider.dart';
import '../providers/card_listing_provider.dart';
import '../providers/card_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/recent_views_provider.dart';
import '../services/card_service.dart';
import '../services/search_debug_trace.dart';
import '../constants/project_links.dart';
import '../utils/browser_capabilities.dart';
import '../utils/card_navigation.dart';
import '../utils/card_palette.dart';
import '../utils/card_url.dart';
import '../utils/price_format.dart';
import '../widgets/site_footer.dart';

const double topBarActionSize = 44;
const double marketplaceTopBarHeight = 64;
const double _topBarIconSize = 24;
const Duration _searchPreviewHeroHoldDuration = Duration(milliseconds: 720);
const Duration marketplaceSearchPreviewHeroHoldDuration =
    _searchPreviewHeroHoldDuration;
const Color marketplaceTopBarColor = Color(0xFF0A1026);

class TopBarActionFrame extends StatelessWidget {
  const TopBarActionFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: topBarActionSize,
      height: topBarActionSize,
      child: Center(child: child),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    this.returnToRecentTop = false,
  });

  final bool returnToRecentTop;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class MarketplaceHomeRouteIntent {
  const MarketplaceHomeRouteIntent.returnToRecentTop();

  bool get shouldReturnToRecentTop => true;
}

class MarketplaceSearchScreen extends ConsumerStatefulWidget {
  const MarketplaceSearchScreen({
    super.key,
    required this.initialQuery,
    this.expansion,
    this.productType,
    this.searchLanguage,
    this.cardService,
  });

  final String initialQuery;
  final String? expansion;
  final String? productType;
  final String? searchLanguage;
  final CardService? cardService;

  @override
  ConsumerState<MarketplaceSearchScreen> createState() =>
      _MarketplaceSearchScreenState();
}

class _MarketplaceSearchScreenState
    extends ConsumerState<MarketplaceSearchScreen> {
  late final CardNotifier _cardNotifier;
  late final TextEditingController _controller;
  late final CardService _cardService;
  final FocusNode _searchFocusNode = FocusNode();
  List<PokemonCard> _results = const [];
  bool _isSearching = false;
  bool _searchFocused = false;
  String? _error;
  String? _selectedProductType;
  String? _selectedExpansion;
  String? _selectedRarity;
  Map<String, int> _productFacetCounts = const {};
  String _productFacetRequestKey = '';
  String _autoOpenedSearchKey = '';
  int _requestId = 0;
  static const int _searchPageSize = 100;
  int _nextOffset = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _cardNotifier = ref.read(cardProvider.notifier);
    _cardService = widget.cardService ?? CardService();
    SearchDebugTrace.instance.configureFromUri(Uri.base);
    _controller = TextEditingController(text: widget.initialQuery);
    final routeLanguage = widget.searchLanguage?.trim();
    if (routeLanguage != null && routeLanguage.isNotEmpty) {
      _cardNotifier.setSearchLanguage(routeLanguage);
    }
    _selectedProductType = _cleanProductType(widget.productType);
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _runSearch(widget.initialQuery);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cardNotifier.exitSearch(reason: 'search_page_dispose');
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _searchFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleSearchFocusChanged() {
    if (mounted) {
      setState(() => _searchFocused = _searchFocusNode.hasFocus);
    }
  }

  void _handleTopBarSearchFocusChanged(bool hasFocus) {
    if (mounted) {
      setState(() => _searchFocused = hasFocus);
    }
  }

  @override
  void didUpdateWidget(covariant MarketplaceSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery ||
        oldWidget.expansion != widget.expansion ||
        oldWidget.productType != widget.productType ||
        oldWidget.searchLanguage != widget.searchLanguage) {
      if (_controller.text != widget.initialQuery) {
        _controller.text = widget.initialQuery;
      }
      _selectedProductType = _cleanProductType(widget.productType);
      _selectedExpansion = null;
      _selectedRarity = null;
      _productFacetRequestKey = '';
      final routeLanguage = widget.searchLanguage?.trim();
      if (routeLanguage != null && routeLanguage.isNotEmpty) {
        _cardNotifier.setSearchLanguage(routeLanguage);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _runSearch(widget.initialQuery);
        }
      });
    }
  }

  Future<void> _loadProductFacets({
    required String query,
    required String searchLanguage,
  }) async {
    final requestKey = '$query|$searchLanguage';
    _productFacetRequestKey = requestKey;
    final facets = await _cardService.getMarketplaceProductFacets(
      query: query,
      searchLanguage: searchLanguage,
    );
    if (!mounted || _productFacetRequestKey != requestKey) {
      return;
    }
    if (facets.isEmpty) {
      return;
    }
    setState(() {
      _productFacetCounts = {
        for (final facet in facets) facet.productType: facet.count,
      };
    });
  }

  Future<void> _runSearch(String query) async {
    final requestId = ++_requestId;
    final normalizedQuery = query.trim();
    final expansion = widget.expansion?.trim();
    await ref.read(cardProvider.notifier).ensureSearchLanguageLoaded();
    if (!mounted || requestId != _requestId) {
      return;
    }
    final searchLanguage = ref.read(cardProvider).searchLanguage;
    setState(() {
      _isSearching = true;
      _error = null;
      _nextOffset = 0;
      _hasMore = true;
      _loadingMore = false;
    });

    try {
      final productType = _selectedProductType?.trim();
      final cardState = ref.read(cardProvider);
      final warmedQuery = cardState.previewQuery.trim().isNotEmpty
          ? cardState.previewQuery.trim()
          : cardState.searchQuery.trim();
      if (expansion == null || expansion.isEmpty) {
        final warmed = warmedQuery.toLowerCase() == normalizedQuery.toLowerCase()
            ? cardState.searchPreviews
            : const <PokemonCard>[];
        if (warmed.isNotEmpty && mounted && requestId == _requestId) {
          setState(() {
            _results = warmed;
            _error = null;
          });
        }
      }
      final results = expansion != null && expansion.isNotEmpty
          ? await _cardService.getCardsByExpansion(expansion)
          : await _loadSearchResults(
              normalizedQuery,
              productType: productType,
              searchLanguage: searchLanguage,
            );
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _results = results;
        _productFacetCounts = const {};
        _isSearching = false;
      });
      unawaited(_loadProductFacets(
        query: normalizedQuery,
        searchLanguage: searchLanguage,
      ));
      ref.read(cardProvider.notifier).cacheCards(results);
      _maybeOpenExactSearchResult(
        query: normalizedQuery,
        results: results,
        productType: _selectedProductType,
        expansion: expansion,
        searchLanguage: searchLanguage,
      );
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

  void _maybeOpenExactSearchResult({
    required String query,
    required List<PokemonCard> results,
    required String? productType,
    required String? expansion,
    required String searchLanguage,
  }) {
    final card = _exactSearchAutoOpenCard(
      query: query,
      results: results,
      productType: productType,
      expansion: expansion,
    );
    if (card == null || !mounted) {
      return;
    }
    final searchKey = [
      _compactSearchIdentity(query),
      card.id,
      searchLanguage,
    ].join('|');
    if (searchKey == _autoOpenedSearchKey) {
      return;
    }
    _autoOpenedSearchKey = searchKey;
    SearchDebugTrace.instance.record('search.exact_result.auto_open', {
      'query': query,
      'cardId': card.id,
      'name': card.name,
      'number': card.number,
      'language': searchLanguage,
    });
    ref.read(cardProvider.notifier).recordCardInteraction(
      card,
      'click',
      source: 'marketplace_search_exact',
      metadata: {
        'query': query,
        'resultCount': results.length,
        'language': searchLanguage,
        'autoOpen': true,
      },
    );
    unawaited(navigateToCanonicalCardDetail(
      context,
      card,
      language: searchLanguage,
      source: 'marketplace_search_exact',
      cardService: _cardService,
      replace: true,
    ));
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      _runSearch(value);
    });
  }

  Future<List<PokemonCard>> _loadSearchResults(
    String normalizedQuery, {
    required String? productType,
    required String searchLanguage,
  }) async {
    final selectedProductType = productType?.trim();
    if (_meaningfulSearchLength(normalizedQuery) < 1) {
      _nextOffset = 0;
      _hasMore = false;
      if (selectedProductType == null || selectedProductType.isEmpty) {
        return _cardService.getAllCards();
      }
      return _cardService.getMarketplaceCardsByProductType(
        selectedProductType,
        limit: _searchPageSize,
      );
    }
    if (selectedProductType == null || selectedProductType.isEmpty) {
      final page = await _cardService.searchMarketplaceCards(
        normalizedQuery,
        limit: _searchPageSize,
        offset: 0,
        searchLanguage: searchLanguage,
      );
      _nextOffset = page.length;
      _hasMore = page.length >= _searchPageSize;
      return page;
    }
    final baseResults = await _cardService.searchMarketplaceCards(
      normalizedQuery,
      limit: _searchPageSize,
      offset: 0,
      searchLanguage: searchLanguage,
    );
    final productResults = await _cardService.searchMarketplaceCards(
      normalizedQuery,
      limit: _searchPageSize,
      productType: selectedProductType,
      searchLanguage: searchLanguage,
    );
    final merged = _mergeSearchResults(baseResults, productResults);
    _nextOffset = baseResults.length;
    _hasMore = baseResults.length >= _searchPageSize;
    return merged;
  }

  Future<void> _loadMoreSearchResults() async {
    if (_loadingMore || !_hasMore || _isSearching) {
      return;
    }
    final normalizedQuery = _controller.text.trim();
    if (_meaningfulSearchLength(normalizedQuery) < 1) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final page = await _cardService.searchMarketplaceCards(
        normalizedQuery,
        limit: _searchPageSize,
        offset: _nextOffset,
        searchLanguage: ref.read(cardProvider).searchLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _results = _dedupeSearchPageCards([..._results, ...page]);
        _nextOffset += page.length;
        _hasMore = page.length >= _searchPageSize;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMore = false;
        _error = '$error';
      });
    }
  }

  List<PokemonCard> _dedupeSearchPageCards(List<PokemonCard> cards) {
    final seen = <String>{};
    final out = <PokemonCard>[];
    for (final card in cards) {
      if (card.id.isEmpty || !seen.add(card.id)) {
        continue;
      }
      out.add(card);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final expansion = widget.expansion?.trim();
    final productType = _selectedProductType?.trim();
    final cartState = ref.watch(cartProvider);
    final cardState = ref.watch(cardProvider);
    _syncSearchDebugAuthorization(ref.watch(userProfileProvider).valueOrNull);
    final cachedBalance = ref.watch(cachedPknBalanceProvider).valueOrNull;
    final balance =
        ref.watch(pknBalanceProvider).valueOrNull ?? cachedBalance ?? 0;
    final compactTopBar = MediaQuery.sizeOf(context).width < 760;
    final compactSearchExpanded =
        compactTopBar && (_searchFocused || _controller.text.isNotEmpty);
    final filteredResults = _applySearchPageFilters(_results);
    final isProductCategory =
        productType != null && productType.isNotEmpty && productType != 'card';
    final isSingleCategory = productType == 'card';
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
          title: isSingleCategory ? 'Graded' : 'Singles',
          cards: singles,
        ),
        const SizedBox(height: 28),
      ],
      if (!isSingleCategory && products.isNotEmpty)
        _SearchResultSection(
          title: isProductCategory ? title : 'Products',
          cards: products,
        ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: marketplaceTopBarColor,
        toolbarHeight: marketplaceTopBarHeight,
        elevation: 0,
        titleSpacing: 16,
        title: MarketplaceTopBar(
          compactExpanded: compactSearchExpanded,
          logo: MarketplaceLogoButton(
            onTap: compactTopBar
                ? () => showMarketplaceSideMenu(context)
                : () => context.go('/marketplace'),
          ),
          search: MarketplaceTopBarSearch(
            controller: _controller,
            focusNode: _searchFocusNode,
            compactTopBar: compactTopBar,
            query: cardState.previewQuery.isNotEmpty
                ? cardState.previewQuery
                : _controller.text,
            isSearching: _isSearching,
            enablePreviews: false,
            onSearchFocusedChanged: _handleTopBarSearchFocusChanged,
            onCompletionChanged: (value) {
              setState(() {});
              _onSearchChanged(value);
            },
            onSelected: (selection) {
              final card = selection.card;
              ref.read(cardProvider.notifier).recordCardInteraction(
                    card,
                    'click',
                    source: 'search_preview',
                  );
              _goToCardDetail(ref, context, card, heroTag: selection.heroTag);
            },
            searchQueryParameters: {
              if (productType?.isNotEmpty == true) 'productType': productType!,
            },
          ),
          languageMenu: SearchLanguageMenu(
            value: cardState.searchLanguage,
            onChanged: (language) {
              ref.read(cardProvider.notifier).setSearchLanguage(language);
              _runSearch(_controller.text);
            },
          ),
          actions: marketplaceTopBarActions(
            context: context,
            balance: balance,
            itemCount: cartState.itemCount,
            compactTopBar: compactTopBar,
            compactSearchExpanded: compactSearchExpanded,
            keyValue: 'search-actions',
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final filters = _SearchFilterPanel(
                selectedProductType: _selectedProductType,
                selectedExpansion: _selectedExpansion,
                selectedRarity: _selectedRarity,
                productCounts: _productFacetCounts.isNotEmpty
                    ? _productFacetCounts
                    : _productFacetCountsFromCards(_results),
                expansionCounts: _facetCounts(
                  _results,
                  (card) => card.set,
                ),
                expansionImages: _facetImages(
                  _results,
                  (card) => card.set,
                ),
                rarityCounts: _facetCounts(
                  _results.where((card) => card.itemKind != 'product'),
                  (card) => card.rarity,
                ),
                onProductTypeChanged: (value) {
                  setState(() => _selectedProductType = value);
                  _runSearch(_controller.text);
                },
                onExpansionChanged: (value) {
                  setState(() => _selectedExpansion = value);
                },
                onRarityChanged: (value) =>
                    setState(() => _selectedRarity = value),
                onClear: () => setState(() {
                  _selectedProductType = null;
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
                  if (_hasMore && query.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Center(
                      child: TextButton(
                        onPressed: _loadingMore ? null : _loadMoreSearchResults,
                        child: Text(
                          _loadingMore ? 'Loading…' : 'Load more cards',
                          style: const TextStyle(color: Color(0xFFFACC15)),
                        ),
                      ),
                    ),
                  ],
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
                    if (_hasMore && query.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Center(
                        child: TextButton(
                          onPressed: _loadingMore ? null : _loadMoreSearchResults,
                          child: Text(
                            _loadingMore ? 'Loading…' : 'Load more cards',
                            style: const TextStyle(color: Color(0xFFFACC15)),
                          ),
                        ),
                      ),
                    ],
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
      floatingActionButton:
          SearchDebugTrace.instance.enabled ? const _SearchDebugPanel() : null,
    );
  }

  void _syncSearchDebugAuthorization(AppUserProfile? profile) {
    syncMarketplaceSearchDebugAuthorization(profile);
  }

  List<PokemonCard> _applySearchPageFilters(List<PokemonCard> cards) {
    return _applyMarketplaceSearchFilters(
      cards,
      selectedProductType: _selectedProductType,
      selectedExpansion: _selectedExpansion,
      selectedRarity: _selectedRarity,
    );
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

  Map<String, String> _facetImages(
    Iterable<PokemonCard> cards,
    String Function(PokemonCard card) valueForCard,
  ) {
    final images = <String, String>{};
    for (final card in cards) {
      final value = valueForCard(card).trim();
      if (value.isEmpty || value == 'Card' || images.containsKey(value)) {
        continue;
      }
      final imageUrl = card.expansionSymbolUrl.trim().isNotEmpty
          ? card.expansionSymbolUrl.trim()
          : _expansionSymbolUrl(value);
      if (imageUrl.isNotEmpty) {
        images[value] = imageUrl;
      }
    }
    return images;
  }

  String _expansionSymbolUrl(String expansion) {
    final slug = expansion
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty
        ? ''
        : 'https://cdn.pokoin.com/expansions/symbols/$slug.png';
  }

  String _productTypeTitle(String productType) {
    return productType == 'card'
        ? 'Graded'
        : _marketplaceProductTypeLabel(productType);
  }
}

String? _cleanProductType(String? value) {
  final productType = value?.trim();
  return productType == null || productType.isEmpty ? null : productType;
}

List<PokemonCard> _mergeSearchResults(
  List<PokemonCard> primary,
  List<PokemonCard> secondary,
) {
  final byId = <String, PokemonCard>{};
  for (final card in [...primary, ...secondary]) {
    if (card.id.isNotEmpty) {
      final existing = byId[card.id];
      byId[card.id] =
          existing == null ? card : _preferredSearchResultCard(existing, card);
    }
  }
  return byId.values.toList();
}

PokemonCard _preferredSearchResultCard(PokemonCard current, PokemonCard next) {
  if (!current.isMarketAvailable && next.isMarketAvailable) {
    return next;
  }
  if (current.isMarketAvailable &&
      next.isMarketAvailable &&
      next.price > 0 &&
      (current.price <= 0 || next.price < current.price)) {
    return next;
  }
  return current;
}

List<PokemonCard> _applyMarketplaceSearchFilters(
  List<PokemonCard> cards, {
  String? selectedProductType,
  String? selectedExpansion,
  String? selectedRarity,
}) {
  return cards.where((card) {
    final productType = selectedProductType?.trim();
    if (productType != null &&
        productType.isNotEmpty &&
        _productFacetValue(card) != productType) {
      return false;
    }
    final expansion = selectedExpansion?.trim();
    if (expansion != null && expansion.isNotEmpty && card.set != expansion) {
      return false;
    }
    final rarity = selectedRarity?.trim();
    if (rarity != null && rarity.isNotEmpty && card.rarity != rarity) {
      return false;
    }
    return true;
  }).toList();
}

Map<String, int> _productFacetCountsFromCards(Iterable<PokemonCard> cards) {
  final counts = <String, int>{};
  for (final card in cards) {
    final value = _productFacetValue(card);
    if (value.isEmpty) {
      continue;
    }
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return Map.fromEntries(
    counts.entries.toList()
      ..sort((a, b) {
        final rank = _productTypeRank(a.key).compareTo(_productTypeRank(b.key));
        if (rank != 0) {
          return rank;
        }
        final count = b.value.compareTo(a.value);
        if (count != 0) {
          return count;
        }
        return _marketplaceProductTypeLabel(a.key)
            .compareTo(_marketplaceProductTypeLabel(b.key));
      }),
  );
}

String _productFacetValue(PokemonCard card) {
  if (card.itemKind != 'product') {
    return 'card';
  }
  final productType = card.productType.trim();
  return productType.isEmpty ? 'sealed_product' : productType;
}

int _productTypeRank(String productType) {
  switch (productType) {
    case 'card':
      return 0;
    case 'booster_box':
      return 10;
    case 'booster_pack':
      return 20;
    case 'booster_bundle':
      return 30;
    case 'elite_trainer_box':
      return 40;
    case 'tin':
      return 50;
    case 'collection_box':
      return 60;
    case 'deck':
      return 70;
    case 'championship_deck':
      return 80;
    case 'accessory':
      return 90;
    case 'sealed_product':
      return 100;
    default:
      return 1000;
  }
}

String _marketplaceProductTypeLabel(String productType) {
  switch (productType) {
    case 'card':
      return 'Singles';
    case 'booster_box':
      return 'Booster boxes';
    case 'booster_pack':
      return 'Boosters';
    case 'booster_bundle':
      return 'Booster bundles';
    case 'elite_trainer_box':
      return 'Elite Trainer Boxes';
    case 'tin':
      return 'Tins';
    case 'collection_box':
      return 'Collection boxes';
    case 'deck':
      return 'Decks';
    case 'championship_deck':
      return 'Championship decks';
    case 'accessory':
      return 'Accessories';
    case 'sealed_product':
      return 'Sealed products';
    default:
      return productType
          .split('_')
          .where((part) => part.isNotEmpty)
          .map((part) => part[0].toUpperCase() + part.substring(1))
          .join(' ');
  }
}

@visibleForTesting
Map<String, int> marketplaceProductFacetCountsForTest(
  Iterable<PokemonCard> cards,
) {
  return _productFacetCountsFromCards(cards);
}

@visibleForTesting
List<PokemonCard> applyMarketplaceSearchFiltersForTest({
  required List<PokemonCard> cards,
  String? selectedProductType,
  String? selectedExpansion,
  String? selectedRarity,
}) {
  return _applyMarketplaceSearchFilters(
    cards,
    selectedProductType: selectedProductType,
    selectedExpansion: selectedExpansion,
    selectedRarity: selectedRarity,
  );
}

@visibleForTesting
String marketplaceProductTypeLabelForTest(String productType) {
  return _marketplaceProductTypeLabel(productType);
}

@visibleForTesting
String marketplaceProductTypeTitleForTest(String productType) {
  return productType == 'card'
      ? 'Graded'
      : _marketplaceProductTypeLabel(productType);
}

PokemonCard? _exactSearchAutoOpenCard({
  required String query,
  required List<PokemonCard> results,
  required String? productType,
  required String? expansion,
}) {
  if (_meaningfulSearchLength(query) < 3 ||
      expansion?.trim().isNotEmpty == true) {
    return null;
  }
  final cleanProductType = productType?.trim();
  if (cleanProductType != null &&
      cleanProductType.isNotEmpty &&
      cleanProductType != 'card') {
    return null;
  }
  final singles = results
      .where((card) => card.itemKind != 'product')
      .toList(growable: false);
  if (singles.length != 1) {
    return null;
  }
  final card = singles.single;
  return _queryIdentifiesCard(query, card) ? card : null;
}

@visibleForTesting
PokemonCard? exactSearchAutoOpenCardForTest({
  required String query,
  required List<PokemonCard> results,
  String? productType,
  String? expansion,
}) {
  return _exactSearchAutoOpenCard(
    query: query,
    results: results,
    productType: productType,
    expansion: expansion,
  );
}

@visibleForTesting
List<PokemonCard> marketplaceRecentCardsForTest({
  required List<RecentCardView> recentViews,
  List<PokemonCard> cards = const [],
  Map<String, MarketplaceCheapestPrice> cheapestPricesByCardId = const {},
}) {
  return _MarketplaceSections._cardsForRecentViews(
    recentViews,
    cards,
    cheapestPricesByCardId,
  );
}

@visibleForTesting
Map<String, List<PokemonCard>> marketplaceHomeSectionCardsForTest({
  required List<PokemonCard> cards,
  MarketplaceHomeSections? cachedSections,
  List<RecentCardView> recentViews = const [],
  Map<String, MarketplaceCheapestPrice> cheapestPricesByCardId = const {},
}) {
  final sections = _MarketplaceSections.fromCards(
    cards,
    cachedSections: cachedSections,
    recentViews: recentViews,
    cheapestPricesByCardId: cheapestPricesByCardId,
  );
  return {
    'recentlySeen': sections.recentlySeen,
    'bestSellers': sections.bestSellers,
    'featured': sections.featured,
  };
}

@visibleForTesting
List<RecentCardView> hydrateRecentViewsWithCheapestPricesForTest(
  List<RecentCardView> views,
  Map<String, MarketplaceCheapestPrice> cheapestPricesByCardId,
) {
  return _hydrateRecentViewsWithCheapestPrices(
    views,
    _indexRecentCheapestPrices(cheapestPricesByCardId),
  );
}

bool _queryIdentifiesCard(String query, PokemonCard card) {
  final queryIdentity = _compactSearchIdentity(query);
  final nameIdentity = _compactSearchIdentity(card.name);
  if (queryIdentity.isEmpty ||
      nameIdentity.isEmpty ||
      !queryIdentity.contains(nameIdentity)) {
    return false;
  }
  final numberIdentity = _compactSearchIdentity(_displaySearchCardNumber(card));
  if (numberIdentity.isEmpty) {
    return queryIdentity == nameIdentity;
  }
  return queryIdentity.contains(numberIdentity);
}

String _displaySearchCardNumber(PokemonCard card) {
  final number = card.number.trim();
  final pipeIndex = number.lastIndexOf('|');
  return pipeIndex >= 0 ? number.substring(pipeIndex + 1).trim() : number;
}

String _compactSearchIdentity(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

final _marketplaceHomeSession = _MarketplaceHomeSession();

class _MarketplaceHomeSession {
  double scrollOffset = 0;
  int visibleCount = 0;
  bool spotlightRevealStarted = false;
  bool spotlightInViewport = false;
  bool spotlightControlsInViewport = false;
  bool footerInViewport = false;
  final Set<String> preloadedSpotlightImageUrls = <String>{};
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final CardNotifier _cardNotifier;
  final CardService _cardService = CardService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final ScrollController _scrollController;
  final GlobalKey _spotlightSectionKey = GlobalKey();
  final GlobalKey _spotlightControlsKey = GlobalKey();
  final GlobalKey _footerSectionKey = GlobalKey();
  static const int _pageSize = 12;
  static const int _spotlightRevealStep = 4;
  static const int _spotlightPrecacheLimit = _pageSize;
  static const int _detailWarmupLimit = 12;
  Timer? _spotlightRevealTimer;
  Timer? _spotlightDerenderTimer;
  late final Set<String> _preloadedSpotlightImageUrls;
  final Set<String> _detailWarmupRequestedIds = <String>{};
  List<String> _lastRenderedWarmupIds = const [];
  Map<String, MarketplaceCheapestPrice> _recentCheapestPrices = const {};
  String _recentCheapestPriceKey = '';
  late int _visibleCount;
  bool _searchFocused = false;
  late bool _spotlightRevealStarted;
  late bool _spotlightInViewport;
  late bool _spotlightControlsInViewport;
  late bool _footerInViewport;

  @override
  void initState() {
    super.initState();
    _cardNotifier = ref.read(cardProvider.notifier);
    final initialScrollOffset =
        widget.returnToRecentTop ? 0.0 : _marketplaceHomeSession.scrollOffset;
    if (widget.returnToRecentTop) {
      _marketplaceHomeSession.scrollOffset = 0;
    }
    _scrollController = ScrollController(
      initialScrollOffset: initialScrollOffset,
    );
    _preloadedSpotlightImageUrls =
        _marketplaceHomeSession.preloadedSpotlightImageUrls;
    _visibleCount = _marketplaceHomeSession.visibleCount;
    _spotlightRevealStarted = _marketplaceHomeSession.spotlightRevealStarted;
    _spotlightInViewport = _marketplaceHomeSession.spotlightInViewport;
    _spotlightControlsInViewport =
        _marketplaceHomeSession.spotlightControlsInViewport;
    _footerInViewport = _marketplaceHomeSession.footerInViewport;
    SearchDebugTrace.instance.configureFromUri(Uri.base);
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    _scrollController.addListener(_handleHomeScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _cardNotifier.refreshCards();
      if (widget.returnToRecentTop) {
        _scrollHomeToRecentTop();
      }
      _syncSpotlightViewportState();
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.returnToRecentTop && widget.returnToRecentTop) {
      _scrollHomeToRecentTop();
    }
  }

  @override
  void dispose() {
    _cardNotifier.exitSearch(reason: 'home_dispose');
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _scrollController.removeListener(_handleHomeScroll);
    _persistHomeSession();
    _spotlightRevealTimer?.cancel();
    _spotlightDerenderTimer?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleHomeScroll() {
    _persistHomeSession();
    _syncSpotlightViewportState();
  }

  void _scheduleRecentCheapestPriceHydration(List<RecentCardView> views) {
    final navigationToken = _cardNotifier.navigationPriorityToken;
    final ids = <String>[];
    final seen = <String>{};
    for (final view in views.take(9)) {
      final viewIds = _recentViewCheapestLookupKeys(view);
      for (final id in viewIds) {
        if (!seen.add(id)) {
          continue;
        }
        ids.add(id);
        if (ids.length >= 50) {
          break;
        }
      }
      if (ids.length >= 50) {
        break;
      }
    }
    final key = ids.join(',');
    if (key.isEmpty || key == _recentCheapestPriceKey) {
      return;
    }
    _recentCheapestPriceKey = key;
    final cachedPrices = _recentCheapestPricesForViews(views);
    if (cachedPrices.isNotEmpty) {
      setState(() {
        _recentCheapestPrices = _mergeRecentCheapestPrices(
          _recentCheapestPrices,
          cachedPrices,
        );
      });
    }
    _cardService.getCheapestPricesForCardIds(ids).then((prices) {
      if (!mounted ||
          _recentCheapestPriceKey != key ||
          prices.isEmpty ||
          _cardNotifier.shouldSkipNavigationDeferredResult(navigationToken)) {
        return;
      }
      final indexedPrices = _indexRecentCheapestPrices(prices);
      final hydratedCheapestPrices = _mergeRecentCheapestPrices(
        cachedPrices,
        indexedPrices,
      );
      setState(() {
        _recentCheapestPrices = _mergeRecentCheapestPrices(
          _recentCheapestPrices,
          indexedPrices,
        );
      });
      final hydratedViews = _hydrateRecentViewsWithCheapestPrices(
        views,
        hydratedCheapestPrices,
      );
      if (!_sameRecentViewCache(views, hydratedViews)) {
        ref.read(recentViewsProvider.notifier).replaceHydratedViews(
              hydratedViews,
            );
      }
    });
  }

  void _scrollHomeToRecentTop() {
    _marketplaceHomeSession.scrollOffset = 0;
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    _persistHomeSession();
  }

  void _persistHomeSession() {
    if (_scrollController.hasClients) {
      _marketplaceHomeSession.scrollOffset = _scrollController.offset;
    }
    _marketplaceHomeSession.visibleCount = _visibleCount;
    _marketplaceHomeSession.spotlightRevealStarted = _spotlightRevealStarted;
    _marketplaceHomeSession.spotlightInViewport = _spotlightInViewport;
    _marketplaceHomeSession.spotlightControlsInViewport =
        _spotlightControlsInViewport;
    _marketplaceHomeSession.footerInViewport = _footerInViewport;
  }

  void _syncSpotlightViewportState() {
    if (!mounted) {
      return;
    }
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final footerInViewport =
        _isKeyNearViewport(_footerSectionKey, viewportHeight);
    final spotlightContext = _spotlightSectionKey.currentContext;
    if (spotlightContext == null) {
      _syncDeferredAreaVisibility(
        controlsInViewport: false,
        footerInViewport: footerInViewport,
      );
      return;
    }
    final renderObject = spotlightContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      _syncDeferredAreaVisibility(
        controlsInViewport: false,
        footerInViewport: footerInViewport,
      );
      return;
    }
    final top = renderObject.localToGlobal(Offset.zero).dy;
    final height = renderObject.size.height;
    final shouldRender = top < viewportHeight * 0.92 && top + height > 90;
    final controlsInViewport =
        _isKeyNearViewport(_spotlightControlsKey, viewportHeight);
    if (shouldRender) {
      _spotlightDerenderTimer?.cancel();
      if (!_spotlightInViewport || !_spotlightRevealStarted) {
        _startSpotlightReveal();
      }
      _syncDeferredAreaVisibility(
        controlsInViewport: controlsInViewport,
        footerInViewport: footerInViewport,
      );
      return;
    }
    _syncDeferredAreaVisibility(
      controlsInViewport: controlsInViewport,
      footerInViewport: footerInViewport,
    );
    if (!_spotlightInViewport && _visibleCount == 0) {
      return;
    }
    _spotlightRevealTimer?.cancel();
    if (_spotlightInViewport) {
      setState(() => _spotlightInViewport = false);
      _persistHomeSession();
    }
    _spotlightDerenderTimer?.cancel();
    _spotlightDerenderTimer = Timer(const Duration(milliseconds: 260), () {
      if (!mounted || _spotlightInViewport) {
        return;
      }
      setState(() {
        _spotlightRevealStarted = false;
        _visibleCount = _pageSize;
        _spotlightControlsInViewport = false;
      });
      _persistHomeSession();
    });
  }

  bool _isKeyNearViewport(GlobalKey key, double viewportHeight) {
    final context = key.currentContext;
    if (context == null) {
      return false;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      return false;
    }
    final top = renderObject.localToGlobal(Offset.zero).dy;
    final height = renderObject.size.height;
    return top < viewportHeight * 0.96 && top + height > 60;
  }

  void _syncDeferredAreaVisibility({
    required bool controlsInViewport,
    required bool footerInViewport,
  }) {
    if (_spotlightControlsInViewport == controlsInViewport &&
        _footerInViewport == footerInViewport) {
      return;
    }
    setState(() {
      _spotlightControlsInViewport = controlsInViewport;
      _footerInViewport = footerInViewport;
    });
    _persistHomeSession();
  }

  void _startSpotlightReveal() {
    _spotlightRevealTimer?.cancel();
    setState(() {
      _spotlightInViewport = true;
      _spotlightRevealStarted = true;
      _spotlightControlsInViewport = false;
      _footerInViewport = false;
    });
    _persistHomeSession();
    _spotlightRevealTimer =
        Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!mounted || !_spotlightInViewport) {
        timer.cancel();
        return;
      }
      if (_visibleCount >= _pageSize) {
        timer.cancel();
        return;
      }
      setState(() {
        _visibleCount =
            math.min(_visibleCount + _spotlightRevealStep, _pageSize);
      });
      _persistHomeSession();
    });
  }

  void _scheduleSpotlightImagePrecache(
    List<PokemonCard> cards, {
    required bool enabled,
  }) {
    if (!mounted ||
        !enabled ||
        cards.isEmpty ||
        _cardNotifier.isNavigationTransitionActive) {
      return;
    }
    final urls = <String>[];
    for (final card in cards.take(_spotlightPrecacheLimit)) {
      final imageUrl = card.imageUrl.trim();
      if (imageUrl.isEmpty || _preloadedSpotlightImageUrls.contains(imageUrl)) {
        continue;
      }
      _preloadedSpotlightImageUrls.add(imageUrl);
      urls.add(imageUrl);
    }
    if (urls.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _cardNotifier.isNavigationTransitionActive) {
        return;
      }
      for (final url in urls) {
        unawaited(
          precacheImage(CachedNetworkImageProvider(url), context).catchError(
            (_) {
              _preloadedSpotlightImageUrls.remove(url);
            },
          ),
        );
      }
    });
  }

  void _scheduleRenderedDetailWarmup(Iterable<PokemonCard> cards) {
    if (!mounted || _cardNotifier.isNavigationTransitionActive) {
      return;
    }
    final ids = <String>[];
    final boundedCards = <PokemonCard>[];
    for (final card in cards) {
      final id = card.id.trim();
      if (id.isEmpty ||
          _detailWarmupRequestedIds.contains(id) ||
          ids.contains(id)) {
        continue;
      }
      ids.add(id);
      boundedCards.add(card);
      if (boundedCards.length >= _detailWarmupLimit) {
        break;
      }
    }
    if (boundedCards.isEmpty || _sameStringList(ids, _lastRenderedWarmupIds)) {
      return;
    }
    _lastRenderedWarmupIds = List.unmodifiable(ids);
    _detailWarmupRequestedIds.addAll(ids);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _cardNotifier.isNavigationTransitionActive) {
        return;
      }
      unawaited(
        ref.read(cardProvider.notifier).warmDetailCards(boundedCards),
      );
    });
  }

  bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }

  void _handleSearchFocusChanged() {
    final compactTopBar = MediaQuery.sizeOf(context).width < 760;
    if (!compactTopBar &&
        _searchFocusNode.hasFocus &&
        _searchController.text.trim().isEmpty) {
      _showEmptyFocusSearchPreviews();
    }
    if (mounted) {
      setState(() => _searchFocused = _searchFocusNode.hasFocus);
    }
  }

  void _handleTopBarSearchFocusChanged(bool hasFocus) {
    if (mounted) {
      setState(() => _searchFocused = hasFocus);
    }
  }

  void _showEmptyFocusSearchPreviews() {
    showMarketplaceEmptyFocusSearchPreviews(ref);
  }

  @override
  Widget build(BuildContext context) {
    final cardState = ref.watch(cardProvider);
    final cartState = ref.watch(cartProvider);
    _syncSearchDebugAuthorization(ref.watch(userProfileProvider).valueOrNull);
    final cachedBalance = ref.watch(cachedPknBalanceProvider).valueOrNull;
    final balance =
        ref.watch(pknBalanceProvider).valueOrNull ?? cachedBalance ?? 0;
    final cards = cardState.filteredCards;
    final activeListings =
        ref.watch(activeCardListingsProvider).valueOrNull ?? const [];
    final hasMarketplaceData = cardState.cards.isNotEmpty ||
        cardState.homeSections != null ||
        cardState.hasMarketplaceLoadCompleted;
    final showMarketplaceSkeleton = cardState.error == null &&
        !hasMarketplaceData &&
        cardState.searchQuery.trim().isEmpty;
    final catalog = _cardsWithActiveListings(cardState.cards, activeListings);
    final listingAwareCards = _cardsWithActiveListings(cards, activeListings);
    final listingAwareSpotlightCards =
        _cardsWithActiveListings(cardState.spotlightCards, activeListings);
    final singles = listingAwareCards.where(_isSingleCard).toList();
    final warmedSpotlightSingles =
        listingAwareSpotlightCards.where(_isSingleCard).toList();
    final recentViewsState = ref.watch(recentViewsProvider);
    final recentViews = recentViewsState.views;
    _scheduleRecentCheapestPriceHydration(recentViews);
    final recentCheapestPrices = _mergeRecentCheapestPrices(
      _recentCheapestPricesForViews(recentViews),
      _recentCheapestPrices,
    );
    final spotlightSource =
        warmedSpotlightSingles.isNotEmpty ? warmedSpotlightSingles : singles;
    final personalizedCards = cardState.searchQuery.trim().isEmpty
        ? _rankCardsByRecentViews(spotlightSource, recentViews)
        : singles;
    final visibleCards = personalizedCards.take(_visibleCount).toList();
    final sections = _MarketplaceSections.fromCards(
      catalog,
      cachedSections: cardState.homeSections,
      recentViews: recentViews,
      cheapestPricesByCardId: recentCheapestPrices,
    );
    final compactTopBar = MediaQuery.sizeOf(context).width < 760;
    final compactSearchExpanded =
        compactTopBar && (_searchFocused || _searchController.text.isNotEmpty);
    _scheduleSpotlightImagePrecache(
      personalizedCards,
      enabled:
          !compactTopBar && !cardState.isLoading && cardState.error == null,
    );
    final renderedWarmupCards = [
      ...sections.recentlySeen,
      ...sections.bestSellers,
      ...sections.featured,
      if (_spotlightRevealStarted) ...visibleCards,
    ];
    if (!cardState.isLoading && cardState.error == null) {
      _scheduleRenderedDetailWarmup(renderedWarmupCards);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: marketplaceTopBarColor,
            toolbarHeight: marketplaceTopBarHeight,
            elevation: 0,
            titleSpacing: 16,
            title: MarketplaceTopBar(
              compactExpanded: compactSearchExpanded,
              logo: MarketplaceLogoButton(
                onTap: compactTopBar
                    ? () => showMarketplaceSideMenu(context)
                    : () => context.go('/marketplace'),
              ),
              search: MarketplaceTopBarSearch(
                controller: _searchController,
                focusNode: _searchFocusNode,
                compactTopBar: compactTopBar,
                onEmptyFocus: _showEmptyFocusSearchPreviews,
                onSearchFocusedChanged: _handleTopBarSearchFocusChanged,
                onSelected: (selection) {
                  final card = selection.card;
                  ref.read(cardProvider.notifier).recordCardInteraction(
                        card,
                        'click',
                        source: 'search_preview',
                      );
                  _goToCardDetail(ref, context, card,
                      heroTag: selection.heroTag);
                  Future<void>.delayed(_searchPreviewHeroHoldDuration, () {
                    if (mounted) {
                      _resetTransientSearch();
                    }
                  });
                },
              ),
              languageMenu: SearchLanguageMenu(
                value: cardState.searchLanguage,
                onChanged: (language) =>
                    ref.read(cardProvider.notifier).setSearchLanguage(language),
              ),
              actions: marketplaceTopBarActions(
                context: context,
                balance: balance,
                itemCount: cartState.itemCount,
                compactTopBar: compactTopBar,
                compactSearchExpanded: compactSearchExpanded,
                keyValue: 'marketplace-actions',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showMarketplaceSkeleton)
                    const _MarketplaceSkeletonShell()
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
                        seeMoreQuery: '',
                        isLoading: recentViewsState.isLoading &&
                            sections.recentlySeen.isEmpty,
                      ),
                      const SizedBox(height: 24),
                    ],
                    _CardCarouselSection(
                      title: 'Best sellers',
                      cards: sections.bestSellers,
                      seeMoreQuery: '',
                    ),
                    const SizedBox(height: 24),
                    _CardCarouselSection(
                      title: 'Featured',
                      cards: sections.featured,
                      seeMoreQuery: '',
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
                              if (!compactTopBar) ...[
                                KeyedSubtree(
                                  key: _spotlightSectionKey,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const _SuggestedCategories(),
                                      const SizedBox(height: 28),
                                      const _MarketHeader(),
                                      const SizedBox(height: 16),
                                      AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 260),
                                        child: !_spotlightRevealStarted
                                            ? const _SpotlightDeferredPlaceholder(
                                                key: ValueKey(
                                                    'spotlight-placeholder'),
                                              )
                                            : AnimatedOpacity(
                                                key: const ValueKey(
                                                    'spotlight-grid'),
                                                opacity: _spotlightInViewport
                                                    ? 1
                                                    : 0,
                                                duration: const Duration(
                                                    milliseconds: 240),
                                                curve: Curves.easeOutCubic,
                                                child: visibleCards.isEmpty
                                                    ? const _SpotlightDeferredPlaceholder()
                                                    : _MarketplaceGrid(
                                                        cards: visibleCards,
                                                        heroScope:
                                                            'marketplace-main',
                                                        emptyTitle:
                                                            'No singles match these filters',
                                                        animateTiles: true,
                                                      ),
                                              ),
                                      ),
                                      const SizedBox(height: 18),
                                      KeyedSubtree(
                                        key: _spotlightControlsKey,
                                        child: AnimatedSwitcher(
                                          duration:
                                              const Duration(milliseconds: 260),
                                          child: _spotlightControlsInViewport &&
                                                  _spotlightInViewport &&
                                                  visibleCards.length <
                                                      personalizedCards.length
                                              ? _SpotlightAnimatedTile(
                                                  key: ValueKey(
                                                      'show-next-${visibleCards.length}'),
                                                  index: visibleCards.length,
                                                  child: Center(
                                                    child: OutlinedButton.icon(
                                                      onPressed: () =>
                                                          setState(() {
                                                        _visibleCount +=
                                                            _pageSize;
                                                        _persistHomeSession();
                                                      }),
                                                      icon: const Icon(
                                                          Icons.expand_more),
                                                      label: Text(
                                                        'Show next ${math.min(_pageSize, personalizedCards.length - visibleCards.length)} cards',
                                                      ),
                                                    ),
                                                  ),
                                                )
                                              : const SizedBox(
                                                  key: ValueKey(
                                                      'show-next-placeholder'),
                                                  height: 40,
                                                ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),
                              ],
                              KeyedSubtree(
                                key: _footerSectionKey,
                                child: compactTopBar
                                    ? const SiteFooter()
                                    : AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 260),
                                        child: _footerInViewport
                                            ? _SpotlightAnimatedTile(
                                                key: ValueKey(
                                                  'site-footer-${visibleCards.length}',
                                                ),
                                                index: visibleCards.length + 1,
                                                child: const SiteFooter(),
                                              )
                                            : const SizedBox(
                                                key: ValueKey(
                                                    'site-footer-placeholder'),
                                                height: 220,
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
      floatingActionButton:
          SearchDebugTrace.instance.enabled ? const _SearchDebugPanel() : null,
    );
  }

  void _syncSearchDebugAuthorization(AppUserProfile? profile) {
    syncMarketplaceSearchDebugAuthorization(profile);
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

class WalletBalanceButton extends ConsumerWidget {
  const WalletBalanceButton({
    super.key,
    required this.balance,
    required this.onTap,
    this.showIcon = true,
  });

  final int balance;
  final VoidCallback onTap;
  final bool showIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;

    if (!showIcon) {
      if (user == null) {
        return Tooltip(
          message: 'Sign in',
          child: TopBarActionFrame(
            child: IconButton(
              onPressed: () => context.go('/auth?from=/profile'),
              icon: const Icon(Icons.login, size: 22),
              color: const Color(0xFFFACC15),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints.tightFor(
                width: topBarActionSize,
                height: topBarActionSize,
              ),
            ),
          ),
        );
      }

      return TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFFACC15),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(topBarActionSize, topBarActionSize),
          fixedSize: const Size.fromHeight(topBarActionSize),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
        child: Text(formatPkn(balance, decimals: 0)),
      );
    }

    return SizedBox(
      height: topBarActionSize,
      child: Center(
        child: TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
          label: Text(formatPkn(balance, decimals: 0)),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFFACC15),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(topBarActionSize, topBarActionSize),
            fixedSize: const Size.fromHeight(topBarActionSize),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class MarketplaceCartButton extends StatelessWidget {
  const MarketplaceCartButton({
    super.key,
    required this.itemCount,
    required this.compact,
    required this.onTap,
  });

  final int itemCount;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconData =
        compact ? Icons.shopping_cart_outlined : Icons.shopping_bag_outlined;
    final icon = Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.hardEdge,
      children: [
        Padding(
          padding: compact && itemCount > 0
              ? const EdgeInsets.only(top: 4, right: 4)
              : EdgeInsets.zero,
          child: Icon(iconData, size: compact ? 22 : 18),
        ),
        if (compact && itemCount > 0)
          Positioned(
            top: 0,
            right: 0,
            child: _CartCountBadge(count: itemCount),
          ),
      ],
    );

    if (compact) {
      return Tooltip(
        message: itemCount == 1 ? '1 item in cart' : '$itemCount items in cart',
        child: TopBarActionFrame(
          child: IconButton(
            onPressed: onTap,
            icon: icon,
            color: const Color(0xFFFACC15),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints.tightFor(
              width: topBarActionSize,
              height: topBarActionSize,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: topBarActionSize,
      child: Center(
        child: FilledButton.icon(
          onPressed: onTap,
          icon: icon,
          label: Text('$itemCount'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, topBarActionSize),
            fixedSize: const Size.fromHeight(topBarActionSize),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}

class _CartCountBadge extends StatelessWidget {
  const _CartCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF0A1026), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class SearchDebugTopBarButton extends StatefulWidget {
  const SearchDebugTopBarButton({super.key});

  @override
  State<SearchDebugTopBarButton> createState() =>
      _SearchDebugTopBarButtonState();
}

class _SearchDebugTopBarButtonState extends State<SearchDebugTopBarButton> {
  final SearchDebugTrace _trace = SearchDebugTrace.instance;

  @override
  void initState() {
    super.initState();
    _trace.addListener(_onTraceChanged);
  }

  @override
  void dispose() {
    _trace.removeListener(_onTraceChanged);
    super.dispose();
  }

  void _onTraceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_trace.authorized) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: 'Open marketplace debug panel',
      child: TopBarActionFrame(
        child: IconButton(
          onPressed: () => context.go('/marketplace/debug'),
          icon: Icon(
            _trace.enabled ? Icons.bug_report : Icons.bug_report_outlined,
            size: 22,
          ),
          color: _trace.enabled
              ? const Color(0xFFFACC15)
              : const Color(0xFF38BDF8),
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints.tightFor(
            width: topBarActionSize,
            height: topBarActionSize,
          ),
        ),
      ),
    );
  }
}

class MarketplaceNavIconButton extends StatelessWidget {
  const MarketplaceNavIconButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.color = const Color(0xFF8B5CF6),
    this.backgroundColor,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: TopBarActionFrame(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: IconButton(
            onPressed: onTap,
            icon: Icon(icon, size: _topBarIconSize),
            color: color,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints.tightFor(
              width: topBarActionSize,
              height: topBarActionSize,
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileIconButton extends ConsumerWidget {
  const ProfileIconButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final photoUrl = profile?.photoUrl?.trim();
    return Tooltip(
      message: user == null ? 'Sign in' : 'Profile',
      child: InkWell(
        onTap: () =>
            context.go(user == null ? '/auth?from=/profile' : '/profile'),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: topBarActionSize,
          height: topBarActionSize,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: const Color(0xFF111936),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: ClipOval(
            child: photoUrl != null && photoUrl.isNotEmpty
                ? Image.network(
                    photoUrl,
                    key: ValueKey(photoUrl),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _ProfileIconFallback(
                      signedIn: user != null,
                    ),
                  )
                : _ProfileIconFallback(signedIn: user != null),
          ),
        ),
      ),
    );
  }
}

class _ProfileIconFallback extends StatelessWidget {
  const _ProfileIconFallback({required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B1020),
      alignment: Alignment.center,
      child: Icon(
        signedIn ? Icons.person_outline : Icons.login,
        color: const Color(0xFFFACC15),
        size: 20,
      ),
    );
  }
}

class MarketplaceTopBar extends StatelessWidget {
  const MarketplaceTopBar({
    super.key,
    required this.compactExpanded,
    required this.logo,
    required this.search,
    required this.languageMenu,
    this.actions = const SizedBox.shrink(),
  });

  final bool compactExpanded;
  final Widget logo;
  final Widget search;
  final Widget languageMenu;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 760;
    final logoSlotWidth = compact ? 52.0 : 56.0;
    final actionGap = compact ? 6.0 : 8.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            Container(
              width: compactExpanded ? 0 : logoSlotWidth,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: logo,
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: search,
              ),
            ),
            SizedBox(width: actionGap),
            SizedBox(
              width: topBarActionSize,
              height: topBarActionSize,
              child: Center(child: languageMenu),
            ),
            if (!compactExpanded) ...[
              SizedBox(width: actionGap),
              Flexible(
                flex: 0,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: actions,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class MarketplaceTopBarSearch extends ConsumerWidget {
  const MarketplaceTopBarSearch({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.compactTopBar,
    required this.onSearchFocusedChanged,
    required this.onSelected,
    this.enablePreviews = true,
    this.isSearching = false,
    this.query,
    this.onCompletionChanged,
    this.onShowAll,
    this.searchQueryParameters = const {},
    this.onEmptyFocus,
    this.holdOverlayForHero = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool compactTopBar;
  final bool enablePreviews;
  final bool isSearching;
  final String? query;
  final ValueChanged<bool> onSearchFocusedChanged;
  final ValueChanged<String>? onCompletionChanged;
  final Map<String, String> searchQueryParameters;
  final ValueChanged<SearchPreviewSelection> onSelected;
  final ValueChanged<String>? onShowAll;
  final VoidCallback? onEmptyFocus;
  final bool holdOverlayForHero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardState = ref.watch(cardProvider);
    return MarketplaceTopSearch(
      controller: controller,
      focusNode: focusNode,
      query: query ?? cardState.previewQuery,
      isSearching: enablePreviews ? cardState.isSearchingPreviews : isSearching,
      previews: enablePreviews ? cardState.searchPreviews : const [],
      enablePreviews: enablePreviews,
      completionText: cardState.searchCompletion,
      completionConfidence: cardState.searchCompletionConfidence,
      completionSource: cardState.searchCompletionSource,
      hintText: 'Search cards, sets, products...',
      onEmptyFocus: enablePreviews
          ? onEmptyFocus ?? () => _showDefaultEmptyFocus(ref)
          : null,
      onExit: (reason) =>
          ref.read(cardProvider.notifier).exitSearch(reason: reason),
      onChanged: (value) {
        onSearchFocusedChanged(focusNode.hasFocus);
        if (!enablePreviews) {
          ref.read(cardProvider.notifier).predictSearchCompletionOnly(value);
          onCompletionChanged?.call(value);
          return;
        }
        if (!compactTopBar && value.trim().isEmpty) {
          (onEmptyFocus ?? () => _showDefaultEmptyFocus(ref)).call();
        } else {
          ref.read(cardProvider.notifier).searchPreviewsOnly(value);
        }
      },
      onAcceptCompletion: (query) {
        final completed = ref
            .read(cardProvider.notifier)
            .acceptSearchCompletion(query, triggerSearch: false);
        controller.value = TextEditingValue(
          text: completed,
          selection: TextSelection.collapsed(offset: completed.length),
        );
      },
      onSelected: onSelected,
      holdOverlayForHero: holdOverlayForHero,
      onShowAll: (query) => goToMarketplaceSearch(
        context,
        ref,
        query,
        onShowAll: onShowAll,
        extraQueryParameters: searchQueryParameters,
      ),
    );
  }

  void _showDefaultEmptyFocus(WidgetRef ref) {
    showMarketplaceEmptyFocusSearchPreviews(ref);
  }
}

void showMarketplaceEmptyFocusSearchPreviews(WidgetRef ref) {
  ref.read(cardProvider.notifier).showHotSearchPreviewsForEmptyFocus(
        recentViews: ref.read(recentViewsProvider).views,
      );
}

Widget marketplaceTopBarActions({
  required BuildContext context,
  required int balance,
  required int itemCount,
  required bool compactTopBar,
  required bool compactSearchExpanded,
  required String keyValue,
  void Function(String location)? beforeNavigate,
}) {
  void go(String location) {
    beforeNavigate?.call(location);
    context.go(location);
  }

  return AnimatedSwitcher(
    duration: const Duration(milliseconds: 260),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: topBarActionsTransition,
    child: compactSearchExpanded
        ? const SizedBox.shrink()
        : SizedBox(
            key: ValueKey(keyValue),
            height: topBarActionSize,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!compactTopBar) ...[
                  MarketplaceNavIconButton(
                    label: 'Home',
                    icon: Icons.home_outlined,
                    onTap: () => go('/'),
                  ),
                  MarketplaceNavIconButton(
                    label: 'Forum',
                    icon: Icons.forum_outlined,
                    onTap: () => go('/forum'),
                  ),
                  MarketplaceNavIconButton(
                    label: 'Signal',
                    icon: Icons.query_stats,
                    onTap: () => go('/marketplace/signal'),
                  ),
                  MarketplaceNavIconButton(
                    label: 'Competitive',
                    icon: Icons.emoji_events,
                    color: const Color(0xFFFACC15),
                    backgroundColor: const Color(0x26FACC15),
                    onTap: () => go('/marketplace/competitive'),
                  ),
                ],
                if (compactTopBar)
                  MarketplaceNavIconButton(
                    label: 'Competitive',
                    icon: Icons.emoji_events,
                    color: const Color(0xFFFACC15),
                    backgroundColor: const Color(0x26FACC15),
                    onTap: () => go('/marketplace/competitive'),
                  ),
                const SearchDebugTopBarButton(),
                WalletBalanceButton(
                  balance: balance,
                  showIcon: !compactTopBar,
                  onTap: () => go('/wallet'),
                ),
                if (!compactTopBar) ...[
                  const SizedBox(width: 8),
                  const TopBarActionFrame(child: ProfileIconButton()),
                ],
                const SizedBox(width: 8),
                MarketplaceCartButton(
                  itemCount: itemCount,
                  compact: compactTopBar,
                  onTap: () => go('/cart'),
                ),
              ],
            ),
          ),
  );
}

void goToMarketplaceSearch(
  BuildContext context,
  WidgetRef ref,
  String query, {
  void Function(String query)? onShowAll,
  Map<String, String> extraQueryParameters = const {},
}) {
  final searchLanguage = ref.read(cardProvider).searchLanguage;
  if (onShowAll != null) {
    onShowAll(query);
    return;
  }
  context.go(
    Uri(
      path: '/marketplace/search',
      queryParameters: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        ...extraQueryParameters,
        if (searchLanguage != 'en') 'lang': searchLanguage,
        if (SearchDebugTrace.instance.enabled) 'searchDebug': '1',
      },
    ).toString(),
  );
}

void syncMarketplaceSearchDebugAuthorization(AppUserProfile? profile) {
  SearchDebugTrace.instance.setAuthorized(_isSearchDebugProfile(profile));
}

Widget topBarActionsTransition(Widget child, Animation<double> animation) {
  return child;
}

class SearchLanguageMenu extends StatelessWidget {
  const SearchLanguageMenu({
    super.key,
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
    'pt': 'PT',
    'nl': 'NL',
    'pl': 'PL',
    'ru': 'RU',
    'ko': 'KO',
    'id': 'ID',
    'th': 'TH',
    'ja': 'JA',
    'zh-cn': 'ZH-CN',
    'zh-tw': 'ZH-TW',
  };

  static const _flags = <String, String>{
    'en': '🇬🇧',
    'it': '🇮🇹',
    'fr': '🇫🇷',
    'de': '🇩🇪',
    'es': '🇪🇸',
    'pt': '🇵🇹',
    'nl': '🇳🇱',
    'pl': '🇵🇱',
    'ru': '🇷🇺',
    'ko': '🇰🇷',
    'id': '🇮🇩',
    'th': '🇹🇭',
    'ja': '🇯🇵',
    'zh-cn': '🇨🇳',
    'zh-tw': '🇹🇼',
  };

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeSearchLanguage(value);
    return PopupMenuButton<String>(
      tooltip: 'Search language',
      initialValue: normalized,
      onSelected: onChanged,
      color: const Color(0xFF111936),
      itemBuilder: (context) => [
        for (final entry in _languages.entries)
          PopupMenuItem(
            value: entry.key,
            child: Row(
              children: [
                Text(
                  _flags[entry.key] ?? '🌐',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  entry.value,
                  style: TextStyle(
                    color: entry.key == normalized
                        ? const Color(0xFFFACC15)
                        : const Color(0xFFE2E8F0),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: topBarActionSize,
        width: topBarActionSize,
        decoration: BoxDecoration(
          color: const Color(0xFF111936),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        alignment: Alignment.center,
        child: Text(
          _flags[normalized] ?? '🌐',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class MarketplaceLogoButton extends StatelessWidget {
  const MarketplaceLogoButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Image.network(
          ProjectLinks.logo,
          width: 40,
          height: 40,
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

Future<void> showMarketplaceSideMenu(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => const _MarketplaceSideMenu(),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

Future<void> showMarketplaceSideMenuWithNavigationIntent(
  BuildContext context,
  void Function(String location) beforeNavigate,
) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => _MarketplaceSideMenu(
      beforeNavigate: beforeNavigate,
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

class _MarketplaceSideMenu extends ConsumerWidget {
  const _MarketplaceSideMenu({this.beforeNavigate});

  final void Function(String location)? beforeNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final isAdmin = ref.watch(isAdminProvider);
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final debugEnabled = _isSearchDebugProfile(profile);
    final profileRoute = user == null ? '/auth?from=/profile' : '/profile';
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: const Color(0xFF0B1020),
        child: SafeArea(
          right: false,
          child: SizedBox(
            width: math.min(MediaQuery.sizeOf(context).width * 0.82, 320),
            height: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
                  child: Row(
                    children: [
                      MarketplaceLogoButton(
                        onTap: () => _goFromSideMenu(
                          context,
                          '/marketplace',
                          beforeNavigate: beforeNavigate,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Pokoin',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        color: const Color(0xFFE2E8F0),
                        tooltip: 'Close menu',
                      ),
                    ],
                  ),
                ),
                const Divider(color: Color(0x1AFFFFFF), height: 1),
                const SizedBox(height: 8),
                _MarketplaceSideMenuItem(
                  icon: Icons.home_outlined,
                  label: 'Home',
                  onTap: () => _goFromSideMenu(
                    context,
                    '/',
                    beforeNavigate: beforeNavigate,
                  ),
                ),
                _MarketplaceSideMenuItem(
                  icon: Icons.storefront_outlined,
                  label: 'Marketplace',
                  onTap: () => _goFromSideMenu(
                    context,
                    '/marketplace',
                    beforeNavigate: beforeNavigate,
                  ),
                ),
                _MarketplaceSideMenuItem(
                  icon: user == null ? Icons.login : Icons.person_outline,
                  label: user == null ? 'Sign in' : 'Profile',
                  onTap: () => _goFromSideMenu(
                    context,
                    profileRoute,
                    beforeNavigate: beforeNavigate,
                  ),
                ),
                _MarketplaceSideMenuItem(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Wallet',
                  onTap: () => _goFromSideMenu(
                    context,
                    '/wallet',
                    beforeNavigate: beforeNavigate,
                  ),
                ),
                _MarketplaceSideMenuItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Pokontact',
                  onTap: () => _goFromSideMenu(
                    context,
                    '/pokontact',
                    beforeNavigate: beforeNavigate,
                  ),
                ),
                _MarketplaceSideMenuItem(
                  icon: Icons.shopping_bag_outlined,
                  label: 'Cart',
                  onTap: () => _goFromSideMenu(
                    context,
                    '/cart',
                    beforeNavigate: beforeNavigate,
                  ),
                ),
                _MarketplaceSideMenuItem(
                  icon: Icons.forum_outlined,
                  label: 'Forum',
                  onTap: () => _goFromSideMenu(
                    context,
                    '/forum',
                    beforeNavigate: beforeNavigate,
                  ),
                ),
                _MarketplaceSideMenuItem(
                  icon: Icons.query_stats,
                  label: 'Signal',
                  onTap: () => _goFromSideMenu(
                    context,
                    '/marketplace/signal',
                    beforeNavigate: beforeNavigate,
                  ),
                ),
                _MarketplaceSideMenuItem(
                  icon: Icons.emoji_events,
                  label: 'Competitive',
                  onTap: () => _goFromSideMenu(
                    context,
                    '/marketplace/competitive',
                    beforeNavigate: beforeNavigate,
                  ),
                ),
                if (debugEnabled)
                  _MarketplaceSideMenuItem(
                    icon: Icons.bug_report_outlined,
                    label: 'Debug panel',
                    onTap: () => _goFromSideMenu(
                      context,
                      '/marketplace/debug',
                      beforeNavigate: beforeNavigate,
                    ),
                  ),
                if (isAdmin) ...[
                  const Divider(color: Color(0x1AFFFFFF)),
                  _MarketplaceSideMenuItem(
                    icon: Icons.admin_panel_settings,
                    label: 'Admin',
                    onTap: () => _goFromSideMenu(
                      context,
                      '/admin',
                      beforeNavigate: beforeNavigate,
                    ),
                  ),
                  _MarketplaceSideMenuItem(
                    icon: Icons.edit_outlined,
                    label: 'Edit listings',
                    onTap: () => _goFromSideMenu(
                      context,
                      '/marketplace/admin/edit',
                      beforeNavigate: beforeNavigate,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MarketplaceSideMenuItem extends StatelessWidget {
  const _MarketplaceSideMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFFFACC15)),
      title: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFE2E8F0),
          fontWeight: FontWeight.w800,
        ),
      ),
      onTap: onTap,
    );
  }
}

bool _isSearchDebugProfile(AppUserProfile? profile) {
  final username = profile?.username.trim().toLowerCase() ?? '';
  final email = profile?.email.trim().toLowerCase() ?? '';
  return username == 'vitologiuseppe17' ||
      email == 'vitologiuseppe17@gmail.com' ||
      email == 'pokoinpos@gmail.com' ||
      (profile?.hasAdminAccess ?? false);
}

void _goFromSideMenu(
  BuildContext context,
  String location, {
  void Function(String location)? beforeNavigate,
}) {
  Navigator.of(context).pop();
  beforeNavigate?.call(location);
  context.go(location);
}

class _SearchDebugPanel extends StatefulWidget {
  const _SearchDebugPanel();

  @override
  State<_SearchDebugPanel> createState() => _SearchDebugPanelState();
}

class _SearchDebugPanelState extends State<_SearchDebugPanel> {
  final SearchDebugTrace _trace = SearchDebugTrace.instance;

  @override
  void initState() {
    super.initState();
    _trace.addListener(_onTraceChanged);
  }

  @override
  void dispose() {
    _trace.removeListener(_onTraceChanged);
    super.dispose();
  }

  void _onTraceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventCount = _trace.events.length;
    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        width: 320,
        margin: const EdgeInsets.only(left: 16, bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1020),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Search debug capture',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Session ${_trace.sessionId}\n$eventCount events',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 11),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _trace.enabled
                        ? _trace.stop
                        : () => _trace.start(source: 'panel'),
                    child: Text(_trace.enabled ? 'Stop' : 'Start'),
                  ),
                  OutlinedButton(
                    onPressed: _trace.clear,
                    child: const Text('Clear'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _trace.exportJson()),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Search trace copied')),
                        );
                      }
                    },
                    child: const Text('Copy JSON'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MarketplaceTopSearch extends StatefulWidget {
  const MarketplaceTopSearch({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.isSearching,
    required this.previews,
    required this.hintText,
    required this.onChanged,
    required this.onSelected,
    required this.onShowAll,
    this.enablePreviews = true,
    this.completionText = '',
    this.completionConfidence = 0,
    this.completionSource = '',
    this.onAcceptCompletion,
    this.onEmptyFocus,
    this.onExit,
    this.holdOverlayForHero = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final bool isSearching;
  final List<PokemonCard> previews;
  final String hintText;
  final ValueChanged<String> onChanged;
  final ValueChanged<SearchPreviewSelection> onSelected;
  final ValueChanged<String> onShowAll;
  final bool enablePreviews;
  final String completionText;
  final double completionConfidence;
  final String completionSource;
  final ValueChanged<String>? onAcceptCompletion;
  final VoidCallback? onEmptyFocus;
  final ValueChanged<String>? onExit;
  final bool holdOverlayForHero;

  @override
  State<MarketplaceTopSearch> createState() => _MarketplaceTopSearchState();
}

class _MarketplaceTopSearchState extends State<MarketplaceTopSearch> {
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _overlayController =
      OverlayPortalController(debugLabel: 'marketplace-search-preview');
  final GlobalKey _fieldKey = GlobalKey();
  final ScrollController _previewScrollController = ScrollController();
  double _overlayWidth = 520;
  double _overlayMaxHeight = 520;
  Timer? _removeOverlayTimer;
  bool _keepOverlayOpenAfterBlur = false;
  bool _holdingOverlayForHero = false;
  bool _previewOpen = false;

  bool get _isCompactSearch {
    final size = _safeMediaSize();
    return size != null && size.width < 760;
  }

  bool get _hasCompletion =>
      widget.completionText.trim().isNotEmpty &&
      widget.completionText.trim() != widget.controller.text.trim();

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_syncOverlay);
  }

  @override
  void didUpdateWidget(covariant MarketplaceTopSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_syncOverlay);
      widget.focusNode.addListener(_syncOverlay);
    }
    _scheduleOverlaySync();
    _scheduleOverlaySync(delay: const Duration(milliseconds: 260));
  }

  @override
  void dispose() {
    _removeOverlayTimer?.cancel();
    widget.focusNode.removeListener(_syncOverlay);
    _previewOpen = false;
    _previewScrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    if (!_hasCompletion) {
      return KeyEventResult.ignored;
    }
    _handleSearchTab(reverse: HardwareKeyboard.instance.isShiftPressed);
    return KeyEventResult.handled;
  }

  void _syncOverlay() {
    if (!mounted) {
      return;
    }
    final mediaSize = _safeMediaSize();
    if (mediaSize == null) {
      _removeOverlay();
      return;
    }
    if (!widget.enablePreviews) {
      _keepOverlayOpenAfterBlur = false;
      _holdingOverlayForHero = false;
      _removeOverlayTimer?.cancel();
      _removeOverlay();
      return;
    }
    if (!widget.focusNode.hasFocus &&
        !_keepOverlayOpenAfterBlur &&
        _previewOpen) {
      widget.onExit?.call('blur');
    }
    final hasVisibleQuery =
        _meaningfulSearchLength(widget.query) >= searchPreviewVisibleChars;
    final hasEmptyQuery = widget.query.trim().isEmpty;
    final isCompactSearch = mediaSize.width < 760;
    final hasEmptyHotPreviews = hasEmptyQuery &&
        !isCompactSearch &&
        (widget.previews.isNotEmpty || widget.isSearching);
    if (hasEmptyQuery && !_holdingOverlayForHero) {
      _keepOverlayOpenAfterBlur = false;
    }
    final shouldShow =
        (widget.focusNode.hasFocus || _keepOverlayOpenAfterBlur) &&
            (hasVisibleQuery || hasEmptyHotPreviews);
    if (!shouldShow) {
      SearchDebugTrace.instance.record('flutter.overlay.hide_scheduled', {
        'query': widget.query,
        'hasFocus': widget.focusNode.hasFocus,
        'keepAfterBlur': _keepOverlayOpenAfterBlur,
        'previewCount': widget.previews.length,
      });
      if ((!widget.focusNode.hasFocus && !_keepOverlayOpenAfterBlur) ||
          widget.query.trim().isEmpty) {}
      _removeOverlayTimer?.cancel();
      if (_holdingOverlayForHero) {
        _setPreviewOpen(true);
      } else {
        _removeOverlayTimer = Timer(
          const Duration(milliseconds: 140),
          _removeOverlay,
        );
        _setPreviewOpen(false);
      }
      return;
    }
    if (hasVisibleQuery) {}
    _removeOverlayTimer?.cancel();
    final fieldContext = _fieldKey.currentContext;
    final fieldSize = fieldContext?.size;
    if (fieldSize != null) {
      _overlayWidth = fieldSize.width;
    }
    final fieldBox = fieldContext?.findRenderObject() as RenderBox?;
    final fieldOffset = fieldBox?.localToGlobal(Offset.zero);
    final mediaQuery = MediaQuery.maybeOf(context);
    final screenSize = mediaQuery?.size ?? mediaSize;
    final bottomPadding = mediaQuery?.padding.bottom ?? 0;
    final keyboardInset = mediaQuery?.viewInsets.bottom ?? 0;
    if (fieldOffset != null && fieldSize != null) {
      final availableBelow = screenSize.height -
          fieldOffset.dy -
          fieldSize.height -
          bottomPadding -
          keyboardInset -
          18;
      _overlayMaxHeight = availableBelow.clamp(220.0, 520.0);
    } else {
      _overlayMaxHeight = screenSize.height < 700 ? 360 : 520;
    }
    if (!_overlayController.isShowing) {
      SearchDebugTrace.instance.record('flutter.overlay.insert', {
        'query': widget.query,
        'previewCount': widget.previews.length,
        'isSearching': widget.isSearching,
        'width': _overlayWidth,
        'maxHeight': _overlayMaxHeight,
      });
      _overlayController.show();
    } else {
      SearchDebugTrace.instance.record('flutter.overlay.update', {
        'query': widget.query,
        'previewCount': widget.previews.length,
        'isSearching': widget.isSearching,
      });
      if (mounted) {
        setState(() {});
      }
    }
    _setPreviewOpen(true);
  }

  void _setPreviewOpen(bool value) {
    if (_previewOpen == value || !mounted) {
      return;
    }
    setState(() => _previewOpen = value);
  }

  void _scheduleOverlaySync({Duration delay = Duration.zero}) {
    if (delay == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncOverlay();
        }
      });
      return;
    }
    Future<void>.delayed(delay, () {
      if (mounted) {
        _syncOverlay();
      }
    });
  }

  void _selectPreview(SearchPreviewSelection selection) {
    SearchDebugTrace.instance.record('flutter.preview.selected', {
      'query': widget.query,
      'cardId': selection.card.id,
      'name': selection.card.name,
      'set': selection.card.set,
      'heroTag': selection.heroTag,
    });
    _removeOverlayTimer?.cancel();
    _keepOverlayOpenAfterBlur = widget.holdOverlayForHero;
    _holdingOverlayForHero = widget.holdOverlayForHero;
    widget.onSelected(selection);
    if (!widget.holdOverlayForHero) {
      widget.onExit?.call('selection');
      _keepOverlayOpenAfterBlur = false;
      _removeOverlay();
      widget.focusNode.unfocus();
      return;
    }
    _removeOverlayTimer = Timer(_searchPreviewHeroHoldDuration, () {
      if (!mounted) {
        return;
      }
      widget.onExit?.call('selection');
      _holdingOverlayForHero = false;
      _keepOverlayOpenAfterBlur = false;
      _removeOverlay();
      widget.focusNode.unfocus();
    });
  }

  void _showAll(String query) {
    SearchDebugTrace.instance.record('flutter.preview.show_all', {
      'query': query,
      'previewCount': widget.previews.length,
    });
    _removeOverlayTimer?.cancel();
    _keepOverlayOpenAfterBlur = false;
    _removeOverlay();
    widget.focusNode.unfocus();
    widget.onExit?.call('show_all');
    widget.onShowAll(query);
  }

  void _handleSearchTab({bool reverse = false}) {
    if (!_hasCompletion) {
      if (reverse) {
        widget.focusNode.previousFocus();
      } else {
        widget.focusNode.nextFocus();
      }
      return;
    }
    _acceptCompletion();
  }

  void _acceptCompletion() {
    final typedQuery = widget.controller.text;
    final completion = widget.completionText.trim();
    if (completion.isEmpty) {
      return;
    }
    SearchDebugTrace.instance.record('flutter.completion.accept', {
      'query': widget.controller.text,
      'completion': completion,
      'confidence': widget.completionConfidence,
      'source': widget.completionSource,
    });
    widget.controller.value = TextEditingValue(
      text: completion,
      selection: TextSelection.collapsed(offset: completion.length),
    );
    if (widget.onAcceptCompletion != null) {
      widget.onAcceptCompletion!(typedQuery);
    }
    widget.onChanged(completion);
    _syncOverlay();
    _scheduleOverlaySync();
  }

  double _completionSuffixLeftOffset(String typedText) {
    if (typedText.isEmpty) {
      return 0;
    }
    final textScaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(
        text: typedText,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout();
    return painter.width;
  }

  void _handoffFocusToPreview() {
    if (widget.query.trim().isEmpty) {
      return;
    }
    _keepOverlayOpenAfterBlur = true;
    _removeOverlayTimer?.cancel();
    if (_isCompactSearch && widget.focusNode.hasFocus) {
      widget.focusNode.unfocus();
    }
    _scheduleOverlaySync();
  }

  Size? _safeMediaSize() {
    if (!mounted) {
      return null;
    }
    return MediaQuery.maybeSizeOf(context);
  }

  void _removeOverlay({bool updatePreviewOpen = true}) {
    if (_overlayController.isShowing) {
      SearchDebugTrace.instance.record('flutter.overlay.removed', {
        'query': widget.query,
        'previewCount': widget.previews.length,
      });
    }
    _removeOverlayTimer?.cancel();
    _removeOverlayTimer = null;
    if (_overlayController.isShowing) {
      _overlayController.hide();
    }
    if (updatePreviewOpen) {
      _setPreviewOpen(false);
    } else {
      _previewOpen = false;
    }
  }

  Widget _buildOverlay(BuildContext context) {
    return CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, 8),
      child: UnconstrainedBox(
        alignment: Alignment.topLeft,
        child: Material(
          color: Colors.transparent,
          child: TextFieldTapRegion(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _handoffFocusToPreview(),
              child: SizedBox(
                width: _overlayWidth,
                child: _SearchPreviewPanel(
                  query: widget.query,
                  cards: widget.previews,
                  isSearching: widget.isSearching,
                  maxHeight: _overlayMaxHeight,
                  scrollController: _previewScrollController,
                  onSelected: _selectPreview,
                  onShowAll: _showAll,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewOpen = _previewOpen || _overlayController.isShowing;
    final completionText = widget.completionText.trim();
    final typedText = widget.controller.text.trim();
    final showCompletion =
        completionText.isNotEmpty && completionText != typedText;
    final completionSuffixStart = showCompletion
        ? searchCompletionSuffixStart(typedText, completionText)
        : 0;
    final completionSuffix = completionSuffixStart > 0
        ? completionText.substring(completionSuffixStart)
        : '';
    final mobileCompletionLeft =
        _isCompactSearch ? _completionSuffixLeftOffset(typedText) : 0.0;
    final completionDebugLabel = SearchDebugTrace.instance.enabled &&
            showCompletion
        ? 'Tab ${widget.completionConfidence.toStringAsFixed(0)}% ${widget.completionSource}'
        : 'Tab';
    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: _buildOverlay,
        child: Focus(
          onKeyEvent: _handleSearchKeyEvent,
          canRequestFocus: false,
          child: AnimatedContainer(
            key: _fieldKey,
            height: previewOpen ? 48 : 42,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: previewOpen
                  ? [
                      BoxShadow(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.18),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  onChanged: (value) {
                    SearchDebugTrace.instance.record('flutter.input.changed', {
                      'query': value,
                      'length': value.length,
                      'chars': value.characters.toList(),
                    });
                    widget.onChanged(value);
                  },
                  onTap: () {
                    SearchDebugTrace.instance.record('flutter.input.tap', {
                      'query': widget.query,
                      'hasFocus': widget.focusNode.hasFocus,
                    });
                    if (_isCompactSearch && _hasCompletion) {
                      _acceptCompletion();
                      return;
                    }
                    _keepOverlayOpenAfterBlur = false;
                    if (!widget.enablePreviews) {
                      return;
                    }
                    if (!_isCompactSearch &&
                        widget.controller.text.trim().isEmpty) {
                      widget.onEmptyFocus?.call();
                    }
                    _syncOverlay();
                    if (_isCompactSearch &&
                        _meaningfulSearchLength(widget.query) >=
                            searchPreviewVisibleChars) {
                      _handoffFocusToPreview();
                    }
                  },
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (value) {
                    SearchDebugTrace.instance
                        .record('flutter.input.submitted', {
                      'query': value,
                    });
                    widget.onExit?.call('submit');
                    widget.onShowAll(value);
                  },
                  decoration: InputDecoration(
                    prefixIcon:
                        const Icon(Icons.search, color: Color(0xFFFACC15)),
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
                                  SearchDebugTrace.instance.record(
                                    'flutter.input.clear',
                                    {'query': widget.controller.text},
                                  );
                                  widget.controller.clear();
                                  _keepOverlayOpenAfterBlur = false;
                                  widget.onExit?.call('clear');
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
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(
                        color: previewOpen
                            ? const Color(0xFF38BDF8).withValues(alpha: 0.38)
                            : Colors.transparent,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(
                        color: previewOpen
                            ? const Color(0xFF38BDF8).withValues(alpha: 0.58)
                            : const Color(0xFFFACC15).withValues(alpha: 0.28),
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (showCompletion)
                  Positioned.fill(
                    left: _isCompactSearch ? 48 + mobileCompletionLeft : 48,
                    right: widget.controller.text.isEmpty ? 14 : 48,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Semantics(
                          label: 'Autocomplete suggestion $completionText',
                          child: _isCompactSearch
                              ? Text(
                                  completionSuffix.isEmpty
                                      ? completionText
                                      : completionSuffix,
                                  style: TextStyle(
                                    color: const Color(0xFF93A4C8)
                                        .withValues(alpha: 0.62),
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.clip,
                                  maxLines: 1,
                                )
                              : Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: typedText,
                                        style: const TextStyle(
                                          color: Colors.transparent,
                                          fontSize: 14,
                                        ),
                                      ),
                                      TextSpan(
                                        text: completionSuffix.isEmpty
                                            ? completionText
                                            : completionSuffix,
                                        style: TextStyle(
                                          color: const Color(0xFF93A4C8)
                                              .withValues(alpha: 0.62),
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  overflow: TextOverflow.clip,
                                  maxLines: 1,
                                ),
                        ),
                      ),
                    ),
                  ),
                if (showCompletion && !_isCompactSearch)
                  Positioned(
                    right: widget.controller.text.isEmpty ? 14 : 48,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF24324F).withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          completionDebugLabel,
                          style: const TextStyle(
                            color: Color(0xFFB6C3E3),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
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
    required this.maxHeight,
    required this.scrollController,
    required this.onSelected,
    required this.onShowAll,
  });

  final String query;
  final List<PokemonCard> cards;
  final bool isSearching;
  final double maxHeight;
  final ScrollController scrollController;
  final ValueChanged<SearchPreviewSelection> onSelected;
  final ValueChanged<String> onShowAll;

  @override
  Widget build(BuildContext context) {
    final trimmedQuery = query.trim();
    if (_meaningfulSearchLength(trimmedQuery) < searchPreviewVisibleChars &&
        cards.isEmpty &&
        !isSearching) {
      return const SizedBox.shrink();
    }

    final singles = cards.where(_isSingle).toList();
    final products = cards.where(_isProduct).toList();
    final hasResults = singles.isNotEmpty || products.isNotEmpty;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final rowHeight = compact ? 82.0 : 116.0;
    final isTypedPreview =
        _meaningfulSearchLength(trimmedQuery) >= searchPreviewVisibleChars;
    final loadingRowCount = isTypedPreview ? searchPreviewLimit : 1;
    final visibleRows = hasResults ? searchPreviewVisibleRows : loadingRowCount;
    final desiredHeight = rowHeight * visibleRows;

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
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.min(maxHeight, desiredHeight),
        ),
        child: Scrollbar(
          controller: scrollController,
          thumbVisibility: cards.length > searchPreviewVisibleRows,
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            primary: false,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            children: hasResults
                ? [
                    _SearchPreviewSection(
                      title: trimmedQuery.isEmpty ? 'Hot singles' : 'Singles',
                      icon: Icons.style_outlined,
                      cards: singles,
                      query: trimmedQuery,
                      isSearching: isSearching,
                      compact: compact,
                      showSpinner: true,
                      onSelected: onSelected,
                    ),
                    _SearchPreviewSection(
                      title: 'Products',
                      icon: Icons.inventory_2_outlined,
                      cards: products,
                      query: trimmedQuery,
                      isSearching: isSearching,
                      compact: compact,
                      onSelected: onSelected,
                    ),
                  ]
                : [
                    _SearchPreviewLoading(
                      query: trimmedQuery,
                      isSearching: isSearching,
                      compact: compact,
                    ),
                  ],
          ),
        ),
      ),
    );
  }

  bool _isProduct(PokemonCard card) => card.itemKind == 'product';

  bool _isSingle(PokemonCard card) => !_isProduct(card);
}

int _meaningfulSearchLength(String query) {
  return RegExp(r'[a-z0-9]', caseSensitive: false).allMatches(query).length;
}

TextSpan _highlightedSearchText(
  String text,
  String query, {
  required TextStyle baseStyle,
  Set<String> consumedTerms = const {},
}) {
  final terms = _highlightTerms(query)
      .where((term) => !consumedTerms.contains(term))
      .toList();
  if (text.isEmpty || terms.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }

  final lowerText = text.toLowerCase();
  final matches = <({int start, int end})>[];
  var index = 0;
  while (index < text.length) {
    ({int start, int end})? nextMatch;
    for (final term in terms) {
      final start = lowerText.indexOf(term, index);
      if (start < 0) {
        continue;
      }
      final match = (start: start, end: start + term.length);
      if (nextMatch == null ||
          match.start < nextMatch.start ||
          (match.start == nextMatch.start && match.end > nextMatch.end)) {
        nextMatch = match;
      }
    }
    if (nextMatch == null) {
      break;
    }
    if (matches.isEmpty || nextMatch.start >= matches.last.end) {
      matches.add(nextMatch);
      index = nextMatch.end;
    } else {
      index += 1;
    }
  }

  if (matches.isEmpty) {
    final characterMatches = _orderedCharacterHighlightMatches(text, query);
    if (characterMatches.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }
    return _highlightTextRanges(text, characterMatches, baseStyle);
  }

  return _highlightTextRanges(text, _mergeHighlightRanges(matches), baseStyle);
}

TextSpan _highlightTextRanges(
  String text,
  List<({int start, int end})> matches,
  TextStyle baseStyle,
) {
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    spans.add(
      TextSpan(
        text: text.substring(match.start, match.end),
        style: baseStyle.copyWith(
          color: const Color(0xFFFACC15),
          fontWeight: FontWeight.w900,
          backgroundColor: const Color(0x332F3A12),
        ),
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return TextSpan(style: baseStyle, children: spans);
}

List<({int start, int end})> _mergeHighlightRanges(
  List<({int start, int end})> ranges,
) {
  final sorted = ranges.where((range) => range.start < range.end).toList()
    ..sort((a, b) {
      final start = a.start.compareTo(b.start);
      return start != 0 ? start : a.end.compareTo(b.end);
    });
  if (sorted.isEmpty) {
    return const [];
  }
  final merged = <({int start, int end})>[sorted.first];
  for (final range in sorted.skip(1)) {
    final last = merged.last;
    if (range.start <= last.end) {
      merged[merged.length - 1] = (
        start: last.start,
        end: math.max(last.end, range.end),
      );
    } else {
      merged.add(range);
    }
  }
  return merged;
}

List<({int start, int end})> _orderedCharacterHighlightMatches(
  String text,
  String query,
) {
  final normalizedQuery =
      query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (text.isEmpty || normalizedQuery.isEmpty) {
    return const [];
  }
  final queryChars = normalizedQuery.split('');
  final best = List.filled(queryChars.length + 1, <int>[]);
  final searchableChar = RegExp(r'[a-z0-9]', caseSensitive: false);
  for (var textIndex = 0; textIndex < text.length; textIndex++) {
    final normalizedChar = text[textIndex].toLowerCase();
    if (!searchableChar.hasMatch(normalizedChar)) {
      continue;
    }
    for (var queryIndex = queryChars.length - 1;
        queryIndex >= 0;
        queryIndex--) {
      if (queryChars[queryIndex] != normalizedChar) {
        continue;
      }
      final candidate = [...best[queryIndex], textIndex];
      if (_isBetterHighlightPath(candidate, best[queryIndex + 1])) {
        best[queryIndex + 1] = candidate;
      }
    }
  }
  final indexes = best.reduce(
    (currentBest, candidate) => _isBetterHighlightPath(candidate, currentBest)
        ? candidate
        : currentBest,
  );
  if (indexes.length < math.min(2, normalizedQuery.length)) {
    return const [];
  }
  return [
    for (final index in indexes) (start: index, end: index + 1),
  ];
}

bool _isBetterHighlightPath(List<int> candidate, List<int> currentBest) {
  if (candidate.length != currentBest.length) {
    return candidate.length > currentBest.length;
  }
  if (candidate.isEmpty) {
    return false;
  }
  final candidateSpan = candidate.last - candidate.first;
  final bestSpan = currentBest.last - currentBest.first;
  if (candidateSpan != bestSpan) {
    return candidateSpan < bestSpan;
  }
  return candidate.first < currentBest.first;
}

List<String> _highlightTerms(String query) {
  final terms = query
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .map((term) => term.trim())
      .where((term) => term.length >= 2)
      .toSet()
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  return terms;
}

class _SearchPreviewSection extends StatelessWidget {
  const _SearchPreviewSection({
    required this.title,
    required this.icon,
    required this.cards,
    required this.query,
    required this.isSearching,
    required this.onSelected,
    required this.compact,
    this.showSpinner = false,
  });

  final String title;
  final IconData icon;
  final List<PokemonCard> cards;
  final String query;
  final bool isSearching;
  final ValueChanged<SearchPreviewSelection> onSelected;
  final bool compact;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title == 'Products')
          _SearchPreviewSectionHeader(
            title: title,
            icon: icon,
            compact: compact,
          ),
        for (final card in cards)
          _SearchPreviewRow(
            card: card,
            query: query,
            compact: compact,
            onSelected: onSelected,
          ),
      ],
    );
  }
}

class _SearchPreviewSectionHeader extends StatelessWidget {
  const _SearchPreviewSectionHeader({
    required this.title,
    required this.icon,
    required this.compact,
  });

  final String title;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 38 : 48,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFF070C1C).withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: compact ? 16 : 18, color: const Color(0xFFFACC15)),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: const Color(0xFFFACC15),
              fontSize: compact ? 13 : 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchPreviewLoading extends StatefulWidget {
  const _SearchPreviewLoading({
    required this.query,
    required this.isSearching,
    required this.compact,
  });

  final String query;
  final bool isSearching;
  final bool compact;

  @override
  State<_SearchPreviewLoading> createState() => _SearchPreviewLoadingState();
}

class _SearchPreviewLoadingState extends State<_SearchPreviewLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _vaporController;

  @override
  void initState() {
    super.initState();
    _vaporController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _vaporController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTypedPreview =
        _meaningfulSearchLength(widget.query) >= searchPreviewVisibleChars;
    if (isTypedPreview && widget.isSearching) {
      return AnimatedBuilder(
        animation: _vaporController,
        builder: (context, child) {
          final vaporProgress = _vaporController.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < searchPreviewLimit; index += 1)
                _SearchPreviewSkeletonRow(
                  compact: widget.compact,
                  vaporProgress: (vaporProgress + (index * 0.055)) % 1.0,
                ),
            ],
          );
        },
      );
    }
    final message = widget.isSearching
        ? (widget.query.trim().isEmpty
            ? 'Loading hot cards...'
            : 'Refining results...')
        : 'No quick matches yet.';
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFF111936),
      child: Row(
        children: [
          if (widget.isSearching) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFFACC15),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFE5E7EB),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchPreviewSkeletonRow extends StatelessWidget {
  const _SearchPreviewSkeletonRow({
    required this.compact,
    required this.vaporProgress,
  });

  final bool compact;
  final double vaporProgress;

  @override
  Widget build(BuildContext context) {
    final vaporOffset = (vaporProgress * 2.4) - 0.7;
    return ClipRect(
      child: Container(
        height: compact ? 82 : 116,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 16,
          vertical: compact ? 8 : 10,
        ),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF1E2A4A))),
        ),
        child: Stack(
          children: [
            Row(
              children: [
                _SearchPreviewSkeletonBox(
                  width: compact ? 26 : 34,
                  height: compact ? 26 : 34,
                  borderRadius: compact ? 7 : 9,
                ),
                SizedBox(width: compact ? 6 : 8),
                _SearchPreviewSkeletonBox(
                  width: compact ? 50 : 80,
                  height: compact ? 66 : 100,
                  borderRadius: 6,
                ),
                SizedBox(width: compact ? 10 : 18),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SearchPreviewSkeletonBox(
                        width: double.infinity,
                        height: compact ? 18 : 28,
                        borderRadius: 999,
                      ),
                      const SizedBox(height: 8),
                      FractionallySizedBox(
                        widthFactor: 0.62,
                        child: _SearchPreviewSkeletonBox(
                          width: double.infinity,
                          height: compact ? 14 : 22,
                          borderRadius: 999,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: compact ? 10 : 18),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _SearchPreviewSkeletonBox(
                      width: compact ? 44 : 70,
                      height: compact ? 13 : 20,
                      borderRadius: 999,
                    ),
                    const SizedBox(height: 8),
                    _SearchPreviewSkeletonBox(
                      width: compact ? 52 : 84,
                      height: compact ? 12 : 18,
                      borderRadius: 999,
                    ),
                  ],
                ),
              ],
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: FractionalTranslation(
                  translation: Offset(vaporOffset, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: compact ? 96 : 160,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            const Color(0xFF38BDF8).withValues(alpha: 0.04),
                            Colors.white.withValues(alpha: 0.10),
                            const Color(0xFFFACC15).withValues(alpha: 0.035),
                            Colors.transparent,
                          ],
                          stops: const [0, 0.28, 0.5, 0.72, 1],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPreviewSkeletonBox extends StatelessWidget {
  const _SearchPreviewSkeletonBox({
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0.05),
          ],
        ),
      ),
    );
  }
}

class SearchPreviewSelection {
  const SearchPreviewSelection({
    required this.card,
    required this.heroTag,
  });

  final PokemonCard card;
  final String heroTag;
}

class _SearchPreviewRow extends StatelessWidget {
  const _SearchPreviewRow({
    required this.card,
    required this.query,
    required this.compact,
    required this.onSelected,
  });

  final PokemonCard card;
  final String query;
  final bool compact;
  final ValueChanged<SearchPreviewSelection> onSelected;

  @override
  Widget build(BuildContext context) {
    final isProduct = card.itemKind == 'product';
    final kindLabel = isProduct ? card.type : 'Singles';
    final title = _previewTitle(card);
    final titleConsumedTerms = _consumedHighlightTerms(title, query);
    final heroTag = _cardHeroTag(card, 'search-preview');
    final paletteHint = cardPaletteHint(
      type: card.type,
      name: card.name,
      tags: card.tags,
    );
    final rowGradient = cardAccentHeaderGradientForPayload(
      card.cardPalette,
      fallbackType: paletteHint,
    );
    final row = InkWell(
      onTap: () => onSelected(
        SearchPreviewSelection(
          card: card,
          heroTag: heroTag,
        ),
      ),
      child: Container(
        height: compact ? 82 : 116,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 16,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: rowGradient.begin,
            end: rowGradient.end,
            colors: [
              rowGradient.colors.first.withValues(alpha: 0.34),
              rowGradient.colors.last.withValues(alpha: 0.24),
              const Color(0xFF0B1024).withValues(alpha: 0.82),
            ],
            stops: const [0, 0.52, 1],
          ),
          border: Border(
            top: BorderSide(
              color: rowGradient.colors.last.withValues(alpha: 0.44),
            ),
          ),
        ),
        child: Row(
          children: [
            _SearchPreviewArtwork(
              card: card,
              paletteHint: paletteHint,
              compact: compact,
            ),
            SizedBox(width: compact ? 10 : 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: _highlightedSearchText(
                      title,
                      query,
                      baseStyle: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: compact ? 17 : 26,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: _highlightedSearchText(
                      card.set,
                      query,
                      consumedTerms: titleConsumedTerms,
                      baseStyle: TextStyle(
                        color: const Color(0xFF93A4C8),
                        fontSize: compact ? 14 : 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: compact ? 4 : 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  kindLabel,
                  style: TextStyle(
                    color: const Color(0xFF93A4C8),
                    fontSize: compact ? 13 : 20,
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
                  style: TextStyle(
                    color: const Color(0xFFFACC15),
                    fontSize: compact ? 12 : 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return _SearchPreviewHeroRow(heroTag: heroTag, child: row);
  }

  String _previewTitle(PokemonCard card) {
    return _cardTitleWithNumber(card);
  }
}

class _SearchPreviewHeroRow extends StatelessWidget {
  const _SearchPreviewHeroRow({
    required this.heroTag,
    required this.child,
  });

  final String heroTag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (heroTag.isEmpty) {
      return child;
    }
    return Hero(
      tag: heroTag,
      flightShuttleBuilder: (
        _,
        animation,
        __,
        ___,
        toHeroContext,
      ) {
        return ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: Material(
            color: Colors.transparent,
            child: toHeroContext.widget,
          ),
        );
      },
      child: child,
    );
  }
}

class _SearchPreviewArtwork extends StatelessWidget {
  const _SearchPreviewArtwork({
    required this.card,
    required this.paletteHint,
    required this.compact,
  });

  final PokemonCard card;
  final String paletteHint;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ExpansionSymbolBadge(
          imageUrl: card.expansionSymbolUrl,
          setName: card.set,
          compact: compact,
        ),
        SizedBox(width: compact ? 6 : 8),
        _CardImageFrame(
          width: compact ? 50 : 80,
          height: compact ? 66 : 100,
          imageUrl: card.previewImageUrl,
          fallbackImageUrl: card.imageUrl,
          cardType: paletteHint,
          cardPalette: card.cardPalette,
          borderRadius: BorderRadius.circular(6),
          padding: const EdgeInsets.all(4),
          fallbackSize: 32,
        ),
      ],
    );
  }
}

class _ExpansionSymbolBadge extends StatelessWidget {
  const _ExpansionSymbolBadge({
    required this.imageUrl,
    required this.setName,
    required this.compact,
  });

  final String imageUrl;
  final String setName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final trimmedImageUrl = imageUrl.trim();
    final fallbackLabel = _setCodeFallback(setName);
    final size = compact ? 26.0 : 34.0;

    return Tooltip(
      message: setName.trim().isEmpty ? 'Expansion' : setName.trim(),
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(compact ? 3 : 4),
        decoration: BoxDecoration(
          color: const Color(0xFF111936),
          borderRadius: BorderRadius.circular(compact ? 7 : 9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: trimmedImageUrl.isEmpty
            ? _ExpansionCodeFallback(label: fallbackLabel, compact: compact)
            : CachedNetworkImage(
                imageUrl: trimmedImageUrl,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                errorWidget: (_, __, ___) => _ExpansionCodeFallback(
                    label: fallbackLabel, compact: compact),
              ),
      ),
    );
  }

  String _setCodeFallback(String value) {
    final words = value
        .trim()
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return '?';
    }
    if (words.length == 1) {
      return words.first.characters.take(3).toString().toUpperCase();
    }
    return words
        .take(3)
        .map((word) => word.characters.first.toUpperCase())
        .join();
  }
}

class _ExpansionCodeFallback extends StatelessWidget {
  const _ExpansionCodeFallback({
    required this.label,
    required this.compact,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: const Color(0xFFFACC15),
          fontSize: compact ? 9 : 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

Set<String> _consumedHighlightTerms(String text, String query) {
  if (text.isEmpty || query.isEmpty) {
    return const {};
  }
  final lowerText = text.toLowerCase();
  return _highlightTerms(query)
      .where((term) => lowerText.contains(term))
      .toSet();
}

class _CardCarouselSection extends StatefulWidget {
  const _CardCarouselSection({
    required this.title,
    required this.cards,
    this.seeMoreQuery,
    this.isLoading = false,
    this.isSkeleton = false,
  });

  final String title;
  final List<PokemonCard> cards;
  final String? seeMoreQuery;
  final bool isLoading;
  final bool isSkeleton;

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
    if (widget.cards.isEmpty && !widget.isLoading && !widget.isSkeleton) {
      return const SizedBox.shrink();
    }
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 900;
    final isMobile = screenWidth < 760;
    final useDesktopControls = isDesktop && hasDesktopPointer();
    final cardWidth =
        screenWidth < 560 ? math.min(screenWidth - 44, 316).toDouble() : 360.0;
    final showSkeletonCards = widget.isSkeleton || widget.isLoading;
    final itemCount = showSkeletonCards
        ? _skeletonCarouselItemCount(screenWidth)
        : widget.cards.length;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncArrowVisibility());
    final contentInset = screenWidth >= 1264 ? (screenWidth - 1220) / 2 : 22.0;
    if (isMobile) {
      final mobileCards = widget.cards.take(3).toList(growable: false);
      final mobileItemCount = showSkeletonCards ? 3 : mobileCards.length;
      final mobileList = Padding(
        padding: EdgeInsets.symmetric(horizontal: contentInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeading(title: widget.title),
            const SizedBox(height: 14),
            for (var index = 0; index < mobileItemCount; index++) ...[
              SizedBox(
                height: screenWidth < 560 ? 184 : 210,
                child: showSkeletonCards
                    ? const _MarketplaceSkeletonFeatureCard()
                    : _FeaturedCard(
                        card: mobileCards[index],
                        heroTag: widget.title == 'Recently seen'
                            ? _recentlySeenHeroTag(mobileCards[index], index)
                            : _cardHeroTag(
                                mobileCards[index],
                                'carousel-${widget.title}-$index',
                              ),
                      ),
              ),
              if (index != mobileItemCount - 1) const SizedBox(height: 14),
            ],
            if (!showSkeletonCards && mobileCards.isNotEmpty) ...[
              const SizedBox(height: 14),
              _SectionSeeMoreButton(
                title: widget.title,
                query: widget.seeMoreQuery,
              ),
            ],
          ],
        ),
      );
      final hasSkeletonPulse =
          _MarketplaceSkeletonPulseScope.maybeOf(context) != null;
      return showSkeletonCards && !hasSkeletonPulse
          ? _MarketplaceSkeletonPulse(child: mobileList)
          : mobileList;
    }
    final carousel = SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: contentInset),
            child: _SectionHeading(title: widget.title),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: screenWidth < 560 ? 184 : 210,
            child: Stack(
              children: [
                ListView.separated(
                  controller: _scrollController,
                  cacheExtent: 0,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  physics: useDesktopControls
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  scrollDirection: Axis.horizontal,
                  itemCount: itemCount,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    if (showSkeletonCards) {
                      return SizedBox(
                        width: cardWidth,
                        child: const _MarketplaceSkeletonFeatureCard(),
                      );
                    }
                    final card = widget.cards[index];
                    final tile = SizedBox(
                      width: cardWidth,
                      child: _FeaturedCard(
                        card: card,
                        heroTag: widget.title == 'Recently seen'
                            ? _recentlySeenHeroTag(card, index)
                            : _cardHeroTag(
                                card,
                                'carousel-${widget.title}-$index',
                              ),
                      ),
                    );
                    if (!isDesktop) {
                      return _MobileCarouselAnimatedTile(
                        key: ValueKey(
                            'carousel-${widget.title}-${card.id}-$index'),
                        child: tile,
                      );
                    }
                    return tile;
                  },
                ),
                if (useDesktopControls &&
                    !showSkeletonCards &&
                    widget.cards.length > 2) ...[
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
    final hasSkeletonPulse =
        _MarketplaceSkeletonPulseScope.maybeOf(context) != null;
    return showSkeletonCards && !hasSkeletonPulse
        ? _MarketplaceSkeletonPulse(child: carousel)
        : carousel;
  }
}

int _skeletonCarouselItemCount(double screenWidth) {
  if (screenWidth < 560) {
    return 2;
  }
  if (screenWidth < 900) {
    return 3;
  }
  return 4;
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

class _SectionSeeMoreButton extends ConsumerWidget {
  const _SectionSeeMoreButton({
    required this.title,
    required this.query,
  });

  final String title;
  final String? query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () {
          goToMarketplaceSearch(context, ref, query ?? title);
        },
        icon: const Icon(Icons.arrow_forward),
        label: Text('See more $title'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFFACC15),
          side: BorderSide(
            color: const Color(0xFFFACC15).withValues(alpha: 0.6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _MobileCarouselAnimatedTile extends StatefulWidget {
  const _MobileCarouselAnimatedTile({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<_MobileCarouselAnimatedTile> createState() =>
      _MobileCarouselAnimatedTileState();
}

class _MobileCarouselAnimatedTileState
    extends State<_MobileCarouselAnimatedTile> {
  Timer? _showTimer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _showTimer = Timer(const Duration(milliseconds: 40), () {
      if (mounted) {
        setState(() => _visible = true);
      }
    });
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0.08, 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _MarketHeader extends StatelessWidget {
  const _MarketHeader();

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 760) {
      return const SizedBox.shrink();
    }

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
    final label = count == 1 ? '1 result' : '$count results';
    return _SectionHeading(
      title: query.isEmpty
          ? 'All marketplace results · $label'
          : 'Results for "$query" · $label',
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
    required this.selectedProductType,
    required this.selectedExpansion,
    required this.selectedRarity,
    required this.productCounts,
    required this.expansionCounts,
    required this.expansionImages,
    required this.rarityCounts,
    required this.onProductTypeChanged,
    required this.onExpansionChanged,
    required this.onRarityChanged,
    required this.onClear,
  });

  final String? selectedProductType;
  final String? selectedExpansion;
  final String? selectedRarity;
  final Map<String, int> productCounts;
  final Map<String, int> expansionCounts;
  final Map<String, String> expansionImages;
  final Map<String, int> rarityCounts;
  final ValueChanged<String?> onProductTypeChanged;
  final ValueChanged<String?> onExpansionChanged;
  final ValueChanged<String?> onRarityChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasFilters = selectedExpansion?.isNotEmpty == true ||
        selectedRarity?.isNotEmpty == true ||
        selectedProductType?.isNotEmpty == true;
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
                    if (selectedProductType?.isNotEmpty == true)
                      _FilterChipLabel(
                        label: _marketplaceProductTypeLabel(
                          selectedProductType!,
                        ),
                      ),
                    if (selectedExpansion?.isNotEmpty == true)
                      _FilterChipLabel(label: selectedExpansion!),
                    if (selectedRarity?.isNotEmpty == true)
                      _FilterChipLabel(label: selectedRarity!),
                    if (!hasFilters)
                      const Text(
                        'No filters applied',
                        style: TextStyle(color: Color(0xFF93A4C8)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          _FilterDivider(),
          _FacetSection(
            title: 'PRODUCTS',
            placeholder: 'Product',
            selectedValue: selectedProductType,
            counts: productCounts,
            labels: {
              for (final productType in productCounts.keys)
                productType: _marketplaceProductTypeLabel(productType),
            },
            onChanged: onProductTypeChanged,
            showPicker: false,
            optionLimit: null,
          ),
          _FilterDivider(),
          _FacetSection(
            title: 'EXPANSION',
            placeholder: 'Expansion',
            selectedValue: selectedExpansion,
            counts: expansionCounts,
            images: expansionImages,
            onChanged: onExpansionChanged,
            showPicker: false,
            optionLimit: null,
            optionsMaxHeight: MediaQuery.sizeOf(context).height * 0.56,
          ),
          _FilterDivider(),
          _FacetSection(
            title: 'RARITY',
            placeholder: 'Rarity',
            selectedValue: selectedRarity,
            counts: rarityCounts,
            onChanged: onRarityChanged,
            showPicker: false,
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
}

class _FacetSection extends StatelessWidget {
  const _FacetSection({
    required this.title,
    required this.placeholder,
    required this.selectedValue,
    required this.counts,
    required this.onChanged,
    this.images = const {},
    this.labels = const {},
    this.showPicker = true,
    this.optionLimit = 6,
    this.optionsMaxHeight,
  });

  final String title;
  final String placeholder;
  final String? selectedValue;
  final Map<String, int> counts;
  final ValueChanged<String?> onChanged;
  final Map<String, String> images;
  final Map<String, String> labels;
  final bool showPicker;
  final int? optionLimit;
  final double? optionsMaxHeight;

  @override
  Widget build(BuildContext context) {
    final entries = optionLimit == null
        ? counts.entries.toList()
        : counts.entries.take(optionLimit!).toList();
    final options = entries
        .map(
          (entry) => _FacetOption(
            label: labels[entry.key] ?? entry.key,
            count: entry.value,
            imageUrl: images[entry.key],
            selected: entry.key == selectedValue,
            onTap: () =>
                onChanged(entry.key == selectedValue ? null : entry.key),
          ),
        )
        .toList();
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
          if (showPicker) ...[
            PopupMenuButton<String>(
              enabled: counts.isNotEmpty || selectedValue?.isNotEmpty == true,
              tooltip: 'Select $placeholder',
              color: const Color(0xFF111936),
              onSelected: (value) => onChanged(value.isEmpty ? null : value),
              itemBuilder: (context) => [
                if (selectedValue?.isNotEmpty == true)
                  PopupMenuItem<String>(
                    value: '',
                    child: Text(
                      'Clear $placeholder',
                      style: const TextStyle(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                for (final entry in counts.entries)
                  PopupMenuItem<String>(
                    value: entry.key,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            labels[entry.key] ?? entry.key,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFE5E7EB)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '(${entry.value})',
                          style: const TextStyle(color: Color(0xFF93A4C8)),
                        ),
                      ],
                    ),
                  ),
              ],
              child: Container(
                height: 42,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF111936),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.10)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectedValue?.isNotEmpty == true
                            ? labels[selectedValue!] ?? selectedValue!
                            : placeholder,
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
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF93A4C8),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (entries.isEmpty)
            Text(
              'No $placeholder options for these results.',
              style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
            )
          else if (optionsMaxHeight == null)
            ...options
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: optionsMaxHeight!),
              child: SingleChildScrollView(
                primary: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: options,
                ),
              ),
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
    this.imageUrl,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final String? imageUrl;

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
            if (imageUrl?.isNotEmpty == true) ...[
              _FacetOptionImage(imageUrl: imageUrl!),
              const SizedBox(width: 10),
            ],
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

class _FacetOptionImage extends StatelessWidget {
  const _FacetOptionImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.collections_bookmark_outlined,
          color: Color(0xFF93A4C8),
          size: 16,
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
  final String heroScope;
  final String emptyTitle;
  final String emptyBody;
  final bool animateTiles;

  const _MarketplaceGrid({
    required this.cards,
    this.heroScope = 'market-grid',
    this.emptyTitle = 'No cards match these filters',
    this.emptyBody =
        'Try clearing filters or searching for a broader set, rarity or Pokémon name.',
    this.animateTiles = false,
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
                : 2;
        final isCompactTwoColumn = columns == 2 && width <= 560;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: isCompactTwoColumn ? 12 : 16,
            mainAxisSpacing: isCompactTwoColumn ? 12 : 16,
            mainAxisExtent: isCompactTwoColumn ? 292 : null,
            childAspectRatio: columns == 1
                ? 0.86
                : isCompactTwoColumn
                    ? 0.52
                    : 0.68,
          ),
          itemBuilder: (context, index) {
            final card = cards[index];
            final heroTag = _cardHeroTag(card, '$heroScope-$index');
            final tile = animateTiles
                ? _SpotlightMarketCard(card: card, heroTag: heroTag)
                : _MarketCard(card: card, heroTag: heroTag);
            if (!animateTiles) {
              return tile;
            }
            return _SpotlightAnimatedTile(index: index, child: tile);
          },
        );
      },
    );
  }
}

class _SpotlightDeferredPlaceholder extends StatelessWidget {
  const _SpotlightDeferredPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF0B1024),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
    );
  }
}

class _MarketplaceSkeletonShell extends StatelessWidget {
  const _MarketplaceSkeletonShell();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return _MarketplaceSkeletonPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardCarouselSection(
            title: 'Recently seen',
            cards: [],
            isSkeleton: true,
          ),
          const SizedBox(height: 24),
          const _CardCarouselSection(
            title: 'Best sellers',
            cards: [],
            isSkeleton: true,
          ),
          const SizedBox(height: 24),
          const _CardCarouselSection(
            title: 'Featured',
            cards: [],
            isSkeleton: true,
          ),
          if (!compact) ...[
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1220),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SuggestedCategoriesSkeleton(),
                      SizedBox(height: 28),
                      _SectionHeading(title: 'Card spotlight'),
                      SizedBox(height: 16),
                      _MarketplaceSkeletonGrid(),
                      SizedBox(height: 18),
                      SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MarketplaceSkeletonPulse extends StatefulWidget {
  const _MarketplaceSkeletonPulse({required this.child});

  final Widget child;

  @override
  State<_MarketplaceSkeletonPulse> createState() =>
      _MarketplaceSkeletonPulseState();
}

class _MarketplaceSkeletonPulseState extends State<_MarketplaceSkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MarketplaceSkeletonPulseScope(
      animation: _controller,
      child: widget.child,
    );
  }
}

class _MarketplaceSkeletonPulseScope extends InheritedWidget {
  const _MarketplaceSkeletonPulseScope({
    required this.animation,
    required super.child,
  });

  final Animation<double> animation;

  static Animation<double>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_MarketplaceSkeletonPulseScope>()
        ?.animation;
  }

  @override
  bool updateShouldNotify(_MarketplaceSkeletonPulseScope oldWidget) {
    return animation != oldWidget.animation;
  }
}

class _SuggestedCategoriesSkeleton extends StatelessWidget {
  const _SuggestedCategoriesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(title: 'Suggested categories'),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 14.0;
            final availableWidth = constraints.maxWidth;
            final cardWidth = ((availableWidth - spacing * 3) / 4)
                .clamp(260.0, 360.0)
                .toDouble();
            final row = Row(
              children: [
                for (var index = 0; index < 4; index++) ...[
                  SizedBox(
                    width: cardWidth,
                    child: const _SkeletonCategoryCard(),
                  ),
                  if (index != 3) const SizedBox(width: spacing),
                ],
              ],
            );
            if (availableWidth >= cardWidth * 4 + spacing * 3) {
              return row;
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: row,
            );
          },
        ),
      ],
    );
  }
}

class _SkeletonCategoryCard extends StatelessWidget {
  const _SkeletonCategoryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Row(
        children: [
          _SkeletonBlock(width: 72, height: 72, radius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBlock(width: 142, height: 18, radius: 999),
                SizedBox(height: 8),
                _SkeletonBlock(width: double.infinity, height: 12, radius: 999),
                SizedBox(height: 6),
                _SkeletonBlock(width: 156, height: 12, radius: 999),
                SizedBox(height: 10),
                _SkeletonBlock(width: 92, height: 12, radius: 999),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketplaceSkeletonFeatureCard extends StatelessWidget {
  const _MarketplaceSkeletonFeatureCard();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 560;
    final imageWidth = compact ? 104.0 : 126.0;
    final imageHeight = compact ? 144.0 : 170.0;
    final contentGap = compact ? 12.0 : 16.0;
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1024),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          _SkeletonBlock(width: imageWidth, height: imageHeight, radius: 16),
          SizedBox(width: contentGap),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBlock(width: double.infinity, height: 22, radius: 999),
                SizedBox(height: 10),
                _SkeletonBlock(width: 180, height: 16, radius: 999),
                SizedBox(height: 14),
                _SkeletonBlock(width: 112, height: 16, radius: 999),
                SizedBox(height: 12),
                _SkeletonBlock(width: 126, height: 18, radius: 999),
                Spacer(),
                _SkeletonBlock(width: double.infinity, height: 42, radius: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketplaceSkeletonGrid extends StatelessWidget {
  const _MarketplaceSkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width > 1120
            ? 4
            : width > 830
                ? 3
                : 2;
        final isCompactTwoColumn = columns == 2 && width <= 560;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: columns * 2,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: isCompactTwoColumn ? 12 : 16,
            mainAxisSpacing: isCompactTwoColumn ? 12 : 16,
            mainAxisExtent: isCompactTwoColumn ? 292 : null,
            childAspectRatio: columns == 1
                ? 0.86
                : isCompactTwoColumn
                    ? 0.52
                    : 0.68,
          ),
          itemBuilder: (_, __) => const _MarketplaceSkeletonCard(),
        );
      },
    );
  }
}

class _MarketplaceSkeletonCard extends StatelessWidget {
  const _MarketplaceSkeletonCard();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 560;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1024),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBlock(
            width: double.infinity,
            height: compact ? 116 : 180,
            radius: 0,
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 9 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SkeletonBlock(
                    width: double.infinity, height: 18, radius: 999),
                const SizedBox(height: 8),
                const _SkeletonBlock(width: 132, height: 14, radius: 999),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    _SkeletonPill(width: 62),
                    SizedBox(width: 8),
                    _SkeletonPill(width: 96),
                  ],
                ),
                if (!compact) ...[
                  const SizedBox(height: 18),
                  const _SkeletonBlock(width: 112, height: 24, radius: 999),
                  const SizedBox(height: 18),
                  const _SkeletonBlock(
                      width: double.infinity, height: 42, radius: 14),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonPill extends StatelessWidget {
  const _SkeletonPill({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return _SkeletonBlock(width: width, height: 34, radius: 999);
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final animation = _MarketplaceSkeletonPulseScope.maybeOf(context);
    final block = _SkeletonBlockSurface(
      width: width,
      height: height,
      radius: radius,
      progress: animation?.value ?? 0.5,
    );
    if (animation == null) {
      return block;
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => _SkeletonBlockSurface(
        width: width,
        height: height,
        radius: radius,
        progress: animation.value,
      ),
    );
  }
}

class _SkeletonBlockSurface extends StatelessWidget {
  const _SkeletonBlockSurface({
    required this.width,
    required this.height,
    required this.radius,
    required this.progress,
  });

  final double width;
  final double height;
  final double radius;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final shimmerAlpha = ui.lerpDouble(0.07, 0.13, progress)!;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: shimmerAlpha),
            Colors.white.withValues(alpha: 0.04),
          ],
        ),
      ),
    );
  }
}

class _SpotlightAnimatedTile extends StatefulWidget {
  const _SpotlightAnimatedTile({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  State<_SpotlightAnimatedTile> createState() => _SpotlightAnimatedTileState();
}

class _SpotlightAnimatedTileState extends State<_SpotlightAnimatedTile> {
  Timer? _showTimer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _showTimer = Timer(
        Duration(
          milliseconds: 35 * (widget.index % _HomeScreenState._pageSize),
        ), () {
      if (mounted) {
        setState(() => _visible = true);
      }
    });
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, 0.06),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _SpotlightMarketCard extends ConsumerWidget {
  const _SpotlightMarketCard({
    required this.card,
    required this.heroTag,
  });

  final PokemonCard card;
  final String heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final isFavorite = favorites.isFavorite(card.id);
    final paletteHint = cardPaletteHint(
      type: card.type,
      name: card.name,
      tags: card.tags,
    );
    final surfaceGradient = cardDarkSurfaceGradientForPayload(
      card.cardPalette,
      fallbackType: paletteHint,
    );
    final compact = MediaQuery.sizeOf(context).width <= 560;
    const priceFontSize = 22.0;

    final tile = Container(
      decoration: BoxDecoration(
        gradient: surfaceGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          ref.read(cardProvider.notifier).recordCardInteraction(
                card,
                'click',
                source: 'market_grid',
              );
          ref.read(cardProvider.notifier).clearFilters();
          _goToCardDetail(ref, context, card, heroTag: heroTag);
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: _CardImageFrame(
                imageUrl: card.imageUrl,
                cardType: paletteHint,
                cardPalette: card.cardPalette,
                fallbackImageUrl: card.previewImageUrl,
                borderRadius: BorderRadius.circular(24),
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                fallbackSize: 64,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.08),
                      const Color(0xFF0B1024).withValues(alpha: 0.28),
                      const Color(0xFF0B1024).withValues(alpha: 0.82),
                      const Color(0xFF050816).withValues(alpha: 0.96),
                    ],
                    stops: const [0.0, 0.36, 0.62, 1.0],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.bottomCenter,
                    radius: 0.95,
                    colors: [
                      surfaceGradient.colors.last.withValues(alpha: 0.48),
                      const Color(0xFF050816).withValues(alpha: 0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
            if (card.rarity.isNotEmpty && card.rarity != 'Card')
              Positioned(
                right: 12,
                top: 126,
                child: _Badge(
                  text: card.rarity,
                  color: const Color(0xFFFACC15),
                ),
              ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton.filledTonal(
                onPressed: () {
                  ref.read(cardProvider.notifier).cacheCards([card]);
                  ref.read(favoritesProvider.notifier).toggleFavorite(card.id);
                },
                icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _cardTitleWithNumber(card),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(color: Colors.black87, blurRadius: 10),
                      ],
                    ),
                    textScaler: TextScaler.noScaling,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    card.set,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 14,
                      shadows: [
                        Shadow(color: Colors.black87, blurRadius: 8),
                      ],
                    ),
                  ),
                  if (card.emoji.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      card.emoji,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, height: 1),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MiniSignal(
                        icon: Icons.star,
                        text: card.starMetricCount.toString(),
                      ),
                      _MiniSignal(
                        icon: Icons.shopping_cart_outlined,
                        text: card.cartMetricCount.toString(),
                      ),
                      if (card.isMarketAvailable)
                        _MiniSignal(
                          icon: Icons.inventory_2_outlined,
                          text: _marketStockLabel(card),
                        ),
                    ],
                  ),
                  if (card.isMarketAvailable) ...[
                    const SizedBox(height: 14),
                    Text(
                      _marketPriceLabel(card),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFACC15),
                        fontSize: priceFontSize,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(color: Colors.black87, blurRadius: 8),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const _MiniPriceDiagram(height: 42),
                ],
              ),
            ),
            if (!card.isMarketAvailable)
              Positioned(
                left: 16,
                right: 16,
                top: compact ? 128 : 156,
                bottom: 16,
                child: _OutOfStockOverlay(compact: compact),
              ),
          ],
        ),
      ),
    );

    return _HeroCardTile(heroTag: heroTag, child: tile);
  }
}

class _MarketCard extends ConsumerWidget {
  final PokemonCard card;
  final String heroTag;

  const _MarketCard({required this.card, required this.heroTag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final isFavorite = favorites.isFavorite(card.id);
    final paletteHint = cardPaletteHint(
      type: card.type,
      name: card.name,
      tags: card.tags,
    );
    final surfaceGradient = cardDarkSurfaceGradientForPayload(
      card.cardPalette,
      fallbackType: paletteHint,
    );
    final compact = MediaQuery.sizeOf(context).width <= 560;
    final imageHeight = compact ? 116.0 : 180.0;
    final contentPadding = compact ? 9.0 : 16.0;
    final titleFontSize = compact ? 13.0 : 18.0;
    final setFontSize = compact ? 11.0 : 14.0;
    final priceFontSize = compact ? 13.0 : 22.0;
    final signalSpacing = compact ? 5.0 : 8.0;
    final signalRunSpacing = compact ? 5.0 : 8.0;

    final tile = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: compact ? 0 : 360,
        maxHeight: compact ? 292 : 430,
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: surfaceGradient,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            ref.read(cardProvider.notifier).recordCardInteraction(
                  card,
                  'click',
                  source: 'market_grid',
                );
            ref.read(cardProvider.notifier).clearFilters();
            _goToCardDetail(ref, context, card, heroTag: heroTag);
          },
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: imageHeight,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _CardImageFrame(
                            imageUrl: card.imageUrl,
                            cardType: paletteHint,
                            cardPalette: card.cardPalette,
                            fallbackImageUrl: card.previewImageUrl,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(24)),
                            padding: EdgeInsets.all(compact ? 9 : 14),
                            fallbackSize: compact ? 42 : 54,
                          ),
                        ),
                        if (card.rarity.isNotEmpty && card.rarity != 'Card')
                          Positioned(
                              right: 12,
                              bottom: 12,
                              child: _Badge(
                                  text: card.rarity,
                                  color: const Color(0xFFFACC15))),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: IconButton.filledTonal(
                            onPressed: () {
                              ref
                                  .read(cardProvider.notifier)
                                  .cacheCards([card]);
                              ref
                                  .read(favoritesProvider.notifier)
                                  .toggleFavorite(card.id);
                            },
                            icon: Icon(isFavorite
                                ? Icons.favorite
                                : Icons.favorite_border),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(contentPadding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _cardTitleWithNumber(card),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.w900),
                          textScaler: TextScaler.noScaling,
                        ),
                        SizedBox(height: compact ? 4 : 6),
                        Text(
                          card.set,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xFF93A4C8),
                            fontSize: setFontSize,
                          ),
                        ),
                        if (card.emoji.trim().isNotEmpty) ...[
                          SizedBox(height: compact ? 5 : 8),
                          Text(
                            card.emoji,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: compact ? 14 : 18, height: 1),
                          ),
                        ],
                        SizedBox(height: compact ? 7 : 10),
                        Wrap(
                          spacing: signalSpacing,
                          runSpacing: signalRunSpacing,
                          children: [
                            _MiniSignal(
                                icon: Icons.star,
                                text: card.starMetricCount.toString()),
                            _MiniSignal(
                                icon: Icons.shopping_cart_outlined,
                                text: card.cartMetricCount.toString()),
                            if (card.isMarketAvailable)
                              _MiniSignal(
                                icon: Icons.inventory_2_outlined,
                                text: _marketStockLabel(card),
                              ),
                          ],
                        ),
                        if (card.isMarketAvailable) ...[
                          SizedBox(height: compact ? 8 : 14),
                          Text(
                            _marketPriceLabel(card),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFFFACC15),
                              fontSize: priceFontSize,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                        if (!compact) ...[
                          const SizedBox(height: 16),
                          const _MiniPriceDiagram(height: 42),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (!card.isMarketAvailable)
                Positioned(
                  left: contentPadding,
                  right: contentPadding,
                  top: imageHeight + contentPadding,
                  bottom: contentPadding,
                  child: _OutOfStockOverlay(compact: compact),
                ),
            ],
          ),
        ),
      ),
    );
    return _HeroCardTile(heroTag: heroTag, child: tile);
  }
}

class _FeaturedCard extends ConsumerWidget {
  final PokemonCard card;
  final String heroTag;

  const _FeaturedCard({required this.card, required this.heroTag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = MediaQuery.sizeOf(context).width < 560;
    final paletteHint = cardPaletteHint(
      type: card.type,
      name: card.name,
      tags: card.tags,
    );
    final surfaceGradient = cardDarkSurfaceGradientForPayload(
      card.cardPalette,
      fallbackType: paletteHint,
    );

    final imageWidth = compact ? 104.0 : 126.0;
    final imageHeight = compact ? 144.0 : 170.0;
    final contentGap = compact ? 12.0 : 16.0;

    final tile = Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        gradient: surfaceGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          ref.read(cardProvider.notifier).recordCardInteraction(
                card,
                'click',
                source: 'market_carousel',
              );
          ref.read(cardProvider.notifier).clearFilters();
          _goToCardDetail(ref, context, card, heroTag: heroTag);
        },
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Row(
              children: [
                _CardImageFrame(
                  imageUrl: compact
                      ? card.previewImageUrl
                      : _homepageCardImageUrl(card),
                  cardType: paletteHint,
                  cardPalette: card.cardPalette,
                  fallbackImageUrl: card.previewImageUrl.isNotEmpty
                      ? card.previewImageUrl
                      : card.imageUrl,
                  width: imageWidth,
                  height: imageHeight,
                  borderRadius: BorderRadius.circular(16),
                  padding: const EdgeInsets.all(6),
                ),
                SizedBox(width: contentGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      if (card.emoji.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          card.emoji,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18, height: 1),
                        ),
                      ],
                      if (card.isMarketAvailable) ...[
                        const SizedBox(height: 10),
                        Text(
                          _marketPriceLabel(card),
                          style: const TextStyle(
                            color: Color(0xFFFACC15),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                      const Spacer(),
                      const _MiniPriceDiagram(),
                    ],
                  ),
                ),
              ],
            ),
            if (!card.isMarketAvailable)
              Positioned(
                left: imageWidth + contentGap,
                right: 0,
                top: 0,
                bottom: 0,
                child: _OutOfStockOverlay(compact: compact),
              ),
          ],
        ),
      ),
    );
    return _HeroCardTile(heroTag: heroTag, child: tile);
  }
}

class _OutOfStockOverlay extends StatelessWidget {
  const _OutOfStockOverlay({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            if (width <= 0 || height <= 0) {
              return const SizedBox.shrink();
            }

            final diagonalWidth = math.sqrt(width * width + height * height);
            final ribbonHeight = (height * (compact ? 0.34 : 0.3))
                .clamp(compact ? 34.0 : 42.0, compact ? 56.0 : 74.0)
                .toDouble();

            return Center(
              child: Transform.rotate(
                angle: -math.pi / 8,
                child: Container(
                  width: diagonalWidth * 1.08,
                  height: ribbonHeight,
                  padding: EdgeInsets.symmetric(
                    horizontal: ribbonHeight * 0.28,
                    vertical: ribbonHeight * 0.1,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1024).withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(ribbonHeight / 2),
                    border: Border.all(
                      color: const Color(0xFFFACC15).withValues(alpha: 0.7),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Text(
                      'Out of stock',
                      maxLines: 1,
                      style: TextStyle(
                        color: const Color(0xFFFACC15),
                        fontSize: compact ? 28 : 36,
                        fontWeight: FontWeight.w900,
                        letterSpacing: compact ? 0.3 : 0.8,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeroCardTile extends StatefulWidget {
  const _HeroCardTile({
    required this.heroTag,
    required this.child,
  });

  final String? heroTag;
  final Widget child;

  @override
  State<_HeroCardTile> createState() => _HeroCardTileState();
}

class _HeroCardTileState extends State<_HeroCardTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final sigma = _hovered ? 1.3 : 0.0;
    final tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.012 : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.14),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
    final tag = widget.heroTag;
    if (tag == null || tag.isEmpty) {
      return tile;
    }
    return Hero(
      tag: tag,
      flightShuttleBuilder: (
        _,
        animation,
        __,
        ___,
        toHeroContext,
      ) {
        return ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: Material(
            color: Colors.transparent,
            child: toHeroContext.widget,
          ),
        );
      },
      child: tile,
    );
  }
}

class _MiniPriceDiagram extends StatelessWidget {
  final double height;

  const _MiniPriceDiagram({this.height = 42});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _MiniPriceDiagramPainter(),
      ),
    );
  }
}

class _MiniPriceDiagramPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = const Color(0xFFFACC15).withValues(alpha: 0.28)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final baseline = size.height - 8;
    for (var index = 0; index < 3; index++) {
      final y = 8 + (index * ((size.height - 16) / 2));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    canvas.drawLine(
        Offset(0, baseline), Offset(size.width, baseline), axisPaint);
    canvas.drawLine(const Offset(0, 6), Offset(0, baseline), axisPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _marketPriceLabel(PokemonCard card) {
  return card.isMarketAvailable ? formatPkn(card.price) : 'Out of stock';
}

String _marketStockLabel(PokemonCard card) {
  return card.stock > 0 ? '${card.stock} in stock' : 'CardTrader available';
}

String _cardTitleWithNumber(PokemonCard card) {
  if (card.itemKind == 'product') {
    final variant = card.number.trim();
    if (variant.isEmpty) {
      return card.name;
    }
    return '${card.name} · $variant';
  }
  final number = _displayCollectorNumber(card.number);
  if (number.isEmpty || _isNameLikeCollectorNumber(card.name, number)) {
    return card.name;
  }
  return '${card.name} $number';
}

bool _isNameLikeCollectorNumber(String name, String number) {
  final compactName = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final compactNumber =
      number.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return compactName.length >= 3 &&
      compactNumber.length >= compactName.length &&
      compactNumber.startsWith(compactName);
}

String _cardHeroTag(PokemonCard card, String scope) {
  return 'market-card-image-${card.id}-$scope';
}

void _goToCardDetail(
  WidgetRef ref,
  BuildContext context,
  PokemonCard card, {
  String? heroTag,
}) {
  ref.read(cardProvider.notifier).beginNavigationTransition();
  unawaited(navigateToCanonicalCardDetail(
    context,
    card,
    extra: heroTag,
    source: 'marketplace_home',
  ));
}

String _homepageCardImageUrl(PokemonCard card) {
  final homepage = card.homepageImageUrl.trim();
  if (homepage.isNotEmpty) {
    return homepage;
  }
  final preview = card.previewImageUrl.trim();
  if (preview.isNotEmpty) {
    return preview;
  }
  return card.imageUrl;
}

String _recentlySeenHeroTag(PokemonCard card, int index) {
  return _cardHeroTag(card, 'carousel-Recently seen-$index');
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
    this.cardType = '',
    this.fallbackImageUrl,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(6),
    this.fallbackSize = 24,
    this.cardPalette = const {},
  });

  final String imageUrl;
  final String cardType;
  final String? fallbackImageUrl;
  final BorderRadius borderRadius;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final double fallbackSize;
  final Map<String, dynamic> cardPalette;

  @override
  Widget build(BuildContext context) {
    final primaryUrl = imageUrl.trim();
    final fallback = fallbackImageUrl?.trim();
    final placeholder = Icon(
      Icons.style,
      color: const Color(0xFFFACC15),
      size: fallbackSize,
    );
    final image = primaryUrl.isEmpty
        ? placeholder
        : CachedNetworkImage(
            imageUrl: primaryUrl,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            errorWidget: (_, __, ___) {
              if (fallback != null &&
                  fallback.isNotEmpty &&
                  fallback != primaryUrl) {
                return CachedNetworkImage(
                  imageUrl: fallback,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  errorWidget: (_, __, ___) => placeholder,
                );
              }
              return placeholder;
            },
          );

    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: cardImageFrameColorForPayload(
          cardPalette,
          fallbackType: cardType,
        ),
        borderRadius: borderRadius,
      ),
      clipBehavior: Clip.none,
      child: image,
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

  final ranked = [
    for (var index = 0; index < cards.length; index++)
      (card: cards[index], sourceIndex: index),
  ]..sort((a, b) {
      final score = _recentViewScore(
        b.card,
        recentIds,
        recentNames,
        recentExpansions,
      ).compareTo(
        _recentViewScore(a.card, recentIds, recentNames, recentExpansions),
      );
      if (score != 0) {
        return score;
      }
      return a.sourceIndex.compareTo(b.sourceIndex);
    });
  return ranked.map((entry) => entry.card).toList(growable: false);
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

bool _isSingleCard(PokemonCard card) {
  return card.itemKind != 'product' && card.productType == 'card';
}

List<PokemonCard> _cardsWithActiveListings(
  List<PokemonCard> cards,
  List<CardListing> listings,
) {
  if (cards.isEmpty || listings.isEmpty) {
    return cards;
  }

  final stockByCardId = <String, int>{};
  final lowestPriceByCardId = <String, double>{};
  for (final listing in listings) {
    final cardId = listing.cardId.trim();
    if (cardId.isEmpty || listing.quantityAvailable <= 0) {
      continue;
    }
    stockByCardId[cardId] =
        (stockByCardId[cardId] ?? 0) + listing.quantityAvailable;
    final currentLowest = lowestPriceByCardId[cardId];
    if (currentLowest == null || listing.pricePkn < currentLowest) {
      lowestPriceByCardId[cardId] = listing.pricePkn;
    }
  }

  if (stockByCardId.isEmpty) {
    return cards;
  }

  return cards.map((card) {
    final listingStock = stockByCardId[card.id];
    if (listingStock == null || listingStock <= 0) {
      return card;
    }
    final listingPrice = lowestPriceByCardId[card.id];
    final price = listingPrice == null
        ? card.price
        : (card.stock > 0 && card.price > 0
            ? math.min(card.price, listingPrice)
            : listingPrice);
    return card.copyWith(
      stock: card.stock > listingStock ? card.stock : listingStock,
      price: price,
    );
  }).toList(growable: false);
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
    Map<String, MarketplaceCheapestPrice> cheapestPricesByCardId = const {},
  }) {
    final singles =
        cards.where((card) => _isSingleCard(card) && card.isMarketAvailable).toList();
    final personalized = _rankCardsByRecentViews(singles, recentViews);
    final recentCards = _cardsForRecentViews(
      recentViews,
      singles,
      cheapestPricesByCardId,
    );
    if (cachedSections != null) {
      final byId = {for (final card in singles) card.id: card};
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
    return ids
        .map((id) => byId[id])
        .whereType<PokemonCard>()
        .where((card) => card.isMarketAvailable)
        .take(9)
        .toList();
  }

  static List<String> _recentViewCheapestLookupIds(RecentCardView view) {
    if (view.itemKind == 'product' || view.productType != 'card') {
      return const [];
    }
    return _recentViewCheapestLookupKeys(view);
  }

  static List<PokemonCard> _cardsForRecentViews(
    List<RecentCardView> views,
    List<PokemonCard> cards,
    Map<String, MarketplaceCheapestPrice> cheapestPricesByCardId,
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
        .map((view) {
          final cheapestPrice = _cheapestPriceForRecentView(
                view,
                cheapestPricesByCardId,
              ) ??
              _cheapestPriceFromRecentView(view);
          final card = byId[view.cardId] ??
              cardsByNameAndSet[
                  '${_normalizePersonalizationKey(view.name)}|${_normalizePersonalizationKey(view.expansion)}'];
          if (card != null) {
            final hydrated = _applyCheapestPriceToRecentCard(
              card,
              cheapestPrice,
            );
            return hydrated.isMarketAvailable ? hydrated : null;
          }
          if (!_cheapestPriceIsAvailable(cheapestPrice)) {
            return null;
          }
          return _cardFromRecentView(view, cheapestPrice);
        })
        .whereType<PokemonCard>()
        .take(9)
        .toList();
  }

  static MarketplaceCheapestPrice? _cheapestPriceForRecentView(
    RecentCardView view,
    Map<String, MarketplaceCheapestPrice> cheapestPricesByCardId,
  ) {
    MarketplaceCheapestPrice? fallback;
    for (final id in _recentViewCheapestLookupIds(view)) {
      final price = cheapestPricesByCardId[id];
      if (_cheapestPriceIsAvailable(price)) {
        return price;
      }
      fallback ??= price;
    }
    return fallback;
  }

  static MarketplaceCheapestPrice? _cheapestPriceFromRecentView(
    RecentCardView view,
  ) {
    final pricePkn = view.pricePkn;
    if (view.productType != 'card' ||
        view.itemKind == 'product' ||
        view.available != true ||
        pricePkn == null ||
        pricePkn <= 0) {
      return null;
    }
    return MarketplaceCheapestPrice(
      cardId: view.cardId,
      pricePkn: pricePkn,
      available: true,
      listingCount: view.listingCount,
      listedQuantity: view.listedQuantity,
      publicNumber: view.publicNumber,
      canonicalPath: view.canonicalPath,
      source: view.priceSource,
      name: view.name,
      setName: view.expansion,
      number: view.number,
    );
  }

  static PokemonCard _applyCheapestPriceToRecentCard(
    PokemonCard card,
    MarketplaceCheapestPrice? cheapestPrice,
  ) {
    final pricePkn = cheapestPrice?.pricePkn;
    if (cheapestPrice?.available != true || pricePkn == null) {
      return card;
    }
    return card.copyWith(
      price: pricePkn,
      stock: math.max(card.stock, cheapestPrice?.listedQuantity ?? 0),
      hasCardTraderListing: true,
      cardtraderEligibleListingCount: math.max(
        card.cardtraderEligibleListingCount,
        cheapestPrice?.listingCount ?? 0,
      ),
      canonicalPath: card.canonicalPath.trim().isNotEmpty
          ? card.canonicalPath
          : cheapestPrice?.canonicalPath,
    );
  }

  static PokemonCard _cardFromRecentView(
    RecentCardView view, [
    MarketplaceCheapestPrice? cheapestPrice,
  ]) {
    final isProduct = view.itemKind == 'product' || view.productType != 'card';
    final type = isProduct ? _productTypeLabel(view.productType) : 'Card';
    final cachedCheapestPrice =
        cheapestPrice ?? _cheapestPriceFromRecentView(view);
    final isAvailable = !isProduct &&
        cachedCheapestPrice?.available == true &&
        cachedCheapestPrice?.pricePkn != null;
    return PokemonCard(
      id: isAvailable && cachedCheapestPrice!.cardId.trim().isNotEmpty
          ? cachedCheapestPrice.cardId
          : view.cardId,
      name: view.name,
      imageUrl: view.imageUrl,
      previewImageUrl: view.previewImageUrl,
      homepageImageUrl: view.homepageImageUrl,
      rarity: isProduct ? type : 'Card',
      type: type,
      hp: 0,
      attacks: const [],
      price: cachedCheapestPrice?.pricePkn ??
          (1000 + (_recentViewSeed(view.cardId) % 120000)).toDouble(),
      description: 'Saved from your recent marketplace views.',
      set: view.expansion,
      number: view.number,
      artist: '',
      stock: cachedCheapestPrice?.listedQuantity ?? 0,
      rating: 0,
      reviewCount: 0,
      isFoil: false,
      isHolo: false,
      releaseDate: view.viewedAt,
      tags: [view.expansion, type, view.itemKind, view.productType],
      condition: 'NM',
      isGraded: false,
      itemKind: isProduct ? 'product' : 'single',
      productType: isProduct ? view.productType : 'card',
      hasCardTraderListing: isAvailable,
      cardtraderEligibleListingCount: cachedCheapestPrice?.listingCount ?? 0,
      canonicalPath: cachedCheapestPrice?.canonicalPath ?? view.canonicalPath,
      cardPalette: view.cardPalette,
      emoji: view.emoji,
    );
  }

  static String _productTypeLabel(String productType) {
    switch (productType) {
      case 'booster_pack':
        return 'Booster pack';
      case 'booster_box':
        return 'Booster box';
      case 'booster_bundle':
        return 'Booster bundle';
      case 'elite_trainer_box':
        return 'Elite Trainer Box';
      case 'tin':
        return 'Tin';
      case 'collection_box':
        return 'Collection box';
      case 'deck':
        return 'Deck';
      case 'championship_deck':
        return 'Championship deck';
      case 'accessory':
        return 'Accessory';
      case 'sealed_product':
        return 'Sealed product';
      default:
        return 'Card';
    }
  }

  static int _recentViewSeed(String value) {
    return value.codeUnits.fold<int>(0, (sum, unit) => sum + unit * 31);
  }
}

List<String> _recentViewCheapestLookupKeys(RecentCardView view) {
  if (view.itemKind == 'product' || view.productType != 'card') {
    return const [];
  }
  final ids = <String>[];
  void addAll(Iterable<String> values) {
    for (final value in values) {
      final id = value.trim();
      if (id.isNotEmpty && !ids.contains(id)) {
        ids.add(id);
      }
    }
  }

  addAll(_marketplaceCheapestLookupIds(view.cardId));
  addAll(_marketplaceCheapestLookupIds(view.publicNumber));
  addAll(_marketplaceCheapestLookupIds(
    _publicNumberFromMarketplacePath(view.canonicalPath),
  ));
  final canonical = view.canonicalPath.trim();
  if (canonical.startsWith('/marketplace/') &&
      canonical.contains('/cards/') &&
      !ids.contains(canonical)) {
    ids.add(canonical);
  }
  addAll(_recentViewStructuredLookupKeys(view));
  return ids;
}

List<String> _marketplaceCheapestLookupIds(String rawId) {
  final ids = <String>[];
  void add(String value) {
    final id = value.trim();
    if (id.isNotEmpty &&
        RegExp(r'^[0-9]+$').hasMatch(id) &&
        !ids.contains(id)) {
      ids.add(id);
    }
  }

  add(rawId);
  add(cardIdFromDoubledId(rawId));
  return ids;
}

Map<String, MarketplaceCheapestPrice> _indexRecentCheapestPrices(
  Map<String, MarketplaceCheapestPrice> prices,
) {
  final indexed = <String, MarketplaceCheapestPrice>{};
  void add(String id, MarketplaceCheapestPrice price) {
    final clean = id.trim();
    if (clean.isNotEmpty) {
      final existing = indexed[clean];
      if (existing == null ||
          (!_cheapestPriceIsAvailable(existing) &&
              _cheapestPriceIsAvailable(price))) {
        indexed[clean] = price;
      }
    }
  }

  for (final price in prices.values) {
    add(price.cardId, price);
    add(price.publicNumber, price);
    add(cardIdFromDoubledId(price.publicNumber), price);
    final canonicalPublicNumber = _publicNumberFromMarketplacePath(
      price.canonicalPath,
    );
    add(canonicalPublicNumber, price);
    add(cardIdFromDoubledId(canonicalPublicNumber), price);
    add(price.canonicalPath, price);
    _addAllStructuredPriceKeys(price, add);
  }
  return indexed;
}

Map<String, MarketplaceCheapestPrice> _recentCheapestPricesForViews(
  List<RecentCardView> views,
) {
  final prices = <String, MarketplaceCheapestPrice>{};
  for (final view in views) {
    final price = _MarketplaceSections._cheapestPriceFromRecentView(view);
    if (price != null) {
      prices[price.cardId] = price;
    }
  }
  return _indexRecentCheapestPrices(prices);
}

Map<String, MarketplaceCheapestPrice> _mergeRecentCheapestPrices(
  Map<String, MarketplaceCheapestPrice> current,
  Map<String, MarketplaceCheapestPrice> incoming,
) {
  if (current.isEmpty) {
    return incoming;
  }
  if (incoming.isEmpty) {
    return current;
  }
  return {
    ...current,
    ...incoming,
  };
}

void _addAllStructuredPriceKeys(
  MarketplaceCheapestPrice price,
  void Function(String id, MarketplaceCheapestPrice price) add,
) {
  final name = _normalizeRecentStructuredKey(price.name);
  final setName = _normalizeRecentStructuredKey(price.setName);
  final number = _normalizeRecentStructuredKey(price.number);
  if (name.isNotEmpty && (setName.isNotEmpty || number.isNotEmpty)) {
    add('structured:$name|$setName|$number', price);
  }
}

bool _cheapestPriceIsAvailable(MarketplaceCheapestPrice? price) {
  return price?.available == true && price?.pricePkn != null;
}

List<RecentCardView> _hydrateRecentViewsWithCheapestPrices(
  List<RecentCardView> views,
  Map<String, MarketplaceCheapestPrice> cheapestPricesByCardId,
) {
  return views.map((view) {
    final price = _MarketplaceSections._cheapestPriceForRecentView(
      view,
      cheapestPricesByCardId,
    );
    if (!_cheapestPriceIsAvailable(price)) {
      return view;
    }
    final publicNumber = price!.publicNumber.trim().isNotEmpty
        ? price.publicNumber.trim()
        : _publicNumberFromMarketplacePath(price.canonicalPath);
    return view.copyWith(
      cardId: price.cardId.trim().isNotEmpty ? price.cardId : view.cardId,
      canonicalPath: price.canonicalPath.trim().isNotEmpty
          ? price.canonicalPath
          : view.canonicalPath,
      publicNumber: publicNumber.isNotEmpty ? publicNumber : view.publicNumber,
      pricePkn: price.pricePkn,
      available: true,
      listingCount: price.listingCount,
      listedQuantity: price.listedQuantity,
      priceSource: price.source.trim().isNotEmpty
          ? price.source
          : (view.priceSource.trim().isNotEmpty
              ? view.priceSource
              : 'cheapest'),
    );
  }).toList(growable: false);
}

bool _sameRecentViewCache(
  List<RecentCardView> a,
  List<RecentCardView> b,
) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index].cardId != b[index].cardId ||
        a[index].canonicalPath != b[index].canonicalPath ||
        a[index].publicNumber != b[index].publicNumber ||
        a[index].pricePkn != b[index].pricePkn ||
        a[index].available != b[index].available ||
        a[index].listingCount != b[index].listingCount ||
        a[index].listedQuantity != b[index].listedQuantity ||
        a[index].priceSource != b[index].priceSource) {
      return false;
    }
  }
  return true;
}

List<String> _recentViewStructuredLookupKeys(RecentCardView view) {
  final name = _normalizeRecentStructuredKey(view.name);
  final setName = _normalizeRecentStructuredKey(view.expansion);
  final number = view.number.trim();
  if (name.isEmpty || (setName.isEmpty && number.isEmpty)) {
    return const [];
  }
  return ['structured:$name|$setName|$number'];
}

String _normalizeRecentStructuredKey(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

String _publicNumberFromMarketplacePath(String canonicalPath) {
  final match = RegExp(r'/cards/([0-9]+)(?:/|$)').firstMatch(canonicalPath);
  return match?.group(1) ?? '';
}

class _SuggestedCategories extends StatelessWidget {
  const _SuggestedCategories();

  @override
  Widget build(BuildContext context) {
    const categories = [
      _CategoryCard(
        title: 'Booster boxes',
        path: '/product/box',
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
        path: '/product/pack',
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
        title: 'Graded',
        path: '/product/graded',
        query: '',
        productType: 'card',
        card: _CategoryCardData(
          id: '272855',
          name: 'Mario Pikachu',
          previewImageUrl:
              '/card-images/previews/272855_mario-pikachu-294-xy-p-xy-promos.webp',
          imageUrl: '/card-images/272855_mario-pikachu-294-xy-p-xy-promos.jpg',
          set: 'XY Promos',
          number: '294/XY-P',
          itemKind: 'single',
          productType: 'card',
        ),
      ),
      _CategoryCard(
        title: 'NFT mark',
        path: '/product/nft',
        query: 'illustration rare',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(
          title: 'Suggested categories',
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 14.0;
            final availableWidth = constraints.maxWidth;
            final cardWidth = ((availableWidth - spacing * 3) / 4)
                .clamp(260.0, 360.0)
                .toDouble();
            final row = Row(
              children: [
                for (var index = 0; index < categories.length; index++) ...[
                  SizedBox(
                    width: cardWidth,
                    child: categories[index],
                  ),
                  if (index != categories.length - 1)
                    const SizedBox(width: spacing),
                ],
              ],
            );
            if (availableWidth >= cardWidth * categories.length + spacing * 3) {
              return row;
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: row,
            );
          },
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
    required this.path,
    required this.query,
    required this.productType,
    required this.card,
  });

  final String title;
  final String path;
  final String query;
  final String productType;
  final _CategoryCardData card;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(path),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
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
              width: 72,
              height: 72,
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.all(5),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'You might like: ${card.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB8C4E6),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Find out more',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFFFACC15),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFFFACC15),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
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
