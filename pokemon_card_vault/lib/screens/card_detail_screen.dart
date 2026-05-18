import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/card_listing.dart';
import '../models/pokemon_card.dart';
import '../providers/auth_provider.dart';
import '../providers/card_listing_provider.dart';
import '../providers/card_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/recent_views_provider.dart';
import '../services/card_service.dart';
import '../utils/price_format.dart';

class CardDetailScreen extends ConsumerWidget {
  final String cardId;

  const CardDetailScreen({
    super.key,
    required this.cardId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardState = ref.watch(cardProvider);
    final card = _findCard(cardState.cards, cardId);
    final directCardState =
        card == null ? ref.watch(_cardDetailByIdProvider(cardId)) : null;
    final directCard = directCardState?.valueOrNull;
    final resolvedCard = card ?? directCard;

    if ((cardState.isLoading || (directCardState?.isLoading ?? false)) &&
        resolvedCard == null) {
      return const _DetailScaffold(child: _LoadingDetail());
    }

    if (resolvedCard == null) {
      return _DetailScaffold(
        child: _NotFoundDetail(
          cardId: cardId,
          onBack: () => _goBackOr(context, '/marketplace'),
        ),
      );
    }

    final listingsState = ref.watch(cardListingsProvider(resolvedCard.id));
    final listings = listingsState.valueOrNull ?? const <CardListing>[];
    final market = _CardMarketData.forCard(resolvedCard, listings);
    final bestListing = market.bestListing;
    final cartState = ref.watch(cartProvider);
    final isInCart = bestListing == null
        ? cartState.isInCart(resolvedCard.id)
        : cartState.isListingInCart(bestListing.id);
    final expansionCardsState =
        ref.watch(_expansionVersionCardsProvider(resolvedCard));
    final expansionCards = expansionCardsState.valueOrNull ?? const [];
    final previousId = _adjacentExpansionCardId(
      expansionCards,
      resolvedCard.id,
      direction: -1,
    );
    final nextId = _adjacentExpansionCardId(
      expansionCards,
      resolvedCard.id,
      direction: 1,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xF20A1026),
            leading: IconButton(
              onPressed: () => _goBackOr(context, '/marketplace'),
              icon: const Icon(Icons.arrow_back),
            ),
            title: Text(resolvedCard.name, overflow: TextOverflow.ellipsis),
            actions: [
              TextButton.icon(
                onPressed: () => context.go('/wallet'),
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Wallet'),
              ),
              const SizedBox(width: 10),
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
                        onSell: () =>
                            _openSellDialog(context, ref, resolvedCard),
                        onWishlist: () => ref
                            .read(favoritesProvider.notifier)
                            .toggleFavorite(resolvedCard.id),
                      ),
                      const SizedBox(height: 18),
                      _TopTerminal(
                        card: resolvedCard,
                        market: market,
                        isInCart: isInCart,
                        onSell: () =>
                            _openSellDialog(context, ref, resolvedCard),
                        onPrevious: previousId == null
                            ? null
                            : () => context.go('/card/$previousId'),
                        onNext: nextId == null
                            ? null
                            : () => context.go('/card/$nextId'),
                        onViewAllVersions: () => context.go(
                          Uri(
                            path: '/marketplace/search',
                            queryParameters: {'q': resolvedCard.name},
                          ).toString(),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _MarketStatsGrid(market: market),
                      const SizedBox(height: 18),
                      _ListingsTerminal(
                        card: resolvedCard,
                        market: market,
                        isLoading: listingsState.isLoading,
                        onSell: () =>
                            _openSellDialog(context, ref, resolvedCard),
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

  PokemonCard? _findCard(List<PokemonCard> cards, String id) {
    for (final card in cards) {
      if (card.id == id) {
        return card;
      }
    }
    return null;
  }

  String? _adjacentExpansionCardId(
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
    return adjacent.id == currentId ? null : adjacent.id;
  }

  void _openSellDialog(
    BuildContext context,
    WidgetRef ref,
    PokemonCard card,
  ) {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      context.go('/auth');
      return;
    }
    final profile = ref.read(userProfileProvider).valueOrNull;
    showDialog(
      context: context,
      builder: (context) => _SellListingDialog(
        card: card,
        sellerUid: user.uid,
        sellerName: profile?.displayName.trim().isNotEmpty == true
            ? profile!.displayName
            : user.displayName ?? user.email ?? 'Pokoin seller',
      ),
    );
  }
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

class _AssetHeader extends StatelessWidget {
  const _AssetHeader({
    required this.card,
    required this.market,
    required this.onSell,
    required this.onWishlist,
  });

  final PokemonCard card;
  final _CardMarketData market;
  final VoidCallback onSell;
  final VoidCallback onWishlist;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Wrap(
        spacing: 16,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const _Badge(text: 'Pokémon', color: Color(0xFF38BDF8)),
          _Badge(text: card.rarity, color: const Color(0xFFFACC15)),
          if (card.itemKind == 'product')
            _Badge(text: card.type, color: const Color(0xFFA78BFA)),
          if (card.isHolo) const _Badge(text: 'Holo', color: Color(0xFFA78BFA)),
          SizedBox(
            width: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.name,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
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
                      ' #${card.number} · ${card.condition} · ${card.type}',
                      style: const TextStyle(color: Color(0xFFB8C4E6)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _QuotePill(
              label: 'Floor',
              value: market.hasListings ? formatPkn(market.floorPrice) : '—'),
          _QuotePill(
              label: '24h', value: market.change24hLabel, positive: true),
          FilledButton.icon(
            onPressed: onSell,
            icon: const Icon(Icons.sell_outlined, size: 18),
            label: const Text('Sell'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: const Color(0xFF07111F),
            ),
          ),
          IconButton.filledTonal(
            onPressed: onWishlist,
            icon: const Icon(Icons.favorite_border),
            tooltip: 'Add to wishlist',
          ),
          IconButton.filledTonal(
            onPressed: () {},
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share',
          ),
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
    required this.onViewAllVersions,
  });

  final PokemonCard card;
  final _CardMarketData market;
  final bool isInCart;
  final VoidCallback onSell;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onViewAllVersions;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 960;
    final artwork = _ArtworkPanel(
      card: card,
      onPrevious: onPrevious,
      onNext: onNext,
      onViewAllVersions: onViewAllVersions,
    );
    final center = _MarketCenterPanel(
      card: card,
      market: market,
      onSell: onSell,
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
    required this.onPrevious,
    required this.onNext,
    required this.onViewAllVersions,
  });

  final PokemonCard card;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onViewAllVersions;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton.filledTonal(
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous card',
              ),
              Flexible(
                child: _Badge(
                  text: card.number,
                  color: const Color(0xFF38BDF8),
                ),
              ),
              IconButton.filledTonal(
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
                color: const Color(0xFF111936),
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
          const SizedBox(height: 12),
          _SelectorLike(label: '${card.set} #${card.number}'),
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

class _MarketCenterPanel extends StatelessWidget {
  const _MarketCenterPanel({
    required this.card,
    required this.market,
    required this.onSell,
  });

  final PokemonCard card;
  final _CardMarketData market;
  final VoidCallback onSell;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _TabPill(text: 'Info', active: true),
              const SizedBox(width: 8),
              InkWell(
                onTap: onSell,
                borderRadius: BorderRadius.circular(999),
                child: const _TabPill(text: 'Sell', active: false),
              ),
              const SizedBox(width: 8),
              const _TabPill(text: 'Markets', active: false),
            ],
          ),
          const SizedBox(height: 18),
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
          const SizedBox(height: 20),
          const Text(
            'Pokoin conditions',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          const _ConditionGuide(),
        ],
      ),
    );
  }
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
    return Column(
      children: [
        _Panel(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Best Deal',
                  style: TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.w800)),
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
                        ref
                            .read(cartProvider.notifier)
                            .addListingToCart(card, bestListing);
                        ref.read(cardProvider.notifier).recordCardInteraction(
                              card,
                              'cart_add',
                              source: 'detail_buy_box',
                            );
                      },
                icon: Icon(
                    isInCart ? Icons.shopping_bag : Icons.add_shopping_cart),
                label: Text(isInCart ? 'In cart' : 'Add to cart'),
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
    required this.onSell,
    required this.onWishlist,
  });

  final PokemonCard card;
  final _CardMarketData market;
  final bool isLoading;
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
      onSell: widget.onSell,
      onWishlist: widget.onWishlist,
      onClearFilters: _clearFilters,
    );

    if (!wide) {
      return Column(
        children: [
          filters,
          const SizedBox(height: 14),
          table,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 240, child: filters),
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
                  for (final language in const [
                    'EN',
                    'IT',
                    'FR',
                    'DE',
                    'ES',
                    'JP'
                  ])
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

class _ListingsTable extends StatelessWidget {
  const _ListingsTable({
    required this.card,
    required this.market,
    required this.listings,
    required this.totalListings,
    required this.isLoading,
    required this.sort,
    required this.onSortChanged,
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
  final VoidCallback onSell;
  final VoidCallback onWishlist;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF111B3F),
            child: const Row(
              children: [
                Expanded(flex: 3, child: _HeaderText('Seller')),
                Expanded(flex: 3, child: _HeaderText('Product')),
                Expanded(flex: 2, child: _HeaderText('Price')),
                Expanded(child: _HeaderText('Qty')),
                SizedBox(width: 188, child: _HeaderText('SHIPPING')),
              ],
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: Color(0xFFFACC15)),
            )
          else if (market.listings.isEmpty)
            _NoListingsState(onSell: onSell, onWishlist: onWishlist)
          else if (listings.isEmpty)
            _NoFilteredListingsState(onClear: onClearFilters)
          else
            for (final listing in listings)
              _ListingRow(card: card, listing: listing),
        ],
      ),
    );
  }
}

class _ListingRow extends ConsumerWidget {
  const _ListingRow({
    required this.card,
    required this.listing,
  });

  final PokemonCard card;
  final CardListing listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCart = ref.watch(cartProvider).isListingInCart(listing.id);
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
                IconButton.filledTonal(
                  onPressed: () {
                    ref
                        .read(cartProvider.notifier)
                        .addListingToCart(card, listing);
                    ref.read(cardProvider.notifier).recordCardInteraction(
                          card,
                          'cart_add',
                          source: 'listing_row',
                        );
                  },
                  icon: Icon(
                    inCart ? Icons.shopping_bag : Icons.shopping_cart_outlined,
                    size: 18,
                  ),
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

class _NoListingsState extends StatelessWidget {
  const _NoListingsState({
    required this.onSell,
    required this.onWishlist,
  });

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
                icon: const Icon(Icons.favorite_border),
                label: const Text('Add to wishlist'),
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
  });

  final PokemonCard card;
  final String sellerUid;
  final String sellerName;

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
    _priceController.text =
        widget.card.price > 0 ? widget.card.price.toStringAsFixed(0) : '1000';
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
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: const TextStyle(color: Color(0xFF93A4C8)),
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
                  decoration: const InputDecoration(
                    labelText: 'Price in PKN',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
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
                        decoration: const InputDecoration(
                          labelText: 'Language',
                          border: OutlineInputBorder(),
                        ),
                        items: const ['EN', 'IT', 'FR', 'DE', 'ES', 'JP']
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
  });

  final Widget child;
  final EdgeInsets padding;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
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

class _ConditionGuide extends StatelessWidget {
  const _ConditionGuide();

  @override
  Widget build(BuildContext context) {
    const rows = [
      (
        'NM',
        'Near Mint',
        'Almost perfect. No visible damage; possible light surface imperfections.'
      ),
      (
        'SP',
        'Slightly Played',
        'Minimal signs of use. Overall good appearance with minor flaws.'
      ),
      (
        'MP',
        'Moderately Played',
        'Noticeable defects or light damage. Still collectible and playable.'
      ),
      (
        'PL',
        'Played',
        'Significant wear with multiple flaws. Aesthetic damage but not structural.'
      ),
    ];
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TinyBadge(text: row.$1),
                const SizedBox(width: 9),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                            text: '${row.$2}: ',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800)),
                        TextSpan(text: row.$3),
                      ],
                    ),
                    style:
                        const TextStyle(color: Color(0xFFB8C4E6), height: 1.35),
                  ),
                ),
              ],
            ),
          ),
      ],
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
