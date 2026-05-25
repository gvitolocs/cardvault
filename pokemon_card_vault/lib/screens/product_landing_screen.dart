import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/pokemon_card.dart';
import '../providers/card_provider.dart';
import '../providers/recent_views_provider.dart';
import '../services/card_service.dart';
import '../utils/card_navigation.dart';

class ProductLandingScreen extends ConsumerWidget {
  const ProductLandingScreen({super.key, required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = _ProductLandingConfig.forKind(kind);
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: FutureBuilder<List<PokemonCard>>(
          future: config.loadCards(),
          builder: (context, snapshot) {
            final cards = snapshot.data ?? const <PokemonCard>[];
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: _ProductHero(config: config),
                      ),
                    ),
                  ),
                ),
                if (snapshot.connectionState != ConnectionState.done)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1240),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
                          child: cards.isEmpty
                              ? _EmptyProductState(config: config)
                              : _ProductGrid(cards: cards),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProductLandingConfig {
  const _ProductLandingConfig({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.ctaLabel,
    required this.ctaPath,
    required this.loadCards,
  });

  final String title;
  final String subtitle;
  final String description;
  final String ctaLabel;
  final String ctaPath;
  final Future<List<PokemonCard>> Function() loadCards;

  static _ProductLandingConfig forKind(String kind) {
    final service = CardService();
    switch (kind) {
      case 'box':
        return _ProductLandingConfig(
          title: 'Booster boxes',
          subtitle: 'Sealed box opportunities',
          description:
              'Browse sealed booster boxes backed by the marketplace catalog.',
          ctaLabel: 'View all boxes',
          ctaPath: '/marketplace/search?productType=booster_box',
          loadCards: () => service.getMarketplaceCardsByProductType(
            'booster_box',
            limit: 80,
          ),
        );
      case 'pack':
        return _ProductLandingConfig(
          title: 'Booster packs',
          subtitle: 'Single-pack product picks',
          description:
              'Find individual boosters and pack products across supported sets.',
          ctaLabel: 'View all packs',
          ctaPath: '/marketplace/search?productType=booster_pack',
          loadCards: () => service.getMarketplaceCardsByProductType(
            'booster_pack',
            limit: 80,
          ),
        );
      case 'graded':
        return _ProductLandingConfig(
          title: 'Graded candidates',
          subtitle: 'Cards worth inspecting',
          description:
              'High-signal singles that collectors often consider for grading.',
          ctaLabel: 'Search candidates',
          ctaPath:
              '/marketplace/search?q=special%20illustration%20rare&productType=card',
          loadCards: () => service.searchMarketplaceCards(
            'special illustration rare',
            limit: 80,
            productType: 'card',
          ),
        );
      case 'nft':
        return _ProductLandingConfig(
          title: 'NFT mark',
          subtitle: 'Cards ready for digital claim workflows',
          description:
              'Explore collectible singles suited for Pokoin NFT reserve marking.',
          ctaLabel: 'Open NFT desk',
          ctaPath: '/nft',
          loadCards: () => service.searchMarketplaceCards(
            'illustration rare',
            limit: 80,
            productType: 'card',
          ),
        );
      default:
        return _ProductLandingConfig(
          title: 'Products',
          subtitle: 'Marketplace categories',
          description:
              'Browse curated product categories in the Pokoin market.',
          ctaLabel: 'Back to market',
          ctaPath: '/marketplace',
          loadCards: () async => const <PokemonCard>[],
        );
    }
  }
}

class _ProductHero extends StatelessWidget {
  const _ProductHero({required this.config});

  final _ProductLandingConfig config;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xDD0B1024),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            config.subtitle,
            style: const TextStyle(
              color: Color(0xFFFACC15),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            config.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            config.description,
            style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton(
                onPressed: () => context.go(config.ctaPath),
                child: Text(config.ctaLabel),
              ),
              OutlinedButton(
                onPressed: () => context.go('/marketplace'),
                child: const Text('Marketplace'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductGrid extends ConsumerWidget {
  const _ProductGrid({required this.cards});

  final List<PokemonCard> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1120
            ? 4
            : width >= 820
                ? 3
                : width >= 540
                    ? 2
                    : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 340,
          ),
          itemBuilder: (context, index) {
            final card = cards[index];
            return _ProductCard(
              card: card,
              onTap: () {
                ref.read(cardProvider.notifier).recordCardInteraction(
                      card,
                      'click',
                      source: 'product_landing',
                    );
                ref.read(recentViewsProvider.notifier).remember(card);
                navigateToCanonicalCardDetail(
                  context,
                  card,
                  source: 'product_landing',
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.card, required this.onTap});

  final PokemonCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = card.previewImageUrl.trim().isNotEmpty
        ? card.previewImageUrl
        : card.imageUrl;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1024),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: imageUrl.trim().isEmpty
                    ? const Icon(
                        Icons.style,
                        color: Color(0xFFFACC15),
                        size: 54,
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.style,
                          color: Color(0xFFFACC15),
                          size: 54,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              card.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (card.set.trim().isNotEmpty) card.set,
                if (card.number.trim().isNotEmpty) card.number,
              ].join(' '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFB8C4E6),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProductState extends StatelessWidget {
  const _EmptyProductState({required this.config});

  final _ProductLandingConfig config;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1024),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          const Icon(Icons.inventory_2_outlined,
              color: Color(0xFFFACC15), size: 46),
          const SizedBox(height: 12),
          Text(
            'No ${config.title.toLowerCase()} found yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try the broader marketplace search while the product index warms up.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF93A4C8)),
          ),
        ],
      ),
    );
  }
}
