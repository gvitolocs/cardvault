import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/app_user_profile.dart';
import '../models/card_listing.dart';
import '../models/pokemon_card.dart';
import '../models/user_card_collection_item.dart';
import '../providers/auth_provider.dart';
import '../providers/card_listing_provider.dart';
import '../providers/card_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/recent_views_provider.dart';
import '../providers/user_card_collection_provider.dart';
import '../services/card_service.dart';
import '../services/flutter_debug_log.dart';
import '../services/pokoin_api_client.dart';
import '../utils/browser_location.dart';
import '../utils/card_navigation.dart';
import '../utils/card_palette.dart';
import '../utils/card_url.dart';
import '../utils/price_format.dart';
import '../widgets/artist_suggestion_field.dart';
import '../widgets/listing_metadata_chips.dart';
import 'home_screen.dart'
    show
        MarketplaceLogoButton,
        MarketplaceTopBar,
        MarketplaceTopBarSearch,
        MarketplaceHomeRouteIntent,
        SearchLanguageMenu,
        marketplaceTopBarColor,
        marketplaceTopBarHeight,
        marketplaceTopBarActions,
        showMarketplaceEmptyFocusSearchPreviews,
        showMarketplaceSideMenuWithNavigationIntent;

const List<String> _listingLanguageCodes = [
  'EN',
  'IT',
  'FR',
  'DE',
  'ES',
  'JP',
  'PT',
  'NL',
  'PL',
  'RU',
  'KO',
  'ZH',
  'ZHT',
  'ID',
  'TH',
  'VI',
];

const List<String> _foilStateOptions = [
  'standard',
  'holo',
  'reverse',
  'stamped',
  'promo',
  'other',
];

const List<String> _listingPriceCurrencies = ['PKN', 'EUR', 'DKK', 'USD'];
const double _dkkPerEur = 7.5;

final _detailListingOverridesProvider = StateProvider.autoDispose
    .family<Map<String, CardListing?>, String>((ref, cardId) => const {});

const int _vintedSearchQueryMaxLength = 14;

String vintedSearchQueryForCard(PokemonCard card) {
  final name = card.name.trim();
  if (name.length >= _vintedSearchQueryMaxLength) {
    return name;
  }

  final number = _leadingCollectorNumber(card.number);
  if (number.isEmpty) {
    return name;
  }

  final queryWithNumber = '$name $number';
  if (queryWithNumber.length <= _vintedSearchQueryMaxLength) {
    return queryWithNumber;
  }

  return name;
}

String _leadingCollectorNumber(String number) {
  final displayNumber = displayCollectorNumberForCard(number);
  return RegExp(r'[A-Za-z0-9]+').firstMatch(displayNumber)?.group(0) ?? '';
}

String displayCollectorNumberForCard(String rawNumber) {
  return _displayCollectorNumber(rawNumber);
}

String _listingLanguageLabel(String code) {
  return listingLanguageLabel(code);
}

Future<double> _listingPriceToPkn(
  WidgetRef ref, {
  required double amount,
  required String currency,
}) async {
  final normalized = currency.trim().toUpperCase();
  if (normalized == 'PKN') {
    return amount;
  }
  final eurAmount = normalized == 'DKK' ? amount / _dkkPerEur : amount;
  final quote = await ref.read(authServiceProvider).quoteCryptoPknPurchase(
        asset: normalized == 'USD' ? 'USDT' : 'EURC',
        amountIn: eurAmount,
      );
  final converted = (quote['amountOut'] as num?)?.toDouble();
  if (converted == null || converted <= 0) {
    throw StateError('Could not convert $normalized price to PKN.');
  }
  return converted;
}

class CardDetailScreen extends ConsumerStatefulWidget {
  final String cardId;
  final String? cardSlug;
  final String language;
  final String? heroTag;

  const CardDetailScreen({
    super.key,
    required this.cardId,
    this.cardSlug,
    this.language = 'en',
    this.heroTag,
  });

  @override
  ConsumerState<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends ConsumerState<CardDetailScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _pageScrollController = ScrollController();
  final CardService _cardService = CardService();
  bool _searchFocused = false;
  late String _currentCardId;
  late String? _currentCardSlug;
  PokemonCard? _currentCardOverride;
  String? _activeHeroTag;
  bool _detailViewRecorded = false;
  bool _isLoadingAdjacentCard = false;
  bool _isReturningToMarketplaceFromArtwork = false;
  Timer? _heroRetargetTimer;
  String? _marketplaceWarmCardId;
  String? _canonicalLookupKey;
  String? _lastResolvedDebugCardId;
  final Set<String> _canonicalTraceKeys = {};

  @override
  void initState() {
    super.initState();
    _currentCardId = widget.cardId;
    _currentCardSlug = widget.cardSlug;
    _activeHeroTag = widget.heroTag;
    CardDetailRouteGuard.instance.cardDetailMounted(
      route: (currentBrowserUri() ?? Uri.base).replace(fragment: '').toString(),
    );
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    FlutterDebugLog.instance.record(
      'card_detail.init',
      category: 'card_detail',
      payload: {
        'cardId': widget.cardId,
        'cardSlug': widget.cardSlug,
        'language': widget.language,
        'browserUrl': (currentBrowserUri() ?? Uri.base).toString(),
      },
    );
  }

  @override
  void didUpdateWidget(covariant CardDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardId != widget.cardId ||
        oldWidget.cardSlug != widget.cardSlug) {
      _currentCardId = widget.cardId;
      _currentCardSlug = widget.cardSlug;
      if (!_cardMatchesCurrent(_currentCardOverride)) {
        _currentCardOverride = null;
      }
      _detailViewRecorded = false;
      _isLoadingAdjacentCard = false;
      _isReturningToMarketplaceFromArtwork = false;
      _heroRetargetTimer?.cancel();
      _lastResolvedDebugCardId = null;
      FlutterDebugLog.instance.record(
        'card_detail.widget_updated',
        category: 'card_detail',
        payload: {
          'oldCardId': oldWidget.cardId,
          'oldCardSlug': oldWidget.cardSlug,
          'cardId': widget.cardId,
          'cardSlug': widget.cardSlug,
          'browserUrl': (currentBrowserUri() ?? Uri.base).toString(),
        },
      );
    }
    if (oldWidget.heroTag != widget.heroTag) {
      _activeHeroTag = widget.heroTag;
    }
  }

  @override
  void dispose() {
    FlutterDebugLog.instance.record(
      'card_detail.dispose',
      category: 'card_detail',
      payload: {
        'cardId': _currentCardId,
        'cardSlug': _currentCardSlug,
        'browserUrl': (currentBrowserUri() ?? Uri.base).toString(),
      },
    );
    CardDetailRouteGuard.instance.cardDetailDisposed();
    _heroRetargetTimer?.cancel();
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _searchFocusNode.dispose();
    _pageScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchFocusChanged() {
    final compactTopBar = MediaQuery.sizeOf(context).width < 760;
    if (!compactTopBar &&
        _searchFocusNode.hasFocus &&
        _searchController.text.trim().isEmpty) {
      showMarketplaceEmptyFocusSearchPreviews(ref);
    }
    if (mounted) {
      setState(() => _searchFocused = _searchFocusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardState = ref.watch(cardProvider);
    final cardKey = RegExp(r'^\d+$').hasMatch(_currentCardId)
        ? _currentCardId
        : _currentCardSlug ?? _currentCardId;
    final overrideCard =
        _cardMatchesCurrent(_currentCardOverride) ? _currentCardOverride : null;
    final card = overrideCard ?? _findCard(cardState.cards, cardKey);
    final needsDetailHydration = card != null && _needsDetailHydration(card);
    final directCardState = card == null || needsDetailHydration
        ? ref.watch(_cardDetailProvider(cardKey))
        : null;
    final directCard = directCardState?.valueOrNull;
    final resolvedCard = _bestDetailCard(
      card,
      directCard,
      routeSlug: _currentCardSlug,
    );

    if ((cardState.isLoading || (directCardState?.isLoading ?? false)) &&
        resolvedCard == null) {
      return const _DetailScaffold(child: _LoadingDetail());
    }

    if (resolvedCard == null) {
      return _DetailScaffold(
        child: _NotFoundDetail(
          cardId: cardKey,
          onBack: () => _goBackOr(context, '/marketplace'),
        ),
      );
    }
    if (_currentCardId != resolvedCard.id) {
      _currentCardId = resolvedCard.id;
    }
    CardDetailRouteGuard.instance.updateCardDetailRoute(
      GoRouterState.of(context).uri.toString(),
    );
    _recordResolvedCardLoaded(resolvedCard);
    _recordDetailViewOnce(resolvedCard);
    _warmMarketplaceAfterCardLoad(resolvedCard);
    _replaceLegacyUrlAfterLoad(resolvedCard);

    final listingsState = ref.watch(cardListingsProvider(resolvedCard.id));
    final listingOverrides =
        ref.watch(_detailListingOverridesProvider(resolvedCard.id));
    final listings = _applyListingOverrides(
      listingsState.valueOrNull ?? const <CardListing>[],
      listingOverrides,
    );
    final market = _CardMarketData.forCard(resolvedCard, listings);
    final bestListing = market.bestListing;
    final cartState = ref.watch(cartProvider);
    final favoritesState = ref.watch(favoritesProvider);
    final isFavorite = favoritesState.isFavorite(resolvedCard.id);
    final cachedBalance = ref.watch(cachedPknBalanceProvider).valueOrNull;
    final balance =
        ref.watch(pknBalanceProvider).valueOrNull ?? cachedBalance ?? 0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compactTopBar = screenWidth < 760;
    final showAssetHeader = screenWidth > 960;
    final showMarketStats = screenWidth > 960;
    final compactSearchExpanded = compactTopBar &&
        (_searchFocused || _searchController.text.trim().isNotEmpty);
    final isInCart = bestListing == null
        ? cartState.isInCart(resolvedCard.id)
        : cartState.isListingInCart(bestListing.id);
    final expansionCardsState =
        ref.watch(_expansionVersionCardsProvider(resolvedCard));
    final expansionCards = expansionCardsState.valueOrNull ?? const [];
    final sameNameVersions = _sameNameExpansionCards(
      expansionCards,
      resolvedCard,
    );
    final debugProductToggle = _DebugProductToggleButtons(
      card: resolvedCard,
      onChanged: ({required itemKind, required productType}) {
        final displayType = itemKind == 'product'
            ? _debugProductTypeLabel(productType)
            : 'Card';
        ref.read(cardProvider.notifier).cacheCards([
          resolvedCard.copyWith(
            itemKind: itemKind,
            productType: productType,
            type: displayType,
          ),
        ]);
        ref.invalidate(_cardDetailProvider(cardKey));
      },
    );

    final listingsTerminal = _ListingsTerminal(
      card: resolvedCard,
      market: market,
      isLoading: listingsState.isLoading,
      isFavorite: isFavorite,
      onSell: () => _openSellDialog(
        context,
        ref,
        resolvedCard,
        listings,
      ),
      onWishlist: () => ref.read(favoritesProvider.notifier).toggleFavorite(
            resolvedCard.id,
          ),
      pageScrollController: _pageScrollController,
    );
    final heroSectionContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showAssetHeader) ...[
          _AssetHeader(
            card: resolvedCard,
            language: widget.language,
            market: market,
            isFavorite: isFavorite,
            onSell: () => _openSellDialog(
              context,
              ref,
              resolvedCard,
              listings,
            ),
            onWishlist: () =>
                ref.read(favoritesProvider.notifier).toggleFavorite(
                      resolvedCard.id,
                    ),
            onShare: () => _copyCardLink(context, resolvedCard),
            debugProductToggle: debugProductToggle,
          ),
          const SizedBox(height: 18),
        ],
        _TopTerminal(
          card: resolvedCard,
          market: market,
          isInCart: isInCart,
          onSell: () => _openSellDialog(
            context,
            ref,
            resolvedCard,
            listings,
          ),
          onPrevious: _isLoadingAdjacentCard
              ? null
              : () => _showAdjacentCardOrLoad(
                    resolvedCard,
                    expansionCards,
                    direction: -1,
                  ),
          onNext: _isLoadingAdjacentCard
              ? null
              : () => _showAdjacentCardOrLoad(
                    resolvedCard,
                    expansionCards,
                    direction: 1,
                  ),
          onArtworkTap: _isReturningToMarketplaceFromArtwork
              ? null
              : () => _returnToMarketplaceFromArtwork(resolvedCard),
          versionCards: sameNameVersions,
          onVersionSelected: _showVersionCard,
          onViewAllVersions: () {
            final path = marketplaceCardVersionsPath(
              resolvedCard,
              language: widget.language,
            );
            if (path.isNotEmpty) {
              CardDetailRouteGuard.instance.markExplicitNavigation(
                path,
              );
              context.go(path);
            }
          },
          mobileListings: listingsTerminal,
          debugArtistSelector: _DebugMissingArtistSelector(
            card: resolvedCard,
            onSaved: (artist) {
              ref.read(cardProvider.notifier).cacheCards([
                resolvedCard.copyWith(artist: artist),
              ]);
              ref.invalidate(_cardDetailProvider(cardKey));
            },
          ),
        ),
      ],
    );
    final heroSection = _HeroCardDetailSection(
      heroTag: _activeHeroTag,
      child: heroSectionContent,
    );
    final showMobileListingsUnderArtwork = screenWidth <= 960;
    final detailContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heroSection,
        const SizedBox(height: 18),
        if (showMarketStats) ...[
          _MarketStatsGrid(market: market),
          const SizedBox(height: 18),
        ],
        if (!showMobileListingsUnderArtwork) listingsTerminal,
      ],
    );

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: CustomScrollView(
        controller: _pageScrollController,
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
                    ? () => showMarketplaceSideMenuWithNavigationIntent(
                          context,
                          CardDetailRouteGuard.instance.markExplicitNavigation,
                        )
                    : () {
                        CardDetailRouteGuard.instance.markExplicitNavigation(
                          '/marketplace',
                        );
                        context.go('/marketplace');
                      },
              ),
              search: MarketplaceTopBarSearch(
                controller: _searchController,
                focusNode: _searchFocusNode,
                compactTopBar: compactTopBar,
                holdOverlayForHero: false,
                onSearchFocusedChanged: (hasFocus) {
                  if (mounted) {
                    setState(() => _searchFocused = hasFocus);
                  }
                },
                onSelected: (selection) {
                  final card = selection.card;
                  ref.read(cardProvider.notifier).recordCardInteraction(
                        card,
                        'click',
                        source: 'search_preview',
                      );
                  _showSearchSelectedCard(card);
                  _resetHeaderSearch();
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
                keyValue: 'detail-marketplace-actions',
                beforeNavigate:
                    CardDetailRouteGuard.instance.markExplicitNavigation,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: detailContent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _resetHeaderSearch() {
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    }
    ref.read(cardProvider.notifier).clearSearchPreviews();
  }

  void _showSearchSelectedCard(PokemonCard card) {
    if (card.id == _currentCardId) {
      return;
    }
    _heroRetargetTimer?.cancel();
    unawaited(navigateToCanonicalCardDetail(
      context,
      card,
      language: widget.language,
      source: 'card_detail_search_preview',
      replace: true,
    ));
  }

  void _showVersionCard(PokemonCard card) {
    if (card.id == _currentCardId) {
      return;
    }
    final detailHeroTag = _recentlySeenHeroTag(card, 0);
    ref.read(cardProvider.notifier).recordCardInteraction(
          card,
          'view',
          source: 'card_detail_version_selector',
        );
    _seedRecentlySeenDestination(card);
    unawaited(navigateToCanonicalCardDetail(
      context,
      card,
      language: widget.language,
      source: 'card_detail_version_selector',
      extra: detailHeroTag,
    ));
  }

  void _showAdjacentCard(PokemonCard card) {
    if (card.id == _currentCardId) {
      return;
    }
    final detailHeroTag = _recentlySeenHeroTag(card, 0);
    ref.read(cardProvider.notifier).recordCardInteraction(
          card,
          'view',
          source: 'card_detail_adjacent',
        );
    _seedRecentlySeenDestination(card);
    unawaited(navigateToCanonicalCardDetail(
      context,
      card,
      language: widget.language,
      source: 'card_detail_adjacent',
      extra: detailHeroTag,
    ));
  }

  Future<void> _returnToMarketplaceFromArtwork(PokemonCard card) async {
    if (_isReturningToMarketplaceFromArtwork) {
      return;
    }
    final recentlySeenTag = _recentlySeenHeroTag(card, 0);
    setState(() {
      _isReturningToMarketplaceFromArtwork = true;
      _activeHeroTag = recentlySeenTag;
    });
    _seedRecentlySeenDestination(card);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || card.id != _currentCardId) {
      return;
    }
    if (_activeHeroTag != recentlySeenTag) {
      setState(() => _activeHeroTag = recentlySeenTag);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || card.id != _currentCardId) {
        return;
      }
    }
    CardDetailRouteGuard.instance.markExplicitNavigation(
      '/marketplace',
    );
    context.go(
      '/marketplace',
      extra: const MarketplaceHomeRouteIntent.returnToRecentTop(),
    );
  }

  Future<void> _showAdjacentCardOrLoad(
    PokemonCard current,
    List<PokemonCard> expansionCards, {
    required int direction,
  }) async {
    final adjacent = _adjacentExpansionCard(
      expansionCards,
      current.id,
      direction: direction,
    );
    if (adjacent != null) {
      _showAdjacentCard(adjacent);
      return;
    }
    if (_isLoadingAdjacentCard) {
      return;
    }
    setState(() => _isLoadingAdjacentCard = true);
    final loadedCards = await _cardService.getExpansionVersionCards(current);
    if (!mounted || current.id != _currentCardId) {
      return;
    }
    final loadedAdjacent = _adjacentExpansionCard(
      loadedCards,
      current.id,
      direction: direction,
    );
    if (loadedAdjacent == null) {
      setState(() => _isLoadingAdjacentCard = false);
      return;
    }
    _showAdjacentCard(loadedAdjacent);
  }

  void _recordDetailViewOnce(PokemonCard card) {
    if (_detailViewRecorded || card.id != _currentCardId) {
      return;
    }
    _detailViewRecorded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || card.id != _currentCardId) {
        return;
      }
      ref.read(cardProvider.notifier).recordCardInteraction(
            card,
            'view',
            source: 'card_detail',
          );
      _seedRecentlySeenDestination(card);
      _retargetHeroToRecentlySeen(card);
    });
  }

  void _recordResolvedCardLoaded(PokemonCard card) {
    if (_lastResolvedDebugCardId == card.id) {
      return;
    }
    _lastResolvedDebugCardId = card.id;
    FlutterDebugLog.instance.record(
      'card_detail.resolved_card_loaded',
      category: 'card_detail',
      routePath: GoRouterState.of(context).uri.path,
      payload: {
        'cardId': card.id,
        'name': card.name,
        'routeSlug': _currentCardSlug,
        'language': widget.language,
        'canonicalPath': safeCardDetailPath(card, language: widget.language),
        'goRouterPath': GoRouterState.of(context).uri.path,
        'browserUrl': (currentBrowserUri() ?? Uri.base).toString(),
      },
    );
  }

  void _seedRecentlySeenDestination(PokemonCard card) {
    ref.read(cardProvider.notifier).cacheCards([card]);
    ref.read(recentViewsProvider.notifier).rememberNow(card);
  }

  void _retargetHeroToRecentlySeen(PokemonCard card) {
    final recentlySeenTag = _recentlySeenHeroTag(card, 0);
    _heroRetargetTimer?.cancel();
    if (_activeHeroTag == null || _activeHeroTag!.isEmpty) {
      setState(() => _activeHeroTag = recentlySeenTag);
      return;
    }
    if (_activeHeroTag == recentlySeenTag) {
      return;
    }
    _heroRetargetTimer = Timer(const Duration(milliseconds: 360), () {
      if (!mounted ||
          card.id != _currentCardId ||
          _isReturningToMarketplaceFromArtwork) {
        return;
      }
      setState(() => _activeHeroTag = recentlySeenTag);
    });
  }

  void _warmMarketplaceAfterCardLoad(PokemonCard card) {
    if (_marketplaceWarmCardId == card.id) {
      FlutterDebugLog.instance.record(
        'card_detail.marketplace_warmup.skipped',
        category: 'card_detail',
        routePath: GoRouterState.of(context).uri.path,
        payload: {
          'cardId': card.id,
          'reason': 'already_requested_for_card',
          'browserUrl': (currentBrowserUri() ?? Uri.base).toString(),
        },
      );
      return;
    }
    _marketplaceWarmCardId = card.id;
    FlutterDebugLog.instance.record(
      'card_detail.marketplace_warmup.requested',
      category: 'card_detail',
      routePath: GoRouterState.of(context).uri.path,
      payload: {
        'cardId': card.id,
        'browserUrl': (currentBrowserUri() ?? Uri.base).toString(),
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || card.id != _currentCardId) {
        FlutterDebugLog.instance.record(
          'card_detail.marketplace_warmup.skipped',
          category: 'card_detail',
          payload: {
            'cardId': card.id,
            'reason': mounted ? 'card_changed' : 'unmounted',
            'currentCardId': _currentCardId,
            'browserUrl': (currentBrowserUri() ?? Uri.base).toString(),
          },
        );
        return;
      }
      final routePath = GoRouterState.of(context).uri.path;
      if (!_isWarmableCardDetailRoutePath(routePath, card)) {
        FlutterDebugLog.instance.record(
          'card_detail.marketplace_warmup.skipped',
          category: 'card_detail',
          routePath: routePath,
          payload: {
            'cardId': card.id,
            'reason': 'route_no_longer_card_detail',
            'browserUrl': (currentBrowserUri() ?? Uri.base).toString(),
          },
        );
        return;
      }
      unawaited(() async {
        try {
          await ref.read(cardProvider.notifier).warmMarketplaceAfterDetail();
          FlutterDebugLog.instance.record(
            'card_detail.marketplace_warmup.completed',
            category: 'card_detail',
            payload: {
              'cardId': card.id,
              'browserUrl': (currentBrowserUri() ?? Uri.base).toString(),
            },
          );
        } catch (error, stackTrace) {
          FlutterDebugLog.instance.recordError(
            'card_detail.marketplace_warmup.error',
            error,
            stackTrace: stackTrace,
            category: 'card_detail',
            payload: {'cardId': card.id},
          );
        }
      }());
    });
  }

  Future<void> _copyCardLink(BuildContext context, PokemonCard card) async {
    final origin = Uri.base.origin;
    final canonical = await _cardService.getMarketplaceCardCanonicalUrl(
      cardId: card.id,
      language: widget.language,
    );
    final path = databaseCanonicalCardDetailPath(
      card.copyWith(canonicalPath: canonical?.canonicalPath ?? ''),
    );
    if (path.isEmpty) {
      FlutterDebugLog.instance.record(
        'card_detail.copy_link.blocked',
        category: 'card_detail',
        payload: {
          'cardId': card.id,
          'reason': 'missing_database_canonical_path',
        },
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card link is not ready yet.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: '$origin$path'));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Card link copied to clipboard.')),
    );
  }

  PokemonCard? _findCard(List<PokemonCard> cards, String id) {
    final normalizedSlug = normalizeCardDetailSlug(id);
    for (final card in cards) {
      if (card.id == id ||
          cardDetailSlug(card) == normalizedSlug ||
          legacyCardDetailSlug(card) == normalizedSlug) {
        return card;
      }
    }
    return null;
  }

  bool _cardMatchesCurrent(PokemonCard? card) {
    if (card == null) {
      return false;
    }
    final slug = _currentCardSlug;
    return card.id == _currentCardId ||
        (slug != null && cardDetailSlugsMatch(cardDetailSlug(card), slug));
  }

  bool _needsDetailHydration(PokemonCard card) {
    return needsMarketplaceDetailHydration(card);
  }

  void _replaceLegacyUrlAfterLoad(PokemonCard card) {
    final currentPath = GoRouterState.of(context).uri.path;
    final routeSlug = _currentCardSlug;
    final browserUri = currentBrowserUri() ?? Uri.base;
    final isRootShortLink =
        routeSlug == null && currentPath == '/${card.id.trim()}';
    final isUnexpectedRootRoute = currentPath == '/';
    final isRootDetailRoute = isLegacyRootCardDetailPathForCard(
      path: currentPath,
      card: card,
    );
    final isLegacyMarketplaceRoute = currentPath.startsWith('/marketplace/');
    final isLegacyCardRoute = currentPath.startsWith('/card/');
    final shouldCanonicalize = isUnexpectedRootRoute ||
        isRootShortLink ||
        isRootDetailRoute ||
        isLegacyMarketplaceRoute ||
        isLegacyCardRoute;
    final traceKey = '${card.id}|$currentPath|$routeSlug';
    void traceCanonical(String eventName, Map<String, Object?> payload) {
      FlutterDebugLog.instance.record(
        eventName,
        category: 'card_detail',
        routePath: currentPath,
        browserUri: browserUri,
        payload: {
          'cardId': card.id,
          'routeSlug': routeSlug,
          'currentPath': currentPath,
          'browserUrl': browserUri.toString(),
          'goRouterLocation': GoRouterState.of(context).uri.toString(),
          ...payload,
        },
      );
    }

    if (_canonicalTraceKeys.add('$traceKey|attempt')) {
      traceCanonical('card_detail.canonical_replace.attempted', {
        'isUnexpectedRootRoute': isUnexpectedRootRoute,
        'isRootShortLink': isRootShortLink,
        'isRootDetailRoute': isRootDetailRoute,
        'isLegacyMarketplaceRoute': isLegacyMarketplaceRoute,
        'isLegacyCardRoute': isLegacyCardRoute,
        'shouldCanonicalize': shouldCanonicalize,
      });
    }
    if (!shouldCanonicalize) {
      if (_canonicalTraceKeys.add('$traceKey|skip_not_needed')) {
        traceCanonical('card_detail.canonical_replace.skipped', {
          'reason': 'not_legacy_route',
        });
      }
      return;
    }
    final localCanonicalPath =
        safeCardDetailPath(card, language: widget.language);
    final needsDbCanonicalPath =
        card.canonicalPath.trim().isEmpty || isRootDetailRoute;
    if (needsDbCanonicalPath) {
      _lookupAndReplaceCanonicalUrl(
        card: card,
        currentPath: currentPath,
        fallbackPath: localCanonicalPath,
        traceCanonical: traceCanonical,
      );
      return;
    }
    if (localCanonicalPath.isEmpty || currentPath == localCanonicalPath) {
      if (_canonicalTraceKeys.add('$traceKey|skip_same_or_empty')) {
        traceCanonical('card_detail.canonical_replace.skipped', {
          'reason': localCanonicalPath.isEmpty
              ? 'empty_canonical_path'
              : 'already_canonical',
          'canonicalPath': localCanonicalPath,
        });
      }
      return;
    }
    traceCanonical('card_detail.canonical_replace.scheduled', {
      'canonicalPath': localCanonicalPath,
    });
    _replaceWithCanonicalPath(card, localCanonicalPath);
  }

  void _lookupAndReplaceCanonicalUrl({
    required PokemonCard card,
    required String currentPath,
    required String fallbackPath,
    required void Function(String eventName, Map<String, Object?> payload)
        traceCanonical,
  }) {
    final lookupKey = '${card.id}|$currentPath|${widget.language}';
    if (_canonicalLookupKey == lookupKey) {
      return;
    }
    _canonicalLookupKey = lookupKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentCardId != card.id) {
        return;
      }
      unawaited(() async {
        final dbCanonical = await _cardService.getMarketplaceCardCanonicalUrl(
          cardId: card.id,
          path: currentPath,
          language: widget.language,
        );
        if (!mounted || _currentCardId != card.id) {
          return;
        }
        if (!isMarketplaceCardDetailRoutePath(
          GoRouterState.of(context).uri.path,
        )) {
          traceCanonical('card_detail.canonical_replace.skipped', {
            'reason': 'route_no_longer_card_detail',
          });
          return;
        }
        final canonicalPath = safeCardDetailPathWithDatabaseCanonical(
          card,
          databaseCanonicalPath: dbCanonical?.canonicalPath ?? '',
          language: widget.language,
        );
        final resolvedCanonicalPath =
            canonicalPath.isNotEmpty ? canonicalPath : fallbackPath;
        if (resolvedCanonicalPath.isEmpty ||
            GoRouterState.of(context).uri.path == resolvedCanonicalPath) {
          traceCanonical('card_detail.canonical_replace.skipped', {
            'reason': resolvedCanonicalPath.isEmpty
                ? 'empty_canonical_path'
                : 'already_canonical',
            'canonicalPath': resolvedCanonicalPath,
            'source': dbCanonical == null ? 'local_fallback' : 'database',
          });
          return;
        }
        if (dbCanonical != null &&
            card.canonicalPath != dbCanonical.canonicalPath) {
          ref.read(cardProvider.notifier).cacheCards([
            card.copyWith(canonicalPath: dbCanonical.canonicalPath),
          ]);
        }
        traceCanonical('card_detail.canonical_replace.scheduled', {
          'canonicalPath': resolvedCanonicalPath,
          'source': dbCanonical == null ? 'local_fallback' : 'database',
        });
        _replaceWithCanonicalPath(card, resolvedCanonicalPath);
      }());
    });
  }

  void _replaceWithCanonicalPath(PokemonCard card, String canonicalPath) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentCardId != card.id) {
        FlutterDebugLog.instance.record(
          'card_detail.canonical_replace.skipped',
          category: 'card_detail',
          payload: {
            'cardId': card.id,
            'reason': mounted ? 'card_changed' : 'unmounted',
            'currentCardId': _currentCardId,
            'canonicalPath': canonicalPath,
            'browserUrl': (currentBrowserUri() ?? Uri.base).toString(),
          },
        );
        return;
      }
      final routePath = GoRouterState.of(context).uri.path;
      final browserPath = (currentBrowserUri() ?? Uri.base).path;
      if (!isMarketplaceCardDetailRoutePath(routePath) &&
          !isLegacyRootCardDetailPathForCard(path: routePath, card: card) &&
          routePath != '/${card.id.trim()}') {
        FlutterDebugLog.instance.record(
          'card_detail.canonical_replace.skipped',
          category: 'card_detail',
          routePath: routePath,
          payload: {
            'cardId': card.id,
            'reason': 'route_no_longer_card_detail',
            'canonicalPath': canonicalPath,
            'browserUrl': (currentBrowserUri() ?? Uri.base).toString(),
          },
        );
        return;
      }
      if (browserPath != routePath) {
        FlutterDebugLog.instance.record(
          'card_detail.canonical_replace.skipped',
          category: 'card_detail',
          routePath: routePath,
          payload: {
            'cardId': card.id,
            'reason': 'browser_router_path_mismatch',
            'browserPath': browserPath,
            'canonicalPath': canonicalPath,
            'browserUrl': (currentBrowserUri() ?? Uri.base).toString(),
          },
        );
        return;
      }
      if (routePath == canonicalPath) {
        FlutterDebugLog.instance.record(
          'card_detail.canonical_replace.skipped',
          category: 'card_detail',
          routePath: routePath,
          payload: {
            'cardId': card.id,
            'reason': 'route_already_canonical_after_frame',
            'canonicalPath': canonicalPath,
            'browserUrl': (currentBrowserUri() ?? Uri.base).toString(),
          },
        );
        return;
      }
      FlutterDebugLog.instance.record(
        'card_detail.canonical_replace.executed',
        category: 'card_detail',
        routePath: routePath,
        payload: {
          'cardId': card.id,
          'fromRoutePath': routePath,
          'canonicalPath': canonicalPath,
          'browserUrlBefore': (currentBrowserUri() ?? Uri.base).toString(),
        },
      );
      final canonicalLocation = cardDetailCanonicalReplacementLocation(
        canonicalPath: canonicalPath,
        currentUri: GoRouterState.of(context).uri,
      );
      if (canonicalLocation.isEmpty) {
        return;
      }
      CardDetailRouteGuard.instance.updateCardDetailRoute(canonicalLocation);
      context.replace(canonicalLocation);
    });
  }

  PokemonCard? _adjacentExpansionCard(
    List<PokemonCard> expansionCards,
    String currentId, {
    required int direction,
  }) {
    if (expansionCards.length < 2) {
      return null;
    }
    final index = expansionCards.indexWhere((card) => card.id == currentId);
    if (index < 0) {
      return null;
    }
    final adjacentIndex = (index + direction) % expansionCards.length;
    final adjacent = expansionCards[
        adjacentIndex < 0 ? expansionCards.length - 1 : adjacentIndex];
    return adjacent.id == currentId ? null : adjacent;
  }

  void _openSellDialog(
    BuildContext context,
    WidgetRef ref,
    PokemonCard card,
    List<CardListing> listings,
  ) {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      final authPath =
          '/auth?from=${Uri.encodeComponent(_authReturnPath(card))}';
      CardDetailRouteGuard.instance.markExplicitNavigation(authPath);
      context.go(authPath);
      return;
    }
    final profile = ref.read(userProfileProvider).valueOrNull;
    final initialPricePkn = _minimumListingPrice(listings);
    showDialog(
      context: context,
      builder: (context) => _SellListingDialog(
        card: card,
        sellerUid: user.uid,
        sellerName: profile?.displayName.trim().isNotEmpty == true
            ? profile!.displayName
            : user.displayName ?? user.email ?? 'Pokoin seller',
        initialPricePkn: initialPricePkn,
        onSaved: (listing) => _upsertVisibleListing(ref, card.id, listing),
      ),
    );
  }

  double? _minimumListingPrice(List<CardListing> listings) {
    final prices = listings
        .where((listing) => listing.isActive && listing.pricePkn > 0)
        .map((listing) => listing.pricePkn)
        .toList()
      ..sort();
    return prices.isEmpty ? null : prices.first;
  }
}

List<CardListing> _applyListingOverrides(
  List<CardListing> baseListings,
  Map<String, CardListing?> overrides,
) {
  if (overrides.isEmpty) return baseListings;
  final byId = <String, CardListing>{
    for (final listing in baseListings)
      if (listing.id.trim().isNotEmpty) listing.id: listing,
  };
  for (final entry in overrides.entries) {
    final listing = entry.value;
    if (listing == null ||
        !listing.isActive ||
        listing.quantityAvailable <= 0) {
      byId.remove(entry.key);
    } else {
      byId[entry.key] = listing;
    }
  }
  final listings = byId.values.toList()
    ..sort((left, right) {
      final price = left.pricePkn.compareTo(right.pricePkn);
      if (price != 0) return price;
      final leftUpdated = left.updatedAt ?? left.createdAt ?? DateTime(0);
      final rightUpdated = right.updatedAt ?? right.createdAt ?? DateTime(0);
      return rightUpdated.compareTo(leftUpdated);
    });
  return listings;
}

void _upsertVisibleListing(WidgetRef ref, String cardId, CardListing listing) {
  if (listing.id.trim().isEmpty) return;
  ref.read(_detailListingOverridesProvider(cardId).notifier).update(
        (state) => {...state, listing.id: listing},
      );
  ref.invalidate(cardListingsProvider(cardId));
  ref.invalidate(activeCardListingsProvider);
  ref.invalidate(sellerListingsProvider(listing.sellerUid));
}

void _removeVisibleListing(
  WidgetRef ref,
  String cardId,
  CardListing listing,
) {
  if (listing.id.trim().isEmpty) return;
  ref.read(_detailListingOverridesProvider(cardId).notifier).update(
        (state) => {...state, listing.id: null},
      );
  ref.invalidate(cardListingsProvider(cardId));
  ref.invalidate(activeCardListingsProvider);
  ref.invalidate(sellerListingsProvider(listing.sellerUid));
}

List<PokemonCard> _sameNameExpansionCards(
  List<PokemonCard> cards,
  PokemonCard current,
) {
  final name = current.name.trim().toLowerCase();
  final expansion = current.set.trim().toLowerCase();
  return cards
      .where((card) =>
          card.name.trim().toLowerCase() == name &&
          card.set.trim().toLowerCase() == expansion)
      .toList();
}

final _cardDetailProvider =
    FutureProvider.family<PokemonCard?, String>((ref, cardPage) {
  if (cardDetailSlugHasNumericId(cardPage)) {
    return ref
        .read(cardProvider.notifier)
        .loadCardById(cardIdFromSlug(cardPage));
  }
  return ref.read(cardProvider.notifier).loadCardByDetailSlug(cardPage);
});

String _recentlySeenHeroTag(PokemonCard card, int index) {
  return 'market-card-image-${card.id}-carousel-Recently seen-$index';
}

String _authReturnPath(PokemonCard card) {
  final path = databaseCanonicalCardDetailPath(card);
  return path.isEmpty ? '/marketplace' : path;
}

bool _isWarmableCardDetailRoutePath(String path, PokemonCard card) {
  if (isMarketplaceCardDetailRoutePath(path) ||
      isLegacyRootCardDetailPathForCard(path: path, card: card)) {
    return true;
  }
  final cardId = card.id.trim();
  if (cardId.isEmpty || !RegExp(r'^\d+$').hasMatch(cardId)) {
    return false;
  }
  final doubledId = doubledCardId(cardId);
  return path == '/$cardId' ||
      path == '/$doubledId' ||
      path == '/card/$cardId' ||
      path == '/card/$doubledId';
}

PokemonCard? _bestDetailCard(
  PokemonCard? cached,
  PokemonCard? direct, {
  required String? routeSlug,
}) {
  final directNumber = direct?.number.trim() ?? '';
  final cachedNumber = cached?.number.trim() ?? '';
  if (direct != null && (cached == null || directNumber.isNotEmpty)) {
    return direct;
  }
  if (cached != null && cachedNumber.isEmpty) {
    final routeNumber = _collectorNumberFromDetailSlug(routeSlug);
    if (routeNumber.isNotEmpty) {
      return cached.copyWith(number: routeNumber);
    }
  }
  return cached ?? direct;
}

String _collectorNumberFromDetailSlug(String? slug) {
  final normalized = normalizeCardDetailSlug(slug ?? '');
  if (normalized.isEmpty) {
    return '';
  }
  final parts = normalized
      .split('-')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  for (var index = 0; index < parts.length - 1; index += 1) {
    final first = int.tryParse(parts[index]);
    final second = int.tryParse(parts[index + 1]);
    if (first == null || second == null || second <= 0) {
      continue;
    }
    if (first <= second || parts[index].startsWith('0')) {
      return '${parts[index]}/${parts[index + 1]}';
    }
  }
  return '';
}

final _expansionVersionCardsProvider =
    FutureProvider.family<List<PokemonCard>, PokemonCard>((ref, card) {
  return CardService().getExpansionVersionCards(card);
});

void _goBackOr(BuildContext context, String fallbackPath) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  CardDetailRouteGuard.instance.markExplicitNavigation(
    fallbackPath,
  );
  context.go(fallbackPath);
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
    final setCodeMatch = RegExp(r'\b[A-Z]{2,5}\s*\d{1,4}[A-Za-z]?\b')
        .firstMatch(part.toUpperCase());
    if (setCodeMatch != null) {
      return setCodeMatch.group(0)!.replaceAll(RegExp(r'\s+'), ' ');
    }
  }
  for (final part in parts.reversed) {
    if (RegExp(r'\d').hasMatch(part)) {
      return part;
    }
  }
  return text;
}

String _collectionSignature({
  required String name,
  required String setName,
  required String number,
}) {
  final normalizedName = _collectionKeyPart(name);
  final normalizedSet = _collectionKeyPart(setName);
  final normalizedNumber = _collectionNumberKey(number);
  if (normalizedName.isEmpty ||
      normalizedSet.isEmpty ||
      normalizedNumber.isEmpty) {
    return '';
  }
  return '$normalizedName|$normalizedSet|$normalizedNumber';
}

String _collectionKeyPart(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String _collectionNumberKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String _setAndVariantLabel(PokemonCard card) {
  final variant = card.number.trim();
  if (variant.isEmpty) {
    return card.set;
  }
  return '${card.set} · $variant';
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _LoadingDetail extends StatelessWidget {
  const _LoadingDetail();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFFACC15)),
            SizedBox(height: 18),
            Text(
              'Loading card market...',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotFoundDetail extends StatelessWidget {
  const _NotFoundDetail({
    required this.cardId,
    required this.onBack,
  });

  final String cardId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.style_outlined,
                color: Color(0xFFFACC15), size: 46),
            const SizedBox(height: 14),
            const Text(
              'Card market not found',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No local market is available for public number $cardId yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF93A4C8)),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Back to marketplace'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkCircleButton extends StatelessWidget {
  const _DarkCircleButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.foregroundColor = const Color(0xFFCBD5E1),
    this.backgroundColor,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color foregroundColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final contentColor = enabled ? foregroundColor : const Color(0xFF64748B);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor ??
            (enabled
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.04)),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          hoverColor: Colors.white.withValues(alpha: 0.12),
          highlightColor: Colors.white.withValues(alpha: 0.10),
          child: SizedBox(
            width: 42,
            height: 42,
            child: IconTheme(
              data: IconThemeData(color: contentColor, size: 20),
              child: Center(child: icon),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssetHeader extends StatelessWidget {
  const _AssetHeader({
    required this.card,
    required this.language,
    required this.market,
    required this.isFavorite,
    required this.onSell,
    required this.onWishlist,
    required this.onShare,
    required this.debugProductToggle,
  });

  final PokemonCard card;
  final String language;
  final _CardMarketData market;
  final bool isFavorite;
  final VoidCallback onSell;
  final VoidCallback onWishlist;
  final VoidCallback onShare;
  final Widget debugProductToggle;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 820;
    final paletteHint = cardPaletteHint(
      type: card.type,
      name: card.name,
      tags: card.tags,
    );
    final accentGradient = cardAccentHeaderGradientForPayload(
      card.cardPalette,
      fallbackType: paletteHint,
    );
    final badges = Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        children: [
          const _Badge(text: 'Pokémon', color: Color(0xFF38BDF8)),
          if (card.itemKind == 'product')
            _Badge(text: card.type, color: const Color(0xFFA78BFA)),
          if (card.itemKind != 'product' &&
              card.rarity.isNotEmpty &&
              card.rarity != 'Card')
            _Badge(text: card.rarity, color: const Color(0xFFFACC15)),
          if (card.isHolo) const _Badge(text: 'Holo', color: Color(0xFFA78BFA)),
        ],
      ),
    );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              card.name,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            if (card.emoji.trim().isNotEmpty)
              Text(
                card.emoji,
                style: const TextStyle(fontSize: 24, height: 1),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => context.go(
                '/marketplace/search?expansion=${Uri.encodeQueryComponent(card.set)}',
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  card.set,
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (card.itemKind == 'product')
              Text(
                ' · ${card.number.trim().isEmpty ? card.type : '${card.number} · ${card.type}'}',
                style: const TextStyle(color: Color(0xFFB8C4E6)),
              )
            else ...[
              if (_displayCollectorNumber(card.number).isNotEmpty)
                Text(
                  ' ${_displayCollectorNumber(card.number)} ·',
                  style: const TextStyle(color: Color(0xFFB8C4E6)),
                )
              else
                const Text(
                  ' ·',
                  style: TextStyle(color: Color(0xFFB8C4E6)),
                ),
              _ArtistCollectionLink(
                artist: card.artist,
                fallbackLabel: card.type,
                language: language,
              ),
            ],
          ],
        ),
        debugProductToggle,
      ],
    );
    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _QuotePill(
          label: 'Floor',
          value: market.hasListings ? formatPkn(market.floorPrice) : '—',
        ),
        _QuotePill(
          label: '24h',
          value: market.change24hLabel,
          positive: true,
        ),
        _DarkCircleButton(
          onPressed: onWishlist,
          icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
          tooltip: isFavorite ? 'Remove from watchlist' : 'Add to watchlist',
          foregroundColor:
              isFavorite ? const Color(0xFFFACC15) : const Color(0xFFCBD5E1),
          backgroundColor: isFavorite
              ? const Color(0xFFFACC15).withValues(alpha: 0.14)
              : null,
        ),
        _DarkCircleButton(
          onPressed: onShare,
          icon: const Icon(Icons.ios_share),
          tooltip: 'Share',
        ),
      ],
    );

    if (compact) {
      return _Panel(
        padding: const EdgeInsets.all(18),
        gradient: accentGradient,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            badges,
            const SizedBox(height: 16),
            title,
            const SizedBox(height: 16),
            actions,
          ],
        ),
      );
    }

    return _Panel(
      padding: const EdgeInsets.all(18),
      gradient: accentGradient,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: badges,
          ),
          const SizedBox(width: 18),
          Expanded(child: title),
          const SizedBox(width: 18),
          actions,
        ],
      ),
    );
  }
}

class _TopTerminal extends StatelessWidget {
  const _TopTerminal({
    required this.card,
    required this.market,
    required this.isInCart,
    required this.onSell,
    required this.onPrevious,
    required this.onNext,
    required this.onArtworkTap,
    required this.versionCards,
    required this.onVersionSelected,
    required this.onViewAllVersions,
    required this.mobileListings,
    required this.debugArtistSelector,
  });

  final PokemonCard card;
  final _CardMarketData market;
  final bool isInCart;
  final VoidCallback onSell;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onArtworkTap;
  final List<PokemonCard> versionCards;
  final ValueChanged<PokemonCard> onVersionSelected;
  final VoidCallback onViewAllVersions;
  final Widget mobileListings;
  final Widget debugArtistSelector;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 960;
    final paletteHint = cardPaletteHint(
      type: card.type,
      name: card.name,
      tags: card.tags,
    );
    final accentGradient = cardAccentHeaderGradientForPayload(
      card.cardPalette,
      fallbackType: paletteHint,
    );
    final artwork = _ArtworkPanel(
      card: card,
      onPrevious: onPrevious,
      onNext: onNext,
      onArtworkTap: onArtworkTap,
      versionCards: versionCards,
      onVersionSelected: onVersionSelected,
      onViewAllVersions: onViewAllVersions,
    );
    final center = _MarketCenterPanel(
      card: card,
      market: market,
      debugArtistSelector: debugArtistSelector,
    );
    final deal = _BestDealPanel(
      card: card,
      market: market,
      isInCart: isInCart,
      mobileGradient: accentGradient,
    );

    final layout = wide
        ? Row(
            key: const ValueKey('card-detail-wide-layout'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 300, child: artwork),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: center),
              const SizedBox(width: 16),
              SizedBox(width: 300, child: deal),
            ],
          )
        : Column(
            key: const ValueKey('card-detail-narrow-layout'),
            children: [
              deal,
              const SizedBox(height: 16),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: artwork,
                ),
              ),
              const SizedBox(height: 16),
              mobileListings,
              const SizedBox(height: 16),
              center,
            ],
          );

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.topCenter,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (child, animation) {
          final offsetAnimation = Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offsetAnimation, child: child),
          );
        },
        child: layout,
      ),
    );
  }
}

class _ArtworkPanel extends StatelessWidget {
  const _ArtworkPanel({
    required this.card,
    required this.onPrevious,
    required this.onNext,
    required this.onArtworkTap,
    required this.versionCards,
    required this.onVersionSelected,
    required this.onViewAllVersions,
  });

  final PokemonCard card;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onArtworkTap;
  final List<PokemonCard> versionCards;
  final ValueChanged<PokemonCard> onVersionSelected;
  final VoidCallback onViewAllVersions;

  @override
  Widget build(BuildContext context) {
    final displayNumber = _displayCollectorNumber(card.number);
    final paletteHint = cardPaletteHint(
      type: card.type,
      name: card.name,
      tags: card.tags,
    );
    final frameColor = cardImageFrameColorForPayload(
      card.cardPalette,
      fallbackType: paletteHint,
    );
    final panel = _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _DarkCircleButton(
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous card',
              ),
              Flexible(
                child: _Badge(
                  text: displayNumber,
                  color: const Color(0xFF38BDF8),
                ),
              ),
              _DarkCircleButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next card',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ArtworkBackButton(
            onTap: onArtworkTap,
            child: AspectRatio(
              aspectRatio: 0.72,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: frameColor,
                  borderRadius: BorderRadius.circular(22),
                ),
                clipBehavior: Clip.none,
                child: CachedNetworkImage(
                  imageUrl: card.imageUrl,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  errorWidget: (_, __, ___) => const Icon(
                    Icons.style,
                    color: Color(0xFFFACC15),
                    size: 72,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _VersionSelector(
            card: card,
            displayNumber: displayNumber,
            versionCards: versionCards,
            onSelected: onVersionSelected,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onViewAllVersions,
            child: const Text('View all versions'),
          ),
        ],
      ),
    );
    return panel;
  }
}

class _ArtworkBackButton extends StatefulWidget {
  const _ArtworkBackButton({
    required this.onTap,
    required this.child,
  });

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_ArtworkBackButton> createState() => _ArtworkBackButtonState();
}

class _ArtworkBackButtonState extends State<_ArtworkBackButton> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _active => _hovered || _pressed;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final sigma = enabled && _active ? 1.8 : 0.0;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (enabled) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: _active
                  ? [
                      BoxShadow(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.18),
                        blurRadius: 24,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MarketCenterPanel extends ConsumerStatefulWidget {
  const _MarketCenterPanel({
    required this.card,
    required this.market,
    required this.debugArtistSelector,
  });

  final PokemonCard card;
  final _CardMarketData market;
  final Widget debugArtistSelector;

  @override
  ConsumerState<_MarketCenterPanel> createState() => _MarketCenterPanelState();
}

class _MarketCenterPanelState extends ConsumerState<_MarketCenterPanel> {
  bool _sellPanelExpanded = false;

  @override
  void didUpdateWidget(covariant _MarketCenterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id) {
      _sellPanelExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 760;
    final narrow = width <= 960;
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MarketInfoPane(
            market: widget.market,
            sales: ref.watch(cardSalesHistoryProvider(widget.card.id)),
          ),
          widget.debugArtistSelector,
          const SizedBox(height: 12),
          if (narrow)
            _ToggleableSellListingPanel(
              card: widget.card,
              initialPricePkn: _suggestedListingPrice(widget.market),
              expanded: _sellPanelExpanded,
              compact: compact,
              onToggle: () =>
                  setState(() => _sellPanelExpanded = !_sellPanelExpanded),
            )
          else
            _InlineSellListingForm(
              card: widget.card,
              initialPricePkn: _suggestedListingPrice(widget.market),
              compactMode: true,
            ),
        ],
      ),
    );
  }

  double? _suggestedListingPrice(_CardMarketData market) {
    return market.hasListings && market.bestDeal > 0 ? market.bestDeal : null;
  }
}

class _CollapsedSellListingPanel extends StatelessWidget {
  const _CollapsedSellListingPanel({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1735),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: const Row(
            children: [
              Icon(Icons.sell_outlined, color: Color(0xFFFACC15), size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'List your card',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Tap to add price, condition and extras',
                      style: TextStyle(
                        color: Color(0xFF93A4C8),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.keyboard_arrow_down, color: Color(0xFF93A4C8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleableSellListingPanel extends StatelessWidget {
  const _ToggleableSellListingPanel({
    required this.card,
    required this.initialPricePkn,
    required this.expanded,
    required this.compact,
    required this.onToggle,
  });

  final PokemonCard card;
  final double? initialPricePkn;
  final bool expanded;
  final bool compact;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return _CollapsedSellListingPanel(onTap: onToggle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SellListingToggleHeader(onTap: onToggle),
        const SizedBox(height: 10),
        _InlineSellListingForm(
          card: card,
          initialPricePkn: initialPricePkn,
          compactMode: true,
          ultraCompact: !compact,
        ),
      ],
    );
  }
}

class _SellListingToggleHeader extends StatelessWidget {
  const _SellListingToggleHeader({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1735),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: const Row(
            children: [
              Icon(Icons.sell_outlined, color: Color(0xFFFACC15), size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'List your card',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.keyboard_arrow_up, color: Color(0xFF93A4C8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarketInfoPane extends StatelessWidget {
  const _MarketInfoPane({
    required this.market,
    required this.sales,
  });

  final _CardMarketData market;
  final AsyncValue<List<CardSaleEvent>> sales;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: _PriceChart(market: market, sales: sales),
        ),
      ],
    );
  }
}

class _HeroCardDetailSection extends StatelessWidget {
  const _HeroCardDetailSection({
    required this.heroTag,
    required this.child,
  });

  final String? heroTag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tag = heroTag;
    if (tag == null || tag.isEmpty) {
      return child;
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
          scale: Tween<double>(begin: 0.98, end: 1).animate(
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

class _InlineSellListingForm extends ConsumerStatefulWidget {
  const _InlineSellListingForm({
    required this.card,
    required this.initialPricePkn,
    this.compactMode = false,
    this.ultraCompact = false,
  });

  final PokemonCard card;
  final double? initialPricePkn;
  final bool compactMode;
  final bool ultraCompact;

  @override
  ConsumerState<_InlineSellListingForm> createState() =>
      _InlineSellListingFormState();
}

class _InlineSellListingFormState
    extends ConsumerState<_InlineSellListingForm> {
  final TextEditingController _priceController = TextEditingController();
  final FocusNode _priceFocusNode = FocusNode();
  final TextEditingController _quantityController =
      TextEditingController(text: '1');
  final TextEditingController _gradingCompanyController =
      TextEditingController(text: 'PSA');
  final TextEditingController _gradeController = TextEditingController();
  final TextEditingController _certificationIdController =
      TextEditingController();
  final TextEditingController _sellerCommentController =
      TextEditingController();
  String _condition = 'NM';
  String _language = 'EN';
  bool _firstEdition = false;
  String _foilState = 'standard';
  final TextEditingController _variantStateController = TextEditingController();
  bool _sealed = false;
  bool _signed = false;
  bool _graded = false;
  bool _shippingAvailable = true;
  bool _reserveAvailable = false;
  bool _nftAvailable = false;
  String? _selectedNftCollectionItemId;
  bool _isSaving = false;
  String _priceCurrency = 'PKN';
  Timer? _priceQuoteTimer;
  int _priceQuoteToken = 0;
  int _fallbackPriceToken = 0;
  bool _appliedFallbackPrice = false;
  double? _suggestedPricePkn;
  String? _suggestedPriceText;
  bool _priceWasEdited = false;
  _ListingPriceQuote? _warmedPriceQuote;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setSuggestedPrice(widget.initialPricePkn);
    _priceController.addListener(_schedulePriceQuoteWarmup);
    _priceFocusNode.addListener(_handlePriceFocusChanged);
    _foilState = _defaultFoilStateForCard(widget.card);
    _loadFallbackPriceIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _InlineSellListingForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id ||
        oldWidget.initialPricePkn != widget.initialPricePkn) {
      _priceController.clear();
      _setSuggestedPrice(widget.initialPricePkn);
      _priceWasEdited = false;
      _quantityController.text = '1';
      _condition = 'NM';
      _language = 'EN';
      _firstEdition = false;
      _foilState = _defaultFoilStateForCard(widget.card);
      _variantStateController.clear();
      _sealed = false;
      _signed = false;
      _graded = false;
      _shippingAvailable = true;
      _reserveAvailable = false;
      _nftAvailable = false;
      _selectedNftCollectionItemId = null;
      _priceCurrency = 'PKN';
      _appliedFallbackPrice = false;
      _fallbackPriceToken++;
      _cancelPriceQuoteWarmup(clearQuote: true);
      _sellerCommentController.clear();
      _error = null;
    }
    _loadFallbackPriceIfNeeded();
  }

  @override
  void dispose() {
    _fallbackPriceToken++;
    _priceQuoteTimer?.cancel();
    _priceController.removeListener(_schedulePriceQuoteWarmup);
    _priceFocusNode.removeListener(_handlePriceFocusChanged);
    _priceFocusNode.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _gradingCompanyController.dispose();
    _gradeController.dispose();
    _certificationIdController.dispose();
    _sellerCommentController.dispose();
    _variantStateController.dispose();
    super.dispose();
  }

  void _setSuggestedPrice(double? price) {
    if (price == null || price <= 0) {
      _suggestedPricePkn = null;
      _suggestedPriceText = null;
      return;
    }
    _suggestedPricePkn = price;
    _suggestedPriceText = formatPknAmount(price);
  }

  void _handlePriceFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String? get _priceHintText {
    if (_priceCurrency != 'PKN' ||
        _priceFocusNode.hasFocus ||
        _priceWasEdited) {
      return null;
    }
    final suggestion = _suggestedPriceText;
    return suggestion;
  }

  List<UserCardCollectionItem> _ownedNftsForCard(
    PokemonCard card,
    List<UserCardCollectionItem>? items,
  ) {
    if (items == null || items.isEmpty) {
      return const [];
    }
    final cardId = card.id.trim();
    final signature = _collectionSignature(
      name: card.name,
      setName: card.set,
      number: card.number,
    );
    return items.where((item) {
      if (!item.isNft) return false;
      if (cardId.isNotEmpty && item.cardId.trim() == cardId) return true;
      if (signature.isEmpty) return false;
      return _collectionSignature(
            name: item.cardName,
            setName: item.setName,
            number: item.collectorNumber,
          ) ==
          signature;
    }).toList(growable: false);
  }

  UserCardCollectionItem? _selectedOwnedNft(List<UserCardCollectionItem> nfts) {
    if (nfts.isEmpty) {
      return null;
    }
    final selectedId = _selectedNftCollectionItemId;
    if (selectedId != null && selectedId.isNotEmpty) {
      for (final item in nfts) {
        if (item.id == selectedId) {
          return item;
        }
      }
    }
    return nfts.first;
  }

  void _applyOwnedNftToForm(UserCardCollectionItem nft) {
    _selectedNftCollectionItemId = nft.id;
    _condition = _listingConditionFromCollectionItem(nft);
    _language = _listingLanguageFromCollectionItem(nft);
    _firstEdition = nft.firstEdition;
    _foilState = _foilStateFromCollectionItem(nft);
    _sealed = false;
    _graded = nft.graded;
    _shippingAvailable = nft.canRequestPhysicalShipping;
    _quantityController.text = '1';
    _variantStateController.text = _nftVariantState(nft);
    if (nft.graded) {
      _gradingCompanyController.text = _nonEmptyOrFallback(
          nft.gradingCompany, _gradingCompanyController.text);
      _gradeController.text = nft.grade ?? '';
      _certificationIdController.text = nft.certificationId ?? '';
    } else {
      _gradeController.clear();
      _certificationIdController.clear();
    }
    final comment = _nftSellerComment(nft);
    if (comment.isNotEmpty) {
      _sellerCommentController.text = comment;
    }
  }

  String _listingConditionFromCollectionItem(UserCardCollectionItem nft) {
    final value = nft.condition.trim();
    return const {'NM', 'SP', 'MP', 'PL', 'Poor'}.contains(value)
        ? value
        : 'NM';
  }

  String _listingLanguageFromCollectionItem(UserCardCollectionItem nft) {
    final value = nft.language.trim().toUpperCase();
    return _listingLanguageCodes.contains(value) ? value : 'EN';
  }

  String _foilStateFromCollectionItem(UserCardCollectionItem nft) {
    if (nft.reverse) return 'reverse';
    if (nft.holo) return 'holo';
    return 'standard';
  }

  String _nftVariantState(UserCardCollectionItem nft) {
    final parts = <String>[];
    if (nft.sourceOrderId.trim().isNotEmpty) {
      parts.add('Order ${nft.sourceOrderId.trim()}');
    }
    if (nft.sourceListingId.trim().isNotEmpty) {
      parts.add('NFT source ${nft.sourceListingId.trim()}');
    }
    return parts.join(' • ');
  }

  String _nftSellerComment(UserCardCollectionItem nft) {
    final status =
        nft.nftStatus.trim().isEmpty ? 'owned' : nft.nftStatus.trim();
    return 'NFT metadata: $status';
  }

  String _nonEmptyOrFallback(String? value, String fallback) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  void _setNftAvailable(bool value, List<UserCardCollectionItem> ownedNfts) {
    if (!value) {
      setState(() {
        _nftAvailable = false;
        _selectedNftCollectionItemId = null;
        _shippingAvailable = true;
        _quantityController.text = '1';
        _loadFallbackPriceIfNeeded();
      });
      return;
    }
    final nft = _selectedOwnedNft(ownedNfts);
    if (nft == null) {
      return;
    }
    setState(() {
      _nftAvailable = true;
      _applyOwnedNftToForm(nft);
      _appliedFallbackPrice = true;
      _cancelPriceQuoteWarmup(clearQuote: true);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final canUseReserveToggle = _canUseReserveListingToggle(profile);
    final compact = MediaQuery.sizeOf(context).width < 760;
    final sellerUid = user?.uid;
    final sellerName = profile?.displayName.trim().isNotEmpty == true
        ? profile!.displayName
        : user?.displayName ?? user?.email ?? 'Pokoin seller';
    final ownedNftsState = ref.watch(userCardCollectionProvider);
    final ownedNfts =
        _ownedNftsForCard(widget.card, ownedNftsState.valueOrNull);
    final nftStateCardId = widget.card.id;
    if (_nftAvailable && ownedNfts.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.card.id != nftStateCardId) return;
        setState(() {
          _nftAvailable = false;
          _selectedNftCollectionItemId = null;
        });
      });
    } else if (_nftAvailable) {
      final selectedNft = _selectedOwnedNft(ownedNfts);
      if (selectedNft != null &&
          _selectedNftCollectionItemId != selectedNft.id) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || widget.card.id != nftStateCardId) return;
          setState(() => _applyOwnedNftToForm(selectedNft));
        });
      }
    }
    final selectedOwnedNft =
        _nftAvailable ? _selectedOwnedNft(ownedNfts) : null;
    final nftLocked = selectedOwnedNft != null;
    final formTheme = Theme.of(context).copyWith(
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFACC15),
        surface: Color(0xFF0B1024),
        onSurface: Colors.white,
      ),
      textTheme: Theme.of(context).textTheme.apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: const TextStyle(color: Color(0xFF93A4C8)),
        floatingLabelStyle: const TextStyle(color: Color(0xFFFACC15)),
        hintStyle: const TextStyle(color: Color(0xFF64748B)),
        filled: true,
        fillColor: const Color(0xFF111936),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFACC15)),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFF111827)
              : const Color(0xFF94A3B8),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFFFACC15)
              : const Color(0xFF1E2A4A),
        ),
      ),
    );

    return Theme(
      data: formTheme,
      child: Container(
        padding: EdgeInsets.all(widget.ultraCompact
            ? 10
            : widget.compactMode
                ? 12
                : 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1735),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.ultraCompact ? 'Sell this card' : 'List your card',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.ultraCompact ? 15 : 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (user == null)
                  TextButton(
                    onPressed: () => context.go(
                      '/auth?from=${Uri.encodeComponent(_authReturnPath(widget.card))}',
                    ),
                    child: const Text('Sign in'),
                  ),
              ],
            ),
            SizedBox(height: widget.ultraCompact ? 8 : 12),
            _buildPrimaryListingRow(
              sellerUid: sellerUid,
              sellerName: sellerName,
              compact: compact || widget.compactMode,
            ),
            SizedBox(height: widget.ultraCompact ? 8 : 10),
            _buildConditionLanguageFoilRow(nftLocked: nftLocked),
            SizedBox(height: widget.ultraCompact ? 8 : 10),
            if (widget.ultraCompact)
              _InlineSellSwitchGrid(
                firstEdition: _firstEdition,
                sealed: _sealed,
                shippingAvailable: _shippingAvailable,
                reserveAvailable: _reserveAvailable,
                showReserve: canUseReserveToggle,
                showNft: ownedNfts.isNotEmpty,
                nftAvailable: _nftAvailable,
                signed: _signed,
                graded: _graded,
                onFirstEditionChanged: nftLocked
                    ? null
                    : (value) => setState(() => _firstEdition = value),
                onSealedChanged: nftLocked
                    ? null
                    : (value) => setState(() => _sealed = value),
                onShippingChanged: nftLocked
                    ? null
                    : (value) => setState(() => _shippingAvailable = value),
                onReserveChanged: (value) =>
                    setState(() => _reserveAvailable = value),
                onNftChanged: (value) => _setNftAvailable(value, ownedNfts),
                onSignedChanged: nftLocked
                    ? null
                    : (value) => setState(() => _signed = value),
                onGradedChanged: nftLocked
                    ? null
                    : (value) => setState(() => _graded = value),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InlineSellSwitch(
                    label: '1st Ed.',
                    value: _firstEdition,
                    onChanged: (value) => setState(() => _firstEdition = value),
                    enabled: !nftLocked,
                  ),
                  _InlineSellSwitch(
                    label: 'Sealed',
                    value: _sealed,
                    onChanged: (value) => setState(() => _sealed = value),
                    enabled: !nftLocked,
                  ),
                  _InlineSellSwitch(
                    label: 'Graded',
                    value: _graded,
                    onChanged: (value) => setState(() => _graded = value),
                    enabled: !nftLocked,
                  ),
                  _InlineSellSwitch(
                    label: 'Signed',
                    value: _signed,
                    onChanged: (value) => setState(() => _signed = value),
                    enabled: !nftLocked,
                  ),
                  _InlineSellSwitch(
                    label: 'Shipping',
                    value: _shippingAvailable,
                    onChanged: (value) =>
                        setState(() => _shippingAvailable = value),
                    enabled: !nftLocked,
                  ),
                  if (canUseReserveToggle)
                    _InlineSellSwitch(
                      label: 'Reserve',
                      value: _reserveAvailable,
                      onChanged: (value) =>
                          setState(() => _reserveAvailable = value),
                    ),
                  if (ownedNfts.isNotEmpty)
                    _InlineSellSwitch(
                      label: 'NFT',
                      value: _nftAvailable,
                      onChanged: (value) => _setNftAvailable(value, ownedNfts),
                    ),
                ],
              ),
            if (selectedOwnedNft != null) ...[
              const SizedBox(height: 8),
              Text(
                'NFT metadata locked from your collection. Quantity is limited to 1 for this NFT.',
                style: TextStyle(
                  color: const Color(0xFFBAE6FD),
                  fontSize: widget.ultraCompact ? 11 : 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (_graded) ...[
              const SizedBox(height: 10),
              if (compact)
                Column(
                  children: [
                    _buildGradingCompanyField(),
                    const SizedBox(height: 10),
                    _buildGradeField(),
                    const SizedBox(height: 10),
                    _buildCertificationField(),
                  ],
                )
              else ...[
                Row(
                  children: [
                    Expanded(child: _buildGradingCompanyField()),
                    const SizedBox(width: 10),
                    SizedBox(width: 150, child: _buildGradeField()),
                  ],
                ),
                const SizedBox(height: 10),
                _buildCertificationField(),
              ],
            ],
            SizedBox(height: widget.ultraCompact ? 8 : 10),
            _buildSellerCommentField(compact: widget.ultraCompact),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPriceField() {
    return TextField(
      controller: _priceController,
      focusNode: _priceFocusNode,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFFFACC15),
      onChanged: (_) {
        if (!_priceWasEdited) {
          setState(() => _priceWasEdited = true);
        }
      },
      decoration: InputDecoration(
        labelText: 'Price',
        floatingLabelBehavior: _priceHintText == null
            ? FloatingLabelBehavior.auto
            : FloatingLabelBehavior.always,
        hintText: _priceHintText,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildPriceCurrencySelector() {
    return DropdownButtonFormField<String>(
      initialValue: _priceCurrency,
      isExpanded: true,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      dropdownColor: const Color(0xFF111936),
      decoration: const InputDecoration(
        labelText: 'Currency',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: OutlineInputBorder(),
      ),
      items: _listingPriceCurrencies
          .map(
            (value) => DropdownMenuItem(
              value: value,
              child: Text(value),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() => _priceCurrency = value ?? _priceCurrency);
        _schedulePriceQuoteWarmup();
      },
    );
  }

  Widget _buildQuantityField() {
    return TextField(
      controller: _quantityController,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFFFACC15),
      enabled: !_nftAvailable,
      decoration: const InputDecoration(
        labelText: 'Qty',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildPrimaryListingRow({
    required String? sellerUid,
    required String sellerName,
    required bool compact,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final quantityWidth = widget.ultraCompact
            ? 72.0
            : compact
                ? 86.0
                : 150.0;
        final buttonWidth = widget.ultraCompact ? 94.0 : 132.0;
        final button = _buildListButton(
          sellerUid: sellerUid,
          sellerName: sellerName,
          compact: widget.ultraCompact,
        );
        if (constraints.maxWidth < 360) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildPriceField()),
                  const SizedBox(width: 8),
                  SizedBox(width: 88, child: _buildPriceCurrencySelector()),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(width: quantityWidth, child: _buildQuantityField()),
                  const SizedBox(width: 8),
                  Expanded(child: button),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: _buildPriceField()),
            SizedBox(width: widget.ultraCompact ? 8 : 10),
            SizedBox(
              width: widget.ultraCompact ? 82 : 92,
              child: _buildPriceCurrencySelector(),
            ),
            SizedBox(width: widget.ultraCompact ? 8 : 10),
            SizedBox(width: quantityWidth, child: _buildQuantityField()),
            SizedBox(width: widget.ultraCompact ? 8 : 10),
            SizedBox(width: buttonWidth, child: button),
          ],
        );
      },
    );
  }

  Widget _buildConditionLanguageFoilRow({required bool nftLocked}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            Expanded(child: _buildConditionField(enabled: !nftLocked)),
            const SizedBox(width: 8),
            Expanded(child: _buildLanguageField(enabled: !nftLocked)),
            const SizedBox(width: 8),
            Expanded(child: _buildFoilStateField(enabled: !nftLocked)),
          ],
        );
      },
    );
  }

  Widget _buildListButton({
    required String? sellerUid,
    required String sellerName,
    required bool compact,
  }) {
    return FilledButton.icon(
      onPressed: sellerUid == null || _isSaving
          ? null
          : () => _saveListing(
                sellerUid: sellerUid,
                sellerName: sellerName,
              ),
      icon: _isSaving
          ? SizedBox(
              width: compact ? 14 : 16,
              height: compact ? 14 : 16,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.sell_outlined, size: compact ? 16 : 18),
      label: Text(compact ? 'List' : 'List card'),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFFACC15),
        foregroundColor: const Color(0xFF111827),
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
      ),
    );
  }

  Widget _buildConditionField({bool enabled = true}) {
    return DropdownButtonFormField<String>(
      initialValue: _condition,
      isExpanded: true,
      style: const TextStyle(color: Colors.white),
      dropdownColor: const Color(0xFF111936),
      decoration: const InputDecoration(
        labelText: 'Condition',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(),
      ),
      items: const ['NM', 'SP', 'MP', 'PL', 'Poor']
          .map(
            (value) => DropdownMenuItem(
              value: value,
              child: Text(_conditionMoodLabel(value)),
            ),
          )
          .toList(),
      onChanged: enabled
          ? (value) => setState(() => _condition = value ?? _condition)
          : null,
    );
  }

  Widget _buildLanguageField({bool enabled = true}) {
    return DropdownButtonFormField<String>(
      initialValue: _language,
      isExpanded: true,
      style: const TextStyle(color: Colors.white),
      dropdownColor: const Color(0xFF111936),
      decoration: const InputDecoration(
        labelText: 'Language',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(),
      ),
      items: _listingLanguageCodes
          .map(
            (value) => DropdownMenuItem(
              value: value,
              child: Text(_listingLanguageLabel(value)),
            ),
          )
          .toList(),
      onChanged: enabled
          ? (value) => setState(() => _language = value ?? _language)
          : null,
    );
  }

  Widget _buildFoilStateField({bool enabled = true}) {
    return DropdownButtonFormField<String>(
      initialValue: _foilState,
      isExpanded: true,
      style: const TextStyle(color: Colors.white),
      dropdownColor: const Color(0xFF111936),
      decoration: const InputDecoration(
        labelText: 'Foil',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(),
      ),
      items: _foilStateOptions
          .map(
            (value) => DropdownMenuItem(
              value: value,
              child: Text(_foilStateLabel(value)),
            ),
          )
          .toList(),
      onChanged: enabled
          ? (value) => setState(() => _foilState = value ?? _foilState)
          : null,
    );
  }

  Widget _buildGradingCompanyField() {
    return TextField(
      controller: _gradingCompanyController,
      style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFFFACC15),
      decoration: const InputDecoration(
        labelText: 'Grading company',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildGradeField() {
    return TextField(
      controller: _gradeController,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFFFACC15),
      decoration: const InputDecoration(
        labelText: 'Grade',
        hintText: '10',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildCertificationField() {
    return TextField(
      controller: _certificationIdController,
      style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFFFACC15),
      decoration: const InputDecoration(
        labelText: 'Certification ID',
        hintText: 'e.g. 12345678',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildSellerCommentField({bool compact = false}) {
    return SizedBox(
      height: compact ? 78 : 74,
      child: TextField(
        controller: _sellerCommentController,
        maxLines: compact ? 3 : 2,
        maxLength: 180,
        style: const TextStyle(color: Colors.white),
        cursorColor: const Color(0xFFFACC15),
        decoration: const InputDecoration(
          labelText: 'Seller comment',
          hintText: 'Optional: whitening, scratches, print lines...',
          border: OutlineInputBorder(),
          counterText: '',
        ),
      ),
    );
  }

  Future<void> _saveListing({
    required String sellerUid,
    required String sellerName,
  }) async {
    final priceText = _priceController.text.trim();
    final usesSuggestedPrice =
        priceText.isEmpty && !_priceWasEdited && _priceCurrency == 'PKN';
    final price =
        usesSuggestedPrice ? _suggestedPricePkn : double.tryParse(priceText);
    final quantity = int.tryParse(_quantityController.text.trim());
    if (price == null || price <= 0 || quantity == null || quantity <= 0) {
      setState(() => _error = 'Enter a valid price and quantity.');
      return;
    }
    if (_nftAvailable) {
      final ownedNfts = _ownedNftsForCard(
        widget.card,
        ref.read(userCardCollectionProvider).valueOrNull,
      );
      final selectedNft = _selectedOwnedNft(ownedNfts);
      if (selectedNft == null) {
        setState(() => _error = 'You need to own this card as an NFT first.');
        return;
      }
      _applyOwnedNftToForm(selectedNft);
    }
    if (_graded &&
        (_gradingCompanyController.text.trim().isEmpty ||
            _gradeController.text.trim().isEmpty ||
            _certificationIdController.text.trim().isEmpty)) {
      setState(
          () => _error = 'Enter grading company, grade and certification ID.');
      return;
    }
    final canUseReserveToggle =
        _canUseReserveListingToggle(ref.read(userProfileProvider).valueOrNull);
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      _cancelPriceQuoteWarmup(clearQuote: false);
      final pricePkn = usesSuggestedPrice ? price : await _priceToPkn(price);
      final listing = CardListing.draft(
        card: widget.card,
        sellerUid: sellerUid,
        sellerName: sellerName,
        sellerCountry: 'EU',
        sellerReputationLabel: 'New seller',
        condition: _condition,
        language: _language,
        pricePkn: pricePkn,
        quantityAvailable: _nftAvailable ? 1 : quantity.clamp(1, 99),
        signed: _signed,
        reverse: _foilState == 'reverse',
        firstEdition: _firstEdition,
        foilState: _foilState,
        variantState: _variantStateController.text.trim(),
        sealed: _sealed,
        graded: _graded,
        gradingCompany: _graded ? _gradingCompanyController.text.trim() : null,
        grade: _graded ? _gradeController.text.trim() : null,
        certificationId:
            _graded ? _certificationIdController.text.trim() : null,
        shippingAvailable: _shippingAvailable,
        reserveAvailable: canUseReserveToggle && _reserveAvailable,
        nftAvailable: _nftAvailable,
        sellerComment: _sellerCommentController.text.trim(),
        source: _nftAvailable ? 'pokoin_user_nft' : 'pokoin_user_listing',
        sourceListingId:
            _nftAvailable ? (_selectedNftCollectionItemId ?? '') : '',
      );
      final created =
          await ref.read(cardListingServiceProvider).createListing(listing);
      if (mounted) {
        _upsertVisibleListing(ref, widget.card.id, created);
        _quantityController.text = '1';
        _cancelPriceQuoteWarmup(clearQuote: true);
        setState(() {
          _isSaving = false;
          _error = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Listing created.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _isSaving = false;
        });
      }
    }
  }

  Future<double> _priceToPkn(double amount) async {
    final quote = _warmedPriceQuote;
    if (quote != null &&
        quote.matches(amount: amount, currency: _priceCurrency)) {
      return quote.pricePkn;
    }
    return _listingPriceToPkn(
      ref,
      amount: amount,
      currency: _priceCurrency,
    );
  }

  Future<void> _loadFallbackPriceIfNeeded() async {
    if (widget.initialPricePkn != null ||
        _appliedFallbackPrice ||
        _suggestedPricePkn != null ||
        _priceWasEdited ||
        _nftAvailable ||
        _priceController.text.trim().isNotEmpty ||
        widget.card.id.trim().isEmpty) {
      return;
    }
    final token = ++_fallbackPriceToken;
    try {
      final suggestedPrice = await CardService()
          .getCardTraderSuggestedListingPrice(widget.card.id);
      if (!mounted || token != _fallbackPriceToken) {
        return;
      }
      final price = suggestedPrice?.pricePkn;
      if (price == null ||
          price <= 0 ||
          _priceWasEdited ||
          _priceController.text.isNotEmpty) {
        return;
      }
      setState(() {
        _setSuggestedPrice(price);
        _appliedFallbackPrice = true;
      });
    } catch (_) {}
  }

  void _schedulePriceQuoteWarmup() {
    final token = ++_priceQuoteToken;
    _priceQuoteTimer?.cancel();
    final amount = double.tryParse(_priceController.text.trim());
    if (_priceCurrency == 'PKN' || amount == null || amount <= 0) {
      _warmedPriceQuote = null;
      return;
    }
    final currency = _priceCurrency;
    _priceQuoteTimer = Timer(const Duration(milliseconds: 450), () async {
      try {
        final pricePkn = await _listingPriceToPkn(
          ref,
          amount: amount,
          currency: currency,
        );
        if (!mounted || token != _priceQuoteToken) {
          return;
        }
        _warmedPriceQuote = _ListingPriceQuote(
          amount: amount,
          currency: currency,
          pricePkn: pricePkn,
        );
      } catch (_) {
        if (!mounted || token != _priceQuoteToken) {
          return;
        }
        _warmedPriceQuote = null;
      }
    });
  }

  void _cancelPriceQuoteWarmup({required bool clearQuote}) {
    _priceQuoteTimer?.cancel();
    _priceQuoteTimer = null;
    _priceQuoteToken++;
    if (clearQuote) {
      _warmedPriceQuote = null;
    }
  }
}

class _ListingPriceQuote {
  const _ListingPriceQuote({
    required this.amount,
    required this.currency,
    required this.pricePkn,
  });

  final double amount;
  final String currency;
  final double pricePkn;

  bool matches({
    required double amount,
    required String currency,
  }) {
    return this.amount == amount && this.currency == currency;
  }
}

bool _canUseReserveListingToggle(AppUserProfile? profile) {
  final username = profile?.username.trim().toLowerCase() ?? '';
  final email = profile?.email.trim().toLowerCase() ?? '';
  return (profile?.hasReserveAccess ?? false) ||
      username == 'vitologiuseppe17' ||
      email == 'vitologiuseppe17@gmail.com' ||
      email == 'pokoinpos@gmail.com' ||
      (profile?.hasAdminAccess ?? false);
}

bool _isArtistDebugProfile(AppUserProfile? profile) {
  final username = profile?.username.trim().toLowerCase() ?? '';
  final email = profile?.email.trim().toLowerCase() ?? '';
  return username == 'vitologiuseppe17' ||
      email == 'vitologiuseppe17@gmail.com' ||
      email == 'pokoinpos@gmail.com' ||
      (profile?.hasAdminAccess ?? false);
}

String _debugProductTypeLabel(String productType) {
  switch (productType) {
    case 'booster_pack':
      return 'Booster pack';
    case 'booster_box':
      return 'Booster box';
    case 'elite_trainer_box':
      return 'Elite Trainer Box';
    case 'tin':
      return 'Tin';
    case 'collection_box':
      return 'Collection box';
    case 'deck':
      return 'Deck';
    case 'accessory':
      return 'Accessory';
    default:
      return 'Sealed product';
  }
}

class _DebugArtistOption {
  const _DebugArtistOption({
    required this.normalizedArtist,
    required this.artist,
    required this.knownCount,
  });

  factory _DebugArtistOption.fromJson(Map<dynamic, dynamic> json) {
    return _DebugArtistOption(
      normalizedArtist: '${json['normalizedArtist'] ?? ''}',
      artist: '${json['artist'] ?? ''}',
      knownCount:
          json['knownCount'] is num ? (json['knownCount'] as num).toInt() : 0,
    );
  }

  final String normalizedArtist;
  final String artist;
  final int knownCount;

  ArtistSuggestion toSuggestion() {
    return ArtistSuggestion(
      name: artist,
      normalizedArtist: normalizedArtist,
      slug: '',
      knownCount: knownCount,
    );
  }
}

class _DebugMissingArtistSelector extends ConsumerStatefulWidget {
  const _DebugMissingArtistSelector({
    required this.card,
    required this.onSaved,
  });

  final PokemonCard card;
  final ValueChanged<String> onSaved;

  @override
  ConsumerState<_DebugMissingArtistSelector> createState() =>
      _DebugMissingArtistSelectorState();
}

class _DebugMissingArtistSelectorState
    extends ConsumerState<_DebugMissingArtistSelector> {
  final TextEditingController _artistSearchController = TextEditingController();
  List<_DebugArtistOption> _artists = const [];
  String _selected = '';
  String _selectedArtistName = '';
  bool _loading = false;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadArtists());
  }

  @override
  void didUpdateWidget(covariant _DebugMissingArtistSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id) {
      _artists = const [];
      _selected = '';
      _selectedArtistName = '';
      _error = '';
      _artistSearchController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadArtists());
    }
  }

  @override
  void dispose() {
    _artistSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    if (widget.card.artist.trim().isNotEmpty ||
        widget.card.itemKind == 'product' ||
        !_isArtistDebugProfile(profile)) {
      return const SizedBox.shrink();
    }
    final selectedValue =
        _artists.any((option) => option.normalizedArtist == _selected)
            ? _selected
            : _selected.isEmpty
                ? null
                : _selected;
    final hasSelectedDropdownItem =
        _artists.any((option) => option.normalizedArtist == selectedValue);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x6658C7FA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Debug: missing artist',
            style: TextStyle(
              color: Color(0xFFBAE6FD),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const LinearProgressIndicator(minHeight: 3)
          else ...[
            ArtistSuggestionField(
              controller: _artistSearchController,
              enabled: !_saving,
              fillColor: const Color(0xFF0B1024),
              borderRadius: 12,
              fallbackSuggestions:
                  _artists.map((option) => option.toSuggestion()).toList(),
              onChanged: (value) => setState(() {
                if (value.trim() != _selectedArtistName.trim()) {
                  _selected = '';
                  _selectedArtistName = '';
                }
              }),
              onCleared: () => setState(() {
                _selected = '';
                _selectedArtistName = '';
              }),
              onSelected: (artist) => setState(() {
                _selected = artist.normalizedArtist;
                _selectedArtistName = artist.name;
                _setArtistSearchText(artist.name);
              }),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('debug-missing-artist-$selectedValue'),
              initialValue: selectedValue,
              isExpanded: true,
              dropdownColor: const Color(0xFF111936),
              decoration: const InputDecoration(
                labelText: 'Select artist',
                border: OutlineInputBorder(),
              ),
              items: [
                if (selectedValue != null && !hasSelectedDropdownItem)
                  DropdownMenuItem(
                    value: selectedValue,
                    child: Text(
                      _selectedArtistName.isEmpty
                          ? selectedValue
                          : _selectedArtistName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                for (final option in _artists)
                  DropdownMenuItem(
                    value: option.normalizedArtist,
                    child: Text(
                      option.knownCount > 0
                          ? '${option.artist} (${option.knownCount})'
                          : option.artist,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                        _selected = value ?? '';
                        _selectedArtistName =
                            _artistNameForSelection(_selected);
                        _setArtistSearchText(_selectedArtistName);
                      }),
            ),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_error, style: const TextStyle(color: Color(0xFFFCA5A5))),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _loading || _saving ? null : _loadArtists,
                icon: const Icon(Icons.refresh),
                label: const Text('Reload'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: selectedValue == null || _saving
                    ? null
                    : _saveSelectedArtist,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Save artist'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _loadArtists() async {
    if (!mounted || widget.card.artist.trim().isNotEmpty) return;
    if (!_isArtistDebugProfile(ref.read(userProfileProvider).valueOrNull)) {
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final apiClient = PokoinApiClient(
        auth: ref.read(pokoinApiAuthServiceProvider),
      );
      final response = await apiClient.get(
        Uri.base.resolve('/api/marketplace-debug-artists').replace(
          queryParameters: {'blueprintId': widget.card.id},
        ),
      );
      final decoded = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        throw StateError(decoded is Map ? '${decoded['error']}' : 'Failed');
      }
      final candidate = decoded is Map ? decoded['candidate'] : null;
      final artistRows = candidate is Map ? candidate['artists'] : null;
      final artists = (artistRows as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(_DebugArtistOption.fromJson)
          .where((option) =>
              option.normalizedArtist.isNotEmpty && option.artist.isNotEmpty)
          .toList(growable: false);
      setState(() {
        _artists = artists;
        _selected =
            artists.any((option) => option.normalizedArtist == _selected)
                ? _selected
                : '';
        _selectedArtistName =
            artists.any((option) => option.normalizedArtist == _selected)
                ? _artistNameForSelection(_selected)
                : _selectedArtistName;
      });
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveSelectedArtist() async {
    _DebugArtistOption? selected;
    for (final option in _artists) {
      if (option.normalizedArtist == _selected) {
        selected = option;
        break;
      }
    }
    final selectedArtistName = selected?.artist ?? _selectedArtistName.trim();
    if (_selected.trim().isEmpty || selectedArtistName.isEmpty) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final apiClient = PokoinApiClient(
        auth: ref.read(pokoinApiAuthServiceProvider),
      );
      final response = await apiClient.postJson(
        Uri.base.resolve('/api/marketplace-debug-artists'),
        body: {
          'action': 'select_artist',
          'blueprintId': widget.card.id,
          'normalizedArtist': _selected,
          'allowAnyArtist': true,
        },
      );
      final decoded = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        throw StateError(decoded is Map ? '${decoded['error']}' : 'Failed');
      }
      widget.onSaved(selectedArtistName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved artist $selectedArtistName')),
        );
      }
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _artistNameForSelection(String normalizedArtist) {
    for (final option in _artists) {
      if (option.normalizedArtist == normalizedArtist) {
        return option.artist;
      }
    }
    return '';
  }

  void _setArtistSearchText(String artistName) {
    final text = artistName.trim();
    _artistSearchController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _DebugProductToggleButtons extends ConsumerStatefulWidget {
  const _DebugProductToggleButtons({
    required this.card,
    required this.onChanged,
  });

  final PokemonCard card;
  final void Function({
    required String itemKind,
    required String productType,
  }) onChanged;

  @override
  ConsumerState<_DebugProductToggleButtons> createState() =>
      _DebugProductToggleButtonsState();
}

class _DebugProductToggleButtonsState
    extends ConsumerState<_DebugProductToggleButtons> {
  bool _saving = false;
  String _error = '';

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    if (!_isArtistDebugProfile(profile)) {
      return const SizedBox.shrink();
    }
    final isProduct = widget.card.itemKind == 'product';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _DebugClassificationButton(
            label: 'Card',
            icon: Icons.style_outlined,
            selected: !isProduct,
            saving: _saving,
            onPressed: () => _classify(itemKind: 'single', productType: 'card'),
          ),
          _DebugClassificationButton(
            label: 'Product',
            icon: Icons.inventory_2_outlined,
            selected: isProduct,
            saving: _saving,
            onPressed: () => _classify(
              itemKind: 'product',
              productType: widget.card.productType == 'card'
                  ? 'sealed_product'
                  : widget.card.productType,
            ),
          ),
          if (_saving)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (_error.isNotEmpty)
            Text(_error, style: const TextStyle(color: Color(0xFFFCA5A5))),
        ],
      ),
    );
  }

  Future<void> _classify({
    required String itemKind,
    required String productType,
  }) async {
    final currentlyProduct = widget.card.itemKind == 'product';
    if ((itemKind == 'product') == currentlyProduct && !_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final apiClient = PokoinApiClient(
        auth: ref.read(pokoinApiAuthServiceProvider),
      );
      final response = await apiClient.postJson(
        Uri.base.resolve('/api/marketplace-debug-artists'),
        body: {
          'action':
              itemKind == 'product' ? 'classify_product' : 'classify_single',
          'blueprintId': widget.card.id,
          if (itemKind == 'product') 'productType': productType,
        },
      );
      final decoded = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        throw StateError(decoded is Map ? '${decoded['error']}' : 'Failed');
      }
      widget.onChanged(itemKind: itemKind, productType: productType);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              itemKind == 'product'
                  ? 'Marked as product'
                  : 'Marked as single card',
            ),
          ),
        );
      }
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _DebugClassificationButton extends StatelessWidget {
  const _DebugClassificationButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.saving,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: saving || selected ? null : onPressed,
      icon: Icon(icon, size: 16),
      label: Text(selected ? '$label ✓' : label),
      style: OutlinedButton.styleFrom(
        foregroundColor:
            selected ? const Color(0xFFFACC15) : const Color(0xFFBAE6FD),
        side: BorderSide(
          color: selected ? const Color(0xFFFACC15) : const Color(0x6658C7FA),
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _InlineSellSwitch extends StatelessWidget {
  const _InlineSellSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _InlineSellToggleButton(
      label: label,
      value: value,
      onTap: enabled ? () => onChanged(!value) : null,
    );
  }
}

class _InlineSellToggleButton extends StatelessWidget {
  const _InlineSellToggleButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final bool value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final background =
        value ? const Color(0xFFFACC15) : const Color(0xFF111936);
    final foreground = onTap == null
        ? const Color(0xFF64748B)
        : value
            ? const Color(0xFF111827)
            : Colors.white;
    final border =
        value ? const Color(0xFFFDE047) : Colors.white.withValues(alpha: 0.08);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
            boxShadow: value
                ? [
                    BoxShadow(
                      color: const Color(0xFFFACC15).withValues(alpha: 0.24),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineSellSwitchGrid extends StatelessWidget {
  const _InlineSellSwitchGrid({
    required this.firstEdition,
    required this.sealed,
    required this.shippingAvailable,
    required this.reserveAvailable,
    required this.showReserve,
    required this.showNft,
    required this.nftAvailable,
    required this.signed,
    required this.graded,
    required this.onFirstEditionChanged,
    required this.onSealedChanged,
    required this.onShippingChanged,
    required this.onReserveChanged,
    required this.onNftChanged,
    required this.onSignedChanged,
    required this.onGradedChanged,
  });

  final bool firstEdition;
  final bool sealed;
  final bool shippingAvailable;
  final bool reserveAvailable;
  final bool showReserve;
  final bool showNft;
  final bool nftAvailable;
  final bool signed;
  final bool graded;
  final ValueChanged<bool>? onFirstEditionChanged;
  final ValueChanged<bool>? onSealedChanged;
  final ValueChanged<bool>? onShippingChanged;
  final ValueChanged<bool> onReserveChanged;
  final ValueChanged<bool> onNftChanged;
  final ValueChanged<bool>? onSignedChanged;
  final ValueChanged<bool>? onGradedChanged;

  @override
  Widget build(BuildContext context) {
    Widget switchCell({
      required String label,
      required bool value,
      required ValueChanged<bool>? onChanged,
    }) {
      return _InlineSellToggleButton(
        label: label,
        value: value,
        onTap: onChanged == null ? null : () => onChanged(!value),
      );
    }

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        switchCell(
          label: '1st Ed.',
          value: firstEdition,
          onChanged: onFirstEditionChanged,
        ),
        switchCell(
          label: 'Sealed',
          value: sealed,
          onChanged: onSealedChanged,
        ),
        switchCell(
          label: 'Graded',
          value: graded,
          onChanged: onGradedChanged,
        ),
        switchCell(
          label: 'Signed',
          value: signed,
          onChanged: onSignedChanged,
        ),
        switchCell(
          label: 'Ship',
          value: shippingAvailable,
          onChanged: onShippingChanged,
        ),
        if (showReserve)
          switchCell(
            label: 'Reserve',
            value: reserveAvailable,
            onChanged: onReserveChanged,
          ),
        if (showNft)
          switchCell(
            label: 'NFT',
            value: nftAvailable,
            onChanged: onNftChanged,
          ),
      ],
    );
  }
}

String _formatInitialPrice(double price) {
  if (price == price.roundToDouble()) {
    return price.toStringAsFixed(0);
  }
  return price.toStringAsFixed(2);
}

ThemeData _listingDialogTheme(BuildContext context) {
  return Theme.of(context).copyWith(
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFFACC15),
      surface: Color(0xFF0B1024),
      onSurface: Colors.white,
    ),
    textTheme: Theme.of(context).textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
    inputDecorationTheme: InputDecorationTheme(
      labelStyle: const TextStyle(color: Color(0xFF93A4C8)),
      floatingLabelStyle: const TextStyle(color: Color(0xFFFACC15)),
      hintStyle: const TextStyle(color: Color(0xFF64748B)),
      filled: true,
      fillColor: const Color(0xFF111936),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFACC15)),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xFF111827)
            : const Color(0xFF94A3B8),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xFFFACC15)
            : const Color(0xFF1E2A4A),
      ),
    ),
  );
}

class _BestDealPanel extends ConsumerStatefulWidget {
  const _BestDealPanel({
    required this.card,
    required this.market,
    required this.isInCart,
    this.mobileGradient,
  });

  final PokemonCard card;
  final _CardMarketData market;
  final bool isInCart;
  final Gradient? mobileGradient;

  @override
  ConsumerState<_BestDealPanel> createState() => _BestDealPanelState();
}

class _BestDealPanelState extends ConsumerState<_BestDealPanel> {
  String? _selectedLanguage;
  String? _selectedCondition;

  @override
  void didUpdateWidget(covariant _BestDealPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id) {
      _selectedLanguage = null;
      _selectedCondition = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final listings = _availableBestDealListings(widget.market.listings);
    final selection = _bestDealSelection(listings);
    final selectedListing = selection.listing;
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final user = ref.watch(authStateProvider).valueOrNull;
    final cartState = ref.watch(cartProvider);
    final hasSilverAccess = profile?.hasSilverAccess == true;
    final compact = MediaQuery.sizeOf(context).width <= 960;
    if (compact) {
      return _MobileBestDealPanel(
        card: widget.card,
        market: widget.market,
        hasSilverAccess: hasSilverAccess,
        isSignedIn: user != null,
        isInCart: widget.isInCart,
        onUnlock: () => _unlockSilver(context, ref),
        gradient: widget.mobileGradient,
      );
    }

    final languageOptions =
        _bestDealLanguageOptions(listings, condition: _selectedCondition);
    final conditionOptions =
        _bestDealConditionOptions(listings, language: _selectedLanguage);
    final selectedInCart = selectedListing == null
        ? false
        : cartState.isListingInCart(selectedListing.id);
    final selectedPriceLabel =
        selectedListing == null ? '—' : formatPkn(selectedListing.pricePkn);
    final selectedSubLabel = selectedListing == null
        ? (listings.isEmpty
            ? 'No sellers yet. Be the first to list this card.'
            : 'No listing matches this selection.')
        : '~${_CardMarketData._usdLabel(selectedListing.pricePkn)}';

    return Column(
      children: [
        _Panel(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Best Deal',
                      style: TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (hasSilverAccess)
                    _ExternalMarketButtons(card: widget.card)
                  else
                    _SilverUnlockButton(
                      isSignedIn: user != null,
                      onUnlock: () => _unlockSilver(context, ref),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                selectedPriceLabel,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                selectedSubLabel,
                style: const TextStyle(color: Color(0xFF93A4C8)),
              ),
              const SizedBox(height: 16),
              _BestDealSelector(
                value: languageOptions.contains(selection.language)
                    ? selection.language
                    : null,
                hint: 'Select language',
                items: [
                  for (final language in languageOptions)
                    DropdownMenuItem(
                      value: language,
                      child: Text(_bestDealLanguageLabel(language)),
                    ),
                ],
                onChanged: listings.isEmpty
                    ? null
                    : (value) => _selectLanguage(listings, value),
              ),
              const SizedBox(height: 8),
              _BestDealSelector(
                value: conditionOptions.contains(selection.condition)
                    ? selection.condition
                    : null,
                hint: 'Select condition',
                items: [
                  for (final condition in conditionOptions)
                    DropdownMenuItem(
                      value: condition,
                      child: Text(_bestDealConditionLabel(condition)),
                    ),
                ],
                onChanged: listings.isEmpty
                    ? null
                    : (value) => _selectCondition(listings, value),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: selectedListing == null
                    ? null
                    : () {
                        if (selectedInCart) {
                          ref
                              .read(cartProvider.notifier)
                              .removeFromCart(selectedListing.id);
                        } else {
                          ref
                              .read(cartProvider.notifier)
                              .addListingToCart(widget.card, selectedListing);
                          ref.read(cardProvider.notifier).recordCardInteraction(
                                widget.card,
                                'cart_add',
                                source: 'detail_buy_box',
                              );
                        }
                      },
                icon: Icon(selectedInCart
                    ? Icons.remove_shopping_cart
                    : Icons.add_shopping_cart),
                label: Text(selectedInCart
                    ? 'Remove from cart'
                    : selectedListing == null
                        ? 'Unavailable'
                        : 'Add to cart'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: const Color(0xFFFACC15),
                  foregroundColor: const Color(0xFF111827),
                  disabledBackgroundColor: const Color(0xFF374151),
                  disabledForegroundColor: const Color(0xFFCBD5E1),
                ),
              ),
              const SizedBox(height: 12),
              _DexLine(label: 'Estimated total', value: selectedPriceLabel),
              const _DexLine(label: 'Network / escrow fee', value: '0.30%'),
              const _DexLine(label: 'Slippage guard', value: '1.00%'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _Panel(
          padding: EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('POKOIN CARD RESERVE',
                  style: TextStyle(
                      color: Color(0xFFFACC15),
                      fontWeight: FontWeight.w900,
                      fontSize: 20)),
              SizedBox(height: 8),
              Text(
                'Unified custody, seller aggregation and inspection-ready settlement for serious collectors.',
                style: TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _unlockSilver(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      final authPath =
          '/auth?from=${Uri.encodeComponent(_authReturnPath(widget.card))}';
      CardDetailRouteGuard.instance.markExplicitNavigation(authPath);
      context.go(authPath);
      return;
    }
    try {
      await ref.read(authServiceProvider).unlockSilver();
      ref.invalidate(userProfileProvider);
      ref.invalidate(pknBalanceProvider);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silver unlocked for 1 year.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  _BestDealSelection _bestDealSelection(List<CardListing> listings) {
    if (listings.isEmpty) {
      return const _BestDealSelection();
    }

    final defaultListing = _preferredDefaultBestDealListing(listings);
    final language = _selectedLanguage ??
        (defaultListing == null ? null : _listingLanguage(defaultListing));
    final condition = _selectedCondition ??
        (defaultListing == null ? null : _listingCondition(defaultListing));
    final listing = language == null && condition == null
        ? listings.first
        : _cheapestBestDealListing(
            listings,
            language: language,
            condition: condition,
          );

    return _BestDealSelection(
      listing: listing,
      language:
          language ?? (listing == null ? null : _listingLanguage(listing)),
      condition:
          condition ?? (listing == null ? null : _listingCondition(listing)),
    );
  }

  void _selectLanguage(List<CardListing> listings, String? value) {
    if (value == null) return;
    final language = _normalizeListingLanguage(value);
    final currentCondition = _selectedCondition;
    final hasCurrentCondition = _cheapestBestDealListing(
          listings,
          language: language,
          condition: currentCondition,
        ) !=
        null;
    final cheapestForLanguage =
        _cheapestBestDealListing(listings, language: language);

    setState(() {
      _selectedLanguage = language;
      _selectedCondition = hasCurrentCondition
          ? currentCondition
          : cheapestForLanguage == null
              ? null
              : _listingCondition(cheapestForLanguage);
    });
  }

  void _selectCondition(List<CardListing> listings, String? value) {
    if (value == null) return;
    final condition = _normalizeListingCondition(value);
    final currentLanguage = _selectedLanguage;
    final hasCurrentLanguage = _cheapestBestDealListing(
          listings,
          language: currentLanguage,
          condition: condition,
        ) !=
        null;
    final cheapestForCondition =
        _cheapestBestDealListing(listings, condition: condition);

    setState(() {
      _selectedCondition = condition;
      _selectedLanguage = hasCurrentLanguage
          ? currentLanguage
          : cheapestForCondition == null
              ? null
              : _listingLanguage(cheapestForCondition);
    });
  }
}

class _BestDealSelection {
  const _BestDealSelection({
    this.listing,
    this.language,
    this.condition,
  });

  final CardListing? listing;
  final String? language;
  final String? condition;
}

class _BestDealSelector extends StatelessWidget {
  const _BestDealSelector({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  final String? value;
  final String hint;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(
            hint,
            style: const TextStyle(
              color: Color(0xFF93A4C8),
              fontWeight: FontWeight.w800,
            ),
          ),
          isExpanded: true,
          dropdownColor: const Color(0xFF111936),
          iconEnabledColor: const Color(0xFF93A4C8),
          iconDisabledColor: const Color(0xFF64748B),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

List<CardListing> _availableBestDealListings(List<CardListing> listings) {
  return listings
      .where((listing) => listing.isActive && listing.pricePkn > 0)
      .toList(growable: false);
}

CardListing? _cheapestBestDealListing(
  List<CardListing> listings, {
  String? language,
  String? condition,
}) {
  for (final listing in listings) {
    if (language != null && _listingLanguage(listing) != language) {
      continue;
    }
    if (condition != null && _listingCondition(listing) != condition) {
      continue;
    }
    return listing;
  }
  return null;
}

CardListing? _preferredDefaultBestDealListing(List<CardListing> listings) {
  return _cheapestBestDealListing(
        listings,
        language: 'EN',
        condition: 'NM',
      ) ??
      _cheapestBestDealListing(listings, condition: 'NM') ??
      _cheapestBestDealListing(listings, language: 'EN') ??
      (listings.isEmpty ? null : listings.first);
}

List<String> _bestDealLanguageOptions(
  List<CardListing> listings, {
  String? condition,
}) {
  final values = <String>{};
  for (final listing in listings) {
    if (condition != null && _listingCondition(listing) != condition) {
      continue;
    }
    values.add(_listingLanguage(listing));
  }
  return _sortListingCodes(values, _listingLanguageCodes);
}

List<String> _bestDealConditionOptions(
  List<CardListing> listings, {
  String? language,
}) {
  final values = <String>{};
  for (final listing in listings) {
    if (language != null && _listingLanguage(listing) != language) {
      continue;
    }
    values.add(_listingCondition(listing));
  }
  return _sortListingCodes(values, const ['NM', 'SP', 'MP', 'PL', 'Poor']);
}

List<String> _sortListingCodes(
    Set<String> values, List<String> preferredOrder) {
  final ordered = <String>[
    for (final value in preferredOrder)
      if (values.remove(value)) value,
  ];
  ordered.addAll(values.toList()..sort());
  return ordered;
}

String _listingLanguage(CardListing listing) {
  return _normalizeListingLanguage(listing.language);
}

String _listingCondition(CardListing listing) {
  return _normalizeListingCondition(listing.condition);
}

String _normalizeListingLanguage(String language) {
  final normalized = language.trim().toUpperCase();
  return normalized.isEmpty ? 'EN' : normalized;
}

String _normalizeListingCondition(String condition) {
  return listingMinimalConditionLabel(condition);
}

String _bestDealLanguageLabel(String language) {
  return '$language · ${_languageName(language)}';
}

String _bestDealConditionLabel(String condition) {
  return '$condition · ${_conditionName(condition)}';
}

class _MobileBestDealPanel extends StatelessWidget {
  const _MobileBestDealPanel({
    required this.card,
    required this.market,
    required this.hasSilverAccess,
    required this.isSignedIn,
    required this.isInCart,
    required this.onUnlock,
    required this.gradient,
  });

  final PokemonCard card;
  final _CardMarketData market;
  final bool hasSilverAccess;
  final bool isSignedIn;
  final bool isInCart;
  final VoidCallback onUnlock;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      gradient: gradient,
      child: Row(
        children: [
          Expanded(
            child: Text(
              market.hasListings ? formatPkn(market.bestDeal) : '-- PKN',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFFACC15),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (hasSilverAccess)
            _ExternalMarketButtons(
              card: card,
              compact: true,
              cartListing: market.bestListing,
              cartListingInCart: isInCart,
            )
          else
            _SilverUnlockButton(
              isSignedIn: isSignedIn,
              onUnlock: onUnlock,
              compact: true,
            ),
        ],
      ),
    );
  }
}

class _SilverUnlockButton extends StatelessWidget {
  const _SilverUnlockButton({
    required this.isSignedIn,
    required this.onUnlock,
    this.compact = false,
  });

  final bool isSignedIn;
  final VoidCallback onUnlock;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isSignedIn
          ? 'Unlock CT and CM links for 20 PKN/year'
          : 'Sign in to unlock CT and CM links',
      child: FilledButton(
        onPressed: onUnlock,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE5E7EB),
          foregroundColor: const Color(0xFF111827),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 13,
            vertical: compact ? 8 : 10,
          ),
          minimumSize: Size(0, compact ? 34 : 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Text(
          compact
              ? (isSignedIn ? 'Unlock' : 'Sign in')
              : (isSignedIn ? 'Unlock for 20 PKN' : 'Sign in to unlock'),
        ),
      ),
    );
  }
}

class _ExternalMarketButtons extends ConsumerStatefulWidget {
  const _ExternalMarketButtons({
    required this.card,
    this.compact = false,
    this.cartListing,
    this.cartListingInCart = false,
  });

  final PokemonCard card;
  final bool compact;
  final CardListing? cartListing;
  final bool cartListingInCart;

  @override
  ConsumerState<_ExternalMarketButtons> createState() =>
      _ExternalMarketButtonsState();
}

class _ExternalMarketButtonsState
    extends ConsumerState<_ExternalMarketButtons> {
  bool _openingCardmarket = false;

  Future<void> _openExternalMarket(String market) async {
    final id = Uri.encodeComponent(widget.card.id);
    final uri = Uri.base.resolve('/api/$market-redirect?id=$id');
    if (market != 'cardmarket') {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      return;
    }

    setState(() => _openingCardmarket = true);
    try {
      final resolveUri =
          Uri.base.resolve('/api/cardmarket-redirect?id=$id&format=json');
      final client = http.Client();
      late final int statusCode;
      late final String? location;
      late final String body;
      try {
        final request = http.Request('GET', resolveUri)
          ..followRedirects = false;
        final response = await client.send(request).timeout(
              const Duration(seconds: 8),
            );
        statusCode = response.statusCode;
        location = response.headers['location'];
        body = await response.stream.bytesToString();
      } finally {
        client.close();
      }

      if (statusCode >= 300 && statusCode < 400 && location != null) {
        await launchUrl(
          Uri.parse(location),
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank',
        );
        return;
      }

      if (statusCode == 200) {
        final targetUrl = _cardmarketResolvedUrl(body);
        if (targetUrl != null) {
          await launchUrl(
            Uri.parse(targetUrl),
            mode: LaunchMode.externalApplication,
            webOnlyWindowName: '_blank',
          );
          return;
        }
      }

      if (statusCode == 409 && mounted) {
        final message = _cardmarketErrorMessage(body);
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF0B1024),
            surfaceTintColor: Colors.transparent,
            title: const Text(
              'Cardmarket link unavailable',
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              message,
              style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFACC15),
                  foregroundColor: const Color(0xFF111827),
                ),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cardmarket link failed: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _openingCardmarket = false);
      }
    }
  }

  Future<void> _openVintedSearch() async {
    final uri = Uri.https('www.vinted.it', '/catalog', {
      'search_text': vintedSearchQueryForCard(widget.card),
    });
    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  }

  void _toggleBestListingCart() {
    final listing = widget.cartListing;
    if (listing == null) {
      return;
    }
    if (widget.cartListingInCart) {
      ref.read(cartProvider.notifier).removeFromCart(listing.id);
      return;
    }
    ref.read(cartProvider.notifier).addListingToCart(widget.card, listing);
    ref.read(cardProvider.notifier).recordCardInteraction(
          widget.card,
          'cart_add',
          source: 'detail_compact_best_deal',
        );
  }

  String _cardmarketErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } catch (_) {
      // Fall through to the generic message.
    }
    return 'Cardmarket does not have a supported product page for this card.';
  }

  String? _cardmarketResolvedUrl(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['url'] is String) {
        return decoded['url'] as String;
      }
    } catch (_) {
      // Fall through to null.
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final spacing = widget.compact ? 5.0 : 8.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.compact) ...[
          _ExternalMarketPill(
            label: '',
            icon: widget.cartListingInCart
                ? Icons.remove_shopping_cart
                : Icons.add_shopping_cart,
            tooltip: widget.cartListing == null
                ? 'No active listing to add'
                : widget.cartListingInCart
                    ? 'Remove best listing from cart'
                    : 'Add best listing to cart',
            enabled: widget.cartListing != null,
            foregroundColor: const Color(0xFF111827),
            borderColor: const Color(0xFFFACC15).withValues(alpha: 0.72),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFE066), Color(0xFFFACC15)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            compact: widget.compact,
            onPressed: _toggleBestListingCart,
          ),
          SizedBox(width: spacing),
        ],
        _ExternalMarketPill(
          label: 'CT',
          enabled: widget.card.id.trim().isNotEmpty,
          foregroundColor: Colors.white,
          borderColor: const Color(0xFF1ED6FF).withValues(alpha: 0.55),
          gradient: const LinearGradient(
            colors: [Color(0xFF00C2FF), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          compact: widget.compact,
          onPressed: () => _openExternalMarket('cardtrader'),
        ),
        SizedBox(width: spacing),
        _ExternalMarketPill(
          label: 'CM',
          enabled: widget.card.id.trim().isNotEmpty && !_openingCardmarket,
          foregroundColor: Colors.white,
          borderColor: const Color(0xFF60A5FA).withValues(alpha: 0.72),
          gradient: const LinearGradient(
            colors: [Color(0xFF2563EB), Color(0xFF002395)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          compact: widget.compact,
          onPressed: () => _openExternalMarket('cardmarket'),
        ),
        SizedBox(width: spacing),
        _ExternalMarketPill(
          label: 'VT',
          enabled: widget.card.name.trim().isNotEmpty,
          foregroundColor: Colors.white,
          borderColor: const Color(0xFF14532D).withValues(alpha: 0.78),
          gradient: const LinearGradient(
            colors: [Color(0xFF166534), Color(0xFF052E16)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          compact: widget.compact,
          onPressed: _openVintedSearch,
        ),
      ],
    );
  }
}

class _ExternalMarketPill extends StatelessWidget {
  const _ExternalMarketPill({
    required this.label,
    required this.enabled,
    required this.foregroundColor,
    required this.borderColor,
    required this.onPressed,
    this.compact = false,
    this.gradient,
    this.icon,
    this.tooltip,
  });

  final String label;
  final String? tooltip;
  final bool enabled;
  final Color foregroundColor;
  final Color borderColor;
  final Gradient? gradient;
  final VoidCallback onPressed;
  final bool compact;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final disabledColor = Colors.white.withValues(alpha: 0.08);
    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: enabled ? null : disabledColor,
        gradient: enabled ? gradient : null,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: enabled ? borderColor : Colors.white.withValues(alpha: 0.12),
        ),
        boxShadow: enabled && gradient != null
            ? [
                BoxShadow(
                  color: const Color(0xFF00C2FF).withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          foregroundColor:
              enabled ? foregroundColor : Colors.white.withValues(alpha: 0.45),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 9 : 13,
            vertical: compact ? 7 : 9,
          ),
          minimumSize: Size(compact ? 38 : 54, compact ? 34 : 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
          shape: const StadiumBorder(),
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
        ),
        child: icon == null ? Text(label) : Icon(icon, size: compact ? 17 : 19),
      ),
    );
    final message = tooltip;
    if (message == null || message.isEmpty) {
      return pill;
    }
    return Tooltip(message: message, child: pill);
  }
}

class _MarketStatsGrid extends StatelessWidget {
  const _MarketStatsGrid({required this.market});

  final _CardMarketData market;

  @override
  Widget build(BuildContext context) {
    final stats = [
      (
        'Market cap',
        market.hasListings ? formatPkn(market.marketCap) : '—',
        market.hasListings ? '+4.2%' : 'empty'
      ),
      (
        'Volume 24h',
        market.hasListings ? formatPkn(market.volume24h) : '—',
        market.hasListings ? '+18.6%' : 'empty'
      ),
      ('Listings', '${market.listings.length}', 'live'),
      ('Liquidity', market.hasListings ? market.liquidityLabel : '—', 'depth'),
      ('Best bid', market.hasListings ? formatPkn(market.bestBid) : '—', 'PKN'),
      (
        'Best ask',
        market.hasListings ? formatPkn(market.bestDeal) : '—',
        market.spreadLabel
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 1000
            ? 6
            : constraints.maxWidth > 720
                ? 3
                : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stats.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: columns > 3 ? 1.65 : 2.1,
          ),
          itemBuilder: (context, index) {
            final stat = stats[index];
            return _StatCard(label: stat.$1, value: stat.$2, sub: stat.$3);
          },
        );
      },
    );
  }
}

class _ListingsTerminal extends StatefulWidget {
  const _ListingsTerminal({
    required this.card,
    required this.market,
    required this.isLoading,
    required this.isFavorite,
    required this.onSell,
    required this.onWishlist,
    required this.pageScrollController,
  });

  final PokemonCard card;
  final _CardMarketData market;
  final bool isLoading;
  final bool isFavorite;
  final VoidCallback onSell;
  final VoidCallback onWishlist;
  final ScrollController pageScrollController;

  @override
  State<_ListingsTerminal> createState() => _ListingsTerminalState();
}

class _ListingsTerminalState extends State<_ListingsTerminal> {
  static const int _listingBatchSize = 20;
  static const double _listingLoadMoreThreshold = 1200;
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();
  final Set<String> _conditions = <String>{};
  final Set<String> _languages = <String>{};
  bool _filtersExpanded = false;
  bool _shippingOnly = false;
  bool _nftOnly = false;
  bool _gradedOnly = false;
  bool _signedOnly = false;
  bool _reverseOnly = false;
  String _sort = 'price_asc';
  int _visibleListingCount = _listingBatchSize;
  String _listingBatchKey = '';

  @override
  void initState() {
    super.initState();
    widget.pageScrollController.addListener(_handlePageScroll);
  }

  @override
  void didUpdateWidget(covariant _ListingsTerminal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageScrollController != widget.pageScrollController) {
      oldWidget.pageScrollController.removeListener(_handlePageScroll);
      widget.pageScrollController.addListener(_handlePageScroll);
    }
  }

  @override
  void dispose() {
    widget.pageScrollController.removeListener(_handlePageScroll);
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    final visibleListings = _filteredListings();
    final batchKey = _batchKeyForListings(visibleListings);
    if (batchKey != _listingBatchKey) {
      _listingBatchKey = batchKey;
      _visibleListingCount = _listingBatchSize;
    }
    final batchedListings =
        visibleListings.take(_visibleListingCount).toList(growable: false);
    final filters = _ListingFilters(
      market: widget.market,
      minPriceController: _minPriceController,
      maxPriceController: _maxPriceController,
      selectedConditions: _conditions,
      selectedLanguages: _languages,
      shippingOnly: _shippingOnly,
      nftOnly: _nftOnly,
      gradedOnly: _gradedOnly,
      signedOnly: _signedOnly,
      reverseOnly: _reverseOnly,
      onPriceChanged: () => setState(() {}),
      onToggleCondition: (value) => setState(() {
        _toggle(_conditions, value);
      }),
      onToggleLanguage: (value) => setState(() {
        _toggle(_languages, value);
      }),
      onShippingOnlyChanged: (value) => setState(() => _shippingOnly = value),
      onNftOnlyChanged: (value) => setState(() => _nftOnly = value),
      onGradedOnlyChanged: (value) => setState(() => _gradedOnly = value),
      onSignedOnlyChanged: (value) => setState(() => _signedOnly = value),
      onReverseOnlyChanged: (value) => setState(() => _reverseOnly = value),
      onClear: _clearFilters,
      collapsed: !wide && !_filtersExpanded,
      onToggleCollapsed: wide
          ? null
          : () => setState(() => _filtersExpanded = !_filtersExpanded),
    );
    final table = _ListingsTable(
      card: widget.card,
      market: widget.market,
      listings: batchedListings,
      totalListings: visibleListings.length,
      isLoading: widget.isLoading,
      sort: _sort,
      onSortChanged: (value) => setState(() => _sort = value),
      isFavorite: widget.isFavorite,
      onSell: widget.onSell,
      onWishlist: widget.onWishlist,
      onClearFilters: _clearFilters,
      hasMoreListings: batchedListings.length < visibleListings.length,
      onLoadMore: _showNextListingsBatch,
    );

    if (!wide) {
      return Column(
        children: [
          filters,
          const SizedBox(height: 14),
          const _PokoinConditionsPlaceholder(),
          const SizedBox(height: 14),
          table,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 240,
          child: Column(
            children: [
              filters,
              const SizedBox(height: 14),
              const _PokoinConditionsPlaceholder(),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: table),
      ],
    );
  }

  List<CardListing> _filteredListings() {
    final minPrice = double.tryParse(_minPriceController.text.trim());
    final maxPrice = double.tryParse(_maxPriceController.text.trim());
    final filtered = widget.market.listings.where((listing) {
      if (minPrice != null && listing.pricePkn < minPrice) {
        return false;
      }
      if (maxPrice != null && listing.pricePkn > maxPrice) {
        return false;
      }
      if (_conditions.isNotEmpty &&
          !_conditions.contains(
            listingMinimalConditionLabel(listing.condition),
          )) {
        return false;
      }
      if (_languages.isNotEmpty && !_languages.contains(listing.language)) {
        return false;
      }
      if (_shippingOnly && !listing.shippingAvailable) {
        return false;
      }
      if (_nftOnly && !listing.nftAvailable) {
        return false;
      }
      if (_gradedOnly && !listing.graded) {
        return false;
      }
      if (_signedOnly && !listing.signed) {
        return false;
      }
      if (_reverseOnly && !listing.reverse) {
        return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      switch (_sort) {
        case 'price_desc':
          return b.pricePkn.compareTo(a.pricePkn);
        case 'qty_desc':
          return b.quantityAvailable.compareTo(a.quantityAvailable);
        case 'seller':
          return a.sellerName.compareTo(b.sellerName);
        case 'price_asc':
        default:
          return a.pricePkn.compareTo(b.pricePkn);
      }
    });
    return filtered;
  }

  void _clearFilters() {
    setState(() {
      _minPriceController.clear();
      _maxPriceController.clear();
      _conditions.clear();
      _languages.clear();
      _shippingOnly = false;
      _nftOnly = false;
      _gradedOnly = false;
      _signedOnly = false;
      _reverseOnly = false;
      _sort = 'price_asc';
    });
  }

  void _toggle(Set<String> values, String value) {
    if (!values.add(value)) {
      values.remove(value);
    }
  }

  String _batchKeyForListings(List<CardListing> listings) {
    return [
      _sort,
      _minPriceController.text.trim(),
      _maxPriceController.text.trim(),
      _conditions.join(','),
      _languages.join(','),
      _shippingOnly,
      _nftOnly,
      _gradedOnly,
      _signedOnly,
      _reverseOnly,
      listings.length,
      if (listings.isNotEmpty) listings.first.id,
      if (listings.isNotEmpty) listings.last.id,
    ].join('|');
  }

  void _showNextListingsBatch() {
    final visibleListings = _filteredListings();
    setState(() {
      _listingBatchKey = _batchKeyForListings(visibleListings);
      _visibleListingCount = math.min(
        _visibleListingCount + _listingBatchSize,
        visibleListings.length,
      );
    });
  }

  void _handlePageScroll() {
    if (!widget.pageScrollController.hasClients) {
      return;
    }
    final position = widget.pageScrollController.position;
    if (position.extentAfter > _listingLoadMoreThreshold) {
      return;
    }
    final visibleListings = _filteredListings();
    if (_visibleListingCount >= visibleListings.length) {
      return;
    }
    setState(() {
      _listingBatchKey = _batchKeyForListings(visibleListings);
      _visibleListingCount = math.min(
        _visibleListingCount + _listingBatchSize,
        visibleListings.length,
      );
    });
  }
}

class _ListingFilters extends StatelessWidget {
  const _ListingFilters({
    required this.market,
    required this.minPriceController,
    required this.maxPriceController,
    required this.selectedConditions,
    required this.selectedLanguages,
    required this.shippingOnly,
    required this.nftOnly,
    required this.gradedOnly,
    required this.signedOnly,
    required this.reverseOnly,
    required this.onPriceChanged,
    required this.onToggleCondition,
    required this.onToggleLanguage,
    required this.onShippingOnlyChanged,
    required this.onNftOnlyChanged,
    required this.onGradedOnlyChanged,
    required this.onSignedOnlyChanged,
    required this.onReverseOnlyChanged,
    required this.onClear,
    this.collapsed = false,
    this.onToggleCollapsed,
  });

  final _CardMarketData market;
  final TextEditingController minPriceController;
  final TextEditingController maxPriceController;
  final Set<String> selectedConditions;
  final Set<String> selectedLanguages;
  final bool shippingOnly;
  final bool nftOnly;
  final bool gradedOnly;
  final bool signedOnly;
  final bool reverseOnly;
  final VoidCallback onPriceChanged;
  final ValueChanged<String> onToggleCondition;
  final ValueChanged<String> onToggleLanguage;
  final ValueChanged<bool> onShippingOnlyChanged;
  final ValueChanged<bool> onNftOnlyChanged;
  final ValueChanged<bool> onGradedOnlyChanged;
  final ValueChanged<bool> onSignedOnlyChanged;
  final ValueChanged<bool> onReverseOnlyChanged;
  final VoidCallback onClear;
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final toggle = onToggleCollapsed;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (toggle == null) ...[
          const Text(
            'Filters',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
        ],
        _FilterGroup(title: 'Price (PKN)', children: [
          _PriceInput(
            controller: minPriceController,
            hint: 'min',
            onChanged: onPriceChanged,
          ),
          const SizedBox(height: 8),
          _PriceInput(
            controller: maxPriceController,
            hint: 'max',
            onChanged: onPriceChanged,
          ),
        ]),
        const SizedBox(height: 16),
        _FilterGroup(
          title: 'Condition',
          children: [
            _FilterCheck(
              text: 'Near Mint',
              checked: selectedConditions.contains('NM'),
              onChanged: () => onToggleCondition('NM'),
            ),
            _FilterCheck(
              text: 'Slightly Played',
              checked: selectedConditions.contains('SP'),
              onChanged: () => onToggleCondition('SP'),
            ),
            _FilterCheck(
              text: 'Moderately Played',
              checked: selectedConditions.contains('MP'),
              onChanged: () => onToggleCondition('MP'),
            ),
            _FilterCheck(
              text: 'Played',
              checked: selectedConditions.contains('PL'),
              onChanged: () => onToggleCondition('PL'),
            ),
            _FilterCheck(
              text: 'Poor',
              checked: selectedConditions.contains('Poor'),
              onChanged: () => onToggleCondition('Poor'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _FilterGroup(
          title: 'Language',
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final language in _listingLanguageCodes)
                  _FilterCheck(
                    text: _listingLanguageLabel(language),
                    checked: selectedLanguages.contains(language),
                    onChanged: () => onToggleLanguage(language),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _FilterGroup(
          title: 'Extra',
          children: [
            _FilterCheck(
              text: 'Reverse holo',
              checked: reverseOnly,
              onChanged: () => onReverseOnlyChanged(!reverseOnly),
            ),
            _FilterCheck(
              text: 'Signed',
              checked: signedOnly,
              onChanged: () => onSignedOnlyChanged(!signedOnly),
            ),
            _FilterCheck(
              text: 'Graded',
              checked: gradedOnly,
              onChanged: () => onGradedOnlyChanged(!gradedOnly),
            ),
            _FilterCheck(
              text: 'Shipping',
              checked: shippingOnly,
              onChanged: () => onShippingOnlyChanged(!shippingOnly),
            ),
            _FilterCheck(
              text: 'NFT available',
              checked: nftOnly,
              onChanged: () => onNftOnlyChanged(!nftOnly),
            ),
          ],
        ),
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: onClear,
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          child: const Text('Clear filters'),
        ),
      ],
    );

    if (toggle != null) {
      return _Panel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Filters',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      collapsed ? 'Show' : 'Hide',
                      style: const TextStyle(
                        color: Color(0xFF93A4C8),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      collapsed
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      color: const Color(0xFFFACC15),
                    ),
                  ],
                ),
              ),
            ),
            if (!collapsed) ...[
              const SizedBox(height: 16),
              body,
            ],
          ],
        ),
      );
    }

    return _Panel(
      padding: const EdgeInsets.all(16),
      child: body,
    );
  }
}

class _PokoinConditionsPlaceholder extends StatelessWidget {
  const _PokoinConditionsPlaceholder();

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('NM', '😄 Near Mint', 'Clean front/back, minimal edge wear.'),
      ('SP', '🙂 Slightly Played', 'Light whitening or small handling marks.'),
      ('MP', '😐 Moderately Played', 'Visible wear, still display-worthy.'),
      ('PL', '🙁 Played', 'Heavy wear, creases or clear surface marks.'),
      ('Poor', '😭 Poor', 'Damaged or binder-only copy.'),
    ];

    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pokoin conditions',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Use these grades to compare seller listings consistently.',
            style: TextStyle(color: Color(0xFF93A4C8), height: 1.35),
          ),
          const SizedBox(height: 12),
          for (final row in rows) ...[
            _ConditionInfoRow(
              code: row.$1,
              label: row.$2,
              description: row.$3,
            ),
            if (row != rows.last) const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }
}

class _ConditionInfoRow extends StatelessWidget {
  const _ConditionInfoRow({
    required this.code,
    required this.label,
    required this.description,
  });

  final String code;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final color = _conditionColor(code);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: color.withValues(alpha: 0.42),
            ),
          ),
          child: Text(
            code,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0xFF93A4C8),
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Color _conditionColor(String code) {
  return listingConditionColor(code);
}

class _ListingsTable extends StatelessWidget {
  const _ListingsTable({
    required this.card,
    required this.market,
    required this.listings,
    required this.totalListings,
    required this.isLoading,
    required this.sort,
    required this.onSortChanged,
    required this.isFavorite,
    required this.onSell,
    required this.onWishlist,
    required this.onClearFilters,
    required this.hasMoreListings,
    required this.onLoadMore,
  });

  final PokemonCard card;
  final _CardMarketData market;
  final List<CardListing> listings;
  final int totalListings;
  final bool isLoading;
  final String sort;
  final ValueChanged<String> onSortChanged;
  final bool isFavorite;
  final VoidCallback onSell;
  final VoidCallback onWishlist;
  final VoidCallback onClearFilters;
  final bool hasMoreListings;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 640;
    return _Panel(
      clip: true,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    totalListings == 0
                        ? 'No sellers yet'
                        : '${listings.length} of $totalListings seller listings',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                DropdownButton<String>(
                  value: sort,
                  dropdownColor: const Color(0xFF111936),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                        value: 'price_asc', child: Text('Lowest price')),
                    DropdownMenuItem(
                        value: 'price_desc', child: Text('Highest price')),
                    DropdownMenuItem(
                        value: 'qty_desc', child: Text('Most quantity')),
                    DropdownMenuItem(value: 'seller', child: Text('Seller')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      onSortChanged(value);
                    }
                  },
                ),
              ],
            ),
          ),
          _ListingsHeader(compact: compact),
          _ListingTableBody(
            card: card,
            market: market,
            listings: listings,
            compact: compact,
            isLoading: isLoading,
            isFavorite: isFavorite,
            onSell: onSell,
            onWishlist: onWishlist,
            onClearFilters: onClearFilters,
            hasMoreListings: hasMoreListings,
            onLoadMore: onLoadMore,
          ),
        ],
      ),
    );
  }
}

class _ListingTableBody extends StatelessWidget {
  const _ListingTableBody({
    required this.card,
    required this.market,
    required this.listings,
    required this.compact,
    required this.isLoading,
    required this.isFavorite,
    required this.onSell,
    required this.onWishlist,
    required this.onClearFilters,
    required this.hasMoreListings,
    required this.onLoadMore,
  });

  final PokemonCard card;
  final _CardMarketData market;
  final List<CardListing> listings;
  final bool compact;
  final bool isLoading;
  final bool isFavorite;
  final VoidCallback onSell;
  final VoidCallback onWishlist;
  final VoidCallback onClearFilters;
  final bool hasMoreListings;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(color: Color(0xFFFACC15)),
      );
    }
    if (market.listings.isEmpty) {
      return _NoListingsState(
        isFavorite: isFavorite,
        onSell: onSell,
        onWishlist: onWishlist,
      );
    }
    if (listings.isEmpty) {
      return _NoFilteredListingsState(onClear: onClearFilters);
    }

    return Column(
      children: [
        for (final listing in listings)
          _FadeInListingRow(
            key: ValueKey('listing-row-${listing.id}'),
            child: _ListingRow(
              card: card,
              listing: listing,
              compact: compact,
            ),
          ),
        if (hasMoreListings)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: TextButton.icon(
              onPressed: onLoadMore,
              icon: const Icon(Icons.expand_more),
              label: const Text('Show more listings'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFACC15),
              ),
            ),
          ),
      ],
    );
  }
}

class _FadeInListingRow extends StatefulWidget {
  const _FadeInListingRow({super.key, required this.child});

  final Widget child;

  @override
  State<_FadeInListingRow> createState() => _FadeInListingRowState();
}

class _FadeInListingRowState extends State<_FadeInListingRow> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _visible = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.03),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _ListingsHeader extends StatelessWidget {
  const _ListingsHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final header = Container(
      width: compact ? 520 : null,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 16,
        vertical: 12,
      ),
      color: const Color(0xFF111B3F),
      child: Row(
        children: compact
            ? const [
                SizedBox(width: 112, child: _HeaderText('Seller')),
                SizedBox(width: 100, child: _HeaderText('Product')),
                SizedBox(width: 96, child: _HeaderText('Price / Qty')),
                SizedBox(width: 132, child: _HeaderText('Actions')),
              ]
            : const [
                Expanded(flex: 3, child: _HeaderText('Seller')),
                Expanded(flex: 3, child: _HeaderText('Product')),
                Expanded(flex: 2, child: _HeaderText('Price')),
                Expanded(child: _HeaderText('Qty')),
                SizedBox(width: 146, child: _HeaderText('Actions')),
              ],
      ),
    );
    if (!compact) {
      return header;
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: header,
    );
  }
}

class _ListingRow extends ConsumerWidget {
  const _ListingRow({
    required this.card,
    required this.listing,
    required this.compact,
  });

  final PokemonCard card;
  final CardListing listing;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCart = ref.watch(cartProvider).isListingInCart(listing.id);
    final currentUser = ref.watch(authStateProvider).valueOrNull;
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final isOwner = currentUser != null && currentUser.uid == listing.sellerUid;
    final showCardTraderLink = isOwner && listing.isCardTraderLinked;
    final sellerComment = _listingDisplaySellerComment(listing.sellerComment);
    final sellerName = _displaySellerNameForListing(
      listing: listing,
      isOwner: isOwner,
      profile: profile,
      fallbackUserName: currentUser?.displayName ?? currentUser?.email,
    );
    if (compact) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _CompactListingRow(
          card: card,
          listing: listing,
          sellerName: sellerName,
          inCart: inCart,
          isOwner: isOwner,
          showCardTraderLink: showCardTraderLink,
          sellerComment: sellerComment,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(listingCountryFlag(listing.sellerCountry),
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        sellerName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (showCardTraderLink) ...[
                      const SizedBox(width: 5),
                      const _CardTraderLinkedIcon(),
                    ],
                    if (sellerComment.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      _SellerCommentIcon(comment: sellerComment),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text('★ ${listing.sellerReputationLabel}',
                    style: const TextStyle(
                        color: Color(0xFF93A4C8), fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                ListingConditionChip(condition: listing.condition),
                ListingMetaChip(text: _listingLanguageLabel(listing.language)),
                if (listing.reverse)
                  ListingMetaChip(text: listingFoilBadgeLabel('reverse')),
                if (listing.reserveAvailable)
                  const ListingMetaChip(text: 'Reserve'),
                if (listing.nftAvailable && !listing.isCardTraderLinked)
                  const ListingMetaChip(text: 'NFT'),
                if (listing.sealed) const ListingMetaChip(text: 'Sealed'),
                if (listing.signed) const ListingMetaChip(text: 'Signed'),
                if (listing.graded)
                  ListingMetaChip(
                    text: [
                      listing.gradingCompany ?? 'Graded',
                      if ((listing.grade ?? '').isNotEmpty) listing.grade!,
                      if ((listing.certificationId ?? '').isNotEmpty)
                        '#${listing.certificationId!}',
                    ].join(' '),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatPkn(listing.pricePkn),
              style: const TextStyle(
                  color: Color(0xFFFACC15), fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: Text(
              '1 of ${listing.quantityAvailable}',
              style: const TextStyle(color: Color(0xFFB8C4E6)),
            ),
          ),
          SizedBox(
            width: 146,
            child: isOwner
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: _OwnerListingActions(card: card, listing: listing),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _DarkCircleButton(
                        onPressed: () {
                          if (inCart) {
                            ref
                                .read(cartProvider.notifier)
                                .removeFromCart(listing.id);
                          } else {
                            ref
                                .read(cartProvider.notifier)
                                .addListingToCart(card, listing);
                            ref
                                .read(cardProvider.notifier)
                                .recordCardInteraction(
                                  card,
                                  'cart_add',
                                  source: 'listing_row',
                                );
                          }
                        },
                        icon: Icon(
                          inCart
                              ? Icons.remove_shopping_cart
                              : Icons.shopping_cart_outlined,
                        ),
                        tooltip: inCart ? 'Remove from cart' : 'Add to cart',
                        foregroundColor: inCart
                            ? const Color(0xFFFACC15)
                            : const Color(0xFFCBD5E1),
                        backgroundColor: inCart
                            ? const Color(0xFFFACC15).withValues(alpha: 0.14)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      _NftListingButton(
                        enabled: listing.nftAvailable,
                        onPressed: () => _addListingAsNft(ref, card, listing),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

String _displaySellerNameForListing({
  required CardListing listing,
  required bool isOwner,
  required AppUserProfile? profile,
  required String? fallbackUserName,
}) {
  if (listing.reserveAvailable || listing.isCardTraderLinked) {
    return listing.sellerName.trim().isEmpty
        ? 'pknreserve'
        : listing.sellerName;
  }
  if (isOwner) {
    final profileName = profile?.displayName.trim() ?? '';
    if (profileName.isNotEmpty) return profileName;
    final username = profile?.username.trim() ?? '';
    if (username.isNotEmpty) return username;
    final userName = fallbackUserName?.trim() ?? '';
    if (userName.isNotEmpty) return userName;
  }
  return listing.sellerName.trim().isEmpty
      ? 'Pokoin seller'
      : listing.sellerName;
}

String _listingDisplaySellerComment(String comment) {
  final cleanComment = comment.trim();
  if (cleanComment.isEmpty) return '';
  final normalized = cleanComment
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const hiddenExactLabels = <String>{
    'cardtrader zero',
    'ct zero',
    'zero',
    '1 day ready',
    'one day ready',
    'cardtrader 1 day ready',
  };
  if (hiddenExactLabels.contains(normalized)) return '';
  final hiddenPromos = <RegExp>[
    RegExp(r'\bcheck (?:out )?my (?:store|shop|profile|page)\b'),
    RegExp(r'\bvisit my (?:store|shop|profile|page)\b'),
    RegExp(r'\bsee my (?:store|shop|profile|page|other cards|listings)\b'),
    RegExp(r'\bmore (?:in|on) (?:the )?(?:store|shop|profile|page)\b'),
    RegExp(r'\bmore (?:cards|items|listings|products) available\b'),
  ];
  return hiddenPromos.any((pattern) => pattern.hasMatch(normalized))
      ? ''
      : cleanComment;
}

void _addListingAsNft(WidgetRef ref, PokemonCard card, CardListing listing) {
  ref.read(cartProvider.notifier).addListingToCart(
        card,
        listing,
        fulfillmentMode: CartFulfillmentMode.nftOnly,
      );
  ref.read(cardProvider.notifier).recordCardInteraction(
        card,
        'cart_add',
        source: 'listing_row_nft',
      );
}

class _CompactListingRow extends ConsumerWidget {
  const _CompactListingRow({
    required this.card,
    required this.listing,
    required this.sellerName,
    required this.inCart,
    required this.isOwner,
    required this.showCardTraderLink,
    required this.sellerComment,
  });

  final PokemonCard card;
  final CardListing listing;
  final String sellerName;
  final bool inCart;
  final bool isOwner;
  final bool showCardTraderLink;
  final String sellerComment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 520,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        sellerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF67E8F9),
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (showCardTraderLink) ...[
                      const SizedBox(width: 4),
                      const _CardTraderLinkedIcon(size: 14),
                    ],
                    if (sellerComment.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      _SellerCommentIcon(
                        comment: sellerComment,
                        size: 14,
                        compact: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${listingCountryFlag(listing.sellerCountry)} ★ ${listing.sellerReputationLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF93A4C8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                ListingConditionChip(condition: listing.condition),
                ListingMetaChip(text: _listingLanguageLabel(listing.language)),
                if (listing.reverse)
                  ListingMetaChip(
                    text: listingFoilBadgeLabel('reverse', compact: true),
                  ),
                if (listing.reserveAvailable)
                  const ListingMetaChip(text: 'RES'),
                if (listing.nftAvailable && !listing.isCardTraderLinked)
                  const ListingMetaChip(text: 'NFT'),
                if (listing.sealed) const ListingMetaChip(text: 'SEALED'),
                if (listing.signed) const ListingMetaChip(text: 'SIG'),
                if (listing.graded) const ListingMetaChip(text: 'GRD'),
              ],
            ),
          ),
          SizedBox(
            width: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatPkn(listing.pricePkn),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${listing.quantityAvailable} avail.',
                  style: const TextStyle(
                    color: Color(0xFF93A4C8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 132,
            child: Align(
              alignment: Alignment.centerRight,
              child: isOwner
                  ? _OwnerListingActions(
                      card: card,
                      listing: listing,
                      compact: true,
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _DarkCircleButton(
                          onPressed: () {
                            if (inCart) {
                              ref
                                  .read(cartProvider.notifier)
                                  .removeFromCart(listing.id);
                            } else {
                              ref
                                  .read(cartProvider.notifier)
                                  .addListingToCart(card, listing);
                              ref
                                  .read(cardProvider.notifier)
                                  .recordCardInteraction(
                                    card,
                                    'cart_add',
                                    source: 'listing_row_mobile',
                                  );
                            }
                          },
                          icon: Icon(
                            inCart
                                ? Icons.remove_shopping_cart
                                : Icons.shopping_cart_outlined,
                          ),
                          tooltip: inCart ? 'Remove from cart' : 'Add to cart',
                          foregroundColor: inCart
                              ? const Color(0xFFFACC15)
                              : const Color(0xFFCBD5E1),
                          backgroundColor: inCart
                              ? const Color(0xFFFACC15).withValues(alpha: 0.14)
                              : const Color(0xFFBAE6FD).withValues(alpha: 0.36),
                        ),
                        const SizedBox(width: 8),
                        _NftListingButton(
                          enabled: listing.nftAvailable,
                          compact: true,
                          onPressed: () => _addListingAsNft(ref, card, listing),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnerListingActions extends ConsumerWidget {
  const _OwnerListingActions({
    required this.card,
    required this.listing,
    this.compact = false,
  });

  final PokemonCard card;
  final CardListing listing;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (compact) {
      return _DarkCircleButton(
        onPressed: () => _showOwnerMenu(context, ref),
        icon: const Icon(Icons.more_horiz),
        tooltip: 'Manage listing',
        foregroundColor: const Color(0xFFFACC15),
        backgroundColor: const Color(0xFFFACC15).withValues(alpha: 0.14),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _OwnerActionButton(
          label: 'Edit',
          icon: Icons.edit_outlined,
          onPressed: () => _openEditor(context, ref),
        ),
        const SizedBox(width: 8),
        _OwnerActionButton(
          label: 'Clone',
          icon: Icons.copy_all_outlined,
          onPressed: () => _openCloneEditor(context, ref),
        ),
        const SizedBox(width: 8),
        _DarkCircleButton(
          onPressed: () => _removeNow(context, ref),
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Remove listing',
          foregroundColor: const Color(0xFFFCA5A5),
          backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.12),
        ),
      ],
    );
  }

  Future<void> _showOwnerMenu(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF0B1024),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.edit_outlined, color: Color(0xFFFACC15)),
              title: const Text('Edit listing',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.copy_all_outlined, color: Color(0xFFFACC15)),
              title: const Text('Clone listing',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'clone'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Color(0xFFFCA5A5)),
              title: const Text('Remove listing',
                  style: TextStyle(color: Color(0xFFFCA5A5))),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'edit':
        _openEditor(context, ref);
        break;
      case 'clone':
        _openCloneEditor(context, ref);
        break;
      case 'remove':
        _removeNow(context, ref);
        break;
    }
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    await showDialog(
      context: context,
      builder: (context) => _EditListingDialog(card: card, listing: listing),
    );
  }

  Future<void> _openCloneEditor(BuildContext context, WidgetRef ref) async {
    await showDialog(
      context: context,
      builder: (context) => _EditListingDialog(
        card: card,
        listing: listing.copyWith(id: '', status: 'active'),
        mode: _ListingEditorMode.clone,
      ),
    );
  }

  Future<void> _removeNow(BuildContext context, WidgetRef ref) async {
    _removeVisibleListing(ref, card.id, listing);
    try {
      await ref.read(cardListingServiceProvider).removeListing(
            listingId: listing.id,
            sellerUid: listing.sellerUid,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Listing removed.')),
        );
      }
    } catch (error) {
      _upsertVisibleListing(ref, card.id, listing);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Remove failed: $error')),
        );
      }
    }
  }
}

class _NftListingButton extends StatelessWidget {
  const _NftListingButton({
    required this.enabled,
    required this.onPressed,
    this.compact = false,
  });

  final bool enabled;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _DarkCircleButton(
        onPressed: enabled ? onPressed : null,
        icon: const Icon(Icons.hexagon_outlined),
        tooltip: enabled ? 'Add as NFT express' : 'NFT unavailable',
        foregroundColor:
            enabled ? const Color(0xFFFACC15) : const Color(0xFF64748B),
        backgroundColor:
            enabled ? const Color(0xFFFACC15).withValues(alpha: 0.12) : null,
      );
    }
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: const Icon(Icons.hexagon_outlined, size: 15),
        label: const Text('NFT'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFFACC15),
          disabledForegroundColor: const Color(0xFF64748B),
          side: BorderSide(
            color: (enabled ? const Color(0xFFFACC15) : const Color(0xFF64748B))
                .withValues(alpha: 0.55),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _CardTraderLinkedIcon extends StatelessWidget {
  const _CardTraderLinkedIcon({this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Linked with CardTrader',
      child: Icon(
        Icons.link,
        size: size,
        color: const Color(0xFFFACC15),
      ),
    );
  }
}

class _OwnerActionButton extends StatelessWidget {
  const _OwnerActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFFACC15),
          side: BorderSide(
            color: const Color(0xFFFACC15).withValues(alpha: 0.45),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _NoListingsState extends StatelessWidget {
  const _NoListingsState({
    required this.isFavorite,
    required this.onSell,
    required this.onWishlist,
  });

  final bool isFavorite;
  final VoidCallback onSell;
  final VoidCallback onWishlist;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.priority_high,
                color: Color(0xFFCBD5E1), size: 42),
          ),
          const SizedBox(height: 14),
          const Text(
            'No items found',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'No seller has listed this card yet. Add it to your wishlist or be the first seller.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF93A4C8), height: 1.45),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: onWishlist,
                icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                label: Text(isFavorite ? 'In watchlist' : 'Add to watchlist'),
              ),
              FilledButton.icon(
                onPressed: onSell,
                icon: const Icon(Icons.sell_outlined),
                label: const Text('Sell this card'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFACC15),
                  foregroundColor: const Color(0xFF111827),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoFilteredListingsState extends StatelessWidget {
  const _NoFilteredListingsState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 38),
      child: Column(
        children: [
          const Icon(Icons.filter_alt_off_outlined,
              color: Color(0xFFFACC15), size: 44),
          const SizedBox(height: 12),
          const Text(
            'No listings match these filters',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try widening the price range, language, condition or extras.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF93A4C8), height: 1.45),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.refresh),
            label: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }
}

enum _ListingEditorMode { edit, clone }

class _EditListingDialog extends ConsumerStatefulWidget {
  const _EditListingDialog({
    required this.card,
    required this.listing,
    this.mode = _ListingEditorMode.edit,
  });

  final PokemonCard card;
  final CardListing listing;
  final _ListingEditorMode mode;

  @override
  ConsumerState<_EditListingDialog> createState() => _EditListingDialogState();
}

class _EditListingDialogState extends ConsumerState<_EditListingDialog> {
  late final TextEditingController _priceController;
  late final TextEditingController _quantityController;
  late final TextEditingController _gradingCompanyController;
  late final TextEditingController _gradeController;
  late final TextEditingController _certificationIdController;
  late final TextEditingController _sellerCommentController;
  late String _condition;
  late String _language;
  late bool _firstEdition;
  late String _foilState;
  late final TextEditingController _variantStateController;
  late bool _sealed;
  late bool _signed;
  late bool _graded;
  late bool _shippingAvailable;
  late bool _reserveAvailable;
  late bool _nftAvailable;
  bool _isSaving = false;
  String? _error;

  bool get _isClone => widget.mode == _ListingEditorMode.clone;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(
        text: _formatInitialPrice(widget.listing.pricePkn));
    _quantityController =
        TextEditingController(text: '${widget.listing.quantityAvailable}');
    _gradingCompanyController =
        TextEditingController(text: widget.listing.gradingCompany ?? 'PSA');
    _gradeController = TextEditingController(text: widget.listing.grade ?? '');
    _certificationIdController =
        TextEditingController(text: widget.listing.certificationId ?? '');
    _sellerCommentController =
        TextEditingController(text: widget.listing.sellerComment);
    _condition = widget.listing.condition;
    _language = widget.listing.language;
    _firstEdition = widget.listing.firstEdition;
    _foilState =
        widget.listing.foilState == 'standard' && widget.listing.reverse
            ? 'reverse'
            : widget.listing.foilState;
    _variantStateController =
        TextEditingController(text: widget.listing.variantState);
    _sealed = widget.listing.sealed;
    _signed = widget.listing.signed;
    _graded = widget.listing.graded;
    _shippingAvailable = widget.listing.shippingAvailable;
    _reserveAvailable = widget.listing.reserveAvailable;
    _nftAvailable = widget.listing.nftAvailable;
  }

  @override
  void dispose() {
    _priceController.dispose();
    _quantityController.dispose();
    _gradingCompanyController.dispose();
    _gradeController.dispose();
    _certificationIdController.dispose();
    _sellerCommentController.dispose();
    _variantStateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canUseReserveToggle =
        _canUseReserveListingToggle(ref.watch(userProfileProvider).valueOrNull);
    return Theme(
      data: _listingDialogTheme(context),
      child: AlertDialog(
        backgroundColor: const Color(0xFF0B1024),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: Text(_isClone ? '🧬 Clone listing' : 'Edit listing',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.card.name,
                  style: const TextStyle(
                    color: Color(0xFFB8C4E6),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: const Color(0xFFFACC15),
                  decoration: const InputDecoration(
                    labelText: 'Price in PKN',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: const Color(0xFFFACC15),
                  decoration: const InputDecoration(
                    labelText: 'Quantity available',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _condition,
                        style: const TextStyle(color: Colors.white),
                        dropdownColor: const Color(0xFF111936),
                        decoration: const InputDecoration(
                          labelText: 'Condition',
                          border: OutlineInputBorder(),
                        ),
                        items: const ['NM', 'SP', 'MP', 'PL', 'Poor']
                            .map((value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_conditionMoodLabel(value)),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _condition = value ?? _condition),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _language,
                        style: const TextStyle(color: Colors.white),
                        dropdownColor: const Color(0xFF111936),
                        decoration: const InputDecoration(
                          labelText: 'Language',
                          border: OutlineInputBorder(),
                        ),
                        items: _listingLanguageCodes
                            .map((value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_listingLanguageLabel(value)),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _language = value ?? _language),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InlineSellSwitch(
                      label: '1st Ed.',
                      value: _firstEdition,
                      onChanged: (value) =>
                          setState(() => _firstEdition = value),
                    ),
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String>(
                        initialValue: _foilState,
                        style: const TextStyle(color: Colors.white),
                        dropdownColor: const Color(0xFF111936),
                        decoration: const InputDecoration(
                          labelText: 'Foil / holo state',
                          border: OutlineInputBorder(),
                        ),
                        items: _foilStateOptions
                            .map((value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_foilStateLabel(value)),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _foilState = value ?? _foilState),
                      ),
                    ),
                    _InlineSellSwitch(
                      label: 'Sealed',
                      value: _sealed,
                      onChanged: (value) => setState(() => _sealed = value),
                    ),
                    _InlineSellSwitch(
                      label: 'Graded',
                      value: _graded,
                      onChanged: (value) => setState(() => _graded = value),
                    ),
                    _InlineSellSwitch(
                      label: 'Signed',
                      value: _signed,
                      onChanged: (value) => setState(() => _signed = value),
                    ),
                    _InlineSellSwitch(
                      label: 'Shipping',
                      value: _shippingAvailable,
                      onChanged: (value) =>
                          setState(() => _shippingAvailable = value),
                    ),
                    if (canUseReserveToggle)
                      _InlineSellSwitch(
                        label: 'Reserve',
                        value: _reserveAvailable,
                        onChanged: (value) =>
                            setState(() => _reserveAvailable = value),
                      ),
                    _InlineSellSwitch(
                      label: 'NFT',
                      value: _nftAvailable,
                      onChanged: (value) =>
                          setState(() => _nftAvailable = value),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _variantStateController,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: const Color(0xFFFACC15),
                  decoration: const InputDecoration(
                    labelText: 'Variant notes',
                    hintText: 'Stamped, promo stamp, error print...',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_graded) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _gradingCompanyController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: const Color(0xFFFACC15),
                          decoration: const InputDecoration(
                            labelText: 'Grading company',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _gradeController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: const Color(0xFFFACC15),
                          decoration: const InputDecoration(
                            labelText: 'Grade',
                            hintText: '10',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _certificationIdController,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: const Color(0xFFFACC15),
                    decoration: const InputDecoration(
                      labelText: 'Certification ID',
                      hintText: 'e.g. 12345678',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  height: 86,
                  child: TextField(
                    controller: _sellerCommentController,
                    maxLines: 3,
                    maxLength: 500,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: const Color(0xFFFACC15),
                    decoration: const InputDecoration(
                      labelText: 'Seller comment',
                      hintText: 'Optional details about condition',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFF93A4C8)),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFACC15),
              foregroundColor: const Color(0xFF111827),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isClone ? 'Create clone' : 'Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final price = double.tryParse(_priceController.text.trim());
    final quantity = int.tryParse(_quantityController.text.trim());
    if (price == null || price <= 0 || quantity == null || quantity < 0) {
      setState(() => _error = 'Enter a valid price and quantity.');
      return;
    }
    if (_graded &&
        (_gradingCompanyController.text.trim().isEmpty ||
            _gradeController.text.trim().isEmpty ||
            _certificationIdController.text.trim().isEmpty)) {
      setState(
          () => _error = 'Enter grading company, grade and certification ID.');
      return;
    }
    final canUseReserveToggle =
        _canUseReserveListingToggle(ref.read(userProfileProvider).valueOrNull);
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final updated = widget.listing.copyWith(
        id: _isClone ? '' : widget.listing.id,
        condition: _condition,
        language: _language,
        pricePkn: price,
        quantityAvailable: quantity.clamp(0, 99),
        signed: _signed,
        reverse: _foilState == 'reverse',
        firstEdition: _firstEdition,
        foilState: _foilState,
        variantState: _variantStateController.text.trim(),
        sealed: _sealed,
        graded: _graded,
        gradingCompany: _graded ? _gradingCompanyController.text.trim() : '',
        grade: _graded ? _gradeController.text.trim() : '',
        certificationId: _graded ? _certificationIdController.text.trim() : '',
        shippingAvailable: _shippingAvailable,
        reserveAvailable: canUseReserveToggle && _reserveAvailable,
        nftAvailable: _nftAvailable,
        sellerComment: _sellerCommentController.text.trim(),
        status: quantity <= 0 ? 'paused' : 'active',
        cardName: widget.listing.cardName.trim().isEmpty
            ? widget.card.name
            : widget.listing.cardName,
        cardImageUrl: widget.listing.cardImageUrl.trim().isEmpty
            ? widget.card.imageUrl
            : widget.listing.cardImageUrl,
        setName: widget.listing.setName.trim().isEmpty
            ? widget.card.set
            : widget.listing.setName,
        collectorNumber: widget.listing.collectorNumber.trim().isEmpty
            ? widget.card.number
            : widget.listing.collectorNumber,
      );
      late final CardListing savedListing;
      if (_isClone) {
        savedListing =
            await ref.read(cardListingServiceProvider).createListing(updated);
      } else {
        savedListing =
            await ref.read(cardListingServiceProvider).updateListing(updated);
      }
      if (mounted) {
        _upsertVisibleListing(ref, widget.card.id, savedListing);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isClone ? 'Listing cloned.' : 'Listing updated.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _isSaving = false;
        });
      }
    }
  }
}

class _SellListingDialog extends ConsumerStatefulWidget {
  const _SellListingDialog({
    required this.card,
    required this.sellerUid,
    required this.sellerName,
    required this.initialPricePkn,
    required this.onSaved,
  });

  final PokemonCard card;
  final String sellerUid;
  final String sellerName;
  final double? initialPricePkn;
  final ValueChanged<CardListing> onSaved;

  @override
  ConsumerState<_SellListingDialog> createState() => _SellListingDialogState();
}

class _SellListingDialogState extends ConsumerState<_SellListingDialog> {
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _quantityController =
      TextEditingController(text: '1');
  final TextEditingController _gradingCompanyController =
      TextEditingController(text: 'PSA');
  final TextEditingController _gradeController = TextEditingController();
  final TextEditingController _certificationIdController =
      TextEditingController();
  final TextEditingController _sellerCommentController =
      TextEditingController();
  String _condition = 'NM';
  String _language = 'EN';
  String _foilState = 'standard';
  bool _sealed = false;
  bool _signed = false;
  bool _graded = false;
  bool _shippingAvailable = true;
  bool _reserveAvailable = false;
  bool _nftAvailable = false;
  String? _selectedNftCollectionItemId;
  bool _isSaving = false;
  String _priceCurrency = 'PKN';
  Timer? _priceQuoteTimer;
  int _priceQuoteToken = 0;
  _ListingPriceQuote? _warmedPriceQuote;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initialPrice = widget.initialPricePkn;
    _priceController.text =
        initialPrice == null ? '' : _formatInitialPrice(initialPrice);
    _priceController.addListener(_schedulePriceQuoteWarmup);
  }

  @override
  void dispose() {
    _priceQuoteTimer?.cancel();
    _priceController.removeListener(_schedulePriceQuoteWarmup);
    _priceController.dispose();
    _quantityController.dispose();
    _gradingCompanyController.dispose();
    _gradeController.dispose();
    _certificationIdController.dispose();
    _sellerCommentController.dispose();
    super.dispose();
  }

  List<UserCardCollectionItem> _ownedNftsForCard(
    PokemonCard card,
    List<UserCardCollectionItem>? items,
  ) {
    if (items == null || items.isEmpty) {
      return const [];
    }
    final cardId = card.id.trim();
    final signature = _collectionSignature(
      name: card.name,
      setName: card.set,
      number: card.number,
    );
    return items.where((item) {
      if (!item.isNft) return false;
      if (cardId.isNotEmpty && item.cardId.trim() == cardId) return true;
      if (signature.isEmpty) return false;
      return _collectionSignature(
            name: item.cardName,
            setName: item.setName,
            number: item.collectorNumber,
          ) ==
          signature;
    }).toList(growable: false);
  }

  UserCardCollectionItem? _selectedOwnedNft(List<UserCardCollectionItem> nfts) {
    if (nfts.isEmpty) {
      return null;
    }
    final selectedId = _selectedNftCollectionItemId;
    if (selectedId != null && selectedId.isNotEmpty) {
      for (final item in nfts) {
        if (item.id == selectedId) {
          return item;
        }
      }
    }
    return nfts.first;
  }

  void _applyOwnedNftToDialog(UserCardCollectionItem nft) {
    _selectedNftCollectionItemId = nft.id;
    _condition = _listingConditionFromCollectionItem(nft);
    _language = _listingLanguageFromCollectionItem(nft);
    _sealed = false;
    _graded = nft.graded;
    _foilState = _foilStateFromCollectionItem(nft);
    _shippingAvailable = nft.canRequestPhysicalShipping;
    _quantityController.text = '1';
    if (nft.graded) {
      _gradingCompanyController.text = _nonEmptyOrFallback(
          nft.gradingCompany, _gradingCompanyController.text);
      _gradeController.text = nft.grade ?? '';
      _certificationIdController.text = nft.certificationId ?? '';
    } else {
      _gradeController.clear();
      _certificationIdController.clear();
    }
    final comment = _nftSellerComment(nft);
    if (comment.isNotEmpty) {
      _sellerCommentController.text = comment;
    }
  }

  String _listingConditionFromCollectionItem(UserCardCollectionItem nft) {
    final value = nft.condition.trim();
    return const {'NM', 'SP', 'MP', 'PL', 'Poor'}.contains(value)
        ? value
        : 'NM';
  }

  String _listingLanguageFromCollectionItem(UserCardCollectionItem nft) {
    final value = nft.language.trim().toUpperCase();
    return _listingLanguageCodes.contains(value) ? value : 'EN';
  }

  String _foilStateFromCollectionItem(UserCardCollectionItem nft) {
    if (nft.reverse) return 'reverse';
    if (nft.holo) return 'holo';
    return 'standard';
  }

  String _nftSellerComment(UserCardCollectionItem nft) {
    final status =
        nft.nftStatus.trim().isEmpty ? 'owned' : nft.nftStatus.trim();
    return 'NFT metadata: $status';
  }

  String _nonEmptyOrFallback(String? value, String fallback) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  void _setDialogNftAvailable(
    bool value,
    List<UserCardCollectionItem> ownedNfts,
  ) {
    if (!value) {
      setState(() {
        _nftAvailable = false;
        _selectedNftCollectionItemId = null;
        _shippingAvailable = true;
        _quantityController.text = '1';
      });
      return;
    }
    final nft = _selectedOwnedNft(ownedNfts);
    if (nft == null) {
      return;
    }
    setState(() {
      _nftAvailable = true;
      _applyOwnedNftToDialog(nft);
      _cancelPriceQuoteWarmup(clearQuote: true);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canUseReserveToggle =
        _canUseReserveListingToggle(ref.watch(userProfileProvider).valueOrNull);
    final ownedNfts = _ownedNftsForCard(
      widget.card,
      ref.watch(userCardCollectionProvider).valueOrNull,
    );
    if (_nftAvailable && ownedNfts.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _nftAvailable = false;
          _selectedNftCollectionItemId = null;
        });
      });
    }
    final selectedOwnedNft =
        _nftAvailable ? _selectedOwnedNft(ownedNfts) : null;
    final nftLocked = selectedOwnedNft != null;
    final dialogTheme = Theme.of(context).copyWith(
      colorScheme: _listingDialogTheme(context).colorScheme,
      textTheme: _listingDialogTheme(context).textTheme,
      inputDecorationTheme: _listingDialogTheme(context).inputDecorationTheme,
      switchTheme: _listingDialogTheme(context).switchTheme,
    );

    return Theme(
      data: dialogTheme,
      child: AlertDialog(
        backgroundColor: const Color(0xFF0B1024),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.card.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: const Color(0xFFFACC15),
                        decoration: const InputDecoration(
                          labelText: 'Price',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 96,
                      child: DropdownButtonFormField<String>(
                        initialValue: _priceCurrency,
                        isExpanded: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                        dropdownColor: const Color(0xFF111936),
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                          border: OutlineInputBorder(),
                        ),
                        items: _listingPriceCurrencies
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(
                            () => _priceCurrency = value ?? _priceCurrency,
                          );
                          _schedulePriceQuoteWarmup();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: const Color(0xFFFACC15),
                  enabled: !nftLocked,
                  decoration: const InputDecoration(
                    labelText: 'Quantity available',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _condition,
                        style: const TextStyle(color: Colors.white),
                        dropdownColor: const Color(0xFF111936),
                        decoration: const InputDecoration(
                          labelText: 'Condition',
                          border: OutlineInputBorder(),
                        ),
                        items: const ['NM', 'SP', 'MP', 'PL', 'Poor']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(_conditionMoodLabel(value)),
                              ),
                            )
                            .toList(),
                        onChanged: nftLocked
                            ? null
                            : (value) => setState(
                                  () => _condition = value ?? _condition,
                                ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _language,
                        style: const TextStyle(color: Colors.white),
                        dropdownColor: const Color(0xFF111936),
                        decoration: const InputDecoration(
                          labelText: 'Language',
                          border: OutlineInputBorder(),
                        ),
                        items: _listingLanguageCodes
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(_listingLanguageLabel(value)),
                              ),
                            )
                            .toList(),
                        onChanged: nftLocked
                            ? null
                            : (value) => setState(
                                  () => _language = value ?? _language,
                                ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _foilState,
                  style: const TextStyle(color: Colors.white),
                  dropdownColor: const Color(0xFF111936),
                  decoration: const InputDecoration(
                    labelText: 'Foil / holo state',
                    border: OutlineInputBorder(),
                  ),
                  items: _foilStateOptions
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_foilStateLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: nftLocked
                      ? null
                      : (value) => setState(
                            () => _foilState = value ?? _foilState,
                          ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InlineSellSwitch(
                      label: 'Sealed',
                      value: _sealed,
                      onChanged: (value) => setState(() => _sealed = value),
                      enabled: !nftLocked,
                    ),
                    _InlineSellSwitch(
                      label: 'Graded',
                      value: _graded,
                      onChanged: (value) => setState(() => _graded = value),
                      enabled: !nftLocked,
                    ),
                    _InlineSellSwitch(
                      label: 'Signed',
                      value: _signed,
                      onChanged: (value) => setState(() => _signed = value),
                      enabled: !nftLocked,
                    ),
                    _InlineSellSwitch(
                      label: 'Shipping',
                      value: _shippingAvailable,
                      onChanged: (value) =>
                          setState(() => _shippingAvailable = value),
                      enabled: !nftLocked,
                    ),
                    if (canUseReserveToggle)
                      _InlineSellSwitch(
                        label: 'Reserve',
                        value: _reserveAvailable,
                        onChanged: (value) =>
                            setState(() => _reserveAvailable = value),
                      ),
                    if (ownedNfts.isNotEmpty)
                      _InlineSellSwitch(
                        label: 'NFT',
                        value: _nftAvailable,
                        onChanged: (value) =>
                            _setDialogNftAvailable(value, ownedNfts),
                      ),
                  ],
                ),
                if (selectedOwnedNft != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'NFT metadata locked from your collection. Quantity is limited to 1 for this NFT.',
                    style: TextStyle(
                      color: Color(0xFFBAE6FD),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (_graded) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _gradingCompanyController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: const Color(0xFFFACC15),
                          decoration: const InputDecoration(
                            labelText: 'Grading company',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _gradeController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: const Color(0xFFFACC15),
                          decoration: const InputDecoration(
                            labelText: 'Grade',
                            hintText: '10',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _certificationIdController,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: const Color(0xFFFACC15),
                    decoration: const InputDecoration(
                      labelText: 'Certification ID',
                      hintText: 'e.g. 12345678',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  height: 86,
                  child: TextField(
                    controller: _sellerCommentController,
                    maxLines: 3,
                    maxLength: 500,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: const Color(0xFFFACC15),
                    decoration: const InputDecoration(
                      labelText: 'Seller comment',
                      hintText: 'Optional details about condition',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFF93A4C8)),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _isSaving ? null : _saveListing,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFACC15),
              foregroundColor: const Color(0xFF111827),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('List card'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveListing() async {
    final price = double.tryParse(_priceController.text.trim());
    final quantity = int.tryParse(_quantityController.text.trim());
    if (price == null || price <= 0 || quantity == null || quantity <= 0) {
      setState(() => _error = 'Enter a valid price and quantity.');
      return;
    }
    if (_nftAvailable) {
      final ownedNfts = _ownedNftsForCard(
        widget.card,
        ref.read(userCardCollectionProvider).valueOrNull,
      );
      final selectedNft = _selectedOwnedNft(ownedNfts);
      if (selectedNft == null) {
        setState(() => _error = 'You need to own this card as an NFT first.');
        return;
      }
      _applyOwnedNftToDialog(selectedNft);
    }
    if (_graded &&
        (_gradingCompanyController.text.trim().isEmpty ||
            _gradeController.text.trim().isEmpty ||
            _certificationIdController.text.trim().isEmpty)) {
      setState(
          () => _error = 'Enter grading company, grade and certification ID.');
      return;
    }
    final canUseReserveToggle =
        _canUseReserveListingToggle(ref.read(userProfileProvider).valueOrNull);
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      _cancelPriceQuoteWarmup(clearQuote: false);
      final pricePkn = await _priceToPkn(price);
      final listing = CardListing.draft(
        card: widget.card,
        sellerUid: widget.sellerUid,
        sellerName: widget.sellerName,
        sellerCountry: 'EU',
        sellerReputationLabel: 'New seller',
        condition: _condition,
        language: _language,
        pricePkn: pricePkn,
        quantityAvailable: _nftAvailable ? 1 : quantity.clamp(1, 99),
        signed: _signed,
        reverse: _foilState == 'reverse',
        firstEdition: false,
        foilState: _foilState,
        variantState: '',
        sealed: _sealed,
        graded: _graded,
        gradingCompany: _graded ? _gradingCompanyController.text.trim() : null,
        grade: _graded ? _gradeController.text.trim() : null,
        certificationId:
            _graded ? _certificationIdController.text.trim() : null,
        shippingAvailable: _shippingAvailable,
        reserveAvailable: canUseReserveToggle && _reserveAvailable,
        nftAvailable: _nftAvailable,
        sellerComment: _sellerCommentController.text.trim(),
        source: _nftAvailable ? 'pokoin_user_nft' : 'pokoin_user_listing',
        sourceListingId:
            _nftAvailable ? (_selectedNftCollectionItemId ?? '') : '',
      );
      final created =
          await ref.read(cardListingServiceProvider).createListing(listing);
      if (mounted) {
        widget.onSaved(created);
        _cancelPriceQuoteWarmup(clearQuote: true);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Listing created.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _isSaving = false;
        });
      }
    }
  }

  Future<double> _priceToPkn(double amount) async {
    final quote = _warmedPriceQuote;
    if (quote != null &&
        quote.matches(amount: amount, currency: _priceCurrency)) {
      return quote.pricePkn;
    }
    return _listingPriceToPkn(
      ref,
      amount: amount,
      currency: _priceCurrency,
    );
  }

  void _schedulePriceQuoteWarmup() {
    final token = ++_priceQuoteToken;
    _priceQuoteTimer?.cancel();
    final amount = double.tryParse(_priceController.text.trim());
    if (_priceCurrency == 'PKN' || amount == null || amount <= 0) {
      _warmedPriceQuote = null;
      return;
    }
    final currency = _priceCurrency;
    _priceQuoteTimer = Timer(const Duration(milliseconds: 450), () async {
      try {
        final pricePkn = await _listingPriceToPkn(
          ref,
          amount: amount,
          currency: currency,
        );
        if (!mounted || token != _priceQuoteToken) {
          return;
        }
        _warmedPriceQuote = _ListingPriceQuote(
          amount: amount,
          currency: currency,
          pricePkn: pricePkn,
        );
      } catch (_) {
        if (!mounted || token != _priceQuoteToken) {
          return;
        }
        _warmedPriceQuote = null;
      }
    });
  }

  void _cancelPriceQuoteWarmup({required bool clearQuote}) {
    _priceQuoteTimer?.cancel();
    _priceQuoteTimer = null;
    _priceQuoteToken++;
    if (clearQuote) {
      _warmedPriceQuote = null;
    }
  }
}

class _PriceChart extends StatelessWidget {
  const _PriceChart({
    required this.market,
    required this.sales,
  });

  final _CardMarketData market;
  final AsyncValue<List<CardSaleEvent>> sales;

  @override
  Widget build(BuildContext context) {
    final events = sales.valueOrNull ?? const <CardSaleEvent>[];
    final analytics = _SoldPriceAnalytics.fromSales(events);
    if (sales.isLoading && events.isEmpty) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF111936),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Text(
          'Loading sold-card analytics...',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF93A4C8), height: 1.45),
        ),
      );
    }
    if (!analytics.hasData) {
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF111936),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Text(
          'No sold-card analytics yet. Condition lines will populate after completed purchases.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF93A4C8), height: 1.45),
        ),
      );
    }

    return Stack(
      children: [
        LineChart(
          LineChartData(
            minX: analytics.minX,
            maxX: analytics.maxX,
            minY: analytics.minY,
            maxY: analytics.maxY,
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(
                color: Colors.white.withValues(alpha: 0.08),
                strokeWidth: 1,
              ),
            ),
            titlesData: const FlTitlesData(
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles:
                  AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            extraLinesData: const ExtraLinesData(),
            lineBarsData: [
              for (final series in analytics.rawSeries)
                LineChartBarData(
                  spots: series.spots,
                  isCurved: series.spots.length > 2,
                  color: _conditionColor(series.condition),
                  barWidth: 3,
                  dotData: FlDotData(show: series.spots.length == 1),
                  belowBarData: BarAreaData(
                    show: true,
                    color: _conditionColor(series.condition)
                        .withValues(alpha: 0.08),
                  ),
                ),
              if (analytics.gradedSpots.isNotEmpty)
                LineChartBarData(
                  spots:
                      analytics.gradedSpots.map((event) => event.spot).toList(),
                  isCurved: false,
                  color: Colors.transparent,
                  barWidth: 0,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      final event = analytics.gradedSpots[index];
                      return FlDotCirclePainter(
                        radius: 4.5,
                        color: _conditionColor(event.condition),
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final condition in analytics.visibleConditions)
                _SalesLegendPill(condition: condition),
            ],
          ),
        ),
        for (final dot in analytics.gradedSpots)
          Positioned(
            left: dot.labelX,
            top: dot.labelY,
            child: _GradedSaleLabel(dot: dot),
          ),
      ],
    );
  }
}

class _SalesLegendPill extends StatelessWidget {
  const _SalesLegendPill({required this.condition});

  final String condition;

  @override
  Widget build(BuildContext context) {
    final color = _conditionColor(condition);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        condition,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _GradedSaleLabel extends StatelessWidget {
  const _GradedSaleLabel({required this.dot});

  final _GradedSaleSpot dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF050816).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _conditionColor(dot.condition).withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        dot.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SoldPriceAnalytics {
  const _SoldPriceAnalytics({
    required this.rawSeries,
    required this.gradedSpots,
    required this.visibleConditions,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final List<_ConditionSaleSeries> rawSeries;
  final List<_GradedSaleSpot> gradedSpots;
  final List<String> visibleConditions;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  bool get hasData => rawSeries.isNotEmpty || gradedSpots.isNotEmpty;

  static _SoldPriceAnalytics fromSales(List<CardSaleEvent> sales) {
    final sorted = [...sales]..sort((a, b) => a.soldAt.compareTo(b.soldAt));
    if (sorted.isEmpty) {
      return const _SoldPriceAnalytics(
        rawSeries: [],
        gradedSpots: [],
        visibleConditions: [],
        minX: 0,
        maxX: 1,
        minY: 0,
        maxY: 1,
      );
    }

    final first = sorted.first.soldAt;
    final rawByCondition = <String, List<FlSpot>>{};
    final graded = <_GradedSaleSpot>[];
    final prices = <double>[];
    var maxX = 1.0;

    for (final sale in sorted) {
      final x = math
          .max(
            0,
            sale.soldAt.difference(first).inHours / 24,
          )
          .toDouble();
      maxX = math.max(maxX, x);
      prices.add(sale.pricePkn);
      if (sale.graded) {
        graded.add(_GradedSaleSpot.fromSale(sale, FlSpot(x, sale.pricePkn)));
      } else {
        final condition = _normalizedConditionCode(sale.condition);
        rawByCondition
            .putIfAbsent(condition, () => [])
            .add(FlSpot(x, sale.pricePkn));
      }
    }

    final rawSeries = _conditionOrder
        .where((condition) => rawByCondition[condition]?.isNotEmpty == true)
        .map((condition) => _ConditionSaleSeries(
              condition: condition,
              spots: rawByCondition[condition]!,
            ))
        .toList();
    final minPrice = prices.reduce(math.min);
    final maxPrice = prices.reduce(math.max);
    final padding = math.max(1.0, (maxPrice - minPrice) * 0.12);
    final visibleConditions = <String>{
      ...rawSeries.map((series) => series.condition),
      for (final dot in graded)
        if (!rawByCondition.containsKey(dot.condition)) dot.condition,
    }.toList();

    return _SoldPriceAnalytics(
      rawSeries: rawSeries,
      gradedSpots: graded
          .map((dot) => dot.withChartBounds(
                minX: 0,
                maxX: maxX,
                minY: minPrice - padding,
                maxY: maxPrice + padding,
              ))
          .toList(),
      visibleConditions: visibleConditions,
      minX: 0,
      maxX: maxX <= 0 ? 1 : maxX,
      minY: math.max(0, minPrice - padding),
      maxY: maxPrice + padding,
    );
  }
}

class _ConditionSaleSeries {
  const _ConditionSaleSeries({
    required this.condition,
    required this.spots,
  });

  final String condition;
  final List<FlSpot> spots;
}

class _GradedSaleSpot {
  const _GradedSaleSpot({
    required this.spot,
    required this.condition,
    required this.label,
    this.labelX = 0,
    this.labelY = 0,
  });

  factory _GradedSaleSpot.fromSale(CardSaleEvent sale, FlSpot spot) {
    final company = sale.gradingCompany.isEmpty ? 'Slab' : sale.gradingCompany;
    final grade = sale.grade.isEmpty ? '' : ' ${sale.grade}';
    return _GradedSaleSpot(
      spot: spot,
      condition: _normalizedConditionCode(sale.condition),
      label: '$company$grade',
    );
  }

  final FlSpot spot;
  final String condition;
  final String label;
  final double labelX;
  final double labelY;

  _GradedSaleSpot withChartBounds({
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
  }) {
    final xRange = math.max(1.0, maxX - minX);
    final yRange = math.max(1.0, maxY - minY);
    final xRatio = ((spot.x - minX) / xRange).clamp(0.0, 1.0);
    final yRatio = 1 - ((spot.y - minY) / yRange).clamp(0.0, 1.0);
    return _GradedSaleSpot(
      spot: spot,
      condition: condition,
      label: label,
      labelX: (xRatio * 190).clamp(0, 145).toDouble(),
      labelY: (yRatio * 170).clamp(12, 178).toDouble(),
    );
  }
}

const List<String> _conditionOrder = ['NM', 'SP', 'MP', 'PL', 'Poor'];

String _normalizedConditionCode(String code) {
  final normalized = code.trim();
  if (_conditionOrder.contains(normalized)) {
    return normalized;
  }
  return 'NM';
}

class _CardMarketData {
  const _CardMarketData({
    required this.floorPrice,
    required this.marketPrice,
    required this.bestDeal,
    required this.bestBid,
    required this.volume24h,
    required this.marketCap,
    required this.chart,
    required this.listings,
  });

  final double floorPrice;
  final double marketPrice;
  final double bestDeal;
  final double bestBid;
  final double volume24h;
  final double marketCap;
  final List<double> chart;
  final List<CardListing> listings;

  static const double pknUsdRate = 0.005;

  bool get hasListings => listings.isNotEmpty;
  bool get hasChart => chart.isNotEmpty;
  CardListing? get bestListing => hasListings ? listings.first : null;
  String get fiatLabel => hasListings ? _usdLabel(bestDeal) : '—';
  String get usMarketLabel => hasListings ? _usdLabel(marketPrice) : '—';
  String get change24hLabel => hasListings
      ? '+${((marketPrice - floorPrice) / floorPrice * 100).toStringAsFixed(2)}%'
      : '—';
  String get spreadLabel => hasListings
      ? '${((bestDeal - bestBid) / bestDeal * 100).toStringAsFixed(2)}%'
      : '—';
  String get liquidityLabel => '${(listings.length * 2.4).toStringAsFixed(1)}x';
  double get chartMin => hasChart ? chart.reduce(math.min) * 0.96 : 0;
  double get chartMax => hasChart ? chart.reduce(math.max) * 1.04 : 1;

  static String _usdLabel(double pknAmount) {
    return '\$${(pknAmount * pknUsdRate).toStringAsFixed(2)}';
  }

  static _CardMarketData forCard(
    PokemonCard card,
    List<CardListing> listings,
  ) {
    final sortedListings = [...listings]
      ..sort((a, b) => a.pricePkn.compareTo(b.pricePkn));
    final floor = sortedListings.isEmpty
        ? 0.0
        : sortedListings.map((listing) => listing.pricePkn).reduce(math.min);
    final market = sortedListings.isEmpty
        ? 0.0
        : sortedListings.fold<double>(
              0,
              (sum, listing) => sum + listing.pricePkn,
            ) /
            sortedListings.length;

    return _CardMarketData(
      floorPrice: floor,
      marketPrice: market,
      bestDeal: floor,
      bestBid: sortedListings.isEmpty ? 0 : floor * 0.964,
      volume24h: sortedListings.fold<double>(
        0,
        (sum, listing) => sum + listing.pricePkn * listing.quantityAvailable,
      ),
      marketCap: sortedListings.fold<double>(
        0,
        (sum, listing) => sum + listing.pricePkn * listing.quantityAvailable,
      ),
      chart: _buildChart(sortedListings),
      listings: sortedListings,
    );
  }

  static List<double> _buildChart(List<CardListing> listings) {
    if (listings.isEmpty) {
      return const [];
    }
    final values = <double>[];
    for (final listing in listings) {
      final pointCount = math.max(1, math.min(listing.quantityAvailable, 8));
      values.addAll(List<double>.filled(pointCount, listing.pricePkn));
    }
    values.sort();
    return values;
  }
}

String _languageName(String code) {
  switch (code) {
    case 'IT':
      return 'Italian';
    case 'FR':
      return 'French';
    case 'DE':
      return 'German';
    case 'ES':
      return 'Spanish';
    case 'JP':
      return 'Japanese';
    case 'EN':
    default:
      return 'English';
  }
}

String _conditionName(String code) {
  switch (code) {
    case 'SP':
      return 'Slightly Played';
    case 'MP':
      return 'Moderately Played';
    case 'PL':
      return 'Played';
    case 'Poor':
      return 'Poor';
    case 'NM':
    default:
      return 'Near Mint';
  }
}

String _conditionMoodLabel(String code) {
  switch (code) {
    case 'SP':
      return '🙂 SP';
    case 'MP':
      return '😐 MP';
    case 'PL':
      return '🙁 PL';
    case 'Poor':
      return '😭 Poor';
    case 'NM':
    default:
      return '😄 NM';
  }
}

String _foilStateLabel(String code) {
  switch (code) {
    case 'holo':
      return 'Holo';
    case 'reverse':
      return 'Reverse';
    case 'stamped':
      return 'Stamped';
    case 'promo':
      return 'Promo';
    case 'other':
      return 'Other';
    case 'standard':
    default:
      return 'Standard';
  }
}

String _defaultFoilStateForCard(PokemonCard card) {
  final haystack = [
    card.rarity,
    card.name,
    card.type,
    ...card.tags,
  ].join(' ').toLowerCase();
  if (haystack.contains('reverse')) {
    return 'reverse';
  }
  if (haystack.contains('stamped')) {
    return 'stamped';
  }
  if (haystack.contains('promo')) {
    return 'promo';
  }
  if (card.isHolo || card.isFoil || haystack.contains('holo')) {
    return 'holo';
  }
  return 'standard';
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.clip = false,
    this.gradient,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool clip;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? const Color(0xCC0B1024) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }
}

class _SellerCommentIcon extends StatelessWidget {
  const _SellerCommentIcon({
    required this.comment,
    this.size = 16,
    this.compact = false,
  });

  final String comment;
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cleanComment = comment.trim();
    final icon = Icon(
      Icons.mode_comment_outlined,
      size: size,
      color: const Color(0xFFBAE6FD),
    );
    return Semantics(
      label: 'Seller comment: $cleanComment',
      button: true,
      child: Tooltip(
        message: cleanComment,
        triggerMode: TooltipTriggerMode.tap,
        margin: const EdgeInsets.symmetric(horizontal: 18),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF111936),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          height: 1.35,
        ),
        preferBelow: false,
        child: ExcludeSemantics(
          child: Container(
            width: compact ? 22 : 24,
            height: compact ? 22 : 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFBAE6FD).withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFBAE6FD).withValues(alpha: 0.28),
              ),
            ),
            child: icon,
          ),
        ),
      ),
    );
  }
}

class _ArtistCollectionLink extends StatelessWidget {
  const _ArtistCollectionLink({
    required this.artist,
    required this.fallbackLabel,
    required this.language,
  });

  final String artist;
  final String fallbackLabel;
  final String language;

  @override
  Widget build(BuildContext context) {
    final label = artist.trim();
    if (label.isEmpty) {
      return Text(
        ' $fallbackLabel',
        style: const TextStyle(color: Color(0xFFB8C4E6)),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      mouseCursor: SystemMouseCursors.click,
      hoverColor: const Color(0xFF38BDF8).withValues(alpha: 0.12),
      onTap: () {
        final path = marketplaceArtistPath(label, language: language);
        CardDetailRouteGuard.instance.markExplicitNavigation(path);
        context.go(path);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 4),
            const Icon(
              Icons.brush_outlined,
              size: 14,
              color: Color(0xFF38BDF8),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF38BDF8),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuotePill extends StatelessWidget {
  const _QuotePill(
      {required this.label, required this.value, this.positive = false});

  final String label;
  final String value;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 12)),
        Text(
          value,
          style: TextStyle(
            color: positive ? const Color(0xFF22C55E) : const Color(0xFFFACC15),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
  });

  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 12)),
          const SizedBox(height: 6),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18)),
          const SizedBox(height: 4),
          Text(sub,
              style: const TextStyle(
                  color: Color(0xFF22C55E),
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _SelectorLike extends StatelessWidget {
  const _SelectorLike({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800))),
          const Icon(Icons.expand_more, color: Color(0xFF93A4C8)),
        ],
      ),
    );
  }
}

class _VersionSelector extends StatelessWidget {
  const _VersionSelector({
    required this.card,
    required this.displayNumber,
    required this.versionCards,
    required this.onSelected,
  });

  final PokemonCard card;
  final String displayNumber;
  final List<PokemonCard> versionCards;
  final ValueChanged<PokemonCard> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = card.itemKind == 'product'
        ? _setAndVariantLabel(card)
        : '${card.set} $displayNumber';
    if (versionCards.length <= 1) {
      return _SelectorLike(label: label);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: card.id,
          isExpanded: true,
          dropdownColor: const Color(0xFF111936),
          iconEnabledColor: const Color(0xFF93A4C8),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
          selectedItemBuilder: (context) => [
            for (final option in versionCards)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  option.id == card.id ? label : _versionOptionLabel(option),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          items: [
            for (final option in versionCards)
              DropdownMenuItem(
                value: option.id,
                child: Text(
                  _versionOptionLabel(option),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value == null || value == card.id) {
              return;
            }
            PokemonCard? selected;
            for (final option in versionCards) {
              if (option.id == value) {
                selected = option;
                break;
              }
            }
            if (selected != null) {
              onSelected(selected);
            }
          },
        ),
      ),
    );
  }

  String _versionOptionLabel(PokemonCard option) {
    final number = _displayCollectorNumber(option.number);
    return '${option.set} $number';
  }
}

class _DexLine extends StatelessWidget {
  const _DexLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style:
                      const TextStyle(color: Color(0xFF93A4C8), fontSize: 12))),
          Text(value,
              style: const TextStyle(
                  color: Color(0xFFB8C4E6),
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class _PriceInput extends StatelessWidget {
  const _PriceInput({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF64748B)),
          filled: true,
          fillColor: const Color(0xFF111936),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
      ),
    );
  }
}

class _FilterCheck extends StatelessWidget {
  const _FilterCheck({
    required this.text,
    required this.checked,
    required this.onChanged,
  });

  final String text;
  final bool checked;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              color:
                  checked ? const Color(0xFFFACC15) : const Color(0xFF64748B),
              size: 17,
            ),
            const SizedBox(width: 5),
            Text(text,
                style: const TextStyle(color: Color(0xFFB8C4E6), fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _HeaderText extends StatelessWidget {
  const _HeaderText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13));
  }
}
