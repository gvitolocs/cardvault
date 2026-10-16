import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/pokemon_card.dart';
import '../providers/card_provider.dart';
import '../providers/favorites_provider.dart';
import '../utils/card_navigation.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesState = ref.watch(favoritesProvider);
    final cardState = ref.watch(cardProvider);
    final favoriteCards = cardState.cards
        .where((card) => favoritesState.isFavorite(card.id))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WatchlistHeader(
                    count: favoriteCards.length,
                    onBack: () => context.go('/profile'),
                    onClear: favoriteCards.isEmpty
                        ? null
                        : () => _showClearDialog(context, ref),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: favoritesState.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : favoriteCards.isEmpty
                            ? _EmptyWatchlist(
                                onBrowse: () => context.go('/marketplace'),
                              )
                            : GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 280,
                                  mainAxisExtent: 430,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                ),
                                itemCount: favoriteCards.length,
                                itemBuilder: (context, index) => _WatchlistCard(
                                  card: favoriteCards[index],
                                ),
                              ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showClearDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0B1020),
        title: const Text(
          'Clear watchlist?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This removes every saved card from your marketplace watchlist.',
          style: TextStyle(color: Color(0xFFB8C4E6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(favoritesProvider.notifier).clearFavorites();
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _WatchlistHeader extends StatelessWidget {
  const _WatchlistHeader({
    required this.count,
    required this.onBack,
    required this.onClear,
  });

  final int count;
  final VoidCallback onBack;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Watchlist',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '$count saved cards and products. Edit directly from here.',
                style: const TextStyle(color: Color(0xFF93A4C8)),
              ),
            ],
          ),
        ),
        if (onClear != null)
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.clear_all),
            label: const Text('Clear all'),
          ),
      ],
    );
  }
}

class _WatchlistCard extends ConsumerWidget {
  const _WatchlistCard({required this.card});

  final PokemonCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => navigateToCanonicalCardDetail(
        context,
        card,
        source: 'favorites_card',
      ),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xDD0B1020),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: Image.network(
                  card.previewImageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.style,
                    color: Color(0xFFFACC15),
                    size: 48,
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
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              card.itemKind == 'product'
                  ? (card.number.trim().isEmpty
                      ? card.set
                      : '${card.set} · ${card.number}')
                  : (card.number.trim().isEmpty
                      ? card.set
                      : '${card.set} ${card.number}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
            ),
            const SizedBox(height: 12),
            const _WatchlistPriceDiagram(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ref
                        .read(favoritesProvider.notifier)
                        .toggleFavorite(card.id),
                    icon: const Icon(Icons.favorite),
                    label: const Text('Remove'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => navigateToCanonicalCardDetail(
                    context,
                    card,
                    source: 'favorites_open_button',
                  ),
                  icon: const Icon(Icons.open_in_new),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WatchlistPriceDiagram extends StatelessWidget {
  const _WatchlistPriceDiagram();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      width: double.infinity,
      child: CustomPaint(
        painter: _WatchlistPriceDiagramPainter(),
      ),
    );
  }
}

class _WatchlistPriceDiagramPainter extends CustomPainter {
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

class _EmptyWatchlist extends StatelessWidget {
  const _EmptyWatchlist({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xDD0B1020),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite_border,
                color: Color(0xFFFACC15), size: 48),
            const SizedBox(height: 12),
            const Text(
              'No watchlist items yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Save cards and products from the marketplace to track them here.',
              style: TextStyle(color: Color(0xFF93A4C8)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onBrowse,
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Browse marketplace'),
            ),
          ],
        ),
      ),
    );
  }
}
