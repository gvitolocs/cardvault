import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/project_links.dart';
import '../widgets/site_footer.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF050816),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            toolbarHeight: 76,
            backgroundColor: Color(0xF2050816),
            elevation: 0,
            flexibleSpace: _TopBar(),
          ),
          SliverToBoxAdapter(
            child: _PageShell(
              children: [
                _HeroSection(),
                _MetricStrip(),
                _ProjectAccessSection(),
                _SectionTitle(
                  eyebrow: 'Pokoin today',
                  title:
                      'A collector marketplace with wallet rails and network roles.',
                  body:
                      'Pokoin combines card discovery, seller listings, PKN balances, node operations and community coordination in one project surface. The homepage should get every role to the right place quickly.',
                ),
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: [
                    _FeatureCard(
                      icon: Icons.style,
                      title: 'Live card marketplace',
                      body:
                          'Browse Pokémon card inventory with real card images, card detail pages, seller offers, no-seller states, and listing-aware cart flows.',
                    ),
                    _FeatureCard(
                      icon: Icons.storefront_outlined,
                      title: 'Seller listings',
                      body:
                          'Logged-in users can create listings with condition, language, reverse holo, grading company, grade, certification ID, shipping and NFT options.',
                    ),
                    _FeatureCard(
                      icon: Icons.query_stats,
                      title: 'Marketplace signal',
                      body:
                          'Reserve analytics track listed value, floor and median ask, price depth, rarity concentration, reserve coverage and readiness signals.',
                    ),
                  ],
                ),
                _MarketplacePanel(),
                _RoadmapSection(),
                _CtaSection(),
                SiteFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavAction extends StatelessWidget {
  final String label;
  final String path;
  final IconData icon;

  const _NavAction({
    required this.label,
    required this.path,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => context.go(path),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFE2E8F0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: const Color(0xFFFACC15)),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 820;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF2050816),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SizedBox(
                height: 68,
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => context.go('/'),
                      borderRadius: BorderRadius.circular(20),
                      child: const _BrandMark(),
                    ),
                    const Spacer(),
                    if (!compact) ...[
                      const _NavPill(),
                      const SizedBox(width: 12),
                    ],
                    _TopBarCta(
                      label: 'Shop',
                      icon: Icons.storefront,
                      primary: true,
                      onPressed: () => context.go('/marketplace'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF111936),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.network(
              ProjectLinks.logo,
              filterQuality: FilterQuality.none,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'Pokoin',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1020),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NavAction(
              label: 'Wallet',
              path: '/wallet',
              icon: Icons.account_balance_wallet_outlined),
          _NavAction(
              label: 'Host node', path: '/docs', icon: Icons.terminal_outlined),
          _NavAction(
              label: 'Forum', path: '/forum', icon: Icons.forum_outlined),
        ],
      ),
    );
  }
}

class _TopBarCta extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onPressed;

  const _TopBarCta({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor:
            primary ? const Color(0xFFFACC15) : const Color(0xFF111936),
        foregroundColor:
            primary ? const Color(0xFF111827) : const Color(0xFFE2E8F0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: primary
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
      ),
    );
  }
}

class _PageShell extends StatelessWidget {
  final List<Widget> children;

  const _PageShell({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.2,
          colors: [Color(0x2238BDF8), Color(0x00050816)],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in children) ...[
                  child,
                  const SizedBox(height: 36),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 840;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Card collecting, marketplace liquidity and PKN network access.',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 0.95,
              ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Pokoin is building a permissioned PoS ecosystem around collectible cards: shop inventory, use wallet-linked accounts, follow reserve signals, host infrastructure and coordinate in the community forum.',
          style: TextStyle(color: Color(0xFFB8C4E6), fontSize: 18, height: 1.6),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: () => context.go('/marketplace'),
              child: const Text('Shop cards'),
            ),
            OutlinedButton(
              onPressed: () => context.go('/docs'),
              child: const Text('Join the network'),
            ),
            OutlinedButton(
              onPressed: () => context.go('/wallet'),
              child: const Text('Wallet roles'),
            ),
            TextButton(
              onPressed: () => context.go('/forum'),
              child: const Text('Open forum'),
            ),
          ],
        ),
      ],
    );

    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 6, child: copy),
              const SizedBox(width: 34),
              const Expanded(flex: 4, child: _HeroTokenCard()),
            ],
          )
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            copy,
            const SizedBox(height: 28),
            const _HeroTokenCard(),
          ]);
  }
}

class _HeroTokenCard extends StatelessWidget {
  const _HeroTokenCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 40, offset: Offset(0, 24)),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: 150,
            height: 150,
            child: Center(
              child: Image.network(
                ProjectLinks.logoLarge,
                width: 132,
                height: 132,
                filterQuality: FilterQuality.none,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 132,
                  height: 132,
                  color: const Color(0xFFFACC15),
                  alignment: Alignment.center,
                  child: const Text(
                    'PKN',
                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Card Reserve',
            style: TextStyle(
                color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Shop cards and settle with PKN',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFB8C4E6)),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.go('/marketplace'),
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Shop the marketplace'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFACC15),
                foregroundColor: const Color(0xFF111827),
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _InfoRow(label: 'Discover', value: 'Real card images'),
          const _InfoRow(label: 'Trade', value: 'Seller offers'),
          const _InfoRow(label: 'Settle', value: 'PKN wallet rails'),
        ],
      ),
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _Metric(label: 'Shop', value: 'Marketplace'),
        _Metric(label: 'Wallet', value: 'PKN roles'),
        _Metric(label: 'Network', value: 'Host nodes'),
        _Metric(label: 'Community', value: 'Forum'),
      ],
    );
  }
}

class _ProjectAccessSection extends StatelessWidget {
  const _ProjectAccessSection();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 18,
      runSpacing: 18,
      children: [
        _AccessCard(
          icon: Icons.storefront_outlined,
          title: 'Card Reserve Market',
          body:
              'Browse cards, sealed products, seller offers, cart flows and collectible inventory.',
          path: '/marketplace',
          action: 'Enter market',
        ),
        _AccessCard(
          icon: Icons.account_balance_wallet_outlined,
          title: 'PKN Utility',
          body:
              'Use PKN balances for marketplace settlement, account identity, withdrawals and buyer or seller activity.',
          path: '/wallet',
          action: 'Use wallet',
        ),
        _AccessCard(
          icon: Icons.terminal_outlined,
          title: 'Node Operators',
          body:
              'Run a peer, understand validator operations, read setup docs and help secure the permissioned PoS layer.',
          path: '/docs',
          action: 'Host node',
        ),
        _AccessCard(
          icon: Icons.forum_outlined,
          title: 'Community Forum',
          body:
              'Coordinate marketplace ideas, wallet support, validator operations and community proposals.',
          path: '/forum',
          action: 'Discuss',
        ),
      ],
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.path,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final String path;
  final String action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 270,
      child: InkWell(
        onTap: () => context.go(path),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          constraints: const BoxConstraints(minHeight: 250),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xCC0B1024),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0x1AFACC15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x44FACC15)),
                ),
                child: Icon(icon, color: const Color(0xFFFACC15)),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  body,
                  style:
                      const TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    action,
                    style: const TextStyle(
                      color: Color(0xFFFACC15),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward,
                    color: Color(0xFFFACC15),
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String body;

  const _SectionTitle(
      {required this.eyebrow, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Pill(eyebrow),
        const SizedBox(height: 14),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 12),
        Text(body,
            style: const TextStyle(
                color: Color(0xFFB8C4E6), fontSize: 16, height: 1.55)),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _FeatureCard(
      {required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xB30B1024),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFFACC15), size: 30),
            const SizedBox(height: 18),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18)),
            const SizedBox(height: 10),
            Text(body,
                style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.5)),
          ],
        ),
      ),
    );
  }
}

class _MarketplacePanel extends StatelessWidget {
  const _MarketplacePanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF111B3F), Color(0xFF0B1020)]),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            eyebrow: 'Marketplace stack',
            title:
                'Catalog data, seller offers and reserve analytics in one flow.',
            body:
                'Pokoin uses Supabase for the card catalog, Firebase for user listings, carts and orders, and PKN wallet rails for settlement. The marketplace signal page turns reserve data into useful trading-style analytics without cluttering the shopping home.',
          ),
          SizedBox(height: 22),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _RouteButton(label: 'Open marketplace', path: '/marketplace'),
              _RouteButton(
                  label: 'Marketplace signal', path: '/marketplace/signal'),
              _RouteButton(label: 'Wallet', path: '/wallet'),
              _RouteButton(label: 'Pokoin Scan', path: '/scan'),
            ],
          ),
          SizedBox(height: 20),
          SelectableText(
            'Current focus: Card Reserve marketplace UX, seller view, cart, watchlist, order flow and reserve analytics.',
            style: TextStyle(color: Color(0xFFCBD5E1), fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

class _RoadmapSection extends StatelessWidget {
  const _RoadmapSection();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 18,
      runSpacing: 18,
      children: [
        _FeatureCard(
          icon: Icons.shopping_bag_outlined,
          title: 'Cart and checkout',
          body:
              'Cart items keep the selected seller listing, condition, language, reverse holo, grading and certification data through checkout.',
        ),
        _FeatureCard(
          icon: Icons.query_stats,
          title: 'Signal dashboard',
          body:
              'A dedicated marketplace signal page shows listed value, depth, floor and median asks, rarity concentration and readiness metrics.',
        ),
        _FeatureCard(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Wallet-linked accounts',
          body:
              'Pokoin profiles connect Firebase auth, wallet linking, balances, orders, watchlists and marketplace actions.',
        ),
      ],
    );
  }
}

class _CtaSection extends StatelessWidget {
  const _CtaSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD33D),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 18,
        runSpacing: 18,
        children: [
          const SizedBox(
            width: 620,
            child: Text(
              'Ready to use the current Pokoin product? Start with the marketplace, then open the signal dashboard for reserve analytics.',
              style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 22,
                  fontWeight: FontWeight.w800),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF111827)),
            onPressed: () => context.go('/marketplace'),
            child: const Text('Open marketplace'),
          ),
        ],
      ),
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
              color: Color(0xFFFDE68A), fontWeight: FontWeight.w700)),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0x990B1024),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF93A4C8))),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF93A4C8))),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteButton extends StatelessWidget {
  final String label;
  final String path;

  const _RouteButton({required this.label, required this.path});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => context.go(path),
      icon: const Icon(Icons.arrow_forward, size: 18),
      label: Text(label),
    );
  }
}
