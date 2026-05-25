import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/project_links.dart';
import '../widgets/site_footer.dart';

class WhitepaperScreen extends StatelessWidget {
  const WhitepaperScreen({super.key});

  static const _sections = [
    _WhitepaperSection(
      eyebrow: '01',
      title: 'Purpose',
      body:
          'Pokoin exists to connect collectible commerce with transparent wallet and network tools. Card Reserve gives collectors a clearer place to browse Pokemon card inventory, compare seller listings, follow marketplace signals, and use PKN wallet features without separating collecting from settlement infrastructure.',
    ),
    _WhitepaperSection(
      eyebrow: '02',
      title: 'Ecosystem',
      body:
          'The Pokoin ecosystem includes Card Reserve marketplace pages, Pokoin accounts, PKN wallet flows, wPKN liquidity references, Pokoin Scan, marketplace signal analytics, NFT infrastructure, public documentation, and support pages. Each layer is designed to be understandable on its own while contributing to a single collector-oriented product surface.',
    ),
    _WhitepaperSection(
      eyebrow: '03',
      title: 'PKN And PokoinPoS',
      body:
          'PKN is the native unit used by PokoinPoS network tooling and account-linked marketplace flows. PokoinPoS exposes public RPC, health, supply, account, transaction, and block information through Pokoin Scan so users can verify network activity without relying only on app screens.',
    ),
    _WhitepaperSection(
      eyebrow: '04',
      title: 'wPKN Liquidity',
      body:
          'wPKN is the wrapped BNB Chain representation used for external liquidity references. The public reserve manifest, token contract links, and PancakeSwap references are maintained so users can inspect the relationship between native ecosystem accounting and wrapped-market visibility.',
    ),
    _WhitepaperSection(
      eyebrow: '05',
      title: 'Card Reserve Marketplace',
      body:
          'Card Reserve focuses on real catalog imagery, card detail pages, seller listings, watchlists, cart flows, account profiles, and card-specific share previews. The marketplace is built around collector context first: card identity, set, rarity, number, artist data, image quality, and comparable listings.',
    ),
    _WhitepaperSection(
      eyebrow: '06',
      title: 'Marketplace Signals',
      body:
          'Marketplace signal pages turn raw inventory, listing, price, rarity, and demand context into readable signals. The goal is not to promise outcomes, but to help collectors understand supply, attention, liquidity context, and collection-level movement.',
    ),
    _WhitepaperSection(
      eyebrow: '07',
      title: 'Trust And Safety',
      body:
          'Pokoin is designed as a family-safe collector product. It avoids adult content, hate speech, graphic violence, harassment, and misleading financial promises. Wallet and market pages are product information, not investment advice. Support will never ask for seed phrases, private keys, passwords, or full payment card details.',
    ),
    _WhitepaperSection(
      eyebrow: '08',
      title: 'Roadmap',
      body:
          'The near-term roadmap is focused on stronger card pages, better search and preview quality, more complete marketplace analytics, clearer documentation, improved Pokoin Scan visibility, stronger account safety, and consistent publication of useful ecosystem content.',
    ),
  ];

  static Future<void> _openExternal(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: const _WhitepaperTopBar(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.25,
            colors: [Color(0x3338BDF8), Color(0x00050816)],
          ),
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 26, 18, 44),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _WhitepaperHero(),
                  const SizedBox(height: 20),
                  const _WhitepaperStats(),
                  const SizedBox(height: 18),
                  for (final section in _sections) ...[
                    _WhitepaperCard(section: section),
                    const SizedBox(height: 14),
                  ],
                  const _ReferenceCard(onOpenExternal: _openExternal),
                  const SiteFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WhitepaperSection {
  const _WhitepaperSection({
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  final String eyebrow;
  final String title;
  final String body;
}

class _WhitepaperTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _WhitepaperTopBar();

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xF2050816),
      elevation: 0,
      titleSpacing: 18,
      title: Row(
        children: [
          Image.network(
            ProjectLinks.logo,
            width: 34,
            height: 34,
            filterQuality: FilterQuality.none,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.currency_bitcoin,
              color: Color(0xFFFACC15),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Whitepaper',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => context.go('/'),
          child: const Text('Home'),
        ),
        const SizedBox(width: 10),
      ],
    );
  }
}

class _WhitepaperHero extends StatelessWidget {
  const _WhitepaperHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: const Color(0xE60B1020),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 38,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0x1AFACC15),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x55FACC15)),
            ),
            child: const Text(
              'Pokoin Whitepaper v1.0',
              style: TextStyle(
                color: Color(0xFFFDE68A),
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Collector Commerce, PKN Wallets, wPKN Liquidity And Marketplace Signals',
            style: TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.5,
              height: 1.06,
            ),
          ),
          const SizedBox(height: 16),
          const SelectableText(
            'Pokoin is a collector-first ecosystem combining Card Reserve marketplace tools, PKN wallet features, wPKN liquidity references, Pokoin Scan, marketplace signals, and NFT infrastructure.',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 16,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              FilledButton(
                onPressed: () => context.go('/marketplace'),
                child: const Text('Open Card Reserve'),
              ),
              OutlinedButton(
                onPressed: () => context.go('/scan'),
                child: const Text('Open Pokoin Scan'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WhitepaperStats extends StatelessWidget {
  const _WhitepaperStats();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Native Unit', 'PKN'),
      ('Wrapped Market', 'wPKN on BNB Chain'),
      ('Explorer', 'Pokoin Scan'),
      ('Marketplace', 'Card Reserve'),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        for (final item in items)
          Container(
            width: 250,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xCC0B1020),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.$1,
                  style: const TextStyle(
                    color: Color(0xFF93A4C8),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.$2,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WhitepaperCard extends StatelessWidget {
  const _WhitepaperCard({required this.section});

  final _WhitepaperSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1020),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x1AFACC15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x55FACC15)),
            ),
            child: Text(
              section.eyebrow,
              style: const TextStyle(
                color: Color(0xFFFDE68A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  section.body,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    height: 1.62,
                    fontSize: 14.5,
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

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({required this.onOpenExternal});

  final Future<void> Function(String url) onOpenExternal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x3314B8A6), Color(0x26FACC15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Public References',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          const SelectableText(
            'Use the official public links below to inspect network status, reserve information, wrapped token metadata, and marketplace context. Never rely on screenshots alone for wallet or contract verification.',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              height: 1.6,
              fontSize: 14.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              OutlinedButton(
                onPressed: () => onOpenExternal(ProjectLinks.reserve),
                child: const Text('Reserve proof'),
              ),
              OutlinedButton(
                onPressed: () => onOpenExternal(ProjectLinks.bscToken),
                child: const Text('wPKN token'),
              ),
              OutlinedButton(
                onPressed: () => onOpenExternal(ProjectLinks.pancakeSwap),
                child: const Text('PancakeSwap'),
              ),
              OutlinedButton(
                onPressed: () => context.go('/docs'),
                child: const Text('Documentation'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
