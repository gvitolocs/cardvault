import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
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
                _SectionTitle(
                  eyebrow: 'Marketplace thesis',
                  title:
                      'Instant international liquidity for collectible cards.',
                  body:
                      'CardVault connects Pokémon card buyers and sellers across borders, using PKN and wPKN as crypto rails for fast settlement, transparent reserves, and an open path to DeFi liquidity.',
                ),
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: [
                    _FeatureCard(
                      icon: Icons.style,
                      title: 'Global card market',
                      body:
                          'A marketplace for collectors to buy, sell, and exchange cards without waiting on slow cross-border payment rails.',
                    ),
                    _FeatureCard(
                      icon: Icons.currency_bitcoin,
                      title: 'PKN-native payments',
                      body:
                          'PokoinPoS powers native PKN transfers with EVM-style wallet compatibility and a public RPC endpoint.',
                    ),
                    _FeatureCard(
                      icon: Icons.hub,
                      title: 'wPKN on BNB Chain',
                      body:
                          'wPKN brings PKN into the BNB ecosystem with a verified BEP-20 contract and PancakeSwap liquidity.',
                    ),
                  ],
                ),
                _TokenPanel(),
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

  static Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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
      decoration: BoxDecoration(
        color: const Color(0xF2050816),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10)),
        ],
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
                      label: 'Buy PKN',
                      icon: Icons.add_card_outlined,
                      primary: false,
                      onPressed: () => context.go('/wallet'),
                    ),
                    const SizedBox(width: 10),
                    _TopBarCta(
                      label: 'Trade wPKN',
                      icon: Icons.swap_horiz,
                      primary: true,
                      onPressed: () => LandingScreen._open(ProjectLinks.pancakeSwap),
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
        const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pokoin',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'CardVault crypto rails',
              style: TextStyle(
                color: Color(0xFF93A4C8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
          _NavAction(label: 'Marketplace', path: '/marketplace', icon: Icons.storefront),
          _NavAction(label: 'Wallet', path: '/wallet', icon: Icons.account_balance_wallet_outlined),
          _NavAction(label: 'Scan', path: '/scan', icon: Icons.query_stats),
          _NavAction(label: 'Health', path: '/health', icon: Icons.health_and_safety_outlined),
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
        backgroundColor: primary ? const Color(0xFFFACC15) : const Color(0xFF111936),
        foregroundColor: primary ? const Color(0xFF111827) : const Color(0xFFE2E8F0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: primary ? Colors.transparent : Colors.white.withValues(alpha: 0.10),
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
          'CardVault is building the crypto marketplace for Pokémon card collectors.',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 0.95,
              ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Buy, sell, and exchange cards instantly across borders using native PKN and wrapped wPKN on BNB Chain. Built for collectors who want speed, transparency, and open-market liquidity.',
          style: TextStyle(color: Color(0xFFB8C4E6), fontSize: 18, height: 1.6),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: () => LandingScreen._open(ProjectLinks.pancakeSwap),
              child: const Text('Trade wPKN'),
            ),
            OutlinedButton(
              onPressed: () => context.go('/health'),
              child: const Text('View network health'),
            ),
            OutlinedButton(
              onPressed: () => context.go('/scan'),
              child: const Text('Open Pokoin Scan'),
            ),
            TextButton(
              onPressed: () => context.go('/marketplace'),
              child: const Text('Open marketplace preview'),
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
            'wPKN',
            style: TextStyle(
                color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Verified BEP-20 on BNB Chain',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFB8C4E6)),
          ),
          const SizedBox(height: 24),
          const _InfoRow(label: 'Supply', value: '2,000,000'),
          const _InfoRow(label: 'Backing', value: '1:1 native PKN reserve'),
          const _InfoRow(label: 'Pool', value: 'wPKN / BNB'),
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
        _Metric(label: 'Native chain', value: 'PokoinPoS'),
        _Metric(label: 'Chain ID', value: '26062026'),
        _Metric(label: 'wPKN chain', value: 'BNB Chain'),
        _Metric(label: 'Reserve', value: '2M PKN'),
      ],
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

class _TokenPanel extends StatelessWidget {
  const _TokenPanel();

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
            eyebrow: 'Token rails',
            title: 'PKN at the core. wPKN where liquidity lives.',
            body:
                'Native PKN powers the PokoinPoS network. wPKN mirrors the reserve on BNB Chain so collectors and traders can access PancakeSwap liquidity while the backing remains publicly documented.',
          ),
          SizedBox(height: 22),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _LinkButton(label: 'BscScan token', url: ProjectLinks.bscToken),
              _LinkButton(
                  label: 'Verified contract', url: ProjectLinks.bscContract),
              _LinkButton(label: 'Reserve proof', url: ProjectLinks.reserve),
              _LinkButton(
                  label: 'PancakeSwap pool', url: ProjectLinks.pancakePair),
            ],
          ),
          SizedBox(height: 20),
          SelectableText(
            'wPKN contract: ${ProjectLinks.wpknContract}',
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
          icon: Icons.swap_horiz,
          title: 'wPKN trades live',
          body:
              'Collectors and crypto users access wPKN on BNB Chain with a verified contract, reserve proof, and PancakeSwap liquidity.',
        ),
        _FeatureCard(
          icon: Icons.query_stats,
          title: 'Live chain transparency',
          body:
              'PokoinScan shows blocks, transactions, validators, RPC status, reserve links, and wallet setup in one public dashboard.',
        ),
        _FeatureCard(
          icon: Icons.style,
          title: 'Collector commerce',
          body:
              'CardVault connects premium card discovery with Pokoin profiles, PKN balances, wallet linking, and crypto settlement rails.',
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
              'Ready to explore the live rails? Check network health, inspect the token, or trade wPKN on PancakeSwap.',
              style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 22,
                  fontWeight: FontWeight.w800),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF111827)),
            onPressed: () => context.go('/health'),
            child: const Text('Open health page'),
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

class _LinkButton extends StatelessWidget {
  final String label;
  final String url;

  const _LinkButton({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => LandingScreen._open(url),
      icon: const Icon(Icons.open_in_new, size: 18),
      label: Text(label),
    );
  }
}
