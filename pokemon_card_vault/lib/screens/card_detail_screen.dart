import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/pokemon_card.dart';
import '../providers/card_provider.dart';
import '../providers/cart_provider.dart';
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

    if (cardState.isLoading && card == null) {
      return const _DetailScaffold(child: _LoadingDetail());
    }

    if (card == null) {
      return _DetailScaffold(
        child: _NotFoundDetail(
          cardId: cardId,
          onBack: () => context.go('/marketplace'),
        ),
      );
    }

    final market = _CardMarketData.forCard(card);
    final isInCart = ref.watch(cartProvider).isInCart(card.id);

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xF20A1026),
            leading: IconButton(
              onPressed: () => context.go('/marketplace'),
              icon: const Icon(Icons.arrow_back),
            ),
            title: Text(card.name, overflow: TextOverflow.ellipsis),
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
                      _AssetHeader(card: card, market: market),
                      const SizedBox(height: 18),
                      _TopTerminal(
                        card: card,
                        market: market,
                        isInCart: isInCart,
                      ),
                      const SizedBox(height: 18),
                      _MarketStatsGrid(market: market),
                      const SizedBox(height: 18),
                      _ListingsTerminal(card: card, market: market),
                      const SizedBox(height: 18),
                      _Fundamentals(card: card, market: market),
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
  });

  final PokemonCard card;
  final _CardMarketData market;

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
                Text(
                  '${card.set} #${card.number} · ${card.condition} · ${card.type}',
                  style: const TextStyle(color: Color(0xFFB8C4E6)),
                ),
              ],
            ),
          ),
          _QuotePill(label: 'Floor', value: formatPkn(market.floorPrice)),
          _QuotePill(
              label: '24h', value: market.change24hLabel, positive: true),
          IconButton.filledTonal(
            onPressed: () {},
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
  });

  final PokemonCard card;
  final _CardMarketData market;
  final bool isInCart;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 960;
    final artwork = _ArtworkPanel(card: card);
    final center = _MarketCenterPanel(card: card, market: market);
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
  const _ArtworkPanel({required this.card});

  final PokemonCard card;

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
                  onPressed: () {}, icon: const Icon(Icons.chevron_left)),
              _Badge(text: '#${card.number}', color: const Color(0xFF38BDF8)),
              IconButton.filledTonal(
                  onPressed: () {}, icon: const Icon(Icons.chevron_right)),
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 0.72,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                color: const Color(0xFF111936),
                child: CachedNetworkImage(
                  imageUrl: card.imageUrl,
                  fit: BoxFit.contain,
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
          _SelectorLike(label: '${card.set} #${card.number}'),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {},
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
  });

  final PokemonCard card;
  final _CardMarketData market;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _TabPill(text: 'Info', active: true),
              SizedBox(width: 8),
              _TabPill(text: 'Sell', active: false),
              SizedBox(width: 8),
              _TabPill(text: 'Markets', active: false),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _MetricTile(
                  title: 'CT Min Price',
                  value: formatPkn(market.floorPrice),
                  accent: true),
              _MetricTile(
                  title: 'CT Market Price',
                  value: formatPkn(market.marketPrice)),
              _MetricTile(
                  title: 'US Market Price', value: market.usMarketLabel),
            ],
          ),
          const SizedBox(height: 20),
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
                formatPkn(market.bestDeal),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                '~${market.fiatLabel} · spread ${market.spreadLabel}',
                style: const TextStyle(color: Color(0xFF93A4C8)),
              ),
              const SizedBox(height: 16),
              const _SelectorLike(label: 'EN · English'),
              const SizedBox(height: 8),
              const _SelectorLike(label: 'NM · Near Mint'),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: card.stock > 0
                    ? () => ref.read(cartProvider.notifier).addToCart(card)
                    : null,
                icon: Icon(
                    isInCart ? Icons.shopping_bag : Icons.add_shopping_cart),
                label: Text(card.stock > 0
                    ? (isInCart ? 'In cart' : 'Add to cart')
                    : 'Preview order book'),
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
                  label: 'Estimated total', value: formatPkn(market.bestDeal)),
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
      ('Market cap', formatPkn(market.marketCap), '+4.2%'),
      ('Volume 24h', formatPkn(market.volume24h), '+18.6%'),
      ('Listings', '${market.listings.length}', 'live'),
      ('Liquidity', market.liquidityLabel, 'depth'),
      ('Best bid', formatPkn(market.bestBid), 'PKN'),
      ('Best ask', formatPkn(market.bestDeal), market.spreadLabel),
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

class _ListingsTerminal extends StatelessWidget {
  const _ListingsTerminal({
    required this.card,
    required this.market,
  });

  final PokemonCard card;
  final _CardMarketData market;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    final filters = _ListingFilters(market: market);
    final table = _ListingsTable(market: market);

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
}

class _ListingFilters extends StatelessWidget {
  const _ListingFilters({required this.market});

  final _CardMarketData market;

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
          const _FilterGroup(title: 'Price (PKN)', children: [
            _InputGhost(text: 'min'),
            SizedBox(height: 8),
            _InputGhost(text: 'max'),
          ]),
          const SizedBox(height: 16),
          const _FilterGroup(
            title: 'Condition',
            children: [
              _CheckGhost(text: 'Near Mint', checked: true),
              _CheckGhost(text: 'Slightly Played'),
              _CheckGhost(text: 'Moderately Played'),
              _CheckGhost(text: 'Played'),
              _CheckGhost(text: 'Poor'),
            ],
          ),
          const SizedBox(height: 16),
          const _FilterGroup(
            title: 'Language',
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _CheckGhost(text: 'EN', checked: true),
                  _CheckGhost(text: 'IT'),
                  _CheckGhost(text: 'FR'),
                  _CheckGhost(text: 'DE'),
                  _CheckGhost(text: 'ES'),
                  _CheckGhost(text: 'JP'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _FilterGroup(
            title: 'Extra',
            children: [
              _CheckGhost(text: 'Signed'),
              _CheckGhost(text: 'Altered/misprint'),
              _CheckGhost(text: 'Graded'),
              _CheckGhost(text: 'Pokoin Card Reserve', checked: true),
            ],
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () {},
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
  const _ListingsTable({required this.market});

  final _CardMarketData market;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      clip: true,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF111B3F),
            child: const Row(
              children: [
                Expanded(flex: 3, child: _HeaderText('Seller')),
                Expanded(flex: 3, child: _HeaderText('Product')),
                Expanded(flex: 2, child: _HeaderText('Price')),
                Expanded(child: _HeaderText('Qty')),
                SizedBox(width: 126, child: _HeaderText('RESERVE')),
              ],
            ),
          ),
          for (final listing in market.listings) _ListingRow(listing: listing),
        ],
      ),
    );
  }
}

class _ListingRow extends StatelessWidget {
  const _ListingRow({required this.listing});

  final _Listing listing;

  @override
  Widget build(BuildContext context) {
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
                    Text(listing.flag, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        listing.seller,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text('★ ${listing.reputation}',
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
                if (listing.signed) const _TinyBadge(text: 'Signed'),
                if (listing.reserve) const _TinyBadge(text: 'Reserve'),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatPkn(listing.price),
              style: const TextStyle(
                  color: Color(0xFFFACC15), fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: Text(
              '1 of ${listing.quantity}',
              style: const TextStyle(color: Color(0xFFB8C4E6)),
            ),
          ),
          SizedBox(
            width: 126,
            child: Row(
              children: [
                if (listing.reserve)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFACC15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('RESERVE',
                        style: TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 11,
                            fontWeight: FontWeight.w900)),
                  )
                else
                  const SizedBox(width: 48),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () {},
                  icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Fundamentals extends StatelessWidget {
  const _Fundamentals({
    required this.card,
    required this.market,
  });

  final PokemonCard card;
  final _CardMarketData market;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Card metadata',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Fundamental(label: 'Set', value: card.set),
              _Fundamental(label: 'Number', value: card.number),
              _Fundamental(label: 'Rarity', value: card.rarity),
              const _Fundamental(label: 'Game', value: 'Pokémon'),
              _Fundamental(label: 'Blueprint ID', value: card.id),
              const _Fundamental(
                  label: 'Condition model', value: 'NM / SP / MP / PL / Poor'),
              const _Fundamental(
                  label: 'Languages', value: 'EN, IT, FR, DE, ES +'),
              _Fundamental(
                  label: 'Reserve asset', value: 'PKN-RESERVE-${card.id}'),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'This panel only shows metadata available from the imported CardTrader blueprint catalog. Artist, release date, card text and social watchlist metrics are intentionally omitted until a verified source is connected.',
            style: TextStyle(color: Color(0xFFB8C4E6), height: 1.55),
          ),
        ],
      ),
    );
  }
}

class _PriceChart extends StatelessWidget {
  const _PriceChart({required this.market});

  final _CardMarketData market;

  @override
  Widget build(BuildContext context) {
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
  final List<_Listing> listings;

  String get fiatLabel => '\$${(bestDeal / 16.3).toStringAsFixed(2)}';
  String get usMarketLabel => '\$${(marketPrice / 16.1).toStringAsFixed(2)}';
  String get change24hLabel =>
      '+${((marketPrice - floorPrice) / floorPrice * 100).toStringAsFixed(2)}%';
  String get spreadLabel =>
      '${((bestDeal - bestBid) / bestDeal * 100).toStringAsFixed(2)}%';
  String get liquidityLabel => '${(listings.length * 2.4).toStringAsFixed(1)}x';
  double get chartMin => chart.reduce(math.min) * 0.96;
  double get chartMax => chart.reduce(math.max) * 1.04;

  static _CardMarketData forCard(PokemonCard card) {
    final seed = _seed(card.id);
    final base = math.max(card.price, 500) * (0.92 + (seed % 13) / 100);
    final listings = _buildListings(base, seed);
    final floor = listings.map((listing) => listing.price).reduce(math.min);
    final market = base * 1.08;

    return _CardMarketData(
      floorPrice: floor,
      marketPrice: market,
      bestDeal: floor,
      bestBid: floor * 0.964,
      volume24h: market * (7 + seed % 11),
      marketCap: market * (850 + seed % 400),
      chart: _buildChart(market, seed),
      listings: listings,
    );
  }

  static int _seed(String value) {
    return value.codeUnits.fold(17, (sum, unit) => sum + unit * 31);
  }

  static List<double> _buildChart(double base, int seed) {
    return List.generate(32, (index) {
      final wave = math.sin((index + seed % 7) / 3.1) * 0.06;
      final drift = (index - 16) * 0.002;
      final shock = index == 23 ? -0.08 : 0.0;
      return base * (1 + wave + drift + shock);
    });
  }

  static List<_Listing> _buildListings(double base, int seed) {
    final sellers = [
      ('YamiWolf', '🇮🇹', '22K'),
      ('OnyTCG', '🇮🇹', '2.3K'),
      ('Nick-04', '🇫🇷', '1K'),
      ('KrakenCards', '🇮🇹', '5.3K'),
      ('Magic Maze', '🇫🇷', '8.8K'),
      ('Pixelpartita', '🇮🇹', '2.7K'),
      ('PokoinDesk', '🇪🇺', '31K'),
      ('ManaStore', '🇩🇪', '5.6K'),
    ];

    return List.generate(sellers.length, (index) {
      final seller = sellers[index];
      return _Listing(
        seller: seller.$1,
        flag: seller.$2,
        reputation: seller.$3,
        condition: index == 5 ? 'SP' : 'NM',
        language: ['EN', 'IT', 'FR', 'DE'][index % 4],
        price: base * (1 + index * 0.018 + (seed % 5) / 1000),
        quantity: 1 + (index % 2),
        reserve: index % 3 != 2,
        signed: index == 4,
      );
    });
  }
}

class _Listing {
  const _Listing({
    required this.seller,
    required this.flag,
    required this.reputation,
    required this.condition,
    required this.language,
    required this.price,
    required this.quantity,
    required this.reserve,
    required this.signed,
  });

  final String seller;
  final String flag;
  final String reputation;
  final String condition;
  final String language;
  final double price;
  final int quantity;
  final bool reserve;
  final bool signed;
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

class _InputGhost extends StatelessWidget {
  const _InputGhost({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFF64748B))),
    );
  }
}

class _CheckGhost extends StatelessWidget {
  const _CheckGhost({required this.text, this.checked = false});

  final String text;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          checked ? Icons.check_box : Icons.check_box_outline_blank,
          color: checked ? const Color(0xFFFACC15) : const Color(0xFF64748B),
          size: 17,
        ),
        const SizedBox(width: 5),
        Text(text,
            style: const TextStyle(color: Color(0xFFB8C4E6), fontSize: 13)),
      ],
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

class _Fundamental extends StatelessWidget {
  const _Fundamental({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
