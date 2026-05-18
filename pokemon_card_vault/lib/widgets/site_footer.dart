import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/project_links.dart';

class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key});

  static Future<void> _openExternal(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final year = DateTime.now().year;

    return Container(
      margin: const EdgeInsets.only(top: 28),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 28,
        vertical: compact ? 24 : 30,
      ),
      decoration: BoxDecoration(
        color: const Color(0xE60A1026),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 28,
            runSpacing: 24,
            alignment: WrapAlignment.spaceBetween,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: const _FooterBrand(),
              ),
              _FooterColumn(
                title: 'Explore',
                links: [
                  _FooterLink('Home', () => context.go('/')),
                  _FooterLink('Documentation', () => context.go('/docs')),
                  _FooterLink('PokoinScan', () => context.go('/scan')),
                  _FooterLink('Network health', () => context.go('/health')),
                  _FooterLink('Account', () => context.go('/profile')),
                ],
              ),
              _FooterColumn(
                title: 'Network',
                links: [
                  _FooterLink(
                      'RPC endpoint', () => _openExternal(ProjectLinks.rpc)),
                  _FooterLink('Reserve proof',
                      () => _openExternal(ProjectLinks.reserve)),
                  _FooterLink('wPKN contract',
                      () => _openExternal(ProjectLinks.bscContract)),
                  _FooterLink('PancakeSwap',
                      () => _openExternal(ProjectLinks.pancakeSwap)),
                  _FooterLink('CoinMarketCap',
                      () => _openExternal(ProjectLinks.coinMarketCap)),
                ],
              ),
              const _FooterSignal(),
            ],
          ),
          const SizedBox(height: 22),
          const Divider(color: Color(0x1AFFFFFF)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                '© $year Pokoin. Card Reserve, PokoinPoS and wPKN are part of the Pokoin ecosystem.',
                style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
              ),
              const Text(
                'Built for transparent collectible commerce and on-chain settlement.',
                style: TextStyle(
                    color: Color(0xFFFDE68A),
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FooterBrand extends StatelessWidget {
  const _FooterBrand();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF111936),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  ProjectLinks.logo,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.none,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.currency_bitcoin,
                    color: Color(0xFFFACC15),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pokoin',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Permissioned PoS + collector rails',
                    style: TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'A production-oriented ecosystem for native PKN settlement, wrapped liquidity and premium card marketplace infrastructure.',
          style: TextStyle(color: Color(0xFFCBD5E1), height: 1.5),
        ),
      ],
    );
  }
}

class _FooterColumn extends StatelessWidget {
  const _FooterColumn({required this.title, required this.links});

  final String title;
  final List<_FooterLink> links;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          for (final link in links)
            TextButton(
              onPressed: link.onTap,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFB8C4E6),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: Alignment.centerLeft,
              ),
              child: Text(link.label),
            ),
        ],
      ),
    );
  }
}

class _FooterSignal extends StatelessWidget {
  const _FooterSignal();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x3314B8A6), Color(0x26FACC15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x33FACC15)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_outlined, color: Color(0xFFFACC15)),
          SizedBox(height: 12),
          Text(
            'Public by design',
            style: TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 8),
          Text(
            'Explorer data, RPC status, reserve proof and wPKN contract references stay one click away.',
            style: TextStyle(color: Color(0xFFCBD5E1), height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _FooterLink {
  const _FooterLink(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;
}
