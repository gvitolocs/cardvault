import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/card_listing.dart';
import '../models/pokemon_card.dart';
import '../providers/card_listing_provider.dart';
import '../providers/card_provider.dart';
import '../utils/price_format.dart';

class MarketplaceSignalScreen extends ConsumerWidget {
  const MarketplaceSignalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardState = ref.watch(cardProvider);
    final listingsState = ref.watch(activeCardListingsProvider);
    final listings = listingsState.valueOrNull ?? const <CardListing>[];
    final signal = _MarketplaceSignal.from(
      cards: cardState.cards,
      listings: listings,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xE60A1026),
            title: const Text('Marketplace Signal'),
            actions: [
              TextButton(
                onPressed: () => context.go('/marketplace'),
                child: const Text('Marketplace'),
              ),
              TextButton(
                onPressed: () => context.go('/wallet'),
                child: const Text('Wallet'),
              ),
              const SizedBox(width: 12),
            ],
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1220),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: cardState.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(48),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SignalHero(
                              signal: signal,
                              listingsLoading: listingsState.isLoading,
                            ),
                            const SizedBox(height: 18),
                            _SignalMetrics(signal: signal),
                            const SizedBox(height: 18),
                            _SignalBreakdown(signal: signal),
                            const SizedBox(height: 18),
                            const _SignalIntegrityNote(),
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
}

class _SignalHero extends StatelessWidget {
  const _SignalHero({
    required this.signal,
    required this.listingsLoading,
  });

  final _MarketplaceSignal signal;
  final bool listingsLoading;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Pill('Card Reserve analytics'),
        const SizedBox(height: 18),
        Text(
          'Live marketplace signal from real catalog and seller listings.',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                height: 1.02,
              ),
        ),
        const SizedBox(height: 14),
        const Text(
          'This dashboard now uses loaded marketplace rows and active Firestore seller listings. Catalog coverage, product mix, seller depth and asks are shown from live data; volume stays empty until completed orders are aggregated.',
          style: TextStyle(
            color: Color(0xFFB8C4E6),
            fontSize: 16,
            height: 1.55,
          ),
        ),
      ],
    );

    final pulse = _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current status',
            style: TextStyle(
              color: Color(0xFFFDE68A),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          _PulseRow(label: 'Catalog items', value: '${signal.totalCards}'),
          _PulseRow(label: 'Active listings', value: '${signal.listingCount}'),
          _PulseRow(
            label: 'Listed quantity',
            value: '${signal.availableQuantity}',
          ),
          _PulseRow(label: 'Floor ask', value: signal.floorAskLabel),
          const SizedBox(height: 14),
          Text(
            listingsLoading
                ? 'Loading seller listings...'
                : 'Completed sale volume is intentionally not shown until order settlement events are aggregated.',
            style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
          ),
        ],
      ),
    );

    return _Panel(
      padding: const EdgeInsets.all(26),
      gradient: const RadialGradient(
        center: Alignment.topRight,
        radius: 1.35,
        colors: [Color(0x2238BDF8), Color(0x00050816)],
      ),
      child: wide
          ? Row(
              children: [
                Expanded(flex: 6, child: copy),
                const SizedBox(width: 26),
                Expanded(flex: 4, child: pulse),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [copy, const SizedBox(height: 22), pulse],
            ),
    );
  }
}

class _SignalMetrics extends StatelessWidget {
  const _SignalMetrics({required this.signal});

  final _MarketplaceSignal signal;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _MetricCard(
          label: 'Catalog rows',
          value: '${signal.totalCards}',
          detail:
              '${signal.singleCount} singles · ${signal.productCount} products',
          icon: Icons.inventory_2_outlined,
        ),
        _MetricCard(
          label: 'Cards with images',
          value: signal.imageCoverageLabel,
          detail: '${signal.withImages} items you can visually check',
          icon: Icons.image_outlined,
        ),
        _MetricCard(
          label: 'Seller listings',
          value: '${signal.listingCount}',
          detail:
              '${signal.sellerCount} sellers · ${signal.availableQuantity} quantity',
          icon: Icons.storefront_outlined,
        ),
        _MetricCard(
          label: 'Listed ask value',
          value: signal.totalAskLabel,
          detail: 'Active seller listings only',
          icon: Icons.price_change_outlined,
        ),
        _MetricCard(
          label: 'Median ask',
          value: signal.medianAskLabel,
          detail: signal.spreadLabel,
          icon: Icons.show_chart,
        ),
        _MetricCard(
          label: 'Expansion coverage',
          value: '${signal.expansionCount}',
          detail: 'Unique sets in loaded marketplace rows',
          icon: Icons.hub_outlined,
        ),
      ],
    );
  }
}

class _SignalBreakdown extends StatelessWidget {
  const _SignalBreakdown({required this.signal});

  final _MarketplaceSignal signal;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 850;
    final children = [
      _RankPanel(
        title: 'Top expansions in catalog',
        rows: signal.topExpansions,
      ),
      _RankPanel(
        title: 'Top product types',
        rows: signal.topProductTypes,
      ),
      _RankPanel(
        title: 'Top listed cards',
        rows: signal.topListedCards,
      ),
    ];

    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final child in children) ...[
                Expanded(child: child),
                if (child != children.last) const SizedBox(width: 14),
              ],
            ],
          )
        : Column(
            children: [
              for (final child in children) ...[
                child,
                if (child != children.last) const SizedBox(height: 14),
              ],
            ],
          );
  }
}

class _SignalIntegrityNote extends StatelessWidget {
  const _SignalIntegrityNote();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What this is showing',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Catalog metrics come from marketplace projection rows. Listing metrics come from active seller listing documents. Completed sales, 24h volume and historical charts are still hidden until settled order events are wired into this dashboard.',
            style: TextStyle(color: Color(0xFFB8C4E6), height: 1.55),
          ),
          SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SignalChip(
                icon: Icons.inventory_2_outlined,
                label: 'Catalog coverage is real',
              ),
              _SignalChip(
                icon: Icons.receipt_long_outlined,
                label: 'Volume still requires completed orders',
              ),
              _SignalChip(
                icon: Icons.sell_outlined,
                label: 'Floor uses active seller listings',
              ),
              _SignalChip(
                icon: Icons.query_stats,
                label: 'Charts require event history',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        gradient: gradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PulseRow extends StatelessWidget {
  const _PulseRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF93A4C8))),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 385,
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFFACC15), size: 26),
            const SizedBox(height: 16),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFFDE68A),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              style: const TextStyle(color: Color(0xFF93A4C8), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankPanel extends StatelessWidget {
  const _RankPanel({
    required this.title,
    required this.rows,
  });

  final String title;
  final List<_RankRow> rows;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const Text(
              'No live rows yet',
              style: TextStyle(color: Color(0xFF93A4C8)),
            )
          else
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFE5E7EB),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      row.value,
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
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFFACC15), size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFE5E7EB),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketplaceSignal {
  const _MarketplaceSignal({
    required this.totalCards,
    required this.singleCount,
    required this.productCount,
    required this.withImages,
    required this.expansionCount,
    required this.listingCount,
    required this.availableQuantity,
    required this.sellerCount,
    required this.floorAsk,
    required this.medianAsk,
    required this.totalAsk,
    required this.topExpansions,
    required this.topProductTypes,
    required this.topListedCards,
  });

  final int totalCards;
  final int singleCount;
  final int productCount;
  final int withImages;
  final int expansionCount;
  final int listingCount;
  final int availableQuantity;
  final int sellerCount;
  final double? floorAsk;
  final double? medianAsk;
  final double totalAsk;
  final List<_RankRow> topExpansions;
  final List<_RankRow> topProductTypes;
  final List<_RankRow> topListedCards;

  String get imageCoverageLabel {
    if (totalCards == 0) {
      return '0%';
    }
    return '${((withImages / totalCards) * 100).round()}%';
  }

  String get floorAskLabel => floorAsk == null ? '—' : formatPkn(floorAsk!);

  String get medianAskLabel => medianAsk == null ? '—' : formatPkn(medianAsk!);

  String get totalAskLabel =>
      totalAsk <= 0 ? '—' : formatPkn(totalAsk, decimals: 0);

  String get spreadLabel {
    if (floorAsk == null || medianAsk == null) {
      return 'No active ask spread yet';
    }
    return 'Floor ${formatPkn(floorAsk!)} · median ${formatPkn(medianAsk!)}';
  }

  static _MarketplaceSignal from({
    required List<PokemonCard> cards,
    required List<CardListing> listings,
  }) {
    final activeListings = listings
        .where((listing) => listing.isActive && listing.pricePkn > 0)
        .toList()
      ..sort((a, b) => a.pricePkn.compareTo(b.pricePkn));
    final prices = activeListings.map((listing) => listing.pricePkn).toList();
    final totalAsk = activeListings.fold<double>(
      0,
      (sum, listing) => sum + listing.pricePkn * listing.quantityAvailable,
    );
    final topListed = activeListings.take(5).map((listing) {
      final title = [
        listing.cardName.isEmpty ? listing.cardId : listing.cardName,
        if (listing.collectorNumber.trim().isNotEmpty) listing.collectorNumber,
      ].join(' ');
      return _RankRow(title, formatPkn(listing.pricePkn));
    }).toList();

    final expansions = <String, int>{};
    final productTypes = <String, int>{};
    var singleCount = 0;
    var productCount = 0;
    var withImages = 0;
    for (final card in cards) {
      if (card.itemKind == 'product') {
        productCount += 1;
        final productType = card.productType.trim().isEmpty
            ? card.type
            : card.productType.replaceAll('_', ' ');
        productTypes[productType] = (productTypes[productType] ?? 0) + 1;
      } else {
        singleCount += 1;
      }
      if (card.imageUrl.trim().isNotEmpty ||
          card.previewImageUrl.trim().isNotEmpty) {
        withImages += 1;
      }
      final set = card.set.trim();
      if (set.isNotEmpty) {
        expansions[set] = (expansions[set] ?? 0) + 1;
      }
    }

    return _MarketplaceSignal(
      totalCards: cards.length,
      singleCount: singleCount,
      productCount: productCount,
      withImages: withImages,
      expansionCount: expansions.length,
      listingCount: activeListings.length,
      availableQuantity: activeListings.fold<int>(
        0,
        (sum, listing) => sum + listing.quantityAvailable,
      ),
      sellerCount:
          activeListings.map((listing) => listing.sellerUid).toSet().length,
      floorAsk: prices.isEmpty ? null : prices.first,
      medianAsk: _median(prices),
      totalAsk: totalAsk,
      topExpansions: _topRows(expansions),
      topProductTypes: _topRows(productTypes),
      topListedCards: topListed,
    );
  }

  static double? _median(List<double> values) {
    if (values.isEmpty) {
      return null;
    }
    final middle = values.length ~/ 2;
    if (values.length.isOdd) {
      return values[middle];
    }
    return (values[middle - 1] + values[middle]) / 2;
  }

  static List<_RankRow> _topRows(Map<String, int> counts) {
    final rows = counts.entries.toList()
      ..sort((a, b) {
        final count = b.value.compareTo(a.value);
        if (count != 0) {
          return count;
        }
        return a.key.compareTo(b.key);
      });
    return rows
        .take(5)
        .map((entry) => _RankRow(entry.key, '${entry.value}'))
        .toList();
  }
}

class _RankRow {
  const _RankRow(this.label, this.value);

  final String label;
  final String value;
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x1AFACC15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x55FACC15)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFFDE68A),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
