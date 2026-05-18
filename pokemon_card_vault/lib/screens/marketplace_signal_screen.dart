import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/card_provider.dart';

class MarketplaceSignalScreen extends ConsumerWidget {
  const MarketplaceSignalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardState = ref.watch(cardProvider);

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
                      : const Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SignalHero(),
                            SizedBox(height: 18),
                            _SignalUnavailablePanel(),
                            SizedBox(height: 18),
                            _SignalNextSteps(),
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
  const _SignalHero();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Pill('Card Reserve analytics'),
        const SizedBox(height: 18),
        Text(
          'Live marketplace signal is not available yet.',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                height: 1.02,
              ),
        ),
        const SizedBox(height: 14),
        const Text(
          'The previous modeled reserve metrics have been removed because they were not based on live listings, fills, or verified order-book depth. This page will only show analytics once the data is real.',
          style: TextStyle(
            color: Color(0xFFB8C4E6),
            fontSize: 16,
            height: 1.55,
          ),
        ),
      ],
    );

    const pulse = _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current status',
            style: TextStyle(
              color: Color(0xFFFDE68A),
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 18),
          _PulseRow(label: 'Live listed cards', value: 'Pending'),
          _PulseRow(label: 'Completed sales', value: 'Pending'),
          _PulseRow(label: '24h volume', value: 'Pending'),
          _PulseRow(label: 'Floor ask', value: 'Pending'),
          SizedBox(height: 14),
          Text(
            'Signals will activate after seller listings and completed purchase events are connected to the analytics pipeline.',
            style: TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
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
                const Expanded(flex: 4, child: pulse),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [copy, const SizedBox(height: 22), pulse],
            ),
    );
  }
}

class _SignalUnavailablePanel extends StatelessWidget {
  const _SignalUnavailablePanel();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analytics offline',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'We are not showing estimated reserve value, fake volume, modeled charts, or synthetic depth. Cards can exist in the catalog even when no seller has listed stock, so catalog presence is not marketplace liquidity.',
            style: TextStyle(color: Color(0xFFB8C4E6), height: 1.55),
          ),
          SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SignalChip(
                icon: Icons.inventory_2_outlined,
                label: 'Unavailable catalog cards show Out of stock',
              ),
              _SignalChip(
                icon: Icons.receipt_long_outlined,
                label: 'Volume requires completed orders',
              ),
              _SignalChip(
                icon: Icons.sell_outlined,
                label: 'Floor requires active seller listings',
              ),
              _SignalChip(
                icon: Icons.query_stats,
                label: 'Charts require live event history',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SignalNextSteps extends StatelessWidget {
  const _SignalNextSteps();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What will make this page live',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SignalChip(
                icon: Icons.price_change_outlined,
                label: 'Active listing floor and spread',
              ),
              _SignalChip(
                icon: Icons.inventory_2_outlined,
                label: 'Real available seller quantity',
              ),
              _SignalChip(
                icon: Icons.local_shipping_outlined,
                label: 'Completed order and settlement events',
              ),
              _SignalChip(
                icon: Icons.show_chart,
                label: 'Rolling 24h marketplace event window',
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            'Until those sources are wired, the marketplace should only say whether a card has real stock. Catalog-only cards are not listed liquidity.',
            style: TextStyle(color: Color(0xFFB8C4E6), height: 1.55),
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
