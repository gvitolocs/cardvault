import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/project_links.dart';
import '../models/pokemon_card.dart';
import '../providers/auth_provider.dart';
import '../providers/card_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../utils/price_format.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _inventoryKey = GlobalKey();
  final List<_MarketFilter> _quickFilters = const [
    _MarketFilter(label: 'Holo grails', rarity: 'Rare Holo'),
    _MarketFilter(label: 'Lightning', type: 'Lightning'),
    _MarketFilter(label: 'Fire icons', type: 'Fire'),
    _MarketFilter(label: 'Under 100 PKN', maxPrice: 100),
    _MarketFilter(label: 'Unavailable', inStock: true),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    final balance = ref.watch(pknBalanceProvider).valueOrNull ?? 0;
    final cards = cardState.filteredCards;
    final featured = cards.isNotEmpty
        ? cards.take(3).toList()
        : cardState.cards.take(3).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xE60A1026),
            title: const Text('CardVault Marketplace'),
            actions: [
              TextButton(
                  onPressed: () => context.go('/'), child: const Text('Home')),
              TextButton(
                  onPressed: () => context.go('/scan'),
                  child: const Text('Scan')),
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
                      _HeroSection(
                        totalCards: cardState.cards.length,
                        cartCount: cartState.itemCount,
                        totalVolume: _marketValue(cardState.cards),
                        onBrowseInventory: _scrollToInventory,
                        onOpenWallet: _openWallet,
                      ),
                      const SizedBox(height: 24),
                      const _TrustStrip(),
                      const SizedBox(height: 24),
                      _SearchAndControls(
                        controller: _searchController,
                        state: cardState,
                        quickFilters: _quickFilters,
                        onSearch: (value) =>
                            ref.read(cardProvider.notifier).searchCards(value),
                        onSort: (value) =>
                            ref.read(cardProvider.notifier).sortCards(value),
                        onFilter: _applyFilter,
                        onClear: () {
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
                        _FeaturedRow(cards: featured),
                        const SizedBox(height: 24),
                        KeyedSubtree(
                          key: _inventoryKey,
                          child: _MarketHeader(count: cards.length),
                        ),
                        const SizedBox(height: 16),
                        _MarketplaceGrid(cards: cards),
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
    if (filter.rarity != null) {
      notifier.filterByRarity(filter.rarity!);
    }
    if (filter.type != null) {
      notifier.filterByType(filter.type!);
    }
    if (filter.maxPrice != null) {
      notifier.filterByPriceRange(0, filter.maxPrice!);
    }
    if (filter.inStock) {
      final state = ref.read(cardProvider);
      if (!state.showOnlyInStock) {
        notifier.toggleInStockFilter();
      }
    }
  }

  double _marketValue(List<PokemonCard> cards) {
    return cards.fold(0, (sum, card) => sum + card.price);
  }

  void _scrollToInventory() {
    final target = _inventoryKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
      return;
    }

    _scrollController.animateTo(
      720,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openWallet() async {
    await launchUrl(
      Uri.parse('${ProjectLinks.website}/wallet'),
      webOnlyWindowName: '_self',
    );
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

class _HeroSection extends StatelessWidget {
  final int totalCards;
  final int cartCount;
  final double totalVolume;
  final VoidCallback onBrowseInventory;
  final VoidCallback onOpenWallet;

  const _HeroSection({
    required this.totalCards,
    required this.cartCount,
    required this.totalVolume,
    required this.onBrowseInventory,
    required this.onOpenWallet,
  });

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Pill('Preview'),
        const SizedBox(height: 18),
        Text(
          'Buy rare cards with collector-grade confidence.',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                height: 1.02,
              ),
        ),
        const SizedBox(height: 16),
        const Text(
          'CardVault combines premium Pokémon card discovery with PKN payment rails, reserve transparency, and a marketplace experience designed for serious collectors.',
          style:
              TextStyle(color: Color(0xFFB8C4E6), fontSize: 17, height: 1.55),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onBrowseInventory,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Browse inventory'),
            ),
            OutlinedButton.icon(
              onPressed: onOpenWallet,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Open PKN wallet'),
            ),
          ],
        ),
      ],
    );

    final panel = Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 34, offset: Offset(0, 18)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Marketplace signal',
              style: TextStyle(
                  color: Color(0xFFFDE68A), fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          _HeroMetric(label: 'Listed cards', value: '$totalCards'),
          _HeroMetric(label: 'Cart items', value: '$cartCount'),
          _HeroMetric(
              label: 'Listed value',
              value: formatPkn(totalVolume, decimals: 0)),
          const Divider(color: Color(0x22FFFFFF), height: 30),
          const Text(
            'Listed cards are priced in PKN and currently marked unavailable until shop settlement opens.',
            style: TextStyle(color: Color(0xFFB8C4E6), height: 1.5),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          center: Alignment.topRight,
          radius: 1.4,
          colors: [Color(0x2238BDF8), Color(0x00050816)],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: wide
          ? Row(
              children: [
                Expanded(flex: 6, child: copy),
                const SizedBox(width: 28),
                Expanded(flex: 4, child: panel),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [copy, const SizedBox(height: 22), panel],
            ),
    );
  }
}

class _TrustStrip extends StatelessWidget {
  const _TrustStrip();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _TrustItem(
            icon: Icons.verified_user_outlined, label: 'Seller quality checks'),
        _TrustItem(
            icon: Icons.local_shipping_outlined,
            label: 'Tracked international shipping'),
        _TrustItem(
            icon: Icons.currency_bitcoin, label: 'PKN and wPKN payment rails'),
        _TrustItem(icon: Icons.shield_outlined, label: 'Reserve transparency'),
      ],
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
  final VoidCallback onClear;

  const _SearchAndControls({
    required this.controller,
    required this.state,
    required this.quickFilters,
    required this.onSearch,
    required this.onSort,
    required this.onFilter,
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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onSearch,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    prefixIcon:
                        const Icon(Icons.search, color: Color(0xFFFACC15)),
                    hintText: 'Search Charizard, Base Set, holo, artist...',
                    hintStyle: const TextStyle(color: Color(0xFF93A4C8)),
                    filled: true,
                    fillColor: const Color(0xFF111936),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              PopupMenuButton<String>(
                tooltip: 'Sort',
                onSelected: onSort,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'price', child: Text('Sort by price')),
                  PopupMenuItem(value: 'rarity', child: Text('Sort by rarity')),
                  PopupMenuItem(value: 'rating', child: Text('Sort by rating')),
                  PopupMenuItem(value: 'name', child: Text('Sort by name')),
                ],
                child: const _RoundControl(icon: Icons.sort, label: 'Sort'),
              ),
              const SizedBox(width: 12),
              TextButton(onPressed: onClear, child: const Text('Clear')),
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
    return state.selectedRarity == filter.rarity && filter.rarity != null ||
        state.selectedType == filter.type && filter.type != null ||
        filter.inStock && state.showOnlyInStock ||
        filter.maxPrice != null && state.maxPrice == filter.maxPrice;
  }
}

class _FeaturedRow extends StatelessWidget {
  final List<PokemonCard> cards;

  const _FeaturedRow({required this.cards});

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(
            title: 'Featured vault picks',
            subtitle: 'High-signal cards selected for collector demand.'),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final card in cards)
              SizedBox(
                width: 380,
                child: _FeaturedCard(card: card),
              ),
          ],
        ),
      ],
    );
  }
}

class _MarketHeader extends StatelessWidget {
  final int count;

  const _MarketHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: _SectionHeading(
            title: 'Live marketplace',
            subtitle:
                'Singles, holos and graded-ready listings with transparent condition data.',
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0x1AFACC15),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x55FACC15)),
          ),
          child: Text('$count results',
              style: const TextStyle(
                  color: Color(0xFFFDE68A), fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _MarketplaceGrid extends StatelessWidget {
  final List<PokemonCard> cards;

  const _MarketplaceGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const _EmptyMarket();
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
    final cart = ref.watch(cartProvider);
    final isFavorite = favorites.isFavorite(card.id);
    final isInCart = cart.isInCart(card.id);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                    child: Container(
                      color: const Color(0xFF111936),
                      child: CachedNetworkImage(
                        imageUrl: card.imageUrl,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => const Icon(Icons.style,
                            color: Color(0xFFFACC15), size: 54),
                      ),
                    ),
                  ),
                ),
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
                  card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  '${card.set} #${card.number} · ${card.condition}',
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
                        icon: Icons.star, text: card.rating.toStringAsFixed(1)),
                    const _MiniSignal(icon: Icons.block, text: 'Unavailable'),
                    if (card.isHolo)
                      const _MiniSignal(icon: Icons.auto_awesome, text: 'Holo'),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatPkn(card.price),
                        style: const TextStyle(
                            color: Color(0xFFFACC15),
                            fontSize: 22,
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                    FilledButton(
                      onPressed: null,
                      child: Text(isInCart ? 'Unavailable' : 'Unavailable'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  final PokemonCard card;

  const _FeaturedCard({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF111B3F), Color(0xFF0B1020)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CachedNetworkImage(
              imageUrl: card.imageUrl,
              width: 92,
              height: 124,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Badge(text: card.rarity, color: const Color(0xFF38BDF8)),
                const SizedBox(height: 10),
                Text(card.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18)),
                const SizedBox(height: 6),
                Text('${card.condition} · ${card.set}',
                    style: const TextStyle(color: Color(0xFFB8C4E6))),
                const SizedBox(height: 10),
                Text(formatPkn(card.price),
                    style: const TextStyle(
                        color: Color(0xFFFACC15), fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
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
  const _EmptyMarket();

  @override
  Widget build(BuildContext context) {
    return const _Notice(
      title: 'No cards match these filters',
      body:
          'Try clearing filters or searching for a broader set, rarity or Pokémon name.',
    );
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

class _HeroMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HeroMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF93A4C8))),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x990B1024),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFFACC15), size: 18),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFFE5E7EB), fontWeight: FontWeight.w700)),
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
  final String subtitle;

  const _SectionHeading({required this.title, required this.subtitle});

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
        const SizedBox(height: 6),
        Text(subtitle,
            style: const TextStyle(color: Color(0xFF93A4C8), height: 1.4)),
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

class _Pill extends StatelessWidget {
  final String text;

  const _Pill(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x1AFACC15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x55FACC15)),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Color(0xFFFDE68A), fontWeight: FontWeight.w800)),
    );
  }
}

class _MarketFilter {
  final String label;
  final String? rarity;
  final String? type;
  final double? maxPrice;
  final bool inStock;

  const _MarketFilter({
    required this.label,
    this.rarity,
    this.type,
    this.maxPrice,
    this.inStock = false,
  });
}
