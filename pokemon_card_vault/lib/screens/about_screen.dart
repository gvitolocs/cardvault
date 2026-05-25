import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/project_links.dart';
import '../widgets/site_footer.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _sections = [
    _AboutSection(
      title: 'What Pokoin Builds',
      body:
          'Pokoin is a collector-focused ecosystem for Card Reserve marketplace listings, PKN wallet features, wPKN liquidity references, Pokoin Scan, marketplace signals, and NFT infrastructure. The site is built for users who want clearer tools around Pokemon card discovery, pricing context, and account-linked marketplace activity.',
    ),
    _AboutSection(
      title: 'Audience And Editorial Focus',
      body:
          'Our audience is collectors, marketplace users, and blockchain-curious card fans. We focus on practical, original content: card inventory pages, market signal explanations, network documentation, wallet guides, reserve information, and product updates that help users understand how Pokoin services work.',
    ),
    _AboutSection(
      title: 'Safety And Policy Standards',
      body:
          'Pokoin content is designed to be family-safe and suitable for a broad collector audience. We avoid adult material, hate speech, graphic violence, harassment, and misleading financial promises. Marketplace and wallet content is presented as product information, not investment advice.',
    ),
    _AboutSection(
      title: 'Fresh Updates',
      body:
          'The site is updated as marketplace data, Card Reserve features, Pokoin Scan, wallet flows, documentation, and ecosystem pages evolve. We publish new guides, static reference pages, image-rich card pages, and data-backed marketplace views as product coverage grows.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: const _InfoTopBar(title: 'About Us'),
      body: _InfoPageScaffold(
        hero: const _AboutHero(),
        children: [
          for (final section in _sections) ...[
            _InfoCard(title: section.title, body: section.body),
            const SizedBox(height: 14),
          ],
          const _CommitmentCard(),
          const SiteFooter(),
        ],
      ),
    );
  }
}

class _AboutSection {
  const _AboutSection({required this.title, required this.body});

  final String title;
  final String body;
}

class _AboutHero extends StatelessWidget {
  const _AboutHero();

  @override
  Widget build(BuildContext context) {
    return _HeroPanel(
      eyebrow: 'Transparency',
      title: 'About Pokoin',
      body:
          'Pokoin brings together card marketplace tools, PKN wallet features, wPKN liquidity references, Pokoin Scan, marketplace signals, and NFT infrastructure in one collector-oriented ecosystem.',
      actions: [
        _HeroAction(label: 'Read docs', onTap: () => context.go('/docs')),
        _HeroAction(label: 'Contact us', onTap: () => context.go('/contact')),
      ],
    );
  }
}

class _CommitmentCard extends StatelessWidget {
  const _CommitmentCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quality Commitment',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'We aim to keep navigation clear, pages fast on desktop and mobile, SEO metadata accurate, and content useful for real collectors. Pokoin pages combine written guides, card imagery, network data, and marketplace analytics so visitors can learn in more than one format.',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              height: 1.6,
              fontSize: 14.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _InfoTopBar({required this.title});

  final String title;

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
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
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

class _InfoPageScaffold extends StatelessWidget {
  const _InfoPageScaffold({required this.hero, required this.children});

  final Widget hero;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topLeft,
          radius: 1.25,
          colors: [Color(0x2638BDF8), Color(0x00050816)],
        ),
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 26, 18, 44),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                hero,
                const SizedBox(height: 20),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.actions,
  });

  final String eyebrow;
  final String title;
  final String body;
  final List<_HeroAction> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xE60B1020),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 34,
            offset: Offset(0, 18),
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
            child: Text(
              eyebrow,
              style: const TextStyle(
                color: Color(0xFFFDE68A),
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.4,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            body,
            style: const TextStyle(
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
              for (final action in actions)
                FilledButton(
                  onPressed: action.onTap,
                  child: Text(action.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroAction {
  const _HeroAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          SelectableText(
            body,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              height: 1.6,
              fontSize: 14.5,
            ),
          ),
        ],
      ),
    );
  }
}
