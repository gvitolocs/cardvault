import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/pokemon_card.dart';
import '../providers/card_provider.dart';
import '../utils/card_url.dart';
import '../utils/price_format.dart';

class NftScreen extends ConsumerWidget {
  const NftScreen({super.key, this.cardId});

  final String? cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardState = ref.watch(cardProvider);
    final selectedCard = _selectedCard(cardState.cards);
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                _NftHeader(
                  card: selectedCard,
                  onBack: () => context.go('/wallet'),
                  onCollection: () => context.go('/collection'),
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 860;
                    final detail = _NftDetailPanel(card: selectedCard);
                    const chart = _NftPricePanel();
                    if (!wide) {
                      return Column(
                        children: [
                          detail,
                          const SizedBox(height: 18),
                          chart,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: detail),
                        const SizedBox(width: 18),
                        const Expanded(child: chart),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PokemonCard? _selectedCard(List<PokemonCard> cards) {
    final id = cardId?.trim();
    if (id == null || id.isEmpty) {
      return cards.isEmpty ? null : cards.first;
    }
    for (final card in cards) {
      if (card.id == id) {
        return card;
      }
    }
    return null;
  }
}

class _NftHeader extends StatelessWidget {
  const _NftHeader({
    required this.card,
    required this.onBack,
    required this.onCollection,
  });

  final PokemonCard? card;
  final VoidCallback onBack;
  final VoidCallback onCollection;

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
              Text(
                card == null ? 'NFT desk' : '${card!.name} NFT',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                'Claim, trade, and price history for tokenized collectibles.',
                style: TextStyle(color: Color(0xFF93A4C8)),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: onCollection,
          icon: const Icon(Icons.collections_bookmark_outlined),
          label: const Text('My collection'),
        ),
      ],
    );
  }
}

class _NftDetailPanel extends StatelessWidget {
  const _NftDetailPanel({required this.card});

  final PokemonCard? card;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 150,
            height: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF111936),
              borderRadius: BorderRadius.circular(18),
            ),
            child: card == null
                ? const Icon(Icons.token_outlined,
                    color: Color(0xFFFACC15), size: 58)
                : Image.network(
                    card!.previewImageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.style,
                      color: Color(0xFFFACC15),
                      size: 48,
                    ),
                  ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card?.name ?? 'Select a collectible',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  card == null
                      ? 'Open this page from My collection to inspect an NFT candidate.'
                      : '${card!.set} #${card!.number}',
                  style: const TextStyle(color: Color(0xFFB8C4E6)),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    const _Metric(label: 'NFT status', value: 'Not minted yet'),
                    _Metric(
                      label: 'Floor',
                      value: card == null ? '—' : formatPkn(card!.price),
                    ),
                    const _Metric(label: 'Chain', value: 'PokoinPoS'),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: card == null
                          ? null
                          : () => context.go(cardDetailPath(card!)),
                      icon: const Icon(Icons.sell_outlined),
                      label: const Text('Sell'),
                    ),
                    OutlinedButton.icon(
                      onPressed: card == null ? null : () {},
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Trade'),
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

class _NftPricePanel extends StatelessWidget {
  const _NftPricePanel();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NFT price chart',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Empty until NFT trades and bids are connected.',
            style: TextStyle(color: Color(0xFF93A4C8)),
          ),
          SizedBox(height: 18),
          SizedBox(height: 240, child: _NftChartPlaceholder()),
        ],
      ),
    );
  }
}

class _NftChartPlaceholder extends StatelessWidget {
  const _NftChartPlaceholder();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _NftChartPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _NftChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final axis = Paint()
      ..color = const Color(0xFFFACC15).withValues(alpha: 0.35)
      ..strokeWidth = 1.4;
    for (var i = 0; i < 5; i++) {
      final y = 12 + i * ((size.height - 24) / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var i = 0; i < 6; i++) {
      final x = i * (size.width / 5);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    canvas.drawLine(Offset(0, size.height - 12),
        Offset(size.width, size.height - 12), axis);
    canvas.drawLine(const Offset(0, 12), Offset(0, size.height - 12), axis);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 11)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xDD0B1020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}
