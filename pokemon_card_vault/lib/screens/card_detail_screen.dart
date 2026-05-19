import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/card_listing.dart';
import '../models/pokemon_card.dart';
import '../providers/auth_provider.dart';
import '../providers/card_listing_provider.dart';
import '../providers/card_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/recent_views_provider.dart';
import '../services/card_service.dart';
import '../utils/card_palette.dart';
import '../utils/card_url.dart';
import '../utils/price_format.dart';
import 'home_screen.dart'
    show
        MarketplaceLogoButton,
        MarketplaceTopBar,
        MarketplaceTopSearch,
        ProfileIconButton,
        SearchLanguageMenu,
        WalletBalanceButton;

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

class CardDetailScreen extends ConsumerStatefulWidget {
  final String cardId;
  final String? heroTag;

  const CardDetailScreen({
    super.key,
    required this.cardId,
    this.heroTag,
  });

  @override
  ConsumerState<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends ConsumerState<CardDetailScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _searchFocused = false;
  late String _currentCardId;
  PokemonCard? _currentCardOverride;

  @override
  void initState() {
    super.initState();
    _currentCardId = widget.cardId;
    _searchFocusNode.addListener(_handleSearchFocusChanged);
  }

  @override
  void didUpdateWidget(covariant CardDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardId != widget.cardId && widget.cardId != _currentCardId) {
      _currentCardId = widget.cardId;
      if (_currentCardOverride?.id != _currentCardId) {
        _currentCardOverride = null;
      }
    }
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchFocusChanged() {
    if (mounted) {
      setState(() => _searchFocused = _searchFocusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardState = ref.watch(cardProvider);
    final overrideCard = _currentCardOverride?.id == _currentCardId
        ? _currentCardOverride
        : null;
    final card = overrideCard ?? _findCard(cardState.cards, _currentCardId);
    final directCardState = card == null
        ? ref.watch(_cardDetailByIdProvider(_currentCardId))
        : null;
    final directCard = directCardState?.valueOrNull;
    final resolvedCard = card ?? directCard;

    if ((cardState.isLoading || (directCardState?.isLoading ?? false)) &&
        resolvedCard == null) {
      return const _DetailScaffold(child: _LoadingDetail());
    }

    if (resolvedCard == null) {
      return _DetailScaffold(
        child: _NotFoundDetail(
          cardId: _currentCardId,
          onBack: () => _goBackOr(context, '/marketplace'),
        ),
      );
    }

    final listingsState = ref.watch(cardListingsProvider(resolvedCard.id));
    final listings = listingsState.valueOrNull ?? const <CardListing>[];
    final market = _CardMarketData.forCard(resolvedCard, listings);
    final bestListing = market.bestListing;
    final cartState = ref.watch(cartProvider);
    final favoritesState = ref.watch(favoritesProvider);
    final isFavorite = favoritesState.isFavorite(resolvedCard.id);
    final cachedBalance = ref.watch(cachedPknBalanceProvider).valueOrNull;
    final balance =
        ref.watch(pknBalanceProvider).valueOrNull ?? cachedBalance ?? 0;
    final compactTopBar = MediaQuery.sizeOf(context).width < 760;
    final compactSearchExpanded = compactTopBar &&
        (_searchFocused || _searchController.text.trim().isNotEmpty);
    final isInCart = bestListing == null
        ? cartState.isInCart(resolvedCard.id)
        : cartState.isListingInCart(bestListing.id);
    final expansionCardsState =
        ref.watch(_expansionVersionCardsProvider(resolvedCard));
    final expansionCards = expansionCardsState.valueOrNull ?? const [];
    final previousCard = _adjacentExpansionCard(
      expansionCards,
      resolvedCard.id,
      direction: -1,
    );
    final nextCard = _adjacentExpansionCard(
      expansionCards,
      resolvedCard.id,
      direction: 1,
    );
    final sameNameVersions = _sameNameExpansionCards(
      expansionCards,
      resolvedCard,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xF20A1026),
            titleSpacing: 16,
            title: MarketplaceTopBar(
              compactExpanded: compactSearchExpanded,
              logo: MarketplaceLogoButton(
                onTap: () => context.go('/marketplace'),
              ),
              search: MarketplaceTopSearch(
                controller: _searchController,
                focusNode: _searchFocusNode,
                query: cardState.previewQuery,
                isSearching: cardState.isSearchingPreviews,
                previews: cardState.searchPreviews,
                hintText: 'Search cards, sets, products...',
                onChanged: (value) {
                  setState(() {});
                  ref.read(cardProvider.notifier).searchPreviewsOnly(value);
                },
                onSelected: (selection) {
                  final card = selection.card;
                  ref.read(cardProvider.notifier).recordCardInteraction(
                        card,
                        'click',
                        source: 'search_preview',
                      );
                  ref.read(recentViewsProvider.notifier).remember(card);
                  _resetHeaderSearch();
                  context.go(cardDetailPath(card), extra: selection.heroTag);
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
              languageMenu: SearchLanguageMenu(
                value: cardState.searchLanguage,
                onChanged: (language) =>
                    ref.read(cardProvider.notifier).setSearchLanguage(language),
              ),
            ),
            actions: [
              if (!compactTopBar) ...[
                TextButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Home')),
                TextButton(
                    onPressed: () => context.go('/forum'),
                    child: const Text('Forum')),
                TextButton(
                    onPressed: () => context.go('/marketplace/signal'),
                    child: const Text('Signal')),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: compactSearchExpanded
                    ? const SizedBox.shrink()
                    : Row(
                        key: const ValueKey('detail-marketplace-actions'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WalletBalanceButton(
                            balance: balance,
                            onTap: () => context.go('/wallet'),
                          ),
                          const SizedBox(width: 8),
                          const ProfileIconButton(),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: FilledButton.icon(
                              onPressed: () => context.go('/cart'),
                              icon: const Icon(Icons.shopping_bag_outlined,
                                  size: 18),
                              label: Text('${cartState.itemCount}'),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AssetHeader(
                        card: resolvedCard,
                        market: market,
                        isFavorite: isFavorite,
                        onSell: () => _openSellDialog(
                          context,
                          ref,
                          resolvedCard,
                          listings,
                        ),
                        onWishlist: () => ref
                            .read(favoritesProvider.notifier)
                            .toggleFavorite(resolvedCard.id),
                        onShare: () => _copyCardLink(context, resolvedCard),
                      ),
                      const SizedBox(height: 18),
                      _TopTerminal(
                        card: resolvedCard,
                        heroTag: widget.heroTag,
                        market: market,
                        isInCart: isInCart,
                        onSell: () => _openSellDialog(
                          context,
                          ref,
                          resolvedCard,
                          listings,
                        ),
                        onPrevious: previousCard == null
                            ? null
                            : () => _showAdjacentCard(previousCard),
                        onNext: nextCard == null
                            ? null
                            : () => _showAdjacentCard(nextCard),
                        versionCards: sameNameVersions,
                        onViewAllVersions: () => context.go(
                          marketplaceCardVersionsPath(resolvedCard),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _MarketStatsGrid(market: market),
                      const SizedBox(height: 18),
                      _ListingsTerminal(
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
                        onWishlist: () => ref
                            .read(favoritesProvider.notifier)
                            .toggleFavorite(resolvedCard.id),
                      ),
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

  void _resetHeaderSearch() {
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    }
    ref.read(cardProvider.notifier).searchPreviewsOnly('');
  }

  void _showAdjacentCard(PokemonCard card) {
    if (card.id == _currentCardId) {
      return;
    }
    context.go(cardDetailPath(card));
    setState(() {
      _currentCardId = card.id;
      _currentCardOverride = card;
    });
    ref.read(cardProvider.notifier).recordCardInteraction(
          card,
          'view',
          source: 'card_detail_adjacent',
        );
    ref.read(recentViewsProvider.notifier).remember(card);
  }

  Future<void> _copyCardLink(BuildContext context, PokemonCard card) async {
    final origin = Uri.base.origin;
    final path = cardDetailPath(card);
    await Clipboard.setData(ClipboardData(text: '$origin$path'));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Card link copied to clipboard.')),
    );
  }

  PokemonCard? _findCard(List<PokemonCard> cards, String id) {
    for (final card in cards) {
      if (card.id == id) {
        return card;
      }
    }
    return null;
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
      context.go('/auth?from=${Uri.encodeComponent(cardDetailPath(card))}');
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

final _cardDetailByIdProvider =
    FutureProvider.family<PokemonCard?, String>((ref, cardId) {
  return ref.read(cardProvider.notifier).loadCardById(cardId).then((card) {
    if (card != null) {
      ref.read(cardProvider.notifier).recordCardInteraction(
            card,
            'view',
            source: 'card_detail',
          );
      ref.read(recentViewsProvider.notifier).remember(card);
    }
    return card;
  });
});

final _expansionVersionCardsProvider =
    FutureProvider.family<List<PokemonCard>, PokemonCard>((ref, card) {
  return CardService().getExpansionVersionCards(card);
});

void _goBackOr(BuildContext context, String fallbackPath) {
  if (context.canPop()) {
    context.pop();
    return;
  }
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
    if (RegExp(r'\d').hasMatch(part)) {
      return part;
    }
  }
  return text;
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
              'No local market is available for card id $cardId yet.',
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
    required this.market,
    required this.isFavorite,
    required this.onSell,
    required this.onWishlist,
    required this.onShare,
  });

  final PokemonCard card;
  final _CardMarketData market;
  final bool isFavorite;
  final VoidCallback onSell;
  final VoidCallback onWishlist;
  final VoidCallback onShare;

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
            Text(
              card.itemKind == 'product'
                  ? ' · ${card.number.trim().isEmpty ? card.type : '${card.number} · ${card.type}'}'
                  : ' #${_displayCollectorNumber(card.number)} · ${card.type}',
              style: const TextStyle(color: Color(0xFFB8C4E6)),
            ),
          ],
        ),
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
        FilledButton.icon(
          onPressed: onSell,
          icon: const Icon(Icons.sell_outlined, size: 18),
          label: const Text('Sell'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF38BDF8),
            foregroundColor: const Color(0xFF07111F),
          ),
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
    required this.heroTag,
    required this.market,
    required this.isInCart,
    required this.onSell,
    required this.onPrevious,
    required this.onNext,
    required this.versionCards,
    required this.onViewAllVersions,
  });

  final PokemonCard card;
  final String? heroTag;
  final _CardMarketData market;
  final bool isInCart;
  final VoidCallback onSell;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final List<PokemonCard> versionCards;
  final VoidCallback onViewAllVersions;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 960;
    final artwork = _ArtworkPanel(
      card: card,
      heroTag: heroTag,
      onPrevious: onPrevious,
      onNext: onNext,
      versionCards: versionCards,
      onViewAllVersions: onViewAllVersions,
    );
    final center = _MarketCenterPanel(
      card: card,
      market: market,
    );
    final deal = _BestDealPanel(card: card, market: market, isInCart: isInCart);

    if (!wide) {
      return Column(
        children: [
          artwork,
          const SizedBox(height: 16),
          center,
          const SizedBox(height: 16),
          deal,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 300, child: artwork),
        const SizedBox(width: 16),
        Expanded(flex: 2, child: center),
        const SizedBox(width: 16),
        SizedBox(width: 300, child: deal),
      ],
    );
  }
}

class _ArtworkPanel extends StatelessWidget {
  const _ArtworkPanel({
    required this.card,
    required this.heroTag,
    required this.onPrevious,
    required this.onNext,
    required this.versionCards,
    required this.onViewAllVersions,
  });

  final PokemonCard card;
  final String? heroTag;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final List<PokemonCard> versionCards;
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
    return _Panel(
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
          AspectRatio(
            aspectRatio: 0.72,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: frameColor,
                borderRadius: BorderRadius.circular(22),
              ),
              clipBehavior: Clip.none,
              child: _HeroCardArtwork(
                heroTag: heroTag,
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
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onViewAllVersions,
            child: const Text('View all versions'),
          ),
        ],
      ),
    );
  }
}

class _MarketCenterPanel extends StatefulWidget {
  const _MarketCenterPanel({
    required this.card,
    required this.market,
  });

  final PokemonCard card;
  final _CardMarketData market;

  @override
  State<_MarketCenterPanel> createState() => _MarketCenterPanelState();
}

class _MarketCenterPanelState extends State<_MarketCenterPanel> {
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _TabPill(text: 'Info', active: true),
              SizedBox(width: 8),
              _TabPill(text: 'Markets', active: false),
            ],
          ),
          const SizedBox(height: 18),
          _MarketInfoPane(market: widget.market),
          const SizedBox(height: 12),
          _InlineSellListingForm(
            card: widget.card,
            initialPricePkn: _minimumListingPrice(widget.market.listings),
            compactMode: true,
            ultraCompact: !compact,
          ),
        ],
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

class _MarketInfoPane extends StatelessWidget {
  const _MarketInfoPane({
    required this.market,
  });

  final _CardMarketData market;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (market.hasListings) ...[
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _MetricTile(
                title: 'Best ask',
                value: formatPkn(market.bestDeal),
                accent: true,
              ),
              _MetricTile(title: 'US market', value: market.usMarketLabel),
            ],
          ),
          const SizedBox(height: 20),
        ],
        SizedBox(height: 220, child: _PriceChart(market: market)),
      ],
    );
  }
}

class _HeroCardArtwork extends StatelessWidget {
  const _HeroCardArtwork({
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
  final TextEditingController _quantityController =
      TextEditingController(text: '1');
  final TextEditingController _gradingCompanyController =
      TextEditingController(text: 'PSA');
  final TextEditingController _gradeController = TextEditingController();
  final TextEditingController _certificationIdController =
      TextEditingController();
  String _condition = 'NM';
  String _language = 'EN';
  bool _reverse = true;
  bool _signed = false;
  bool _graded = false;
  bool _shippingAvailable = true;
  bool _nftAvailable = false;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initialPrice = widget.initialPricePkn;
    _priceController.text =
        initialPrice == null ? '' : _formatInitialPrice(initialPrice);
  }

  @override
  void didUpdateWidget(covariant _InlineSellListingForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id ||
        oldWidget.initialPricePkn != widget.initialPricePkn) {
      final initialPrice = widget.initialPricePkn;
      _priceController.text =
          initialPrice == null ? '' : _formatInitialPrice(initialPrice);
      _quantityController.text = '1';
      _condition = 'NM';
      _language = 'EN';
      _reverse = true;
      _signed = false;
      _graded = false;
      _shippingAvailable = true;
      _nftAvailable = false;
      _error = null;
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    _quantityController.dispose();
    _gradingCompanyController.dispose();
    _gradeController.dispose();
    _certificationIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final compact = MediaQuery.sizeOf(context).width < 760;
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
                      '/auth?from=${Uri.encodeComponent(cardDetailPath(widget.card))}',
                    ),
                    child: const Text('Sign in'),
                  ),
              ],
            ),
            SizedBox(height: widget.ultraCompact ? 8 : 12),
            if (widget.ultraCompact)
              Row(
                children: [
                  Expanded(flex: 2, child: _buildPriceField()),
                  const SizedBox(width: 8),
                  SizedBox(width: 72, child: _buildQuantityField()),
                  const SizedBox(width: 8),
                  Expanded(child: _buildConditionField()),
                  const SizedBox(width: 8),
                  Expanded(child: _buildLanguageField()),
                ],
              )
            else if (compact || widget.compactMode)
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildPriceField()),
                      const SizedBox(width: 10),
                      SizedBox(width: 86, child: _buildQuantityField()),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildConditionField()),
                      const SizedBox(width: 10),
                      Expanded(child: _buildLanguageField()),
                    ],
                  ),
                ],
              )
            else ...[
              Row(
                children: [
                  Expanded(child: _buildPriceField()),
                  const SizedBox(width: 10),
                  SizedBox(width: 150, child: _buildQuantityField()),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildConditionField()),
                  const SizedBox(width: 10),
                  Expanded(child: _buildLanguageField()),
                ],
              ),
            ],
            SizedBox(height: widget.ultraCompact ? 8 : 10),
            if (widget.ultraCompact)
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _InlineSellSwitch(
                          label: 'Reverse',
                          value: _reverse,
                          compact: true,
                          onChanged: (value) =>
                              setState(() => _reverse = value),
                        ),
                        _InlineSellSwitch(
                          label: 'Ship',
                          value: _shippingAvailable,
                          compact: true,
                          onChanged: (value) =>
                              setState(() => _shippingAvailable = value),
                        ),
                        _InlineSellSwitch(
                          label: 'NFT',
                          value: _nftAvailable,
                          compact: true,
                          onChanged: (value) =>
                              setState(() => _nftAvailable = value),
                        ),
                        _InlineSellSwitch(
                          label: 'Signed',
                          value: _signed,
                          compact: true,
                          onChanged: (value) => setState(() => _signed = value),
                        ),
                        _InlineSellSwitch(
                          label: 'Graded',
                          value: _graded,
                          compact: true,
                          onChanged: (value) => setState(() => _graded = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: user == null || _isSaving
                        ? null
                        : () => _saveListing(
                              sellerUid: user.uid,
                              sellerName:
                                  profile?.displayName.trim().isNotEmpty == true
                                      ? profile!.displayName
                                      : user.displayName ??
                                          user.email ??
                                          'Pokoin seller',
                            ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sell_outlined, size: 16),
                    label: const Text('List'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFACC15),
                      foregroundColor: const Color(0xFF111827),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InlineSellSwitch(
                    label: 'Reverse holo',
                    value: _reverse,
                    onChanged: (value) => setState(() => _reverse = value),
                  ),
                  _InlineSellSwitch(
                    label: 'Shipping',
                    value: _shippingAvailable,
                    onChanged: (value) =>
                        setState(() => _shippingAvailable = value),
                  ),
                  _InlineSellSwitch(
                    label: 'NFT claim',
                    value: _nftAvailable,
                    onChanged: (value) => setState(() => _nftAvailable = value),
                  ),
                  _InlineSellSwitch(
                    label: 'Signed',
                    value: _signed,
                    onChanged: (value) => setState(() => _signed = value),
                  ),
                  _InlineSellSwitch(
                    label: 'Graded',
                    value: _graded,
                    onChanged: (value) => setState(() => _graded = value),
                  ),
                ],
              ),
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
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            if (!widget.ultraCompact) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: user == null || _isSaving
                      ? null
                      : () => _saveListing(
                            sellerUid: user.uid,
                            sellerName:
                                profile?.displayName.trim().isNotEmpty == true
                                    ? profile!.displayName
                                    : user.displayName ??
                                        user.email ??
                                        'Pokoin seller',
                          ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sell_outlined, size: 18),
                  label: const Text('List card'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFACC15),
                    foregroundColor: const Color(0xFF111827),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPriceField() {
    return TextField(
      controller: _priceController,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFFFACC15),
      decoration: const InputDecoration(
        labelText: 'Price in PKN',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildQuantityField() {
    return TextField(
      controller: _quantityController,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFFFACC15),
      decoration: const InputDecoration(
        labelText: 'Qty',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildConditionField() {
    return DropdownButtonFormField<String>(
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
              child: Text(value),
            ),
          )
          .toList(),
      onChanged: (value) => setState(() => _condition = value ?? _condition),
    );
  }

  Widget _buildLanguageField() {
    return DropdownButtonFormField<String>(
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
              child: Text(value),
            ),
          )
          .toList(),
      onChanged: (value) => setState(() => _language = value ?? _language),
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

  Future<void> _saveListing({
    required String sellerUid,
    required String sellerName,
  }) async {
    final price = double.tryParse(_priceController.text.trim());
    final quantity = int.tryParse(_quantityController.text.trim());
    if (price == null || price <= 0 || quantity == null || quantity <= 0) {
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
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final listing = CardListing.draft(
        card: widget.card,
        sellerUid: sellerUid,
        sellerName: sellerName,
        sellerCountry: 'EU',
        sellerReputationLabel: 'New seller',
        condition: _condition,
        language: _language,
        pricePkn: price,
        quantityAvailable: quantity.clamp(1, 99),
        signed: _signed,
        reverse: _reverse,
        graded: _graded,
        gradingCompany: _graded ? _gradingCompanyController.text.trim() : null,
        grade: _graded ? _gradeController.text.trim() : null,
        certificationId:
            _graded ? _certificationIdController.text.trim() : null,
        shippingAvailable: _shippingAvailable,
        nftAvailable: _nftAvailable,
      );
      await ref.read(cardListingServiceProvider).createListing(listing);
      if (mounted) {
        _quantityController.text = '1';
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
}

class _InlineSellSwitch extends StatelessWidget {
  const _InlineSellSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(left: compact ? 8 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Transform.scale(
            scale: compact ? 0.62 : 0.78,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

String _formatInitialPrice(double price) {
  if (price == price.roundToDouble()) {
    return price.toStringAsFixed(0);
  }
  return price.toStringAsFixed(2);
}

class _BestDealPanel extends ConsumerWidget {
  const _BestDealPanel({
    required this.card,
    required this.market,
    required this.isInCart,
  });

  final PokemonCard card;
  final _CardMarketData market;
  final bool isInCart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bestListing = market.bestListing;
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final user = ref.watch(authStateProvider).valueOrNull;
    final hasSilverAccess = profile?.hasSilverAccess == true;
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
                    _ExternalMarketButtons(blueprintId: card.id)
                  else
                    _SilverUnlockButton(
                      isSignedIn: user != null,
                      onUnlock: () => _unlockSilver(context, ref),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                market.hasListings ? formatPkn(market.bestDeal) : '—',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                market.hasListings
                    ? '~${market.fiatLabel} · spread ${market.spreadLabel}'
                    : 'No sellers yet. Be the first to list this card.',
                style: const TextStyle(color: Color(0xFF93A4C8)),
              ),
              const SizedBox(height: 16),
              _SelectorLike(
                  label: bestListing == null
                      ? 'Select language'
                      : '${bestListing.language} · ${_languageName(bestListing.language)}'),
              const SizedBox(height: 8),
              _SelectorLike(
                  label: bestListing == null
                      ? 'Select condition'
                      : '${bestListing.condition} · ${_conditionName(bestListing.condition)}'),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: bestListing == null
                    ? null
                    : () {
                        if (isInCart) {
                          ref
                              .read(cartProvider.notifier)
                              .removeFromCart(bestListing.id);
                        } else {
                          ref
                              .read(cartProvider.notifier)
                              .addListingToCart(card, bestListing);
                          ref.read(cardProvider.notifier).recordCardInteraction(
                                card,
                                'cart_add',
                                source: 'detail_buy_box',
                              );
                        }
                      },
                icon: Icon(isInCart
                    ? Icons.remove_shopping_cart
                    : Icons.add_shopping_cart),
                label: Text(isInCart ? 'Remove from cart' : 'Add to cart'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: const Color(0xFFFACC15),
                  foregroundColor: const Color(0xFF111827),
                  disabledBackgroundColor: const Color(0xFF374151),
                  disabledForegroundColor: const Color(0xFFCBD5E1),
                ),
              ),
              const SizedBox(height: 12),
              _DexLine(
                  label: 'Estimated total',
                  value: market.hasListings ? formatPkn(market.bestDeal) : '—'),
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
      context.go('/auth?from=${Uri.encodeComponent(cardDetailPath(card))}');
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
}

class _SilverUnlockButton extends StatelessWidget {
  const _SilverUnlockButton({
    required this.isSignedIn,
    required this.onUnlock,
  });

  final bool isSignedIn;
  final VoidCallback onUnlock;

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
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          minimumSize: const Size(0, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Text(isSignedIn ? 'Unlock for 20 PKN' : 'Sign in to unlock'),
      ),
    );
  }
}

class _ExternalMarketButtons extends StatelessWidget {
  const _ExternalMarketButtons({required this.blueprintId});

  final String blueprintId;

  Future<void> _openExternalMarket(String market) async {
    final id = Uri.encodeComponent(blueprintId);
    await launchUrl(
      Uri.base.resolve('/api/$market-redirect?id=$id'),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ExternalMarketPill(
          label: 'CT',
          tooltip: 'Open on CardTrader',
          enabled: blueprintId.trim().isNotEmpty,
          foregroundColor: Colors.white,
          borderColor: const Color(0xFF1ED6FF).withValues(alpha: 0.55),
          gradient: const LinearGradient(
            colors: [Color(0xFF00C2FF), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          onPressed: () => _openExternalMarket('cardtrader'),
        ),
        const SizedBox(width: 8),
        _ExternalMarketPill(
          label: 'CM',
          tooltip: 'Open on Cardmarket without sending a Pokoin referrer',
          enabled: blueprintId.trim().isNotEmpty,
          foregroundColor: Colors.white,
          borderColor: const Color(0xFF60A5FA).withValues(alpha: 0.72),
          gradient: const LinearGradient(
            colors: [Color(0xFF2563EB), Color(0xFF002395)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          onPressed: () => _openExternalMarket('cardmarket'),
        ),
      ],
    );
  }
}

class _ExternalMarketPill extends StatelessWidget {
  const _ExternalMarketPill({
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.foregroundColor,
    required this.borderColor,
    required this.onPressed,
    this.gradient,
  });

  final String label;
  final String tooltip;
  final bool enabled;
  final Color foregroundColor;
  final Color borderColor;
  final Gradient? gradient;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final disabledColor = Colors.white.withValues(alpha: 0.08);
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
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
            foregroundColor: enabled
                ? foregroundColor
                : Colors.white.withValues(alpha: 0.45),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            minimumSize: const Size(54, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
            shape: const StadiumBorder(),
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
          ),
          child: Text(label),
        ),
      ),
    );
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
  });

  final PokemonCard card;
  final _CardMarketData market;
  final bool isLoading;
  final bool isFavorite;
  final VoidCallback onSell;
  final VoidCallback onWishlist;

  @override
  State<_ListingsTerminal> createState() => _ListingsTerminalState();
}

class _ListingsTerminalState extends State<_ListingsTerminal> {
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();
  final Set<String> _conditions = <String>{};
  final Set<String> _languages = <String>{};
  bool _shippingOnly = false;
  bool _nftOnly = false;
  bool _gradedOnly = false;
  bool _signedOnly = false;
  bool _reverseOnly = false;
  String _sort = 'price_asc';

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    final visibleListings = _filteredListings();
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
    );
    final table = _ListingsTable(
      card: widget.card,
      market: widget.market,
      listings: visibleListings,
      totalListings: widget.market.listings.length,
      isLoading: widget.isLoading,
      sort: _sort,
      onSortChanged: (value) => setState(() => _sort = value),
      isFavorite: widget.isFavorite,
      onSell: widget.onSell,
      onWishlist: widget.onWishlist,
      onClearFilters: _clearFilters,
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
      if (_conditions.isNotEmpty && !_conditions.contains(listing.condition)) {
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

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Filters',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
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
                      text: language,
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
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44)),
            child: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }
}

class _PokoinConditionsPlaceholder extends StatelessWidget {
  const _PokoinConditionsPlaceholder();

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('NM', 'Near Mint', 'Clean front/back, minimal edge wear.'),
      ('SP', 'Slightly Played', 'Light whitening or small handling marks.'),
      ('MP', 'Moderately Played', 'Visible wear, still display-worthy.'),
      ('PL', 'Played', 'Heavy wear, creases or clear surface marks.'),
      ('Poor', 'Poor', 'Damaged or binder-only copy.'),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFFACC15).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFFFACC15).withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            code,
            style: const TextStyle(
              color: Color(0xFFFACC15),
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
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: Color(0xFFFACC15)),
            )
          else if (market.listings.isEmpty)
            _NoListingsState(
              isFavorite: isFavorite,
              onSell: onSell,
              onWishlist: onWishlist,
            )
          else if (listings.isEmpty)
            _NoFilteredListingsState(onClear: onClearFilters)
          else
            for (final listing in listings)
              _ListingRow(card: card, listing: listing, compact: compact),
        ],
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
                SizedBox(width: 96, child: _HeaderText('Shipping')),
                SizedBox(width: 88, child: _HeaderText('')),
              ]
            : const [
                Expanded(flex: 3, child: _HeaderText('Seller')),
                Expanded(flex: 3, child: _HeaderText('Product')),
                Expanded(flex: 2, child: _HeaderText('Price')),
                Expanded(child: _HeaderText('Qty')),
                SizedBox(width: 188, child: _HeaderText('SHIPPING')),
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
    if (compact) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _CompactListingRow(
          card: card,
          listing: listing,
          inCart: inCart,
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
                    Text(_countryFlag(listing.sellerCountry),
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        listing.sellerName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800),
                      ),
                    ),
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
                _TinyBadge(text: listing.condition),
                _TinyBadge(text: listing.language),
                if (listing.reverse) const _TinyBadge(text: 'Reverse'),
                if (listing.signed) const _TinyBadge(text: 'Signed'),
                if (listing.graded)
                  _TinyBadge(
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
            width: 188,
            child: Row(
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
                      ref.read(cardProvider.notifier).recordCardInteraction(
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
                SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: listing.nftAvailable ? () {} : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFACC15),
                      side: BorderSide(
                        color: const Color(0xFFFACC15).withValues(alpha: 0.55),
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
                    child: const Text('NFT'),
                  ),
                ),
                const SizedBox(width: 8),
                if (listing.shippingAvailable)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFACC15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('SHIPPING',
                        style: TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 11,
                            fontWeight: FontWeight.w900)),
                  )
                else
                  const SizedBox(width: 78),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactListingRow extends ConsumerWidget {
  const _CompactListingRow({
    required this.card,
    required this.listing,
    required this.inCart,
  });

  final PokemonCard card;
  final CardListing listing;
  final bool inCart;

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
                Text(
                  listing.sellerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF67E8F9),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_countryFlag(listing.sellerCountry)} ★ ${listing.sellerReputationLabel}',
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
                _TinyBadge(text: listing.condition),
                _TinyBadge(text: listing.language),
                if (listing.reverse) const _TinyBadge(text: 'REV'),
                if (listing.signed) const _TinyBadge(text: 'SIG'),
                if (listing.graded) const _TinyBadge(text: 'GRD'),
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
            width: 96,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: listing.shippingAvailable
                      ? const Color(0xFFFFE8AA)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  listing.shippingAvailable ? '1-DAY' : '—',
                  style: TextStyle(
                    color: listing.shippingAvailable
                        ? const Color(0xFF7C4A03)
                        : const Color(0xFF93A4C8),
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 88,
            child: Align(
              alignment: Alignment.centerRight,
              child: _DarkCircleButton(
                onPressed: () {
                  if (inCart) {
                    ref.read(cartProvider.notifier).removeFromCart(listing.id);
                  } else {
                    ref
                        .read(cartProvider.notifier)
                        .addListingToCart(card, listing);
                    ref.read(cardProvider.notifier).recordCardInteraction(
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
                foregroundColor:
                    inCart ? const Color(0xFFFACC15) : const Color(0xFFCBD5E1),
                backgroundColor: inCart
                    ? const Color(0xFFFACC15).withValues(alpha: 0.14)
                    : const Color(0xFFBAE6FD).withValues(alpha: 0.36),
              ),
            ),
          ),
        ],
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

class _SellListingDialog extends ConsumerStatefulWidget {
  const _SellListingDialog({
    required this.card,
    required this.sellerUid,
    required this.sellerName,
    required this.initialPricePkn,
  });

  final PokemonCard card;
  final String sellerUid;
  final String sellerName;
  final double? initialPricePkn;

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
  String _condition = 'NM';
  String _language = 'EN';
  bool _reverse = true;
  bool _signed = false;
  bool _graded = false;
  bool _shippingAvailable = true;
  bool _nftAvailable = false;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initialPrice = widget.initialPricePkn;
    _priceController.text =
        initialPrice == null ? '' : _formatInitialPrice(initialPrice);
  }

  @override
  void dispose() {
    _priceController.dispose();
    _quantityController.dispose();
    _gradingCompanyController.dispose();
    _gradeController.dispose();
    _certificationIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dialogTheme = Theme.of(context).copyWith(
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
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
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
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _language = value ?? _language),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _reverse,
                  onChanged: (value) => setState(() => _reverse = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reverse holo'),
                ),
                SwitchListTile(
                  value: _shippingAvailable,
                  onChanged: (value) =>
                      setState(() => _shippingAvailable = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Shipping available'),
                ),
                SwitchListTile(
                  value: _nftAvailable,
                  onChanged: (value) => setState(() => _nftAvailable = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('NFT claim available'),
                ),
                SwitchListTile(
                  value: _signed,
                  onChanged: (value) => setState(() => _signed = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Signed card'),
                ),
                SwitchListTile(
                  value: _graded,
                  onChanged: (value) => setState(() => _graded = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Graded card'),
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
    if (_graded &&
        (_gradingCompanyController.text.trim().isEmpty ||
            _gradeController.text.trim().isEmpty ||
            _certificationIdController.text.trim().isEmpty)) {
      setState(
          () => _error = 'Enter grading company, grade and certification ID.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final listing = CardListing.draft(
        card: widget.card,
        sellerUid: widget.sellerUid,
        sellerName: widget.sellerName,
        sellerCountry: 'EU',
        sellerReputationLabel: 'New seller',
        condition: _condition,
        language: _language,
        pricePkn: price,
        quantityAvailable: quantity.clamp(1, 99),
        signed: _signed,
        reverse: _reverse,
        graded: _graded,
        gradingCompany: _graded ? _gradingCompanyController.text.trim() : null,
        grade: _graded ? _gradeController.text.trim() : null,
        certificationId:
            _graded ? _certificationIdController.text.trim() : null,
        shippingAvailable: _shippingAvailable,
        nftAvailable: _nftAvailable,
      );
      await ref.read(cardListingServiceProvider).createListing(listing);
      if (mounted) {
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
}

class _PriceChart extends StatelessWidget {
  const _PriceChart({required this.market});

  final _CardMarketData market;

  @override
  Widget build(BuildContext context) {
    if (!market.hasChart) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF111936),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Text(
          'No price history yet. The chart will populate after seller listings and completed purchases.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF93A4C8), height: 1.45),
        ),
      );
    }
    return LineChart(
      LineChartData(
        minY: market.chartMin,
        maxY: market.chartMax,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withValues(alpha: 0.08),
            strokeWidth: 1,
          ),
        ),
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < market.chart.length; i++)
                FlSpot(i.toDouble(), market.chart[i]),
            ],
            isCurved: true,
            color: const Color(0xFF38BDF8),
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF38BDF8).withValues(alpha: 0.28),
                  const Color(0xFF38BDF8).withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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

  bool get hasListings => listings.isNotEmpty;
  bool get hasChart => chart.isNotEmpty;
  CardListing? get bestListing => hasListings ? listings.first : null;
  String get fiatLabel =>
      hasListings ? '\$${(bestDeal / 16.3).toStringAsFixed(2)}' : '—';
  String get usMarketLabel =>
      hasListings ? '\$${(marketPrice / 16.1).toStringAsFixed(2)}' : '—';
  String get change24hLabel => hasListings
      ? '+${((marketPrice - floorPrice) / floorPrice * 100).toStringAsFixed(2)}%'
      : '—';
  String get spreadLabel => hasListings
      ? '${((bestDeal - bestBid) / bestDeal * 100).toStringAsFixed(2)}%'
      : '—';
  String get liquidityLabel => '${(listings.length * 2.4).toStringAsFixed(1)}x';
  double get chartMin => hasChart ? chart.reduce(math.min) * 0.96 : 0;
  double get chartMax => hasChart ? chart.reduce(math.max) * 1.04 : 1;

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

String _countryFlag(String country) {
  switch (country.toUpperCase()) {
    case 'IT':
      return '🇮🇹';
    case 'FR':
      return '🇫🇷';
    case 'DE':
      return '🇩🇪';
    case 'ES':
      return '🇪🇸';
    case 'US':
      return '🇺🇸';
    case 'JP':
      return '🇯🇵';
    case 'EU':
    default:
      return '🇪🇺';
  }
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

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x1AFACC15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Color(0xFFFDE68A),
              fontSize: 11,
              fontWeight: FontWeight.w900)),
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

class _MetricTile extends StatelessWidget {
  const _MetricTile(
      {required this.title, required this.value, this.accent = false});

  final String title;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (accent)
                const Icon(Icons.trending_up,
                    size: 15, color: Color(0xFFFACC15)),
              if (accent) const SizedBox(width: 4),
              Text(title,
                  style:
                      const TextStyle(color: Color(0xFF93A4C8), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 17)),
        ],
      ),
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

class _TabPill extends StatelessWidget {
  const _TabPill({required this.text, required this.active});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: active ? const Color(0x1AFACC15) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: active
                ? const Color(0x55FACC15)
                : Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: active ? const Color(0xFFFDE68A) : const Color(0xFF93A4C8),
          fontWeight: FontWeight.w900,
        ),
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
  });

  final PokemonCard card;
  final String displayNumber;
  final List<PokemonCard> versionCards;

  @override
  Widget build(BuildContext context) {
    final label = card.itemKind == 'product'
        ? _setAndVariantLabel(card)
        : '${card.set} #$displayNumber';
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
              context.go(cardDetailPath(selected));
            }
          },
        ),
      ),
    );
  }

  String _versionOptionLabel(PokemonCard option) {
    final number = _displayCollectorNumber(option.number);
    return '${option.set} #$number';
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
