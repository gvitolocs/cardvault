import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/project_links.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xE60A1026),
            title: const Text('CardVault'),
            actions: [
              _NavAction(label: 'Marketplace', path: '/marketplace'),
              _NavAction(label: 'Scan', path: '/scan'),
              _NavAction(label: 'Health', path: '/health'),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: OutlinedButton(
                  onPressed: () => _open(ProjectLinks.pancakeSwap),
                  child: const Text('Trade wPKN'),
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: _PageShell(
              children: [
                const _HeroSection(),
                const _MetricStrip(),
                const _SectionTitle(
                  eyebrow: 'Marketplace thesis',
                  title:
                      'Instant international liquidity for collectible cards.',
                  body:
                      'CardVault connects Pokémon card buyers and sellers across borders, using PKN and wPKN as crypto rails for fast settlement, transparent reserves, and an open path to DeFi liquidity.',
                ),
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: const [
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
                const _TokenPanel(),
                const _RoadmapSection(),
                const _CtaSection(),
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

  const _NavAction({required this.label, required this.path});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => context.go(path),
      child: Text(label),
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
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 40, offset: Offset(0, 24)),
        ],
      ),
      child: Column(
        children: [
          ClipOval(
            child: Image.network(
              ProjectLinks.logo,
              width: 116,
              height: 116,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 116,
                height: 116,
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
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: const [
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
          border: Border.all(color: Colors.white.withOpacity(0.08)),
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
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            eyebrow: 'Token rails',
            title: 'PKN at the core. wPKN where liquidity lives.',
            body:
                'Native PKN powers the PokoinPoS network. wPKN mirrors the reserve on BNB Chain so collectors and traders can access PancakeSwap liquidity while the backing remains publicly documented.',
          ),
          const SizedBox(height: 22),
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
          const SizedBox(height: 20),
          const SelectableText(
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
    return Wrap(
      spacing: 18,
      runSpacing: 18,
      children: const [
        _FeatureCard(
          icon: Icons.verified,
          title: 'Now live',
          body:
              'wPKN contract verified on BscScan with a published reserve manifest and initial PancakeSwap liquidity.',
        ),
        _FeatureCard(
          icon: Icons.query_stats,
          title: 'Pokoin Scan',
          body:
              'A public scan page at pokoin.com/scan summarizes chain data, wallet setup, RPC details, reserve links, and wPKN references.',
        ),
        _FeatureCard(
          icon: Icons.mail,
          title: 'Profile approvals',
          body:
              'BscScan token profile, token-list metadata, and public contact channels are being prepared for discoverability.',
        ),
        _FeatureCard(
          icon: Icons.storefront,
          title: 'Marketplace expansion',
          body:
              'The CardVault commerce app will connect inventory, seller flows, and crypto settlement into one collector experience.',
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
        border: Border.all(color: Colors.white.withOpacity(0.08)),
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
